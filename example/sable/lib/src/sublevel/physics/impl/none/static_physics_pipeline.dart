// `dev.ryanhcode.sable.physics.impl.none.StaticPhysicsPipeline`: a physics
// engine that does nothing, and keeps every sub-level static
// (`StaticPhysicsPipeline.java:1-166`).
//
// It is the fallback provider (priority `900`, below the default `1000`): when
// no real solver is registered, a sub-level still exists, still has a body
// handle and still reports its logical pose, but no force moves it. That is
// what makes the sub-level model usable before a solver is ported.
//
// The Java class returns `null` from `addBox`/`addRope`; here those return a
// handle that remembers the object and does nothing. The pipeline contract in
// this port has non-nullable handles, and a caller that ignores the difference
// gets the same "nothing moves" behaviour instead of a null dereference.
// `TODO(parity)`: `StaticPhysicsPipeline.java:92-103` returns `null`.
//
// Pure: no host imports.
import '../../../host/sub_level_host.dart';
import '../../../math/pose.dart';
import '../../../math/vector.dart';
import '../../../model/server_sub_level.dart';
import '../../../api/physics.dart';
import '../../../api/physics_pipeline.dart';
import '../../../api/physics_pipeline_provider.dart';

/// The provider of the no-op pipeline (`StaticPhysicsPipelineProvider.java`).
///
/// Priority `900` (`StaticPhysicsPipelineProvider.java:9`), i.e. below the
/// default `1000` of a real solver, so it is only picked as a fallback.
final class StaticPhysicsPipelineProvider implements PhysicsPipelineProvider {
  const StaticPhysicsPipelineProvider();

  @override
  int get loadPriority => 900;

  @override
  PhysicsPipeline createPipeline(SableLevel level) => StaticPhysicsPipeline();
}

/// A physics engine that does nothing, and keeps every sub-level static.
final class StaticPhysicsPipeline implements PhysicsPipeline {
  /// The bodies added to this pipeline, by sub-level.
  final Map<ServerSubLevel, StaticBodyHandle> bodies = {};

  /// The boxes added to this pipeline.
  final List<StaticBoxHandle> boxes = [];

  /// The ropes added to this pipeline.
  final List<StaticRopeHandle> ropes = [];

  /// The contraptions added to this pipeline.
  final List<KinematicContraption> contraptions = [];

  int _nextRuntimeId = 0;

  /// `init(gravity, universalDrag)`: no-op.
  @override
  void init(Vector3d gravity, double universalDrag) {}

  /// `dispose()`: no-op.
  @override
  void dispose() {
    bodies.clear();
    boxes.clear();
    ropes.clear();
    contraptions.clear();
  }

  /// `tick()`: no-op.
  @override
  void tick() {}

  /// `prePhysicsTicks()`: no-op.
  @override
  void prePhysicsTicks() {}

  /// `physicsTick(timeStep)`: no-op — the sub-levels stay where they are.
  @override
  void physicsTick(double timeStep) {}

  /// `postPhysicsTicks()`: no-op.
  @override
  void postPhysicsTicks() {}

  /// `add(subLevel, pose)`: records the body and returns its handle.
  ///
  /// Java ignores [pose]; the sub-level's logical pose is the truth here too.
  @override
  RigidBodyHandle addSubLevel(ServerSubLevel subLevel, Pose3dc pose) {
    final existing = bodies[subLevel];
    if (existing != null) return existing;
    final handle = StaticBodyHandle(subLevel, _nextRuntimeId++);
    bodies[subLevel] = handle;
    return handle;
  }

  /// `remove(subLevel)`: forgets the body.
  @override
  void removeSubLevel(ServerSubLevel subLevel) => bodies.remove(subLevel);

  /// `add(contraption)`: no-op beyond remembering it.
  @override
  void addContraption(KinematicContraption contraption) {
    if (!contraptions.contains(contraption)) contraptions.add(contraption);
  }

  /// `remove(contraption)`.
  @override
  void removeContraption(KinematicContraption contraption) => contraptions.remove(contraption);

  /// `readPose(subLevel, dest)`: the sub-level's logical pose, unchanged.
  @override
  Pose3d readPose(ServerSubLevel subLevel, Pose3d dest) => dest.set(subLevel.logicalPose);

  /// `addBox(box)`: remembers the box, no simulation.
  @override
  BoxHandle addBox(BoxPhysicsObject box) {
    final handle = StaticBoxHandle(box, _nextRuntimeId++);
    boxes.add(handle);
    return handle;
  }

  /// `removeBox(box)`.
  @override
  void removeBox(BoxHandle box) => boxes.remove(box);

  /// `addRope(rope)`: remembers the rope, no simulation.
  @override
  RopeHandle addRope(RopePhysicsObject rope) {
    final handle = StaticRopeHandle(rope, _nextRuntimeId++);
    ropes.add(handle);
    return handle;
  }

  /// `removeRope(rope)`.
  @override
  void removeRope(RopeHandle rope) => ropes.remove(rope);

  /// `handleChunkSectionAddition`: no-op.
  @override
  void handleChunkSectionAddition(
    int x,
    int y,
    int z,
    List<int> blockStates, {
    required bool global,
    int? subLevelRuntimeId,
  }) {}

  /// `handleChunkSectionRemoval`: no-op.
  @override
  void handleChunkSectionRemoval(int x, int y, int z, {bool global = false}) {}

  /// `handleBlockChange`: no-op.
  @override
  void handleBlockChange(int x, int y, int z, int packedState) {}

  /// `onStatsChanged`: no-op.
  @override
  void onStatsChanged(ServerSubLevel subLevel) {}

  /// `teleport(body, position, orientation)`: writes the sub-level's logical
  /// pose, exactly like `StaticPhysicsPipeline.java:117-122`.
  ///
  /// A body that is not a [StaticBodyHandle] is ignored, as Java ignores a
  /// non-`ServerSubLevel` body.
  @override
  void teleport(RigidBodyHandle body, Vector3d position, Quaterniond orientation) {
    if (body is! StaticBodyHandle) return;
    body.subLevel.logicalPose.position().setFrom(position);
    body.subLevel.logicalPose.orientation().setFrom(orientation);
  }

  /// `applyImpulse`: no-op.
  @override
  void applyImpulse(RigidBodyHandle body, Vector3d position, Vector3d force) {}

  /// `applyLinearAndAngularImpulse`: no-op.
  @override
  void applyLinearAndAngularImpulse(
    RigidBodyHandle body,
    Vector3d force,
    Vector3d torque,
    bool wakeUp,
  ) {}

  /// `addLinearAndAngularVelocity`: no-op.
  @override
  void addLinearAndAngularVelocity(
    RigidBodyHandle body,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
  ) {}

  /// `resetVelocity`: no-op.
  @override
  void resetVelocity(RigidBodyHandle body) {}

  /// `getLinearVelocity`: always zero; nothing moves.
  @override
  Vector3d getLinearVelocity(RigidBodyHandle body, Vector3d dest) => dest.set(0, 0, 0);

  /// `getAngularVelocity`: always zero; nothing moves.
  @override
  Vector3d getAngularVelocity(RigidBodyHandle body, Vector3d dest) => dest.set(0, 0, 0);

  /// `wakeUp`: no-op.
  @override
  void wakeUp(RigidBodyHandle body) {}

  /// `getNextRuntimeID()`: `0` in Java, and still `0` here.
  ///
  /// TODO(parity): `StaticPhysicsPipeline.java:163-165` returns a constant `0`,
  /// so two bodies share a runtime id. It is harmless because nothing
  /// simulates them; a real solver assigns unique ids.
  @override
  int getNextRuntimeId() => 0;
}

/// The body handle a [StaticPhysicsPipeline] hands out.
///
/// Every mutating operation is a no-op except [teleport], which writes the
/// sub-level's logical pose; the velocities are always zero.
final class StaticBodyHandle implements RigidBodyHandle {
  /// The sub-level this body belongs to.
  final ServerSubLevel subLevel;

  /// The runtime id (always `0` in the Java pipeline, `StaticPhysicsPipeline.java:163`).
  final int runtimeId;

  StaticBodyHandle(this.subLevel, this.runtimeId);

  @override
  Vector3d getLinearVelocity([Vector3d? dest]) => (dest ?? Vector3d()).set(0, 0, 0);

  @override
  Vector3d getAngularVelocity([Vector3d? dest]) => (dest ?? Vector3d()).set(0, 0, 0);

  @override
  void applyLinearAndAngularImpulse(Vector3d linear, Vector3d angular, bool wakeUp) {}

  @override
  void applyForcesAndReset(ForceTotal forceTotal) => forceTotal.reset();

  @override
  void applyImpulseAtPoint(Vector3d position, Vector3d force) {}

  @override
  void teleport(Vector3d position, Quaterniond orientation) {
    subLevel.logicalPose.position().setFrom(position);
    subLevel.logicalPose.orientation().setFrom(orientation);
  }

  @override
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular) {}

  @override
  bool get isValid => true;

  @override
  String toString() => 'StaticBodyHandle[$runtimeId, ${subLevel.uniqueId}]';
}

/// The box handle of a [StaticPhysicsPipeline]: remembers the box, never moves it.
final class StaticBoxHandle implements BoxHandle {
  final BoxPhysicsObject box;
  final int runtimeId;
  bool _removed = false;

  StaticBoxHandle(this.box, this.runtimeId);

  /// `readPose(dest)`: the pose the box was created with.
  @override
  void readPose(Pose3d dest) => dest.set(box.pose);

  @override
  void remove() => _removed = true;

  @override
  void wakeUp() {}

  @override
  int getRuntimeId() => runtimeId;

  @override
  String toString() => 'StaticBoxHandle[$runtimeId${_removed ? ', removed' : ''}]';
}

/// The rope handle of a [StaticPhysicsPipeline]: remembers the points, never moves them.
final class StaticRopeHandle implements RopeHandle {
  final RopePhysicsObject rope;
  final int runtimeId;
  bool _removed = false;

  StaticRopeHandle(this.rope, this.runtimeId);

  /// `queryPoints()`: the points the rope was created with.
  @override
  List<Vector3d> queryPoints() => [for (final point in rope.points) Vector3d.copy(point)];

  @override
  void remove() => _removed = true;

  @override
  int getRuntimeId() => runtimeId;

  @override
  String toString() => 'StaticRopeHandle[$runtimeId${_removed ? ', removed' : ''}]';
}
