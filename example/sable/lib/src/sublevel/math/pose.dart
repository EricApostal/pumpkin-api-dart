// `dev.ryanhcode.sable.companion.math.Pose3d`: a position, rotation, rotation
// point and scale. The mutable read-write half (`Pose3d`) is what the model
// stores; the abstract `Pose3dc` carries the read-only transforms.
//
// Pure: no host imports.
//
// create's pure helpers (positions, `Aabb`, `BlockBounds`) are not exported from
// its public barrel yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:pumpkin_api/src/geometry.dart' show Vec3;

import 'bounding_box.dart';
import 'vector.dart';

/// A read-only 3D pose, consisting of a position, rotation, and scale.
///
/// The transform semantics match Sable exactly:
/// `global = orientation * ((local - rotationPoint) * scale) + position`.
abstract class Pose3dc {
  const Pose3dc();

  /// The global position of this pose.
  Vector3d position();

  /// The global orientation of this pose.
  Quaterniond orientation();

  /// The rotation point of this pose.
  Vector3d rotationPoint();

  /// The global scale of this pose.
  Vector3d scale();

  /// Transform a local position to a global position, storing it in [dest].
  Vector3d transformPosition(Vector3d local, [Vector3d? dest]) {
    final out = dest ?? Vector3d();
    final relative = local.subInto(rotationPoint(), out).mulVec(scale());
    return orientation().transform(relative, out).add(position());
  }

  /// `transformPosition(Vec3)` for the immutable record vectors the rest of the
  /// port uses.
  Vec3 transformPositionVec(Vec3 local) {
    final v = transformPosition(Vector3d(local.$1, local.$2, local.$3));
    return (v.x, v.y, v.z);
  }

  /// Transform a global position to a local position, storing it in [dest].
  Vector3d transformPositionInverse(Vector3d global, [Vector3d? dest]) {
    final out = dest ?? Vector3d();
    final s = scale();
    final relative = global.subInto(position(), out);
    orientation().transformInverse(relative, out);
    return out
        .mulVec(Vector3d(1.0 / s.x, 1.0 / s.y, 1.0 / s.z))
        .add(rotationPoint());
  }

  /// `transformPositionInverse(Vec3)` for record vectors.
  Vec3 transformPositionInverseVec(Vec3 global) {
    final v = transformPositionInverse(Vector3d(global.$1, global.$2, global.$3));
    return (v.x, v.y, v.z);
  }

  /// Transforms a local normal to a global normal.
  ///
  /// If the scale is non-uniform, the result will not be of the same magnitude.
  Vector3d transformNormal(Vector3d local, [Vector3d? dest]) {
    final out = dest ?? Vector3d();
    final scaled = local.mulVecInto(scale(), out);
    return orientation().transform(scaled, out);
  }

  /// `transformNormal(Vec3)` for record vectors.
  Vec3 transformNormalVec(Vec3 local) {
    final v = transformNormal(Vector3d(local.$1, local.$2, local.$3));
    return (v.x, v.y, v.z);
  }

  /// Transforms a global normal to a local normal.
  ///
  /// If the scale is non-uniform, the result will not be of the same magnitude.
  Vector3d transformNormalInverse(Vector3d global, [Vector3d? dest]) {
    final out = dest ?? Vector3d();
    orientation().transformInverse(global, out);
    final s = scale();
    return out.mulVec(Vector3d(1.0 / s.x, 1.0 / s.y, 1.0 / s.z));
  }

  /// `transformNormalInverse(Vec3)` for record vectors.
  Vec3 transformNormalInverseVec(Vec3 global) {
    final v = transformNormalInverse(Vector3d(global.$1, global.$2, global.$3));
    return (v.x, v.y, v.z);
  }

  /// Lerps this pose towards [pose] by [frac], writing into [dest].
  Pose3d lerp(Pose3dc pose, double frac, Pose3d dest) {
    dest.position().set(
      position().x + (pose.position().x - position().x) * frac,
      position().y + (pose.position().y - position().y) * frac,
      position().z + (pose.position().z - position().z) * frac,
    );
    orientation().nlerp(pose.orientation(), frac, dest.orientation());
    dest.rotationPoint().set(
      rotationPoint().x + (pose.rotationPoint().x - rotationPoint().x) * frac,
      rotationPoint().y + (pose.rotationPoint().y - rotationPoint().y) * frac,
      rotationPoint().z + (pose.rotationPoint().z - rotationPoint().z) * frac,
    );
    dest.scale().set(
      scale().x + (pose.scale().x - scale().x) * frac,
      scale().y + (pose.scale().y - scale().y) * frac,
      scale().z + (pose.scale().z - scale().z) * frac,
    );
    return dest;
  }

  /// Bakes this pose into a matrix transform.
  Matrix4d bakeIntoMatrix(Matrix4d dest) {
    final rp = rotationPoint();
    return dest
        .identity()
        .translate(position().x, position().y, position().z)
        .rotate(orientation())
        .scale(scale())
        .translate(-rp.x, -rp.y, -rp.z);
  }

  /// Whether this pose is within [distanceTolerance] metres and
  /// [angularTolerance] radians of [pose].
  bool withinTolerance(Pose3d pose, double distanceTolerance, double angularTolerance) {
    final d2 = distanceTolerance * distanceTolerance;
    return position().distanceSquared(pose.position()) <= d2 &&
        rotationPoint().distanceSquared(pose.rotationPoint()) <= d2 &&
        orientation().div(pose.orientation(), Quaterniond()).angle() <= angularTolerance;
  }
}

/// A read-write 3D pose, consisting of a position, rotation, and scale.
final class Pose3d extends Pose3dc {
  final Vector3d _position;
  final Quaterniond _orientation;
  final Vector3d _rotationPoint;
  final Vector3d _scale;

  /// The identity pose: no translation or rotation, unit scale.
  Pose3d()
    : _position = Vector3d(),
      _orientation = Quaterniond(),
      _rotationPoint = Vector3d(),
      _scale = Vector3d(1.0, 1.0, 1.0);

  /// `new Pose3d(Pose3dc)`: a deep copy.
  Pose3d.copy(Pose3dc pose)
    : _position = Vector3d.copy(pose.position()),
      _orientation = Quaterniond.copy(pose.orientation()),
      _rotationPoint = Vector3d.copy(pose.rotationPoint()),
      _scale = Vector3d.copy(pose.scale());

  /// `new Pose3d(position, orientation, rotationPoint, scale)`.
  ///
  /// The vectors are taken as-is (Java semantics: no copy).
  Pose3d.full(this._position, this._orientation, this._rotationPoint, this._scale);

  /// Copies all values from [pose] into this pose.
  Pose3d set(Pose3dc pose) {
    _position.setFrom(pose.position());
    _orientation.setFrom(pose.orientation());
    _rotationPoint.setFrom(pose.rotationPoint());
    _scale.setFrom(pose.scale());
    return this;
  }

  /// Lerps this pose towards [pose] by [frac], in place.
  Pose3d lerpInPlace(Pose3dc pose, double frac) => lerp(pose, frac, this);

  @override
  Vector3d position() => _position;

  @override
  Quaterniond orientation() => _orientation;

  @override
  Vector3d rotationPoint() => _rotationPoint;

  @override
  Vector3d scale() => _scale;

  /// The transform of this pose as a matrix (the Java `bakeIntoMatrix`).
  Matrix4d matrix() => bakeIntoMatrix(Matrix4d());

  /// The box of [bounds] after this transform.
  BoundingBox3d transformBounds(BoundingBox3dc bounds) =>
      bounds.transform(this, BoundingBox3d());

  @override
  String toString() => 'Pose3d{position=$_position, orientation=$_orientation, '
      'rotationPoint=$_rotationPoint, scale=$_scale}';
}
