// `GantryCarriageBlock` and `GantryCarriageBlockEntity`: the pinion that rides a gantry shaft and
// assembles the gantry contraption. The shaft itself is a kinetics block; its parts are asked
// through [GantryShaftLike].
//
// Java: `content/contraptions/gantry/{GantryCarriageBlock,GantryCarriageBlockEntity}`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart'
    show HostBlockGetter, manifestBlock, setBlockState, toDirection;
import '../../common/common.dart';
import '../../core/blocks.dart';
import '../../kinetics/api.dart';
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_nbt.dart';
import '../blocks/actuator_runtime.dart';
import '../core/structure_info.dart';
import 'gantry_contraption.dart';
import 'gantry_contraption_entity.dart';
import 'gantry_logic.dart';

export 'gantry_logic.dart'
    show
        gantryCarriageKey,
        gantryShaftKey,
        toDirection2,
        getValidGantryShaftAxis,
        getGantryPinionModifier;

/// The gantry carriage definition.
List<CreateBlock> buildGantryBlocks() => [
  manifestBlock(
    'gantry_carriage',
    placement: const [PlacementRule.clickedFace('facing')],
    blockEntityType: gantryCarriageKey,
    behavior: BlockBehavior(
      onUseWithoutItem: (server, e) async {
        if (e.sneaking) return BlockUseResult.pass;
        final runtime = ActuatorRuntime.maybe;
        final be = runtime?.store.at(e.targetWorld.getId(), e.pos);
        if (be is GantryCarriageBlockEntity) be.checkValidGantryShaft();
        return BlockUseResult.success;
      },
      onPlaced: (server, e) async {
        // `GantryCarriageBlock.getStateForPlacement`: cycle `axis_along_first` so the shaft
        // behind the carriage becomes the valid shaft axis.
        if (e.moved) return;
        final pos = (e.pos.x, e.pos.y, e.pos.z);
        final level = HostBlockGetter(e.targetWorld);
        final state = level.stateAt(pos);
        final next = gantryPlacementState(level, pos);
        if (next != state) await setBlockState(e.targetWorld, pos, next);
      },
      onNeighborUpdate: (server, e) async {
        // `GantryCarriageBlock.neighborChanged`: `canSurvive` needs a shaft behind the
        // carriage, on another axis.
        final level = HostBlockGetter(e.targetWorld);
        final state = level.stateAt((e.pos.x, e.pos.y, e.pos.z));
        final facing = state.dir('facing') ?? Direction.north;
        final shaft = level.stateAt(
          (e.pos.x, e.pos.y, e.pos.z).relative(facing.opposite),
        );
        if (!gantryCarriageCanSurvive(state, shaft)) {
          await e.targetWorld.breakBlock(e.pos, drop: true);
        }
      },
      onUpdateShape: (server, e) {
        // `cycleAxisIfNecessary`: the axis along first follows the shaft's axis.
        final state = HostBlockGetter(e.targetWorld).stateAt(
          (e.pos.x, e.pos.y, e.pos.z),
        );
        final facing = state.dir('facing');
        if (facing == null || facing.opposite != toDirection(e.direction))
          return null;
        final other = HostBlockGetter.stateOfId(e.neighborStateId);
        final next = cycleGantryAxisIfNecessary(
          state,
          toDirection(e.direction),
          other,
        );
        if (next == state) return null;
        return BlockRegistry.resolveState(state.key, next.props);
      },
    ),
  ),
];

/// `GantryCarriageBlockEntity`.
class GantryCarriageBlockEntity extends KineticBlockEntity
    implements AssemblyExceptionHolding {
  GantryCarriageBlockEntity(super.worldId, super.pos);

  bool assembleNextTick = false;
  AssemblyException? lastException;

  Pos get localPos => (this.pos.x, this.pos.y, this.pos.z);

  BState get stateNow =>
      HostBlockGetter.stateOfId(world!.getBlockStateId(pos: this.pos));

  /// `checkValidGantryShaft`.
  void checkValidGantryShaft() {
    if (shouldAssemble()) queueAssembly();
  }

  /// `queueAssembly`.
  void queueAssembly() => assembleNextTick = true;

  @override
  void initialize() {
    super.initialize();
    // `GantryCarriageBlockEntity.initialize`: a carriage without a shaft behind it cannot stay.
    final world = this.world;
    if (world == null) return;
    final state = stateNow;
    if (state.key != gantryCarriageKey) return;
    final facing = state.dir('facing') ?? Direction.north;
    final behind = HostBlockGetter(world)
        .stateAt(localPos.relative(facing.opposite));
    if (!gantryCarriageCanSurvive(state, behind)) {
      unawaited(world.breakBlock(this.pos, drop: true));
    }
  }

  @override
  void tick() {
    super.tick();
    if (!assembleNextTick) return;
    assembleNextTick = false;
    unawaited(_tryAssemble());
  }

  Future<void> _tryAssemble() async {
    final level = ActuatorHosts.levelOf(worldId);
    final factory = ActuatorHosts.entities;
    if (level == null || factory == null) return;
    final state = stateNow;
    if (state.key != gantryCarriageKey) return;
    final direction = state.dir('facing') ?? Direction.north;

    final shaft = GantryShafts.at(
      worldId,
      localPos.relative(direction.opposite),
    );
    if (shaft == null || shaft.shaftState.key != gantryShaftKey) return;

    final shaftState = shaft.shaftState;
    final speed = shaft.pinionMovementSpeed;
    final shaftOrientation = shaftState.dir('facing') ?? Direction.north;
    final movementDirection = gantryPinionMovementDirection(
      shaftOrientation,
      speed,
    );

    final contraption = GantryContraption(direction);
    try {
      lastException = null;
      if (!await contraption.assemble(level, localPos)) return;
      sendData();
    } on AssemblyException catch (e) {
      lastException = e;
      sendData();
      return;
    }

    if (ContraptionCollision.isCollidingWithWorld?.call(
          level,
          contraption,
          localPos.relative(movementDirection),
          movementDirection,
        ) ??
        false) {
      return;
    }

    await contraption.removeBlocksFromWorld(level, posZero);
    final entity = factory.createGantry(worldId, contraption, shaftOrientation);
    entity.setPos(localPos.toVec3());
    factory.spawn(worldId, entity);

    final sequence = shaft.sequenceContext;
    if (sequence != null &&
        sequence.instruction == SequencerInstructions.turnDistance &&
        entity is GantryContraptionEntity) {
      entity.limitMovement(sequence.getEffectiveValue(shaft.theoreticalSpeed));
    }
  }

  bool shouldAssemble() {
    final state = stateNow;
    if (state.key != gantryCarriageKey) return false;
    final facing = (state.dir('facing') ?? Direction.north).opposite;
    final shaft = GantryShafts.at(worldId, localPos.relative(facing));
    if (shaft == null) return false;
    if (shaft.shaftState.key != gantryShaftKey) return false;
    if (shaft.shaftState.flag('powered')) return false;
    return shaft.canAssembleOn;
  }

  @override
  double propagateRotationTo(
    KineticNode target,
    KState stateFrom,
    KState stateTo,
    KPos diff,
    bool connectedViaAxes,
    bool connectedViaCogs,
  ) {
    final defaultModifier = super.propagateRotationTo(
      target,
      stateFrom,
      stateTo,
      diff,
      connectedViaAxes,
      connectedViaCogs,
    );
    if (connectedViaAxes) return defaultModifier;
    if (stateTo.block != gantryShaftKey || !stateTo.flag('powered'))
      return defaultModifier;
    final direction = Dir.approximateNearest(diff.x, diff.y, diff.z);
    final facing = stateFrom.dirOf('facing') ?? Dir.north;
    if (facing != direction.opposite) return defaultModifier;
    final shaft = stateTo.dirOf('facing') ?? Dir.north;
    return getGantryPinionModifier(toDirection2(shaft), toDirection2(facing));
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    writeAssemblyException(tag, lastException);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    lastException = readAssemblyException(tag);
    super.read(tag, clientPacket: clientPacket);
  }

  @override
  AssemblyException? get lastAssemblyException => lastException;
}
