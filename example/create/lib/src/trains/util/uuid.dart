// Random uuids (pure): `UUID.randomUUID()` for trains, graphs, edge points and signal groups.
import 'dart:math';

final Random _random = Random.secure();

/// A random version 4 uuid in canonical text.
String randomUuid() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0F) | 0x40;
  b[8] = (b[8] & 0x3F) | 0x80;
  final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// `UUID.getMostSignificantBits` (signed 64 bit).
int uuidMostSignificant(String uuid) {
  final hex = uuid.replaceAll('-', '');
  return BigInt.parse(hex.substring(0, 16), radix: 16).toSigned(64).toInt();
}

/// `UUID.getLeastSignificantBits`.
int uuidLeastSignificant(String uuid) {
  final hex = uuid.replaceAll('-', '');
  return BigInt.parse(hex.substring(16), radix: 16).toSigned(64).toInt();
}

/// `new UUID(most, least)`.
String uuidFromBits(int most, int least) {
  final hex = BigInt.from(most).toUnsigned(64).toRadixString(16).padLeft(16, '0') +
      BigInt.from(least).toUnsigned(64).toRadixString(16).padLeft(16, '0');
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
