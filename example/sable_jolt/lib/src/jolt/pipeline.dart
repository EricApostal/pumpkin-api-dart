// `JoltPhysicsPipeline`: Sable's `PhysicsPipeline` (`sable/lib/src/sublevel/
// api/physics_pipeline.dart`) on top of the Jolt core module.
//
// The Java implementation this replaces is
// `sable_rapier/src/main/java/dev/ryanhcode/sable/physics/impl/rapier/
// RapierPhysicsPipeline.java` plus the `Rapier3D` JNI entry points
// (`sable_rapier/src/main/rust/rapier/src/`). Every method below names the
// entry point and the file it mirrors.
//
// Marshalling only: poses and vectors cross as `f32` (Sable's `marten::Real`),
// block states as `u32`, scalars as `double`. Everything lives in the module's
// own linear memory, reached through [JoltMemory]; the functions are
// [JoltAbi]. Both are interfaces so the pipeline can be driven from the Dart VM
// against the real module (see `test/support/node_jolt.dart`).
//
// Pure: no host imports, so this file is loadable by `package:test`.
import 'package:sable/sable.dart'
    show
        BoxHandle,
        BoxPhysicsObject,
        KinematicContraption,
        MassData,
        PhysicsPipeline,
        Pose3d,
        Pose3dc,
        Quaterniond,
        RigidBodyHandle,
        RopeHandle,
        RopePhysicsObject,
        ServerSubLevel,
        Vector3d;

import '../physics/buoyancy.dart';
import 'abi.dart';
import 'voxel.dart';

/// A [MassData] that also reports its inertia tensor.
///
/// Java's `MassData` exposes `getMass()` and `getInertiaTensor()`
/// (`sable/common/.../api/physics/mass/MassData.java:12-26`) and
/// `Rapier3D.setMassPropertiesFrom` uploads all three
/// (`Rapier3D.java:675-690`). The Dart seam in `api/physics.dart` only carries
/// the inverse mass, so the pipeline reads the tensor through this interface
/// when the tracker provides one.
abstract interface class InertiaMassData implements MassData {
  /// The inertia tensor in local space, column-major:
  /// `m00, m10, m20, m01, m11, m21, m02, m12, m22`.
  List<double> getInertiaTensor();
}

/// The Jolt-backed physics pipeline.
final class JoltPhysicsPipeline implements PhysicsPipeline {
  /// The module's exported functions.
  final JoltAbi abi;

  /// The module's linear memory.
  final JoltMemory memory;

  /// The block collider registry (`VoxelColliderMap`,
  /// `voxel_collider.rs:12-31`).
  ///
  /// Shared by every pipeline because the module's registry is process-wide,
  /// like Rapier's global `PHYSICS_STATE` (`lib.rs`), so ids must keep matching
  /// across pipeline instances.
  static final BlockColliderRegistry _colliders = BlockColliderRegistry();

  /// The shared block collider registry.
  BlockColliderRegistry get colliders => _colliders;

  /// The static level's blocks, for buoyancy and block changes.
  final BlockSectionStore levelBlocks = BlockSectionStore();

  int _world = 0;
  int _nextRuntimeId = 0;

  // One scratch block in the module's memory.
  int _scratch = 0;
  int _posePtr = 0;
  int _vecPtr = 0;
  int _inertiaPtr = 0;
  int _chunkPtr = 0;

  final Map<ServerSubLevel, _SubLevelBody> _subLevels = {};

  /// Buoyancy forces computed by [prePhysicsTicks], applied before every
  /// substep by [physicsTick].
  final Map<_SubLevelBody, List<BuoyancyForce>> _buoyancy = {};

  JoltPhysicsPipeline({required this.abi, required this.memory});

  /// The native world handle, or 0 before [init].
  int get worldHandle => _world;

  /// `jolt_abi_version`: the version of the module's C ABI.
  int get moduleAbiVersion => abi.abiVersion();

  /// `jolt_version`: `JPH_VERSION_ID` of the linked Jolt build.
  int get moduleVersion => abi.version();

  @override
  void init(Vector3d gravity, double universalDrag) {
    if (_world != 0) {
      throw StateError('JoltPhysicsPipeline.init was already called.');
    }
    _world = abi.worldCreate(
      gravity.x,
      gravity.y,
      gravity.z,
      universalDrag,
    );
    if (_world == 0) {
      throw StateError('jolt_world_create returned no world.');
    }
    _allocateScratch();
  }

  @override
  void dispose() {
    if (_world == 0) {
      return;
    }
    abi.worldDestroy(_world);
    _world = 0;
    _subLevels.clear();
    _buoyancy.clear();
    if (_scratch != 0) {
      abi.free(_scratch);
      _scratch = 0;
    }
  }

  @override
  void tick() {
    // `RapierPhysicsPipeline.tick` clears its query cache
    // (`RapierPhysicsPipeline.java:184-186`); Jolt has no equivalent.
  }

  @override
  void prePhysicsTicks() {
    _requireWorld();
    // `RapierPhysicsPipeline.prePhysicsTicks` calls `Rapier3D.tick`, which runs
    // `rope::tick`, `joints::tick` and `compute_buoyancy` (`lib.rs:492-509`).
    // Rope and joint ticking are folded into their own calls; buoyancy is
    // recomputed here and applied before every substep (Rapier keeps forces
    // until the next `reset_forces`, so they act on every substep of a tick).
    _buoyancy.clear();
    for (final body in _subLevels.values) {
      if (body.removed) {
        continue;
      }
      final forces = _computeBuoyancy(body);
      if (forces.isNotEmpty) {
        _buoyancy[body] = forces;
      }
    }
  }

  @override
  void physicsTick(double timeStep) {
    _requireWorld();
    for (final entry in _buoyancy.entries) {
      final body = entry.key;
      if (body.removed) {
        continue;
      }
      for (final force in entry.value) {
        abi.bodyAddForceAt(
          _world,
          body.handle,
          force.point.x,
          force.point.y,
          force.point.z,
          force.force.x,
          force.force.y,
          force.force.z,
        );
      }
    }
    abi.worldStep(_world, timeStep);
  }

  @override
  void postPhysicsTicks() {
    // `RapierPhysicsPipeline.postPhysicsTicks` drains contact-force events
    // (`RapierPhysicsPipeline.java:175-178`); contact events are not part of
    // this milestone.
  }

  @override
  RigidBodyHandle addSubLevel(ServerSubLevel subLevel, Pose3dc pose) {
    _requireWorld();
    final existing = _subLevels[subLevel];
    if (existing != null && !existing.removed) {
      return existing;
    }
    final position = pose.position();
    final orientation = pose.orientation();
    final handle = abi.subLevelCreate(
      _world,
      subLevel.runtimeId,
      position.x,
      position.y,
      position.z,
      orientation.x,
      orientation.y,
      orientation.z,
      orientation.w,
    );
    if (handle == 0) {
      throw StateError('jolt_sublevel_create failed for ${subLevel.runtimeId}.');
    }
    final body = _SubLevelBody(this, handle, subLevel);
    _subLevels[subLevel] = body;
    subLevel.physicsBody = body;
    return body;
  }

  @override
  void removeSubLevel(ServerSubLevel subLevel) {
    final body = _subLevels.remove(subLevel);
    if (body == null || body.removed) {
      return;
    }
    body.markRemoved();
    _buoyancy.remove(body);
    if (_world != 0) {
      abi.bodyDestroy(_world, body.handle);
    }
    if (identical(subLevel.physicsBody, body)) {
      subLevel.physicsBody = null;
    }
  }

  @override
  void addContraption(KinematicContraption contraption) {
    throw UnimplementedError(
      'JoltPhysicsPipeline.addContraption: kinematic contraption bodies '
      '(`createKinematicContraption` / `addKinematicContraptionChunkSection`, '
      '`Rapier3D.java:152-672`) are driven by the Create compat layer (W6) and '
      'are not part of this milestone. The native module already exposes the '
      'body primitives they need (`jolt_body_*`).',
    );
  }

  @override
  void removeContraption(KinematicContraption contraption) {
    throw UnimplementedError(
      'JoltPhysicsPipeline.removeContraption: see addContraption.',
    );
  }

  @override
  Pose3d readPose(ServerSubLevel subLevel, Pose3d dest) {
    final body = _subLevelBody(subLevel);
    _requireWorld();
    // `Rapier3D.getPose` (`lib.rs:554-581`).
    abi.bodyGetPose(_world, body.handle, _posePtr);
    dest.position().set(
      memory.loadFloat32(_posePtr),
      memory.loadFloat32(_posePtr + 4),
      memory.loadFloat32(_posePtr + 8),
    );
    dest.orientation().set(
      memory.loadFloat32(_posePtr + 12),
      memory.loadFloat32(_posePtr + 16),
      memory.loadFloat32(_posePtr + 20),
      memory.loadFloat32(_posePtr + 24),
    );
    return dest;
  }

  @override
  JoltBoxBody addBox(BoxPhysicsObject box) {
    _requireWorld();
    final runtimeId = getNextRuntimeId();
    final position = box.pose.position();
    final orientation = box.pose.orientation();
    final handle = abi.boxCreate(
      _world,
      runtimeId,
      box.mass,
      box.halfExtents.x,
      box.halfExtents.y,
      box.halfExtents.z,
      position.x,
      position.y,
      position.z,
      orientation.x,
      orientation.y,
      orientation.z,
      orientation.w,
    );
    if (handle == 0) {
      throw StateError('jolt_box_create failed.');
    }
    return JoltBoxBody(this, handle, runtimeId);
  }

  @override
  void removeBox(BoxHandle box) {
    if (box is! JoltBoxBody || box.removed) {
      return;
    }
    box.markRemoved();
    if (_world != 0) {
      abi.bodyDestroy(_world, box.handle);
    }
  }

  @override
  RopeHandle addRope(RopePhysicsObject rope) {
    throw UnimplementedError(
      'JoltPhysicsPipeline.addRope: a Sable rope is a chain of dynamic bodies '
      'joined by a distance limit plus a velocity-damping six-DOF joint '
      '(`rope.rs:108-260`), which needs the rope tuning in `rope.rs` and the '
      'joint layer to be validated together. The native module has the joint '
      'primitives (`jolt_joint_create_sixdof`) but no rope chain yet.',
    );
  }

  @override
  void removeRope(RopeHandle rope) {
    throw UnimplementedError('JoltPhysicsPipeline.removeRope: see addRope.');
  }

  @override
  void handleChunkSectionAddition(
    int x,
    int y,
    int z,
    List<int> blockStates, {
    required bool global,
    int? subLevelRuntimeId,
  }) {
    _requireWorld();
    if (blockStates.length != 4096) {
      throw ArgumentError.value(
        blockStates.length,
        'blockStates',
        'a chunk section holds 4096 packed block states',
      );
    }
    for (var i = 0; i < 4096; i++) {
      memory.storeUint32(_chunkPtr + i * 4, blockStates[i]);
    }

    final body = global ? null : _bodyForRuntimeId(subLevelRuntimeId);
    abi.chunkAdd(
      _world,
      x,
      y,
      z,
      _chunkPtr,
      global,
      body?.handle ?? 0,
    );

    if (global) {
      levelBlocks.setSection(x, y, z, blockStates);
    } else {
      body!.blocks.setSection(x, y, z, blockStates);
    }
  }

  @override
  void handleChunkSectionRemoval(int x, int y, int z, {bool global = false}) {
    _requireWorld();
    abi.chunkRemove(_world, x, y, z, global, 0);
    if (global) {
      levelBlocks.removeSection(x, y, z);
    } else {
      for (final body in _subLevels.values) {
        body.blocks.removeSection(x, y, z);
      }
    }
  }

  @override
  void handleBlockChange(int x, int y, int z, int packedState) {
    _requireWorld();
    // `changeBlock` (`lib.rs:995-1107`) looks the block up in every sub-level
    // first and falls back to the static level.
    abi.blockChange(_world, x, y, z, packedState);
    var updated = false;
    for (final body in _subLevels.values) {
      if (body.blocks.hasSection(x >> 4, y >> 4, z >> 4)) {
        body.blocks.setBlock(x, y, z, packedState);
        updated = true;
      }
    }
    if (!updated) {
      levelBlocks.setBlock(x, y, z, packedState);
    }
  }

  @override
  void onStatsChanged(ServerSubLevel subLevel) {
    final body = _subLevelBody(subLevel);
    _requireWorld();
    final tracker = subLevel.massTracker;
    if (tracker == null || tracker.isInvalid()) {
      return;
    }
    final centerOfMass = tracker.getCenterOfMass();
    final inverseMass = tracker.getInverseMass();
    if (inverseMass <= 0.0) {
      return;
    }
    final mass = 1.0 / inverseMass;

    body.centerOfMass.setFrom(centerOfMass);
    abi.bodySetCom(_world, body.handle, centerOfMass.x, centerOfMass.y, centerOfMass.z);

    final inertia = tracker is InertiaMassData
        ? tracker.getInertiaTensor()
        : _isotropicInertia(mass);
    if (inertia.length != 9) {
      throw StateError(
        'InertiaMassData.getInertiaTensor must return 9 values '
        '(column-major), got ${inertia.length}.',
      );
    }
    for (var i = 0; i < 9; i++) {
      memory.storeFloat32(_inertiaPtr + i * 4, inertia[i]);
    }
    abi.bodySetMass(_world, body.handle, mass, _inertiaPtr);
  }

  @override
  void teleport(
    RigidBodyHandle body,
    Vector3d position,
    Quaterniond orientation,
  ) {
    _requireWorld();
    abi.bodySetPose(
      _world,
      _handleOf(body),
      position.x,
      position.y,
      position.z,
      orientation.x,
      orientation.y,
      orientation.z,
      orientation.w,
    );
  }

  @override
  void applyImpulse(RigidBodyHandle body, Vector3d position, Vector3d force) {
    _requireWorld();
    final handle = _handleOf(body);
    final centerOfMass = _centerOfMassOf(body);
    // `RapierPhysicsPipeline.applyImpulse` subtracts the center of mass before
    // calling `Rapier3D.applyForce` (`RapierPhysicsPipeline.java:450-456`).
    abi.bodyAddImpulse(
      _world,
      handle,
      position.x - centerOfMass.x,
      position.y - centerOfMass.y,
      position.z - centerOfMass.z,
      force.x,
      force.y,
      force.z,
      true,
    );
  }

  @override
  void applyLinearAndAngularImpulse(
    RigidBodyHandle body,
    Vector3d force,
    Vector3d torque,
    bool wakeUp,
  ) {
    _requireWorld();
    abi.bodyAddImpulseAndTorque(
      _world,
      _handleOf(body),
      force.x,
      force.y,
      force.z,
      torque.x,
      torque.y,
      torque.z,
      wakeUp,
    );
  }

  @override
  void addLinearAndAngularVelocity(
    RigidBodyHandle body,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
  ) {
    _requireWorld();
    abi.bodyAddVelocities(
      _world,
      _handleOf(body),
      linearVelocity.x,
      linearVelocity.y,
      linearVelocity.z,
      angularVelocity.x,
      angularVelocity.y,
      angularVelocity.z,
      true,
    );
  }

  @override
  void resetVelocity(RigidBodyHandle body) {
    final linear = getLinearVelocity(body, Vector3d());
    final angular = getAngularVelocity(body, Vector3d());
    addLinearAndAngularVelocity(body, linear.negate(), angular.negate());
  }

  @override
  Vector3d getLinearVelocity(RigidBodyHandle body, Vector3d dest) {
    _requireWorld();
    abi.bodyGetLinearVelocity(_world, _handleOf(body), _vecPtr);
    return dest.set(
      memory.loadFloat32(_vecPtr),
      memory.loadFloat32(_vecPtr + 4),
      memory.loadFloat32(_vecPtr + 8),
    );
  }

  @override
  Vector3d getAngularVelocity(RigidBodyHandle body, Vector3d dest) {
    _requireWorld();
    abi.bodyGetAngularVelocity(_world, _handleOf(body), _vecPtr);
    return dest.set(
      memory.loadFloat32(_vecPtr),
      memory.loadFloat32(_vecPtr + 4),
      memory.loadFloat32(_vecPtr + 8),
    );
  }

  @override
  void wakeUp(RigidBodyHandle body) {
    _requireWorld();
    abi.bodyWake(_world, _handleOf(body));
  }

  @override
  int getNextRuntimeId() => _nextRuntimeId++;

  // ---- Not part of `PhysicsPipeline` --------------------------------------

  /// Registers a block collider with both the Dart registry and the module
  /// (`newVoxelCollider`, `voxel_collider.rs:34-92`).
  int registerVoxelCollider(BlockColliderData data) {
    final index = colliders.add(data);
    final native = abi.voxelColliderNew(
      data.friction,
      data.volume,
      data.restitution,
      data.fluid,
    );
    if (native != index) {
      throw StateError(
        'The module reports voxel collider $native for registry index $index; '
        'the two registries are out of sync.',
      );
    }
    for (final box in data.boxes) {
      abi.voxelColliderAddBox(
        index,
        box.minX,
        box.minY,
        box.minZ,
        box.maxX,
        box.maxY,
        box.maxZ,
      );
    }
    return index;
  }

  /// The block store of one sub-level, or `null` when it has no body.
  BlockSectionStore? blocksOf(ServerSubLevel subLevel) =>
      _subLevels[subLevel]?.blocks;

  /// The handle Sable stores in `ServerSubLevel.physicsBody`, or `null`.
  RigidBodyHandle? bodyOf(ServerSubLevel subLevel) => _subLevels[subLevel];

  /// `addRotaryConstraint` (`joints.rs:304-380`): a hinge between two bodies.
  ///
  /// A `null` body attaches that side to the static world, like the Java
  /// `id == -1` (`joints.rs:311-320`).
  JoltJointHandle addHinge(
    RigidBodyHandle? bodyA,
    RigidBodyHandle? bodyB,
    Vector3d anchorA,
    Vector3d anchorB,
    Vector3d axisA,
    Vector3d axisB,
  ) {
    _requireWorld();
    final handle = abi.jointCreateHinge(
      _world,
      bodyA == null ? 0 : _handleOf(bodyA),
      bodyB == null ? 0 : _handleOf(bodyB),
      anchorA.x,
      anchorA.y,
      anchorA.z,
      anchorB.x,
      anchorB.y,
      anchorB.z,
      axisA.x,
      axisA.y,
      axisA.z,
      axisB.x,
      axisB.y,
      axisB.z,
    );
    return _joint(handle, 'hinge');
  }

  /// `addFixedConstraint` (`joints.rs:390-475`).
  JoltJointHandle addFixed(
    RigidBodyHandle? bodyA,
    RigidBodyHandle? bodyB,
    Vector3d anchorA,
    Vector3d anchorB,
    Quaterniond rotation, {
    bool contactsEnabled = false,
  }) {
    _requireWorld();
    final handle = abi.jointCreateFixed(
      _world,
      bodyA == null ? 0 : _handleOf(bodyA),
      bodyB == null ? 0 : _handleOf(bodyB),
      anchorA.x,
      anchorA.y,
      anchorA.z,
      anchorB.x,
      anchorB.y,
      anchorB.z,
      rotation.x,
      rotation.y,
      rotation.z,
      rotation.w,
    );
    final joint = _joint(handle, 'fixed');
    joint.setContactsEnabled(contactsEnabled);
    return joint;
  }

  /// `addGenericConstraint` (`joints.rs:565-720`): a six-DOF joint with a
  /// locked-axis mask (Rapier's `JointAxesMask`: bit 0 = X, 1 = Y, 2 = Z,
  /// 3 = angX, 4 = angY, 5 = angZ).
  JoltJointHandle addSixDof(
    RigidBodyHandle? bodyA,
    RigidBodyHandle? bodyB,
    Vector3d anchorA,
    Quaterniond rotationA,
    Vector3d anchorB,
    Quaterniond rotationB, {
    int lockedAxesMask = 0,
  }) {
    _requireWorld();
    final handle = abi.jointCreateSixDof(
      _world,
      bodyA == null ? 0 : _handleOf(bodyA),
      bodyB == null ? 0 : _handleOf(bodyB),
      anchorA.x,
      anchorA.y,
      anchorA.z,
      rotationA.x,
      rotationA.y,
      rotationA.z,
      rotationA.w,
      anchorB.x,
      anchorB.y,
      anchorB.z,
      rotationB.x,
      rotationB.y,
      rotationB.z,
      rotationB.w,
      lockedAxesMask,
    );
    return _joint(handle, 'six-DOF');
  }

  JoltJointHandle _joint(int handle, String kind) {
    if (handle == 0) {
      throw StateError('jolt_joint_create_$kind failed.');
    }
    return JoltJointHandle(this, handle);
  }

  /// Sets the world gravity.
  void setGravity(Vector3d gravity) {
    _requireWorld();
    abi.worldSetGravity(_world, gravity.x, gravity.y, gravity.z);
  }

  /// Sets the solver iteration counts.
  void setSolverIterations({int? velocitySteps, int? positionSteps}) {
    _requireWorld();
    abi.worldSetSolver(_world, velocitySteps ?? 0, positionSteps ?? 0);
  }

  /// `jolt_body_mass`, for diagnostics and tests.
  double massOf(RigidBodyHandle body) {
    _requireWorld();
    return abi.bodyMass(_world, _handleOf(body));
  }

  /// Whether the engine still considers [body] active.
  bool isActive(RigidBodyHandle body) {
    _requireWorld();
    return abi.bodyIsActive(_world, _handleOf(body)) != 0;
  }

  // ---- Internals ----------------------------------------------------------

  void _requireWorld() {
    if (_world == 0) {
      throw StateError('JoltPhysicsPipeline.init has not been called.');
    }
  }

  void _allocateScratch() {
    const poseBytes = 7 * 4;
    const vecBytes = 3 * 4;
    const inertiaBytes = 9 * 4;
    const chunkBytes = 4096 * 4;
    _scratch = abi.alloc(
      poseBytes + vecBytes + inertiaBytes + chunkBytes,
    );
    if (_scratch == 0) {
      throw StateError('jolt_alloc failed for the scratch buffer.');
    }
    _posePtr = _scratch;
    _vecPtr = _posePtr + poseBytes;
    _inertiaPtr = _vecPtr + vecBytes;
    _chunkPtr = _inertiaPtr + inertiaBytes;
  }

  _SubLevelBody _subLevelBody(ServerSubLevel subLevel) {
    final body = _subLevels[subLevel];
    if (body == null || body.removed) {
      throw StateError(
        'Sub-level ${subLevel.runtimeId} has no physics body; '
        'call addSubLevel first.',
      );
    }
    return body;
  }

  _SubLevelBody? _bodyForRuntimeId(int? runtimeId) {
    if (runtimeId == null) {
      return null;
    }
    for (final body in _subLevels.values) {
      if (body.subLevel.runtimeId == runtimeId && !body.removed) {
        return body;
      }
    }
    return null;
  }

  int _handleOf(RigidBodyHandle body) {
    if (body is _SubLevelBody) {
      if (body.removed) {
        throw StateError('Sub-level body ${body.runtimeId} was removed.');
      }
      return body.handle;
    }
    if (body is JoltBoxBody) {
      if (body.removed) {
        throw StateError('Box body ${body.runtimeId} was removed.');
      }
      return body.handle;
    }
    throw ArgumentError.value(
      body,
      'body',
      'not a body of this JoltPhysicsPipeline',
    );
  }

  Vector3d _centerOfMassOf(RigidBodyHandle body) {
    if (body is _SubLevelBody) {
      return body.centerOfMass;
    }
    return Vector3d();
  }

  List<BuoyancyForce> _computeBuoyancy(_SubLevelBody body) {
    final tracker = body.subLevel.massTracker;
    final bounds = tracker?.getBounds();
    if (tracker == null || bounds == null) {
      return const [];
    }
    final pose = Pose3d();
    readPose(body.subLevel, pose);
    return computeBuoyancy(
      pose: pose,
      centerOfMass: body.centerOfMass,
      localBounds: bounds,
      bodyBlocks: body.blocks.solidBlocks(colliders),
      colliders: colliders,
      world: StoreBlockSource(levelBlocks),
      velocityAt: (point) {
        abi.bodyVelocityAtPoint(
          _world,
          body.handle,
          point.x,
          point.y,
          point.z,
          _vecPtr,
        );
        return Vector3d(
          memory.loadFloat32(_vecPtr),
          memory.loadFloat32(_vecPtr + 4),
          memory.loadFloat32(_vecPtr + 8),
        );
      },
    );
  }

  /// The fallback inertia of a body whose tracker does not report a tensor: a
  /// solid sphere of the same mass, `I = 0.4 m r^2` with `r = 1`
  /// (`massPropertiesOf` in `native/jolt/src/joltabi.cpp`).
  static List<double> _isotropicInertia(double mass) {
    final i = 0.4 * mass;
    return [i, 0.0, 0.0, 0.0, i, 0.0, 0.0, 0.0, i];
  }
}

/// A constraint handle (`PhysicsConstraintHandle` in Java,
/// `sable_rapier/.../Rapier3D.java:152-672`).
final class JoltJointHandle {
  final JoltPhysicsPipeline _pipeline;
  final int handle;

  JoltJointHandle(this._pipeline, this.handle);

  /// The native joint handle.
  int get nativeHandle => handle;

  /// Whether the engine still holds the joint.
  bool get isValid {
    if (_pipeline._world == 0) {
      return false;
    }
    return _pipeline.abi.jointIsValid(_pipeline._world, handle) != 0;
  }

  /// `setConstraintFrame` (`joints.rs:640-700`); [side] 0 is body A, 1 body B.
  void setFrame(int side, Vector3d position, Quaterniond rotation) {
    _pipeline._requireWorld();
    _pipeline.abi.jointSetFrame(
      _pipeline._world,
      handle,
      side,
      position.x,
      position.y,
      position.z,
      rotation.x,
      rotation.y,
      rotation.z,
      rotation.w,
    );
  }

  /// The hinge axis of one side.
  void setAxis(int side, Vector3d axis) {
    _pipeline._requireWorld();
    _pipeline.abi.jointSetAxis(
      _pipeline._world,
      handle,
      side,
      axis.x,
      axis.y,
      axis.z,
    );
  }

  /// `setConstraintMotor` (`joints.rs:114-160`): axis 0-2 linear, 3-5 angular.
  void setMotor(
    int axis,
    double target,
    double stiffness,
    double damping, {
    double? maxForce,
  }) {
    _pipeline._requireWorld();
    _pipeline.abi.jointSetMotor(
      _pipeline._world,
      handle,
      axis,
      target,
      stiffness,
      damping,
      maxForce != null,
      maxForce ?? 0.0,
    );
  }

  /// `setConstraintLimit` (`joints.rs:163-205`).
  void setLimit(int axis, double min, double max) {
    _pipeline._requireWorld();
    _pipeline.abi.jointSetLimit(_pipeline._world, handle, axis, min, max);
  }

  /// `lockConstraintAxes` (`joints.rs:208-240`).
  void lockAxes(int mask) {
    _pipeline._requireWorld();
    _pipeline.abi.jointLockAxes(_pipeline._world, handle, mask);
  }

  /// `setConstraintContactsEnabled` (`joints.rs:274-300`).
  void setContactsEnabled(bool enabled) {
    _pipeline._requireWorld();
    _pipeline.abi.jointSetContactsEnabled(_pipeline._world, handle, enabled);
  }

  /// `getConstraintImpulses` (`joints.rs:238-272`): six values, linear then
  /// angular.
  List<double> impulses() {
    _pipeline._requireWorld();
    final pointer = _pipeline._vecPtr;
    _pipeline.abi.jointGetImpulses(_pipeline._world, handle, pointer);
    return [
      for (var i = 0; i < 6; i++)
        _pipeline.memory.loadFloat32(pointer + i * 4),
    ];
  }

  /// `removeConstraint` (`joints.rs:302-320`).
  void destroy() {
    if (_pipeline._world == 0) {
      return;
    }
    _pipeline.abi.jointDestroy(_pipeline._world, handle);
  }
}

/// A sub-level's body.
final class _SubLevelBody implements RigidBodyHandle {
  final JoltPhysicsPipeline _pipeline;
  final int handle;
  final ServerSubLevel subLevel;

  /// The tracked center of mass, in plot coordinates.
  final Vector3d centerOfMass = Vector3d();

  /// The blocks of this sub-level's plot sections.
  final BlockSectionStore blocks = BlockSectionStore();

  bool removed = false;

  Vector3d? _lastForce;

  _SubLevelBody(this._pipeline, this.handle, this.subLevel);

  int get runtimeId => subLevel.runtimeId;

  void markRemoved() => removed = true;

  @override
  Vector3d getLinearVelocity([Vector3d? dest]) =>
      _pipeline.getLinearVelocity(this, dest ?? Vector3d());

  @override
  Vector3d getAngularVelocity([Vector3d? dest]) =>
      _pipeline.getAngularVelocity(this, dest ?? Vector3d());

  @override
  void applyLinearAndAngularImpulse(
    Vector3d linear,
    Vector3d angular,
    bool wakeUp,
  ) {
    _pipeline.applyLinearAndAngularImpulse(this, linear, angular, wakeUp);
  }

  /// `RigidBodyHandle.applyForcesAndReset` sends a local force as an impulse
  /// and only wakes the body when the force changed
  /// (`ForceTotal.applyForces`, `ForceTotal.java:29-43`).
  @override
  void applyForcesAndReset(Vector3d force) {
    final previous = _lastForce;
    final changed =
        previous == null ||
        (force.x - previous.x) * (force.x - previous.x) +
                (force.y - previous.y) * (force.y - previous.y) +
                (force.z - previous.z) * (force.z - previous.z) >
            1e-5;
    _lastForce ??= Vector3d();
    _lastForce!.setFrom(force);
    _pipeline.applyLinearAndAngularImpulse(
      this,
      force,
      Vector3d(),
      changed,
    );
  }

  @override
  void teleport(Vector3d position, Quaterniond orientation) {
    _pipeline.teleport(this, position, orientation);
    subLevel.pose.position().setFrom(position);
    subLevel.pose.orientation().setFrom(orientation);
  }

  @override
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular) {
    _pipeline.addLinearAndAngularVelocity(this, linear, angular);
  }
}

/// A box's body (`BoxPhysicsObject`, `boxes.rs:28-70`).
///
/// A box is a rigid body like a sub-level, so it is also a [RigidBodyHandle]
/// (constraints and impulses treat both the same way in Java, where
/// `BoxPhysicsObject implements PhysicsPipelineBody`).
final class JoltBoxBody implements BoxHandle, RigidBodyHandle {
  final JoltPhysicsPipeline _pipeline;
  final int handle;
  final int runtimeId;

  bool removed = false;

  JoltBoxBody(this._pipeline, this.handle, this.runtimeId);

  void markRemoved() => removed = true;

  @override
  void readPose(Pose3d dest) {
    _pipeline._requireWorld();
    _pipeline.abi.bodyGetPose(_pipeline._world, handle, _pipeline._posePtr);
    final memory = _pipeline.memory;
    final ptr = _pipeline._posePtr;
    dest.position().set(
      memory.loadFloat32(ptr),
      memory.loadFloat32(ptr + 4),
      memory.loadFloat32(ptr + 8),
    );
    dest.orientation().set(
      memory.loadFloat32(ptr + 12),
      memory.loadFloat32(ptr + 16),
      memory.loadFloat32(ptr + 20),
      memory.loadFloat32(ptr + 24),
    );
  }

  @override
  Vector3d getLinearVelocity([Vector3d? dest]) =>
      _pipeline.getLinearVelocity(this, dest ?? Vector3d());

  @override
  Vector3d getAngularVelocity([Vector3d? dest]) =>
      _pipeline.getAngularVelocity(this, dest ?? Vector3d());

  @override
  void applyLinearAndAngularImpulse(
    Vector3d linear,
    Vector3d angular,
    bool wakeUp,
  ) {
    _pipeline.applyLinearAndAngularImpulse(this, linear, angular, wakeUp);
  }

  @override
  void applyForcesAndReset(Vector3d force) {
    _pipeline.applyLinearAndAngularImpulse(this, force, Vector3d(), true);
  }

  @override
  void teleport(Vector3d position, Quaterniond orientation) {
    _pipeline.teleport(this, position, orientation);
  }

  @override
  void addLinearAndAngularVelocity(Vector3d linear, Vector3d angular) {
    _pipeline.addLinearAndAngularVelocity(this, linear, angular);
  }

  @override
  void remove() => _pipeline.removeBox(this);

  @override
  void wakeUp() {
    _pipeline._requireWorld();
    _pipeline.abi.bodyWake(_pipeline._world, handle);
  }

  @override
  int getRuntimeId() => runtimeId;
}
