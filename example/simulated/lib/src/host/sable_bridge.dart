// The bridge that lets the Simulated component reach the Sable component's
// sub-levels.
//
// Simulated links `package:sable` like every other plugin, but a Pumpkin server
// runs each plugin in its own wasm instance, so Sable's `SubLevelContainer`
// static map here is a *different* map from the one the Sable plugin fills. The
// model therefore cannot be read across components; it has to be asked.
//
// `SableSubLevelApi` (`example/sable/lib/src/plugin/sable_sub_level_api.dart`)
// is that ask: an operation channel, addressed to the `sable` plugin, over the
// host's plugin IPC. This file is the caller half:
//
//  * operations that answer ([assemble], [containing], [get], [areaLoaded]) for
//    entry points that can await — `simulated:assemble` is dispatched from an
//    async payload handler, so the assembler awaits the reply;
//  * a **mirror** ([subLevelAt], [subLevelById]) for the callers that cannot
//    await: a block-entity tick or a block callback is synchronous, and an IPC
//    round trip is a `Future`. The mirror is refreshed by Sable's `changed`
//    pushes and is therefore one push behind — never assume it is exact.
//
// Host: this file uses `pumpkin_api`.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

/// One sub-level, as much as another component may know about it.
final class SableSubLevelRef {
  const SableSubLevelRef({
    required this.id,
    required this.position,
    required this.bounds,
    required this.mass,
    required this.plot,
    required this.centerBlock,
  });

  final String id;

  /// The pose position (world coordinates).
  final (double, double, double) position;

  /// The global block bounds `[minX, minY, minZ, maxX, maxY, maxZ]`.
  final (int, int, int, int, int, int) bounds;

  /// The sub-level's mass, or `null` when it has no valid mass tracker.
  final double? mass;

  /// The plot grid coordinates of the plot it lives in.
  final (int, int) plot;

  /// The plot's centre block (`LevelPlot.getCenterBlock`), which is what the
  /// assembly offset is measured from.
  final (int, int, int) centerBlock;

  /// Reads a reference out of the API's reply, or `null` when the reply has
  /// none (`{"subLevel": null}`).
  static SableSubLevelRef? from(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final position = json['position'];
    final bounds = json['bounds'];
    final plot = json['plot'];
    final centerBlock = json['centerBlock'];
    if (id is! String || position is! List || position.length != 3 || bounds is! List || bounds.length != 6) {
      return null;
    }
    return SableSubLevelRef(
      id: id,
      position: (_double(position[0]), _double(position[1]), _double(position[2])),
      bounds: (
        _int(bounds[0]),
        _int(bounds[1]),
        _int(bounds[2]),
        _int(bounds[3]),
        _int(bounds[4]),
        _int(bounds[5]),
      ),
      mass: json['mass'] is num ? (json['mass'] as num).toDouble() : null,
      plot: plot is List && plot.length == 2 ? (_int(plot[0]), _int(plot[1])) : (0, 0),
      centerBlock: centerBlock is List && centerBlock.length == 3
          ? (_int(centerBlock[0]), _int(centerBlock[1]), _int(centerBlock[2]))
          : (0, 0, 0),
    );
  }

  static double _double(Object? value) => value is num ? value.toDouble() : 0.0;

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  @override
  String toString() => 'SableSubLevelRef[$id at $position]';
}

/// The result of one operation: the API's `ok` flag plus its payload.
final class SableReply {
  const SableReply(this.ok, this.payload, [this.error]);

  final bool ok;
  final Map<String, Object?> payload;
  final String? error;

  /// The sub-level in the reply, if it carries one.
  SableSubLevelRef? get subLevel => SableSubLevelRef.from(payload['subLevel']);

  /// Every sub-level in the reply (the `list` / `changed` shape).
  List<SableSubLevelRef> get subLevels => [
    for (final entry in (payload['subLevels'] as List? ?? const []))
      ?SableSubLevelRef.from(entry),
  ];

  @override
  String toString() => ok ? 'SableReply$payload' : 'SableReply.error($error)';
}

/// The caller half of Sable's sub-level operation channel.
///
/// One instance per plugin; [install] registers the push handler and asks Sable
/// to subscribe the plugin, [close] drops it.
final class SableBridge {
  SableBridge(this._log);

  final Logger _log;

  /// The channel name, shared with `SableSubLevelApi`.
  static const String channelName = 'sable.sublevels';

  /// The plugin that owns the containers.
  static const String pluginName = 'sable';

  static const IpcChannel<Map<String, Object?>> _channel =
      IpcChannel<Map<String, Object?>>(channelName, _identity, _asMap);

  /// The mirror, by dimension and id: what a synchronous caller can answer from.
  final Map<String, Map<String, SableSubLevelRef>> _byId = {};

  bool _installed = false;

  /// Whether the bridge has been installed (and Sable answered the subscribe).
  bool get installed => _installed;

  /// Registers the `changed` push handler. Safe to call before Sable loads: the
  /// mirror simply stays empty until the first push.
  void install() {
    if (_installed) return;
    _channel.handle((sender, message) {
      if (message['op'] == 'changed') _absorb(message);
      return null;
    });
    _installed = true;
  }

  bool _subscribed = false;

  /// Asks Sable to push its sub-level changes here.
  ///
  /// Awaited by the plugin's `onLoad` so a failure is visible in the log rather
  /// than a silently empty mirror. The load order of two independent plugins is
  /// not guaranteed, so a failure here is retried by the next [request] instead
  /// of leaving the mirror empty forever.
  Future<void> subscribe() async {
    try {
      await _rawRequest({'op': 'subscribe'});
      _subscribed = true;
      _log.info('Sable bridge: subscribed to the sub-level changes of the sable component.');
    } on Object catch (error) {
      _log.warn('Sable bridge: could not subscribe to the sable plugin yet: $error');
    }
  }

  /// Forgets the mirror (plugin unload).
  void close() {
    _byId.clear();
    _installed = false;
    _subscribed = false;
  }

  // ------------------------------------------------------------- operations

  /// Assembles [blocks] of [world] into a new sub-level at [anchor].
  ///
  /// The work runs inside Sable's component (see the file comment); the block
  /// list is the only thing that crosses. `await` is required: a synchronous
  /// caller (a block-entity tick) must queue its request instead.
  Future<SableReply> assemble({
    required String world,
    required (int, int, int) anchor,
    required List<(int, int, int)> blocks,
    required (int, int, int, int, int, int) bounds,
  }) => _request({
    'op': 'assemble',
    'world': world,
    'anchor': [anchor.$1, anchor.$2, anchor.$3],
    'blocks': [
      for (final block in blocks) [block.$1, block.$2, block.$3],
    ],
    'bounds': [bounds.$1, bounds.$2, bounds.$3, bounds.$4, bounds.$5, bounds.$6],
  });

  /// The sub-level of [world] that contains a block position.
  Future<SableReply> containing(String world, (int, int, int) pos) => _request({
    'op': 'containing',
    'world': world,
    'pos': [pos.$1, pos.$2, pos.$3],
  });

  /// One sub-level by id.
  Future<SableReply> get(String world, String id) =>
      _request({'op': 'get', 'world': world, 'id': id});

  /// Whether every chunk within `range` blocks of `center` is loaded, in Sable's
  /// view of the level (`SimLevelUtil.isAreaActuallyLoaded`).
  Future<SableReply> areaLoaded(String world, (int, int, int) center, int range) => _request({
    'op': 'areaLoaded',
    'world': world,
    'center': [center.$1, center.$2, center.$3],
    'range': range,
  });

  // ---------------------------------------------------------------- the mirror

  /// The sub-level of [dimension] containing [pos], from the mirror.
  ///
  /// Synchronous, and one push behind: a sub-level assembled since the last push
  /// is not in it yet. Use [containing] where the caller can await.
  SableSubLevelRef? subLevelAt(String dimension, (int, int, int) pos) {
    final byId = _byId[dimension];
    if (byId == null) return null;
    for (final ref in byId.values) {
      if (pos.$1 >= ref.bounds.$1 &&
          pos.$1 <= ref.bounds.$4 &&
          pos.$2 >= ref.bounds.$2 &&
          pos.$2 <= ref.bounds.$5 &&
          pos.$3 >= ref.bounds.$3 &&
          pos.$3 <= ref.bounds.$6) {
        return ref;
      }
    }
    return null;
  }

  /// One sub-level of [dimension] by id, from the mirror.
  SableSubLevelRef? subLevelById(String dimension, String id) => _byId[dimension]?[id];

  /// The mirrored sub-levels of [dimension].
  Iterable<SableSubLevelRef> subLevelsOf(String dimension) =>
      _byId[dimension]?.values ?? const [];

  /// Replaces the mirror of the pushed dimension with [message]'s list.
  void _absorb(Map<String, Object?> message) {
    final world = message['world'];
    if (world is! String) return;
    final list = <String, SableSubLevelRef>{};
    for (final entry in (message['subLevels'] as List? ?? const [])) {
      final ref = SableSubLevelRef.from(entry);
      if (ref != null) list[ref.id] = ref;
    }
    _byId[world] = list;
  }

  Future<SableReply> _request(Map<String, Object?> message) async {
    if (!_subscribed) await subscribe();
    return _rawRequest(message);
  }

  /// One request, without the subscribe retry.
  Future<SableReply> _rawRequest(Map<String, Object?> message) async {
    final reply = await _channel.request(pluginName, message);
    if (reply is! Map) return const SableReply(false, {}, 'malformed reply');
    final payload = _asMap(reply);
    final ok = payload['ok'] == true;
    return SableReply(ok, payload, ok ? null : '${payload['error']}');
  }

  static Object? _identity(Map<String, Object?> message) => message;

  static Map<String, Object?> _asMap(Object? json) =>
      json is Map ? {for (final entry in json.entries) '${entry.key}': entry.value} : const {};
}