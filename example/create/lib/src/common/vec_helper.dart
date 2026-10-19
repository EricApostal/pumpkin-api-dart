// VecHelper and AngleHelper of Catnip (pure), on `(double, double, double)` records.
import 'dart:math' as math;

import 'package:pumpkin_api/src/geometry.dart' show Vec3, Vec3Math, vec3Zero;

import 'direction.dart';
import 'pos.dart';

export 'package:pumpkin_api/src/geometry.dart' show Vec3, Vec3Math, vec3, vec3Zero;

/// `net.createmod.catnip.api.math.VecHelper`.
abstract final class VecHelper {
  static const Vec3 centerOfOrigin = (0.5, 0.5, 0.5);

  static Vec3 rotateAll(Vec3 vec, Vec3 rotationVec) => rotateXYZ(vec, rotationVec.$1, rotationVec.$2, rotationVec.$3);

  static Vec3 rotateXYZ(Vec3 vec, double xRot, double yRot, double zRot) =>
      rotate(rotate(rotate(vec, xRot, Axis.x), yRot, Axis.y), zRot, Axis.z);

  static Vec3 rotateCentered(Vec3 vec, double deg, Axis axis) {
    return rotate(vec - centerOfOrigin, deg, axis) + centerOfOrigin;
  }

  /// Rotates [vec] by [deg] degrees around [axis] (right handed, like Java).
  static Vec3 rotate(Vec3 vec, double deg, Axis axis) {
    if (deg == 0) return vec;
    if (vec == vec3Zero) return vec;
    final angle = toFloat(deg / 180.0 * math.pi);
    final sin = math.sin(angle);
    final cos = math.cos(angle);
    final x = vec.$1, y = vec.$2, z = vec.$3;
    return switch (axis) {
      Axis.x => (x, y * cos - z * sin, z * cos + y * sin),
      Axis.y => (x * cos + z * sin, y, z * cos - x * sin),
      Axis.z => (x * cos - y * sin, y * cos + x * sin, z),
    };
  }

  static Vec3 mirrorCentered(Vec3 vec, BlockMirror mirror) => VecHelper.mirror(vec - centerOfOrigin, mirror) + centerOfOrigin;

  static Vec3 mirror(Vec3 vec, BlockMirror mirror) {
    if (mirror == BlockMirror.none) return vec;
    if (vec == vec3Zero) return vec;
    final x = vec.$1, y = vec.$2, z = vec.$3;
    if (mirror == BlockMirror.leftRight) return (x, y, -z);
    if (mirror == BlockMirror.frontBack) return (-x, y, z);
    return vec;
  }

  static Vec3 lookAt(Vec3 vec, Vec3 fwd) {
    fwd = fwd.normalized;
    var up = (0.0, 1.0, 0.0);
    final dot = fwd.dot(up);
    if (dot.abs() > 1 - 1.0e-3) up = (0.0, 0.0, dot > 0 ? 1.0 : -1.0);
    final right = fwd.cross(up).normalized;
    up = right.cross(fwd).normalized;
    final x = vec.$1 * right.$1 + vec.$2 * up.$1 + vec.$3 * fwd.$1;
    final y = vec.$1 * right.$2 + vec.$2 * up.$2 + vec.$3 * fwd.$2;
    final z = vec.$1 * right.$3 + vec.$2 * up.$3 + vec.$3 * fwd.$3;
    return (x, y, z);
  }

  static bool isVecPointingTowards(Vec3 vec, Direction direction) =>
      direction.unitVec3.dot(vec.normalized) > 0.125;

  /// `getCenterOf(Vec3i)`.
  static Vec3 getCenterOf(Pos pos) => pos == posZero ? centerOfOrigin : pos.center;

  static Vec3 offsetRandomly(Vec3 vec, math.Random r, double radius) => (
    vec.$1 + (r.nextDouble() - 0.5) * 2 * radius,
    vec.$2 + (r.nextDouble() - 0.5) * 2 * radius,
    vec.$3 + (r.nextDouble() - 0.5) * 2 * radius,
  );

  static Vec3 axisAlignedPlaneOfVec(Vec3 vec) {
    vec = vec.normalized;
    return (1 - vec.$1.abs(), 1 - vec.$2.abs(), 1 - vec.$3.abs());
  }

  static Vec3 axisAlignedPlaneOf(Direction face) => axisAlignedPlaneOfVec(face.unitVec3);

  /// `voxelSpace`: pixels (1/16 block) to blocks.
  static Vec3 voxelSpace(double x, double y, double z) => (x, y, z) * (1 / 16.0);

  static int getCoordinatePos(Pos pos, Axis axis) => pos.get(axis);

  static double getCoordinate(Vec3 vec, Axis axis) => axis.choose(vec.$1, vec.$2, vec.$3);

  static bool onSameAxis(Pos pos1, Pos pos2, Axis axis) {
    if (pos1 == pos2) return true;
    for (final other in Axis.values) {
      if (axis != other && pos1.get(other) != pos2.get(other)) return false;
    }
    return true;
  }

  static Vec3 clamp(Vec3 vec, double maxLength) =>
      vec.lengthSquared > maxLength * maxLength ? vec.normalized * maxLength : vec;

  static Vec3 lerp(double p, Vec3 from, Vec3 to) => from + (to - from) * p;

  static Vec3 slerp(double p, Vec3 from, Vec3 to) {
    final theta = math.acos(from.dot(to));
    return (from * math.sin(1 - p) * theta + to * math.sin(theta * p)) * (1 / math.sin(theta));
  }

  static Vec3 clampComponentWise(Vec3 vec, double maxLength) => (
    vec.$1.clamp(-maxLength, maxLength).toDouble(),
    vec.$2.clamp(-maxLength, maxLength).toDouble(),
    vec.$3.clamp(-maxLength, maxLength).toDouble(),
  );

  static Vec3 componentMin(Vec3 a, Vec3 b) => (math.min(a.$1, b.$1), math.min(a.$2, b.$2), math.min(a.$3, b.$3));

  static Vec3 componentMax(Vec3 a, Vec3 b) => (math.max(a.$1, b.$1), math.max(a.$2, b.$2), math.max(a.$3, b.$3));

  static Vec3 project(Vec3 vec, Vec3 ontoVec) {
    if (ontoVec == vec3Zero) return vec3Zero;
    return ontoVec * (vec.dot(ontoVec) / ontoVec.lengthSquared);
  }

  static Vec3? intersectSphere(Vec3 origin, Vec3 lineDirection, Vec3 sphereCenter, double radius) {
    if (lineDirection == vec3Zero) return null;
    if (lineDirection.lengthSquared != 1) lineDirection = lineDirection.normalized;
    final diff = origin - sphereCenter;
    final lineDotDiff = lineDirection.dot(diff);
    final delta = lineDotDiff * lineDotDiff - (diff.lengthSquared - radius * radius);
    if (delta < 0) return null;
    final t = -lineDotDiff + math.sqrt(delta);
    return origin + lineDirection * t;
  }

  static Vec3 bezier(Vec3 p1, Vec3 p2, Vec3 q1, Vec3 q2, double t) {
    final v1 = lerp(t, p1, q1);
    final v2 = lerp(t, q1, q2);
    final v3 = lerp(t, q2, p2);
    final inner1 = lerp(t, v1, v2);
    final inner2 = lerp(t, v2, v3);
    return lerp(t, inner1, inner2);
  }

  static Vec3 bezierDerivative(Vec3 p1, Vec3 p2, Vec3 q1, Vec3 q2, double t) =>
      p1 * (-3 * t * t + 6 * t - 3) + q1 * (9 * t * t - 12 * t + 3) + q2 * (-9 * t * t + 6 * t) + p2 * (3 * t * t);

  static List<double>? intersectRanged(Vec3 p1, Vec3 q1, Vec3 p2, Vec3 q2, Axis plane) {
    final pDiff = p2 - p1;
    final qDiff = q2 - q1;
    final hit = intersect(p1, q1, pDiff.normalized, qDiff.normalized, plane);
    if (hit == null) return null;
    if (hit[0] < 0 || hit[1] < 0) return null;
    if (hit[0] * hit[0] > pDiff.lengthSquared || hit[1] * hit[1] > qDiff.lengthSquared) return null;
    return hit;
  }

  static List<double>? intersect(Vec3 p1, Vec3 p2, Vec3 r, Vec3 s, Axis plane) {
    if (plane == Axis.x) {
      p1 = (p1.$2, 0, p1.$3);
      p2 = (p2.$2, 0, p2.$3);
      r = (r.$2, 0, r.$3);
      s = (s.$2, 0, s.$3);
    }
    if (plane == Axis.z) {
      p1 = (p1.$1, 0, p1.$2);
      p2 = (p2.$1, 0, p2.$2);
      r = (r.$1, 0, r.$2);
      s = (s.$1, 0, s.$2);
    }
    final qminusp = p2 - p1;
    final rcs = r.$1 * s.$3 - r.$3 * s.$1;
    if (mthEqual(rcs, 0)) return null;
    final rdivrcs = r * (1 / rcs);
    final sdivrcs = s * (1 / rcs);
    final t = qminusp.$1 * sdivrcs.$3 - qminusp.$3 * sdivrcs.$1;
    final u = qminusp.$1 * rdivrcs.$3 - qminusp.$3 * rdivrcs.$1;
    return [t, u];
  }

  static double alignedDistanceToFace(Vec3 pos, Pos blockPos, Direction face) {
    final axis = face.axis;
    return (getCoordinate(pos, axis) - (blockPos.get(axis) + (face.axisDirection == AxisDirection.positive ? 1 : 0)))
        .abs();
  }
}

/// `net.createmod.catnip.api.math.AngleHelper`.
abstract final class AngleHelper {
  static double horizontalAngle(Direction facing) {
    if (facing.axis.isVertical) return 0;
    var angle = facing.toYRot;
    if (facing.axis == Axis.x) angle = -angle;
    return angle;
  }

  static double verticalAngle(Direction facing) => facing == Direction.up ? -90 : (facing == Direction.down ? 90 : 0);

  static double rad(double angle) => angle == 0 ? 0 : toFloat(angle / 180 * math.pi);

  static double deg(double angle) => angle == 0 ? 0 : toFloat(angle * 180 / math.pi);

  static double angleLerp(double pct, double current, double target) =>
      toFloat(current + getShortestAngleDiff(current, target) * pct);

  static double getShortestAngleDiff(double current, double target) {
    current = current.remainder(360);
    target = target.remainder(360);
    return toFloat((((((target - current).remainder(360)) + 540).remainder(360)) - 180));
  }

  static double getShortestAngleDiffHint(double current, double target, double hint) {
    final diff = getShortestAngleDiff(current, target);
    if (mthEqual(diff.abs(), 180) && diff.sign != hint.sign) return diff + 360 * hint.sign;
    return diff;
  }

  static double wrapAngle180(double angle) => (angle + 180).remainder(360) - 180;
}
