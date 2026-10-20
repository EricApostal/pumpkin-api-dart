// `dev.ryanhcode.sable.util.SableMathUtils`: the pure math helpers Sable uses.
//
// Only the functions the sub-level model needs are ported here (the Java class
// also has inertia-tensor helpers that belong to the physics workstream):
// angular velocity from two orientations, and snapping a quaternion to one of
// the 24 axis-aligned grid orientations.
//
// Pure: no host imports.
import 'dart:math' as math;

import '../math/vector.dart';

/// The 24 axis-aligned quaternions, in the Java order.
final List<Quaterniond> _allQuats = [
  Quaterniond(0, 0, 0, 1),
  Quaterniond(1, 0, 0, 0),
  Quaterniond(0, 1, 0, 0),
  Quaterniond(0, 0, 1, 0),
  Quaterniond(1, 0, 0, 1)..normalize(),
  Quaterniond(0, 1, 0, 1)..normalize(),
  Quaterniond(0, 0, 1, 1)..normalize(),
  Quaterniond(0, 1, 1, 0)..normalize(),
  Quaterniond(1, 0, 1, 0)..normalize(),
  Quaterniond(1, 1, 0, 0)..normalize(),
  Quaterniond(1, 1, 1, 1)..normalize(),
];

/// The pure math helpers of Sable.
abstract final class SableMathUtils {
  /// `getAngularVelocity(lastOrientation, orientation, dest)`: the angular
  /// velocity that takes [lastOrientation] to [orientation] in one tick.
  static Vector3d getAngularVelocity(
    Quaterniond lastOrientation,
    Quaterniond orientation,
    [Vector3d? dest]
  ) {
    final out = dest ?? Vector3d();
    final difference = orientation.difference(lastOrientation, Quaterniond()).conjugate();

    if (difference.w < 0) {
      difference.mulScalar(-1);
    }

    final angularVelocity = out.set(difference.x, difference.y, difference.z);

    if (angularVelocity.lengthSquared <= 1e-15) {
      angularVelocity.mul(2.0 / difference.w);
    } else {
      angularVelocity.normalize().mul(2.0 * math.acos(difference.w.clamp(-1.0, 1.0)));
    }
    return out;
  }

  /// `clampQuaternionToGrid(q, gridQuats, dest)`: snaps [q] to the nearest
  /// quaternion of [gridQuats].
  static Quaterniond clampQuaternionToGrid(
    Quaterniond q,
    Iterable<Quaterniond> gridQuats, [
    Quaterniond? dest,
  ]) {
    final signX = q.x < 0 ? -1 : 1;
    final signY = q.y < 0 ? -1 : 1;
    final signZ = q.z < 0 ? -1 : 1;
    final signW = q.w < 0 ? -1 : 1;

    final work = dest ?? Quaterniond();
    work.set(q.x, q.y, q.z, q.w);
    // Enforce q to only have non-positive entries, so that adding behaves like
    // subtraction.
    work.x *= -signX;
    work.y *= -signY;
    work.z *= -signZ;
    work.w *= -signW;

    final temp = Quaterniond();
    final best = Quaterniond();
    var distance = 10.0;

    for (final grid in gridQuats) {
      final currentDistance = temp
          .set(work.x + grid.x, work.y + grid.y, work.z + grid.z, work.w + grid.w)
          .lengthSquared;
      if (currentDistance < distance) {
        distance = currentDistance;
        best.setFrom(grid);
      }
    }

    work
      ..setFrom(best)
      ..x *= signX
      ..y *= signY
      ..z *= signZ
      ..w *= signW;
    return work;
  }

  /// The 24 grid quaternions (`GridQuats.ALL`).
  static Iterable<Quaterniond> get allGridQuaternions => _allQuats;
}
