// A mutable compound tag over the pure NBT model (pure). Contraptions keep block entity data,
// movement context data and storage as NBT; this is the `CompoundTag` they work with.
import '../../common/common.dart';
import '../../core/nbt.dart';

/// `CompoundTag`: a mutable string-keyed map of [NbtValue]s. Nested compounds returned by the
/// getters are views of the same data, so changes to them show up in the parent.
final class NbtMap {
  /// The entries, in insertion order.
  final Map<String, NbtValue> map;

  NbtMap([Map<String, NbtValue>? entries]) : map = entries ?? <String, NbtValue>{};

  /// The compound inside [value], sharing its map. A value of another kind gives an empty map.
  factory NbtMap.of(NbtValue? value) =>
      value != null && value.kind == NbtKind.compound ? NbtMap(value.asCompound) : NbtMap();

  /// A deep copy of the compound [value].
  factory NbtMap.copyOf(NbtValue? value) => NbtMap.of(value).copy();

  /// This compound as a value (sharing the entries).
  NbtValue toValue() => NbtValue.compound(map);

  /// A deep copy.
  NbtMap copy() => NbtMap({for (final e in map.entries) e.key: copyValue(e.value)});

  bool get isEmpty => map.isEmpty;
  bool get isNotEmpty => map.isNotEmpty;
  Iterable<String> get keys => map.keys;

  bool contains(String key) => map.containsKey(key);

  NbtValue? operator [](String key) => map[key];

  void operator []=(String key, NbtValue value) => map[key] = value;

  void remove(String key) => map.remove(key);

  void clear() => map.clear();

  // -- Writing -----------------------------------------------------------------------------

  void putByte(String key, int v) => map[key] = NbtValue.byte(v);
  void putBool(String key, bool v) => map[key] = NbtValue.byte(v ? 1 : 0);
  void putShort(String key, int v) => map[key] = NbtValue.short(v);
  void putInt(String key, int v) => map[key] = NbtValue.int32(v);
  void putLong(String key, int v) => map[key] = NbtValue.long(v);
  void putFloat(String key, double v) => map[key] = NbtValue.float(v);
  void putDouble(String key, double v) => map[key] = NbtValue.double64(v);
  void putString(String key, String v) => map[key] = NbtValue.string(v);
  void putIntArray(String key, List<int> v) => map[key] = NbtValue.intArray(v);
  void putCompound(String key, NbtMap v) => map[key] = v.toValue();
  void putList(String key, List<NbtValue> v) => map[key] = NbtValue.list(v);

  /// `BlockPos.CODEC`: an int array of three.
  void putBlockPos(String key, Pos p) => map[key] = NbtValue.intArray([p.$1, p.$2, p.$3]);

  /// `NBTHelper.putMarker`.
  void putMarker(String key) => map[key] = NbtValue.emptyCompound();

  /// `VecHelper.writeNBT`: a list of three doubles.
  void putVec(String key, Vec3 v) => map[key] = writeVec(v);

  // -- Reading -----------------------------------------------------------------------------

  /// An integer of any width stored at [key], [fallback] if absent or not a number.
  int getInt(String key, [int fallback = 0]) {
    final v = map[key];
    if (v == null) return fallback;
    return switch (v.kind) {
      NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => v.value as int,
      NbtKind.float || NbtKind.double => (v.value as double).toInt(),
      _ => fallback,
    };
  }

  bool getBool(String key, [bool fallback = false]) {
    final v = map[key];
    if (v == null) return fallback;
    return switch (v.kind) {
      NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => (v.value as int) != 0,
      _ => fallback,
    };
  }

  double getDouble(String key, [double fallback = 0]) {
    final v = map[key];
    if (v == null) return fallback;
    return switch (v.kind) {
      NbtKind.float || NbtKind.double => v.value as double,
      NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => (v.value as int).toDouble(),
      _ => fallback,
    };
  }

  String getString(String key, [String fallback = '']) {
    final v = map[key];
    return v != null && v.kind == NbtKind.string ? v.value as String : fallback;
  }

  /// The nested compound at [key], or an empty detached map (`getCompoundOrEmpty`).
  NbtMap getCompound(String key) {
    final v = map[key];
    return v != null && v.kind == NbtKind.compound ? NbtMap(v.asCompound) : NbtMap();
  }

  /// The nested compound at [key] or `null` when absent.
  NbtMap? getCompoundOrNull(String key) {
    final v = map[key];
    return v != null && v.kind == NbtKind.compound ? NbtMap(v.asCompound) : null;
  }

  /// The list at [key] or an empty list (`getListOrEmpty`).
  List<NbtValue> getList(String key) {
    final v = map[key];
    return v != null && v.kind == NbtKind.list ? v.value as List<NbtValue> : <NbtValue>[];
  }

  List<int> getIntArray(String key) {
    final v = map[key];
    return v != null && (v.kind == NbtKind.intArray || v.kind == NbtKind.byteArray || v.kind == NbtKind.longArray)
        ? v.value as List<int>
        : <int>[];
  }

  /// `NBTHelper.readBlockPos`: an int array, or the legacy `{X, Y, Z}` compound.
  Pos getBlockPos(String key) {
    final v = map[key];
    if (v == null) return posZero;
    if (v.kind == NbtKind.intArray) {
      final a = v.value as List<int>;
      if (a.length >= 3) return (a[0], a[1], a[2]);
    }
    if (v.kind == NbtKind.compound) {
      final c = NbtMap(v.asCompound);
      return (c.getInt('X'), c.getInt('Y'), c.getInt('Z'));
    }
    return posZero;
  }

  /// `VecHelper.readNBT` of the list at [key] (zero if absent).
  Vec3 getVec(String key) => readVec(getList(key));

  @override
  String toString() => 'NbtMap($map)';
}

/// A deep copy of [v].
NbtValue copyValue(NbtValue v) {
  switch (v.kind) {
    case NbtKind.compound:
      return NbtValue.compound({for (final e in v.asCompound.entries) e.key: copyValue(e.value)});
    case NbtKind.list:
      return NbtValue.list([for (final e in v.value as List<NbtValue>) copyValue(e)]);
    case NbtKind.byteArray:
      return NbtValue.byteArray(List<int>.of(v.value as List<int>));
    case NbtKind.intArray:
      return NbtValue.intArray(List<int>.of(v.value as List<int>));
    case NbtKind.longArray:
      return NbtValue.longArray(List<int>.of(v.value as List<int>));
    default:
      return v;
  }
}

/// `VecHelper.writeNBT`.
NbtValue writeVec(Vec3 v) =>
    NbtValue.list([NbtValue.double64(v.$1), NbtValue.double64(v.$2), NbtValue.double64(v.$3)]);

/// `VecHelper.readNBT`.
Vec3 readVec(List<NbtValue> list) {
  double at(int i) {
    if (i >= list.length) return 0;
    final v = list[i];
    return switch (v.kind) {
      NbtKind.float || NbtKind.double => v.value as double,
      NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => (v.value as int).toDouble(),
      _ => 0,
    };
  }

  return (at(0), at(1), at(2));
}

/// Structural equality of two values (floats compare exactly).
bool nbtEquals(NbtValue? a, NbtValue? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.kind != b.kind) return false;
  switch (a.kind) {
    case NbtKind.compound:
      final ma = a.asCompound, mb = b.asCompound;
      if (ma.length != mb.length) return false;
      for (final e in ma.entries) {
        if (!mb.containsKey(e.key) || !nbtEquals(e.value, mb[e.key])) return false;
      }
      return true;
    case NbtKind.list:
      final la = a.value as List<NbtValue>, lb = b.value as List<NbtValue>;
      if (la.length != lb.length) return false;
      for (var i = 0; i < la.length; i++) {
        if (!nbtEquals(la[i], lb[i])) return false;
      }
      return true;
    case NbtKind.byteArray:
    case NbtKind.intArray:
    case NbtKind.longArray:
      final xa = a.value as List<int>, xb = b.value as List<int>;
      if (xa.length != xb.length) return false;
      for (var i = 0; i < xa.length; i++) {
        if (xa[i] != xb[i]) return false;
      }
      return true;
    default:
      return a.value == b.value;
  }
}
