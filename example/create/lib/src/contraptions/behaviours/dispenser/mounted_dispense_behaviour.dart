// `MountedDispenseBehavior` and `DefaultMountedDispenseBehavior` (pure + the item drop of the
// default): what a dispenser on a contraption does with one item. Blocks with a special item
// (buckets, projectiles, ...) register a behaviour for the item key; everything else uses the
// default.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../common/common.dart';
import '../../../common/host_bridge.dart';
import '../../core/movement.dart';
import '../../storage/stacks.dart';
import '../../actors/actor_runtime.dart';

/// `MountedDispenseBehavior`.
abstract interface class MountedDispenseBehaviour {
  /// `REGISTRY`: the behaviour per item key (`minecraft:arrow`), by registration.
  static final Map<String, MountedDispenseBehaviour> registry = {};

  static void register(String itemKey, MountedDispenseBehaviour behaviour) =>
      registry[itemKey] = behaviour;

  static MountedDispenseBehaviour? of(String itemKey) => registry[itemKey];

  /// `dispense`: returns the remainder of the stack after dispensing one item.
  Future<StoredStack> dispense(
    StoredStack stack,
    MovementContext context,
    Pos pos,
  );

  /// `getDispenserNormal`: the facing of the dispenser in world space.
  static Vec3 getDispenserNormal(MovementContext context) {
    final facing = context.state.dir('facing') ?? Direction.north;
    return context.rotation(facing.unitVec3).normalized;
  }

  /// `getClosestFacingDirection`.
  static Direction getClosestFacingDirection(Vec3 facing) =>
      Direction.nearest(facing.$1, facing.$2, facing.$3);

  /// `placeItemInInventory`: the dispenser inventory first, then the contraption's, then the world.
  static Future<void> placeItemInInventory(
    StoredStack stack,
    MovementContext context,
    Pos pos,
  ) async {
    if (stack.isEmpty) return;
    final own = context.itemStorage;
    if (own != null) {
      final remainder = ItemSlotsHelper.insert(own, stack);
      if (remainder.isEmpty) return;
      stack = remainder;
    }
    final contraption = context.contraption.storage.allItems;
    final remainder = ItemSlotsHelper.insert(contraption, stack);
    if (remainder.isEmpty) return;
    await const DefaultMountedDispenseBehaviour().dispense(
      remainder,
      context,
      pos,
    );
  }
}

/// `DefaultMountedDispenseBehavior`.
final class DefaultMountedDispenseBehaviour
    implements MountedDispenseBehaviour {
  const DefaultMountedDispenseBehaviour();

  static const MountedDispenseBehaviour instance =
      DefaultMountedDispenseBehaviour();

  @override
  Future<StoredStack> dispense(
    StoredStack stack,
    MovementContext context,
    Pos pos,
  ) async {
    if (stack.isEmpty) return stack;
    final world = actors?.worldOf(context);
    if (world == null) return stack;
    final normal = MountedDispenseBehaviour.getDispenserNormal(context);
    final closest = MountedDispenseBehaviour.getClosestFacingDirection(normal);

    // `HopperBlockEntity.getContainerAt`: a container in front of the dispenser takes the item.
    final handler = ItemHandlers.at(
      world,
      pos.relative(closest).toBlockPos(),
      side: closest.opposite.toHost(),
    );
    if (handler != null) {
      final item = ItemStack.create(registryKey: stack.item, count: 1);
      try {
        final remainder = await handler.insertStack(item);
        if (remainder == null) return stack.shrink(1);
      } finally {
        item.dispose();
      }
      return stack;
    }

    final toDispense = stack.shrink(1);
    await spawnItem(context, world, toDispense, 6, normal, pos);
    world.playCustomSound(
      soundName: 'minecraft:block.dispenser.dispense',
      category: SoundCategory.blocks,
      pos: pos.center,
      volume: 1,
      pitch: 1,
    );
    return toDispense;
  }

  /// `DefaultMountedDispenseBehavior.spawnItem`.
  static Future<void> spawnItem(
    MovementContext context,
    World world,
    StoredStack stack,
    int speed,
    Vec3 facing,
    Pos pos,
  ) async {
    final closest = MountedDispenseBehaviour.getClosestFacingDirection(facing);
    var y = pos.$2 + facing.$2 + .5;
    y = closest.axis == Axis.y ? y - 0.125 : y - 0.15625;
    final position = (pos.$1 + facing.$1 + .5, y, pos.$3 + facing.$3 + .5);
    final d3 = actorRandom.nextDouble() * 0.1 + 0.2;
    double gauss() =>
        (actorRandom.nextDouble() + actorRandom.nextDouble() - 1) *
        math.sqrt(6);
    final velocity = (
      gauss() * 0.0075 * speed + facing.$1 * d3 + context.motion.$1,
      gauss() * 0.0075 * speed + facing.$2 * d3 + context.motion.$2,
      gauss() * 0.0075 * speed + facing.$3 * d3 + context.motion.$3,
    );
    await dropStoredStack(world, position, stack, velocity: velocity);
  }
}
