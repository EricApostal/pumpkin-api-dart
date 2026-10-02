
import 'bindings.g.dart';

/// Builds [NbtTree]s holding a single value, the form in which persistent
/// data is stored.
abstract final class NbtTrees {
  static NbtTree _single(NbtTag tag) => NbtTree(root: 0, tags: [tag]);

  /// A tree holding a string.
  static NbtTree string(String value) => _single(NbtTagStringTag(value));

  /// A tree holding a 32-bit integer.
  static NbtTree int32(int value) => _single(NbtTagInt(value));

  /// A tree holding a 64-bit integer.
  static NbtTree int64(int value) => _single(NbtTagLong(value));

  /// A tree holding a 16-bit integer.
  static NbtTree int16(int value) => _single(NbtTagShort(value));

  /// A tree holding an 8-bit integer.
  static NbtTree int8(int value) => _single(NbtTagByte(value));

  /// A tree holding a boolean, stored as a byte (1 or 0).
  static NbtTree boolean(bool value) => _single(NbtTagByte(value ? 1 : 0));

  /// A tree holding a 32-bit float.
  static NbtTree float32(double value) => _single(NbtTagFloat(value));

  /// A tree holding a 64-bit float.
  static NbtTree float64(double value) => _single(NbtTagDouble(value));

  /// A tree holding a byte array.
  static NbtTree byteArray(List<int> value) => _single(NbtTagByteArray(List.of(value)));

  /// A tree holding an int array.
  static NbtTree intArray(List<int> value) => _single(NbtTagIntArray(List.of(value)));

  /// A tree holding a long array.
  static NbtTree longArray(List<int> value) => _single(NbtTagLongArray(List.of(value)));
}

extension NbtTreeRoot on NbtTree {
  /// The root tag, or `null` if [NbtTree.root] is out of range.
  NbtTag? get rootTag => root >= 0 && root < tags.length ? tags[root] : null;
}

/// Reads and writes custom data stored by a plugin on an entity, item,
/// block entity, chunk or world. Values are namespaced and survive restarts.
/// Get one with `persistentData(namespace)` on any of those objects:
///
/// ```dart
/// final data = player.asEntity().persistentData('my_plugin');
/// data.setInt('kills', (data.getInt('kills') ?? 0) + 1);
/// ```
///
/// A container is only valid as long as the object it came from. Getters
/// return `null` when the key is missing or holds another type; integer
/// getters also accept narrower integer types, and `getDouble` accepts floats.
final class PersistentData {
  /// The namespace all keys of this container live in.
  final String namespace;

  final void Function(String namespace, String key, NbtTree value) _set;
  final NbtTree? Function(String namespace, String key) _get;
  final void Function(String namespace, String key) _remove;
  final bool Function(String namespace, String key) _has;

  PersistentData._(this.namespace, this._set, this._get, this._remove, this._has);

  /// Whether [key] has a value.
  bool has(String key) => _has(namespace, key);

  /// Deletes the value of [key].
  void remove(String key) => _remove(namespace, key);

  /// The raw NBT stored under [key].
  NbtTree? getTree(String key) => _get(namespace, key);

  /// Stores raw NBT under [key].
  void setTree(String key, NbtTree value) => _set(namespace, key, value);

  NbtTag? _tag(String key) => getTree(key)?.rootTag;

  /// Stores a string.
  void setString(String key, String value) => setTree(key, NbtTrees.string(value));

  /// The string under [key].
  String? getString(String key) => switch (_tag(key)) {
    NbtTagStringTag(:final value) => value,
    _ => null,
  };

  /// Stores a 32-bit integer.
  void setInt(String key, int value) => setTree(key, NbtTrees.int32(value));

  /// The integer under [key] (stored as byte, short or int).
  int? getInt(String key) => switch (_tag(key)) {
    NbtTagInt(:final value) || NbtTagShort(:final value) || NbtTagByte(:final value) => value,
    _ => null,
  };

  /// Stores a 64-bit integer.
  void setLong(String key, int value) => setTree(key, NbtTrees.int64(value));

  /// The integer under [key] (stored as byte, short, int or long).
  int? getLong(String key) => switch (_tag(key)) {
    NbtTagLong(:final value) ||
    NbtTagInt(:final value) ||
    NbtTagShort(:final value) ||
    NbtTagByte(:final value) => value,
    _ => null,
  };

  /// Stores a 16-bit integer.
  void setShort(String key, int value) => setTree(key, NbtTrees.int16(value));

  /// The integer under [key] (stored as byte or short).
  int? getShort(String key) => switch (_tag(key)) {
    NbtTagShort(:final value) || NbtTagByte(:final value) => value,
    _ => null,
  };

  /// Stores an 8-bit integer.
  void setByte(String key, int value) => setTree(key, NbtTrees.int8(value));

  /// The byte under [key].
  int? getByte(String key) => switch (_tag(key)) {
    NbtTagByte(:final value) => value,
    _ => null,
  };

  /// Stores a boolean.
  void setBool(String key, bool value) => setTree(key, NbtTrees.boolean(value));

  /// The boolean under [key] (a non-zero byte is `true`).
  bool? getBool(String key) => switch (_tag(key)) {
    NbtTagByte(:final value) => value != 0,
    _ => null,
  };

  /// Stores a 32-bit float.
  void setFloat(String key, double value) => setTree(key, NbtTrees.float32(value));

  /// The float under [key].
  double? getFloat(String key) => switch (_tag(key)) {
    NbtTagFloat(:final value) => value,
    _ => null,
  };

  /// Stores a 64-bit float.
  void setDouble(String key, double value) => setTree(key, NbtTrees.float64(value));

  /// The number under [key] (stored as float or double).
  double? getDouble(String key) => switch (_tag(key)) {
    NbtTagDouble(:final value) || NbtTagFloat(:final value) => value,
    _ => null,
  };

  /// Stores a byte array.
  void setByteArray(String key, List<int> value) =>
      setTree(key, NbtTrees.byteArray(value));

  /// The byte array under [key].
  List<int>? getByteArray(String key) => switch (_tag(key)) {
    NbtTagByteArray(:final value) => value,
    _ => null,
  };

  /// Stores an int array.
  void setIntArray(String key, List<int> value) => setTree(key, NbtTrees.intArray(value));

  /// The int array under [key].
  List<int>? getIntArray(String key) => switch (_tag(key)) {
    NbtTagIntArray(:final value) => value,
    _ => null,
  };

  /// Stores a long array.
  void setLongArray(String key, List<int> value) =>
      setTree(key, NbtTrees.longArray(value));

  /// The long array under [key].
  List<int>? getLongArray(String key) => switch (_tag(key)) {
    NbtTagLongArray(:final value) => value,
    _ => null,
  };
}


extension ItemStackPersistentData on ItemStack {
  /// Persistent data of this item in [namespace].
  PersistentData persistentData(String namespace) => PersistentData._(
    namespace,
    (ns, key, value) => setCustomData(namespace: ns, key: key, value: value),
    (ns, key) => getCustomData(namespace: ns, key: key),
    (ns, key) => removeCustomData(namespace: ns, key: key),
    (ns, key) => hasCustomData(namespace: ns, key: key),
  );
}

extension EntityPersistentData on Entity {
  /// Persistent data of this entity in [namespace].
  PersistentData persistentData(String namespace) => PersistentData._(
    namespace,
    (ns, key, value) => setCustomData(namespace: ns, key: key, value: value),
    (ns, key) => getCustomData(namespace: ns, key: key),
    (ns, key) => removeCustomData(namespace: ns, key: key),
    (ns, key) => hasCustomData(namespace: ns, key: key),
  );
}

extension PlayerPersistentData on Player {
  /// Persistent data of this player (stored on its entity) in [namespace].
  PersistentData persistentData(String namespace) => asEntity().persistentData(namespace);
}

extension BlockEntityPersistentData on BlockEntity {
  /// Persistent data of this block entity in [namespace].
  PersistentData persistentData(String namespace) => PersistentData._(
    namespace,
    (ns, key, value) => setCustomData(namespace: ns, key: key, value: value),
    (ns, key) => getCustomData(namespace: ns, key: key),
    (ns, key) => removeCustomData(namespace: ns, key: key),
    (ns, key) => hasCustomData(namespace: ns, key: key),
  );
}

extension ChunkPersistentData on Chunk {
  /// Persistent data of this chunk in [namespace].
  PersistentData persistentData(String namespace) => PersistentData._(
    namespace,
    (ns, key, value) => setCustomData(namespace: ns, key: key, value: value),
    (ns, key) => getCustomData(namespace: ns, key: key),
    (ns, key) => removeCustomData(namespace: ns, key: key),
    (ns, key) => hasCustomData(namespace: ns, key: key),
  );
}

extension WorldPersistentData on World {
  /// Persistent data of this world in [namespace].
  PersistentData persistentData(String namespace) => PersistentData._(
    namespace,
    (ns, key, value) => setCustomData(namespace: ns, key: key, value: value),
    (ns, key) => getCustomData(namespace: ns, key: key),
    (ns, key) => removeCustomData(namespace: ns, key: key),
    (ns, key) => hasCustomData(namespace: ns, key: key),
  );
}
