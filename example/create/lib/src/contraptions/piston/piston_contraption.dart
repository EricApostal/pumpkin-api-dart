// `PistonContraption`: the head and the extension poles of a mechanical piston. The piston moves
// the structure along its facing without rotating it.
//
// Java: `content/contraptions/piston/PistonContraption`.
import 'dart:collection';

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../core/contraption.dart';
import '../core/level.dart';
import '../core/movement_checks.dart';
import '../core/nbt_map.dart';
import '../core/structure_info.dart';
import '../entity/translating_contraption.dart';
import 'linear_actuator_logic.dart';

export 'linear_actuator_logic.dart'
    show isPistonStateKey, isPistonPole, isPistonHead, pistonPoleMatchesAxis;

class PistonContraption extends TranslatingContraption {
  int extensionLength = 0;
  int initialExtensionProgress = 0;
  Direction orientation = Direction.north;
  bool retract = false;

  Aabb? _pistonExtensionCollisionBox;

  @override
  String get typeId => 'create:piston';

  PistonContraption([this.orientation = Direction.north, this.retract = false]);

  @override
  Future<bool> assemble(ContraptionLevel level, Pos pos) async {
    if (!_collectExtensions(level, pos, orientation)) return false;
    final count = blocks.length;
    if (!searchMovedStructure(
      level,
      anchor,
      retract ? orientation.opposite : orientation,
    ))
      return false;
    final extensionBox = _pistonExtensionCollisionBox;
    if (extensionBox != null) {
      bounds = blocks.length == count
          ? extensionBox
          : (bounds ?? Aabb.ofBlock(posZero)).minmax(extensionBox);
    }
    startMoving(level);
    return true;
  }

  bool _collectExtensions(
    ContraptionLevel level,
    Pos pos,
    Direction direction,
  ) {
    final poles = <StructureBlockInfo>[];
    var actualStart = pos;
    var nextBlock = level.stateAt(actualStart.relative(direction));
    var extensionsInFront = 0;
    final blockState = level.stateAt(pos);
    final sticky = blockState.key == 'create:sticky_mechanical_piston';

    if (!isPistonStateKey(blockState.key)) return false;

    if (blockState['state'] == 'extended') {
      while (pistonPoleMatchesAxis(nextBlock, direction.axis) ||
          (isPistonHead(nextBlock) && nextBlock.dir('facing') == direction)) {
        actualStart = actualStart.relative(direction);
        poles.add(
          StructureBlockInfo(
            actualStart,
            nextBlock.setDir('facing', direction),
          ),
        );
        extensionsInFront++;
        if (isPistonHead(nextBlock)) break;
        nextBlock = level.stateAt(actualStart.relative(direction));
        if (extensionsInFront > level.settings.maxPistonPoles) {
          throw AssemblyException.tooManyPistonPoles(
            level.settings.maxPistonPoles,
          );
        }
      }
    }

    if (extensionsInFront == 0) {
      poles.add(
        StructureBlockInfo(
          pos,
          BState('create:mechanical_piston_head', {
            'facing': direction.serializedName,
            'type': sticky ? 'sticky' : 'normal',
          }),
        ),
      );
    } else {
      poles.add(
        StructureBlockInfo(
          pos,
          BState('create:piston_extension_pole', {
            'facing': direction.serializedName,
          }),
        ),
      );
    }

    var end = pos;
    nextBlock = level.stateAt(end.relative(direction.opposite));
    var extensionsInBack = 0;

    while (pistonPoleMatchesAxis(nextBlock, direction.axis)) {
      end = end.relative(direction.opposite);
      poles.add(StructureBlockInfo(end, nextBlock.setDir('facing', direction)));
      extensionsInBack++;
      nextBlock = level.stateAt(end.relative(direction.opposite));
      if (extensionsInFront + extensionsInBack >
          level.settings.maxPistonPoles) {
        throw AssemblyException.tooManyPistonPoles(
          level.settings.maxPistonPoles,
        );
      }
    }

    anchor = pos.relative(direction, initialExtensionProgress + 1);
    extensionLength = extensionsInBack + extensionsInFront;
    initialExtensionProgress = extensionsInFront;
    _pistonExtensionCollisionBox = Aabb.between(
      posZero.relative(direction, -1).toVec3(),
      posZero.relative(direction, -extensionLength - 1).toVec3(),
    ).expandTowards(1, 1, 1);

    if (extensionLength == 0) throw AssemblyException.noPistonPoles();

    bounds = Aabb.ofBlock(posZero);

    for (final pole in poles) {
      final relPos = pole.pos.relative(direction, -extensionsInFront);
      final localPos = relPos - anchor;
      blocks[localPos] = StructureBlockInfo(localPos, pole.state);
    }

    return true;
  }

  @override
  bool isAnchoringBlockAt(Pos pos) {
    final box = _pistonExtensionCollisionBox;
    if (box == null) return super.isAnchoringBlockAt(pos);
    return box.contains(VecHelper.getCenterOf(pos - anchor));
  }

  @override
  bool addToInitialFrontier(
    ContraptionLevel level,
    Pos pos,
    Direction? direction,
    Queue<Pos> frontier,
  ) {
    frontier.clear();
    final sticky =
        level.stateAt(pos.relative(orientation, -1)).key ==
        'create:sticky_mechanical_piston';
    final retracting = direction != orientation;
    if (retracting && !sticky) return true;
    for (var offset = 0; offset <= level.settings.maxChassisRange; offset++) {
      if (offset == 1 && retracting) return true;
      final currentPos = pos.relative(
        orientation,
        offset + initialExtensionProgress,
      );
      if (retracting && level.isOutsideBuildHeight(currentPos)) return true;
      if (!level.isLoaded(currentPos))
        throw AssemblyException.unloadedChunk(currentPos);
      final state = level.stateAt(currentPos);
      if (!BlockMovementChecks.isMovementNecessary(state, level, currentPos))
        return true;
      if (BlockMovementChecks.isBrittle(state, level) &&
          !state.key.endsWith('_carpet')) {
        return true;
      }
      if (isPistonHead(state) && state.dir('facing') == direction?.opposite)
        return true;
      if (!BlockMovementChecks.isMovementAllowed(state, level, currentPos)) {
        if (retracting) return true;
        throw AssemblyException.unmovableBlock(currentPos, state);
      }
      if (retracting && level.pushReaction(state) == PushReaction.pushOnly)
        return true;
      frontier.add(currentPos);
      if (BlockMovementChecks.isNotSupportive(state, orientation, level))
        return true;
    }
    return true;
  }

  @override
  void addBlock(ContraptionLevel level, Pos pos, CapturedBlock captured) {
    super.addBlock(
      level,
      pos.relative(orientation, -initialExtensionProgress),
      captured,
    );
  }

  @override
  Pos toLocalPos(Pos globalPos) =>
      (globalPos - anchor).relative(orientation, -initialExtensionProgress);

  @override
  bool customBlockPlacement(ContraptionLevel level, Pos pos, BState state) {
    final pistonPos = anchor.relative(orientation, -1);
    if (pos != pistonPos) return false;
    final pistonState = level.stateAt(pistonPos);
    final be = level.blockEntityAt(pistonPos);
    if (be == null) return true;
    if (!isPistonPole(state) && isPistonStateKey(pistonState.key)) {
      level.placeBlock(pistonPos, pistonState.setValue('state', 'retracted'));
    }
    return true;
  }

  @override
  bool customBlockRemoval(ContraptionLevel level, Pos pos, BState state) {
    final pistonPos = anchor.relative(orientation, -1);
    if (pos != pistonPos) return false;
    final blockState = level.stateAt(pos);
    if (!isPistonStateKey(blockState.key)) return false;
    level.placeBlock(pos, blockState.setValue('state', 'moving'));
    return true;
  }

  @override
  void readNbt(ContraptionLevel level, NbtMap nbt, {bool spawnData = false}) {
    super.readNbt(level, nbt, spawnData: spawnData);
    initialExtensionProgress = nbt.getInt('InitialLength');
    extensionLength = nbt.getInt('ExtensionLength');
    orientation = Direction.from3DDataValue(nbt.getInt('Orientation'));
  }

  @override
  NbtMap writeNbt({bool spawnPacket = false}) {
    final tag = super.writeNbt(spawnPacket: spawnPacket);
    tag.putInt('InitialLength', initialExtensionProgress);
    tag.putInt('ExtensionLength', extensionLength);
    tag.putInt('Orientation', orientation.data3d);
    return tag;
  }
}
