// Network NBT helpers for the payloads whose Java codec is
// `ByteBufCodecs.fromCodec(Codec)`: `physics_property` and `floating_material`.
//
// `fromCodec` writes the codec's result as one nameless network-NBT root tag
// (`FriendlyByteBuf.writeNbt`), so the payload body of those two packets is a
// compound tag. This file wraps `create`'s `NetworkNbt` with the field access
// the codecs need, and reproduces Mojang's `NbtOps` tolerance: a numeric field
// accepts any numeric tag kind, and a boolean accepts any byte.
//
// Pure: no host imports.
import 'dart:typed_data';

// create's barrel re-exports the host bridge (wasm); the NBT model is pure.
// ignore_for_file: implementation_imports
import 'package:create/src/core/nbt.dart' show NbtKind, NbtValue, NetworkNbt;
import 'package:pumpkin_api/pumpkin_api_core.dart';

/// Reading and writing the nameless root compound of a `fromCodec` payload.
abstract final class NetworkNbtMap {
  /// Reads the root tag and requires it to be a compound.
  static Map<String, NbtValue> read(PacketReader r) {
    final root = NetworkNbt.read(r);
    if (root == null || root.kind != NbtKind.compound) {
      throw const PacketException('Expected a compound tag as the payload root');
    }
    return root.asCompound;
  }

  /// Writes [map] as the nameless root compound.
  static void write(PacketWriter w, Map<String, NbtValue> map) {
    NetworkNbt.write(w, NbtValue.compound(map));
  }

  /// Encodes [map] into a fresh byte array (the payload body of a
  /// `fromCodec` codec).
  static Uint8List encode(Map<String, NbtValue> map) => PacketBuffer.encode((w) => write(w, map));

  /// Decodes a payload body into its root compound.
  static Map<String, NbtValue> decode(List<int> bytes) => PacketBuffer.decode(bytes, read);
}

/// Typed access to the fields of a decoded compound.
///
/// Every getter mirrors the matching `Codec` field accessor: an absent field
/// yields the default (for `optionalFieldOf`) or throws (for `fieldOf`).
abstract final class NbtFields {
  static Never _missing(String key) => throw PacketException('Missing required NBT field "$key"');

  static Never _wrongType(String key, NbtKind actual, String expected) =>
      throw PacketException('NBT field "$key" is ${actual.name}, expected $expected');

  /// A numeric field as a double (`Codec.DOUBLE`, `Codec.FLOAT`); `null` when
  /// the field is absent.
  static double? doubleOrNull(Map<String, NbtValue> map, String key) {
    final value = map[key];
    if (value == null) return null;
    return switch (value.kind) {
      NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => (value.value as int).toDouble(),
      NbtKind.float || NbtKind.double => value.value as double,
      _ => _wrongType(key, value.kind, 'a number'),
    };
  }

  /// A required numeric field (`fieldOf`).
  static double requireDouble(Map<String, NbtValue> map, String key) =>
      doubleOrNull(map, key) ?? _missing(key);

  /// A numeric field as a double, or [fallback].
  static double doubleOr(Map<String, NbtValue> map, String key, double fallback) =>
      doubleOrNull(map, key) ?? fallback;

  /// A numeric field as an int (`Codec.INT`); `null` when absent.
  static int? intOrNull(Map<String, NbtValue> map, String key) {
    final value = map[key];
    if (value == null) return null;
    return switch (value.kind) {
      NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long => value.value as int,
      NbtKind.float || NbtKind.double => (value.value as double).toInt(),
      _ => _wrongType(key, value.kind, 'a number'),
    };
  }

  /// An int field, or [fallback].
  static int intOr(Map<String, NbtValue> map, String key, int fallback) =>
      intOrNull(map, key) ?? fallback;

  /// A boolean field (`Codec.BOOL`, stored as a byte); `null` when absent.
  static bool? boolOrNull(Map<String, NbtValue> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value.kind != NbtKind.byte) _wrongType(key, value.kind, 'a byte');
    return (value.value as int) != 0;
  }

  /// A boolean field, or [fallback].
  static bool boolOr(Map<String, NbtValue> map, String key, bool fallback) =>
      boolOrNull(map, key) ?? fallback;

  /// A string field (`Codec.STRING`); `null` when absent.
  static String? stringOrNull(Map<String, NbtValue> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value.kind != NbtKind.string) _wrongType(key, value.kind, 'a string');
    return value.value as String;
  }

  /// A required string field.
  static String requireString(Map<String, NbtValue> map, String key) =>
      stringOrNull(map, key) ?? _missing(key);

  /// A compound field; `null` when absent.
  static Map<String, NbtValue>? compoundOrNull(Map<String, NbtValue> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value.kind != NbtKind.compound) _wrongType(key, value.kind, 'a compound');
    return value.asCompound;
  }

  /// A required compound field.
  static Map<String, NbtValue> requireCompound(Map<String, NbtValue> map, String key) =>
      compoundOrNull(map, key) ?? _missing(key);

  /// A list field; `null` when absent.
  static List<NbtValue>? listOrNull(Map<String, NbtValue> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value.kind != NbtKind.list) _wrongType(key, value.kind, 'a list');
    return value.value as List<NbtValue>;
  }

  // ------------------------------------------------------------- constructors

  /// `Codec.BOOL` encoding.
  static NbtValue boolean(bool value) => NbtValue.byte(value ? 1 : 0);

  /// `Codec.DOUBLE` encoding.
  static NbtValue doubleValue(double value) => NbtValue.double64(value);

  /// `Codec.INT` encoding.
  static NbtValue intValue(int value) => NbtValue.int32(value);

  /// `Codec.STRING` encoding.
  static NbtValue string(String value) => NbtValue.string(value);

  /// A compound value.
  static NbtValue compound(Map<String, NbtValue> value) => NbtValue.compound(value);

  /// `Codec.DOUBLE.listOf()` encoding.
  static NbtValue doubleList(List<double> values) =>
      NbtValue.list([for (final v in values) NbtValue.double64(v)]);
}
