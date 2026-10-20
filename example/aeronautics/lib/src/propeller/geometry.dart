// Geometry shared by the propeller content: the rotation Minecraft attaches to
// each facing, and the vector helpers the smart propeller needs.
//
// Java: `net.minecraft.core.Direction#getRotation`, `SimMathUtils`.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/common/direction.dart' show Axis, Direction;
import 'package:sable/sable.dart' show Matrix3d, Quaterniond, Vector3d;

/// `Direction.getRotation()`: the rotation that takes the block's local frame
/// (up along +Y) to the direction's frame.
Quaterniond directionRotation(Direction direction) => switch (direction) {
  Direction.down => Quaterniond()..rotateX(math.pi),
  Direction.up => Quaterniond(),
  Direction.north => Quaterniond()
    ..rotateX(math.pi / 2)
    ..rotateZ(math.pi),
  Direction.south => Quaterniond()..rotateX(math.pi / 2),
  Direction.west => Quaterniond()
    ..rotateX(math.pi / 2)
    ..rotateZ(math.pi / 2),
  Direction.east => Quaterniond()
    ..rotateX(math.pi / 2)
    ..rotateZ(-math.pi / 2),
};

/// `SimMathUtils.clampIntoCone`: [v] clamped into the cone of [coneAngle]
/// radians around [coneAxis], normalized.
///
/// The `1.01` keeps the discriminant positive when [v] is the axis or almost
/// its opposite.
Vector3d clampIntoCone(Vector3d v, Vector3d coneAxis, double coneAngle) {
  final vv = v.dot(v);
  final vn = v.dot(coneAxis);
  final nn = coneAxis.dot(coneAxis);
  final disc = nn * vv * 1.01 - vn * vn;
  final offsetDistance = (-vn + math.sqrt(math.max(disc, 0))) / math.tan(coneAngle);

  if ((offsetDistance < 0) != (coneAngle < 0)) return v;

  return v..fma(offsetDistance, coneAxis)..normalize();
}

/// `SimMathUtils.getQuaternionfFromVectorRotation`: the shortest rotation from
/// [from] to [to].
Quaterniond rotationBetween(Vector3d from, Vector3d to, [Quaterniond? dest]) {
  final out = dest ?? Quaterniond();
  final a = Vector3d.copy(from)..normalize();
  final b = Vector3d.copy(to)..normalize();
  final dot = a.dot(b).clamp(-1.0, 1.0);

  if (dot > 0.999999) return out.identity();
  if (dot < -0.999999) {
    // Opposite vectors: any perpendicular axis works.
    final axis = a.cross(a.x.abs() < 0.9 ? Vector3d(1, 0, 0) : Vector3d(0, 1, 0))..normalize();
    return out.fromAxisAngle(axis, math.pi);
  }

  final axis = a.cross(b);
  return out.fromAxisAngle(axis, math.acos(dot));
}

/// The matrix of the orientation, for the smart propeller's pitch readout.
Matrix3d orientationMatrix(Quaterniond orientation, [Matrix3d? dest]) =>
    (dest ?? Matrix3d()).setFromQuaternion(orientation);

/// `Direction.get(Direction.AxisDirection.POSITIVE, axis).getClockWise()`: the
/// horizontal direction the smart propeller hinges around.
Direction hingeDirection(Axis horizontalAxis) => switch (horizontalAxis) {
  Axis.x => Direction.south,
  Axis.z => Direction.west,
  Axis.y => Direction.north,
};
