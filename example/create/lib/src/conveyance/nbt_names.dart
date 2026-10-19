// Java writes enum constants into NBT with `Enum.name()` (upper case). Dart's
// `Enum.name` is lower case, so every enum-valued key (the tunnel's
// `StackEnteredFrom`, the ejector's `State`) goes through these helpers. The
// direction list forms (`Flaps`, `Sides`) are Java `ListTag`s of `IntTag`, not
// int arrays, so only their values are pure; the container is built by the
// host block entities.
import '../common/direction.dart';

/// `Enum.name()` of the Dart constant [dartName].
String enumNbtName(String dartName) => dartName.toUpperCase();

/// The Dart constant name among [dartNames] that `Enum.valueOf` would find for
/// [nbtName], or `null` when no constant matches. Comparison is case
/// insensitive so a lower-case name written by an older Dart build is still
/// read.
String? enumDartName(Iterable<String> dartNames, String nbtName) {
  final upper = nbtName.toUpperCase();
  for (final name in dartNames) {
    if (name.toUpperCase() == upper) return name;
  }
  return null;
}

/// `Direction.name()` for NBT.
String directionNbtName(Direction direction) => enumNbtName(direction.name);

/// `BrassTunnelBlockEntity.readDirection`: the constant named [nbtName], or the
/// first constant (`down`) for an unknown name.
Direction directionFromNbtName(String nbtName) {
  final name = enumDartName([
    for (final d in Direction.values) d.name,
  ], nbtName);
  for (final d in Direction.values) {
    if (d.name == name) return d;
  }
  return Direction.values.first;
}

/// The values of `writeFlapsAndSides`' `IntTag` list.
List<int> directionValues(Iterable<Direction> directions) => [
  for (final d in directions) d.data3d,
];

/// The directions of the `IntTag` values; unknown values are clamped like
/// `Direction.from3DDataValue`.
Set<Direction> directionsFromValues(Iterable<int> values) => {
  for (final v in values) Direction.from3DDataValue(v),
};
