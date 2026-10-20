// `PloughMovementBehaviour`: the mechanical plough breaks the blocks it runs into and hoes the
// ground below it with a fake player holding a diamond hoe.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import '../../../api/block_state.dart';
import '../../../common/common.dart';
import '../../../common/host_bridge.dart';
import '../../core/level.dart';
import '../../core/movement.dart';
import '../actor_runtime.dart';
import '../block_breaking_movement_behaviour.dart';
import 'plough_block.dart';

/// `PloughMovementBehaviour`.
final class PloughMovementBehaviour extends BlockBreakingMovementBehaviour {
  const PloughMovementBehaviour();

  @override
  bool isActive(MovementContext context) {
    final facing = context.state.dir('facing') ?? Direction.north;
    return super.isActive(context) &&
        !VecHelper.isVecPointingTowards(
          context.relativeMotion,
          facing.opposite,
        );
  }

  @override
  Vec3 getActiveAreaOffset(MovementContext context) {
    final facing = context.state.dir('facing') ?? Direction.north;
    return facing.unitVec3 * .45;
  }

  @override
  bool throwsEntities(World world) => true;

  @override
  Future<void> visitNewPosition(MovementContext context, Pos pos) async {
    await super.visitNewPosition(context, pos);
    final world = actors?.worldOf(context);
    if (world == null) return;
    final below = pos.below;
    if (!context.level.isLoaded(below)) return;

    final player = getPlayer(context, world);
    if (player == null) return;

    // `player.getMainHandItem().useOn(ctx)` on a downward ray: hoe the block below's top face.
    await player.useItemOnBlock(below.toBlockPos(), BlockDirection.up);
  }

  @override
  bool canBreak(ContraptionLevel level, Pos breakingPos, BState state) {
    if (state.isAir) return false;
    if (level.stateAt(breakingPos.below).key == 'minecraft:farmland')
      return false;
    if (state.key == 'minecraft:water' || state.key == 'minecraft:lava')
      return false;
    if (state.key == 'minecraft:bubble_column') return false;
    if (state.key == 'create:track') return true;
    if (state.key == 'create:fake_track') return false;
    if (level.stateHasTag(state, 'create:plough_blacklist')) return false;
    if (level.stateHasTag(state, 'create:plough_whitelist')) return true;
    return level.stateCollisionEmpty(state);
  }

  @override
  Future<void> onBlockBroken(
    MovementContext context,
    Pos pos,
    BState brokenState,
  ) async {
    await super.onBlockBroken(context, pos, brokenState);
    if (brokenState.key != 'minecraft:snow') return;
    final world = actors?.worldOf(context);
    if (world == null) return;
    final shovel = ItemStack.create(
      registryKey: 'minecraft:iron_shovel',
      count: 1,
    );
    try {
      final drops = await world.getBlockDrops(
        pos: pos.toBlockPos(),
        tool: shovel,
      );
      for (final stack in drops) {
        await collectOrDropHost(context, stack);
      }
    } finally {
      shovel.dispose();
    }
  }

  @override
  Future<void> stopMoving(MovementContext context) async {
    await super.stopMoving(context);
    final player = context.temporaryData;
    if (player is Player) {
      try {
        FakePlayers.remove(player);
      } on Object {
        // already gone
      }
      try {
        player.dispose();
      } on Object {
        // already released
      }
    }
    context.temporaryData = null;
  }

  /// `getPlayer`: the plough's fake player, holding an (unbreakable) diamond hoe.
  Player? getPlayer(MovementContext context, World world) {
    final existing = context.temporaryData;
    if (existing is Player) return existing;
    // The player outlives this call (`temporaryData` is kept until `stopMoving`), so it must be
    // owned; without `keep()` the host releases it when the callback returns and every later use
    // throws "This Entity is no longer valid (disposed)". `FakePlayers.remove` releases it.
    final player = createPloughFakePlayer(world).keep();
    final hoe = ItemStack.create(
      registryKey: 'minecraft:diamond_hoe',
      count: 1,
    );
    // Items assigned to the inventory are consumed.
    final inventory = player.getInventory();
    inventory.storage[inventory.selectedSlot] = hoe;
    context.temporaryData = player;
    return player;
  }
}
