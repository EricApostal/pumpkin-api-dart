// Java writes enum constants into NBT with `Enum.name()` (upper case). Dart's
// `Enum.name` is lower case, so every enum-valued key (the tunnel's
// `StackEnteredFrom`, the ejector's `State`, the basin's `PreferredSpoutput`,
// a contraption's `InitialOrientation`) goes through these helpers. Writing a
// Dart name instead is a silent failure: the reader's `Enum.valueOf`/`readEnum`
// finds no constant and falls back to the *first* one, far from the mistake.
//
// The direction list forms (`Flaps`, `Sides`) are Java `ListTag`s of `IntTag`,
// not int arrays, so only their values are pure; the container is built by the
// host block entities.
import '../common/direction.dart';

/// `Enum.name()` of the Dart constant [dartName].
///
/// Only for an enum whose Dart constant keeps the Java name (`Direction.north`
/// is `NORTH`); an enum with a Dart-only identifier (`ArmPhase.searchInputs` is
/// `SEARCH_INPUTS`) keeps an explicit `javaName`.
String enumNbtName(String dartName) => dartName.toUpperCase();

/// Java's `NBTHelper.readEnum` (and `Enum.valueOf`): the constant whose Java
/// name matches [nbtName], else the first constant (`getEnumConstants()[0]`).
///
/// [nameOf] is the Java constant name of a value; it defaults to `Enum.name`,
/// which is the Java name whenever the Dart constant keeps it. An enum whose
/// Dart identifier differs passes its `javaName`.
///
/// The comparison is case insensitive so a lower-case name written by an older
/// Dart build is still read; Java itself matches exactly, so this only ever
/// accepts more.
E enumFromNbtName<E extends Enum>(
  String? nbtName,
  List<E> values, {
  String Function(E value)? nameOf,
}) {
  final javaName = nameOf ?? (E value) => value.name;
  final wanted = nbtName?.toUpperCase();
  if (wanted != null) {
    for (final value in values) {
      if (javaName(value).toUpperCase() == wanted) return value;
    }
  }
  return values.first;
}

/// The constant whose Java name matches [nbtName] (case insensitively), or
/// `null` when none matches -- for a reader that has something to fall back to
/// other than the first constant (an absent key, a list of names).
E? enumByNameIgnoreCase<E extends Enum>(
  String? nbtName,
  List<E> values, {
  String Function(E value)? nameOf,
}) {
  final javaName = nameOf ?? (E value) => value.name;
  final wanted = nbtName?.toUpperCase();
  if (wanted == null) return null;
  for (final value in values) {
    if (javaName(value).toUpperCase() == wanted) return value;
  }
  return null;
}

/// `Direction.name()` for NBT.
String directionNbtName(Direction direction) => enumNbtName(direction.name);

/// `readDirection` / `readEnum(key, Direction.class)`: the constant named
/// [nbtName], or the first constant (`down`) for an unknown name.
Direction directionFromNbtName(String? nbtName) =>
    enumFromNbtName(nbtName, Direction.values);

/// The direction named [nbtName] (case insensitively), `null` when the name is
/// absent or unknown.
Direction? directionByNameIgnoreCase(String? nbtName) =>
    enumByNameIgnoreCase(nbtName, Direction.values);

/// The values of `writeFlapsAndSides`' `IntTag` list.
List<int> directionValues(Iterable<Direction> directions) => [
  for (final d in directions) d.data3d,
];

/// The directions of the `IntTag` values; unknown values are clamped like
/// `Direction.from3DDataValue`.
Set<Direction> directionsFromValues(Iterable<int> values) => {
  for (final v in values) Direction.from3DDataValue(v),
};
