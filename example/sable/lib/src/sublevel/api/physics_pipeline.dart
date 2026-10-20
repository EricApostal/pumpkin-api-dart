// `dev.ryanhcode.sable.api.physics.PhysicsPipeline`: the engine-facing half of
// the physics seam.
//
// `sable/common/.../api/physics/PhysicsPipeline.java:34-252` is the Java
// contract; `sable_rapier/.../rapier/RapierPhysicsPipeline.java` is its only
// implementation there, and `JoltPhysicsPipeline` (package `sable_jolt`) is the
// Dart one. `api/physics.dart` holds the model-facing types (`RigidBodyHandle`,
// `MassData`, force groups); this file adds the pipeline itself plus the
// box/rope objects and handles it owns.
//
// Pure: no host imports. The host-free part matters: `example/sable` is loaded
// by the Dart VM tests, so nothing here may import `dart:_wasm`.
import '../math/bounding_box.dart';
import '../math/pose.dart';
import '../math/vector.dart';
import '../model/server_sub_level.dart';
import 'physics.dart';

/// `dev.ryanhcode.sable.api.physics.PhysicsPipeline`.
///
/// A pipeline owns one physics scene: the sub-level bodies, the arbitrary
/// bodies (boxes, ropes), the voxel world those bodies collide with, and the
/// constraints between them.
abstract interface class PhysicsPipeline {
  /// `init(gravity, universalDrag)`: creates the scene.
  void init(Vector3d gravity, double universalDrag);

  /// `dispose()`: releases every native resource.
  void dispose();

  /// `tick()`: per-tick bookkeeping that also runs while physics is paused
  /// (`RapierPhysicsPipeline.java:184-186` clears its query cache here).
  void tick();

  /// `prePhysicsTicks()`: runs once per game tick before the substeps
  /// (`RapierPhysicsPipeline.java:146-149`, which calls `rope::tick`,
  /// `joints::tick` and `compute_buoyancy`).
  void prePhysicsTicks();

  /// `physicsTick(timeStep)`: one physics substep.
  void physicsTick(double timeStep);

  /// `postPhysicsTicks()`: finalizes the game tick.
  void postPhysicsTicks();

  /// Adds a sub-level body at [pose] and returns the handle to attach to
  /// `subLevel.physicsBody`.
  RigidBodyHandle addSubLevel(ServerSubLevel subLevel, Pose3dc pose);

  /// Removes the sub-level body. A missing body is not an error.
  void removeSubLevel(ServerSubLevel subLevel);

  /// Adds a kinematic contraption to the scene (`PhysicsPipeline.java:76`).
  ///
  /// Contraptions are Create entities; the compat layer (W6) drives them.
  void addContraption(KinematicContraption contraption);

  /// Removes a kinematic contraption.
  void removeContraption(KinematicContraption contraption);

  /// Reads the current pose of [subLevel] into [dest].
  Pose3d readPose(ServerSubLevel subLevel, Pose3d dest);

  /// Adds a box body.
  BoxHandle addBox(BoxPhysicsObject box);

  /// Removes a box body.
  void removeBox(BoxHandle box);

  /// Adds a rope (a chain of dynamic points).
  RopeHandle addRope(RopePhysicsObject rope);

  /// Removes a rope.
  void removeRope(RopeHandle rope);

  /// Uploads one chunk section to the physics world.
  ///
  /// [blockStates] has 4096 entries, indexed `bx + (bz << 4) + (by << 8)` (the
  /// layout `RapierPhysicsPipeline.handleChunkSectionAddition` packs at
  /// `RapierPhysicsPipeline.java:335-356`), each
  /// `(voxelColliderId + 1) << 16 | voxelStateIndex`.
  ///
  /// [global] selects the static level (the shared world) over a sub-level
  /// body; a non-global section belongs to [subLevelRuntimeId].
  void handleChunkSectionAddition(
    int x,
    int y,
    int z,
    List<int> blockStates, {
    required bool global,
    int? subLevelRuntimeId,
  });

  /// Removes one chunk section (`handleChunkSectionRemoval`).
  void handleChunkSectionRemoval(int x, int y, int z, {bool global = false});

  /// Replaces the block at the **global** block position [x],[y],[z] with
  /// [packedState] (`handleBlockChange`). [x],[y],[z] are absolute block
  /// coordinates, as `RapierPhysicsPipeline.java:386-406` converts them.
  void handleBlockChange(int x, int y, int z, int packedState);

  /// Re-uploads center of mass, mass properties and bounds
  /// (`onStatsChanged`, `RapierPhysicsPipeline.java:409-423`).
  void onStatsChanged(ServerSubLevel subLevel);

  /// Teleports a body (`PhysicsPipeline.java:154`).
  void teleport(RigidBodyHandle body, Vector3d position, Quaterniond orientation);

  /// Applies an impulse at the plot-local position [position]
  /// (`PhysicsPipeline.java:158`; the pipeline subtracts the body's center of
  /// mass, `RapierPhysicsPipeline.java:450-456`).
  void applyImpulse(RigidBodyHandle body, Vector3d position, Vector3d force);

  /// Adds a local force and torque (`PhysicsPipeline.java:167-170`).
  void applyLinearAndAngularImpulse(
    RigidBodyHandle body,
    Vector3d force,
    Vector3d torque,
    bool wakeUp,
  );

  /// Adds linear and angular velocities (`PhysicsPipeline.java:179-181`).
  void addLinearAndAngularVelocity(
    RigidBodyHandle body,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
  );

  /// Resets the velocity of [body] (`PhysicsPipeline.java:188-190`).
  void resetVelocity(RigidBodyHandle body);

  /// The world-space linear velocity of [body] (`PhysicsPipeline.java:199-201`).
  Vector3d getLinearVelocity(RigidBodyHandle body, Vector3d dest);

  /// The world-space angular velocity of [body] (`PhysicsPipeline.java:209-211`).
  Vector3d getAngularVelocity(RigidBodyHandle body, Vector3d dest);

  /// Wakes [body] up (`PhysicsPipeline.java:218`).
  void wakeUp(RigidBodyHandle body);

  /// The next runtime id handed to a collider or sub-level
  /// (`PhysicsPipeline.java:251`).
  int getNextRuntimeId();
}

/// `dev.ryanhcode.sable.api.physics.object.box.BoxPhysicsObject`: a cuboid body.
final class BoxPhysicsObject {
  /// The pose of the box. Rotation point and scale are ignored: the body's
  /// origin is its geometric center (`BoxPhysicsObject.java:41-48`).
  final Pose3d pose;

  /// The half extents of the cuboid.
  final Vector3d halfExtents;

  /// The mass of the box, in kilograms.
  final double mass;

  BoxPhysicsObject(this.pose, this.halfExtents, this.mass);
}

/// `dev.ryanhcode.sable.api.physics.object.box.BoxHandle`.
abstract interface class BoxHandle {
  /// Queries the pose of the box from the physics engine.
  void readPose(Pose3d dest);

  /// Removes the box from the pipeline.
  void remove();

  /// Wakes the box up.
  void wakeUp();

  /// The runtime id of the box.
  int getRuntimeId();
}

/// `dev.ryanhcode.sable.api.physics.object.rope.RopePhysicsObject`: a rope made
/// of points, each becoming a dynamic body in the chain
/// (`sable_rapier/src/main/rust/rapier/src/rope.rs:108-260`).
final class RopePhysicsObject {
  /// The points of the rope, in world space.
  final List<Vector3d> points;

  /// The collision radius of every segment.
  final double collisionRadius;

  RopePhysicsObject(this.points, this.collisionRadius);

  /// The bounding box the rope requires to be loaded
  /// (`RopePhysicsObject.java:60-72`).
  BoundingBox3d boundingBox() {
    final first = points.first;
    final box = BoundingBox3d.full(first.x, first.y, first.z, first.x, first.y, first.z);
    for (final point in points) {
      box.expandToValues(
        point.x - collisionRadius,
        point.y - collisionRadius,
        point.z - collisionRadius,
      );
      box.expandToValues(
        point.x + collisionRadius,
        point.y + collisionRadius,
        point.z + collisionRadius,
      );
    }
    return box;
  }
}

/// `dev.ryanhcode.sable.api.physics.object.rope.RopeHandle`.
abstract interface class RopeHandle {
  /// Queries the current point positions of the rope.
  List<Vector3d> queryPoints();

  /// Removes the rope from the pipeline.
  void remove();

  /// The runtime id of the rope.
  int getRuntimeId();
}
