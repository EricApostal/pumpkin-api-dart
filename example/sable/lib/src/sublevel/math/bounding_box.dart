// `dev.ryanhcode.sable.companion.math.BoundingBox3d` / `BoundingBox3i`:
// mutable axis-aligned boxes with the JOML-facing operations Sable uses.
//
// `BoundingBox3d` is a double box with inclusive max; `BoundingBox3i` is an
// integer box that is inclusive on both ends (so it covers the blocks
// `min..max`, unlike an `AABB`, which is half-open). Both are mutable, like
// their Java counterparts.
//
// Dart has no method overloading, so the Java `dest` overloads of the same name
// are split: the plain name takes an optional `dest` (defaulting to a fresh box,
// or to `this` in the concrete classes) and the variants that differ only in
// their first argument get a distinct name (`expandToPoint` / `expandToBox`,
// `transformMatrix`, ...).
//
// Pure: no host imports.
import 'dart:math' as math;

import 'package:pumpkin_api/src/geometry.dart' show Vec3;

import '../../common/bounds.dart' show Aabb, BlockBounds;
import '../../common/pos.dart' show Pos;
import 'pose.dart';
import 'vector.dart';

/// A read-only double bounding box.
abstract class BoundingBox3dc {
  const BoundingBox3dc();

  double get minX;
  double get minY;
  double get minZ;
  double get maxX;
  double get maxY;
  double get maxZ;

  /// Whether this box intersects [other].
  bool intersects(BoundingBox3dc other) =>
      intersectsValues(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// Whether this box intersects the half-open box [other].
  bool intersectsAabb(Aabb other) =>
      intersectsValues(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// Whether this box intersects the given bounds.
  bool intersectsValues(double minX, double minY, double minZ, double maxX, double maxY, double maxZ) =>
      this.maxX >= minX &&
      this.maxY >= minY &&
      this.maxZ >= minZ &&
      this.minX <= maxX &&
      this.minY <= maxY &&
      this.minZ <= maxZ;

  /// Whether this box contains [point].
  bool contains(Vector3d point) => containsValues(point.x, point.y, point.z);

  /// Whether this box contains the given point.
  bool containsValues(double x, double y, double z) =>
      x >= minX && x <= maxX && y >= minY && y <= maxY && z >= minZ && z <= maxZ;

  /// Expands this box to include [point], writing into [dest].
  BoundingBox3d expandToPoint(Vector3d point, [BoundingBox3d? dest]) =>
      expandToValues(point.x, point.y, point.z, dest);

  /// Expands this box to include the given point, writing into [dest].
  BoundingBox3d expandToValues(double x, double y, double z, [BoundingBox3d? dest]) {
    final out = dest ?? BoundingBox3d();
    out.setUnchecked(minX, minY, minZ, maxX, maxY, maxZ);
    out.maxX = math.max(out.maxX, x);
    out.maxY = math.max(out.maxY, y);
    out.maxZ = math.max(out.maxZ, z);
    out.minX = math.min(out.minX, x);
    out.minY = math.min(out.minY, y);
    out.minZ = math.min(out.minZ, z);
    return out;
  }

  /// Expands this box to include [other], writing into [dest].
  BoundingBox3d expandToBox(BoundingBox3dc other, [BoundingBox3d? dest]) {
    final out = dest ?? BoundingBox3d();
    out.setUnchecked(minX, minY, minZ, maxX, maxY, maxZ);
    out.maxX = math.max(out.maxX, other.maxX);
    out.maxY = math.max(out.maxY, other.maxY);
    out.maxZ = math.max(out.maxZ, other.maxZ);
    out.minX = math.min(out.minX, other.minX);
    out.minY = math.min(out.minY, other.minY);
    out.minZ = math.min(out.minZ, other.minZ);
    return out;
  }

  /// Expands this box by [amount] on all sides into [dest].
  BoundingBox3d expand(double amount, [BoundingBox3d? dest]) => expand3(amount, amount, amount, dest);

  /// Expands this box by the given amounts into [dest].
  BoundingBox3d expand3(double amountX, double amountY, double amountZ, [BoundingBox3d? dest]) =>
      (dest ?? BoundingBox3d()).setUnchecked(
        minX - amountX,
        minY - amountY,
        minZ - amountZ,
        maxX + amountX,
        maxY + amountY,
        maxZ + amountZ,
      );

  /// Moves this box by the given amounts into [dest].
  BoundingBox3d move(double amountX, double amountY, double amountZ, [BoundingBox3d? dest]) =>
      (dest ?? BoundingBox3d()).setUnchecked(
        minX + amountX,
        minY + amountY,
        minZ + amountZ,
        maxX + amountX,
        maxY + amountY,
        maxZ + amountZ,
      );

  /// The intersection of this box and [box], stored in [dest].
  BoundingBox3d intersect(BoundingBox3dc box, [BoundingBox3d? dest]) => (dest ?? BoundingBox3d()).setUnchecked(
    math.max(minX, box.minX),
    math.max(minY, box.minY),
    math.max(minZ, box.minZ),
    math.min(maxX, box.maxX),
    math.min(maxY, box.maxY),
    math.min(maxZ, box.maxZ),
  );

  /// Transforms this box by [pose], taking the bounds around the transformed
  /// corners, and stores the result in [dest].
  BoundingBox3d transform(Pose3dc pose, [BoundingBox3d? dest]) =>
      transformMatrix(pose.bakeIntoMatrix(Matrix4d()), dest);

  /// `transform(Pose3dc, Matrix4d, BoundingBox3d)`: reuses [bakedMatrix].
  BoundingBox3d transformWith(Pose3dc pose, Matrix4d bakedMatrix, [BoundingBox3d? dest]) =>
      transformMatrix(pose.bakeIntoMatrix(bakedMatrix), dest);

  /// Transforms this box by [mpose] and stores the result in [dest].
  BoundingBox3d transformMatrix(Matrix4d mpose, [BoundingBox3d? dest]) {
    final out = dest ?? BoundingBox3d();
    final minXv = minX, minYv = minY, minZv = minZ;
    final maxXv = maxX, maxYv = maxY, maxZv = maxZ;

    out.setUnchecked(
      double.infinity,
      double.infinity,
      double.infinity,
      double.negativeInfinity,
      double.negativeInfinity,
      double.negativeInfinity,
    );

    final corner = Vector3d();
    for (var i = 0; i <= 0x7; i++) {
      corner.set(
        (i & 0x1) == 0 ? minXv : maxXv,
        (i & 0x2) == 0 ? minYv : maxYv,
        (i & 0x4) == 0 ? minZv : maxZv,
      );
      out.expandToPoint(mpose.transformPosition(corner));
    }
    return out;
  }

  /// Transforms this box by the inverse of [pose], storing the result in [dest].
  BoundingBox3d transformInverse(Pose3dc pose, [BoundingBox3d? dest]) =>
      transformMatrixInverse(pose.bakeIntoMatrix(Matrix4d()).invertAffine(), dest);

  /// `transformInverse(Pose3dc, Matrix4d, BoundingBox3d)`.
  BoundingBox3d transformInverseWith(Pose3dc pose, Matrix4d bakedMatrix, [BoundingBox3d? dest]) =>
      transformMatrixInverse(pose.bakeIntoMatrix(bakedMatrix).invertAffine(), dest);

  /// Transforms this box by the inverse of [mpose], storing the result in [dest].
  BoundingBox3d transformMatrixInverse(Matrix4d mpose, [BoundingBox3d? dest]) => transformMatrix(mpose, dest);

  /// The center of this box.
  Vector3d center([Vector3d? dest]) => (dest ?? Vector3d()).set(
    (minX + maxX) / 2.0,
    (minY + maxY) / 2.0,
    (minZ + maxZ) / 2.0,
  );

  /// The side-length vector of this box.
  Vector3d size([Vector3d? dest]) => (dest ?? Vector3d()).set(maxX - minX, maxY - minY, maxZ - minZ);

  /// The chunk sections this box intersects.
  BoundingBox3i chunkBoundsFrom([BoundingBox3i? dest]) => (dest ?? BoundingBox3i()).setValues(
    minX.floor() >> 4,
    minY.floor() >> 4,
    minZ.floor() >> 4,
    maxX.floor() >> 4,
    maxY.floor() >> 4,
    maxZ.floor() >> 4,
  );

  /// The encompassing X range.
  double width() => maxX - minX + 1.0;

  /// The encompassing Y range.
  double height() => maxY - minY + 1.0;

  /// The encompassing Z range.
  double length() => maxZ - minZ + 1.0;

  /// The volume of this box.
  double volume() => (maxX - minX) * (maxY - minY) * (maxZ - minZ);

  /// A Mojang `AABB` with the same values.
  Aabb toMojang() => Aabb(minX, minY, minZ, maxX, maxY, maxZ);

  /// A record vector of the minimum corner.
  Vec3 minVec3() => (minX, minY, minZ);

  /// A record vector of the maximum corner.
  Vec3 maxVec3() => (maxX, maxY, maxZ);
}

/// A mutable double bounding box.
final class BoundingBox3d extends BoundingBox3dc {
  /// A box of zeroes (Java's `BoundingBox3d.EMPTY`).
  static final BoundingBox3d empty = BoundingBox3d();

  @override
  double minX;
  @override
  double minY;
  @override
  double minZ;
  @override
  double maxX;
  @override
  double maxY;
  @override
  double maxZ;

  /// An all-zero box.
  BoundingBox3d()
    : this.full(0.0, 0.0, 0.0, 0.0, 0.0, 0.0);

  /// A box with the given values; min/max are swapped into order.
  BoundingBox3d.full(double minX, double minY, double minZ, double maxX, double maxY, double maxZ)
    : minX = math.min(minX, maxX),
      minY = math.min(minY, maxY),
      minZ = math.min(minZ, maxZ),
      maxX = math.max(minX, maxX),
      maxY = math.max(minY, maxY),
      maxZ = math.max(minZ, maxZ);

  /// A box with the given values, *not* swapped into order.
  BoundingBox3d.unchecked(double minX, double minY, double minZ, double maxX, double maxY, double maxZ)
    : minX = minX,
      minY = minY,
      minZ = minZ,
      maxX = maxX,
      maxY = maxY,
      maxZ = maxZ;

  /// `new BoundingBox3d(BoundingBox3dc)`.
  BoundingBox3d.copy(BoundingBox3dc other)
    : this.full(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// `new BoundingBox3d(AABB)`.
  BoundingBox3d.fromAabb(Aabb other)
    : this.full(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// `new BoundingBox3d(BoundingBox)`: the box covering the blocks.
  BoundingBox3d.fromBlockBounds(BlockBounds other)
    : this.full(
        other.minX.toDouble(),
        other.minY.toDouble(),
        other.minZ.toDouble(),
        other.maxX + 1.0,
        other.maxY + 1.0,
        other.maxZ + 1.0,
      );

  /// `new BoundingBox3d(BlockPos)`: the unit box of the block.
  BoundingBox3d.fromPos(Pos pos)
    : this.full(pos.$1.toDouble(), pos.$2.toDouble(), pos.$3.toDouble(), pos.$1 + 1.0, pos.$2 + 1.0, pos.$3 + 1.0);

  /// `new BoundingBox3d(BoundingBox3ic)`: the box covering the blocks.
  BoundingBox3d.fromBoundingBox3i(BoundingBox3ic other)
    : this.full(
        other.minX.toDouble(),
        other.minY.toDouble(),
        other.minZ.toDouble(),
        other.maxX + 1.0,
        other.maxY + 1.0,
        other.maxZ + 1.0,
      );

  /// Sets this box from [other].
  BoundingBox3d set(BoundingBox3dc other) =>
      setValues(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// Sets this box from an `AABB`.
  BoundingBox3d setAabb(Aabb other) =>
      setValues(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// Sets this box, swapping min/max into order.
  BoundingBox3d setValues(double minX, double minY, double minZ, double maxX, double maxY, double maxZ) {
    this.minX = math.min(minX, maxX);
    this.minY = math.min(minY, maxY);
    this.minZ = math.min(minZ, maxZ);
    this.maxX = math.max(minX, maxX);
    this.maxY = math.max(minY, maxY);
    this.maxZ = math.max(minZ, maxZ);
    return this;
  }

  /// Sets this box without swapping.
  BoundingBox3d setUnchecked(double minX, double minY, double minZ, double maxX, double maxY, double maxZ) {
    this.minX = minX;
    this.minY = minY;
    this.minZ = minZ;
    this.maxX = maxX;
    this.maxY = maxY;
    this.maxZ = maxZ;
    return this;
  }

  /// Sets this box from [other] without swapping.
  BoundingBox3d setUncheckedFrom(BoundingBox3dc other) =>
      setUnchecked(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// Expands this box to include the given point, in place.
  @override
  BoundingBox3d expandToPoint(Vector3d point, [BoundingBox3d? dest]) =>
      super.expandToPoint(point, dest ?? this);

  /// Expands this box to include the given point, in place.
  @override
  BoundingBox3d expandToValues(double x, double y, double z, [BoundingBox3d? dest]) =>
      super.expandToValues(x, y, z, dest ?? this);

  /// Expands this box to include [other], in place.
  @override
  BoundingBox3d expandToBox(BoundingBox3dc other, [BoundingBox3d? dest]) => super.expandToBox(other, dest ?? this);

  /// Expands this box by [amount] on all sides, in place.
  @override
  BoundingBox3d expand(double amount, [BoundingBox3d? dest]) => super.expand(amount, dest ?? this);

  /// Expands this box by the given amounts, in place.
  @override
  BoundingBox3d expand3(double amountX, double amountY, double amountZ, [BoundingBox3d? dest]) =>
      super.expand3(amountX, amountY, amountZ, dest ?? this);

  /// Moves this box, in place.
  @override
  BoundingBox3d move(double amountX, double amountY, double amountZ, [BoundingBox3d? dest]) =>
      super.move(amountX, amountY, amountZ, dest ?? this);

  /// Intersects this box with [box], in place.
  @override
  BoundingBox3d intersect(BoundingBox3dc box, [BoundingBox3d? dest]) => super.intersect(box, dest ?? this);

  /// Transforms this box by [pose], in place.
  @override
  BoundingBox3d transform(Pose3dc pose, [BoundingBox3d? dest]) => super.transform(pose, dest ?? this);

  /// Transforms this box by [mpose], in place.
  @override
  BoundingBox3d transformMatrix(Matrix4d mpose, [BoundingBox3d? dest]) => super.transformMatrix(mpose, dest ?? this);

  /// Transforms this box by the inverse of [pose], in place.
  @override
  BoundingBox3d transformInverse(Pose3dc pose, [BoundingBox3d? dest]) => super.transformInverse(pose, dest ?? this);

  /// Transforms this box by the inverse of [mpose], in place.
  @override
  BoundingBox3d transformMatrixInverse(Matrix4d mpose, [BoundingBox3d? dest]) =>
      super.transformMatrixInverse(mpose, dest ?? this);

  @override
  bool operator ==(Object other) =>
      other is BoundingBox3dc &&
      other.minX == minX &&
      other.minY == minY &&
      other.minZ == minZ &&
      other.maxX == maxX &&
      other.maxY == maxY &&
      other.maxZ == maxZ;

  @override
  int get hashCode => Object.hash(minX, minY, minZ, maxX, maxY, maxZ);

  @override
  String toString() => 'BoundingBox3d[$minX, $minY, $minZ -> $maxX, $maxY, $maxZ]';
}

/// A read-only inclusive integer bounding box.
abstract class BoundingBox3ic {
  const BoundingBox3ic();

  int get minX;
  int get minY;
  int get minZ;
  int get maxX;
  int get maxY;
  int get maxZ;

  /// Whether this box intersects [other].
  bool intersects(BoundingBox3ic other) =>
      intersectsValues(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// Whether this box intersects [other].
  bool intersectsBounds(BlockBounds other) =>
      intersectsValues(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// Whether this box intersects the given inclusive bounds.
  bool intersectsValues(int minX, int minY, int minZ, int maxX, int maxY, int maxZ) =>
      this.maxX >= minX &&
      this.maxY >= minY &&
      this.maxZ >= minZ &&
      this.minX <= maxX &&
      this.minY <= maxY &&
      this.minZ <= maxZ;

  /// Whether this box contains the block [point].
  bool contains(Vector3i point) => containsValues(point.x, point.y, point.z);

  /// Whether this box contains the block at the given coordinates.
  bool containsValues(int x, int y, int z) =>
      x >= minX && x <= maxX && y >= minY && y <= maxY && z >= minZ && z <= maxZ;

  /// Whether this box contains the double point (half-open at the max side).
  bool containsVec(Vector3d other) =>
      other.x >= minX &&
      other.x <= maxX + 1 &&
      other.y >= minY &&
      other.y <= maxY + 1 &&
      other.z >= minZ &&
      other.z <= maxZ + 1;

  /// Expands this box to include [point], writing into [dest].
  BoundingBox3i expandToPoint(Vector3i point, [BoundingBox3i? dest]) =>
      expandToValues(point.x, point.y, point.z, dest);

  /// Expands this box to include the given point, writing into [dest].
  BoundingBox3i expandToValues(int x, int y, int z, [BoundingBox3i? dest]) {
    final out = (dest ?? BoundingBox3i()).setFrom(this);
    out.maxX = math.max(out.maxX, x);
    out.maxY = math.max(out.maxY, y);
    out.maxZ = math.max(out.maxZ, z);
    out.minX = math.min(out.minX, x);
    out.minY = math.min(out.minY, y);
    out.minZ = math.min(out.minZ, z);
    return out;
  }

  /// Expands this box to include [other], writing into [dest].
  BoundingBox3i expandToBox(BoundingBox3ic other, [BoundingBox3i? dest]) {
    final out = (dest ?? BoundingBox3i()).setFrom(this);
    out.maxX = math.max(out.maxX, other.maxX);
    out.maxY = math.max(out.maxY, other.maxY);
    out.maxZ = math.max(out.maxZ, other.maxZ);
    out.minX = math.min(out.minX, other.minX);
    out.minY = math.min(out.minY, other.minY);
    out.minZ = math.min(out.minZ, other.minZ);
    return out;
  }

  /// Translates this box by [vec] into [dest].
  BoundingBox3i moveBy(Vector3i vec, [BoundingBox3i? dest]) => move(vec.x, vec.y, vec.z, dest);

  /// Translates this box into [dest].
  BoundingBox3i move(int x, int y, int z, [BoundingBox3i? dest]) {
    final out = (dest ?? BoundingBox3i()).setFrom(this);
    out.minX += x;
    out.minY += y;
    out.minZ += z;
    out.maxX += x;
    out.maxY += y;
    out.maxZ += z;
    return out;
  }

  /// The intersection of this box and [box], stored in [dest].
  BoundingBox3i intersect(BoundingBox3ic box, [BoundingBox3i? dest]) => (dest ?? BoundingBox3i()).setUnchecked(
    math.max(minX, box.minX),
    math.max(minY, box.minY),
    math.max(minZ, box.minZ),
    math.min(maxX, box.maxX),
    math.min(maxY, box.maxY),
    math.min(maxZ, box.maxZ),
  );

  /// The center of this box.
  Vector3i center([Vector3i? dest]) =>
      (dest ?? Vector3i()).set((minX + maxX) ~/ 2, (minY + maxY) ~/ 2, (minZ + maxZ) ~/ 2);

  /// The side-length vector of this box.
  Vector3i size([Vector3i? dest]) => (dest ?? Vector3i()).set(maxX - minX, maxY - minY, maxZ - minZ);

  /// The encompassing X range.
  int width() => maxX - minX + 1;

  /// The encompassing Y range.
  int height() => maxY - minY + 1;

  /// The encompassing Z range.
  int length() => maxZ - minZ + 1;

  /// The volume of this box, in blocks.
  int volume() => (maxX - minX + 1) * (maxY - minY + 1) * (maxZ - minZ + 1);

  /// The chunk sections this box intersects.
  BoundingBox3i chunkBoundsFrom([BoundingBox3i? dest]) => (dest ?? BoundingBox3i()).setValues(
    minX >> 4,
    minY >> 4,
    minZ >> 4,
    maxX >> 4,
    maxY >> 4,
    maxZ >> 4,
  );

  /// The half-open `AABB` covering the same blocks.
  Aabb toAabb() =>
      Aabb(minX.toDouble(), minY.toDouble(), minZ.toDouble(), maxX + 1.0, maxY + 1.0, maxZ + 1.0);

  /// The `BoundingBox` covering the same blocks.
  BlockBounds toBlockBounds() => BlockBounds(minX, minY, minZ, maxX, maxY, maxZ);
}

/// A mutable inclusive integer bounding box.
final class BoundingBox3i extends BoundingBox3ic {
  /// An empty box: min values at the maximum int, max values at the minimum int
  /// (Java's `BoundingBox3i.EMPTY`).
  static final BoundingBox3i empty = BoundingBox3i.unchecked(
    0x7FFFFFFF,
    0x7FFFFFFF,
    0x7FFFFFFF,
    -0x80000000,
    -0x80000000,
    -0x80000000,
  );

  @override
  int minX;
  @override
  int minY;
  @override
  int minZ;
  @override
  int maxX;
  @override
  int maxY;
  @override
  int maxZ;

  /// An all-zero box.
  BoundingBox3i()
    : this.values(0, 0, 0, 0, 0, 0);

  /// A box with the given values; min/max are swapped into order.
  BoundingBox3i.values(int minX, int minY, int minZ, int maxX, int maxY, int maxZ)
    : minX = math.min(minX, maxX),
      minY = math.min(minY, maxY),
      minZ = math.min(minZ, maxZ),
      maxX = math.max(minX, maxX),
      maxY = math.max(minY, maxY),
      maxZ = math.max(minZ, maxZ);

  /// A box with the given values, *not* swapped into order.
  BoundingBox3i.unchecked(int minX, int minY, int minZ, int maxX, int maxY, int maxZ)
    : minX = minX,
      minY = minY,
      minZ = minZ,
      maxX = maxX,
      maxY = maxY,
      maxZ = maxZ;

  /// `new BoundingBox3i(BoundingBox3ic)`.
  BoundingBox3i.copy(BoundingBox3ic other)
    : this.values(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// `new BoundingBox3i(BoundingBox)`.
  BoundingBox3i.fromBlockBounds(BlockBounds other)
    : this.values(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// `new BoundingBox3i(BoundingBox3d)`: floors the double bounds.
  BoundingBox3i.fromBoundingBox3d(BoundingBox3dc other)
    : this.values(
        other.minX.floor(),
        other.minY.floor(),
        other.minZ.floor(),
        other.maxX.floor(),
        other.maxY.floor(),
        other.maxZ.floor(),
      );

  /// `BoundingBox3i.from(Iterable<BlockPos>)`, or `null` when empty.
  static BoundingBox3i? fromPositions(Iterable<Pos> blocks) {
    final iterator = blocks.iterator;
    if (!iterator.moveNext()) return null;
    var pos = iterator.current;
    var minX = pos.$1, minY = pos.$2, minZ = pos.$3;
    var maxX = minX, maxY = minY, maxZ = minZ;
    while (iterator.moveNext()) {
      pos = iterator.current;
      minX = math.min(minX, pos.$1);
      minY = math.min(minY, pos.$2);
      minZ = math.min(minZ, pos.$3);
      maxX = math.max(maxX, pos.$1);
      maxY = math.max(maxY, pos.$2);
      maxZ = math.max(maxZ, pos.$3);
    }
    return BoundingBox3i.values(minX, minY, minZ, maxX, maxY, maxZ);
  }

  /// Sets this box from [other].
  BoundingBox3i setFrom(BoundingBox3ic other) =>
      setValues(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// Sets this box from a double box, flooring.
  BoundingBox3i setFromBoundingBox3d(BoundingBox3dc other) => setValues(
    other.minX.floor(),
    other.minY.floor(),
    other.minZ.floor(),
    other.maxX.floor(),
    other.maxY.floor(),
    other.maxZ.floor(),
  );

  /// Sets this box, swapping min/max into order.
  BoundingBox3i setValues(int minX, int minY, int minZ, int maxX, int maxY, int maxZ) {
    this.minX = math.min(minX, maxX);
    this.minY = math.min(minY, maxY);
    this.minZ = math.min(minZ, maxZ);
    this.maxX = math.max(minX, maxX);
    this.maxY = math.max(minY, maxY);
    this.maxZ = math.max(minZ, maxZ);
    return this;
  }

  /// Sets this box without swapping.
  BoundingBox3i setUnchecked(int minX, int minY, int minZ, int maxX, int maxY, int maxZ) {
    this.minX = minX;
    this.minY = minY;
    this.minZ = minZ;
    this.maxX = maxX;
    this.maxY = maxY;
    this.maxZ = maxZ;
    return this;
  }

  /// Sets this box from [other] without swapping.
  BoundingBox3i setUncheckedFrom(BoundingBox3ic other) =>
      setUnchecked(other.minX, other.minY, other.minZ, other.maxX, other.maxY, other.maxZ);

  /// Expands this box by the given amounts, in place.
  BoundingBox3i expand(int xExpansion, int yExpansion, int zExpansion) {
    minX -= xExpansion;
    minY -= yExpansion;
    minZ -= zExpansion;
    maxX += xExpansion;
    maxY += yExpansion;
    maxZ += zExpansion;
    return this;
  }

  /// Expands this box to include [point], in place.
  @override
  BoundingBox3i expandToPoint(Vector3i point, [BoundingBox3i? dest]) =>
      super.expandToPoint(point, dest ?? this);

  /// Expands this box to include the given point, in place.
  @override
  BoundingBox3i expandToValues(int x, int y, int z, [BoundingBox3i? dest]) =>
      super.expandToValues(x, y, z, dest ?? this);

  /// Expands this box to include [other], in place.
  @override
  BoundingBox3i expandToBox(BoundingBox3ic other, [BoundingBox3i? dest]) => super.expandToBox(other, dest ?? this);

  /// Translates this box by [vec], in place.
  @override
  BoundingBox3i moveBy(Vector3i vec, [BoundingBox3i? dest]) => super.moveBy(vec, dest ?? this);

  /// Translates this box, in place.
  @override
  BoundingBox3i move(int x, int y, int z, [BoundingBox3i? dest]) => super.move(x, y, z, dest ?? this);

  /// Intersects this box with [box], in place.
  @override
  BoundingBox3i intersect(BoundingBox3ic box, [BoundingBox3i? dest]) => super.intersect(box, dest ?? this);

  @override
  bool operator ==(Object other) =>
      other is BoundingBox3ic &&
      other.minX == minX &&
      other.minY == minY &&
      other.minZ == minZ &&
      other.maxX == maxX &&
      other.maxY == maxY &&
      other.maxZ == maxZ;

  @override
  int get hashCode => Object.hash(minX, minY, minZ, maxX, maxY, maxZ);

  @override
  String toString() =>
      'BoundingBox3i{minX=$minX, minY=$minY, minZ=$minZ, maxX=$maxX, maxY=$maxY, maxZ=$maxZ}';
}
