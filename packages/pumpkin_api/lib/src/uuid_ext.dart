import 'bindings.g.dart';

String _hex(int value, int digits) =>
    value.toRadixString(16).padLeft(digits, '0');

/// Parsing and well-known [Uuid]s.
abstract final class Uuids {
  /// The all-zero UUID.
  static const nil = Uuid(high: 0, low: 0);

  /// Parses the canonical `8-4-4-4-12` hex form (case-insensitive). Returns
  /// null if [text] is not a valid UUID.
  static Uuid? tryParse(String text) {
    if (text.length != 36) return null;
    for (final i in const [8, 13, 18, 23]) {
      if (text.codeUnitAt(i) != 0x2d) return null;
    }
    final hex =
        text.substring(0, 8) +
        text.substring(9, 13) +
        text.substring(14, 18) +
        text.substring(19, 23) +
        text.substring(24);
    final high = _parseHex64(hex.substring(0, 16));
    final low = _parseHex64(hex.substring(16));
    if (high == null || low == null) return null;
    return Uuid(high: high, low: low);
  }

  /// Like [tryParse], but throws a [FormatException] on invalid input.
  static Uuid parse(String text) =>
      tryParse(text) ?? (throw FormatException('Invalid UUID', text));

  static int? _parseHex64(String hex) {
    final upper = int.tryParse(hex.substring(0, 8), radix: 16);
    final lower = int.tryParse(hex.substring(8), radix: 16);
    if (upper == null || lower == null) return null;
    return (upper << 32) | lower;
  }
}

/// Formatting and comparison for [Uuid].
///
/// [Uuid] is a plain record without `==`; compare with [equals] or use
/// [asString] as a map key.
extension UuidExt on Uuid {
  /// The canonical lowercase form, like `00112233-4455-6677-8899-aabbccddeeff`.
  String get asString =>
      '${_hex((high >>> 32) & 0xffffffff, 8)}-'
      '${_hex((high >>> 16) & 0xffff, 4)}-'
      '${_hex(high & 0xffff, 4)}-'
      '${_hex((low >>> 48) & 0xffff, 4)}-'
      '${_hex(low & 0xffffffffffff, 12)}';

  /// Whether both hold the same value.
  bool equals(Uuid other) => high == other.high && low == other.low;

  /// Whether this is [Uuids.nil].
  bool get isNil => high == 0 && low == 0;
}
