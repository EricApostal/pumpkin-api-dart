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

/// Whether a block along the segment [from]–[to] satisfies [blockedAt].
///
/// `Level.clip` in Java; the walk is Amanatides–Woo, so it visits exactly the
/// voxels the segment crosses and stops at the first one [blockedAt] accepts.
/// The starting voxel is not tested (the ray starts at the entity, which is
/// inside its own block).
bool segmentBlocked(
  Vector3d from,
  Vector3d to,
  bool Function(int x, int y, int z) blockedAt,
) {
  final dx = to.x - from.x;
  final dy = to.y - from.y;
  final dz = to.z - from.z;
  if (dx == 0 && dy == 0 && dz == 0) return false;

  var x = from.x.floor();
  var y = from.y.floor();
  var z = from.z.floor();

  final stepX = dx > 0 ? 1 : (dx < 0 ? -1 : 0);
  final stepY = dy > 0 ? 1 : (dy < 0 ? -1 : 0);
  final stepZ = dz > 0 ? 1 : (dz < 0 ? -1 : 0);

  double tMaxX, tMaxY, tMaxZ, tDeltaX, tDeltaY, tDeltaZ;
  if (stepX == 0) {
    tMaxX = double.infinity;
    tDeltaX = double.infinity;
  } else {
    tMaxX = ((x + (stepX > 0 ? 1 : 0)) - from.x) / dx;
    tDeltaX = (1 / dx).abs();
  }
  if (stepY == 0) {
    tMaxY = double.infinity;
    tDeltaY = double.infinity;
  } else {
    tMaxY = ((y + (stepY > 0 ? 1 : 0)) - from.y) / dy;
    tDeltaY = (1 / dy).abs();
  }
  if (stepZ == 0) {
    tMaxZ = double.infinity;
    tDeltaZ = double.infinity;
  } else {
    tMaxZ = ((z + (stepZ > 0 ? 1 : 0)) - from.z) / dz;
    tDeltaZ = (1 / dz).abs();
  }

  while (true) {
    final t = tMaxX < tMaxY
        ? (tMaxX < tMaxZ ? tMaxX : tMaxZ)
        : (tMaxY < tMaxZ ? tMaxY : tMaxZ);
    if (t > 1) return false;

    if (tMaxX <= tMaxY && tMaxX <= tMaxZ) {
      x += stepX;
      tMaxX += tDeltaX;
    } else if (tMaxY <= tMaxZ) {
      y += stepY;
      tMaxY += tDeltaY;
    } else {
      z += stepZ;
      tMaxZ += tDeltaZ;
    }

    if (blockedAt(x, y, z)) return true;
  }
}
