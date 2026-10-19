// Plain Dart values for the wire kinds that are not already a Dart built-in
// (pure). See `codec_compiler.dart` for the kind -> value table.
import 'dart:typed_data';

import '../core/nbt.dart';

/// The value of a `dispatch` field: which variant (the enum constant or the
/// registry entry named in the manifest) and its payload value.
final class PayloadVariant {
  /// The variant name as listed in the manifest (`SCENE`, `create:train_station`).
  final String variant;

  /// The variant's value; `null` for variants without data.
  final Object? value;

  const PayloadVariant(this.variant, [this.value]);

  @override
  bool operator ==(Object other) =>
      other is PayloadVariant && other.variant == variant && deepEquals(other.value, value);

  @override
  int get hashCode => Object.hash(variant, deepHash(value));

  @override
  String toString() => 'PayloadVariant($variant, $value)';
}

/// The value of an `either` field.
final class EitherValue {
  /// `true` when [value] is the left side.
  final bool isLeft;
  final Object? value;

  const EitherValue.left(this.value) : isLeft = true;
  const EitherValue.right(this.value) : isLeft = false;

  @override
  bool operator ==(Object other) => other is EitherValue && other.isLeft == isLeft && deepEquals(other.value, value);

  @override
  int get hashCode => Object.hash(isLeft, deepHash(value));

  @override
  String toString() => 'Either.${isLeft ? 'left' : 'right'}($value)';
}

/// Structural equality for decoded payload values (maps, lists, byte arrays,
/// records, [PayloadVariant], ...). Used by the tests and handy for modules.
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Uint8List && b is Uint8List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    // Keys may be maps/lists (identity equality), so compare entry by entry in order.
    final ea = a.entries.toList();
    final eb = b.entries.toList();
    for (var i = 0; i < ea.length; i++) {
      if (!deepEquals(ea[i].key, eb[i].key) || !deepEquals(ea[i].value, eb[i].value)) return false;
    }
    return true;
  }
  if (a is NbtValue && b is NbtValue) return a.kind == b.kind && deepEquals(a.value, b.value);
  if (a is double && b is double) return a == b || (a.isNaN && b.isNaN);
  return a == b;
}

/// A hash consistent with [deepEquals].
int deepHash(Object? v) {
  if (v is Uint8List) return Object.hashAll(v);
  if (v is List) return Object.hashAll(v.map(deepHash));
  if (v is Map) return Object.hashAll(v.entries.map((e) => Object.hash(deepHash(e.key), deepHash(e.value))));
  if (v is NbtValue) return Object.hash(v.kind, deepHash(v.value));
  return v.hashCode;
}
