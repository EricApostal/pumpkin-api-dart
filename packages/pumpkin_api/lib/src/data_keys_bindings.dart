import 'bindings.g.dart';
import 'data_keys.dart';
import 'persistent_data.dart';

/// Adapts the host's [PersistentData] to a [DataStore].
final class _PersistentStore implements DataStore {
  final PersistentData _data;
  _PersistentStore(this._data);

  @override
  bool has(String name) => _data.has(name);
  @override
  void remove(String name) => _data.remove(name);
  @override
  String? readString(String name) => _data.getString(name);
  @override
  void writeString(String name, String value) => _data.setString(name, value);
  @override
  int? readLong(String name) => _data.getLong(name);
  @override
  void writeLong(String name, int value) => _data.setLong(name, value);
  @override
  bool? readBool(String name) => _data.getBool(name);
  @override
  void writeBool(String name, bool value) => _data.setBool(name, value);
  @override
  double? readDouble(String name) => _data.getDouble(name);
  @override
  void writeDouble(String name, double value) => _data.setDouble(name, value);
}

/// Typed access to an existing [PersistentData] container.
extension PersistentDataTyped on PersistentData {
  /// This container as [TypedData], for use with [DataKey]s.
  TypedData get typed => TypedData(_PersistentStore(this));
}

/// `data(namespace)` on players: typed persistent data stored on the player.
///
/// ```dart
/// const ns = PluginData('my_plugin');
/// const kills = IntKey('kills', defaultValue: 0);
/// player.data(ns).update(kills, (n) => n + 1);
/// ```
extension PlayerTypedData on Player {
  /// Typed data of this player in [namespace]. Only valid while this player
  /// object is.
  TypedData data(PluginData namespace) =>
      persistentData(namespace.namespace).typed;
}

/// Typed persistent data on entities.
extension EntityTypedData on Entity {
  /// Typed data of this entity in [namespace].
  TypedData data(PluginData namespace) =>
      persistentData(namespace.namespace).typed;
}

/// Typed persistent data on item stacks.
extension ItemStackTypedData on ItemStack {
  /// Typed data of this item in [namespace].
  TypedData data(PluginData namespace) =>
      persistentData(namespace.namespace).typed;
}

/// Typed persistent data on worlds.
extension WorldTypedData on World {
  /// Typed data of this world in [namespace].
  TypedData data(PluginData namespace) =>
      persistentData(namespace.namespace).typed;
}

/// Typed persistent data on chunks.
extension ChunkTypedData on Chunk {
  /// Typed data of this chunk in [namespace].
  TypedData data(PluginData namespace) =>
      persistentData(namespace.namespace).typed;
}

/// Typed persistent data on block entities.
extension BlockEntityTypedData on BlockEntity {
  /// Typed data of this block entity in [namespace].
  TypedData data(PluginData namespace) =>
      persistentData(namespace.namespace).typed;
}
