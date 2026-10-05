import 'bindings.g.dart' show NbtEntry, NbtTag, NbtTagByte, NbtTagByteArray, NbtTagCompound, NbtTagDouble, NbtTagFloat, NbtTagInt, NbtTagIntArray, NbtTagListTag, NbtTagLong, NbtTagLongArray, NbtTagShort, NbtTagStringTag, NbtTree;

/// A compound NBT tag as a tree of Dart objects: the form block entity data
/// is written and read in, instead of the flat `nbt-tree` of the WIT.
///
/// Values are the generated scalar tags (`NbtTagInt`, ...; the `put*` and
/// `get*` methods hide them), nested [NbtCompound]s and `List<Object>`s of
/// those. Keys keep their insertion order.
///
/// ```dart
/// final tag = NbtCompound()
///   ..putInt('ComputerId', 7)
///   ..putString('Label', 'miner')
///   ..putBool('On', true);
/// world.setPluginBlockEntity(pos, 'computercraft:computer_normal', tag);
/// ```
final class NbtCompound {
  final Map<String, Object> _values = {};

  NbtCompound();

  /// Reads the compound at the root of [tree]. Throws a [FormatException] if
  /// the root is not a compound or the tree is malformed.
  factory NbtCompound.fromTree(NbtTree tree) {
    final value = _read(tree, tree.root, 0);
    if (value is! NbtCompound) {
      throw const FormatException('The root of the NBT tree is not a compound tag');
    }
    return value;
  }

  static Object _read(NbtTree tree, int index, int depth) {
    if (depth > 64) throw const FormatException('NBT tree is nested too deeply');
    if (index < 0 || index >= tree.tags.length) {
      throw FormatException('NBT tree refers to the missing tag $index');
    }
    final tag = tree.tags[index];
    return switch (tag) {
      NbtTagCompound(:final value) => () {
        final compound = NbtCompound();
        for (final entry in value) {
          compound._values[entry.key] = _read(tree, entry.value, depth + 1);
        }
        return compound;
      }(),
      NbtTagListTag(:final value) => <Object>[for (final i in value) _read(tree, i, depth + 1)],
      _ => tag,
    };
  }

  /// The keys, in insertion order.
  Iterable<String> get keys => _values.keys;

  bool get isEmpty => _values.isEmpty;

  bool containsKey(String key) => _values.containsKey(key);

  /// Removes [key].
  void remove(String key) => _values.remove(key);

  // -- Writing ------------------------------------------------------------------

  NbtCompound putByte(String key, int value) => _put(key, NbtTagByte(value));

  /// A boolean as a byte (1 or 0), like Minecraft does.
  NbtCompound putBool(String key, bool value) => _put(key, NbtTagByte(value ? 1 : 0));

  NbtCompound putShort(String key, int value) => _put(key, NbtTagShort(value));

  NbtCompound putInt(String key, int value) => _put(key, NbtTagInt(value));

  NbtCompound putLong(String key, int value) => _put(key, NbtTagLong(value));

  NbtCompound putFloat(String key, double value) => _put(key, NbtTagFloat(value));

  NbtCompound putDouble(String key, double value) => _put(key, NbtTagDouble(value));

  NbtCompound putString(String key, String value) => _put(key, NbtTagStringTag(value));

  NbtCompound putByteArray(String key, List<int> value) => _put(key, NbtTagByteArray(List.of(value)));

  NbtCompound putIntArray(String key, List<int> value) => _put(key, NbtTagIntArray(List.of(value)));

  NbtCompound putLongArray(String key, List<int> value) => _put(key, NbtTagLongArray(List.of(value)));

  NbtCompound putCompound(String key, NbtCompound value) => _put(key, value);

  /// A list tag. The elements are [NbtCompound]s, nested lists, or the
  /// generated scalar tags; Minecraft requires all of one type.
  NbtCompound putList(String key, List<Object> elements) => _put(key, List<Object>.of(elements));

  NbtCompound _put(String key, Object value) {
    _values[key] = value;
    return this;
  }

  // -- Reading ------------------------------------------------------------------

  /// The integer at [key] if it is a byte, short, int or long.
  int? getInt(String key) => switch (_values[key]) {
    NbtTagByte(:final value) || NbtTagShort(:final value) || NbtTagInt(:final value) || NbtTagLong(:final value) => value,
    _ => null,
  };

  /// A byte as a boolean (non-zero is true).
  bool? getBool(String key) {
    final value = getInt(key);
    return value == null ? null : value != 0;
  }

  double? getDouble(String key) => switch (_values[key]) {
    NbtTagFloat(:final value) || NbtTagDouble(:final value) => value,
    NbtTagByte(:final value) || NbtTagShort(:final value) || NbtTagInt(:final value) || NbtTagLong(:final value) => value.toDouble(),
    _ => null,
  };

  String? getString(String key) => switch (_values[key]) {
    NbtTagStringTag(:final value) => value,
    _ => null,
  };

  List<int>? getByteArray(String key) => switch (_values[key]) {
    NbtTagByteArray(:final value) => value,
    _ => null,
  };

  List<int>? getIntArray(String key) => switch (_values[key]) {
    NbtTagIntArray(:final value) => value,
    _ => null,
  };

  NbtCompound? getCompound(String key) => switch (_values[key]) {
    final NbtCompound compound => compound,
    _ => null,
  };

  List<Object>? getList(String key) => switch (_values[key]) {
    final List<Object> list => list,
    _ => null,
  };

  // -- Conversion ----------------------------------------------------------------

  /// The flat `nbt-tree` of the WIT, with this compound as its root.
  NbtTree toTree() {
    final tags = <NbtTag>[];
    final root = _add(this, tags);
    return NbtTree(root: root, tags: tags);
  }

  static int _add(Object value, List<NbtTag> tags) {
    switch (value) {
      case NbtCompound(:final _values):
        final entries = <NbtEntry>[];
        for (final entry in _values.entries) {
          entries.add(NbtEntry(key: entry.key, value: _add(entry.value, tags)));
        }
        tags.add(NbtTagCompound(entries));
      case List<Object>():
        final indices = [for (final element in value) _add(element, tags)];
        tags.add(NbtTagListTag(indices));
      case NbtTag():
        tags.add(value);
      default:
        throw ArgumentError.value(value, 'value', 'Not an NBT value');
    }
    return tags.length - 1;
  }

  @override
  String toString() => 'NbtCompound($_values)';
}
