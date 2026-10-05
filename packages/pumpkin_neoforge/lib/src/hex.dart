// Hex helpers for logs and tests. Binding-free.
import 'dart:typed_data';

/// The lower-case hex of [bytes].
String toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// The inverse of [toHex]; whitespace is ignored.
Uint8List fromHex(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  if (clean.length.isOdd) throw const FormatException('Odd hex length');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}
