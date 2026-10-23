// Hands Aeronautics' physics data to the component that owns the sub-levels.
//
// Java reads one global property registry and one global material table for the
// whole server: Sable fills both with a `SimpleJsonResourceReloadListener` over
// `physics_block_properties/**` and `floating_materials/**`, and *every* enabled
// pack contributes, so `data/aeronautics/physics_block_properties/levitite.json`
// gives `#aeronautics:levitite` the material `aeronautics:levitite` and levitite
// floats.
//
// A Pumpkin plugin cannot read datapack files, and the sub-levels are ticked in
// the `sable` component (which owns the containers; see "Cross-plugin
// ownership" in `example/sable/docs/sable-core-port.md`), so the entries are
// read from this component's **embedded** copy of its pack
// ([AeronauticsPhysicsData]) and pushed over the operation channel
// (`package:sable/src/plugin/sable_sub_level_api.dart`, op `physicsData`).
// Without the push the component that ticks a levitite assembly has no
// `aeronautics:levitite` material and no definition naming it, so the blocks
// resolve to `null` and simply do not float -- which is what "levitite falls
// like stone" was.
//
// Host: this file uses `pumpkin_api` (IPC) and the `sable` package.
// ignore_for_file: implementation_imports
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/src/plugin/sable_sub_level_api.dart'
    show SableSubLevelOps, sableSubLevelChannel;

import '../data/aeronautics_physics_data.dart';

/// The push itself.
abstract final class SablePhysicsPush {
  /// The plugin that owns the sub-level containers.
  ///
  /// There is one Sable plugin and it links the solver, so the address is a
  /// constant rather than a probed value (see "Cross-plugin ownership" in
  /// `example/sable/docs/sable-core-port.md`).
  static const String ownerPlugin = 'sable';

  /// The channel of the operation, the same object the owner registers.
  static const IpcChannel<Map<String, Object?>> channel = sableSubLevelChannel;

  /// Sends the embedded physics data to the component that owns the sub-levels.
  ///
  /// Returns the owner's reply, or `null` when nothing answered. A server
  /// without the `sable` plugin has no sub-levels, so a failure here is not an
  /// error on its own; the caller logs what comes back.
  static Future<Map<String, Object?>?> send({
    required Logger log,
    AeronauticsPhysicsData? data,
  }) async {
    final physics = data ?? AeronauticsPhysicsData.fromEmbeddedPack();
    if (physics.isEmpty) {
      log.warn('Aeronautics: the embedded pack carries no physics data to send.');
      return null;
    }

    const plugin = ownerPlugin;
    try {
      final reply = await channel.request(plugin, {
        'op': SableSubLevelOps.physicsData,
        'materials': physics.materials,
        'properties': physics.properties,
      });
      final payload = reply is Map
          ? {for (final entry in reply.entries) '${entry.key}': entry.value}
          : const <String, Object?>{};
      if (payload['ok'] == true) {
        final definitions = physics.properties.length;
        log.info(
          'Aeronautics: sent ${physics.materials.length} floating material(s) and '
          '$definitions physics block propert${definitions == 1 ? 'y' : 'ies'} to $plugin.',
        );
      } else {
        log.warn('Aeronautics: $plugin rejected the physics data: ${payload['error']}');
      }
      return payload;
    } on Object catch (error) {
      log.warn('Aeronautics: could not send the physics data to $plugin: $error');
      return null;
    }
  }
}