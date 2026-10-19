// Axis aligned boxes (pure): `Aabb` (doubles, `net.minecraft.world.phys.AABB`) and
// `BlockBounds` (inclusive ints, `net.minecraft.world.level.levelgen.structure.BoundingBox`).
import 'dart:math' as math;

import 'package:pumpkin_api/src/geometry.dart' show Vec3, Vec3Math;

import 'direction.dart';
import 'pos.dart';

/// `AABB`.
final class Aabb {
  final double minX, minY, minZ, maxX, maxY, maxZ;

  const Aabb(this.minX, this.minY, this.minZ, this.maxX, this.maxY, this.maxZ);

  /// `new AABB(Vec3, Vec3)` (corners in any order).
  factory Aabb.between(Vec3 a, Vec3 b) => Aabb(
    math.min(a.$1, b.$1),
    math.min(a.$2, b.$2),
    math.min(a.$3, b.$3),
    math.max(a.$1, b.$1),
    math.max(a.$2, b.$2),
    math.max(a.$3, b.$3),
  );

  /// `new AABB(BlockPos)`: the unit box of the block.
  factory Aabb.ofBlock(Pos p) => Aabb(p.$1.toDouble(), p.$2.toDouble(), p.$3.toDouble(), p.$1 + 1.0, p.$2 + 1.0, p.$3 + 1.0);

  /// `AABB.ofSize(center, x, y, z)`.
  factory Aabb.ofSize(Vec3 c, double x, double y, double z) =>
      Aabb(c.$1 - x / 2, c.$2 - y / 2, c.$3 - z / 2, c.$1 + x / 2, c.$2 + y / 2, c.$3 + z / 2);

  /// `AABB.unitCubeFromLowerCorner`.
  factory Aabb.unitFrom(Vec3 v) => Aabb(v.$1, v.$2, v.$3, v.$1 + 1, v.$2 + 1, v.$3 + 1);

  double get xSize => maxX - minX;
  double get ySize => maxY - minY;
  double get zSize => maxZ - minZ;
  Vec3 get center => (minX + (maxX - minX) * 0.5, minY + (maxY - minY) * 0.5, minZ + (maxZ - minZ) * 0.5);
  Vec3 get minPos => (minX, minY, minZ);
  Vec3 get maxPos => (maxX, maxY, maxZ);

  double min(Axis a) => a.choose(minX, minY, minZ);
  double max(Axis a) => a.choose(maxX, maxY, maxZ);

  Aabb inflate(double x, [double? y, double? z]) =>
      Aabb(minX - x, minY - (y ?? x), minZ - (z ?? x), maxX + x, maxY + (y ?? x), maxZ + (z ?? x));

  Aabb deflate(double x, [double? y, double? z]) => inflate(-x, y == null ? null : -y, z == null ? null : -z);

  Aabb move(double x, double y, double z) => Aabb(minX + x, minY + y, minZ + z, maxX + x, maxY + y, maxZ + z);

  Aabb moveBy(Vec3 v) => move(v.$1, v.$2, v.$3);

  Aabb expandTowards(double x, double y, double z) {
    var a = minX, b = minY, c = minZ, d = maxX, e = maxY, f = maxZ;
    if (x < 0) {
      a += x;
    } else if (x > 0) {
      d += x;
    }
    if (y < 0) {
      b += y;
    } else if (y > 0) {
      e += y;
    }
    if (z < 0) {
      c += z;
    } else if (z > 0) {
      f += z;
    }
    return Aabb(a, b, c, d, e, f);
  }

  Aabb intersect(Aabb o) => Aabb(
    math.max(minX, o.minX),
    math.max(minY, o.minY),
    math.max(minZ, o.minZ),
    math.min(maxX, o.maxX),
    math.min(maxY, o.maxY),
    math.min(maxZ, o.maxZ),
  );

  /// `minmax` (the box containing both).
  Aabb minmax(Aabb o) => Aabb(
    math.min(minX, o.minX),
    math.min(minY, o.minY),
    math.min(minZ, o.minZ),
    math.max(maxX, o.maxX),
    math.max(maxY, o.maxY),
    math.max(maxZ, o.maxZ),
  );

  bool intersects(Aabb o) =>
      minX < o.maxX && maxX > o.minX && minY < o.maxY && maxY > o.minY && minZ < o.maxZ && maxZ > o.minZ;

  /// `AABB.contains(x, y, z)`.
  bool contains(Vec3 v) => v.$1 >= minX && v.$1 < maxX && v.$2 >= minY && v.$2 < maxY && v.$3 >= minZ && v.$3 < maxZ;

  double distanceToSqr(Vec3 v) {
    final dx = math.max(math.max(minX - v.$1, v.$1 - maxX), 0);
    final dy = math.max(math.max(minY - v.$2, v.$2 - maxY), 0);
    final dz = math.max(math.max(minZ - v.$3, v.$3 - maxZ), 0);
    return (dx * dx + dy * dy + dz * dz).toDouble();
  }

  /// `AABB.clip(from, to)`: the point where the segment enters the box, or `null`.
  Vec3? clip(Vec3 from, Vec3 to) {
    var tMin = 0.0, tMax = 1.0;
    final d = to - from;
    for (final axis in Axis.values) {
      final o = axis.choose(from.$1, from.$2, from.$3);
      final dir = axis.choose(d.$1, d.$2, d.$3);
      final lo = min(axis), hi = max(axis);
      if (dir.abs() < 1.0e-7) {
        if (o < lo || o > hi) return null;
      } else {
        var t1 = (lo - o) / dir, t2 = (hi - o) / dir;
        if (t1 > t2) {
          final t = t1;
          t1 = t2;
          t2 = t;
        }
        tMin = math.max(tMin, t1);
        tMax = math.min(tMax, t2);
        if (tMin > tMax) return null;
      }
    }
    return from + d * tMin;
  }

  @override
  bool operator ==(Object other) =>
      other is Aabb && other.minX == minX && other.minY == minY && other.minZ == minZ && other.maxX == maxX && other.maxY == maxY && other.maxZ == maxZ;

  @override
  int get hashCode => Object.hash(minX, minY, minZ, maxX, maxY, maxZ);

  @override
  String toString() => 'AABB[$minX, $minY, $minZ] -> [$maxX, $maxY, $maxZ]';
}

/// `BoundingBox` (integer, inclusive on both ends) and the static helpers of `BBHelper`.
final class BlockBounds {
  final int minX, minY, minZ, maxX, maxY, maxZ;

  const BlockBounds(this.minX, this.minY, this.minZ, this.maxX, this.maxY, this.maxZ);

  /// `BoundingBox.fromCorners`.
  factory BlockBounds.fromCorners(Pos a, Pos b) => BlockBounds(
    math.min(a.$1, b.$1),
    math.min(a.$2, b.$2),
    math.min(a.$3, b.$3),
    math.max(a.$1, b.$1),
    math.max(a.$2, b.$2),
    math.max(a.$3, b.$3),
  );

  /// `new BoundingBox(BlockPos)`.
  factory BlockBounds.single(Pos p) => BlockBounds(p.$1, p.$2, p.$3, p.$1, p.$2, p.$3);

  /// `BoundingBox.orientBox`-less constructor from an origin and size: `[origin, origin + size - 1]`.
  factory BlockBounds.ofSize(Pos origin, Pos size) =>
      BlockBounds(origin.$1, origin.$2, origin.$3, origin.$1 + size.$1 - 1, origin.$2 + size.$2 - 1, origin.$3 + size.$3 - 1);

  int get xSpan => maxX - minX + 1;
  int get ySpan => maxY - minY + 1;
  int get zSpan => maxZ - minZ + 1;
  Pos get minPos => (minX, minY, minZ);
  Pos get maxPos => (maxX, maxY, maxZ);
  Pos get size => (xSpan, ySpan, zSpan);
  Pos get center => (minX + (maxX - minX + 1) ~/ 2, minY + (maxY - minY + 1) ~/ 2, minZ + (maxZ - minZ + 1) ~/ 2);

  bool isInside(Pos p) =>
      p.$1 >= minX && p.$1 <= maxX && p.$2 >= minY && p.$2 <= maxY && p.$3 >= minZ && p.$3 <= maxZ;

  bool intersects(BlockBounds o) =>
      maxX >= o.minX && minX <= o.maxX && maxZ >= o.minZ && minZ <= o.maxZ && maxY >= o.minY && minY <= o.maxY;

  BlockBounds moved(int dx, int dy, int dz) => BlockBounds(minX + dx, minY + dy, minZ + dz, maxX + dx, maxY + dy, maxZ + dz);

  BlockBounds inflatedBy(int n) => BlockBounds(minX - n, minY - n, minZ - n, maxX + n, maxY + n, maxZ + n);

  /// `BBHelper.encapsulate(bb, pos)`.
  BlockBounds encapsulatePos(Pos p) => BlockBounds(
    math.min(minX, p.$1),
    math.min(minY, p.$2),
    math.min(minZ, p.$3),
    math.max(maxX, p.$1),
    math.max(maxY, p.$2),
    math.max(maxZ, p.$3),
  );

  /// `BBHelper.encapsulate(bb, bb2)`.
  BlockBounds encapsulate(BlockBounds o) => BlockBounds(
    math.min(minX, o.minX),
    math.min(minY, o.minY),
    math.min(minZ, o.minZ),
    math.max(maxX, o.maxX),
    math.max(maxY, o.maxY),
    math.max(maxZ, o.maxZ),
  );

  /// `AABB.of(BoundingBox)`: the box covering all included blocks.
  Aabb toAabb() => Aabb(minX.toDouble(), minY.toDouble(), minZ.toDouble(), maxX + 1.0, maxY + 1.0, maxZ + 1.0);

  /// All positions in the box (x fastest, then z, then y).
  Iterable<Pos> positions() => minPos.boxTo(maxPos);

  @override
  bool operator ==(Object other) =>
      other is BlockBounds && other.minX == minX && other.minY == minY && other.minZ == minZ && other.maxX == maxX && other.maxY == maxY && other.maxZ == maxZ;

  @override
  int get hashCode => Object.hash(minX, minY, minZ, maxX, maxY, maxZ);

  @override
  String toString() => 'BoundingBox[$minX, $minY, $minZ -> $maxX, $maxY, $maxZ]';
}
