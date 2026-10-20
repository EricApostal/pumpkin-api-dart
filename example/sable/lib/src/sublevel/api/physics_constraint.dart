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

  /// Which axes are locked (`ConstraintJointAxis` bit mask).
  final int lockedAxesMask;

  GenericConstraintConfiguration(
    this.pos1,
    this.quatA,
    this.pos2,
    this.quatB,
    this.lockedAxesMask,
  );
}

/// `ConstraintJointAxis`: the bit of each axis in the generic lock mask.
abstract final class ConstraintJointAxis {
  static const int linearX = 1;
  static const int linearY = 2;
  static const int linearZ = 4;
  static const int angularX = 8;
  static const int angularY = 16;
  static const int angularZ = 32;

  /// Every axis.
  static const int all = 63;
}

/// `PhysicsConstraintHandle`.
abstract interface class PhysicsConstraintHandle {
  /// `setContactsEnabled(enabled)`.
  void setContactsEnabled(bool enabled);
}

/// The constraint half of a physics pipeline, for engines that support joints.
abstract interface class ConstraintPipeline {
  /// `addConstraint(a, b, configuration)`.
  PhysicsConstraintHandle addConstraint(
    Object a,
    Object b,
    PhysicsConstraintConfiguration configuration,
  );
}
