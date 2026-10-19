// `Contraption` (pure): a structure of blocks that moves as one. The block capture, the structure
// search (`searchMovedStructure` / `moveBlock`), the actors and seats, the mounted storage, the
// NBT form and the placement back into the world. The entity that carries a contraption lives in
// `entity/` and drives the actors; this class only holds the structure.
//
// The host is reached through [ContraptionLevel]; every world write is a hook of that interface,
// so the whole class runs on the Dart VM in tests.
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../core/nbt.dart' show NbtKind, NbtValue;
import '../../core/perf.dart';
import '../storage/storage_manager.dart';
import '../storage/stacks.dart';
import 'collision.dart';
import 'contraption_type.dart';
import 'level.dart';
import 'movement.dart';
import 'movement_checks.dart';
import 'nbt_map.dart';
import 'structure_info.dart';
import 'structure_transform.dart';

/// The entity that carries a contraption, as the structure sees it. Implemented by
/// `AbstractContraptionEntity`; kept here so the core does not depend on the entity layer.
abstract interface class ContraptionEntityHandle {
  /// `entity.getId()`.
  int get entityId;

  /// `entity.getUUID().toString()`.
  String get uuid;

  /// `entity.isAlive()`.
  bool get isAlive;

  /// `entity.getBoundingBox()`.
  Aabb get boundingBox;

  /// `entity.position()`.
  Vec3 get position;

  /// `entity.getPassengers()`.
  List<Object> get passengers;

  /// `addSittingPassenger(passenger, seatIndex)`.
  void addSittingPassenger(Object passenger, int seatIndex);

  /// `contraption.setBlock(localPos, info)`: replaces a block and tells the clients.
  void setBlock(Pos localPos, StructureBlockInfo info);

  /// `MountedStorageSyncPacket` to the clients tracking the entity.
  void sendStorageSync(StorageSync sync);

  /// Sends a clientbound payload (`create:contraption_actor_toggle`) to the clients tracking the
  /// entity.
  void sendPayload(String channel, Map<String, Object?> fields);

  /// `onContraptionStalled()`.
  void onContraptionStalled();
}

/// A captured block: its state and saved data, plus the block entity it came from.
final class CapturedBlock {
  final StructureBlockInfo info;

  /// The block entity as the world holds it, `null` for a block without one.
  final CapturedBlockEntity? blockEntity;

  const CapturedBlock(this.info, this.blockEntity);
}

/// The block entity types whose data is a multiblock (`IMultiBlockEntityContainer`). The
/// multiblock modules add their types in `onLoad`; the fallback recognises the vanilla-like
/// markers in the saved data.
abstract final class MultiBlockContainers {
  static final Set<String> _types = {
    'create:fluid_tank',
    'create:creative_fluid_tank',
    'create:item_vault',
  };

  static void register(String typeKey) => _types.add(typeKey);

  static bool isContainer(String typeKey) => _types.contains(typeKey);
}

/// Hooks the actuator modules install for block kinds the core cannot know about. Everything
/// optional; the fallbacks are the vanilla/Create rules that live in this file.
abstract final class ContraptionMovementHooks {
  /// `ChassisBlockEntity.addAttachedChasses(frontier, visited)`.
  static void Function(
    ContraptionLevel level,
    Pos pos,
    Queue<Pos> frontier,
    Set<Pos> visited,
  )?
  addAttachedChasses;

  /// `ChassisBlockEntity.getIncludedBlockPositions(direction, false)`, `null` when the block
  /// entity at [pos] is not a chassis.
  static List<Pos>? Function(
    ContraptionLevel level,
    Pos pos,
    Direction? direction,
  )?
  chassisIncludedPositions;

  /// `BeltBlock.nextSegmentPosition(state, pos, forward)`.
  static Pos? Function(BState state, Pos pos, bool forward)? beltNextSegment;
}

/// The limits of a contraption that are not in [ContraptionSettings].
const int _intMin = -0x80000000;

/// `Contraption`.
class Contraption {
  /// `simplifiedEntityColliders`: the collision boxes of the carried blocks, rebuilt on demand.
  final CollisionList simplifiedEntityColliders = CollisionList();

  /// The entity carrying this contraption, `null` while it is only a structure.
  ContraptionEntityHandle? entity;

  /// The bounds of the contraption in local coordinates.
  Aabb? bounds;
  Pos anchor = posZero;
  bool stalled = false;
  bool hasUniversalCreativeCrate = false;
  bool disassembled = false;

  /// The captured blocks by local position.
  final Map<Pos, StructureBlockInfo> blocks = {};

  /// `getUpdateTag` of each block entity, by local position.
  final Map<Pos, NbtMap> updateTags = {};

  /// Whether the saved data of a block came from a pre-updateTag contraption.
  final Map<Pos, bool> isLegacy = {};

  /// The actors of the contraption, in capture order.
  final List<MovementContext> actors = [];

  /// The interaction behaviour of each block that has one.
  final Map<Pos, MovingInteractionBehaviour> interactors = {};

  /// The actors disabled by contraption controls.
  List<StoredStack> disabledActors = [];

  /// The boxes of the super glue that held the structure together.
  List<Aabb> superglue = [];

  /// The local positions of the seats, in seat index order.
  final List<Pos> seats = [];

  /// Passenger uuid -> seat index.
  Map<String, int> seatMapping = {};

  /// Oriented sub-contraption entity uuid -> its bearing position and face.
  final Map<String, BlockFace> stabilizedSubContraptions = {};

  /// The mounted storages of the carried blocks.
  MountedStorageManager storage = MountedStorageManager();

  /// Controller local position -> the parts of a captured multiblock.
  final Map<Pos, List<StructureBlockInfo>> capturedMultiblocks = {};

  final Set<GlueRef> _glueToRemove = {};

  /// Seat local position -> the passenger that sat there before assembly.
  final Map<Pos, Object> _initialPassengers = {};

  /// Bearings that create a stabilized sub-contraption when the entity is created.
  final List<BlockFace> pendingSubContraptions = [];

  /// The storage that was taken out of the contraption by the train code (`takeStorage`), kept
  /// so [returnStorageForDisassembly] can put it back.
  Object? _externalStorage;

  /// The limits of the config the contraption was assembled with (see [ContraptionLevel.settings]).
  ContraptionSettings? settings;

  /// `ContraptionType`: the registered kind. Override in a subclass (or register a factory).
  String get typeId => ContraptionTypes.genericId;

  // -- Assembly -------------------------------------------------------------------------------

  /// `assemble(world, pos)`: captures the structure at [pos]. Subclasses add the checks of their
  /// kind after [searchMovedStructure].
  Future<bool> assemble(ContraptionLevel level, Pos pos) async {
    disassembled = false;
    final watch = Perf.enabled ? (Stopwatch()..start()) : null;
    try {
      return searchMovedStructure(level, pos, null);
    } finally {
      if (watch != null) {
        Perf.record(
          'assemble.${typeId}(blocks=${blocks.length})',
          watch.elapsedMicroseconds,
        );
      }
    }
  }

  /// `canBeStabilized(facing, localPos)`: whether a bearing at [localPos] facing [facing] creates
  /// a sub-contraption instead of dragging its neighbour. False in the base class; the bearing
  /// kinds override it.
  bool canBeStabilized(Direction facing, Pos localPos) => false;

  /// `customBlockPlacement`: a hook for blocks that place themselves differently.
  bool customBlockPlacement(ContraptionLevel level, Pos pos, BState state) =>
      false;

  /// `customBlockRemoval`: a hook for blocks that are removed differently.
  bool customBlockRemoval(ContraptionLevel level, Pos pos, BState state) =>
      false;

  /// `addToInitialFrontier`: adds the first positions of the structure search.
  bool addToInitialFrontier(
    ContraptionLevel level,
    Pos pos,
    Direction? forcedDirection,
    Queue<Pos> frontier,
  ) => true;

  /// `searchMovedStructure`.
  bool searchMovedStructure(
    ContraptionLevel level,
    Pos pos,
    Direction? forcedDirection,
  ) {
    _initialPassengers.clear();
    final frontier = ListQueue<Pos>();
    final visited = <Pos>{};
    anchor = pos;
    levelForColliders = level;
    settings = level.settings;
    bounds ??= Aabb.ofBlock(posZero);

    if (!BlockMovementChecks.isBrittle(level.stateAt(pos), level))
      frontier.add(pos);
    if (!addToInitialFrontier(level, pos, forcedDirection, frontier))
      return false;
    for (var limit = 100000; limit > 0; limit--) {
      if (frontier.isEmpty) return true;
      if (!Perf.enabled) {
        if (!moveBlock(level, forcedDirection, frontier, visited)) return false;
        continue;
      }
      final watch = Stopwatch()..start();
      final moved = moveBlock(level, forcedDirection, frontier, visited);
      Perf.record('assemble.moveBlock', watch.elapsedMicroseconds);
      if (!moved) return false;
    }
    throw AssemblyException.structureTooLarge(level.settings.maxBlocksMoved);
  }

  /// `moveBlock`: captures the first block of [frontier] and adds the blocks it drags along.
  bool moveBlock(
    ContraptionLevel level,
    Direction? forcedDirection,
    Queue<Pos> frontier,
    Set<Pos> visited,
  ) {
    final pos = frontier.isEmpty ? null : frontier.removeFirst();
    if (pos == null) return false;
    visited.add(pos);

    if (level.isOutsideBuildHeight(pos)) return true;
    if (!level.isLoaded(pos)) throw AssemblyException.unloadedChunk(pos);
    if (isAnchoringBlockAt(pos)) return true;

    final state = level.stateAt(pos);
    if (!BlockMovementChecks.isMovementNecessary(state, level, pos))
      return true;
    if (!movementAllowed(state, level, pos))
      throw AssemblyException.unmovableBlock(pos, state);

    if (isChassisState(state) &&
        !_moveChassis(level, pos, forcedDirection, frontier, visited))
      return false;

    if (_isBelt(state)) _moveBelt(pos, frontier, visited, state);

    if (state.key == 'create:windmill_bearing')
      level.disassembleWindmillBearing(pos);

    if (state.key == 'create:gantry_carriage')
      _moveGantryPinion(level, pos, frontier, visited, state);
    if (state.key == 'create:gantry_shaft')
      _moveGantryShaft(level, pos, frontier, visited, state);

    if (state.key == 'create:sticker' && state.flag('extended')) {
      final offset = state.dir('facing') ?? Direction.north;
      final attached = pos.relative(offset);
      if (!visited.contains(attached) &&
          !BlockMovementChecks.isNotSupportive(
            level.stateAt(attached),
            offset.opposite,
            level,
          )) {
        frontier.add(attached);
      }
    }

    level.notifyChainConveyor(pos);

    // Double chest halves stick together.
    if (state.has('type') && state.has('facing') && state['type'] != 'single') {
      final offset = _chestConnectedDirection(state);
      if (offset != null) {
        final attached = pos.relative(offset);
        if (!visited.contains(attached)) frontier.add(attached);
      }
    }

    // Bogeys tend to have sticky sides.
    for (final d in _bogeyStickySurfaces(state)) {
      if (!visited.contains(pos.relative(d))) frontier.add(pos.relative(d));
    }

    if (isBearingState(state)) _moveBearing(pos, frontier, visited, state);
    if (state.key == 'create:windmill_bearing')
      _moveWindmillBearing(pos, frontier, visited, state);

    if (level.stateHasTag(state, 'create:seats')) _moveSeat(level, pos);

    if (state.key == 'create:rope_pulley')
      _movePulley(level, pos, frontier, visited);

    if (isPistonState(state)) {
      if (!_moveMechanicalPiston(level, pos, frontier, visited, state))
        return false;
    }
    if (state.key == 'create:piston_extension_pole')
      _movePistonPole(level, pos, frontier, visited, state);
    if (state.key == 'create:mechanical_piston_head')
      _movePistonHead(level, pos, frontier, visited, state);

    // Cart assemblers attach themselves.
    final posDown = pos.below;
    if (!visited.contains(posDown) &&
        level.stateAt(posDown).key == 'create:cart_assembler')
      frontier.add(posDown);

    // Slime blocks and super glue drag adjacent blocks if possible.
    for (final offset in Direction.values) {
      final offsetPos = pos.relative(offset);
      final blockState = level.stateAt(offsetPos);
      if (isAnchoringBlockAt(offsetPos)) continue;
      if (!movementAllowed(blockState, level, offsetPos)) {
        if (offset == forcedDirection)
          throw AssemblyException.unmovableBlock(pos, state);
        continue;
      }

      final wasVisited = visited.contains(offsetPos);
      final faceHasGlue = _isGlued(level, pos, offset);
      final blockAttachedTowardsFace =
          BlockMovementChecks.isBlockAttachedTowards(
            blockState,
            level,
            offsetPos,
            offset.opposite,
          );
      final brittle = BlockMovementChecks.isBrittle(blockState, level);
      var canStick = !brittle && _canStickTo(state, blockState);
      if (canStick) {
        if (level.pushReaction(state) == PushReaction.pushOnly ||
            level.pushReaction(blockState) == PushReaction.pushOnly) {
          canStick = false;
        }
        if (BlockMovementChecks.isNotSupportive(state, offset, level))
          canStick = false;
        if (BlockMovementChecks.isNotSupportive(
          blockState,
          offset.opposite,
          level,
        ))
          canStick = false;
      }

      if (!wasVisited &&
          (canStick ||
              blockAttachedTowardsFace ||
              faceHasGlue ||
              (offset == forcedDirection &&
                  forcedDirection != null &&
                  !BlockMovementChecks.isNotSupportive(
                    state,
                    forcedDirection,
                    level,
                  )))) {
        frontier.add(offsetPos);
      }
    }

    addBlock(level, pos, capture(level, pos));
    if (blocks.length <= level.settings.maxBlocksMoved) return true;
    throw AssemblyException.structureTooLarge(level.settings.maxBlocksMoved);
  }

  void _movePistonHead(
    ContraptionLevel level,
    Pos pos,
    Queue<Pos> frontier,
    Set<Pos> visited,
    BState state,
  ) {
    final direction = state.dir('facing') ?? Direction.north;
    final offset = pos.relative(direction.opposite);
    if (!visited.contains(offset)) {
      final blockState = level.stateAt(offset);
      if (blockState.key == 'create:piston_extension_pole' &&
          (blockState.dir('facing')?.axis ?? Axis.y) == direction.axis) {
        frontier.add(offset);
      }
      if (isPistonState(blockState)) {
        final pistonFacing = blockState.dir('facing');
        if (pistonFacing == direction && blockState['state'] == 'extended')
          frontier.add(offset);
      }
    }
    if (state['type'] == 'sticky') {
      final attached = pos.relative(direction);
      if (!visited.contains(attached)) frontier.add(attached);
    }
  }

  void _movePistonPole(
    ContraptionLevel level,
    Pos pos,
    Queue<Pos> frontier,
    Set<Pos> visited,
    BState state,
  ) {
    final axis = state.dir('facing')?.axis ?? Axis.y;
    for (final d in Iterate.directionsInAxis(axis)) {
      final offset = pos.relative(d);
      if (visited.contains(offset)) continue;
      final blockState = level.stateAt(offset);
      if (blockState.key == 'create:piston_extension_pole' &&
          (blockState.dir('facing')?.axis ?? Axis.y) == d.axis) {
        frontier.add(offset);
      }
      if (blockState.key == 'create:mechanical_piston_head' &&
          (blockState.dir('facing')?.axis ?? Axis.y) == d.axis) {
        frontier.add(offset);
      }
      if (isPistonState(blockState)) {
        final pistonFacing = blockState.dir('facing');
        if (pistonFacing == d ||
            (pistonFacing == d.opposite && blockState['state'] == 'extended')) {
          frontier.add(offset);
        }
      }
    }
  }

  void _moveGantryPinion(
    ContraptionLevel level,
    Pos pos,
    Queue<Pos> frontier,
    Set<Pos> visited,
    BState state,
  ) {
    final facing = state.dir('facing') ?? Direction.north;
    final offset = pos.relative(facing);
    if (!visited.contains(offset)) frontier.add(offset);
    final rotationAxis = state.axisOf('axis') ?? facing.axis;
    for (final d in Iterate.directionsInAxis(rotationAxis)) {
      final o = pos.relative(d);
      final offsetState = level.stateAt(o);
      if (offsetState.key == 'create:gantry_shaft' &&
          (offsetState.dir('facing')?.axis ?? Axis.y) == d.axis &&
          !visited.contains(o)) {
        frontier.add(o);
      }
    }
  }

  void _moveGantryShaft(
    ContraptionLevel level,
    Pos pos,
    Queue<Pos> frontier,
    Set<Pos> visited,
    BState state,
  ) {
    final facing = state.dir('facing') ?? Direction.north;
    for (final d in Direction.values) {
      final offset = pos.relative(d);
      if (visited.contains(offset)) continue;
      final offsetState = level.stateAt(offset);
      if (d.axis == facing.axis &&
          offsetState.key == 'create:gantry_shaft' &&
          offsetState.dir('facing') == facing) {
        frontier.add(offset);
      } else if (offsetState.key == 'create:gantry_carriage' &&
          offsetState.dir('facing') == d) {
        frontier.add(offset);
      }
    }
  }

  void _moveWindmillBearing(
    Pos pos,
    Queue<Pos> frontier,
    Set<Pos> visited,
    BState state,
  ) {
    final facing = state.dir('facing') ?? Direction.north;
    final offset = pos.relative(facing);
    if (!visited.contains(offset)) frontier.add(offset);
  }

  void _moveBearing(
    Pos pos,
    Queue<Pos> frontier,
    Set<Pos> visited,
    BState state,
  ) {
    final facing = state.dir('facing') ?? Direction.north;
    if (!canBeStabilized(facing, pos - anchor)) {
      final offset = pos.relative(facing);
      if (!visited.contains(offset)) frontier.add(offset);
      return;
    }
    pendingSubContraptions.add(BlockFace(pos, facing));
  }

  void _moveBelt(Pos pos, Queue<Pos> frontier, Set<Pos> visited, BState state) {
    final hook = ContraptionMovementHooks.beltNextSegment;
    final nextPos = hook != null
        ? hook(state, pos, true)
        : _beltNextSegment(state, pos, true);
    final prevPos = hook != null
        ? hook(state, pos, false)
        : _beltNextSegment(state, pos, false);
    if (nextPos != null && !visited.contains(nextPos)) frontier.add(nextPos);
    if (prevPos != null && !visited.contains(prevPos)) frontier.add(prevPos);
  }

  /// `BeltBlock.nextSegmentPosition` for a straight belt segment: the next block in the facing
  /// direction until the end of the segment. Sloped and vertical belts are handled by the
  /// `beltNextSegment` hook the contraptions module installs.
  static Pos? _beltNextSegment(BState state, Pos pos, bool forward) {
    final part = state['part'];
    if (part == null) return null;
    if (forward && part == 'end') return null;
    if (!forward && part == 'start') return null;
    final facing = state.dir('facing');
    if (facing == null) return null;
    return pos.relative(forward ? facing : facing.opposite);
  }

  void _moveSeat(ContraptionLevel level, Pos pos) {
    final local = toLocalPos(pos);
    seats.add(local);
    final passenger = level.seatPassengerAt(pos);
    if (passenger != null) _initialPassengers[local] = passenger;
  }

  void _movePulley(
    ContraptionLevel level,
    Pos pos,
    Queue<Pos> frontier,
    Set<Pos> visited,
  ) {
    var limit = level.settings.maxRopeLength;
    var ropePos = pos;
    while (limit-- >= 0) {
      ropePos = ropePos.below;
      if (!level.isLoaded(ropePos)) break;
      final ropeState = level.stateAt(ropePos);
      if (ropeState.key != 'create:rope' &&
          ropeState.key != 'create:pulley_magnet') {
        if (!visited.contains(ropePos)) frontier.add(ropePos);
        break;
      }
      addBlock(level, ropePos, capture(level, ropePos));
    }
  }

  bool _moveMechanicalPiston(
    ContraptionLevel level,
    Pos pos,
    Queue<Pos> frontier,
    Set<Pos> visited,
    BState state,
  ) {
    final direction = state.dir('facing') ?? Direction.north;
    final pistonState = state['state'];
    if (pistonState == 'moving') return false;

    final offset = pos.relative(direction.opposite);
    if (!visited.contains(offset)) {
      final poleState = level.stateAt(offset);
      if (poleState.key == 'create:piston_extension_pole' &&
          (poleState.dir('facing')?.axis ?? Axis.y) == direction.axis) {
        frontier.add(offset);
      }
    }

    if (pistonState == 'extended' ||
        state.key == 'create:sticky_mechanical_piston') {
      final next = pos.relative(direction);
      if (!visited.contains(next)) frontier.add(next);
    }
    return true;
  }

  bool _moveChassis(
    ContraptionLevel level,
    Pos pos,
    Direction? movementDirection,
    Queue<Pos> frontier,
    Set<Pos> visited,
  ) {
    ContraptionMovementHooks.addAttachedChasses?.call(
      level,
      pos,
      frontier,
      visited,
    );
    final hook = ContraptionMovementHooks.chassisIncludedPositions;
    final included = hook?.call(level, pos, movementDirection);
    if (included == null)
      return true; // no chassis module: the block alone is captured
    for (final blockPos in included) {
      if (!visited.contains(blockPos)) frontier.add(blockPos);
    }
    return true;
  }

  /// `capture(world, pos)`.
  CapturedBlock capture(ContraptionLevel level, Pos pos) {
    var blockstate = level.stateAt(pos);
    if (blockstate.key == 'create:redstone_contact') {
      blockstate = blockstate.setFlag('powered', true);
    }
    if (blockstate.key == 'create:powered_shaft') {
      // The captured shaft is a plain shaft with the same axis.
      final axis = blockstate['axis'];
      blockstate = axis == null
          ? const BState('create:shaft')
          : BState('create:shaft', {'axis': axis});
    }
    if (blockstate.key == 'create:controls' && _opensControls()) {
      blockstate = blockstate.setFlag('open', true);
    }
    if (blockstate.has('visible'))
      blockstate = blockstate.setFlag('visible', false);
    if (_isButtonOrPlate(blockstate) && blockstate.has('powered')) {
      blockstate = blockstate.setFlag('powered', false);
      level.scheduleBlockTick(pos, blockstate.key);
    }
    final be = level.blockEntityAt(pos);
    final nbt = be == null ? null : be.saved.copy();
    if (nbt != null) {
      nbt.remove('x');
      nbt.remove('y');
      nbt.remove('z');
    }
    return CapturedBlock(StructureBlockInfo(pos, blockstate, nbt), be);
  }

  bool _opensControls() => true;

  static bool _isButtonOrPlate(BState state) {
    final path = state.key.substring(state.key.indexOf(':') + 1);
    return path.endsWith('_button') || path.endsWith('pressure_plate');
  }

  /// `addBlock(level, pos, pair)`.
  void addBlock(ContraptionLevel level, Pos pos, CapturedBlock captured) {
    final localPos = pos - anchor;
    final state = captured.info.state;
    final info = StructureBlockInfo(localPos, state, captured.info.nbt);

    if (blocks.containsKey(localPos)) return;
    blocks[localPos] = info;
    levelForColliders = level;
    bounds = (bounds ?? Aabb.ofBlock(posZero)).minmax(Aabb.ofBlock(localPos));

    final be = captured.blockEntity;
    if (be != null) updateTags[localPos] = be.update.copy();

    storage.addBlock(level, state, localPos, be);
    captureMultiblock(localPos, info, be);

    if (MovementBehaviours.of(state, level) != null) {
      actors.add(MovementContext(level, level.worldId, info, this));
    }
    final interaction = MovingInteractions.of(state, level);
    if (interaction != null) interactors[localPos] = interaction;

    if (state.key == 'create:creative_crate') hasUniversalCreativeCrate = true;
  }

  /// `removeBlock`: drops a block from the captured structure.
  void removeBlock(Pos localPos) {
    blocks.remove(localPos);
    updateTags.remove(localPos);
    isLegacy.remove(localPos);
    interactors.remove(localPos);
    actors.removeWhere((c) => c.localPos == localPos);
  }

  void captureMultiblock(
    Pos localPos,
    StructureBlockInfo info,
    CapturedBlockEntity? be,
  ) {
    if (be == null || !MultiBlockContainers.isContainer(be.typeKey)) return;
    final nbt = info.nbt;
    if (nbt == null) return;

    var controllerPos = localPos;
    if (nbt.contains('Controller'))
      controllerPos = toLocalPos(nbt.getBlockPos('Controller'));
    nbt.putBlockPos('Controller', controllerPos);
    updateTags[localPos]?.putBlockPos('Controller', controllerPos);

    if (_isMultiblockController(nbt) &&
        _multiBlockHeight(nbt) <= 1 &&
        _multiBlockWidth(nbt) <= 1) {
      nbt.putBlockPos('LastKnownPos', (0, _intMin + 1, 0));
      return;
    }

    nbt.remove('LastKnownPos');
    capturedMultiblocks.putIfAbsent(controllerPos, () => []).add(info);
  }

  static bool _isMultiblockController(NbtMap nbt) {
    if (!nbt.contains('Controller')) return true;
    final c = nbt.getBlockPos('Controller');
    return c == posZero;
  }

  static int _multiBlockHeight(NbtMap nbt) => nbt.getInt('Height', 1);
  static int _multiBlockWidth(NbtMap nbt) => nbt.getInt('Width', 1);

  bool _isGlued(ContraptionLevel level, Pos pos, Direction offset) {
    for (final glue in level.gluesIn(Aabb.ofBlock(pos).inflate(0.01))) {
      if (glue.contains(pos.relative(offset))) {
        _glueToRemove.add(glue);
        return true;
      }
    }
    return false;
  }

  static bool _canStickTo(BState state1, BState state2) {
    if (state1.key == 'minecraft:honey_block' &&
        state2.key == 'minecraft:slime_block')
      return false;
    if (state1.key == 'minecraft:slime_block' &&
        state2.key == 'minecraft:honey_block')
      return false;
    return _isStickyBlock(state1) || _isStickyBlock(state2);
  }

  static bool _isStickyBlock(BState state) =>
      state.key == 'minecraft:slime_block' ||
      state.key == 'minecraft:honey_block';

  static bool _isBelt(BState state) => state.key == 'create:belt';

  static Direction? _chestConnectedDirection(BState state) {
    final facing = state.dir('facing');
    if (facing == null) return null;
    return state['type'] == 'left' ? facing.clockWise : facing.counterClockWise;
  }

  static List<Direction> _bogeyStickySurfaces(BState state) {
    if (state.key != 'create:small_bogey' && state.key != 'create:large_bogey')
      return const [];
    final axis = state.axisOf('horizontal_axis') ?? Axis.x;
    return axis == Axis.x
        ? const [Direction.east, Direction.west]
        : const [Direction.south, Direction.north];
  }

  /// `movementAllowed`: whether a block of the structure may be captured. Subclasses add the
  /// rules of their kind (`MountedContraption` checks secondary cart assemblers).
  bool movementAllowed(BState state, ContraptionLevel level, Pos pos) =>
      BlockMovementChecks.isMovementAllowed(state, level, pos);

  /// `isAnchoringBlockAt`: the blocks that belong to the controller and are never captured.
  /// `PistonContraption` extends this to its extension poles.
  bool isAnchoringBlockAt(Pos pos) => pos == anchor;

  /// `shouldUpdateAfterMovement`: whether the placed block notifies its neighbours on disassembly.
  /// Java also skips blocks that own a POI; the host owns those and does not expose the check.
  bool shouldUpdateAfterMovement(StructureBlockInfo info) =>
      !_isDoor(info.state);

  // -- Entity integration ---------------------------------------------------------------------

  /// `onEntityCreated(entity)`.
  void onEntityCreated(ContraptionEntityHandle entity) {
    this.entity = entity;
    storage.initialize();
    invalidateColliders();
  }

  /// `onEntityInitialize(world, entity)`: seats the passengers that were sitting on the structure
  /// before it was assembled. The stabilized sub-contraptions are mounted by the host entity,
  /// which has the entity query of the world.
  void onEntityInitialize(ContraptionLevel level, Object entity) {
    if (entity is! ContraptionEntityHandle) return;
    for (final seatPos in seats) {
      final passenger = _initialPassengers[seatPos];
      if (passenger == null) continue;
      final seatIndex = seats.indexOf(seatPos);
      if (seatIndex == -1) continue;
      entity.addSittingPassenger(passenger, seatIndex);
    }
  }

  /// `takeStorage` (`swapStorageAfterAssembly`): the contraption keeps an empty storage manager and
  /// returns the cargo to the caller (a train carriage).
  MountedStorageManager takeStorage() {
    final taken = storage;
    storage = MountedStorageManager();
    _externalStorage = taken;
    return taken;
  }

  /// `returnStorageForDisassembly(storage)`: puts a cargo back before the blocks are placed.
  void returnStorageForDisassembly(Object storage) {
    _externalStorage = storage;
    if (storage is MountedStorageManager) this.storage = storage;
  }

  /// The cargo taken out by [takeStorage], if any.
  Object? get externalStorage => _externalStorage;

  // -- NBT ------------------------------------------------------------------------------------

  /// `Contraption.fromNBT`: a contraption of the saved type.
  static Contraption fromNbt(
    ContraptionLevel level,
    NbtMap nbt, {
    bool spawnData = false,
  }) {
    final contraption = ContraptionTypes.fromType(nbt.getString('Type'));
    contraption.readNbt(level, nbt, spawnData: spawnData);
    contraption.invalidateColliders();
    return contraption;
  }

  /// `readNBT`.
  void readNbt(ContraptionLevel level, NbtMap nbt, {bool spawnData = false}) {
    levelForColliders = level;
    settings = level.settings;
    _readBlocksCompound(nbt, level);

    capturedMultiblocks.clear();
    for (final v in nbt.getList('CapturedMultiblocks')) {
      final tag = NbtMap.of(v);
      if (!tag.contains('Controller') && !tag.contains('Parts')) continue;
      final controllerPos = tag.getBlockPos('Controller');
      for (final part in tag.getList('Parts')) {
        final cPart = NbtMap.of(part);
        // `cPart.contains("Pos") ? readBlockPos : (X, Y, Z)`; `getBlockPos` reads both forms.
        final partPos = cPart.getBlockPos('Pos');
        final info = blocks[partPos];
        if (info != null)
          capturedMultiblocks.putIfAbsent(controllerPos, () => []).add(info);
      }
    }

    storage.read(nbt, clientPacket: spawnData, contraption: this);

    actors.clear();
    for (final v in nbt.getList('Actors')) {
      final comp = NbtMap.of(v);
      final info = blocks[comp.getBlockPos('Pos')];
      if (info == null) continue;
      actors.add(
        MovementContext.readNbt(level, level.worldId, info, comp, this),
      );
    }

    disabledActors = _readItemList(nbt.getList('DisabledActors'));
    for (final stack in disabledActors) {
      setActorsActive(stack, false);
    }

    superglue = [
      for (final v in nbt.getList('Superglue')) _readAabb(NbtMap.of(v)),
    ];

    seats.clear();
    for (final v in nbt.getList('Seats')) {
      final c = NbtMap.of(v);
      // `c.contains("Pos") ? readBlockPos : (X, Y, Z)`; `getBlockPos` reads both forms.
      seats.add(c.getBlockPos('Pos'));
    }

    seatMapping.clear();
    for (final v in nbt.getList('Passengers')) {
      final c = NbtMap.of(v);
      final id = c.getUuid('Id');
      if (id != null) seatMapping[id] = c.getInt('Seat', 0);
    }

    stabilizedSubContraptions.clear();
    for (final v in nbt.getList('SubContraptions')) {
      final c = NbtMap.of(v);
      final id = c.getUuid('Id');
      final location = c.getCompoundOrNull('Location');
      if (id == null || location == null) continue;
      stabilizedSubContraptions[id] = BlockFace(
        location.getBlockPos('pos'),
        Direction.byName(location.getString('direction')) ?? Direction.north,
      );
    }

    interactors.clear();
    for (final v in nbt.getList('Interactors')) {
      final c = NbtMap.of(v);
      final pos = c.getBlockPos('Pos');
      final info = blocks[pos];
      if (info == null) continue;
      final behaviour = MovingInteractions.of(info.state, level);
      if (behaviour != null) interactors[pos] = behaviour;
    }

    if (nbt.contains('BoundsFront'))
      bounds = _readAabbList(nbt.getList('BoundsFront'));

    stalled = nbt.getBool('Stalled');
    hasUniversalCreativeCrate = nbt.getBool('BottomlessSupply');
    anchor = nbt.getBlockPos('Anchor');
  }

  /// `writeNBT(registries, spawnPacket)`.
  NbtMap writeNbt({bool spawnPacket = false}) {
    storage.initialize();
    final nbt = NbtMap()..putString('Type', typeId);

    final blocksNbt = _writeBlocksCompound(spawnPacket);

    final multiblocksNbt = <NbtValue>[];
    for (final e in capturedMultiblocks.entries) {
      final tag = NbtMap()..putBlockPos('Controller', e.key);
      tag.putList('Parts', [
        for (final info in e.value)
          (NbtMap()..putBlockPos('Pos', info.pos)).toValue(),
      ]);
      multiblocksNbt.add(tag.toValue());
    }

    final actorsNbt = <NbtValue>[];
    for (final context in getActors()) {
      final behaviour = MovementBehaviours.of(context.state);
      if (behaviour == null) continue;
      final compound = NbtMap()..putBlockPos('Pos', context.localPos);
      behaviour.writeExtraData(context);
      context.writeToNbt(compound);
      actorsNbt.add(compound.toValue());
    }

    final disabledNbt = _writeItemList(disabledActors);

    final superglueNbt = <NbtValue>[];
    if (!spawnPacket) {
      for (final glue in superglue) {
        superglueNbt.add(_writeAabb(glue).toValue());
      }
    }

    writeStorage(nbt, spawnPacket);

    final interactorNbt = <NbtValue>[
      for (final pos in interactors.keys)
        (NbtMap()..putBlockPos('Pos', pos)).toValue(),
    ];

    nbt.putList('Seats', [
      for (final pos in getSeats())
        (NbtMap()..putBlockPos('Pos', pos)).toValue(),
    ]);
    nbt.putList('Passengers', [
      for (final e in getSeatMapping().entries)
        (NbtMap()
              ..putUuid('Id', e.key)
              ..putInt('Seat', e.value))
            .toValue(),
    ]);

    nbt.putList('SubContraptions', [
      for (final e in stabilizedSubContraptions.entries)
        (NbtMap()
              ..putUuid('Id', e.key)
              ..putCompound(
                'Location',
                NbtMap()
                  ..putBlockPos('pos', e.value.pos)
                  ..putString('direction', e.value.face.serializedName),
              ))
            .toValue(),
    ]);

    nbt.putCompound('Blocks', blocksNbt);
    nbt.putList('Actors', actorsNbt);
    nbt.putList('CapturedMultiblocks', multiblocksNbt);
    nbt.putList('DisabledActors', disabledNbt);
    nbt.putList('Interactors', interactorNbt);
    nbt.putList('Superglue', superglueNbt);
    nbt.putBlockPos('Anchor', anchor);
    nbt.putBool('Stalled', stalled);
    nbt.putBool('BottomlessSupply', hasUniversalCreativeCrate);

    final b = bounds;
    if (b != null) nbt.putList('BoundsFront', _writeAabbList(b));

    return nbt;
  }

  /// `writeStorage`.
  void writeStorage(NbtMap nbt, bool spawnPacket) =>
      storage.write(nbt, clientPacket: spawnPacket);

  List<StoredStack> _readItemList(List<NbtValue> list) {
    final out = <StoredStack>[];
    for (final v in list) {
      final tag = NbtMap.of(v);
      if (tag.isEmpty) continue;
      final stack = StoredStack.fromNbt(tag);
      if (stack.isNotEmpty) out.add(stack);
    }
    return out;
  }

  List<NbtValue> _writeItemList(List<StoredStack> list) => [
    for (final s in list)
      if (!s.isEmpty) s.toNbt().toValue(),
  ];

  /// `SuperGlueEntity.writeBoundingBox`: `{From, To}` as two `VecHelper` vectors.
  NbtMap _writeAabb(Aabb bb) => NbtMap()
    ..putVec('From', (bb.minX, bb.minY, bb.minZ))
    ..putVec('To', (bb.maxX, bb.maxY, bb.maxZ));

  Aabb _readAabb(NbtMap c) => Aabb.between(c.getVec('From'), c.getVec('To'));

  List<NbtValue> _writeAabbList(Aabb bb) => [
    NbtValue.double64(bb.minX),
    NbtValue.double64(bb.minY),
    NbtValue.double64(bb.minZ),
    NbtValue.double64(bb.maxX),
    NbtValue.double64(bb.maxY),
    NbtValue.double64(bb.maxZ),
  ];

  Aabb _readAabbList(List<NbtValue> list) {
    double at(int i) {
      if (i >= list.length) return 0;
      final v = list[i];
      return switch (v.kind) {
        NbtKind.double || NbtKind.float => v.value as double,
        NbtKind.int ||
        NbtKind.long ||
        NbtKind.short ||
        NbtKind.byte => (v.value as int).toDouble(),
        _ => 0,
      };
    }

    return Aabb(at(0), at(1), at(2), at(3), at(4), at(5));
  }

  NbtMap _writeBlocksCompound(bool spawnPacket) {
    final palette = <BState>[];
    final paletteIds = <BState, int>{};
    final blockList = <NbtValue>[];

    for (final block in blocks.values) {
      var id = paletteIds[block.state];
      if (id == null) {
        id = palette.length;
        paletteIds[block.state] = id;
        palette.add(block.state);
      }
      final c = NbtMap()
        ..putLong('Pos', block.pos.asLong)
        ..putInt('State', id);

      final updateTag = updateTags[block.pos];
      if (spawnPacket) {
        if (updateTag != null) {
          c.putCompound('Data', updateTag.copy());
        } else if (block.nbt != null) {
          c.putCompound('Data', block.nbt!.copy());
          c.putMarker('Legacy');
        }
      } else {
        if (block.nbt != null) c.putCompound('Data', block.nbt!.copy());
        if (updateTag != null) c.putCompound('UpdateTag', updateTag.copy());
      }
      blockList.add(c.toValue());
    }

    final compound = NbtMap();
    compound.putList('Palette', [
      for (final state in palette) _writeState(state).toValue(),
    ]);
    compound.putList('BlockList', blockList);
    return compound;
  }

  void _readBlocksCompound(NbtMap nbt, ContraptionLevel level) {
    blocks.clear();
    updateTags.clear();
    isLegacy.clear();

    final blocksTag = nbt['Blocks'];
    final usePaletted =
        blocksTag != null &&
        blocksTag.kind == NbtKind.compound &&
        NbtMap.of(blocksTag).contains('Palette');

    if (usePaletted) {
      final c = NbtMap.of(blocksTag);
      final palette = [
        for (final v in c.getList('Palette')) _readState(NbtMap.of(v)),
      ];
      for (final v in c.getList('BlockList')) {
        final entry = NbtMap.of(v);
        final stateIndex = entry.getInt('State');
        final state = stateIndex >= 0 && stateIndex < palette.length
            ? palette[stateIndex]
            : BState.air;
        final info = StructureBlockInfo(
          posFromLong(entry.getInt('Pos')),
          state,
          entry.contains('Data') ? entry.getCompound('Data') : null,
        );
        blocks[info.pos] = info;
        if (entry.contains('UpdateTag'))
          updateTags[info.pos] = entry.getCompound('UpdateTag');
        isLegacy[info.pos] = entry.contains('Legacy');
      }
      return;
    }

    // Legacy: a list of `{Pos, Block, Data}` entries.
    final list = blocksTag != null && blocksTag.kind == NbtKind.list
        ? blocksTag.value as List<NbtValue>
        : <NbtValue>[];
    for (final v in list) {
      final entry = NbtMap.of(v);
      final info = StructureBlockInfo(
        entry.getBlockPos('Pos'),
        _readState(entry.getCompound('Block')),
        entry.contains('Data') ? entry.getCompound('Data') : null,
      );
      blocks[info.pos] = info;
    }
  }

  static NbtMap _writeState(BState state) {
    final nbt = NbtMap()..putString('Name', state.key);
    if (state.props.isNotEmpty) {
      final props = NbtMap();
      for (final e in state.props.entries) {
        props.putString(e.key, e.value);
      }
      nbt.putCompound('Properties', props);
    }
    return nbt;
  }

  static BState _readState(NbtMap nbt) {
    final key = nbt.getString('Name', 'minecraft:air');
    final props = nbt.getCompoundOrNull('Properties');
    return BState(
      key,
      props == null
          ? const {}
          : {for (final k in props.keys) k: props.getString(k)},
    );
  }

  // -- Disassembly ----------------------------------------------------------------------------

  /// `removeBlocksFromWorld(world, offset)`.
  Future<void> removeBlocksFromWorld(ContraptionLevel level, Pos offset) async {
    for (final glue in _glueToRemove) {
      superglue.add(glue.box.moveBy((offset + anchor).toVec3() * -1.0));
      level.discardGlue(glue);
    }
    _glueToRemove.clear();

    final minimisedGlue = List<BlockBounds?>.filled(superglue.length, null);

    for (final brittles in Iterate.trueAndFalse) {
      final iterator = blocks.values.toList();
      for (final block in iterator) {
        if (brittles != BlockMovementChecks.isBrittle(block.state, level))
          continue;

        for (var i = 0; i < superglue.length; i++) {
          final aabb = superglue[i];
          if (!aabb.contains(block.pos.center)) continue;
          final prev = minimisedGlue[i];
          minimisedGlue[i] = prev == null
              ? BlockBounds.single(block.pos)
              : prev.encapsulatePos(block.pos);
        }

        final add = block.pos + anchor + offset;
        if (customBlockRemoval(level, add, block.state)) continue;
        final oldState = level.stateAt(add);
        var blockMismatch = block.state.key != oldState.key;
        blockMismatch &=
            !(oldState.key == 'create:powered_shaft' &&
                block.state.key == 'create:shaft');
        if (blockMismatch) {
          blocks.remove(block.pos);
        }
        await level.removeBlockEntityAt(add);
        if (oldState.flag('waterlogged')) {
          await level.placeBlock(add, const BState('minecraft:water'));
          continue;
        }
        await level.placeBlock(add, BState.air);
      }
    }

    superglue.clear();
    for (final box in minimisedGlue) {
      if (box == null) continue;
      final bb = Aabb(
        box.minX.toDouble(),
        box.minY.toDouble(),
        box.minZ.toDouble(),
        box.maxX + 1.0,
        box.maxY + 1.0,
        box.maxZ + 1.0,
      );
      if (bb.xSize > 1.01 || bb.ySize > 1.01 || bb.zSize > 1.01)
        superglue.add(bb);
    }

    for (final block in blocks.values) {
      final add = block.pos + anchor + offset;
      level.sendBlockUpdate(add, block.state, BState.air);
      level.updateNeighbours(add, block.state);
    }
  }

  /// `disassemble`: stops the actors and places the blocks and passengers back into the world.
  Future<void> disassemble(
    ContraptionLevel level,
    StructureTransform transform, [
    List<Object> seatedEntities = const [],
  ]) async {
    stopMoving();
    await addBlocksToWorld(level, transform);
    await addPassengersToWorld(level, transform, seatedEntities);
  }

  /// `addBlocksToWorld(world, transform)`.
  Future<void> addBlocksToWorld(
    ContraptionLevel level,
    StructureTransform transform,
  ) async {
    if (disassembled) return;
    disassembled = true;

    final shouldDropBlocks = !level.settings.noDropWhenContraptionReplaceBlocks;

    translateMultiblockControllers(transform);

    for (final nonBrittles in Iterate.trueAndFalse) {
      for (final block in blocks.values.toList()) {
        if (nonBrittles == BlockMovementChecks.isBrittle(block.state, level))
          continue;

        var targetPos = transform.applyPos(block.pos);
        var state = transform.applyState(block.state);

        if (customBlockPlacement(level, targetPos, state)) continue;

        final existing = level.stateAt(targetPos);
        if (level.isUnbreakable(existing) ||
            (level.stateCollisionEmpty(state) &&
                !level.stateCollisionEmpty(existing))) {
          if (targetPos.y == level.minY) targetPos = targetPos.above;
          level.blockBreakParticles(targetPos, state);
          if (shouldDropBlocks) level.dropBlockItems(state, targetPos);
          continue;
        }

        if (state.has('waterlogged')) {
          state = state.setFlag('waterlogged', level.isWater(targetPos));
        }

        await level.destroyBlockAt(targetPos, drop: shouldDropBlocks);

        if (state.has('visible')) {
          state = state
              .setFlag('visible', !state.flag('open'))
              .setFlag('powered', false);
        }
        if (state.key == 'minecraft:sculk_shrieker') {
          state = const BState('minecraft:sculk_shrieker');
        }

        await level.placeBlock(targetPos, state);

        final verticalRotation =
            transform.rotationAxis == null ||
            transform.rotationAxis!.isHorizontal;
        if (verticalRotation && transform.rotation != BlockRotation.none) {
          if (state.key == 'create:rope' ||
              state.key == 'create:pulley_magnet' ||
              _isDoor(state)) {
            await level.destroyBlockAt(targetPos, drop: shouldDropBlocks);
          }
        }

        var tag = block.nbt?.copy();
        if (state.key == 'minecraft:sculk_sensor' ||
            state.key == 'minecraft:sculk_shrieker')
          tag = null;

        if (tag != null) {
          tag
            ..putInt('x', targetPos.$1)
            ..putInt('y', targetPos.$2)
            ..putInt('z', targetPos.$3);

          if (verticalRotation && state.key == 'create:rope_pulley') {
            tag.remove('Offset');
            tag.remove('InitialOffset');
          }

          if (MultiBlockContainers.isContainer(tag.getString('id'))) {
            if (tag.contains('LastKnownPos') || capturedMultiblocks.isEmpty) {
              tag.putBlockPos('LastKnownPos', (0, _intMin + 1, 0));
              tag.remove('Controller');
            }
          }

          // The mounted storage puts its items back into the block entity data.
          tag = storage.unmount(level, block, tag);

          if (tag != null) {
            final typeKey = tag.getString('id');
            if (typeKey.isNotEmpty) transform.applyBlockEntity(typeKey, tag);
            await level.restoreBlockEntity(targetPos, tag);
          }
        } else {
          // No block entity data: still let the storage put its content somewhere sensible.
          storage.unmount(level, block, null);
        }
      }
    }

    for (final block in blocks.values) {
      if (!shouldUpdateAfterMovement(block)) continue;
      final targetPos = transform.applyPos(block.pos);
      level.updateNeighbours(targetPos, block.state);
    }

    for (final box in superglue) {
      level.addGlue(transform.applyAabb(box));
    }
  }

  /// `translateMultiblockControllers(transform)`.
  void translateMultiblockControllers(StructureTransform transform) {
    if (transform.rotationAxis != null &&
        transform.rotationAxis != Axis.y &&
        transform.rotation != BlockRotation.none) {
      for (final parts in capturedMultiblocks.values) {
        for (final info in parts) {
          info.nbt?.putBlockPos('LastKnownPos', (0, _intMin + 1, 0));
        }
      }
      return;
    }

    for (final controllerPos in capturedMultiblocks.keys.toList()) {
      final parts = capturedMultiblocks[controllerPos]!;
      if (parts.isEmpty) continue;
      final transformed = [
        for (final info in parts) transform.applyPos(info.pos),
      ];
      var minX = transformed.first.$1,
          minY = transformed.first.$2,
          minZ = transformed.first.$3;
      var maxX = minX, maxY = minY, maxZ = minZ;
      for (final p in transformed) {
        if (p.$1 < minX) minX = p.$1;
        if (p.$2 < minY) minY = p.$2;
        if (p.$3 < minZ) minZ = p.$3;
        if (p.$1 > maxX) maxX = p.$1;
        if (p.$2 > maxY) maxY = p.$2;
        if (p.$3 > maxZ) maxZ = p.$3;
      }
      final newControllerPos = (minX, minY, minZ);
      final otherPos = transform.unapplyPos(newControllerPos);

      for (final info in parts) {
        info.nbt?.putBlockPos('Controller', newControllerPos);
      }

      if (controllerPos == otherPos) continue;

      final prevControllerInfo = blocks[controllerPos];
      final newControllerInfo = blocks[otherPos];
      if (prevControllerInfo == null || newControllerInfo == null) continue;

      blocks[otherPos] = StructureBlockInfo(
        newControllerInfo.pos,
        newControllerInfo.state,
        prevControllerInfo.nbt,
      );
      blocks[controllerPos] = StructureBlockInfo(
        prevControllerInfo.pos,
        prevControllerInfo.state,
        newControllerInfo.nbt,
      );
    }
  }

  /// `addPassengersToWorld(world, transform, seatedEntities)`.
  Future<void> addPassengersToWorld(
    ContraptionLevel level,
    StructureTransform transform,
    List<Object> seatedEntities,
  ) async {
    if (getSeatMapping().isEmpty) return;
    for (final seatedEntity in seatedEntities) {
      final uuid = _passengerUuid(seatedEntity);
      if (uuid == null) continue;
      final seatIndex = getSeatMapping()[uuid];
      if (seatIndex == null) continue;
      if (seatIndex >= seats.length) continue;
      final seatPos = transform.applyPos(seats[seatIndex]);
      await level.sitPassenger(seatPos, seatedEntity);
    }
  }

  static String? _passengerUuid(Object passenger) {
    if (passenger is ContraptionPassenger) return passenger.uuid;
    return null;
  }

  // -- Actors ---------------------------------------------------------------------------------

  /// `startMoving(world)`.
  void startMoving(ContraptionLevel level) {
    disabledActors.clear();

    for (var i = 0; i < actors.length; i++) {
      final old = actors[i];
      final info = blocks[old.localPos];
      if (info == null) continue;
      final context = MovementContext(level, level.worldId, info, this);
      final behaviour = MovementBehaviours.of(info.state, level);
      if (behaviour != null) behaviour.startMoving(context);
      actors[i] = context;
      final hook = ActorControlHooks.isDisabledInitially;
      if (hook != null && hook(context)) _disableActorOnStart(context);
    }

    for (final stack in disabledActors) {
      setActorsActive(stack, false);
    }
  }

  void _disableActorOnStart(MovementContext context) {
    final filterHook = ActorControlHooks.filterOf;
    if (filterHook == null) return;
    final filter = filterHook(context);
    if (filter == null) return;
    if (isActorTypeDisabled(filter)) return;
    disabledActors.add(filter);
  }

  /// `isActorTypeDisabled(filter)`.
  bool isActorTypeDisabled(StoredStack filter) {
    final same = ActorControlHooks.isSameFilter;
    if (same == null)
      return disabledActors.any((i) => i.sameItemSameComponents(filter));
    return disabledActors.any((i) => same(i, filter));
  }

  /// `setActorsActive(referenceStack, enable)`.
  void setActorsActive(StoredStack referenceStack, bool enable) {
    final same = ActorControlHooks.isSameFilter;
    for (final context in actors) {
      final behaviour = MovementBehaviours.of(context.state);
      if (behaviour == null) continue;
      final behaviourStack = behaviour.canBeDisabledVia(context);
      if (behaviourStack == null) continue;
      if (!referenceStack.isEmpty) {
        final matches = same != null
            ? same(referenceStack, behaviourStack)
            : referenceStack.sameItemSameComponents(behaviourStack);
        if (!matches) continue;
      }
      context.disabled = !enable;
      if (!enable) behaviour.onDisabledByControls(context);
    }
  }

  /// `getDisabledActors()`.
  List<StoredStack> getDisabledActors() => disabledActors;

  /// `stop(world)`.
  void stopMoving() {
    forEachActor((behaviour, context) {
      behaviour.stopMoving(context);
      context.position = null;
      context.motion = vec3Zero;
      context.relativeMotion = vec3Zero;
      context.rotation = (v) => v;
    });
  }

  /// `cancelActorStalls()` (`train` calls it through `ContraptionData`).
  void cancelActorStalls() {
    forEachActor((behaviour, context) => behaviour.cancelStall(context));
  }

  /// `forEachActor`.
  void forEachActor(
    void Function(MovementBehaviour behaviour, MovementContext context)
    callback,
  ) {
    for (final context in actors) {
      final behaviour = MovementBehaviours.of(context.state);
      if (behaviour == null) continue;
      callback(behaviour, context);
    }
  }

  /// `tick(level)`: syncs the mounted storages to the clients.
  void tick(ContraptionLevel level) {
    final sync = storage.tick();
    if (sync != null && entity != null) entity!.sendStorageSync(sync);
  }

  /// `tickStorage(entity)`.
  void tickStorage(ContraptionEntityHandle entity) {
    final sync = storage.tick();
    if (sync != null) entity.sendStorageSync(sync);
  }

  /// `containsBlockBreakers()`.
  bool containsBlockBreakers() {
    for (final context in actors) {
      final behaviour = MovementBehaviours.of(context.state);
      if (behaviour != null && behaviour.breaksBlocks()) return true;
    }
    return false;
  }

  /// `getActorAt(localPos)`.
  MovementContext? getActorAt(Pos localPos) {
    for (final context in actors) {
      if (context.localPos == localPos) return context;
    }
    return null;
  }

  // -- Positions and bounds -------------------------------------------------------------------

  /// `toLocalPos(globalPos)`.
  Pos toLocalPos(Pos globalPos) => globalPos - anchor;

  /// `toGlobalPos(localPos)`.
  Pos toGlobalPos(Pos localPos) => localPos + anchor;

  /// `getSeatMapping()`.
  Map<String, int> getSeatMapping() => seatMapping;

  /// `setSeatMapping`.
  void setSeatMapping(Map<String, int> mapping) => seatMapping = mapping;

  /// `getSeatOf(entityId)`.
  Pos? getSeatOf(String entityId) {
    final index = seatMapping[entityId];
    if (index == null || index >= seats.length) return null;
    return seats[index];
  }

  /// `getBearingPosOf(subContraptionEntityId)`.
  Pos? getBearingPosOf(String subContraptionEntityId) =>
      stabilizedSubContraptions[subContraptionEntityId]?.connectedPos;

  /// `getSeats()`.
  List<Pos> getSeats() => seats;

  /// `getBlocks()`.
  Map<Pos, StructureBlockInfo> getBlocks() => blocks;

  /// `getIsLegacy()`.
  Map<Pos, bool> getIsLegacy() => isLegacy;

  /// `getActors()`.
  List<MovementContext> getActors() => actors;

  /// `getInteractors()`.
  Map<Pos, MovingInteractionBehaviour> getInteractors() => interactors;

  /// `getStorage()`.
  MountedStorageManager getStorage() => storage;

  /// `isHiddenInPortal(localPos)`; the train carriage overrides this.
  bool isHiddenInPortal(Pos localPos) => false;

  /// `getSimplifiedEntityColliders()`.
  CollisionList getSimplifiedEntityColliders() => simplifiedEntityColliders;

  /// `invalidateColliders()`: rebuilds the collision boxes of the carried blocks.
  void invalidateColliders() {
    simplifiedEntityColliders.clear();
    for (final entry in blocks.entries) {
      final info = entry.value;
      final boxes =
          levelForColliders?.stateCollisionBoxes(info.state) ?? const [];
      if (boxes.isEmpty) continue;
      for (final box in boxes) {
        simplifiedEntityColliders.append(
          entry.key.$1 + (box.minX + box.maxX) / 2,
          entry.key.$2 + (box.minY + box.maxY) / 2,
          entry.key.$3 + (box.minZ + box.maxZ) / 2,
          (box.maxX - box.minX) / 2,
          (box.maxY - box.minY) / 2,
          (box.maxZ - box.minZ) / 2,
        );
      }
    }
  }

  /// The level used to look up the collision shapes of the states (`ContraptionWorld` of Create).
  ContraptionLevel? levelForColliders;

  /// `expandBoundsAroundAxis(axis)`.
  void expandBoundsAroundAxis(Axis axis) {
    final radius = getRadius(blocks.keys, axis).ceil();
    var maxX = radius + 2;
    var maxY = radius + 2;
    var maxZ = radius + 2;
    var minX = -radius - 1;
    var minY = -radius - 1;
    var minZ = -radius - 1;
    final b = bounds;
    if (b != null) {
      if (axis == Axis.x) {
        maxX = b.maxX.ceil();
        minX = b.minX.floor();
      } else if (axis == Axis.y) {
        maxY = b.maxY.ceil();
        minY = b.minY.floor();
      } else {
        maxZ = b.maxZ.ceil();
        minZ = b.minZ.floor();
      }
    }
    bounds = Aabb(
      minX.toDouble(),
      minY.toDouble(),
      minZ.toDouble(),
      maxX.toDouble(),
      maxY.toDouble(),
      maxZ.toDouble(),
    );
  }

  /// `Contraption.getRadius(blocks, axis)`.
  static double getRadius(Iterable<Pos> blocks, Axis axis) {
    final (axisA, axisB) = switch (axis) {
      Axis.x => (Axis.y, Axis.z),
      Axis.y => (Axis.x, Axis.z),
      Axis.z => (Axis.x, Axis.y),
    };
    var maxDistSq = 0;
    for (final vec in blocks) {
      final a = vec.get(axisA);
      final b = vec.get(axisB);
      final distSq = a * a + b * b;
      if (distSq > maxDistSq) maxDistSq = distSq;
    }
    return math.sqrt(maxDistSq.toDouble());
  }

  /// `isAliveOrStale` on the entity side: whether the contraption still has blocks to show.
  bool get isEmpty => blocks.isEmpty;

  static bool _isDoor(BState state) =>
      state.has('hinge') &&
      state.has('half') &&
      state.has('open') &&
      state.has('facing');
}

/// A passenger of a contraption seat (`Entity`), as `addPassengersToWorld` sees it.
abstract interface class ContraptionPassenger {
  String get uuid;
}
