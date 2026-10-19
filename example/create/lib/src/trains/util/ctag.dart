// `CompoundTag` for the trains module (pure): typed values under string keys with the
// accessors Create's `write`/`read` code uses. Values are [NbtValue]s of `core/nbt.dart`, so a
// tag converts to the network NBT a Create client reads, to JSON (saved data) and, in
// `support/ctag_host.dart`, to the host's `NbtCompound`.
//
// Java -> Dart: `tag.putInt(k, v)` -> `tag.putInt(k, v)`; `tag.getInt(k)` -> `tag.getInt(k)`
// (0 when missing, like Java); `tag.contains(k)` -> `tag.contains(k)`; `NBTHelper.writeCompoundList`
// -> `tag.putCompoundList`; `NbtUtils.writeBlockPos` -> `putBlockPos`; `VecHelper.writeNBT` ->
// `putVec3`; `UUIDUtil` int array -> `putUuid`.
import '../../common/pos.dart';
import '../../common/vec_helper.dart' show Vec3;
import '../../core/nbt.dart';

/// A mutable compound with Java `CompoundTag` flavoured accessors.
final class CTag {
  final Map<String, NbtValue> _map;

  CTag([Map<String, NbtValue>? map]) : _map = map ?? <String, NbtValue>{};

  /// From a network NBT compound; anything else gives an empty tag.
  factory CTag.fromNbt(NbtValue? value) {
    if (value == null || value.kind != NbtKind.compound) return CTag();
    return CTag(Map<String, NbtValue>.of(value.asCompound));
  }

  /// The network NBT form (a shallow copy of the map).
  NbtValue toNbt() => NbtValue.compound(Map<String, NbtValue>.of(_map));

  /// Typed JSON (lossless): `{"k": kind index, "v": value}` per entry. Used for saved data.
  Map<String, dynamic> toJson() => {for (final e in _map.entries) e.key: _valueToJson(e.value)};

  factory CTag.fromJson(Map<String, dynamic> json) =>
      CTag({for (final e in json.entries) e.key: _valueFromJson(e.value as Map<String, dynamic>)});

  static Map<String, dynamic> _valueToJson(NbtValue v) {
    final Object payload = switch (v.kind) {
      NbtKind.list => [for (final e in v.value as List<NbtValue>) _valueToJson(e)],
      NbtKind.compound => {for (final e in (v.value as Map<String, NbtValue>).entries) e.key: _valueToJson(e.value)},
      _ => v.value,
    };
    return {'k': v.kind.index, 'v': payload};
  }

  static NbtValue _valueFromJson(Map<String, dynamic> j) {
    final kind = NbtKind.values[j['k'] as int];
    final v = j['v'];
    switch (kind) {
      case NbtKind.end:
        throw const FormatException('TAG_End in saved data');
      case NbtKind.byte:
        return NbtValue.byte(v as int);
      case NbtKind.short:
        return NbtValue.short(v as int);
      case NbtKind.int:
        return NbtValue.int32(v as int);
      case NbtKind.long:
        return NbtValue.long(v as int);
      case NbtKind.float:
        return NbtValue.float((v as num).toDouble());
      case NbtKind.double:
        return NbtValue.double64((v as num).toDouble());
      case NbtKind.string:
        return NbtValue.string(v as String);
      case NbtKind.byteArray:
        return NbtValue.byteArray(List<int>.from(v as List));
      case NbtKind.intArray:
        return NbtValue.intArray(List<int>.from(v as List));
      case NbtKind.longArray:
        return NbtValue.longArray(List<int>.from(v as List));
      case NbtKind.list:
        return NbtValue.list([for (final e in v as List) _valueFromJson(e as Map<String, dynamic>)]);
      case NbtKind.compound:
        return NbtValue.compound({
          for (final e in (v as Map<String, dynamic>).entries) e.key: _valueFromJson(e.value as Map<String, dynamic>),
        });
    }
  }

  Iterable<String> get keys => _map.keys;
  bool get isEmpty => _map.isEmpty;
  bool get isNotEmpty => _map.isNotEmpty;
  int get size => _map.length;

  /// The raw values (for converting to the host's tag classes).
  Map<String, NbtValue> get entries => _map;

  bool contains(String key) => _map.containsKey(key);

  /// `contains(key, type)`.
  bool containsKind(String key, NbtKind kind) => _map[key]?.kind == kind;

  NbtKind? kindOf(String key) => _map[key]?.kind;

  void remove(String key) => _map.remove(key);

  /// A deep copy.
  CTag copy() => CTag.fromNbt(_deep(toNbt()));

  static NbtValue _deep(NbtValue v) => switch (v.kind) {
    NbtKind.list => NbtValue.list([for (final e in v.value as List<NbtValue>) _deep(e)]),
    NbtKind.compound => NbtValue.compound({
      for (final e in (v.value as Map<String, NbtValue>).entries) e.key: _deep(e.value),
    }),
    NbtKind.byteArray => NbtValue.byteArray(List<int>.of(v.value as List<int>)),
    NbtKind.intArray => NbtValue.intArray(List<int>.of(v.value as List<int>)),
    NbtKind.longArray => NbtValue.longArray(List<int>.of(v.value as List<int>)),
    _ => v,
  };

  /// `CompoundTag.merge`: values of [other] replace ours.
  void merge(CTag other) => _map.addAll(other._map);

  // -- Reading (Java semantics: a missing or mistyped key reads as 0 / "" / false) -------------

  int getInt(String key) => getIntOr(key, 0);
  int getLong(String key) => getIntOr(key, 0);
  int getByte(String key) => getIntOr(key, 0);
  int getShort(String key) => getIntOr(key, 0);

  int getIntOr(String key, int fallback) {
    final v = _map[key];
    if (v == null) return fallback;
    return switch (v.kind) {
      NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => v.value as int,
      NbtKind.float || NbtKind.double => (v.value as double).toInt(),
      _ => fallback,
    };
  }

  int getLongOr(String key, int fallback) => getIntOr(key, fallback);

  double getDouble(String key) => getDoubleOr(key, 0);
  double getFloat(String key) => getDoubleOr(key, 0);

  double getDoubleOr(String key, double fallback) {
    final v = _map[key];
    if (v == null) return fallback;
    return switch (v.kind) {
      NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => (v.value as int).toDouble(),
      NbtKind.float || NbtKind.double => v.value as double,
      _ => fallback,
    };
  }

  double getFloatOr(String key, double fallback) => getDoubleOr(key, fallback);

  String getString(String key) => getStringOr(key, '');

  String getStringOr(String key, String fallback) {
    final v = _map[key];
    return v != null && v.kind == NbtKind.string ? v.value as String : fallback;
  }

  bool getBoolean(String key) => getBooleanOr(key, false);

  bool getBooleanOr(String key, bool fallback) {
    final v = _map[key];
    if (v == null) return fallback;
    return switch (v.kind) {
      NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => (v.value as int) != 0,
      _ => fallback,
    };
  }

  /// `getCompound` (an empty tag when missing). The returned tag is a live view of the stored
  /// compound's map: changes to it show in this tag.
  CTag getCompound(String key) {
    final v = _map[key];
    if (v == null || v.kind != NbtKind.compound) return CTag();
    return CTag(v.value as Map<String, NbtValue>);
  }

  /// `getCompound` as nullable (`null` when missing or not a compound).
  CTag? getCompoundOrNull(String key) {
    final v = _map[key];
    if (v == null || v.kind != NbtKind.compound) return null;
    return CTag(v.value as Map<String, NbtValue>);
  }

  /// `getList(key, Tag.TAG_COMPOUND)` as tags.
  List<CTag> getCompoundList(String key) {
    final v = _map[key];
    if (v == null || v.kind != NbtKind.list) return const [];
    return [
      for (final e in v.value as List<NbtValue>)
        if (e.kind == NbtKind.compound) CTag(e.value as Map<String, NbtValue>),
    ];
  }

  /// `getList` of any element type.
  List<NbtValue> getList(String key) {
    final v = _map[key];
    return v != null && v.kind == NbtKind.list ? v.value as List<NbtValue> : const [];
  }

  /// `getList(key, Tag.TAG_STRING)` as strings.
  List<String> getStringList(String key) => [
    for (final e in getList(key))
      if (e.kind == NbtKind.string) e.value as String,
  ];

  /// `getList(key, Tag.TAG_INT)` as ints.
  List<int> getIntList(String key) => [
    for (final e in getList(key))
      if (e.kind == NbtKind.int) e.value as int,
  ];

  /// `getList(key, Tag.TAG_DOUBLE)`.
  List<double> getDoubleList(String key) => [
    for (final e in getList(key))
      if (e.kind == NbtKind.double || e.kind == NbtKind.float) e.value as double,
  ];

  List<int> getIntArray(String key) {
    final v = _map[key];
    return v != null && v.kind == NbtKind.intArray ? List<int>.of(v.value as List<int>) : <int>[];
  }

  List<int> getLongArray(String key) {
    final v = _map[key];
    return v != null && v.kind == NbtKind.longArray ? List<int>.of(v.value as List<int>) : <int>[];
  }

  List<int> getByteArray(String key) {
    final v = _map[key];
    return v != null && v.kind == NbtKind.byteArray ? List<int>.of(v.value as List<int>) : <int>[];
  }

  /// `NbtUtils.readBlockPos` / `NBTHelper.readBlockPos`: an int array `[x, y, z]`, or the legacy
  /// `{X, Y, Z}` compound; the origin when missing.
  Pos getBlockPos(String key) {
    final a = getIntArray(key);
    if (a.length >= 3) return (a[0], a[1], a[2]);
    final c = getCompoundOrNull(key);
    if (c != null) return (c.getInt('X'), c.getInt('Y'), c.getInt('Z'));
    return posZero;
  }

  /// `VecHelper.readNBT`: a list of three doubles; zero when missing.
  Vec3 getVec3(String key) {
    final l = getDoubleList(key);
    return l.length >= 3 ? (l[0], l[1], l[2]) : (0.0, 0.0, 0.0);
  }

  /// A uuid stored as an int array of four ints (`NbtUtils.createUUID`), as its canonical text.
  /// `null` when missing.
  String? getUuid(String key) {
    final a = getIntArray(key);
    return a.length == 4 ? uuidFromInts(a) : null;
  }

  // -- Writing ----------------------------------------------------------------------------------

  void putByte(String key, int value) => _map[key] = NbtValue.byte(value);
  void putShort(String key, int value) => _map[key] = NbtValue.short(value);
  void putInt(String key, int value) => _map[key] = NbtValue.int32(value);
  void putLong(String key, int value) => _map[key] = NbtValue.long(value);
  void putFloat(String key, double value) => _map[key] = NbtValue.float(value);
  void putDouble(String key, double value) => _map[key] = NbtValue.double64(value);
  void putString(String key, String value) => _map[key] = NbtValue.string(value);
  void putBoolean(String key, bool value) => _map[key] = NbtValue.byte(value ? 1 : 0);
  void putIntArray(String key, List<int> value) => _map[key] = NbtValue.intArray(List<int>.of(value));
  void putLongArray(String key, List<int> value) => _map[key] = NbtValue.longArray(List<int>.of(value));
  void putByteArray(String key, List<int> value) => _map[key] = NbtValue.byteArray(List<int>.of(value));
  void putList(String key, List<NbtValue> value) => _map[key] = NbtValue.list(value);
  void putTag(String key, NbtValue value) => _map[key] = value;

  /// Stores [tag] itself (not a copy).
  void putCompound(String key, CTag tag) => _map[key] = NbtValue.compound(tag._map);

  /// `NBTHelper.writeCompoundList`.
  void putCompoundList(String key, Iterable<CTag> tags) =>
      _map[key] = NbtValue.list([for (final t in tags) NbtValue.compound(t._map)]);

  void putStringList(String key, Iterable<String> values) =>
      _map[key] = NbtValue.list([for (final s in values) NbtValue.string(s)]);

  void putIntList(String key, Iterable<int> values) =>
      _map[key] = NbtValue.list([for (final s in values) NbtValue.int32(s)]);

  void putBlockPos(String key, Pos p) => putIntArray(key, [p.$1, p.$2, p.$3]);

  void putVec3(String key, Vec3 v) => _map[key] = NbtValue.list([
    NbtValue.double64(v.$1),
    NbtValue.double64(v.$2),
    NbtValue.double64(v.$3),
  ]);

  void putUuid(String key, String uuid) => putIntArray(key, uuidToInts(uuid));

  /// `NBTHelper.putMarker`.
  void putMarker(String key) => _map[key] = NbtValue.emptyCompound();

  @override
  String toString() => 'CTag($_map)';
}

/// A uuid in canonical text (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) as four signed ints
/// (`UUIDUtil.uuidToIntArray`).
List<int> uuidToInts(String uuid) {
  final hex = uuid.replaceAll('-', '');
  if (hex.length != 32) throw FormatException('Not a uuid: $uuid');
  return [
    for (var i = 0; i < 4; i++) int.parse(hex.substring(i * 8, i * 8 + 8), radix: 16).toSigned(32),
  ];
}

/// `UUIDUtil.uuidFromIntArray`.
String uuidFromInts(List<int> ints) {
  final hex = [for (final i in ints) (i & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
