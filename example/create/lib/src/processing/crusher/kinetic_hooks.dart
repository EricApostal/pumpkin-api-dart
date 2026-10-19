// `buildKineticBehavior` (`lib/src/kinetics/behavior_builder.dart`) assembles the shared hooks of
// a kinetic block but does not take the entity hooks. The crushing wheel needs `entityInside`
// (`onEntityCollision`) and the millstone needs `fallOn` (`onLandedUpon`); this copies the built
// behaviour and adds them, so the shared kinetic part (state changes on placement, placement
// correction) is not duplicated. Used by the crusher and the millstone part.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

BlockBehavior kineticBehaviorWith(
  BlockBehavior base, {
  FutureOr<void> Function(
    Server server,
    CustomBlockEntityCollisionEventData event,
  )?
  onEntityCollision,
  FutureOr<double> Function(Server server, CustomBlockLandedEventData event)?
  onLandedUpon,
}) => BlockBehavior(
  onNeighborUpdate: base.onNeighborUpdate,
  onPlaced: base.onPlaced,
  onStateReplaced: base.onStateReplaced,
  onBroken: base.onBroken,
  onScheduledTick: base.onScheduledTick,
  onRandomTick: base.onRandomTick,
  onEntityCollision: onEntityCollision ?? base.onEntityCollision,
  onEntityStep: base.onEntityStep,
  onCanPlace: base.onCanPlace,
  onUpdateShape: base.onUpdateShape,
  onWeakPower: base.onWeakPower,
  onStrongPower: base.onStrongPower,
  onComparatorOutput: base.onComparatorOutput,
  onShape: base.onShape,
  onUse: base.onUse,
  onUseWithItem: base.onUseWithItem,
  onUseWithoutItem: base.onUseWithoutItem,
  onAttack: base.onAttack,
  onCloneItem: base.onCloneItem,
  onPlayerWillDestroy: base.onPlayerWillDestroy,
  onFriction: base.onFriction,
  onSpeedFactor: base.onSpeedFactor,
  onJumpFactor: base.onJumpFactor,
  canEntityDestroy: base.canEntityDestroy,
  isPathfindable: base.isPathfindable,
  canConnectRedstone: base.canConnectRedstone,
  onLandedUpon: onLandedUpon ?? base.onLandedUpon,
  soundType: base.soundType,
  onFireSpread: base.onFireSpread,
  redstoneOutput: base.redstoneOutput,
  comparatorOutput: base.comparatorOutput,
  priority: base.priority,
);

/// Rebuilds [base] with the entity-aware collision shape added
/// (`CrushingWheelControllerBlock.getCollisionShape`: empty for the entity being crushed and
/// for an output item that this controller ejected, so it does not fall back through).
BlockBehavior withEntityCollisionShape(
  BlockBehavior base,
  FutureOr<List<BlockBox>?> Function(
    Server server,
    CustomBlockCollisionShapeEventData event,
  )
  onEntityCollisionShape,
) => BlockBehavior(
  onNeighborUpdate: base.onNeighborUpdate,
  onPlaced: base.onPlaced,
  onStateReplaced: base.onStateReplaced,
  onBroken: base.onBroken,
  onScheduledTick: base.onScheduledTick,
  onRandomTick: base.onRandomTick,
  onEntityCollision: base.onEntityCollision,
  onEntityStep: base.onEntityStep,
  onCanPlace: base.onCanPlace,
  onUpdateShape: base.onUpdateShape,
  onWeakPower: base.onWeakPower,
  onStrongPower: base.onStrongPower,
  onComparatorOutput: base.onComparatorOutput,
  onShape: base.onShape,
  onEntityCollisionShape: onEntityCollisionShape,
  onUse: base.onUse,
  onUseWithItem: base.onUseWithItem,
  onUseWithoutItem: base.onUseWithoutItem,
  onAttack: base.onAttack,
  onCloneItem: base.onCloneItem,
  onPlayerWillDestroy: base.onPlayerWillDestroy,
  onFriction: base.onFriction,
  onSpeedFactor: base.onSpeedFactor,
  onJumpFactor: base.onJumpFactor,
  canEntityDestroy: base.canEntityDestroy,
  isPathfindable: base.isPathfindable,
  canConnectRedstone: base.canConnectRedstone,
  onLandedUpon: base.onLandedUpon,
  soundType: base.soundType,
  onFireSpread: base.onFireSpread,
  redstoneOutput: base.redstoneOutput,
  comparatorOutput: base.comparatorOutput,
  priority: base.priority,
);
