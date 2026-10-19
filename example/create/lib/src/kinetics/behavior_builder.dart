// Assembles the `BlockBehavior` of a kinetic block from small callbacks, with
// the shared parts: block entity creation and kinetic state changes on
// placement, and the player placement correction.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/blocks.dart';
import 'block_factory.dart';
import 'geometry.dart';
import 'kinetic_block_entity.dart';
import 'placement.dart';
import 'use_records.dart';
import '../core/perf.dart';
import 'runtime.dart';

/// What a hook knows about the block it is called for.
final class HookCtx {
  /// The server, valid until the callback returns.
  final Server server;
  final KineticsRuntime rt;
  final World world;
  final String worldId;
  final BlockPos pos;
  final CreateBlock block;
  final KState state;

  HookCtx(
    this.server,
    this.rt,
    this.world,
    this.worldId,
    this.pos,
    this.block,
    this.state,
  );

  KPos get kpos => KPos(pos.x, pos.y, pos.z);

  HostKineticLevel get level => rt.level(worldId);

  /// The kinetic block entity here, if any.
  KineticBlockEntity? get be {
    final e = rt.store.at(worldId, pos);
    return e is KineticBlockEntity ? e : null;
  }

  /// A typed block entity.
  T? beOf<T>() {
    final e = rt.store.at(worldId, pos);
    return e is T ? e as T : null;
  }

  Future<void> setState(
    KState s, {
    Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal,
  }) {
    if (flags.contains(BlockFlagsFlag.skipShapeUpdate)) {
      rt.keepKineticInfo.add('$worldId:${kpos.packed}');
    }
    return setKState(rt, world, pos, s, flags: flags);
  }
}

HookCtx makeCtx(
  Server server,
  CreateBlock block,
  World world,
  BlockPos pos,
  int stateIndex,
) {
  final rt = KineticsRuntime.instance;
  final worldId = rt.worlds.touch(world);
  return HookCtx(
    server,
    rt,
    world,
    worldId,
    pos,
    block,
    stateOfEvent(block, stateIndex),
  );
}

/// `ProperWaterloggedBlock.updateShape` (`updateWater`): a waterlogged kinetic
/// block keeps its fluid ticking when a neighbour changes. Returns `null` so the
/// block state stays as it is.
int? waterloggedUpdateShape(HookCtx c, CustomBlockUpdateShapeEventData e) {
  if (c.state.flag('waterlogged')) {
    c.world.scheduleFluidFlow(c.pos, delayTicks: 5);
  }
  return null;
}

/// Builds the behaviour. [blockRef] returns the block this behaviour belongs to
/// (the block is created with the behaviour, so it is looked up lazily).
BlockBehavior buildKineticBehavior(
  CreateBlock Function() blockRef, {
  KineticBlockSpec Function()? specRef,
  FutureOr<void> Function(HookCtx c, CustomBlockNeighborUpdateEventData e)?
  neighbor,
  FutureOr<void> Function(HookCtx c)? scheduledTick,
  int? Function(HookCtx c, CustomBlockUpdateShapeEventData e)? updateShape,
  FutureOr<BlockUseResult> Function(HookCtx c, CustomBlockUseEventData e)? use,
  FutureOr<bool> Function(HookCtx c, CustomBlockCanPlaceEventData e)? canPlace,
  int? Function(HookCtx c)? comparator,
  FutureOr<void> Function(HookCtx c, CustomBlockEntityStepEventData e)?
  entityStep,
  FutureOr<void> Function(HookCtx c, CustomBlockStateReplacedEventData e)?
  replaced,
  FutureOr<void> Function(HookCtx c, CustomBlockPlacedEventData e)? afterPlaced,
  FutureOr<bool> Function(HookCtx c, CustomBlockPlayerWillDestroyEventData e)?
  willDestroy,
  FutureOr<ItemStack?> Function(HookCtx c, CustomBlockCloneItemEventData e)?
  cloneItem,
  bool pathfindable = true,
}) {
  return BlockBehavior(
    onPlaced: (server, e) async {
      final watch = Perf.enabled ? (Stopwatch()..start()) : null;
      final block = blockRef();
      try {
        final c = makeCtx(server, block, e.targetWorld, e.pos, e.stateIndex);
        final be = c.be;
        if (be != null && e.oldStateId != null) {
          final old = c.rt.states.decode(e.oldStateId!);
          final keep = c.rt.keepKineticInfo.remove(
            '${c.worldId}:${c.kpos.packed}',
          );
          applyKineticBlockChange(c.rt, be, old, c.state, keepInfo: keep);
        }
        final playerId = e.player;
        if (playerId != null) {
          be?.queueRotationIndicators(); // KineticBlock.setPlacedBy
          final spec = specRef?.call();
          final fix = spec?.placement;
          if (fix != null) await _placementFix(server, c, e, playerId, fix);
        }
        if (afterPlaced != null) await afterPlaced(c, e);
      } finally {
        if (watch != null) {
          Perf.record('place.kinetic(${block.key})', watch.elapsedMicroseconds);
        }
      }
    },
    onNeighborUpdate: neighbor == null
        ? null
        : (server, e) => neighbor(
            makeCtx(server, blockRef(), e.targetWorld, e.pos, e.stateIndex),
            e,
          ),
    onScheduledTick: scheduledTick == null
        ? null
        : (server, e) => scheduledTick(
            makeCtx(server, blockRef(), e.targetWorld, e.pos, e.stateIndex),
          ),
    onUpdateShape: updateShape == null
        ? null
        : (server, e) => updateShape(
            makeCtx(server, blockRef(), e.targetWorld, e.pos, e.stateIndex),
            e,
          ),
    onUse: use == null
        ? null
        : (server, e) => use(
            makeCtx(server, blockRef(), e.targetWorld, e.pos, e.stateIndex),
            e,
          ),
    onCanPlace: canPlace == null
        ? null
        : (server, e) => canPlace(
            makeCtx(server, blockRef(), e.targetWorld, e.pos, e.stateIndex),
            e,
          ),
    onComparatorOutput: comparator == null
        ? null
        : (server, e) => comparator(
            makeCtx(server, blockRef(), e.targetWorld, e.pos, e.stateIndex),
          ),
    onEntityStep: entityStep == null
        ? null
        : (server, e) => entityStep(
            makeCtx(server, blockRef(), e.targetWorld, e.pos, e.stateIndex),
            e,
          ),
    onStateReplaced: replaced == null
        ? null
        : (server, e) => replaced(
            makeCtx(server, blockRef(), e.targetWorld, e.pos, e.oldStateIndex),
            e,
          ),
    onPlayerWillDestroy: willDestroy == null
        ? null
        : (server, e) => willDestroy(
            makeCtx(server, blockRef(), e.targetWorld, e.pos, e.stateIndex),
            e,
          ),
    onCloneItem: cloneItem == null
        ? null
        : (server, e) => cloneItem(
            makeCtx(server, blockRef(), e.targetWorld, e.pos, e.stateIndex),
            e,
          ),
    isPathfindable: pathfindable ? null : (server, e) => false,
  );
}

Future<void> _placementFix(
  Server server,
  HookCtx c,
  CustomBlockPlacedEventData e,
  Uuid playerId,
  FutureOr<KState> Function(
    PlacementContext ctx,
    KState placed,
    UseRecord? use,
    World world,
  )
  fix,
) async {
  final player = server.getPlayerByUuid(id: playerId);
  if (player == null) return;
  final record = c.rt.useRecords.matching(playerId.asString, c.pos);
  final yaw = player.getYaw();
  final pitch = player.getPitch();
  final level = c.level;
  final clickedFace = record?.face ?? clickedFaceForPlacedState(c.state);
  final ctx = PlacementContext(
    pos: c.kpos,
    clickedFace: clickedFace,
    nearestLooking: nearestLookingDirection(yaw, pitch),
    horizontal: horizontalDirection(yaw),
    sneaking: record?.sneaking ?? player.asEntity().isSneaking(),
    stateAt: level.stateAt,
    blocks: c.rt.blocks,
  );
  final fixed = await fix(ctx, c.state, record, c.world);
  if (fixed != c.state) {
    await c.setState(fixed);
  }
}
