import 'dart:math' as math;

/// A point or direction in 3D space: the same record type the generated API
/// uses for positions, so every `getPosition()` result gains the [Vec3Math]
/// methods.
typedef Vec3 = (double, double, double);

/// Creates a [Vec3].
Vec3 vec3(double x, double y, double z) => (x, y, z);

/// The zero vector.
const Vec3 vec3Zero = (0.0, 0.0, 0.0);

const double _degToRad = math.pi / 180.0;
const double _radToDeg = 180.0 / math.pi;

/// Vector math on `(double, double, double)` records.
///
/// ```dart
/// final eye = player.position + vec3(0, 1.62, 0);
/// final d = eye.distanceTo(target.position);
/// ```
extension Vec3Math on (double, double, double) {
  /// The x component.
  double get x => $1;

  /// The y component.
  double get y => $2;

  /// The z component.
  double get z => $3;

  /// Component-wise sum.
  Vec3 operator +(Vec3 o) => ($1 + o.$1, $2 + o.$2, $3 + o.$3);

  /// Component-wise difference.
  Vec3 operator -(Vec3 o) => ($1 - o.$1, $2 - o.$2, $3 - o.$3);

  /// Negated vector.
  Vec3 operator -() => (-$1, -$2, -$3);

  /// Scales by [k].
  Vec3 operator *(num k) => ($1 * k, $2 * k, $3 * k);

  /// Divides by [k].
  Vec3 operator /(num k) => ($1 / k, $2 / k, $3 / k);

  /// Component-wise product.
  Vec3 multiplyBy(Vec3 o) => ($1 * o.$1, $2 * o.$2, $3 * o.$3);

  /// Component-wise quotient.
  Vec3 divideBy(Vec3 o) => ($1 / o.$1, $2 / o.$2, $3 / o.$3);

  /// A copy with a different x.
  Vec3 withX(double v) => (v, $2, $3);

  /// A copy with a different y.
  Vec3 withY(double v) => ($1, v, $3);

  /// A copy with a different z.
  Vec3 withZ(double v) => ($1, $2, v);

  /// Squared length.
  double get lengthSquared => $1 * $1 + $2 * $2 + $3 * $3;

  /// Euclidean length.
  double get length => math.sqrt(lengthSquared);

  /// Whether every component is zero.
  bool get isZero => $1 == 0 && $2 == 0 && $3 == 0;

  /// Distance to [o].
  double distanceTo(Vec3 o) => (this - o).length;

  /// Squared distance to [o] (cheaper, good for comparisons).
  double distanceSquaredTo(Vec3 o) => (this - o).lengthSquared;

  /// Distance to [o] ignoring y.
  double horizontalDistanceTo(Vec3 o) {
    final dx = $1 - o.$1, dz = $3 - o.$3;
    return math.sqrt(dx * dx + dz * dz);
  }

  /// This vector with length 1, or the zero vector if its length is 0.
  Vec3 get normalized {
    final l = length;
    return l == 0 ? vec3Zero : this / l;
  }

  /// Dot product.
  double dot(Vec3 o) => $1 * o.$1 + $2 * o.$2 + $3 * o.$3;

  /// Cross product.
  Vec3 cross(Vec3 o) => (
    $2 * o.$3 - $3 * o.$2,
    $3 * o.$1 - $1 * o.$3,
    $1 * o.$2 - $2 * o.$1,
  );

  /// Linear interpolation: [t] 0 is this, 1 is [o].
  Vec3 lerp(Vec3 o, double t) => (
    $1 + (o.$1 - $1) * t,
    $2 + (o.$2 - $2) * t,
    $3 + (o.$3 - $3) * t,
  );

  /// The angle in radians between this vector and [o] (0 if either is zero).
  double angleTo(Vec3 o) {
    final d = length * o.length;
    if (d == 0) return 0;
    return math.acos((dot(o) / d).clamp(-1.0, 1.0));
  }

  /// Scales the vector down so its length is at most [max].
  Vec3 clampLength(double max) {
    final l = length;
    return l <= max || l == 0 ? this : this * (max / l);
  }

  /// Component-wise floor.
  Vec3 floorVec() => ($1.floorToDouble(), $2.floorToDouble(), $3.floorToDouble());

  /// Component-wise round.
  Vec3 roundVec() => ($1.roundToDouble(), $2.roundToDouble(), $3.roundToDouble());

  /// The block coordinates containing this point (floored), as ints.
  (int, int, int) get blockCoords => ($1.floor(), $2.floor(), $3.floor());

  /// The nearest block coordinates (rounded), as ints.
  (int, int, int) get roundedBlockCoords => ($1.round(), $2.round(), $3.round());

  /// Yaw and pitch (degrees) that make something at this position face
  /// [target], in Minecraft's convention. Returns `(0, 0)` if equal.
  (double, double) rotationTo(Vec3 target) => rotationFromDirection(target - this);

  /// Formats as `x, y, z` with [decimals] decimals.
  String describe({int decimals = 2}) =>
      '${($1 + 0.0).toStringAsFixed(decimals)}, '
      '${($2 + 0.0).toStringAsFixed(decimals)}, '
      '${($3 + 0.0).toStringAsFixed(decimals)}';
}

/// The unit direction a viewer with [yaw] and [pitch] (degrees) looks in.
///
/// Minecraft convention: yaw 0 looks toward +z (south), yaw 90 toward -x
/// (west), pitch -90 straight up and pitch 90 straight down.
Vec3 directionFromRotation(double yaw, double pitch) {
  final y = yaw * _degToRad, p = pitch * _degToRad;
  final cp = math.cos(p);
  return (-math.sin(y) * cp, -math.sin(p), math.cos(y) * cp);
}

/// The inverse of [directionFromRotation]: `(yaw, pitch)` in degrees for
/// [direction]. The yaw is in `(-180, 180]`. A zero vector gives `(0, 0)`.
(double, double) rotationFromDirection(Vec3 direction) {
  final l = direction.length;
  if (l == 0) return (0.0, 0.0);
  final yaw = math.atan2(-direction.$1, direction.$3) * _radToDeg;
  final pitch = -math.asin((direction.$2 / l).clamp(-1.0, 1.0)) * _radToDeg;
  return (yaw, pitch);
}

/// An axis-aligned box of whole blocks, both corners inclusive.
///
/// ```dart
/// final room = Cuboid.corners((0, 64, 0), (9, 68, 9));
/// room.volume; // 500
/// ```
///
/// With bindings available, `package:pumpkin_api` adds `blocks` (a lazy
/// iterable of `BlockPos`) and world filling on top, see `CuboidBlocks` and
/// `WorldFill`.
final class Cuboid {
  /// Smallest x, y and z.
  final (int, int, int) min;

  /// Largest x, y and z (inclusive).
  final (int, int, int) max;

  const Cuboid._(this.min, this.max);

  /// The box spanned by two corners, in any order.
  factory Cuboid.corners((int, int, int) a, (int, int, int) b) => Cuboid._(
    (math.min(a.$1, b.$1), math.min(a.$2, b.$2), math.min(a.$3, b.$3)),
    (math.max(a.$1, b.$1), math.max(a.$2, b.$2), math.max(a.$3, b.$3)),
  );

  /// The blocks within [radius] blocks (per axis) of the block containing
  /// [center].
  factory Cuboid.around(Vec3 center, int radius) {
    final c = center.blockCoords;
    return Cuboid.corners(
      (c.$1 - radius, c.$2 - radius, c.$3 - radius),
      (c.$1 + radius, c.$2 + radius, c.$3 + radius),
    );
  }

  /// Extent in blocks along x.
  int get sizeX => max.$1 - min.$1 + 1;

  /// Extent in blocks along y.
  int get sizeY => max.$2 - min.$2 + 1;

  /// Extent in blocks along z.
  int get sizeZ => max.$3 - min.$3 + 1;

  /// Number of blocks.
  int get volume => sizeX * sizeY * sizeZ;

  /// The geometric center of the box (so a single block at 0,0,0 has center
  /// 0.5, 0.5, 0.5).
  Vec3 get center => (
    min.$1 + sizeX / 2,
    min.$2 + sizeY / 2,
    min.$3 + sizeZ / 2,
  );

  /// Whether the block at ([x], [y], [z]) is inside.
  bool containsBlockXYZ(int x, int y, int z) =>
      x >= min.$1 &&
      x <= max.$1 &&
      y >= min.$2 &&
      y <= max.$2 &&
      z >= min.$3 &&
      z <= max.$3;

  /// Whether the point [p] is inside (the box spans `min` to `max + 1`).
  bool contains(Vec3 p) =>
      p.$1 >= min.$1 &&
      p.$1 < max.$1 + 1 &&
      p.$2 >= min.$2 &&
      p.$2 < max.$2 + 1 &&
      p.$3 >= min.$3 &&
      p.$3 < max.$3 + 1;

  /// Grows the box by [n] blocks on every side (negative shrinks; an empty
  /// result collapses onto its center block).
  Cuboid expand(int n) => expandBy(n, n, n);

  /// Grows the box by [x], [y], [z] blocks on each side of that axis.
  Cuboid expandBy(int x, int y, int z) => Cuboid.corners(
    (min.$1 - x, min.$2 - y, min.$3 - z),
    (max.$1 + x, max.$2 + y, max.$3 + z),
  );

  /// The box moved by ([x], [y], [z]) blocks.
  Cuboid translate(int x, int y, int z) => Cuboid._(
    (min.$1 + x, min.$2 + y, min.$3 + z),
    (max.$1 + x, max.$2 + y, max.$3 + z),
  );

  /// Whether the two boxes share at least one block.
  bool intersects(Cuboid o) =>
      min.$1 <= o.max.$1 &&
      max.$1 >= o.min.$1 &&
      min.$2 <= o.max.$2 &&
      max.$2 >= o.min.$2 &&
      min.$3 <= o.max.$3 &&
      max.$3 >= o.min.$3;

  /// The shared blocks, or null if the boxes don't intersect.
  Cuboid? intersection(Cuboid o) {
    if (!intersects(o)) return null;
    return Cuboid._(
      (math.max(min.$1, o.min.$1), math.max(min.$2, o.min.$2), math.max(min.$3, o.min.$3)),
      (math.min(max.$1, o.max.$1), math.min(max.$2, o.max.$2), math.min(max.$3, o.max.$3)),
    );
  }

  /// The smallest box containing both.
  Cuboid union(Cuboid o) => Cuboid.corners(
    (math.min(min.$1, o.min.$1), math.min(min.$2, o.min.$2), math.min(min.$3, o.min.$3)),
    (math.max(max.$1, o.max.$1), math.max(max.$2, o.max.$2), math.max(max.$3, o.max.$3)),
  );

  /// Lazily iterates all block coordinates, x fastest, then z, then y.
  Iterable<(int, int, int)> get blockCoords sync* {
    for (var y = min.$2; y <= max.$2; y++) {
      for (var z = min.$3; z <= max.$3; z++) {
        for (var x = min.$1; x <= max.$1; x++) {
          yield (x, y, z);
        }
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Cuboid && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'Cuboid($min .. $max)';
}

/// Another name for [Cuboid].
typedef Region = Cuboid;

/// An immutable position and rotation in a named world. Plain data: it holds
/// no host handles, so it can be stored and compared freely.
///
/// [world] is the world name as the server reports it (for example `world`).
final class Location {
  /// The world name.
  final String world;

  /// Position.
  final double x, y, z;

  /// Horizontal rotation in degrees (0 = +z, 90 = -x).
  final double yaw;

  /// Vertical rotation in degrees (-90 = up).
  final double pitch;

  /// Creates a location.
  const Location({
    required this.world,
    required this.x,
    required this.y,
    required this.z,
    this.yaw = 0,
    this.pitch = 0,
  });

  /// Creates a location from a [Vec3].
  factory Location.fromVec3(
    String world,
    Vec3 position, {
    double yaw = 0,
    double pitch = 0,
  }) => Location(
    world: world,
    x: position.$1,
    y: position.$2,
    z: position.$3,
    yaw: yaw,
    pitch: pitch,
  );

  /// The position as a [Vec3].
  Vec3 get position => (x, y, z);

  /// The block coordinates containing the position.
  (int, int, int) get blockCoords => (x.floor(), y.floor(), z.floor());

  /// The unit vector this location faces.
  Vec3 get direction => directionFromRotation(yaw, pitch);

  /// A copy with the given fields replaced.
  Location copyWith({
    String? world,
    double? x,
    double? y,
    double? z,
    double? yaw,
    double? pitch,
  }) => Location(
    world: world ?? this.world,
    x: x ?? this.x,
    y: y ?? this.y,
    z: z ?? this.z,
    yaw: yaw ?? this.yaw,
    pitch: pitch ?? this.pitch,
  );

  /// A copy moved by [delta].
  Location add(Vec3 delta) =>
      copyWith(x: x + delta.$1, y: y + delta.$2, z: z + delta.$3);

  /// A copy at [p], keeping world and rotation.
  Location withPosition(Vec3 p) => copyWith(x: p.$1, y: p.$2, z: p.$3);

  /// Distance to [other], or infinity when they are in different worlds.
  double distanceTo(Location other) =>
      world == other.world ? position.distanceTo(other.position) : double.infinity;

  /// A short readable form.
  String describe({int decimals = 1}) =>
      '$world (${position.describe(decimals: decimals)}) '
      'yaw=${yaw.toStringAsFixed(decimals)} pitch=${pitch.toStringAsFixed(decimals)}';

  @override
  bool operator ==(Object other) =>
      other is Location &&
      other.world == world &&
      other.x == x &&
      other.y == y &&
      other.z == z &&
      other.yaw == yaw &&
      other.pitch == pitch;

  @override
  int get hashCode => Object.hash(world, x, y, z, yaw, pitch);

  @override
  String toString() => 'Location(${describe()})';
}
