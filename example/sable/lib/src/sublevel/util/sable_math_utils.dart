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

/// The 11 base axis-aligned quaternions (`SableMathUtils.ALL_QUATS`,
/// `SableMathUtils.java:15-27`). The opposite of each is the same rotation
/// with every component negated, which is why the groups below only need these.
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

/// `SableMathUtils.GridQuats`: a subset of [_allQuats] selected by a bit
/// pattern, plus the orientations the pattern leaves out ([opposite]).
///
/// The Java enum's bit patterns (`SableMathUtils.java:197-211`), from least
/// significant bit (index 0 of `ALL_QUATS`) upwards:
///
/// | group | pattern | indices |
/// |---|---|---|
/// | `ALL` | `0b11111111111` | every one |
/// | `X_AXIS` | `0b10011` | 0, 1, 4 |
/// | `Y_AXIS` | `0b100101` | 0, 2, 5 |
/// | `Z_AXIS` | `0b1001001` | 0, 3, 6 |
/// | `REAL` | `0b10001110001` | 0, 4, 5, 6, 10 |
final class GridQuats {
  /// The orientations the bit pattern selects.
  final List<Quaterniond> quaternions;

  /// The orientations the bit pattern leaves out (`opposite()` in Java).
  final List<Quaterniond> oppositeQuaternions;

  GridQuats._(int bitPattern) : quaternions = [], oppositeQuaternions = [] {
    for (var i = 0; i < _allQuats.length; i++) {
      ((bitPattern & 1) > 0 ? quaternions : oppositeQuaternions).add(_allQuats[i]);
      bitPattern >>= 1;
    }
  }

  /// `GridQuats.ALL`: all 11 base orientations.
  static final GridQuats all = GridQuats._(0x7FF);

  /// `GridQuats.X_AXIS`.
  static final GridQuats xAxis = GridQuats._(0x13) /* 0b10011 */;

  /// `GridQuats.Y_AXIS`.
  static final GridQuats yAxis = GridQuats._(0x25) /* 0b100101 */;

  /// `GridQuats.Z_AXIS`.
  static final GridQuats zAxis = GridQuats._(0x49) /* 0b1001001 */;

  /// `GridQuats.REAL`: identity, the three quarter turns and the 120° corner
  /// rotation — the orientations `getHitBoxYaw` snaps to.
  static final GridQuats real = GridQuats._(0x471) /* 0b10001110001 */;

  /// `opposite()`: the orientations this group leaves out.
  Iterable<Quaterniond> get opposite => oppositeQuaternions;

  @override
  String toString() => 'GridQuats[${quaternions.length} + ${oppositeQuaternions.length} opposite]';
}

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

  /// All grid quaternions (`GridQuats.ALL`).
  static Iterable<Quaterniond> get allGridQuaternions => GridQuats.all.quaternions;
}
