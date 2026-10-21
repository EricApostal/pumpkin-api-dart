// `ElevatorColumn.ColumnCoords`: the column of a contact (its block x/z and the side it faces).
// Kept free of host imports so the NBT form can be round-tripped in `dart test`.
//
// Java: `content/contraptions/elevator/ElevatorColumn.ColumnCoords`.
import '../../common/common.dart';
import '../../conveyance/nbt_names.dart'
    show directionFromNbtName, directionNbtName;
import '../core/nbt_map.dart';

/// `ElevatorColumn.ColumnCoords`: the column of a contact: its block x/z and the side the contact
/// faces.
final class ColumnCoords {
  final int x;
  final int z;
  final Direction side;

  const ColumnCoords(this.x, this.z, this.side);

  ColumnCoords relative(Pos anchor) =>
      ColumnCoords(x + anchor.$1, z + anchor.$3, side);

  /// `Side` is the Java enum name (`Direction.name()`, upper case); a missing or unknown side falls
  /// back to `Direction.values()[0]` (`getEnumConstants()[0]`), i.e. [Direction.down].
  NbtMap write() => NbtMap()
    ..putInt('X', x)
    ..putInt('Z', z)
    ..putString('Side', directionNbtName(side));

  static ColumnCoords read(NbtMap tag) => ColumnCoords(
    tag.getInt('X'),
    tag.getInt('Z'),
    directionFromNbtName(tag.getString('Side')),
  );

  @override
  bool operator ==(Object other) =>
      other is ColumnCoords &&
      other.x == x &&
      other.z == z &&
      other.side == side;

  @override
  int get hashCode => Object.hash(x, z, side);

  @override
  String toString() => 'ColumnCoords($x, $z, $side)';
}
