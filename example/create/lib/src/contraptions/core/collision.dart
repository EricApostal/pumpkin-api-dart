// The collision maths of contraptions (pure): `foundation/collision` of Create. A contraption
// entity collides as an oriented box (the entity box, rotated by the contraption) against the
// collision boxes of the blocks it carries. `ContinuousOBBCollider` is the swept (continuous)
// version used for every entity that touches a contraption.
import 'dart:math' as math;

import '../../common/bounds.dart';
import '../../common/vec_helper.dart' show Vec3, Vec3Math, vec3Zero;

/// `Matrix3d`: a 3x3 matrix, row major, as the collision code uses it.
final class Matrix3d {
  double m00 = 0, m01 = 0, m02 = 0;
  double m10 = 0, m11 = 0, m12 = 0;
  double m20 = 0, m21 = 0, m22 = 0;

  Matrix3d();

  Matrix3d.identity() {
    m00 = m11 = m22 = 1;
  }

  Matrix3d asIdentity() {
    m00 = m11 = m22 = 1;
    m01 = m02 = m10 = m12 = m20 = m21 = 0;
    return this;
  }

  Matrix3d asXRotation(double radians) {
    asIdentity();
    if (radians == 0) return this;
    final s = math.sin(radians);
    final c = math.cos(radians);
    m22 = c;
    m11 = c;
    m21 = s;
    m12 = -s;
    return this;
  }

  Matrix3d asYRotation(double radians) {
    asIdentity();
    if (radians == 0) return this;
    final s = math.sin(radians);
    final c = math.cos(radians);
    m00 = c;
    m22 = c;
    m02 = s;
    m20 = -s;
    return this;
  }

  Matrix3d asZRotation(double radians) {
    asIdentity();
    if (radians == 0) return this;
    final s = math.sin(radians);
    final c = math.cos(radians);
    m00 = c;
    m11 = c;
    m01 = -s;
    m10 = s;
    return this;
  }

  Matrix3d scale(double d) {
    m00 *= d;
    m11 *= d;
    m22 *= d;
    return this;
  }

  /// `this = this * m`.
  Matrix3d multiply(Matrix3d m) {
    final n00 = m00 * m.m00 + m01 * m.m10 + m02 * m.m20;
    final n01 = m00 * m.m01 + m01 * m.m11 + m02 * m.m21;
    final n02 = m00 * m.m02 + m01 * m.m12 + m02 * m.m22;
    final n10 = m10 * m.m00 + m11 * m.m10 + m12 * m.m20;
    final n11 = m10 * m.m01 + m11 * m.m11 + m12 * m.m21;
    final n12 = m10 * m.m02 + m11 * m.m12 + m12 * m.m22;
    final n20 = m20 * m.m00 + m21 * m.m10 + m22 * m.m20;
    final n21 = m20 * m.m01 + m21 * m.m11 + m22 * m.m21;
    final n22 = m20 * m.m02 + m21 * m.m12 + m22 * m.m22;
    m00 = n00;
    m01 = n01;
    m02 = n02;
    m10 = n10;
    m11 = n11;
    m12 = n12;
    m20 = n20;
    m21 = n21;
    m22 = n22;
    return this;
  }

  Vec3 transform(Vec3 vec) => transformXYZ(vec.$1, vec.$2, vec.$3);

  Vec3 transformTransposed(Vec3 vec) =>
      transformTransposedXYZ(vec.$1, vec.$2, vec.$3);

  Vec3 transformXYZ(double x, double y, double z) => (
    x * m00 + y * m01 + z * m02,
    x * m10 + y * m11 + z * m12,
    x * m20 + y * m21 + z * m22,
  );

  Vec3 transformTransposedXYZ(double x, double y, double z) => (
    x * m00 + y * m10 + z * m20,
    x * m01 + y * m11 + z * m21,
    x * m02 + y * m12 + z * m22,
  );

  Matrix3d copy() => Matrix3d()
    ..m00 = m00
    ..m01 = m01
    ..m02 = m02
    ..m10 = m10
    ..m11 = m11
    ..m12 = m12
    ..m20 = m20
    ..m21 = m21
    ..m22 = m22;
}

/// `CollisionList`: structure-of-arrays storage of dense boxes (centre + extents), for collision.
final class CollisionList {
  static const int defaultCapacity = 16;

  List<double> centerX = List<double>.filled(defaultCapacity, 0);
  List<double> centerY = List<double>.filled(defaultCapacity, 0);
  List<double> centerZ = List<double>.filled(defaultCapacity, 0);
  List<double> extentsX = List<double>.filled(defaultCapacity, 0);
  List<double> extentsY = List<double>.filled(defaultCapacity, 0);
  List<double> extentsZ = List<double>.filled(defaultCapacity, 0);

  int size = 0;

  void clear() => size = 0;

  void append(
    double cx,
    double cy,
    double cz,
    double ex,
    double ey,
    double ez,
  ) {
    if (size == centerX.length) {
      final newCapacity = centerX.length * 2;
      centerX = List<double>.of(centerX, growable: true)..length = newCapacity;
      centerY = List<double>.of(centerY, growable: true)..length = newCapacity;
      centerZ = List<double>.of(centerZ, growable: true)..length = newCapacity;
      extentsX = List<double>.of(extentsX, growable: true)
        ..length = newCapacity;
      extentsY = List<double>.of(extentsY, growable: true)
        ..length = newCapacity;
      extentsZ = List<double>.of(extentsZ, growable: true)
        ..length = newCapacity;
    }
    centerX[size] = cx;
    centerY[size] = cy;
    centerZ[size] = cz;
    extentsX[size] = ex;
    extentsY[size] = ey;
    extentsZ[size] = ez;
    size++;
  }

  /// Appends the box of [aabb] (`VoxelShape.forAllBoxes` over the unit box of a block).
  void appendBox(Aabb aabb) => append(
    (aabb.minX + aabb.maxX) / 2,
    (aabb.minY + aabb.maxY) / 2,
    (aabb.minZ + aabb.maxZ) / 2,
    (aabb.maxX - aabb.minX) / 2,
    (aabb.maxY - aabb.minY) / 2,
    (aabb.maxZ - aabb.minZ) / 2,
  );

  void appendFrom(CollisionList other, int index) => append(
    other.centerX[index],
    other.centerY[index],
    other.centerZ[index],
    other.extentsX[index],
    other.extentsY[index],
    other.extentsZ[index],
  );
}

/// `CollisionList.Populate`: consumes the boxes of a shape at a block offset.
final class CollisionPopulate {
  final CollisionList collisionList;
  int offsetX = 0;
  int offsetY = 0;
  int offsetZ = 0;

  CollisionPopulate(this.collisionList);

  void consume(
    double x1,
    double y1,
    double z1,
    double x2,
    double y2,
    double z2,
  ) {
    collisionList.append(
      offsetX + 0.5 * (x2 + x1),
      offsetY + 0.5 * (y2 + y1),
      offsetZ + 0.5 * (z2 + z1),
      0.5 * (x2 - x1),
      0.5 * (y2 - y1),
      0.5 * (z2 - z1),
    );
  }
}

/// `OrientedBB`: a box with a rotation.
final class OrientedBB {
  Vec3 center;
  Vec3 extents;
  Matrix3d rotation;

  OrientedBB(Aabb bb)
    : center = bb.center,
      extents = (bb.xSize / 2, bb.ySize / 2, bb.zSize / 2),
      rotation = Matrix3d.identity();

  OrientedBB.create(this.center, this.extents, this.rotation);

  OrientedBB copy() => OrientedBB.create(center, extents, rotation.copy());

  void move(Vec3 offset) => center = center + offset;

  Aabb get asAabb => Aabb.between(center - extents, center + extents);
}

/// `ContinuousOBBCollider.CollisionResponse`.
final class CollisionResponse {
  bool surfaceCollision = false;
  Vec3 collisionResponse = vec3Zero;
  Vec3 normal = vec3Zero;
  Vec3 location = vec3Zero;
  double temporalResponse = 1;

  bool get hardCollision => collisionResponse != vec3Zero;
  bool get temporalCollision => temporalResponse != 1;
  bool get anyCollision => hardCollision || temporalCollision;
}

/// `ContinuousOBBCollider`: swept separation of an oriented box against a list of boxes.
abstract final class ContinuousOBBCollider {
  static const Vec3 _uA0 = (1.0, 0.0, 0.0);
  static const Vec3 _uA1 = (0.0, 1.0, 0.0);
  static const Vec3 _uA2 = (0.0, 0.0, 1.0);

  static CollisionResponse collideMany(
    CollisionList collidableBBs,
    CollisionList denseViableColliders,
    OrientedBB obb,
    Vec3 motion,
    double entityMaxStep,
    bool doHorizontalPass,
  ) {
    final obbCenter = obb.center;
    final obbExtents = obb.extents;
    final rotation = obb.rotation;

    final a00 = rotation.m00.abs();
    final a01 = rotation.m01.abs();
    final a02 = rotation.m02.abs();
    final a10 = rotation.m10.abs();
    final a11 = rotation.m11.abs();
    final a12 = rotation.m12.abs();
    final a20 = rotation.m20.abs();
    final a21 = rotation.m21.abs();
    final a22 = rotation.m22.abs();

    final aabbInLocalX = (a00 + a01 + a02) * obbExtents.$1 + 0.5;
    final aabbInLocalY = (a10 + a11 + a12) * obbExtents.$2 + 0.5;
    final aabbInLocalZ = (a20 + a21 + a22) * obbExtents.$3 + 0.5;

    denseViableColliders.size = 0;
    for (var bbIdx = 0; bbIdx < collidableBBs.size; ++bbIdx) {
      if (((obbCenter.$1 + motion.$1) - collidableBBs.centerX[bbIdx]).abs() >
          collidableBBs.extentsX[bbIdx] + aabbInLocalX) {
        continue;
      }
      if (((obbCenter.$2 + motion.$2) - collidableBBs.centerY[bbIdx]).abs() >
          collidableBBs.extentsY[bbIdx] + aabbInLocalY) {
        continue;
      }
      if (((obbCenter.$3 + motion.$3) - collidableBBs.centerZ[bbIdx]).abs() >
          collidableBBs.extentsZ[bbIdx] + aabbInLocalZ) {
        continue;
      }
      denseViableColliders.appendFrom(collidableBBs, bbIdx);
    }

    if (denseViableColliders.size == 0) return CollisionResponse();

    var collisionResponseX = 0.0;
    var collisionResponseY = 0.0;
    var collisionResponseZ = 0.0;

    var locationX = 0.0;
    var locationY = 0.0;
    var locationZ = 0.0;

    var normalX = 0.0;
    var normalY = 0.0;
    var normalZ = 0.0;

    var surfaceCollision = false;
    var temporalResponse = 1.0;

    final uB0 = (rotation.m00, rotation.m10, rotation.m20).normalized;
    final uB1 = (rotation.m01, rotation.m11, rotation.m21).normalized;
    final uB2 = (rotation.m02, rotation.m12, rotation.m22).normalized;

    final motion2 = rotation.transformTransposed(motion);
    final mf = _ContinuousSeparationManifold(uB1);

    for (final horizontalPass in const [true, false]) {
      if (horizontalPass && !doHorizontalPass) continue;
      final verticalPass = !horizontalPass || !doHorizontalPass;

      for (var bbIdx = 0; bbIdx < denseViableColliders.size; ++bbIdx) {
        final deltaX =
            obbCenter.$1 +
            collisionResponseX -
            denseViableColliders.centerX[bbIdx];
        final deltaY =
            obbCenter.$2 +
            collisionResponseY -
            denseViableColliders.centerY[bbIdx];
        final deltaZ =
            obbCenter.$3 +
            collisionResponseZ -
            denseViableColliders.centerZ[bbIdx];

        mf.reset();

        final extentsX = denseViableColliders.extentsX[bbIdx];
        final extentsY = denseViableColliders.extentsY[bbIdx];
        final extentsZ = denseViableColliders.extentsZ[bbIdx];

        if (mf.separate(
              _uA0,
              deltaX,
              extentsX,
              a00 * obbExtents.$1 + a01 * obbExtents.$2 + a02 * obbExtents.$3,
              motion.$1,
              true,
            ) ||
            mf.separate(
              _uA1,
              deltaY,
              extentsY,
              a10 * obbExtents.$1 + a11 * obbExtents.$2 + a12 * obbExtents.$3,
              motion.$2,
              true,
            ) ||
            mf.separate(
              _uA2,
              deltaZ,
              extentsZ,
              a20 * obbExtents.$1 + a21 * obbExtents.$2 + a22 * obbExtents.$3,
              motion.$3,
              true,
            )) {
          continue;
        }

        final deltaEntityFrame = rotation.transformTransposedXYZ(
          deltaX,
          deltaY,
          deltaZ,
        );

        if (mf.separate(
              uB0,
              deltaEntityFrame.$1,
              extentsX * a00 + extentsY * a10 + extentsZ * a20,
              obbExtents.$1,
              motion2.$1,
              false,
            ) ||
            mf.separate(
              uB1,
              deltaEntityFrame.$2,
              extentsX * a01 + extentsY * a11 + extentsZ * a21,
              obbExtents.$2,
              motion2.$2,
              false,
            ) ||
            mf.separate(
              uB2,
              deltaEntityFrame.$3,
              extentsX * a02 + extentsY * a12 + extentsZ * a22,
              obbExtents.$3,
              motion2.$3,
              false,
            )) {
          continue;
        }

        if (verticalPass && !surfaceCollision) surfaceCollision = true;

        var timeOfImpact = mf.getTimeOfImpact();
        final isTemporal = timeOfImpact > 0 && timeOfImpact < 1;

        if (!isTemporal && mf.isDiscreteCollision) {
          if (mf.stepSeparation <= entityMaxStep) {
            final sep = _withSignedEpsilon(mf.stepSeparation);
            collisionResponseX += mf.stepSeparationAxis.$1 * sep;
            collisionResponseY += mf.stepSeparationAxis.$2 * sep;
            collisionResponseZ += mf.stepSeparationAxis.$3 * sep;
          } else {
            final sep = _withSignedEpsilon(mf.separation);
            collisionResponseX += mf.axis!.$1 * sep;
            collisionResponseY += mf.axis!.$2 * sep;
            collisionResponseZ += mf.axis!.$3 * sep;
          }
          timeOfImpact = 0;
        }

        if (timeOfImpact >= 0 && temporalResponse > timeOfImpact) {
          final scale = _withSignedEpsilon(mf.normalSeparation);
          final normalAxis = mf.normalAxis ?? _uA1;
          normalX = normalAxis.$1 * scale;
          normalY = normalAxis.$2 * scale;
          normalZ = normalAxis.$3 * scale;

          locationX = mf.collisionX;
          locationY = mf.collisionY;
          locationZ = mf.collisionZ;
        }

        if (isTemporal && temporalResponse > timeOfImpact)
          temporalResponse = timeOfImpact;
      }

      if (verticalPass) break;

      final noVerticalMotionResponse = temporalResponse == 1;
      final noVerticalCollision = collisionResponseY == 0;
      if (noVerticalCollision && noVerticalMotionResponse) break;

      collisionResponseX *= 129.0 / 128.0;
      collisionResponseZ *= 129.0 / 128.0;
    }

    return CollisionResponse()
      ..surfaceCollision = surfaceCollision
      ..collisionResponse = (
        collisionResponseX,
        collisionResponseY,
        collisionResponseZ,
      )
      ..normal = (normalX, normalY, normalZ)
      ..location = (locationX, locationY, locationZ)
      ..temporalResponse = temporalResponse;
  }

  static double _withSignedEpsilon(double sep) => sep + (_sign(sep) * 1e-4);
}

/// `Math.signum` of a double.
double _sign(double v) => v > 0 ? 1.0 : (v < 0 ? -1.0 : 0.0);

final class _ContinuousSeparationManifold {
  static const double _undefined = -1;

  double latestCollisionEntryTime = _undefined;
  double earliestCollisionExitTime = double.maxFinite;
  bool isDiscreteCollision = true;

  double collisionX = 0, collisionY = 0, collisionZ = 0;

  final Vec3 stepSeparationAxis;
  double stepSeparation = double.maxFinite;

  Vec3? normalAxis;
  double normalSeparation = double.maxFinite;
  Vec3? axis;
  double separation = double.maxFinite;

  _ContinuousSeparationManifold(this.stepSeparationAxis);

  /// Returns `true` when the boxes are separated on [axis] (no collision).
  bool separate(
    Vec3 axis,
    double tl,
    double rA,
    double rB,
    double projectedMotion,
    bool axisOfObjA,
  ) {
    final distance = tl.abs();
    final diff = distance - (rA + rB);

    final discreteCollision = diff <= 0;
    if (!discreteCollision && _sign(projectedMotion) == _sign(tl)) return true;

    final sTl = _sign(tl);
    final separation = sTl * diff.abs();

    if (!discreteCollision) {
      isDiscreteCollision = false;
      if (separation.abs() > projectedMotion.abs()) return true;

      final entryTime = separation.abs() / projectedMotion.abs();
      final exitTime = (diff + rA.abs() + rB.abs()) / projectedMotion.abs();
      latestCollisionEntryTime = math.max(entryTime, latestCollisionEntryTime);
      earliestCollisionExitTime = math.min(exitTime, earliestCollisionExitTime);
    }

    if (axisOfObjA && distance != 0 && -diff <= normalSeparation.abs()) {
      normalAxis = axis;
      normalSeparation = separation;
    }

    final dot = stepSeparationAxis.dot(axis);
    if (dot != 0 && discreteCollision) {
      final cross = axis.cross(stepSeparationAxis);
      final dotSeparation = _sign(dot) * tl - (rA + rB);
      var stepSeparation = -dotSeparation;

      if (cross != vec3Zero) {
        final sepVec = axis * dotSeparation;
        final axisPlane = axis.cross(cross);
        final stepPlane = stepSeparationAxis.cross(cross);
        final stepSeparationVec =
            sepVec -
            axisPlane * (sepVec.dot(stepPlane) / axisPlane.dot(stepPlane));
        stepSeparation = stepSeparationVec.length;
        if (this.stepSeparation.abs() > stepSeparation.abs() &&
            stepSeparation != 0) {
          this.stepSeparation = stepSeparation;
        }
      } else if (this.stepSeparation.abs() > stepSeparation.abs()) {
        this.stepSeparation = stepSeparation;
      }
    }

    if (distance != 0 && -diff <= this.separation.abs()) {
      this.axis = axis;
      this.separation = separation;
      final scale =
          _sign(tl) * (axisOfObjA ? -rA : -rB) - _sign(separation) * 0.125;

      collisionX = axis.$1 * scale;
      collisionY = axis.$2 * scale;
      collisionZ = axis.$3 * scale;
    }

    return false;
  }

  double getTimeOfImpact() {
    if (latestCollisionEntryTime == _undefined) return _undefined;
    if (latestCollisionEntryTime > earliestCollisionExitTime) return _undefined;
    return latestCollisionEntryTime;
  }

  void reset() {
    axis = null;
    normalAxis = null;
    separation = double.maxFinite;
    stepSeparation = double.maxFinite;
    normalSeparation = double.maxFinite;
    latestCollisionEntryTime = -1;
    earliestCollisionExitTime = double.maxFinite;
    isDiscreteCollision = true;
  }
}
