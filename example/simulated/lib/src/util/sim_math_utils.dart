// `dev.simulated_team.simulated.util.SimMathUtils`: the geometry helpers the
// blocks share (quaternion vector rotation, cone clamping, grid snapping).
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.util.SimMathUtils
import 'dart:math' as math;

import 'package:sable/sable.dart' show Quaterniond, Vector3d;

/// The unit Y vector, `OrientedBoundingBox3d.UP`.
final Vector3d upVector = Vector3d(0, 1, 0);

/// Geometry helpers.
abstract final class SimMathUtils {
  /// Rotates [v] by [q]: `q * v * q^-1`, with [v] as a pure quaternion.
  static Vector3d rotateQuat(Vector3d v, Quaterniond q) {
    final p = Quaterniond(v.x, v.y, v.z, 0);
    final q2 = Quaterniond.copy(q);
    p.mul(q2);
    q2.conjugate();
    q2.mul(p);
    return Vector3d(q2.x, q2.y, q2.z);
  }

  /// Rotates [v] by the inverse of [q].
  static Vector3d rotateQuatReverse(Vector3d v, Quaterniond q) {
    final p = Quaterniond(v.x, v.y, v.z, 0);
    final q2 = Quaterniond.copy(q);
    q2.conjugate();
    p.mul(q2);
    q2.conjugate();
    q2.mul(p);
    return Vector3d(q2.x, q2.y, q2.z);
  }

  /// Clamps [v] into the cone of half-angle [coneAngle] (radians) around
  /// [coneAxis], returning a normalized vector.
  ///
  /// A vector already inside the cone is returned normalized and unchanged in
  /// direction; one outside is moved to the cone's surface.
  static Vector3d clampIntoCone(Vector3d v, Vector3d coneAxis, double coneAngle) {
    final vv = v.dot(v);
    final vn = v.dot(coneAxis);
    final nn = coneAxis.dot(coneAxis);
    // 1.01 keeps the discriminant positive when v == axis, and makes the result
    // behave smoothly when v is almost the opposite of the axis.
    final disc = nn * vv * 1.01 - vn * vn;
    final offsetDistance = (-vn + math.sqrt(math.max(disc, 0)) / math.tan(coneAngle)) / nn;
    if ((offsetDistance < 0) != (coneAngle < 0)) {
      return Vector3d.copy(v)..normalize();
    }
    return Vector3d.copy(v)
      ..add(coneAxis.mulInto(offsetDistance, Vector3d()))
      ..normalize();
  }

  /// Whether [relativePosition] (relative to the base of the cylinder) is inside
  /// the cylinder of [cylinderLength] and [cylinderRadius].
  static bool isInCylinder(
    Vector3d axisVector,
    Vector3d relativePosition,
    double cylinderLength,
    double cylinderRadius,
  ) {
    final distance = axisVector.dot(relativePosition);
    if (distance < 0 || distance > cylinderLength) return false;

    final scaledAxis = axisVector.mulInto(distance, Vector3d());
    final offset = relativePosition.sub(scaledAxis);
    return offset.lengthSquared <= cylinderRadius * cylinderRadius;
  }

  /// The quaternion rotating [start] onto [end] (`Quaternionf` in Java, a
  /// double-precision quaternion here).
  static Quaterniond quaternionFromVectorRotation(Vector3d start, Vector3d end) {
    final cross = start.crossInto(end, Vector3d());
    return Quaterniond(cross.x, cross.y, cross.z, 1 + start.dot(end)).normalize();
  }

  /// Snaps [q] to the closest quaternion of [gridQuats].
  ///
  /// The signs of the components are kept: the comparison flips [q] into the
  /// negative hemisphere, adds each grid quaternion and picks the smallest
  /// distance, then restores the signs.
  static Quaterniond clampQuaternionToGrid(
    Quaterniond q,
    Iterable<Quaterniond> gridQuats, [
    Quaterniond? dest,
  ]) {
    final out = dest ?? Quaterniond();

    final signX = q.x < 0 ? -1.0 : 1.0;
    final signY = q.y < 0 ? -1.0 : 1.0;
    final signZ = q.z < 0 ? -1.0 : 1.0;
    final signW = q.w < 0 ? -1.0 : 1.0;

    out.set(q.x * -signX, q.y * -signY, q.z * -signZ, q.w * -signW);

    final best = Quaterniond();
    var distance = 10.0;

    for (final gq in gridQuats) {
      final dx = out.x + gq.x;
      final dy = out.y + gq.y;
      final dz = out.z + gq.z;
      final dw = out.w + gq.w;
      final currentDist = dx * dx + dy * dy + dz * dz + dw * dw;
      if (currentDist < distance) {
        distance = currentDist;
        best.setFrom(gq);
      }
    }

    out.set(best.x * signX, best.y * signY, best.z * signZ, best.w * signW);
    return out;
  }

  /// `smoothStep(t)`: the Hermite curve `3t^2 - 2t^3`.
  static double smoothStep(double t) => t * t * (3 - 2 * t);

  /// The closest yaw of [orientation], in radians.
  ///
  /// Java: `getClosestYaw`
  static double closestYaw(Quaterniond orientation) {
    final d = upVector.dot(Vector3d(orientation.x, orientation.y, orientation.z));
    return 2 * math.atan2(-d, orientation.w);
  }

  /// `GridQuats`: the eleven axis-aligned quaternions, as bit masks.
  static const List<Quaterniond> _allQuats = [
    Quaterniond(0, 0, 0, 1),
    Quaterniond(1, 0, 0, 0),
    Quaterniond(0, 1, 0, 0),
    Quaterniond(0, 0, 1, 0),
    Quaterniond(1, 0, 0, 1),
    Quaterniond(0, 1, 0, 1),
    Quaterniond(0, 0, 1, 1),
    Quaterniond(0, 1, 1, 0),
    Quaterniond(1, 0, 1, 0),
    Quaterniond(1, 1, 0, 0),
    Quaterniond(1, 1, 1, 1),
  ];

  /// The normalized grid quaternions.
  static List<Quaterniond> get allGridQuats =>
      [for (final q in _allQuats) Quaterniond.copy(q)..normalize()];
}

/// `SimMathUtils.GridQuats`: which subset of the grid a clamp may use.
enum GridQuats {
  all(0x7ff),
  xAxis(0x13),
  yAxis(0x25),
  zAxis(0x49),
  real(0x471);

  const GridQuats(this.bitPattern);

  final int bitPattern;

  /// The quaternions of this subset.
  List<Quaterniond> get quaternions {
    final out = <Quaterniond>[];
    var pattern = bitPattern;
    for (final q in SimMathUtils._allQuats) {
      if (pattern & 1 != 0) out.add(Quaterniond.copy(q)..normalize());
      pattern >>= 1;
    }
    return out;
  }

  /// The quaternions *not* in this subset.
  List<Quaterniond> get oppositeQuaternions {
    final out = <Quaterniond>[];
    var pattern = bitPattern;
    for (final q in SimMathUtils._allQuats) {
      if (pattern & 1 == 0) out.add(Quaterniond.copy(q)..normalize());
      pattern >>= 1;
    }
    return out;
  }
}
