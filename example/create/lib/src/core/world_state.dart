// Per-world saved data: dart_mappable models stored as a JSON string in the
// world's custom data (`create` namespace), cached in memory and written at the
// end of the tick when marked dirty.
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import 'worlds.dart';

/// Describes one kind of saved data, usually a `static final` next to the model:
///
/// ```dart
/// static final type = SavedDataType<LinkData>('redstone_links',
///     create: LinkData.new, fromMap: LinkDataMapper.fromMap, toMap: (v) => v.toMap());
/// ```
final class SavedDataType<T extends Object> {
  /// Key in the world's custom data.
  final String name;
  final T Function() create;
  final T Function(Map<String, dynamic> map) fromMap;
  final Map<String, dynamic> Function(T value) toMap;

  const SavedDataType(this.name, {required this.create, required this.fromMap, required this.toMap});
}

final class WorldSavedData {
  static const String namespace = 'create';

  final Worlds worlds;
  final Logger log;

  WorldSavedData(this.worlds, this.log);

  final Map<String, Object> _cache = {};
  final Map<String, (String worldId, SavedDataType<Object> type)> _dirty = {};

  String _id(String worldId, String name) => '$worldId/$name';

  /// The data of [type] in [world], loaded on first use (or a fresh one).
  T get<T extends Object>(World world, SavedDataType<T> type) {
    final worldId = worlds.touch(world);
    final id = _id(worldId, type.name);
    final cached = _cache[id];
    if (cached != null) return cached as T;
    T value;
    try {
      final json = world.persistentData(namespace).getString(type.name);
      value = json == null ? type.create() : type.fromMap(jsonDecode(json) as Map<String, dynamic>);
    } catch (e, s) {
      log.error('Saved data ${type.name} of $worldId is unreadable, starting empty', error: e, stackTrace: s);
      value = type.create();
    }
    _cache[id] = value;
    return value;
  }

  /// Queues [type] of [worldId] for writing.
  void markDirty<T extends Object>(String worldId, SavedDataType<T> type) =>
      _dirty[_id(worldId, type.name)] = (worldId, type as SavedDataType<Object>);

  void _write(World world, String id, SavedDataType<Object> type) {
    final value = _cache[id];
    if (value == null) return;
    world.persistentData(namespace).setString(type.name, jsonEncode(type.toMap(value)));
  }

  /// Writes the dirty data of [world].
  void flushWorld(World world) {
    if (_dirty.isEmpty) return;
    final worldId = world.getId();
    for (final e in _dirty.entries.toList()) {
      if (e.value.$1 != worldId) continue;
      _dirty.remove(e.key);
      try {
        _write(world, e.key, e.value.$2);
      } catch (err, s) {
        log.error('Writing saved data ${e.key} failed', error: err, stackTrace: s);
      }
    }
  }

  void flushAll() {
    for (final e in _dirty.entries.toList()) {
      final world = worlds.byId(e.value.$1);
      if (world != null) _write(world, e.key, e.value.$2);
    }
    _dirty.clear();
  }

  /// Flushes at the end of every [saveIntervalTicks] and when a world unloads.
  void install(Context context, {required int saveIntervalTicks}) {
    context.listen(Events.worldTick, (server, e) {
      if (e.tick % saveIntervalTicks == 0) flushWorld(e.targetWorld);
    });
    context.listen(Events.worldUnload, (server, e) {
      if (e.cancelled) return;
      flushWorld(e.targetWorld);
      final prefix = '${e.targetWorld.getId()}/';
      _cache.removeWhere((k, _) => k.startsWith(prefix));
    });
  }
}
