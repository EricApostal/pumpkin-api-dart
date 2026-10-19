// `MountedDispenseBehavior` and its reusable variants (host-touching): what a dispenser on a
// contraption does with one item. The base interface and the default behavior live in the
// contraptions module (`contraptions/behaviours/dispenser/`); this file is the public API entry
// point and adds the optional and projectile variants.
//
// Java's `MountedProjectileDispenseBehavior.of(vanillaBehaviour)` wraps a vanilla
// `ProjectileDispenseBehavior`; the host does not expose those, so a ported item behavior
// implements [MountedProjectileDispenseBehaviour.getProjectile] itself.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../common/common.dart';
import '../../../common/host_bridge.dart';
import '../../../contraptions/actors/actor_runtime.dart';
import '../../../contraptions/behaviours/dispenser/mounted_dispense_behaviour.dart';
import '../../../contraptions/core/movement.dart';
import '../../../contraptions/storage/stacks.dart';

export '../../../contraptions/behaviours/dispenser/mounted_dispense_behaviour.dart'
    show MountedDispenseBehaviour, DefaultMountedDispenseBehaviour;

/// `DefaultMountedDispenseBehavior.dispense`'s container branch: a container in front of the
/// dispenser takes one item (`HopperBlockEntity.getContainerAt` + `addItem`).
Future<bool> _containerTakesItem(
  World world,
  Pos pos,
  Direction closest,
  StoredStack stack,
) async {
  final handler = ItemHandlers.at(
    world,
    pos.relative(closest).toBlockPos(),
    side: closest.opposite.toHost(),
  );
  if (handler == null) return false;
  final item = ItemStack.create(registryKey: stack.item, count: 1);
  try {
    final remainder = await handler.insertStack(item);
    return remainder == null;
  } finally {
    item.dispose();
  }
}

/// `OptionalMountedDispenseBehavior`: a behavior that may fail, playing the empty sound then.
///
/// [doExecute] returns the remainder after dispensing one item, or `null` when it failed. The
/// default implementation dispenses the item into the world like the default behavior does.
abstract class OptionalMountedDispenseBehaviour
    implements MountedDispenseBehaviour {
  const OptionalMountedDispenseBehaviour();

  /// `doExecute(stack, context, pos, facing)`: the remainder, or `null` on failure.
  Future<StoredStack?> doExecute(
    StoredStack stack,
    MovementContext context,
    Pos pos,
    Vec3 facing,
  ) async {
    final world = actors?.worldOf(context);
    if (world == null) return null;
    final toDispense = stack.shrink(1);
    await DefaultMountedDispenseBehaviour.spawnItem(
      context,
      world,
      toDispense,
      6,
      facing,
      pos,
    );
    return toDispense;
  }

  @override
  Future<StoredStack> dispense(
    StoredStack stack,
    MovementContext context,
    Pos pos,
  ) async {
    final world = actors?.worldOf(context);
    if (world == null) return stack;
    final normal = MountedDispenseBehaviour.getDispenserNormal(context);
    final closest = MountedDispenseBehaviour.getClosestFacingDirection(normal);
    if (await _containerTakesItem(world, pos, closest, stack)) {
      return stack.shrink(1);
    }
    final remainder = await doExecute(stack, context, pos, normal);
    if (remainder == null) {
      // `LevelEvent.SOUND_DISPENSER_FAIL`.
      world.playCustomSound(
        soundName: 'minecraft:block.dispenser.fail',
        category: SoundCategory.blocks,
        pos: pos.center,
        volume: 1,
        pitch: 1,
      );
      return stack;
    }
    world.playCustomSound(
      soundName: 'minecraft:block.dispenser.dispense',
      category: SoundCategory.blocks,
      pos: pos.center,
      volume: 1,
      pitch: 1,
    );
    return remainder;
  }
}

/// `MountedProjectileDispenseBehavior`: shoots a projectile in the facing of the dispenser.
abstract class MountedProjectileDispenseBehaviour
    implements MountedDispenseBehaviour {
  const MountedProjectileDispenseBehaviour();

  /// `getProjectile(level, x, y, z, stack, facing)`: spawns the projectile at [position] and
  /// returns it, or `null` when the item cannot be shot. The behavior then gives it [power] and
  /// the motion of the contraption.
  Future<Entity?> getProjectile(
    World world,
    Vec3 position,
    StoredStack stack,
    Direction facing,
  );

  /// `getUncertainty`.
  double get uncertainty => 6;

  /// `getPower`.
  double get power => 1.1;

  @override
  Future<StoredStack> dispense(
    StoredStack stack,
    MovementContext context,
    Pos pos,
  ) async {
    final world = actors?.worldOf(context);
    if (world == null) return stack;
    final normal = MountedDispenseBehaviour.getDispenserNormal(context);
    final closest = MountedDispenseBehaviour.getClosestFacingDirection(normal);
    if (await _containerTakesItem(world, pos, closest, stack)) {
      return stack.shrink(1);
    }
    return _execute(stack, context, world, pos, normal);
  }

  /// `DefaultMountedDispenseBehavior.execute` overridden for projectiles.
  Future<StoredStack> _execute(
    StoredStack stack,
    MovementContext context,
    World world,
    Pos pos,
    Vec3 facing,
  ) async {
    final position = (
      pos.$1 + facing.$1 * .7 + .5,
      pos.$2 + facing.$2 * .7 + .5,
      pos.$3 + facing.$3 * .7 + .5,
    );
    final direction = MountedDispenseBehaviour.getClosestFacingDirection(
      facing,
    );
    final projectile = await getProjectile(
      world,
      position,
      stack.copyWithCount(1),
      direction,
    );
    if (projectile == null) return stack;
    // `Projectile.shoot(x, y, z, speed, uncertainty)`: the direction gets triangular noise,
    // then the motion keeps the speed it had in the facing of the dispenser.
    final motion = (
      facing.$1 * power + context.motion.$1,
      facing.$2 * power + context.motion.$2,
      facing.$3 * power + context.motion.$3,
    );
    final speed = motion.length;
    double noise() =>
        (actorRandom.nextDouble() - actorRandom.nextDouble()) *
        0.0172275 *
        uncertainty;
    final shot = (
      motion.$1 + noise(),
      motion.$2 + noise(),
      motion.$3 + noise(),
    );
    projectile.setVelocity(velocity: shot.normalized * speed);
    // `LevelEvent.SOUND_DISPENSER_PROJECTILE_LAUNCH`.
    world.playCustomSound(
      soundName: 'minecraft:block.dispenser.launch',
      category: SoundCategory.blocks,
      pos: pos.center,
      volume: 1,
      pitch: 1.2,
    );
    return stack.shrink(1);
  }
}
