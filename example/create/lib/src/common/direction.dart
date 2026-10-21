// Direction, Axis, Rotation and Mirror (pure), with Minecraft's exact semantics
// (`net.minecraft.core.Direction`, `Rotation`, `Mirror`). Positions are
// `(int, int, int)` records (see `pos.dart`), vectors `(double, double, double)`.
import 'dart:typed_data';

/// `Direction.Axis`.
enum Axis {
  x('x'),
  y('y'),
  z('z');

  const Axis(this.serializedName);

  final String serializedName;

  bool get isVertical => this == y;
  bool get isHorizontal => this != y;

  /// Picks the component of this axis (`Axis.choose`).
  T choose<T>(T x, T y, T z) => switch (this) {
    Axis.x => x,
    Axis.y => y,
    Axis.z => z,
  };

  /// The positive direction on this axis (`Axis.getPositive`).
  Direction get positive => Direction.fromAxisAndDirection(this, AxisDirection.positive);

  /// The negative direction on this axis.
  Direction get negative => Direction.fromAxisAndDirection(this, AxisDirection.negative);

  /// The two directions on this axis, positive first.
  List<Direction> get directions => [positive, negative];

  /// The other two axes in x, y, z order (`Iterate.axes` minus this one).
  List<Axis> get others => [for (final a in Axis.values) if (a != this) a];

  static Axis? byName(String name) {
    for (final a in Axis.values) {
      if (a.serializedName == name) return a;
    }
    return null;
  }
}

/// `Direction.AxisDirection`.
enum AxisDirection {
  positive(1),
  negative(-1);

  const AxisDirection(this.step);

  final int step;

  AxisDirection get opposite => this == positive ? negative : positive;
}

/// `Direction.Plane`.
enum Plane {
  horizontal,
  vertical;

  List<Direction> get directions =>
      this == horizontal ? Direction.horizontals : const [Direction.up, Direction.down];
}

/// `net.minecraft.core.Direction`, in the same order (`down, up, north, south, west, east`).
enum Direction {
  down(0, 1, -1, 'down', Axis.y, AxisDirection.negative, 0, -1, 0),
  up(1, 0, -1, 'up', Axis.y, AxisDirection.positive, 0, 1, 0),
  north(2, 3, 2, 'north', Axis.z, AxisDirection.negative, 0, 0, -1),
  south(3, 2, 0, 'south', Axis.z, AxisDirection.positive, 0, 0, 1),
  west(4, 5, 1, 'west', Axis.x, AxisDirection.negative, -1, 0, 0),
  east(5, 4, 3, 'east', Axis.x, AxisDirection.positive, 1, 0, 0);

  const Direction(
    this.data3d,
    this._oppositeIndex,
    this.data2d,
    this.serializedName,
    this.axis,
    this.axisDirection,
    this.stepX,
    this.stepY,
    this.stepZ,
  );

  /// `get3DDataValue` (the ordinal).
  final int data3d;
  final int _oppositeIndex;

  /// `get2DDataValue`: south 0, west 1, north 2, east 3; -1 for vertical.
  final int data2d;
  final String serializedName;
  final Axis axis;
  final AxisDirection axisDirection;
  final int stepX, stepY, stepZ;

  static const List<Direction> horizontals = [Direction.south, Direction.west, Direction.north, Direction.east];

  Direction get opposite => Direction.values[_oppositeIndex];

  int get get2DDataValue => data2d;

  bool get isHorizontal => axis.isHorizontal;
  bool get isVertical => axis.isVertical;

  /// `getUnitVec3`.
  (double, double, double) get unitVec3 => (stepX.toDouble(), stepY.toDouble(), stepZ.toDouble());

  /// `getNormal`.
  (int, int, int) get normal => (stepX, stepY, stepZ);

  /// `toYRot`: the yaw looking along this horizontal direction (0 for vertical).
  double get toYRot => data2d < 0 ? 0 : (data2d & 3) * 90.0;

  /// `getClockWise()` around Y.
  Direction get clockWise => switch (this) {
    Direction.north => Direction.east,
    Direction.east => Direction.south,
    Direction.south => Direction.west,
    Direction.west => Direction.north,
    _ => throw StateError('Unable to get Y-rotated facing of $this'),
  };

  /// `getCounterClockWise()` around Y.
  Direction get counterClockWise => switch (this) {
    Direction.north => Direction.west,
    Direction.west => Direction.south,
    Direction.south => Direction.east,
    Direction.east => Direction.north,
    _ => throw StateError('Unable to get CCW facing of $this'),
  };

  Direction get _clockWiseX => switch (this) {
    Direction.up => Direction.north,
    Direction.north => Direction.down,
    Direction.down => Direction.south,
    Direction.south => Direction.up,
    _ => throw StateError('Unable to get X-rotated facing of $this'),
  };

  Direction get _counterClockWiseX => switch (this) {
    Direction.up => Direction.south,
    Direction.south => Direction.down,
    Direction.down => Direction.north,
    Direction.north => Direction.up,
    _ => throw StateError('Unable to get X-rotated facing of $this'),
  };

  Direction get _clockWiseZ => switch (this) {
    Direction.up => Direction.east,
    Direction.east => Direction.down,
    Direction.down => Direction.west,
    Direction.west => Direction.up,
    _ => throw StateError('Unable to get Z-rotated facing of $this'),
  };

  Direction get _counterClockWiseZ => switch (this) {
    Direction.up => Direction.west,
    Direction.west => Direction.down,
    Direction.down => Direction.east,
    Direction.east => Direction.up,
    _ => throw StateError('Unable to get Z-rotated facing of $this'),
  };

  /// `getClockWise(Axis)`: this direction rotated clockwise around [around]
  /// (unchanged if it lies on that axis).
  Direction clockWiseAround(Axis around) => switch (around) {
    Axis.x => this != Direction.west && this != Direction.east ? _clockWiseX : this,
    Axis.y => this != Direction.up && this != Direction.down ? clockWise : this,
    Axis.z => this != Direction.north && this != Direction.south ? _clockWiseZ : this,
  };

  /// `getCounterClockWise(Axis)`.
  Direction counterClockWiseAround(Axis around) => switch (around) {
    Axis.x => this != Direction.west && this != Direction.east ? _counterClockWiseX : this,
    Axis.y => this != Direction.up && this != Direction.down ? counterClockWise : this,
    Axis.z => this != Direction.north && this != Direction.south ? _counterClockWiseZ : this,
  };

  /// `Direction.rotate(Rotation)` for a horizontal direction; vertical ones stay.
  Direction rotate(BlockRotation rotation) => rotation.rotate(this);

  /// `Mirror.mirror(Direction)`.
  Direction mirror(BlockMirror mirror) => mirror.mirrorDirection(this);

  /// `Direction.from3DDataValue`.
  static Direction from3DDataValue(int i) => values[i.abs() % values.length];

  /// `Direction.from2DDataValue`.
  static Direction from2DDataValue(int i) => horizontals[i.abs() % 4];

  /// `Direction.fromYRot`.
  static Direction fromYRot(double yRot) => from2DDataValue((yRot / 90 + 0.5).floor() & 3);

  /// `Direction.fromAxisAndDirection`.
  static Direction fromAxisAndDirection(Axis axis, AxisDirection d) => switch (axis) {
    Axis.x => d == AxisDirection.positive ? Direction.east : Direction.west,
    Axis.y => d == AxisDirection.positive ? Direction.up : Direction.down,
    Axis.z => d == AxisDirection.positive ? Direction.south : Direction.north,
  };

  /// `Direction.getApproximateNearest`: the constant whose normal has the highest dot product
  /// with `(x, y, z)`, `north` when nothing scores above the starting best -- the first in
  /// `down, up, north, south, west, east` that ties resolves like vanilla, i.e. only a strictly
  /// higher dot product wins.
  ///
  /// The double arguments are narrowed to `float` and the products are accumulated in `float`, as
  /// Java does, and the starting best is `Float.MIN_VALUE` -- the smallest *positive* float, not a
  /// negative bound -- so a vector whose dots are all zero or negative (a zero vector from a track
  /// shape with no axis, say) keeps `north`. A negative starting bound would hand such a vector to
  /// the first constant, `down`, which is a vertical direction no train can be assembled along.
  static Direction nearest(double x, double y, double z) {
    final dx = toFloat(x);
    final dy = toFloat(y);
    final dz = toFloat(z);
    var best = Direction.north;
    var bestDot = _floatMinValue;
    for (final d in values) {
      final dot = toFloat(
        toFloat(toFloat(dx * d.stepX) + toFloat(dy * d.stepY)) +
            toFloat(dz * d.stepZ),
      );
      if (dot > bestDot) {
        bestDot = dot;
        best = d;
      }
    }
    return best;
  }

  /// `Direction.fromDelta`, or `null` if the delta is not a unit step.
  static Direction? fromDelta(int x, int y, int z) {
    for (final d in values) {
      if (d.stepX == x && d.stepY == y && d.stepZ == z) return d;
    }
    return null;
  }

  /// `Direction.byName`.
  static Direction? byName(String name) {
    for (final d in values) {
      if (d.serializedName == name) return d;
    }
    return null;
  }

  /// The horizontal directions in `Direction.Plane.HORIZONTAL` order (north, east, south, west).
  static const List<Direction> planeHorizontal = [Direction.north, Direction.east, Direction.south, Direction.west];

  /// `Direction.orderedByNearest` for a view vector `(x, y, z)`.
  static List<Direction> orderedByNearest(double x, double y, double z) {
    final list = List<Direction>.of(values);
    list.sort((a, b) {
      final da = x * a.stepX + y * a.stepY + z * a.stepZ;
      final db = x * b.stepX + y * b.stepY + z * b.stepZ;
      return db.compareTo(da);
    });
    return list;
  }

  @override
  String toString() => serializedName;
}

/// `net.minecraft.world.level.block.Rotation`.
enum BlockRotation {
  none('none'),
  clockwise90('clockwise_90'),
  clockwise180('180'),
  counterclockwise90('counterclockwise_90');

  const BlockRotation(this.serializedName);

  final String serializedName;

  /// `Rotation.getRotated(Rotation)`: this rotation followed by [other].
  BlockRotation getRotated(BlockRotation other) {
    switch (other) {
      case BlockRotation.clockwise180:
        return switch (this) {
          BlockRotation.none => BlockRotation.clockwise180,
          BlockRotation.clockwise90 => BlockRotation.counterclockwise90,
          BlockRotation.clockwise180 => BlockRotation.none,
          BlockRotation.counterclockwise90 => BlockRotation.clockwise90,
        };
      case BlockRotation.counterclockwise90:
        return switch (this) {
          BlockRotation.none => BlockRotation.counterclockwise90,
          BlockRotation.clockwise90 => BlockRotation.none,
          BlockRotation.clockwise180 => BlockRotation.clockwise90,
          BlockRotation.counterclockwise90 => BlockRotation.clockwise180,
        };
      case BlockRotation.clockwise90:
        return switch (this) {
          BlockRotation.none => BlockRotation.clockwise90,
          BlockRotation.clockwise90 => BlockRotation.clockwise180,
          BlockRotation.clockwise180 => BlockRotation.counterclockwise90,
          BlockRotation.counterclockwise90 => BlockRotation.none,
        };
      case BlockRotation.none:
        return this;
    }
  }

  /// `Rotation.rotate(Direction)`: vertical directions are unchanged.
  Direction rotate(Direction d) {
    if (d.axis == Axis.y) return d;
    return switch (this) {
      BlockRotation.clockwise90 => d.clockWise,
      BlockRotation.clockwise180 => d.opposite,
      BlockRotation.counterclockwise90 => d.counterClockWise,
      BlockRotation.none => d,
    };
  }

  /// `Rotation.rotate(int rotation, int steps)` for rotations measured in `[0, steps)`.
  int rotateInt(int rotation, int steps) {
    final half = steps ~/ 2;
    return switch (this) {
      BlockRotation.clockwise90 => (rotation + steps ~/ 4) % steps,
      BlockRotation.clockwise180 => (rotation + half) % steps,
      BlockRotation.counterclockwise90 => (rotation + steps * 3 ~/ 4) % steps,
      BlockRotation.none => rotation,
    };
  }

  /// The number of clockwise quarter turns.
  int get quarterTurns => index;

  /// The rotation by [quarters] clockwise quarter turns (any integer).
  static BlockRotation ofQuarterTurns(int quarters) => values[((quarters % 4) + 4) % 4];

  /// `Rotation.rotate` applied to a yaw in degrees.
  double rotateYaw(double yaw) => yaw + index * 90.0;

  static BlockRotation? byName(String name) {
    for (final r in values) {
      if (r.serializedName == name) return r;
    }
    return null;
  }
}

/// `net.minecraft.world.level.block.Mirror`.
enum BlockMirror {
  none('none'),
  leftRight('left_right'),
  frontBack('front_back');

  const BlockMirror(this.serializedName);

  final String serializedName;

  /// `Mirror.mirror(int rotation, int steps)`.
  int mirrorInt(int rotation, int steps) {
    final half = steps ~/ 2;
    final base = rotation > half ? rotation - steps : rotation;
    return switch (this) {
      BlockMirror.frontBack => (steps - base) % steps,
      BlockMirror.leftRight => (half - base + steps) % steps,
      BlockMirror.none => rotation,
    };
  }

  /// `Mirror.getRotation(Direction)`: the rotation that, applied to [d], gives its mirror image.
  BlockRotation getRotation(Direction d) {
    final axis = d.axis;
    return (this == BlockMirror.leftRight && axis == Axis.z) || (this == BlockMirror.frontBack && axis == Axis.x)
        ? BlockRotation.clockwise180
        : BlockRotation.none;
  }

  /// `Mirror.mirror(Direction)`.
  Direction mirrorDirection(Direction d) {
    if (this == BlockMirror.frontBack && d.axis == Axis.x) return d.opposite;
    if (this == BlockMirror.leftRight && d.axis == Axis.z) return d.opposite;
    return d;
  }

  static BlockMirror? byName(String name) {
    for (final m in values) {
      if (m.serializedName == name) return m;
    }
    return null;
  }
}

/// `Mth.floorDiv`.
int floorDiv(int a, int b) => (a / b).floor();

/// `Mth.clamp`.
T clampNum<T extends num>(T v, T lo, T hi) => v < lo ? lo : (v > hi ? hi : v);

/// `Mth.equal(a, b)`.
bool mthEqual(double a, double b) => (b - a).abs() < 1.0e-5;

final Float32List _f32 = Float32List(1);

/// `Float.MIN_VALUE`: the smallest positive float, the starting best of
/// `Direction.getApproximateNearest` (it is not a negative bound).
const double _floatMinValue = 1.401298464324817e-45;

/// Rounds to float32, to reproduce Java `float` arithmetic where it matters.
double toFloat(double v) {
  _f32[0] = v;
  return _f32[0];
}
