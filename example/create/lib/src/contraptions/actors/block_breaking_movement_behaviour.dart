// `BlockBreakingMovementBehaviour` (the kinetics base of the plough and the roller): actors that
// grind through blocks when the contraption moves them into a block. Progress is kept in the
// actor's data; the host has no per-block break progress overlay, so the block is broken once the
// accumulated progress reaches the threshold.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../core/level.dart';
import '../core/movement.dart';
import '../storage/stacks.dart';
import 'actor_runtime.dart';

/// `BlockBreakingKineticBlockEntity.NEXT_BREAKER_ID`.
int _nextBreakerId = 0;

/// `MovementBehaviour.collectOrDropItem`: into the contraption's storage when the config asks for
/// it, the remainder as an item entity at the actor.
Future<void> collectOrDropItem(
  MovementContext context,
  StoredStack stack,
) async {
  if (stack.isEmpty) return;
  var remainder = stack;
  final runtime = actors;
  if (runtime != null && runtime.moveItemsToStorage) {
    remainder = ItemSlotsHelper.insert(
      context.contraption.storage.allItems,
      stack,
    );
    if (remainder.isEmpty) return;
  }
  final world = runtime?.worldOf(context);
  final position = context.position;
  if (world == null || position == null) return;
  final velocity =
      (context.motion + (0.0, 0.5, 0.0)) * (actorRandom.nextDouble() * 0.3);
  await dropStoredStack(world, position, remainder, velocity: velocity);
}

/// `collectOrDropItem` for a host stack from a loot table. The host stack exposes no component
/// serialisation, so the saved stack keeps the item and the count only.
Future<void> collectOrDropHost(MovementContext context, ItemStack stack) async {
  final key = await stack.getRegistryKey();
  final count = await stack.getCount();
  if (count <= 0) return;
  await collectOrDropItem(context, StoredStack(key, count));
}

/// `BlockBreakingMovementBehaviour`.
class BlockBreakingMovementBehaviour extends MovementBehaviour {
  const BlockBreakingMovementBehaviour();

  @override
  bool breaksBlocks() => true;

  @override
  void startMoving(MovementContext context) {
    context.data.putInt('BreakerId', -++_nextBreakerId);
  }

  @override
  Future<void> visitNewPosition(MovementContext context, Pos pos) async {
    final world = actors?.worldOf(context);
    if (world == null) return;
    final stateVisited = context.level.stateAt(pos);

    if (!context.level.isRedstoneConductor(pos))
      await damageEntities(context, pos, world);

    if (!canBreak(context.level, pos, stateVisited)) return;
    context.data.putBlockPos('BreakingPos', pos);
    context.stall = true;
  }

  /// `damageEntities`: hurts living entities the actor runs into and throws them along.
  Future<void> damageEntities(
    MovementContext context,
    Pos pos,
    World world,
  ) async {
    final throws = throwsEntities(world);
    final damageSource = getDamageSourceKey();
    if (damageSource == null && !throws) return;

    for (final snapshot in world.entitiesIn(
      Cuboid.corners(pos, pos),
      filter: const EntityFilterLiving(),
    )) {
      final entity = world.getEntityById(id: snapshot.id);
      if (entity == null) continue;
      final living = entity.asLiving();
      if (living == null) continue;
      if (damageSource != null) {
        final damage = clampInt(
          (6 * math.pow(context.relativeMotion.length, 0.4) + 1).round(),
          2,
          10,
        );
        unawaited(
          living.damageByKey(
            amount: damage.toDouble(),
            damageTypeKey: damageSource,
          ),
        );
      }
      if (throws) throwEntity(context, entity);
    }
  }

  /// `throwEntity`.
  void throwEntity(MovementContext context, Entity entity) {
    var boost = context.motion + (0.0, context.motion.length / 4, 0.0);
    const maxBoost = 4;
    if (boost.length > maxBoost) {
      boost = boost - boost.normalized * (boost.length - maxBoost);
    }
    entity.velocity = entity.velocity + boost;
  }

  /// `getDamageSource`: the damage type key, `null` when the actor does not hurt entities.
  String? getDamageSourceKey() => null;

  /// `throwsEntities`.
  bool throwsEntities(World world) => getDamageSourceKey() != null;

  @override
  void cancelStall(MovementContext context) {
    if (!context.data.contains('BreakingPos')) return;
    context.data.remove('Progress');
    context.data.remove('TicksUntilNextProgress');
    context.data.remove('BreakingPos');
    super.cancelStall(context);
  }

  @override
  Future<void> stopMoving(MovementContext context) async =>
      cancelStall(context);

  @override
  Future<void> tick(MovementContext context) async {
    await tickBreaker(context);
    if (!context.data.contains('WaitingTicks')) return;

    var waitingTicks = context.data.getInt('WaitingTicks');
    if (waitingTicks-- > 0) {
      context.data.putInt('WaitingTicks', waitingTicks);
      context.stall = true;
      return;
    }

    final pos = context.data.getBlockPos('LastPos');
    context.data.remove('WaitingTicks');
    context.data.remove('LastPos');
    context.stall = false;
    await visitNewPosition(context, pos);
  }

  /// `tickBreaker`.
  Future<void> tickBreaker(MovementContext context) async {
    final world = actors?.worldOf(context);
    if (world == null) return;
    final data = context.data;
    if (!data.contains('BreakingPos')) {
      context.stall = false;
      return;
    }
    if (context.relativeMotion == vec3Zero) {
      context.stall = false;
      return;
    }

    var ticksUntilNextProgress = data.getInt('TicksUntilNextProgress');
    if (ticksUntilNextProgress-- > 0) {
      data.putInt('TicksUntilNextProgress', ticksUntilNextProgress);
      return;
    }

    var breakingPos = data.getBlockPos('BreakingPos');
    var destroyProgress = data.getInt('Progress');
    var stateToBreak = context.level.stateAt(breakingPos);
    final blockHardness = world
        .getBlock(pos: breakingPos.toBlockPos())
        .hardness;

    if (!canBreak(context.level, breakingPos, stateToBreak)) {
      if (destroyProgress != 0) {
        data.remove('Progress');
        data.remove('TicksUntilNextProgress');
        data.remove('BreakingPos');
      }
      context.stall = false;
      return;
    }

    final breakSpeed = getBlockBreakingSpeed(context);
    final gain = clampInt(
      (breakSpeed / (blockHardness == 0 ? 0.0001 : blockHardness)).toInt(),
      1,
      10 - destroyProgress,
    );
    destroyProgress += gain;

    if (destroyProgress >= 10) {
      // Break falling blocks from top to bottom.
      final originalPos = breakingPos;
      var above = context.level.stateAt(breakingPos.above);
      while (_isFalling(above)) {
        breakingPos = breakingPos.above;
        above = context.level.stateAt(breakingPos.above);
      }
      stateToBreak = context.level.stateAt(breakingPos);

      context.stall = false;
      if (shouldDestroyStartBlock(stateToBreak))
        await destroyBlock(context, breakingPos);
      await onBlockBroken(context, originalPos, stateToBreak);
      data.remove('Progress');
      data.remove('TicksUntilNextProgress');
      data.remove('BreakingPos');
      return;
    }

    ticksUntilNextProgress = (blockHardness / breakSpeed).toInt();
    data.putInt('TicksUntilNextProgress', ticksUntilNextProgress);
    data.putInt('Progress', destroyProgress);
  }

  /// `FallingBlock`: the host has no falling-block interface; the blocks that fall are the
  /// `minecraft:` sand, gravel and concrete powder families.
  static bool _isFalling(BState state) =>
      state.key.startsWith('minecraft:') &&
      (state.key.contains('sand') ||
          state.key == 'minecraft:gravel' ||
          state.key.endsWith('_concrete_powder'));

  /// `destroyBlock`.
  Future<void> destroyBlock(MovementContext context, Pos breakingPos) async {
    final world = actors?.worldOf(context);
    if (world == null) return;
    await BlockHelper.destroyBlockWith(world, breakingPos, 1, (stack) async {
      await collectOrDropHost(context, stack);
    });
  }

  /// `getBlockBreakingSpeed`.
  double getBlockBreakingSpeed(MovementContext context) {
    const lowerLimit = 1 / 128;
    return clampDouble(context.getAnimationSpeed().abs() / 500, lowerLimit, 16);
  }

  /// `shouldDestroyStartBlock`.
  bool shouldDestroyStartBlock(BState stateToBreak) => true;

  /// `canBreak(world, breakingPos, state)`: Java takes the level, not the context, because the
  /// contraption collider asks whether a *moving block* could break the block it runs into
  /// (`ContraptionCollider.isCollidingWithWorld`) before the actor ever ticks.
  bool canBreak(ContraptionLevel level, Pos breakingPos, BState state) {
    if (state.isAir) return false;
    if (level.isUnbreakable(state)) return false;
    if (level.stateHasTag(state, 'create:non_breakable')) return false;
    return true;
  }

  /// `onBlockBroken`: falling blocks above the broken block are broken after a pause.
  Future<void> onBlockBroken(
    MovementContext context,
    Pos pos,
    BState brokenState,
  ) async {
    if (!_isFalling(brokenState)) return;
    context.data.putInt('WaitingTicks', 10);
    context.data.putBlockPos('LastPos', pos);
    context.stall = true;
  }
}
