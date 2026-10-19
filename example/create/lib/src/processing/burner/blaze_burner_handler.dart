// `BlazeBurnerHandler`: a thrown egg that hits a blaze burner is eaten by it and feeds the
// burner (`content/processing/burner/BlazeBurnerHandler.java`).
//
// The Java class also extinguishes lit burners when a water splash potion breaks on them. The
// host's projectile-hit event carries no item stack and the projectile entity exposes none, so
// the port cannot tell a water potion from any other potion; that half is not ported.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/module.dart';
import '../processing_runtime.dart';
import 'blaze_burner_block_entity.dart';

/// The server-side blaze burner projectile handler.
abstract final class BlazeBurnerHandler {
  /// `onThrowableImpact`: installs the projectile intercept.
  static void install(CreateContext ctx) {
    ctx.host.intercept(Events.projectileHit, _onProjectileHit);
  }

  static ProjectileHitEventData _onProjectileHit(
    Server server,
    ProjectileHitEventData e,
  ) {
    if (e.cancelled) return e;
    final hit = e.hitBlockPos;
    if (hit == null) return e;
    if (!ProcessingRuntime.isLoaded) return e;

    // The event does not carry the world; entity ids are unique across the server, so the
    // projectile is in exactly one of the loaded worlds.
    for (final world in server.getAllWorlds()) {
      final entity = world.getEntityById(id: e.entityId);
      if (entity == null) {
        world.dispose();
        continue;
      }
      try {
        if (entity.getType() != EntityType.egg) return e;
        final rt = ProcessingRuntime.instance;
        final worldId = rt.worlds.touch(world);
        final burner = rt.store.typed<BlazeBurnerBlockEntity>(worldId, hit);
        if (burner == null) return e;

        entity.setVelocity(velocity: (0, 0, 0));
        entity.remove();

        if (!burner.isCreative && burner.activeFuel != FuelType.special) {
          burner.activeFuel = FuelType.normal;
          burner.remainingBurnTime = (burner.remainingBurnTime + 80)
              .clamp(0, BlazeBurnerBlockEntity.maxHeatCapacity)
              .toInt();
          burner.updateBlockState();
          burner.sendData();
        }

        world.playCustomSound(
          soundName: 'create:blaze_munch',
          category: SoundCategory.blocks,
          pos: (hit.x + .5, hit.y + .5, hit.z + .5),
          volume: 1,
          pitch: 1,
        );
        return e.cancel();
      } finally {
        entity.dispose();
        world.dispose();
      }
    }
    return e;
  }
}
