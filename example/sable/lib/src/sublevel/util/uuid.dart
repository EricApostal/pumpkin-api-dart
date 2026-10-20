// UUID helpers for the sub-level storage format.
//
// Minecraft stores UUIDs as four ints (`UUIDUtil.CODEC`), most significant
// first. The `8-4-4-4-12` string form is what the rest of the port uses as an
// identity, so the conversion lives here.
//
// Pure: no host imports.

/// The four ints of [uuid] (`UUIDUtil.CODEC`).
List<int> uuidToInts(String uuid) {
  final hex = uuid.replaceAll('-', '');
  if (hex.length != 32) {
    throw FormatException('Not a UUID: $uuid');
  }
  int part(int i) => int.parse(hex.substring(i * 8, i * 8 + 8), radix: 16).toSigned(32);
  return [part(0), part(1), part(2), part(3)];
}

/// The `8-4-4-4-12` string of the four ints of a `UUIDUtil.CODEC` array.
String uuidFromInts(List<int> ints) {
  if (ints.length != 4) {
    throw FormatException('A UUID needs four ints, got ${ints.length}');
  }
  final hex = [
    for (final i in ints) (i & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
