// The physics contracts `ServerSubLevel` exposes to the rest of Sable.
//
// Sable's Java `ServerSubLevel` implements `PhysicsPipelineBody` and talks to a
// Rapier-backed `PhysicsPipeline`. The Dart physics pipeline is workstream W3;
// this file is the seam it plugs into, so the world model can be written and
// tested without it.
//
// `ServerSubLevel.physicsBody` is `null` until W3 attaches a body. Methods that
// genuinely cannot do anything without a body throw a [StateError] with a
// precise message — they never silently pretend the sub-level has no velocity.
//
// Pure: no host imports.
import '../math/bounding_box.dart';
import '../math/pose.dart';
import '../math/vector.dart';

/// `dev.ryanhcode.sable.api.physics.handle.RigidBodyHandle`: the physics body of
/// one sub-level.
abstract interface class RigidBodyHandle {
  Vector3d getLinearVelocity([Vector3d? dest]);

  Vector3d getAngularVelocity([Vector3d? dest]);

  /// `applyLinearAndAngularImpulse(linear, angular, wakeUp)`.
  void applyLinearAndAngularImpulse(Vector3d linear, Vector3d angular, bool wakeUp);

  /// `applyForcesAndReset(Vector3dc)`.
  void applyForcesAndReset(Vector3d force);

  /// `teleport(position, orientation)`.
  void teleport(Vector3d position, Quaterniond orientation);

  /// `addLinearAndAngularVelocity(linear, angular)`.
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular);
}

/// `dev.ryanhcode.sable.api.physics.mass.MassData`: the mass properties the
/// model reads.
abstract interface class MassData {
  /// `getCenterOfMass()`.
  Vector3d getCenterOfMass();

  double getInverseMass();

  /// Whether the tracker is no longer usable (the sub-level's blocks are gone).
  bool isInvalid();

  /// The bounding box the tracker covers, when known.
  BoundingBox3ic? getBounds();
}

/// A named force group (`dev.ryanhcode.sable.api.physics.force.ForceGroup`).
final class ForceGroup {
  final String name;

  const ForceGroup(this.name);

  static const ForceGroup lift = ForceGroup('sable:lift');
  static const ForceGroup drag = ForceGroup('sable:drag');

  @override
  bool operator ==(Object other) => other is ForceGroup && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'ForceGroup[$name]';
}

/// `QueuedForceGroup`: the accumulated point forces of one [ForceGroup] between
/// two physics ticks.
final class QueuedForceGroup {
  final Object subLevel;
  final Vector3d _forceTotal = Vector3d();

  QueuedForceGroup(this.subLevel);

  /// `recordPointForce(position, force)`.
  void recordPointForce(Vector3d position, Vector3d force) => _forceTotal.add(force);

  /// `getForceTotal()`.
  Vector3d getForceTotal() => _forceTotal;

  /// `reset()`.
  void reset() => _forceTotal.zero();
}

/// The splitting heat map of a sub-level (`SubLevelHeatMapManager`, W4).
abstract interface class SubLevelHeatMap {
  void tick();
}

/// A kinematic contraption inside a plot (`api.sublevel.KinematicContraption`).
///
/// The Create contraption types implement this in the compat layer; the model
/// only needs the local pose and the lift providers.
abstract interface class KinematicContraption {
  /// The local bounds of the contraption.
  void sable$getLocalBounds(BoundingBox3i bounds);

  /// The block getter of the contraption.
  Object sable$blockGetter();

  /// The mass tracker of the contraption.
  MassData sable$getMassTracker();

  /// The position at [partialTick].
  Vector3d sable$getPosition(double partialTick);

  /// The orientation at [partialTick].
  Quaterniond sable$getOrientation(double partialTick);

  /// The lift provider contexts of the contraption.
  Map<(int, int, int), Object> sable$liftProviders();

  /// Whether the contraption should collide.
  bool sable$shouldCollide();

  /// Whether the contraption is still valid.
  bool sable$isValid();

  /// The local pose of the contraption.
  Pose3d sable$getLocalPose(Pose3d dest, double partialTick) {
    dest.rotationPoint().setFrom(sable$getMassTracker().getCenterOfMass());
    dest.position().setFrom(sable$getPosition(partialTick));
    dest.orientation().setFrom(sable$getOrientation(partialTick));
    dest.scale().set(1.0, 1.0, 1.0);
    return dest;
  }
}
