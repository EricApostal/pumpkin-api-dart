// Block positions as `(int, int, int)` records (pure), with the methods of
// `BlockPos` / `Vec3i`. The host's `BlockPos` class converts with
// `PosBridge` in `host_bridge.dart`.
import 'package:pumpkin_api/src/geometry.dart' show Vec3;

import '../core/pos.dart' show packPos, unpackPos;
import 'direction.dart';

/// A block position.
typedef Pos = (int, int, int);

/// `BlockPos.ZERO`.
const Pos posZero = (0, 0, 0);

/// Builds a [Pos] (reads like `new BlockPos(x, y, z)`).
Pos pos(int x, int y, int z) => (x, y, z);

/// Methods of `BlockPos` on a [Pos].
extension PosMath on (int, int, int) {
  int get x => $1;
  int get y => $2;
  int get z => $3;

  Pos operator +(Pos o) => ($1 + o.$1, $2 + o.$2, $3 + o.$3);
  Pos operator -(Pos o) => ($1 - o.$1, $2 - o.$2, $3 - o.$3);
  Pos operator -() => (-$1, -$2, -$3);

  /// `BlockPos.offset`.
  Pos offset(int dx, int dy, int dz) => ($1 + dx, $2 + dy, $3 + dz);

  /// `BlockPos.offset(Vec3i)` / `Vec3i.subtract`: use `+` and `-`.
  Pos multiply(int k) => ($1 * k, $2 * k, $3 * k);

  Pos relative(Direction d, [int n = 1]) => ($1 + d.stepX * n, $2 + d.stepY * n, $3 + d.stepZ * n);

  /// `relative(Axis, n)`.
  Pos relativeAxis(Axis axis, int n) => switch (axis) {
    Axis.x => ($1 + n, $2, $3),
    Axis.y => ($1, $2 + n, $3),
    Axis.z => ($1, $2, $3 + n),
  };

  Pos get above => ($1, $2 + 1, $3);
  Pos get below => ($1, $2 - 1, $3);
  Pos aboveBy(int n) => ($1, $2 + n, $3);
  Pos belowBy(int n) => ($1, $2 - n, $3);
  Pos get north => ($1, $2, $3 - 1);
  Pos get south => ($1, $2, $3 + 1);
  Pos get east => ($1 + 1, $2, $3);
  Pos get west => ($1 - 1, $2, $3);

  Pos withX(int v) => (v, $2, $3);
  Pos withY(int v) => ($1, v, $3);
  Pos withZ(int v) => ($1, $2, v);

  /// `Vec3i.get(Axis)`.
  int get(Axis axis) => axis.choose($1, $2, $3);

  /// `Vec3i.cross`.
  Pos cross(Pos o) => ($2 * o.$3 - $3 * o.$2, $3 * o.$1 - $1 * o.$3, $1 * o.$2 - $2 * o.$1);

  /// `Vec3i.distSqr`.
  int distSqr(Pos o) {
    final dx = $1 - o.$1, dy = $2 - o.$2, dz = $3 - o.$3;
    return dx * dx + dy * dy + dz * dz;
  }

  /// `Vec3i.distManhattan`.
  int distManhattan(Pos o) => ($1 - o.$1).abs() + ($2 - o.$2).abs() + ($3 - o.$3).abs();

  /// `BlockPos.closerThan`-style comparison on block centres.
  bool closerThan(Pos o, double distance) => distSqr(o) < distance * distance;

  /// `Vec3.atLowerCornerOf`.
  Vec3 toVec3() => ($1.toDouble(), $2.toDouble(), $3.toDouble());

  /// `Vec3.atCenterOf`.
  Vec3 get center => ($1 + 0.5, $2 + 0.5, $3 + 0.5);

  /// `Vec3.atBottomCenterOf`.
  Vec3 get bottomCenter => ($1 + 0.5, $2.toDouble(), $3 + 0.5);

  /// `BlockPos.rotate(Rotation)` around the origin.
  Pos rotate(BlockRotation r) => switch (r) {
    BlockRotation.none => this,
    BlockRotation.clockwise90 => (-$3, $2, $1),
    BlockRotation.clockwise180 => (-$1, $2, -$3),
    BlockRotation.counterclockwise90 => ($3, $2, -$1),
  };

  /// `BlockPos.asLong`.
  int get asLong => packPos($1, $2, $3);

  /// The six neighbours in `Direction` order.
  List<Pos> get neighbours => [for (final d in Direction.values) relative(d)];

  /// `BlockPos.betweenClosed`-style iteration of the box with corners this and [o].
  Iterable<Pos> boxTo(Pos o) sync* {
    final x0 = $1 < o.$1 ? $1 : o.$1, x1 = $1 < o.$1 ? o.$1 : $1;
    final y0 = $2 < o.$2 ? $2 : o.$2, y1 = $2 < o.$2 ? o.$2 : $2;
    final z0 = $3 < o.$3 ? $3 : o.$3, z1 = $3 < o.$3 ? o.$3 : $3;
    for (var yy = y0; yy <= y1; yy++) {
      for (var zz = z0; zz <= z1; zz++) {
        for (var xx = x0; xx <= x1; xx++) {
          yield (xx, yy, zz);
        }
      }
    }
  }

  /// The chunk coordinates of this position.
  (int, int) get chunk => ($1 >> 4, $3 >> 4);

  String toShortString() => '$x, $y, $z';
}

/// `BlockPos.of(long)`.
Pos posFromLong(int packed) => unpackPos(packed);

/// The block containing the point (`BlockPos.containing`).
Pos posContaining(Vec3 v) => (v.$1.floor(), v.$2.floor(), v.$3.floor());

/// `BlockPos.betweenClosed(a, b)`.
Iterable<Pos> betweenClosed(Pos a, Pos b) => a.boxTo(b);

/// `StructureTemplate.transform(pos, mirror, rotation, pivot)`: mirrors then rotates [p]
/// around [pivot] exactly as vanilla does when placing a structure.
Pos transformPos(Pos p, BlockMirror mirror, BlockRotation rotation, Pos pivot) {
  var i = p.$1;
  final j = p.$2;
  var k = p.$3;
  var flag = true;
  switch (mirror) {
    case BlockMirror.leftRight:
      k = -k;
    case BlockMirror.frontBack:
      i = -i;
    case BlockMirror.none:
      flag = false;
  }
  final l = pivot.$1;
  final i1 = pivot.$3;
  switch (rotation) {
    case BlockRotation.counterclockwise90:
      return (l - i1 + k, j, l + i1 - i);
    case BlockRotation.clockwise90:
      return (l + i1 - k, j, i1 - l + i);
    case BlockRotation.clockwise180:
      return (l + l - i, j, i1 + i1 - k);
    case BlockRotation.none:
      return flag ? (i, j, k) : p;
  }
}

/// `StructureTemplate.transform(Vec3, mirror, rotation, pivot)`.
Vec3 transformVec(Vec3 v, BlockMirror mirror, BlockRotation rotation, Pos pivot) {
  var d0 = v.$1;
  final d1 = v.$2;
  var d2 = v.$3;
  var flag = true;
  switch (mirror) {
    case BlockMirror.leftRight:
      d2 = 1.0 - d2;
    case BlockMirror.frontBack:
      d0 = 1.0 - d0;
    case BlockMirror.none:
      flag = false;
  }
  final i = pivot.$1;
  final j = pivot.$3;
  switch (rotation) {
    case BlockRotation.counterclockwise90:
      return (i - j + d2, d1, i + j + 1.0 - d0);
    case BlockRotation.clockwise90:
      return (i + j + 1.0 - d2, d1, j - i + d0);
    case BlockRotation.clockwise180:
      return (i + i + 1.0 - d0, d1, j + j + 1.0 - d2);
    case BlockRotation.none:
      return flag ? (d0, d1, d2) : v;
  }
}
