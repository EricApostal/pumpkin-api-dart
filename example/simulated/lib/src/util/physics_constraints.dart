// The joint motors the assembler and the swivel bearing drive.
//
// Both blocks hold a sub-level with a joint whose axes have PD motors: the
// assembler pulls a sub-level onto a whole-block grid before it places the
// blocks back, and the swivel bearing holds its target angle. The engine side is
// sable's `PhysicsConstraintHandle.setMotor`; this file is the part that is pure
// — the axis sets and the gain maths — plus the one lookup that gets a pipeline
// out of a level.
//
// Pure: no host imports.
import 'package:sable/sable.dart';

import '../content/blocks/swivel_bearing/swivel_bearing_logic.dart';

/// The motors of the assembler's alignment joint, as Java sets them.
///
/// Java: `PhysicsAssemblerBlockEntity`'s `LINEAR_*`/`ANGULAR_*` constants
abstract final class AssemblyAlignmentMotors {
  /// Stiffness of the linear alignment motors.
  static const double linearStiffness = 1000;

  /// Damping of the linear alignment motors.
  static const double linearDamping = 50;

  /// Stiffness of the angular alignment motors.
  static const double angularStiffness = 13000;

  /// Damping of the angular alignment motors.
  static const double angularDamping = 1000;

  /// The axes the joint locks with a stiff motor: the three angles.
  static const List<int> angularAxes = [
    ConstraintJointAxis.angularX,
    ConstraintJointAxis.angularY,
    ConstraintJointAxis.angularZ,
  ];

  /// The axes the joint holds with a soft motor, then tightens: the three
  /// positions.
  static const List<int> linearAxes = [
    ConstraintJointAxis.linearX,
    ConstraintJointAxis.linearY,
    ConstraintJointAxis.linearZ,
  ];

  /// The motors that hold a sub-level at [localGoal] (its rotation point in the
  /// joint's frame) and at zero rotation.
  ///
  /// [tightenLinear] swaps the soft linear motor for the stiff one, which the
  /// assembler does once the joint exists.
  static List<(int axis, double target, double stiffness, double damping)> motors({
    required Vector3d localGoal,
    bool tightenLinear = false,
  }) => [
    for (final axis in angularAxes)
      (axis, 0.0, angularStiffness, angularDamping),
    (ConstraintJointAxis.linearX, localGoal.x, tightenLinear ? linearStiffness : 0.000001, linearDamping),
    (ConstraintJointAxis.linearY, localGoal.y, tightenLinear ? linearStiffness : 0.000001, linearDamping),
    (ConstraintJointAxis.linearZ, localGoal.z, tightenLinear ? linearStiffness : 0.000001, linearDamping),
  ];

  /// Applies [motors] to [handle].
  static void apply(
    PhysicsConstraintHandle handle,
    List<(int axis, double target, double stiffness, double damping)> motors,
  ) {
    for (final (axis, target, stiffness, damping) in motors) {
      handle.setMotor(axis, target, stiffness, damping, false, 0.0);
    }
  }
}

/// The hinge of a swivel bearing.
///
/// Java: `SwivelBearingBlockEntity#attachConstraints` and
/// `#updateServoCoefficients`, plus `RotaryConstraintHandle.DEFAULT_AXIS`
///
/// The joint is a rotary constraint between the sub-level the bearing stands in
/// and the sub-level its plate is in. The hinge turns about the joint's own
/// angular Y axis, which is the axis Rapier's rotary joint drives.
abstract final class SwivelHinge {
  /// `RotaryConstraintHandle.DEFAULT_AXIS`: the axis the servo drives.
  static const int defaultAxis = ConstraintJointAxis.angularY;

  /// `attachConstraints(plateSubLevel, attachPos)`: the hinge between
  /// [containingSubLevel] (which may be `null` for a bearing in the world) and
  /// [plateSubLevel].
  ///
  /// [anchor] is the centre of the block in front of the bearing, [attachPos]
  /// the centre of the plate's facing side, and the two axes the hinge's
  /// direction on either side.
  static PhysicsConstraintHandle? attach(
    ConstraintPipeline pipeline, {
    required Object? containingSubLevel,
    required Object? plateSubLevel,
    required Vector3d anchor,
    required Vector3d attachPos,
    required Vector3d axis,
    required Vector3d plateAxis,
  }) {
    // Java pulls the two anchors 1 mm apart along the plate's facing so the
    // solver has a definite hinge direction rather than a degenerate one.
    final offset = Vector3d.copy(plateAxis)..mul(0.001);
    return pipeline.addConstraint(
      containingSubLevel,
      plateSubLevel,
      RotaryConstraintConfiguration(
        Vector3d.copy(anchor),
        Vector3d.copy(attachPos)..sub(offset),
        Vector3d.copy(axis),
        Vector3d.copy(plateAxis),
      ),
    );
  }

  /// The inertia of [mass] about [axis], or `null` when the tracker has none.
  static double? inertiaAbout(MassData? mass, Vector3d axis) {
    if (mass == null) return null;
    final transformed = mass.getInertiaTensor().transform(Vector3d.copy(axis));
    return transformed.dot(axis);
  }

  /// `updateServoCoefficients`: drives the hinge's motor for this tick.
  ///
  /// [partialTick] interpolates the target angle, so the servo sees a smooth
  /// goal between ticks. Returns the settings that were applied, or `null` when
  /// there was no handle.
  static SwivelMotorSettings? drive(
    PhysicsConstraintHandle? handle, {
    required SwivelBearingLogic logic,
    required double partialTick,
    required MassData? containingMass,
    required MassData? plateMass,
    required Vector3d axis,
    required double stiffness,
    required double damping,
    required double friction,
  }) {
    if (handle == null || !handle.isValid) return null;

    final settings = logic.motorFor(
      hasHandle: true,
      partialTick: partialTick,
      inertiaA: inertiaAbout(containingMass, axis),
      inertiaB: inertiaAbout(plateMass, axis),
      stiffness: stiffness,
      damping: damping,
      friction: friction,
    );
    if (settings == null) return null;

    handle.setMotor(defaultAxis, settings.goal, settings.stiffness, settings.damping, false, 0.0);
    return settings;
  }
}

/// The physics pipeline of [level], when the level has one that takes joints.
///
/// Returns `null` when the level has no container, the container has no physics
/// system, or the pipeline does not implement [ConstraintPipeline]. Callers treat
/// that as "no alignment this tick" rather than as an error: a level without
/// physics still assembles and disassembles, it just cannot pull the sub-level
/// straight first.
ConstraintPipeline? constraintPipelineOf(SableLevel level) {
  final container = SubLevelContainer.of(level);
  if (container is! ServerSubLevelContainer) return null;
  final system = container.physics;
  if (system is! SubLevelPhysicsSystem) return null;
  final pipeline = system.getPipeline();
  // The two interfaces are unrelated, so the value needs an explicit cast; a
  // pipeline that does not take joints simply has no alignment.
  return pipeline is ConstraintPipeline ? pipeline as ConstraintPipeline : null;
}
