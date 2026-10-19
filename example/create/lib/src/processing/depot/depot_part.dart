import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart';
import '../../core/module.dart';
import '../processing_part.dart';
import '../processing_runtime.dart';
import 'api.dart';

/// The depot.
///
/// The depot blocks themselves belong to the conveyance module; this part publishes the
/// [DepotApi] the machines of this module use to read and fill a depot. It also handles the
/// serverbound payloads of the weighted ejector (`create:place_ejector`,
/// `create:trigger_ejector`, `create:ejector_elytra`, `create:ejector_award`), which the client
/// sends while it aims and launches.
final class DepotPart extends ProcessingPart {
  @override
  String get name => 'depot';

  @override
  void onLoad(CreateContext ctx, ProcessingRuntime rt) {
    ctx.services.provide<DepotApi>(DepotApi());

    final bus = ctx.services.find<PayloadBus>();
    if (bus == null) return;

    // `EjectorPlacementPacket.handle`: the client picked a target for the ejector at `pos`.
    bus.onServerbound('create:place_ejector', (player, fields) {
      final h = fields['h'];
      final v = fields['v'];
      final facing = fields['facing'];
      if (h is! int || v is! int || facing is! int) return;

      final access = _accessAt(rt, player, fields['pos']);
      if (access == null) return;
      if (access.isEjector) access.setTarget(h, v);
      access.setFacing(facing);
    });

    // `EjectorTriggerPacket.applySettings`: launches on the next tick. It is a
    // `BlockEntityConfigurationPacket`, so the base class validates the player first.
    bus.onServerbound('create:trigger_ejector', (player, fields) {
      final pos = fields['pos'];
      if (pos is! (int, int, int) || !_mayConfigure(player, pos)) return;
      final access = _accessAt(rt, player, pos);
      if (access != null && access.isEjector) access.activate();
    });

    // `EjectorElytraPacket.handle`: the client launched the player; make it glide.
    bus.onServerbound('create:ejector_elytra', (player, fields) {
      final access = _accessAt(rt, player, fields['pos']);
      if (access != null && access.isEjector) access.deployElytra(player);
    });

    // `EjectorAwardPacket.applySettings`: `AllAdvancements.EJECTOR_MAXED` (also a
    // `BlockEntityConfigurationPacket`).
    bus.onServerbound('create:ejector_award', (player, fields) {
      final pos = fields['pos'];
      if (pos is! (int, int, int) || !_mayConfigure(player, pos)) return;
      final access = _accessAt(rt, player, pos);
      if (access != null && access.isEjector) access.awardMaxed(player);
    });
  }

  /// `BlockEntityConfigurationPacket.handle`: spectators and adventure players cannot configure
  /// block entities, and the block must be within the 20 block interaction range.
  bool _mayConfigure(Player player, (int, int, int) pos) {
    final mode = player.getGamemode();
    if (mode == GameMode.spectator || mode == GameMode.adventure) return false;
    final (x, y, z) = player.getPosition();
    final dx = x - (pos.$1 + .5);
    final dy = y - (pos.$2 + .5);
    final dz = z - (pos.$3 + .5);
    return dx * dx + dy * dy + dz * dz <= 20 * 20;
  }

  /// The depot accessor at the `pos` field of a payload, or `null` when the chunk is not loaded
  /// (Java's `world.isLoaded(pos)`) or no depot block is there.
  DepotAccess? _accessAt(ProcessingRuntime rt, Player player, Object? rawPos) {
    if (rawPos is! (int, int, int)) return null;

    final world = player.getWorld();
    try {
      final loaded = world.isLoaded(
        pos: BlockPos(x: rawPos.$1, y: rawPos.$2, z: rawPos.$3),
      );
      if (!loaded) return null;
      final api = rt.services.find<DepotApi>();
      if (api == null) return null;
      return api.accessAt(rt.worlds.touch(world), rawPos);
    } finally {
      world.dispose();
    }
  }
}
