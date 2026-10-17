// Directions and block positions of the turtle model. Binding-free.
//
// The order and the axes are Minecraft's `Direction`: north is -z, south +z,
// west -x, east +x; the clockwise turn of a horizontal direction is seen from
// above (north -> east -> south -> west).

/// A block face / direction.
enum Dir {
  down(0, -1, 0),
  up(0, 1, 0),
  north(0, 0, -1),
  south(0, 0, 1),
  west(-1, 0, 0),
  east(1, 0, 0);

  final int dx;
  final int dy;
  final int dz;

  const Dir(this.dx, this.dy, this.dz);

  bool get isHorizontal => this != down && this != up;

  Dir get opposite => switch (this) {
    down => up,
    up => down,
    north => south,
    south => north,
    west => east,
    east => west,
  };

  /// A quarter turn clockwise, seen from above (horizontal directions only;
  /// vertical ones stay).
  Dir get clockwise => switch (this) {
    north => east,
    east => south,
    south => west,
    west => north,
    _ => this,
  };

  Dir get counterClockwise => switch (this) {
    north => west,
    west => south,
    south => east,
    east => north,
    _ => this,
  };

  /// The direction called [name] (`north`, ...), or null.
  static Dir? parse(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// A block position in a world.
final class WorldPos {
  final int x;
  final int y;
  final int z;

  const WorldPos(this.x, this.y, this.z);

  WorldPos relative(Dir direction) => WorldPos(x + direction.dx, y + direction.dy, z + direction.dz);

  @override
  bool operator ==(Object other) => other is WorldPos && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '($x, $y, $z)';
}
