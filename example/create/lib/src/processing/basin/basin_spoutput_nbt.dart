// `BasinBlockEntity`'s spout-output preferences: the `PreferredSpoutput` and
// `DisabledSpoutput` NBT forms, pure so the Java name round trip runs on the VM
// (the block entity itself imports the host bindings).
//
// Java (`BasinBlockEntity.java:213-215`, `:187-193`) writes the direction names
// (`writeEnum` -> `Direction.name()`, and `StringTag.valueOf(d.name())` for the
// list), reads the preferred one with `readEnum` (the first constant, `down`,
// for an unknown name) and the list with `Direction.valueOf` (which throws on an
// unknown name; the port skips it).
import '../../common/direction.dart';
import '../../conveyance/nbt_names.dart';

/// `writeEnum(compound, "PreferredSpoutput", preferred)`, `null` when there is
/// no preferred spout (Java writes the key only then).
String? preferredSpoutputNbtName(Direction? preferred) =>
    preferred == null ? null : directionNbtName(preferred);

/// The `StringTag` values of the `DisabledSpoutput` list.
List<String> disabledSpoutputNbtNames(Iterable<Direction> disabled) => [
  for (final d in disabled) directionNbtName(d),
];

/// `readEnum(compound, "PreferredSpoutput", Direction.class)`: the Java name
/// resolves to its constant, an unknown one to the first constant (`down`).
Direction preferredSpoutputFromNbt(String nbtName) =>
    directionFromNbtName(nbtName);

/// The directions of a `DisabledSpoutput` list; names that match no constant are
/// skipped (`Direction.valueOf` would throw).
Set<Direction> disabledSpoutputsFromNbt(Iterable<String?> names) {
  final out = <Direction>{};
  for (final name in names) {
    final direction = directionByNameIgnoreCase(name);
    if (direction != null) out.add(direction);
  }
  return out;
}
