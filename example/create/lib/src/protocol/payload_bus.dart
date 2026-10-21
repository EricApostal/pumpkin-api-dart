// The payload bus: the one object other modules use to send and handle any of
// Create's payloads with plain Dart maps. Provided as a service
// (`ctx.services.require<PayloadBus>()`). Host glue over `PayloadHub`.
import 'dart:async';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import 'payload_hub.dart';

/// What a single send to one player did (see [PayloadBus._sendAll]).
enum _Delivery { delivered, unsupported, failed }

/// Players that are online, held as handles the plugin owns.
///
/// A `Player` an event carries dies with the callback that received it: when the plugin hands the
/// event back, the host takes ownership of that handle, so the Dart wrapper is invalidated
/// (`ownership was transferred to the host` on the next use) and `keep()` cannot save it — the
/// entry is gone from the host's table whether or not it was kept (`docs/lifetimes.md` of
/// `pumpkin_api`, and `cleanup_event` in the host). A `Player` stored from an event is therefore a
/// *dead* handle whose every call (`getName()`, `getWorld()`, `asJava()`) fails; while those
/// failures were swallowed, a roster of event handles made every broadcast and every
/// `sendToTracking` reach nobody, silently.
///
/// The roster keeps the uuid of each online player and a handle looked up again through
/// `Server.getPlayerByUuid`, which the plugin owns and disposes when the player leaves.
final class PlayerRoster {
  final Map<String, Player> _players = {};

  Iterable<Player> get players => _players.values;
  int get length => _players.length;

  /// Adds the player [eventPlayer] carries, replacing an earlier handle of the same uuid. Only
  /// the uuid is taken from the event. Returns false when the server no longer knows the player.
  bool add(Server server, Player eventPlayer) => _put(server, eventPlayer.getId());

  /// Forgets [player] (an event's player, used for its uuid only).
  void remove(Player player) => _drop(player.getId().asString);

  /// Adds every player the server has online, and forgets the ones that are gone.
  void refresh(Server server) {
    final online = <String>{};
    for (final player in server.getAllPlayers()) {
      final id = player.getId();
      online.add(id.asString);
      _put(server, id, fresh: player);
    }
    for (final key in _players.keys.toList()) {
      if (!online.contains(key)) _drop(key);
    }
  }

  void clear() {
    for (final player in _players.values) {
      try {
        player.dispose();
      } on Object {
        // already invalid
      }
    }
    _players.clear();
  }

  /// Keeps a handle of the player with [id]: [fresh] when the caller already looked it up,
  /// otherwise one from `Server.getPlayerByUuid`.
  bool _put(Server server, Uuid id, {Player? fresh}) {
    final key = id.asString;
    final previous = _players.remove(key);
    final player = fresh ?? server.getPlayerByUuid(id: id);
    if (player == null) {
      previous?.dispose();
      return false;
    }
    _players[key] = player.keep();
    previous?.dispose();
    return true;
  }

  void _drop(String key) {
    final player = _players.remove(key);
    try {
      player?.dispose();
    } on Object {
      // already invalid
    }
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

  /// Sends [id] to every player of [players] (encoded once). A broadcast that reaches fewer
  /// players than it was addressed to is logged; a broadcast that reaches *none* of them is an
  /// error, because that is what a list of handles the host no longer knows looks like.
  void sendClientboundAll(String id, Iterable<Player> players, Map<String, Object?> fields) {
    final bytes = _hub.encodeClientbound(id, fields);
    if (bytes == null) return;
    unawaited(_sendAll(id, players.toList(), bytes));
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
    final tracking = [
      for (final p in roster.players)
        if (_tracks(p, worldId, cx, cz)) p,
    ];
    // Nobody tracking that chunk is normal; a player the roster cannot even ask about is not, and
    // `_tracks` says so.
    if (tracking.isEmpty) return;
    unawaited(_sendAll(id, tracking, bytes));
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
    } on Object catch (e) {
      // A player the roster holds but the host cannot answer about is a broken handle, and the
      // answer used to be a silent "not tracking": every tracking send then reached nobody.
      _hub.log.error(
        'track:$worldId',
        'Could not tell whether ${_who(p)} tracks the chunk ($cx, $cz) of $worldId, '
        'treating it as out of range: $e',
      );
      return false;
    }
  }

  /// Whether one send reached one player, so a broadcast can report what it achieved: [delivered]
  /// reached the client, [unsupported] is a Bedrock player (Create's payloads are Java only) and
  /// [failed] is a handle the host would not answer for or a send that threw.
  Future<_Delivery> _send(String id, Player player, Uint8List bytes) async {
    JavaPlayer? java;
    try {
      java = player.asJava();
    } on Object catch (e) {
      _hub.log.error(
        'sendfail:$id',
        'Could not resolve the Java player for $id (${_who(player)}), nothing was sent: $e',
      );
      return _Delivery.failed;
    }
    if (java == null) {
      // Bedrock players have no custom payloads: not a failure, but not a delivery either.
      _hub.log.debug('send:$id', 'Not sending $id to the Bedrock player ${_who(player)}');
      return _Delivery.unsupported;
    }
    try {
      await java.sendCustomPayload(channel: id, data: bytes);
      return _Delivery.delivered;
    } on Object catch (e) {
      _hub.log.warn('sendfail:$id', 'Could not send $id to ${_who(player)} (player gone?): $e');
      return _Delivery.failed;
    } finally {
      java.dispose();
    }
  }

  /// Sends the encoded [bytes] of payload [id] to [recipients], and says in the log when the
  /// broadcast reached nobody: that must never be a debug-level whisper (see the class comment of
  /// [PlayerRoster]).
  Future<void> _sendAll(String id, List<Player> recipients, Uint8List bytes) async {
    final List<_Delivery> results;
    try {
      results = await Future.wait([for (final p in recipients) _send(id, p, bytes)]);
    } on Object catch (e) {
      // `_send` contains its own failures, so this is a bug on the way to the host. Say it: the
      // future is not awaited by the callers, so an escaping error would vanish.
      _hub.log.error('broadcast:$id', 'Sending $id to ${recipients.length} players failed: $e');
      return;
    }
    final delivered = results.where((r) => r == _Delivery.delivered).length;
    if (delivered == recipients.length) return;
    final failed = results.where((r) => r == _Delivery.failed).length;
    if (failed == 0) {
      // Every recipient is a Bedrock player, which can never receive a Create payload: not an
      // error, and saying it every tick would drown the log.
      _hub.log.debug(
        'broadcast:$id',
        'Sent $id to no one: all ${recipients.length} recipients are Bedrock players',
      );
    } else if (delivered == 0) {
      _hub.log.error(
        'broadcast:$id',
        'Sent $id to none of the ${recipients.length} players it was addressed to: $failed of them '
        'could not be resolved (see the sendfail lines above)',
      );
    } else {
      _hub.log.warn(
        'broadcast:$id',
        'Sent $id to $delivered of ${recipients.length} players, $failed did not get it',
      );
    }
  }

  /// The name of [player] for a log line, without letting a broken handle turn reporting into
  /// another failure.
  String _who(Player player) {
    try {
      return _hub.describePlayer(player);
    } on Object {
      return '<unknown player>';
    }
  }

  /// Decodes the body of payload [id] (for tests and tools). Throws on malformed data.
  Map<String, Object?> decode(String id, Uint8List bytes) => _hub.decode(id, bytes);

  /// Encodes [fields] as the body of payload [id] (for tests and tools). Throws on invalid fields.
  Uint8List encode(String id, Map<String, Object?> fields) => _hub.encode(id, fields);
}
