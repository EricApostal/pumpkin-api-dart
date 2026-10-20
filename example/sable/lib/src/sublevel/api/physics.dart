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
import '../math/matrix3.dart';
import '../math/pose.dart';
import '../math/vector.dart';

/// `dev.ryanhcode.sable.api.physics.handle.RigidBodyHandle`: the physics body of
/// one sub-level.
abstract interface class RigidBodyHandle {
  Vector3d getLinearVelocity([Vector3d? dest]);

  Vector3d getAngularVelocity([Vector3d? dest]);

  /// `applyLinearAndAngularImpulse(linear, angular, wakeUp)`.
  void applyLinearAndAngularImpulse(Vector3d linear, Vector3d angular, bool wakeUp);

  /// `applyForcesAndReset(ForceTotal)`: sends the accumulated local force and
  /// torque as one impulse and resets the total
  /// (`RigidBodyHandle.java:176-178`, `ForceTotal.java:29-43`).
  void applyForcesAndReset(ForceTotal forceTotal);

  /// `applyImpulseAtPoint(position, force)`: a local impulse at the plot-local
  /// [position] (`RigidBodyHandle.java:80-88`).
  void applyImpulseAtPoint(Vector3d position, Vector3d force);

  /// `teleport(position, orientation)`.
  void teleport(Vector3d position, Quaterniond orientation);

  /// `addLinearAndAngularVelocity(linear, angular)`.
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular);

  /// `isValid()`: whether the body is still in the pipeline
  /// (`RigidBodyHandle.java:220-222`).
  bool get isValid;
}

/// `dev.ryanhcode.sable.api.physics.mass.MassData`: the mass properties the
/// model reads.
abstract interface class MassData {
  /// `getMass()`: total mass [kg].
  double getMass();

  /// `getCenterOfMass()`.
  ///
  /// Java returns `null` for a tracker whose blocks are gone; Dart's trackers
  /// throw a [StateError] with a precise message instead, and callers guard
  /// with [isInvalid].
  Vector3d getCenterOfMass();

  double getInverseMass();

  /// `getInertiaTensor()`: the inertia tensor in local space [kg·m²].
  Matrix3d getInertiaTensor();

  /// `getInverseInertiaTensor()`: `getInertiaTensor().invert()`.
  Matrix3d getInverseInertiaTensor();

  /// Whether the tracker is no longer usable (the sub-level's blocks are gone).
  bool isInvalid();

  /// The bounding box the tracker covers, when known.
  BoundingBox3ic? getBounds();
}

/// `PhysicsPipelineBody`'s single-axis impulses, as the `/sable physics
/// impulse` command applies them.
extension RigidBodyImpulses on RigidBodyHandle {
  /// `applyLinearImpulse(impulse)`.
  void applyLinearImpulse(Vector3d impulse) =>
      applyLinearAndAngularImpulse(impulse, Vector3d(), true);

  /// `applyAngularImpulse(impulse)`.
  void applyAngularImpulse(Vector3d impulse) =>
      applyLinearAndAngularImpulse(Vector3d(), impulse, true);

  /// `applyTorqueImpulse(torque)`.
  void applyTorqueImpulse(Vector3d torque) => applyAngularImpulse(torque);
}

/// `dev.ryanhcode.sable.api.physics.force.ForceTotal`: the local force and
/// torque accumulated between two physics ticks.
///
/// The body is only woken when the total changed by more than `1e-5` since the
/// last [applyForces] (`ForceTotal.java:29-43`), so a constant force lets a
/// resting body sleep.
final class ForceTotal {
  final Vector3d _lastLocalForce = Vector3d();
  final Vector3d _lastLocalTorque = Vector3d();
  final Vector3d _localForce = Vector3d();
  final Vector3d _localTorque = Vector3d();
  final Vector3d _temp = Vector3d();

  /// `applyForces(handle)`: applies the totals and clears them.
  void applyForces(RigidBodyHandle handle) {
    final forceChanged = _localForce.distanceSquared(_lastLocalForce) > 1e-5;
    final torqueChanged = _localTorque.distanceSquared(_lastLocalTorque) > 1e-5;

    handle.applyLinearAndAngularImpulse(
      _localForce,
      _localTorque,
      forceChanged || torqueChanged,
    );

    _lastLocalForce.setFrom(_localForce);
    _lastLocalTorque.setFrom(_localTorque);
    _localForce.zero();
    _localTorque.zero();
  }

  /// `reset()`: clears the current total, leaving the last-applied value alone.
  void reset() {
    _localForce.zero();
    _localTorque.zero();
  }

  /// `applyForceTotal(other)`: adds another total to this one.
  void applyForceTotal(ForceTotal other) {
    _localForce.add(other._localForce);
    _localTorque.add(other._localTorque);
  }

  /// `applyLinearAndAngularImpulse(impulse, torque)`.
  void applyLinearAndAngularImpulse(Vector3d impulse, Vector3d torque) {
    _localForce.add(impulse);
    _localTorque.add(torque);
  }

  /// `applyLinearImpulse(impulse)`.
  void applyLinearImpulse(Vector3d impulse) => _localForce.add(impulse);

  /// `applyAngularImpulse(impulse)`.
  void applyAngularImpulse(Vector3d impulse) => _localTorque.add(impulse);

  /// `applyTorqueImpulse(torque)`.
  void applyTorqueImpulse(Vector3d torque) => applyAngularImpulse(torque);

  /// `applyImpulseAtPoint(massData, position, force)`: adds [force] and the
  /// torque its lever arm around the centre of mass produces.
  void applyImpulseAtPoint(MassData massData, Vector3d position, Vector3d force) {
    _localForce.add(force);
    position.subInto(massData.getCenterOfMass(), _temp);
    _temp.crossInto(force, _temp);
    _localTorque.add(_temp);
  }

  /// `getLocalForce()`: the accumulated local force [N].
  Vector3d getLocalForce() => _localForce;

  /// `getLocalTorque()`: the accumulated local torque [Nm].
  Vector3d getLocalTorque() => _localTorque;
}

/// A force group (`dev.ryanhcode.sable.api.physics.force.ForceGroup`).
///
/// Java's record carries a display name, an optional description, an RGB
/// colour and whether the group is shown by default; the registry key is what
/// [name] holds here, since the Dart side has no component registry.
/// Equality is by [name], the unique key of a group.
final class ForceGroup {
  /// The registry key, e.g. `sable:gravity` (`ForceGroups.java:22-30`).
  final String name;

  /// The description shown to players, or `null`.
  final String? description;

  /// The RGB colour used by force displays.
  final int color;

  /// Whether GUIs display the group by default.
  final bool defaultDisplayed;

  const ForceGroup(
    this.name, {
    this.description,
    this.color = 0,
    this.defaultDisplayed = false,
  });

  static const ForceGroup gravity = ForceGroup('sable:gravity', color: 0x216e55);
  static const ForceGroup drag = ForceGroup('sable:drag', color: 0x834f31);
  static const ForceGroup levitation = ForceGroup(
    'sable:levitation',
    color: 0x734480,
    defaultDisplayed: true,
  );
  static const ForceGroup balloonLift = ForceGroup(
    'sable:balloon_lift',
    color: 0xd2643e,
    defaultDisplayed: true,
  );
  static const ForceGroup propulsion = ForceGroup(
    'sable:propulsion',
    color: 0x5a7c9f,
    defaultDisplayed: true,
  );
  static const ForceGroup lift = ForceGroup(
    'sable:lift',
    color: 0x8cb6c6,
    defaultDisplayed: true,
  );
  static const ForceGroup magneticForce = ForceGroup(
    'sable:magnetic_force',
    color: 0xe05343,
  );

  @override
  bool operator ==(Object other) => other is ForceGroup && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'ForceGroup[$name]';
}

/// The sub-level-side inputs a [QueuedForceGroup] needs
/// (`ServerSubLevel.getMassTracker`/`isTrackingIndividualQueuedForces`).
///
/// [ServerSubLevel] implements it; the interface keeps `physics.dart` free of
/// an import cycle.
abstract interface class QueuedForceTarget {
  /// The sub-level's mass tracker (`ServerSubLevel.getMassTracker`).
  MassData getMassTracker();

  /// Whether individual point forces should be recorded for display.
  bool isTrackingIndividualQueuedForces();
}

/// `dev.ryanhcode.sable.api.physics.force.QueuedForceGroup`: the accumulated
/// point forces of one [ForceGroup] between two physics ticks
/// (`QueuedForceGroup.java:12-51`).
final class QueuedForceGroup {
  /// The sub-level the forces belong to.
  final QueuedForceTarget subLevel;

  /// The recorded point forces, for the force-display overlay.
  final List<PointForce> _appliedForces = [];

  final ForceTotal _forceTotal = ForceTotal();

  QueuedForceGroup(this.subLevel);

  /// `getForceTotal()`: the accumulated local force and torque.
  ForceTotal getForceTotal() => _forceTotal;

  /// `applyAndRecordPointForce(point, force)`: applies [force] at the
  /// plot-local [point] — which also contributes the torque of its lever arm
  /// around the centre of mass — and records it.
  void applyAndRecordPointForce(Vector3d point, Vector3d force) {
    _forceTotal.applyImpulseAtPoint(subLevel.getMassTracker(), point, force);
    recordPointForce(point, force);
  }

  /// `recordPointForce(point, force)`: records [force] for display when the
  /// sub-level tracks individual forces. Forces below `0.001 N` are ignored.
  void recordPointForce(Vector3d point, Vector3d force) {
    if (!subLevel.isTrackingIndividualQueuedForces()) {
      return;
    }
    if (force.lengthSquared > 0.001 * 0.001) {
      _appliedForces.add(PointForce(Vector3d.copy(point), Vector3d.copy(force)));
    }
  }

  /// `getRecordedPointForces()`.
  List<PointForce> getRecordedPointForces() => List.unmodifiable(_appliedForces);

  /// `reset()`: clears the total and the recorded forces.
  void reset() {
    _forceTotal.reset();
    _appliedForces.clear();
  }
}

/// `QueuedForceGroup.PointForce`: one recorded point force.
final class PointForce {
  final Vector3d point;
  final Vector3d force;

  const PointForce(this.point, this.force);
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
