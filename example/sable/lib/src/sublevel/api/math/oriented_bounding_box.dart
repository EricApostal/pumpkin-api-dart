// `dev.ryanhcode.sable.api.math.OrientedBoundingBox3d`: an oriented box with
// extents, orientation and position, plus the SAT / swept-SAT routines the
// entity collision code uses.
//
// The box is expected to be centred on its position.
//
// Pure: no host imports.
import 'dart:math' as math;

import '../../math/vector.dart';
import 'level_reused_vectors.dart';

/// An oriented bounding box.
final class OrientedBoundingBox3d {
  /// `(1, 0, 0)`.
  static final Vector3d unitX = Vector3d(1.0, 0.0, 0.0);

  /// `(0, 1, 0)`.
  static final Vector3d unitY = Vector3d(0.0, 1.0, 0.0);

  /// `(0, 0, 1)`.
  static final Vector3d unitZ = Vector3d(0.0, 0.0, 1.0);

  static final Vector3d right = unitX;
  static final Vector3d up = unitY;
  static final Vector3d forward = unitZ;

  final Vector3d _position = Vector3d();
  final Vector3d _dimensions = Vector3d();
  final Quaterniond _orientation = Quaterniond();
  final LevelReusedVectors sink;

  /// Creates an empty box using [sink] for scratch vectors.
  OrientedBoundingBox3d(this.sink);

  /// Creates a box at [position] with [dimensions] (total size) and
  /// [orientation].
  OrientedBoundingBox3d.withValues(
    Vector3d position,
    Vector3d dimensions,
    Quaterniond orientation,
    this.sink,
  ) {
    _position.setFrom(position);
    _dimensions.setFrom(dimensions);
    _orientation.setFrom(orientation);
  }

  /// Creates a box at `(x, y, z)` with total sizes `sizeX, sizeY, sizeZ`.
  OrientedBoundingBox3d.at(
    double x,
    double y,
    double z,
    double sizeX,
    double sizeY,
    double sizeZ,
    Quaterniond orientation,
    this.sink,
  ) {
    _position.set(x, y, z);
    _dimensions.set(sizeX, sizeY, sizeZ);
    _orientation.setFrom(orientation);
  }

  /// Sets position, dimensions and orientation.
  void set(Vector3d position, Vector3d dimensions, Quaterniond orientation) {
    _position.setFrom(position);
    _dimensions.setFrom(dimensions);
    _orientation.setFrom(orientation);
  }

  /// Sets the centre.
  OrientedBoundingBox3d setPosition(Vector3d position) {
    _position.setFrom(position);
    return this;
  }

  /// Sets the total dimensions.
  OrientedBoundingBox3d setDimensions(Vector3d dimensions) {
    _dimensions.setFrom(dimensions);
    return this;
  }

  /// Sets the orientation.
  OrientedBoundingBox3d setOrientation(Quaterniond orientation) {
    _orientation.setFrom(orientation);
    return this;
  }

  /// The orientation.
  Quaterniond getOrientation() => _orientation;

  /// The centre.
  Vector3d getPosition() => _position;

  /// The total dimensions.
  Vector3d getDimensions() => _dimensions;

  /// Computes all eight global vertices of this box into [result].
  List<Vector3d> vertices(List<Vector3d> result) {
    _dimensions.mulInto(0.5, sink.tempmin);
    _dimensions.mulInto(-0.5, sink.tempmax);

    _orientation.transform(sink.tempmin, result[0]).add(_position);
    _orientation
        .transform(sink.tempVert1.set(sink.tempmax.x, sink.tempmin.y, sink.tempmin.z), result[1])
        .add(_position);
    _orientation
        .transform(sink.tempVert4.set(sink.tempmin.x, sink.tempmin.y, sink.tempmax.z), result[4])
        .add(_position);
    _orientation
        .transform(sink.tempVert5.set(sink.tempmax.x, sink.tempmin.y, sink.tempmax.z), result[5])
        .add(_position);
    _orientation
        .transform(sink.tempVert3.set(sink.tempmax.x, sink.tempmax.y, sink.tempmin.z), result[3])
        .add(_position);
    _orientation
        .transform(sink.tempVert2.set(sink.tempmin.x, sink.tempmax.y, sink.tempmin.z), result[2])
        .add(_position);
    _orientation
        .transform(sink.tempVert6.set(sink.tempmin.x, sink.tempmax.y, sink.tempmax.z), result[6])
        .add(_position);
    _orientation.transform(sink.tempmax, result[7]).add(_position);

    return result;
  }

  /// Rotates [vec] from local space to global space.
  Vector3d rotate(Vector3d vec) => _orientation.transform(vec, vec);

  static bool _doesOverlap(Vector2d a, Vector2d b) => a.x <= b.y && a.y >= b.x;

  /// The overlap of the two intervals.
  static double getOverlap(Vector2d a, Vector2d b) {
    if (!_doesOverlap(a, b)) return 0.0;
    return math.min(a.y, b.y) - math.max(a.x, b.x);
  }

  /// Computes the minimum translation vector between two OBBs.
  static Vector3d sat(OrientedBoundingBox3d obbA, OrientedBoundingBox3d obbB) =>
      satInto(obbA, obbB, Vector3d());

  /// Computes the minimum translation vector between two OBBs into [dest].
  static Vector3d satInto(
    OrientedBoundingBox3d obbA,
    OrientedBoundingBox3d obbB,
    Vector3d dest,
  ) {
    final context = obbA.sink;

    final verticesA = obbA.vertices(context.a);
    final verticesB = obbB.vertices(context.b);

    final checker = obbA._position.subInto(obbB._position, context.checker).normalize();

    final aRight = obbA.rotate(context.obbARight.setFrom(unitX));
    final aUp = obbA.rotate(context.obbAUp.setFrom(unitY));
    final aForward = obbA.rotate(context.obbAForward.setFrom(unitZ));

    final bRight = obbB.rotate(context.obbBRight.setFrom(unitX));
    final bUp = obbB.rotate(context.obbBUp.setFrom(unitY));
    final bForward = obbB.rotate(context.obbBForward.setFrom(unitZ));

    final mtv = dest.setScalar(double.maxFinite);

    genChecks(aRight, aUp, aForward, bRight, bUp, bForward, context.checks);

    var minOverlap = double.maxFinite;

    for (final check in context.checks) {
      if (check.lengthSquared <= 0.0) continue;

      check.normalize();

      checkSeparation(verticesA, check, context.proj1);
      checkSeparation(verticesB, check, context.proj2);

      if (check.dot(checker) > 0) check.mul(-1.0);

      final overlap = getOverlap(context.proj1, context.proj2);

      if (overlap == 0.0) {
        // Shapes are not overlapping.
        return dest.zero();
      } else if (overlap < minOverlap) {
        minOverlap = overlap;
        mtv.setFrom(check.mul(minOverlap));
      }
    }

    final facingOpposite =
        obbA._position.subInto(obbB._position, context.oppo).dot(mtv) < 0;

    if (facingOpposite) mtv.mul(-1.0);

    return mtv;
  }

  /// Sweeps [obbA] along [sweep] against [obbB].
  static SweepResult sweep(
    OrientedBoundingBox3d obbA,
    OrientedBoundingBox3d obbB,
    Vector3d sweep,
    SweepResult dest,
  ) {
    final context = obbA.sink;

    final aX = obbA.rotate(context.obbARight.setFrom(unitX));
    final aY = obbA.rotate(context.obbAUp.setFrom(unitY));
    final aZ = obbA.rotate(context.obbAForward.setFrom(unitZ));

    final bX = obbB.rotate(context.obbBRight.setFrom(unitX));
    final bY = obbB.rotate(context.obbBUp.setFrom(unitY));
    final bZ = obbB.rotate(context.obbBForward.setFrom(unitZ));

    genChecks(aX, aY, aZ, bX, bY, bZ, context.checks);

    var tFirst = 0.0;
    var tLast = double.infinity;
    var minOverlap = double.infinity;

    final hitNormal = context.hitNormal.zero();
    final exitNormal = context.exitNormal.zero();
    final overlapNormal = context.overlapNormal.zero();

    final relativePos = context.relativePos.setFrom(obbB._position).sub(obbA._position);

    const epsilon = 1e-5;
    for (final check in context.checks) {
      if (check.lengthSquared < epsilon) continue;

      check.normalize();

      final rA =
          0.5 * obbA._dimensions.x * aX.dot(check).abs() +
          0.5 * obbA._dimensions.y * aY.dot(check).abs() +
          0.5 * obbA._dimensions.z * aZ.dot(check).abs();

      final rB =
          0.5 * obbB._dimensions.x * bX.dot(check).abs() +
          0.5 * obbB._dimensions.y * bY.dot(check).abs() +
          0.5 * obbB._dimensions.z * bZ.dot(check).abs();

      final r = rA + rB;
      final distance = relativePos.dot(check);
      final speed = sweep.dot(check);

      final overlap = r - distance.abs();
      if (overlap >= 0 && overlap < minOverlap) {
        minOverlap = overlap;
        overlapNormal.setFrom(check);
        if (distance > 0) overlapNormal.negate();
      }

      if (speed.abs() < epsilon) {
        if (distance.abs() > r) {
          dest.reset();
          return dest;
        }
        continue;
      }

      final t1 = (distance - r) / speed;
      final t2 = (distance + r) / speed;
      final tNear = math.min(t1, t2);
      final tFar = math.max(t1, t2);

      if (tNear > tFirst) {
        tFirst = tNear;
        hitNormal.setFrom(check);
        if (distance > 0) hitNormal.negate();
      }
      if (tFar < tLast) {
        tLast = tFar;
        exitNormal.setFrom(check);
        if (speed <= 0) exitNormal.negate();
      }

      if (tFirst > tLast) {
        dest.reset();
        return dest;
      }
    }

    if (!(tFirst <= tLast) || tFirst > 1.0) {
      dest.reset();
      return dest;
    }

    if (hitNormal.lengthSquared <= 0 && minOverlap != double.infinity) {
      hitNormal.setFrom(overlapNormal);
    }

    dest.reset();
    dest.hit = true;
    dest.entryT = tFirst;
    dest.exitT = tLast;
    dest.exitNormal.setFrom(exitNormal);
    dest.normal.setFrom(hitNormal);
    return dest;
  }

  /// The 15 candidate separating axes of two boxes.
  static List<Vector3d> genChecks(
    Vector3d aRight,
    Vector3d aUp,
    Vector3d aForward,
    Vector3d bRight,
    Vector3d bUp,
    Vector3d bForward,
    List<Vector3d> checks,
  ) {
    checks[0].setFrom(aRight);
    checks[1].setFrom(aUp);
    checks[2].setFrom(aForward);
    checks[3].setFrom(bRight);
    checks[4].setFrom(bUp);
    checks[5].setFrom(bForward);
    aRight.crossInto(bRight, checks[6]);
    aRight.crossInto(bUp, checks[7]);
    aRight.crossInto(bForward, checks[8]);
    aUp.crossInto(bRight, checks[9]);
    aUp.crossInto(bUp, checks[10]);
    aUp.crossInto(bForward, checks[11]);
    aForward.crossInto(bRight, checks[12]);
    aForward.crossInto(bUp, checks[13]);
    aForward.crossInto(bForward, checks[14]);

    return checks;
  }

  /// Projects [self] onto [axis]; the result is `[min, max]`.
  static Vector2d checkSeparation(List<Vector3d> self, Vector3d axis, Vector2d result) {
    if (axis.lengthSquared <= 0.0) return result.set(0.0, 0.0);

    var min = double.maxFinite;
    var max = -double.maxFinite;

    for (final vec in self) {
      final dot = vec.dot(axis);
      min = math.min(dot, min);
      max = math.max(dot, max);
    }

    return result.set(min, max);
  }
}

/// The result of [sweep].
final class SweepResult {
  bool hit = false;
  double entryT = 0.0;
  double exitT = 0.0;
  final Vector3d exitNormal = Vector3d();
  final Vector3d normal = Vector3d();

  /// Clears the result.
  void reset() {
    hit = false;
    exitNormal.zero();
    normal.zero();
    entryT = 0.0;
    exitT = 0.0;
  }
}
