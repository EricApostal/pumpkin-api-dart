// `CompoundTag` for the display link's source configuration (pure): typed values under
// string keys, with the accessors the display sources use (`getIntOr`, `putLong`, ...).
// The values are [NbtValue]s of `core/nbt.dart`, so the tag converts to the network NBT the
// client sends and expects.
import '../../core/nbt.dart';

/// A compound with Java `CompoundTag` flavoured accessors.
final class ConfigTag {
  final Map<String, NbtValue> _map;

  ConfigTag([Map<String, NbtValue>? map]) : _map = map ?? {};

  /// From a network NBT compound; anything else gives an empty tag.
  factory ConfigTag.fromNbt(NbtValue? value) {
    if (value == null || value.kind != NbtKind.compound) return ConfigTag();
    return ConfigTag(Map<String, NbtValue>.of(value.asCompound));
  }

  /// The network NBT form.
  NbtValue toNbt() => NbtValue.compound(Map<String, NbtValue>.of(_map));

  Iterable<String> get keys => _map.keys;

  bool get isEmpty => _map.isEmpty;

  /// The raw values (for converting to the host's tag classes).
  Map<String, NbtValue> get entries => _map;

  bool contains(String key) => _map.containsKey(key);

  void remove(String key) => _map.remove(key);

  ConfigTag copy() => ConfigTag(Map<String, NbtValue>.of(_map));

  /// `CompoundTag.merge`: values of [other] replace ours.
  void merge(ConfigTag other) => _map.addAll(other._map);

  // -- Reading ----------------------------------------------------------------------------------

  /// `getIntOr`: any numeric tag reads as an int.
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

  double getFloatOr(String key, double fallback) {
    final v = _map[key];
    if (v == null) return fallback;
    return switch (v.kind) {
      NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => (v.value as int).toDouble(),
      NbtKind.float || NbtKind.double => v.value as double,
      _ => fallback,
    };
  }

  String getStringOr(String key, String fallback) {
    final v = _map[key];
    return v != null && v.kind == NbtKind.string ? v.value as String : fallback;
  }

  bool getBooleanOr(String key, bool fallback) {
    final v = _map[key];
    if (v == null) return fallback;
    return switch (v.kind) {
      NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => (v.value as int) != 0,
      _ => fallback,
    };
  }

  /// `getListOrEmpty`.
  List<NbtValue> getListOrEmpty(String key) {
    final v = _map[key];
    return v != null && v.kind == NbtKind.list ? v.value as List<NbtValue> : const [];
  }

  // -- Writing ----------------------------------------------------------------------------------

  void putInt(String key, int value) => _map[key] = NbtValue.int32(value);

  void putLong(String key, int value) => _map[key] = NbtValue.long(value);

  void putFloat(String key, double value) => _map[key] = NbtValue.float(value);

  void putString(String key, String value) => _map[key] = NbtValue.string(value);

  void putBoolean(String key, bool value) => _map[key] = NbtValue.byte(value ? 1 : 0);

  void putList(String key, List<NbtValue> value) => _map[key] = NbtValue.list(value);

  @override
  String toString() => 'ConfigTag($_map)';
}
