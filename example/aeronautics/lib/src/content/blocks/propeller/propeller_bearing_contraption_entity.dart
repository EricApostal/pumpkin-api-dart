// The contraption entity of a propeller bearing: a controlled contraption that
// also carries the gyroscopic tilt.
//
// Java: `content/blocks/propeller/bearing/contraption/PropellerBearingContraptionEntity`.
//
// A plain bearing contraption only rotates; this one applies the tilt of a
// gyroscopic bearing to the local transform, so the propeller visibly swings
// with gravity. The bearing pushes the tilt into the entity every tick.
import 'dart:math' as math;

// create's contraption entity is not exported from its barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/entity/controlled_contraption_entity.dart';
import 'package:sable/sable.dart' show Quaterniond, Vector3d;

/// The registered entity type key (`AeroEntityTypes.PROPELLER_CONTROLLED_CONTRAPTION`,
/// `AeroEntityTypes.java:23`).
const String propellerBearingContraptionEntityKey =
    'aeronautics:propeller_bearing_contraption';

/// `PropellerBearingContraptionEntity`.
class PropellerBearingContraptionEntity extends ControlledContraptionEntity {
  PropellerBearingContraptionEntity(super.host);

  /// The tilt applied this tick.
  final Quaterniond tiltQuat = Quaterniond();

  /// The tilt of the last tick, for the interpolation.
  final Quaterniond previousTiltQuat = Quaterniond();

  /// The facing of the bearing that owns this contraption.
  Direction direction = Direction.up;

  final Quaterniond _interpolated = Quaterniond();

  /// `getInterpolatedQuat`: the tilt at [partialTicks].
  Quaterniond getInterpolatedQuat(double partialTicks) =>
      previousTiltQuat.nlerp(tiltQuat, partialTicks, _interpolated);

  /// `applyRotation`: rotate by the angle, then by the inverse tilt.
  @override
  Vec3 applyRotation(Vec3 localPos, double partialTicks) {
    var pos = VecHelper.rotate(localPos, getAngle(partialTicks), rotationAxis ?? Axis.y);
    pos = _rotateReverse(pos, getInterpolatedQuat(partialTicks));
    return pos;
  }

  /// `reverseRotation`: undo the tilt, then the angle.
  @override
  Vec3 reverseRotation(Vec3 localPos, double partialTicks) {
    var pos = _rotate(localPos, getInterpolatedQuat(partialTicks));
    pos = VecHelper.rotate(pos, -getAngle(partialTicks), rotationAxis ?? Axis.y);
    return pos;
  }

  /// `SimMathUtils.rotateQuatReverse`: rotate by the inverse of [q].
  static Vec3 _rotateReverse(Vec3 v, Quaterniond q) {
    final inverse = Quaterniond.copy(q)..conjugate();
    return _rotate(v, inverse);
  }

  /// `SimMathUtils.rotateQuat`: rotate [v] by [q].
  static Vec3 _rotate(Vec3 v, Quaterniond q) {
    final out = Vector3d(v.$1, v.$2, v.$3);
    q.transform(out, out);
    return (out.x, out.y, out.z);
  }

  /// The tilt of the bearing at [partialTicks], as an angle around the facing.
  double tiltAngle(double partialTicks) {
    final quat = getInterpolatedQuat(partialTicks);
    return 2 * math.acos(quat.w.abs().clamp(-1.0, 1.0));
  }
}
