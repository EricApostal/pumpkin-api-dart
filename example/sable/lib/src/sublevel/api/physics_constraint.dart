// `dev.ryanhcode.sable.api.physics.constraint`: the joint configurations the
// `/sable joint` and `/sable spawn joint_test` commands create.
//
// Sable's Java code hands these to `PhysicsPipeline.addConstraint`. The Dart
// pipeline (`api/physics_pipeline.dart`, physics workstream) has no constraint
// entry point yet, so the commands program against [ConstraintPipeline]: a
// pipeline that implements it can build joints, and the command reports a
// precise failure when it does not.
//
// Pure: no host imports.
import '../math/vector.dart';

/// A joint configuration.
sealed class PhysicsConstraintConfiguration {
  const PhysicsConstraintConfiguration();
}

/// `RotaryConstraintConfiguration`: a hinge.
final class RotaryConstraintConfiguration extends PhysicsConstraintConfiguration {
  /// The anchor on the first body, in its plot.
  final Vector3d pos1;

  /// The anchor on the second body, in its plot.
  final Vector3d pos2;

  /// The hinge axis of the first body.
  final Vector3d axis1;

  /// The hinge axis of the second body.
  final Vector3d axis2;

  RotaryConstraintConfiguration(this.pos1, this.pos2, this.axis1, this.axis2);
}

/// `FixedConstraintConfiguration`: the two bodies are welded.
final class FixedConstraintConfiguration extends PhysicsConstraintConfiguration {
  final Vector3d pos1;
  final Vector3d pos2;
  final Quaterniond quatB;

  FixedConstraintConfiguration(this.pos1, this.pos2, this.quatB);
}

/// `FreeConstraintConfiguration`: a spherical joint.
final class FreeConstraintConfiguration extends PhysicsConstraintConfiguration {
  final Vector3d pos1;
  final Vector3d pos2;
  final Quaterniond quatB;

  FreeConstraintConfiguration(this.pos1, this.pos2, this.quatB);
}

/// `GenericConstraintConfiguration`: six axes with a lock mask.
final class GenericConstraintConfiguration extends PhysicsConstraintConfiguration {
  final Vector3d pos1;
  final Quaterniond quatA;
  final Vector3d pos2;
  final Quaterniond quatB;

  /// Which axes are locked (`ConstraintJointAxisMask` bits).
  final int lockedAxesMask;

  GenericConstraintConfiguration(
    this.pos1,
    this.quatA,
    this.pos2,
    this.quatB,
    this.lockedAxesMask,
  );
}

/// `ConstraintJointAxis`: the axis number `setMotor`/`setLimit` take.
///
/// Java's enum ordinals are the contract (`RapierConstraintHandle.java:30`
/// passes `axis.ordinal()`), so these are **indices**, not bits: linear X/Y/Z
/// are 0-2 and angular X/Y/Z are 3-5. The lock mask uses
/// [ConstraintJointAxisMask] instead.
abstract final class ConstraintJointAxis {
  static const int linearX = 0;
  static const int linearY = 1;
  static const int linearZ = 2;
  static const int angularX = 3;
  static const int angularY = 4;
  static const int angularZ = 5;

  /// Every linear axis.
  static const List<int> linear = [linearX, linearY, linearZ];

  /// Every angular axis.
  static const List<int> angular = [angularX, angularY, angularZ];

  /// Every axis.
  static const List<int> all = [linearX, linearY, linearZ, angularX, angularY, angularZ];
}

/// The bit of each axis in a joint lock mask (Rapier's `JointAxesMask`, which
/// `jolt_joint_create_sixdof` and `jolt_joint_lock_axes` take).
abstract final class ConstraintJointAxisMask {
  static const int linearX = 1 << 0;
  static const int linearY = 1 << 1;
  static const int linearZ = 1 << 2;
  static const int angularX = 1 << 3;
  static const int angularY = 1 << 4;
  static const int angularZ = 1 << 5;

  /// Every axis.
  static const int all = 0x3f;
}

/// `PhysicsConstraintHandle`.
///
/// Java's interface is `sable/common/.../api/physics/constraint/
/// PhysicsConstraintHandle.java:9-46`: impulses, contacts, motors, removal and
/// validity. `ConstraintJointAxis`'s constants above are the axis numbers
/// `setMotor`/`setLimit` take (Java passes `ConstraintJointAxis.ordinal()`,
/// `RapierConstraintHandle.java:30`).
abstract interface class PhysicsConstraintHandle {
  /// `getJointImpulses(linearImpulseDest, angularImpulseDest)`: the latest
  /// global linear and angular joint impulses from the solver.
  void getJointImpulses(Vector3d linearImpulseDest, Vector3d angularImpulseDest);

  /// `setContactsEnabled(enabled)`.
  void setContactsEnabled(bool enabled);

  /// `setMotor(axis, target, stiffness, damping, hasMaxForce, maxForce)`: adds
  /// or sets a PD motor on [axis] (`RapierConstraintHandle.java:30-33`).
  ///
  /// [axis] is one of the [ConstraintJointAxis] indices (0-5); [target] is a
  /// position [m] or angle [rad] depending on the axis.
  void setMotor(
    int axis,
    double target,
    double stiffness,
    double damping,
    bool hasMaxForce,
    double maxForce,
  );

  /// `remove()`: removes the constraint from the engine.
  void remove();

  /// `isValid()`: whether the engine still holds the constraint.
  bool get isValid;
}

/// `GenericConstraintHandle`: the six-axis joint with re-anchorable frames.
abstract interface class GenericConstraintHandle implements PhysicsConstraintHandle {
  /// `setFrame1(localPosition, localOrientation)`.
  void setFrame1(Vector3d localPosition, Quaterniond localOrientation);

  /// `setFrame2(localPosition, localOrientation)`.
  void setFrame2(Vector3d localPosition, Quaterniond localOrientation);

  /// `setLimit(axis, min, max)`.
  void setLimit(int axis, double min, double max);

  /// `lockAxes(axes)`: a mask of [ConstraintJointAxisMask] bits.
  void lockAxes(int axes);
}

/// The constraint half of a physics pipeline, for engines that support joints.
abstract interface class ConstraintPipeline {
  /// `addConstraint(a, b, configuration)`.
  ///
  /// A `null` body attaches that side to the static world, as Java's `-1`
  /// body id does (`RapierRotaryConstraintHandle.java:20-23`).
  PhysicsConstraintHandle addConstraint(
    Object? a,
    Object? b,
    PhysicsConstraintConfiguration configuration,
  );
}
