// Pure integer geometry for the equipment module: block positions as records,
// Minecraft's `Direction` / `Axis` with the exact rotation semantics. No host imports.
import 'dart:math' as math;

/// A block position (x, y, z).
typedef P3 = (int, int, int);

extension P3Math on (int, int, int) {
  int get x => $1;
  int get y => $2;
  int get z => $3;
  P3 plus(P3 o) => ($1 + o.$1, $2 + o.$2, $3 + o.$3);
  P3 minus(P3 o) => ($1 - o.$1, $2 - o.$2, $3 - o.$3);
  P3 shift(int dx, int dy, int dz) => ($1 + dx, $2 + dy, $3 + dz);
  P3 rel(Dir d, [int n = 1]) => ($1 + d.dx * n, $2 + d.dy * n, $3 + d.dz * n);
  P3 get up1 => ($1, $2 + 1, $3);
  P3 get down1 => ($1, $2 - 1, $3);

  /// `BlockPos.closerThan(Vec3i, double)`: squared distance below the square of [distance].
  bool within(P3 o, double distance) {
    final dx = $1 - o.$1, dy = $2 - o.$2, dz = $3 - o.$3;
    return dx * dx + dy * dy + dz * dz < distance * distance;
  }
}

/// `Direction.Axis`.
enum Ax {
  x,
  y,
  z;

  /// `Axis.choose(x, y, z)`.
  T choose<T>(T xv, T yv, T zv) => switch (this) {
    Ax.x => xv,
    Ax.y => yv,
    Ax.z => zv,
  };

  bool get isVertical => this == Ax.y;
  bool get isHorizontal => this != Ax.y;

  static Ax? parse(String s) => switch (s) {
    'x' => Ax.x,
    'y' => Ax.y,
    'z' => Ax.z,
    _ => null,
  };
}

/// `Direction`, in Minecraft's declaration order (DOWN, UP, NORTH, SOUTH, WEST, EAST).
enum Dir {
  down(0, -1, 0, Ax.y, false),
  up(0, 1, 0, Ax.y, true),
  north(0, 0, -1, Ax.z, false),
  south(0, 0, 1, Ax.z, true),
  west(-1, 0, 0, Ax.x, false),
  east(1, 0, 0, Ax.x, true);

  const Dir(this.dx, this.dy, this.dz, this.axis, this.positive);

  final int dx, dy, dz;
  final Ax axis;
  final bool positive;

  /// `getAxisDirection().getStep()`.
  int get step => positive ? 1 : -1;

  bool get isHorizontal => axis != Ax.y;

  Dir get opposite => switch (this) {
    Dir.down => Dir.up,
    Dir.up => Dir.down,
    Dir.north => Dir.south,
    Dir.south => Dir.north,
    Dir.west => Dir.east,
    Dir.east => Dir.west,
  };

  /// `Direction.getClockWise()` (about Y, horizontals only).
  Dir get clockWise => switch (this) {
    Dir.north => Dir.east,
    Dir.east => Dir.south,
    Dir.south => Dir.west,
    Dir.west => Dir.north,
    _ => throw StateError('Unable to get Y-rotated facing of $this'),
  };

  Dir get counterClockWise => switch (this) {
    Dir.north => Dir.west,
    Dir.west => Dir.south,
    Dir.south => Dir.east,
    Dir.east => Dir.north,
    _ => throw StateError('Unable to get CCW facing of $this'),
  };

  Dir get _clockWiseX => switch (this) {
    Dir.up => Dir.north,
    Dir.north => Dir.down,
    Dir.down => Dir.south,
    Dir.south => Dir.up,
    _ => throw StateError('Unable to get X-rotated facing of $this'),
  };

  Dir get _clockWiseZ => switch (this) {
    Dir.up => Dir.east,
    Dir.east => Dir.down,
    Dir.down => Dir.west,
    Dir.west => Dir.up,
    _ => throw StateError('Unable to get Z-rotated facing of $this'),
  };

  /// `Direction.getClockWise(Axis)`.
  Dir clockWiseAbout(Ax a) => switch (a) {
    Ax.x => this != Dir.west && this != Dir.east ? _clockWiseX : this,
    Ax.y => this != Dir.up && this != Dir.down ? clockWise : this,
    Ax.z => this != Dir.north && this != Dir.south ? _clockWiseZ : this,
  };

  static Dir? parse(String s) {
    for (final d in Dir.values) {
      if (d.name == s) return d;
    }
    return null;
  }

  /// `Direction.get(AxisDirection, Axis)`.
  static Dir of(bool positive, Ax axis) => switch (axis) {
    Ax.x => positive ? Dir.east : Dir.west,
    Ax.y => positive ? Dir.up : Dir.down,
    Ax.z => positive ? Dir.south : Dir.north,
  };

  /// `Direction.getApproximateNearest(x, y, z)`.
  static Dir nearest(double x, double y, double z) {
    var best = Dir.north;
    var bestDot = -double.maxFinite;
    for (final d in Dir.values) {
      final dot = x * d.dx + y * d.dy + z * d.dz;
      if (dot > bestDot) {
        bestDot = dot;
        best = d;
      }
    }
    return best;
  }

  /// `Direction.fromYRot(yaw)`.
  static Dir fromYRot(double yaw) {
    const horizontal = [Dir.south, Dir.west, Dir.north, Dir.east];
    return horizontal[((yaw / 90 + 0.5).floor()) & 3];
  }
}

double floorMod(double a, double b) => a - (a / b).floorToDouble() * b;

/// Euclidean length of a 3-vector.
double len3(double x, double y, double z) => math.sqrt(x * x + y * y + z * z);
