// `AttachedActorBlock`: the base of the harvester, the plough and the roller - a horizontal facing
// actor that hangs on the solid side of the block behind it and can be waterlogged.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter, manifestBlock, updateWater;
import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../../core/blocks.dart';
import 'actor_shapes.dart';

/// `AttachedActorBlock`: `HARVESTER_BASE` as the selection shape (`Shapes.block` for the roller).
/// [behavior] adds the hooks of the concrete actor; the placement and water hooks stay.
CreateBlock buildAttachedActorBlock(
  String key, {
  String? blockEntityType,
  BlockBehavior? behavior,
  List<String> tags = const [],
  BlockDrops? drops,
  bool fullCube = false,
  bool requireSupport = true,
}) {
  final boxes = fullCube
      ? const [BlockBox(0, 0, 0, 1, 1, 1)]
      : [actorBox(0, 2, 0, 16, 14, 3)];
  final shape = BlockShape.boxes(boxes);
  final rules = fullCube
      ? <ShapeRule>[]
      : actorShapeRules(
          'facing',
          boxes,
          Direction.south,
          collisionBoxes: const [BlockBox(0, 0, 0, 1, 1, 1)],
        );

  late final CreateBlock block;
  Future<void> placed(Server server, CustomBlockPlacedEventData e) async {
    if (!e.moved && requireSupport) {
      final lvl = HostBlockGetter(e.targetWorld);
      final pos = e.pos.toPos();
      final facing =
          Direction.byName(block.stateOf(e.stateIndex)['facing'] ?? '') ??
          Direction.north;
      // `canSurvive`: the block behind the actor has a solid side toward it.
      if (!lvl.isFaceSturdy(pos.relative(facing.opposite), facing)) {
        await e.targetWorld.setBlockByName(
          pos: e.pos,
          name: 'minecraft:air',
          updateFlags: BlockUpdateFlags.normal,
        );
        return;
      }
    }
    await behavior?.onPlaced?.call(server, e);
  }

  FutureOr<int?> updateShape(Server server, CustomBlockUpdateShapeEventData e) {
    final props = block.stateOf(e.stateIndex);
    updateWater(e.targetWorld, e.pos.toPos(), BState(block.key, props));
    return behavior?.onUpdateShape?.call(server, e);
  }

  block = manifestBlock(
    key,
    blockEntityType: blockEntityType,
    placement: const [
      PlacementRule.lookingDirection('facing', opposite: true),
      PlacementRule.inWater('waterlogged'),
    ],
    collisionShape: const BlockShape.boxes([BlockBox(0, 0, 0, 1, 1, 1)]),
    selectionShape: shape,
    shapeRules: rules,
    tags: tags,
    drops: drops,
    behavior: _merge(
      BlockBehavior(
        onPlaced: placed,
        onUpdateShape: updateShape,
        isPathfindable: (server, e) => false,
      ),
      behavior,
    ),
  );
  return block;
}

/// [user]'s hooks win; the hooks of [base] fill the gaps.
BlockBehavior _merge(BlockBehavior base, BlockBehavior? user) {
  if (user == null) return base;
  return BlockBehavior(
    onNeighborUpdate: user.onNeighborUpdate ?? base.onNeighborUpdate,
    onPlaced: base.onPlaced ?? user.onPlaced,
    onStateReplaced: user.onStateReplaced ?? base.onStateReplaced,
    onBroken: user.onBroken ?? base.onBroken,
    onScheduledTick: user.onScheduledTick ?? base.onScheduledTick,
    onRandomTick: user.onRandomTick ?? base.onRandomTick,
    onEntityCollision: user.onEntityCollision ?? base.onEntityCollision,
    onEntityStep: user.onEntityStep ?? base.onEntityStep,
    onCanPlace: user.onCanPlace ?? base.onCanPlace,
    onUpdateShape: base.onUpdateShape ?? user.onUpdateShape,
    onWeakPower: user.onWeakPower ?? base.onWeakPower,
    onStrongPower: user.onStrongPower ?? base.onStrongPower,
    onComparatorOutput: user.onComparatorOutput ?? base.onComparatorOutput,
    onShape: user.onShape ?? base.onShape,
    onUse: user.onUse ?? base.onUse,
    onUseWithItem: user.onUseWithItem ?? base.onUseWithItem,
    onUseWithoutItem: user.onUseWithoutItem ?? base.onUseWithoutItem,
    onAttack: user.onAttack ?? base.onAttack,
    onCloneItem: user.onCloneItem ?? base.onCloneItem,
    onPlayerWillDestroy: user.onPlayerWillDestroy ?? base.onPlayerWillDestroy,
    onFriction: user.onFriction ?? base.onFriction,
    onSpeedFactor: user.onSpeedFactor ?? base.onSpeedFactor,
    onJumpFactor: user.onJumpFactor ?? base.onJumpFactor,
    canEntityDestroy: user.canEntityDestroy ?? base.canEntityDestroy,
    isPathfindable: user.isPathfindable ?? base.isPathfindable,
    canConnectRedstone: user.canConnectRedstone ?? base.canConnectRedstone,
    onLandedUpon: user.onLandedUpon ?? base.onLandedUpon,
    soundType: user.soundType ?? base.soundType,
    onFireSpread: user.onFireSpread ?? base.onFireSpread,
    redstoneOutput: user.redstoneOutput || base.redstoneOutput,
    comparatorOutput: user.comparatorOutput || base.comparatorOutput,
    priority: user.priority,
  );
}
