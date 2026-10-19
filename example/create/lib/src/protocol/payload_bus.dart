// The payload bus: the one object other modules use to send and handle any of
// Create's payloads with plain Dart maps. Provided as a service
// (`ctx.services.require<PayloadBus>()`). Host glue over `PayloadHub`.
import 'dart:async';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import 'payload_hub.dart';

/// Players that are online, kept as resources so `sendToTracking` can look at
/// them outside of an event callback (docs/lifetimes.md of pumpkin_api).
final class PlayerRoster {
  final Map<String, Player> _players = {};

  Iterable<Player> get players => _players.values;
  int get length => _players.length;

  /// Keeps [player] (replacing and releasing an earlier handle of the same uuid).
  void add(Player player) {
    final uuid = player.getId().asString;
    final old = _players[uuid];
    if (old != null) {
      try {
        old.dispose();
      } on Object {
        // already invalid
      }
    }
    _players[uuid] = player.keep();
  }

  void remove(Player player) {
    final old = _players.remove(player.getId().asString);
    if (old == null) return;
    try {
      old.dispose();
    } on Object {
      // already invalid
    }
  }

  void refresh(Server server) {
    for (final p in server.getAllPlayers()) {
      final uuid = p.getId().asString;
      if (_players.containsKey(uuid)) {
        p.dispose();
      } else {
        _players[uuid] = p.keep();
      }
    }
  }

  void clear() {
    for (final p in _players.values) {
      try {
        p.dispose();
      } on Object {
        // ignore
      }
    }
    _players.clear();
  }
}

/// Sends and handles Create's payloads (all 119 of the manifest) as
/// `Map<String, Object?>` keyed by the manifest field names. The value kinds are
/// listed in `codec_compiler.dart` (block positions are `(int, int, int)`,
/// uuids are strings, enums are ordinals, ...).
final class PayloadBus {
  final PayloadHub<Player> _hub;
  final PlayerRoster roster;

  /// The default chunk radius of `sendToTracking` when the client's view distance is unknown.
  static const int defaultTrackingRadius = 8;

  PayloadBus(this._hub, this.roster);

  /// Handles the serverbound payload [id] (`create:configure_filter`). [player] is valid
  /// until the handler first yields. Exceptions are caught and logged; invalid or oversized
  /// payloads never reach the handler.
  void onServerbound(String id, void Function(Player player, Map<String, Object?> fields) handler) =>
      _hub.onServerbound(id, handler);

  /// Handles the clientbound payload [id] (`create:mounted_storage_sync`) when this plugin runs
  /// on a client. The handler receives the fields of the payload, decoded like a serverbound one.
  void onClientbound(String id, void Function(Player player, Map<String, Object?> fields) handler) =>
      _hub.onClientbound(id, handler);

  /// Sends the clientbound payload [id] to [player]. Invalid [fields], an oversized payload
  /// or a player that disconnected are logged (rate-limited) and ignored.
  void sendClientbound(String id, Player player, Map<String, Object?> fields) {
    final bytes = _hub.encodeClientbound(id, fields);
    if (bytes != null) unawaited(_send(id, player, bytes));
  }

  /// Sends [id] to every player of [players] (encoded once).
  void sendClientboundAll(String id, Iterable<Player> players, Map<String, Object?> fields) {
    final bytes = _hub.encodeClientbound(id, fields);
    if (bytes == null) return;
    for (final p in players) {
      unawaited(_send(id, p, bytes));
    }
  }

  /// Sends [id] to the players that have the chunk of [pos] in view: same world and within
  /// the player's view distance in chunks (clamped to 2..32, default [defaultTrackingRadius]).
  void sendToTracking(String id, World world, BlockPos pos, Map<String, Object?> fields) =>
      sendToTrackingAt(id, world.getId(), (pos.x, pos.y, pos.z), fields);

  /// Like [sendToTracking] with a world id (`World.getId()`) and a `(x, y, z)` position.
  void sendToTrackingAt(String id, String worldId, (int, int, int) pos, Map<String, Object?> fields) {
    final bytes = _hub.encodeClientbound(id, fields);
    if (bytes == null) return;
    final cx = pos.$1 >> 4, cz = pos.$3 >> 4;
    for (final p in roster.players) {
      if (!_tracks(p, worldId, cx, cz)) continue;
      unawaited(_send(id, p, bytes));
    }
  }

  /// The players of [roster] that track the chunk of [pos] (for modules that send other things).
  List<Player> playersTracking(String worldId, (int, int, int) pos) {
    final cx = pos.$1 >> 4, cz = pos.$3 >> 4;
    return [
      for (final p in roster.players)
        if (_tracks(p, worldId, cx, cz)) p,
    ];
  }

  bool _tracks(Player p, String worldId, int cx, int cz) {
    try {
      final w = p.getWorld();
      final same = w.getId() == worldId;
      w.dispose();
      if (!same) return false;
      final (x, _, z) = p.getPosition();
      var radius = defaultTrackingRadius;
      final java = p.asJava();
      if (java != null) {
        try {
          radius = java.getSettings().viewDistance.clamp(2, 32);
        } on Object {
          // keep the default
        } finally {
          java.dispose();
        }
      }
      return ((x.floor() >> 4) - cx).abs() <= radius && ((z.floor() >> 4) - cz).abs() <= radius;
    } on Object {
      return false; // disconnected or invalid handle
    }
  }

  Future<void> _send(String id, Player player, Uint8List bytes) async {
    try {
      final java = player.asJava();
      if (java == null) return; // Bedrock players have no custom payloads
      try {
        await java.sendCustomPayload(channel: id, data: bytes);
      } finally {
        java.dispose();
      }
    } on Object catch (e) {
      _hub.log.debug('sendfail:$id', 'Could not send $id (player gone?): $e');
    }
  }

  /// Decodes the body of payload [id] (for tests and tools). Throws on malformed data.
  Map<String, Object?> decode(String id, Uint8List bytes) => _hub.decode(id, bytes);

  /// Encodes [fields] as the body of payload [id] (for tests and tools). Throws on invalid fields.
  Uint8List encode(String id, Map<String, Object?> fields) => _hub.encode(id, fields);
}
