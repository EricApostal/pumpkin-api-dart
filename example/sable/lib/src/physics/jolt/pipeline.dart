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
import 'dart:math' as math;

import '../../../sable.dart'
    show
        BoxHandle,
        BoxPhysicsObject,
        ConstraintJointAxis,
        ConstraintJointAxisMask,
        ConstraintPipeline,
        FeatureAwarePhysicsPipeline,
        FixedConstraintConfiguration,
        ForceTotal,
        FreeConstraintConfiguration,
        GenericConstraintConfiguration,
        GenericConstraintHandle,
        KinematicContraption,
        LevelPlot,
        Matrix3d,
        PhysicsConstraintConfiguration,
        PhysicsConstraintHandle,
        PhysicsPipeline,
        PhysicsPipelineFeature,
        Pose3d,
        Pose3dc,
        Quaterniond,
        RigidBodyHandle,
        RotaryConstraintConfiguration,
        RopeHandle,
        RopePhysicsObject,
        ServerSubLevel,
        SubLevelContainer,
        UnsupportedPhysicsFeatureException,
        Vector3d;

import '../buoyancy.dart';
import 'abi.dart';
import 'voxel.dart';

/// The Jolt-backed physics pipeline.
///
/// Its capabilities are declared through [FeatureAwarePhysicsPipeline]: this
/// module has no kinematic-body factory and no rope chain, so both
/// [PhysicsPipelineFeature.contraption] and [PhysicsPipelineFeature.rope] are
/// unsupported, which keeps Sable's call sites
/// (`compat/create/contraption_physics.dart`,
/// `command/sable_spawn_commands.dart`) from reaching the throwing methods
/// below.
final class JoltPhysicsPipeline
    implements PhysicsPipeline, ConstraintPipeline, FeatureAwarePhysicsPipeline {
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
  int _impulsePtr = 0;
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
    // `RapierPhysicsPipeline.postPhysicsTicks` finalizes the tick by draining
    // the engine's contact-force events into `processCollisionEffects`
    // (`RapierPhysicsPipeline.java:171-178`), which drives collision sounds,
    // particles and fragile-block breaking through
    // `BlockSubLevelCollisionCallback` (`RapierPhysicsPipeline.java:
    // processCollisionEffects`). That is not implementable from here: the
    // module's `ContactListenerImpl` only adjusts friction and restitution per
    // manifold (`jolt_abi.cpp:244-296`) and the C ABI has no export to record or
    // drain contacts (`jolt_joint_set_contacts_enabled` is the only
    // contact-related entry point). It needs a new native listener plus a drain
    // export before the Dart callback layer can consume anything, so this stays
    // an empty finalisation rather than a fake.
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
    throw UnsupportedPhysicsFeatureException(
      PhysicsPipelineFeature.contraption,
      'a kinematic body factory: `native/jolt/src/jolt_abi.cpp` only creates '
          'static and dynamic bodies (`EMotionType::Static`/`Dynamic`), so a '
          'contraption cannot be driven by a kinematic body plus its chunk '
          'sections (`RapierPhysicsPipeline.createKinematicContraption`, '
          '`RapierPhysicsPipeline.java:225-299`)',
    );
  }

  @override
  void removeContraption(KinematicContraption contraption) {
    throw UnsupportedPhysicsFeatureException(
      PhysicsPipelineFeature.contraption,
      'a kinematic body factory (see addContraption)',
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
    return JoltBoxBody(this, handle, runtimeId, box.mass, box.halfExtents);
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
    throw UnsupportedPhysicsFeatureException(
      PhysicsPipelineFeature.rope,
      'a rope chain: a Sable rope is a chain of dynamic bodies joined by a '
          'distance limit plus a velocity-damping six-DOF joint '
          '(`rope.rs:108-260`), and the checked-in module only exposes the bare '
          'joint primitives (`jolt_joint_create_sixdof`), not the rope tuning '
          'the Rust original carries',
    );
  }

  @override
  void removeRope(RopeHandle rope) {
    throw UnsupportedPhysicsFeatureException(
      PhysicsPipelineFeature.rope,
      'a rope chain (see addRope)',
    );
  }

  /// Neither contraptions nor ropes are implemented: [supportsFeature] answers
  /// `false` for every [PhysicsPipelineFeature] of this module.
  ///
  /// Sable's call sites consult this before calling, so the four throwing
  /// methods above are unreachable in normal operation and the failure mode is
  /// a reported capability gap instead of an exception inside a tick.
  @override
  bool supportsFeature(PhysicsPipelineFeature feature) => false;

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

    // The owner is decided here, not by the caller:
    // `RapierPhysicsPipeline.handleChunkSectionAddition` looks the plot up at
    // the chunk position and uploads to that sub-level's body when the plot has
    // one (`RapierPhysicsPipeline.java:358-365`), and Sable's physics system
    // cannot make that decision for the engine
    // (`physics_system.dart:419` always passes `global: false` and no runtime
    // id). An explicit `subLevelRuntimeId` is honoured first — that is Java's
    // `uploadDataIfGlobal` path — and a section that no plot covers is static
    // level geometry.
    final explicit = global ? null : _bodyForRuntimeId(subLevelRuntimeId);
    final plot = (global || explicit != null) ? null : _plotAt(x, z);
    final body = explicit ?? (plot == null ? null : _subLevels[plot.getSubLevel()]);
    final toGlobal = global || (explicit == null && plot == null);

    abi.chunkAdd(_world, x, y, z, _chunkPtr, toGlobal, body?.handle ?? 0);

    if (toGlobal) {
      levelBlocks.setSection(x, y, z, blockStates);
    } else if (body != null) {
      body.blocks.setSection(x, y, z, blockStates);
    }
    // A section of a plot whose sub-level has no body yet is not uploaded:
    // `chunkAdd` with body 0 is a native no-op, which is what Java's `id = -1`
    // does (`RapierPhysicsPipeline.java:363`), and recording it in
    // [levelBlocks] would claim static geometry the module never got.
  }

  @override
  void handleChunkSectionRemoval(int x, int y, int z, {bool global = false}) {
    _requireWorld();
    // `RapierPhysicsPipeline.handleChunkSectionRemoval` removes a section as
    // static level geometry exactly when it is outside the plot grid
    // (`RapierPhysicsPipeline.java:371-373`: `!container.inBounds(x, z)`); a
    // section inside the grid is removed from whichever body recorded it. The
    // old code trusted the caller's `global: false` and never removed a static
    // section's colliders, and `jolt_chunk_remove` with body 0 is a no-op
    // (`jolt_abi.cpp:1399-1410`).
    final container = _container;
    if (global || container == null || !container.inBounds(x, z)) {
      abi.chunkRemove(_world, x, y, z, true, 0);
      levelBlocks.removeSection(x, y, z);
      return;
    }
    for (final body in _subLevels.values) {
      if (body.removed || !body.blocks.hasSection(x, y, z)) {
        continue;
      }
      abi.chunkRemove(_world, x, y, z, false, body.handle);
      body.blocks.removeSection(x, y, z);
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
    final mass = tracker.getMass();

    body.centerOfMass.setFrom(centerOfMass);
    body.mass = mass;
    abi.bodySetCom(_world, body.handle, centerOfMass.x, centerOfMass.y, centerOfMass.z);

    // Jolt stores the inertia tensor column-major
    // (`massPropertiesOf`, `native/jolt/src/jolt_abi.cpp:369-388`).
    final inertia = tracker.getInertiaTensor();
    body.inertiaTensor.setFrom(inertia);
    memory
      ..storeFloat32(_inertiaPtr, inertia.m00)
      ..storeFloat32(_inertiaPtr + 4, inertia.m10)
      ..storeFloat32(_inertiaPtr + 8, inertia.m20)
      ..storeFloat32(_inertiaPtr + 12, inertia.m01)
      ..storeFloat32(_inertiaPtr + 16, inertia.m11)
      ..storeFloat32(_inertiaPtr + 20, inertia.m21)
      ..storeFloat32(_inertiaPtr + 24, inertia.m02)
      ..storeFloat32(_inertiaPtr + 28, inertia.m12)
      ..storeFloat32(_inertiaPtr + 32, inertia.m22);
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
    return _joint(handle, 'hinge', bodyA, bodyB, hingeAxis: Vector3d.copy(axisA));
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
    final joint = _joint(handle, 'fixed', bodyA, bodyB);
    joint.setContactsEnabled(contactsEnabled);
    return joint;
  }

  /// `addGenericConstraint` (`joints.rs:565-720`): a six-DOF joint with a
  /// locked-axis mask (Rapier's `JointAxesMask`, i.e. the
  /// [ConstraintJointAxisMask] bits: bit 0 = X, 1 = Y, 2 = Z,
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
    return _joint(handle, 'six-DOF', bodyA, bodyB, generic: true);
  }

  JoltJointHandle _joint(
    int handle,
    String kind,
    RigidBodyHandle? bodyA,
    RigidBodyHandle? bodyB, {
    bool generic = false,
    Vector3d? hingeAxis,
  }) {
    if (handle == 0) {
      throw StateError('jolt_joint_create_$kind failed.');
    }
    return generic
        ? JoltGenericJointHandle(this, handle, kind, bodyA, bodyB, hingeAxis)
        : JoltJointHandle(this, handle, kind, bodyA, bodyB, hingeAxis);
  }

  /// `addConstraint(bodyA, bodyB, configuration)`
  /// (`RapierPhysicsPipeline.java:523-554`).
  ///
  /// A `null` body attaches that side to the static world. Java also validates
  /// the anchors against the sub-level containers; the pipeline has no
  /// container reference, so that check belongs to the caller
  /// (`PhysicsConstraintConfiguration.validate`).
  @override
  PhysicsConstraintHandle addConstraint(
    Object? a,
    Object? b,
    PhysicsConstraintConfiguration configuration,
  ) {
    _requireWorld();
    if (a == null && b == null) {
      throw ArgumentError(
        'Cannot add a constraint between the static world and static world.',
      );
    }
    if (a != null && identical(a, b)) {
      throw ArgumentError('Cannot add a constraint between a body and itself.');
    }

    final bodyA = _constraintBody(a);
    final bodyB = _constraintBody(b);

    return switch (configuration) {
      RotaryConstraintConfiguration config => addHinge(
        bodyA,
        bodyB,
        config.pos1,
        config.pos2,
        config.axis1,
        config.axis2,
      ),
      FixedConstraintConfiguration config => addFixed(
        bodyA,
        bodyB,
        config.pos1,
        config.pos2,
        config.quatB,
      ),
      // Rapier's free joint is a six-DOF joint with no locked axis
      // (`RapierFreeConstraintHandle.java:18-33`).
      FreeConstraintConfiguration config => addSixDof(
        bodyA,
        bodyB,
        config.pos1,
        Quaterniond(),
        config.pos2,
        config.quatB,
      ),
      GenericConstraintConfiguration config => addSixDof(
        bodyA,
        bodyB,
        config.pos1,
        config.quatA,
        config.pos2,
        config.quatB,
        lockedAxesMask: config.lockedAxesMask,
      ),
    };
  }

  RigidBodyHandle? _constraintBody(Object? body) {
    if (body == null) return null;
    if (body is! RigidBodyHandle) {
      throw ArgumentError.value(
        body,
        'body',
        'not a rigid body of this JoltPhysicsPipeline',
      );
    }
    return body;
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
    const impulseBytes = 6 * 4;
    const chunkBytes = 4096 * 4;
    _scratch = abi.alloc(
      poseBytes + vecBytes + inertiaBytes + impulseBytes + chunkBytes,
    );
    if (_scratch == 0) {
      throw StateError('jolt_alloc failed for the scratch buffer.');
    }
    _posePtr = _scratch;
    _vecPtr = _posePtr + poseBytes;
    _inertiaPtr = _vecPtr + vecBytes;
    _impulsePtr = _inertiaPtr + inertiaBytes;
    _chunkPtr = _impulsePtr + impulseBytes;
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

  /// The plot grid the pipeline's sub-levels are allocated in, or `null` when
  /// none is registered.
  ///
  /// The pipeline has no level of its own and must stay free of host imports,
  /// so the container comes from a registered body's plot; every registered
  /// sub-level is allocated from the same container
  /// (`RapierPhysicsPipeline` reads it from the level instead,
  /// `RapierPhysicsPipeline.java:359`).
  SubLevelContainer? get _container {
    for (final body in _subLevels.values) {
      return body.subLevel.getPlot().container;
    }
    return null;
  }

  /// The plot that owns the chunk section `(x, z)`, or `null` when the section
  /// is not inside a sub-level's plot (`SubLevelContainer.getPlot`, the lookup
  /// `RapierPhysicsPipeline.java:359` does).
  LevelPlot? _plotAt(int x, int z) => _container?.getPlot(x, z);

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

  /// The mass of [body] [kg], or 0 for the static world.
  double _massOfBody(RigidBodyHandle? body) {
    if (body is _SubLevelBody) return body.mass;
    if (body is JoltBoxBody) return body.mass;
    return 0.0;
  }

  /// The inertia tensor of [body] in its local frame, or `null` when unknown.
  Matrix3d? _inertiaOfBody(RigidBodyHandle? body) {
    if (body is _SubLevelBody) return body.inertiaTensor;
    if (body is JoltBoxBody) return body.inertiaTensor;
    return null;
  }

  /// The reduced mass of a linear axis: the static world is infinitely massive,
  /// so a joint to it uses the other body's mass.
  double reducedMass(RigidBodyHandle? a, RigidBodyHandle? b) {
    final massA = _massOfBody(a);
    final massB = _massOfBody(b);
    if (massA <= 0.0) return massB;
    if (massB <= 0.0) return massA;
    return massA * massB / (massA + massB);
  }

  /// The reduced inertia about world axis [axisIndex] (0 = x, 1 = y, 2 = z).
  ///
  /// `nᵀ·I·n` with the local tensor rotated by the body's orientation, then the
  /// two bodies' inverse inertias add like the reduced mass does.
  double reducedInertia(RigidBodyHandle? a, RigidBodyHandle? b, int axisIndex) {
    final inertiaA = _effectiveInertia(a, axisIndex);
    final inertiaB = _effectiveInertia(b, axisIndex);
    if (inertiaA <= 0.0) return inertiaB;
    if (inertiaB <= 0.0) return inertiaA;
    return inertiaA * inertiaB / (inertiaA + inertiaB);
  }

  /// The reduced inertia about [axis], given in the bodies' local frame.
  ///
  /// A Jolt hinge stores its hinge axis in the body's local frame
  /// (`jolt_abi.cpp:599-605`), so the hinge motor's gain conversion uses this
  /// form rather than a world axis.
  double reducedInertiaAbout(RigidBodyHandle? a, RigidBodyHandle? b, Vector3d axis) {
    final inertiaA = _localInertia(a, axis);
    final inertiaB = _localInertia(b, axis);
    if (inertiaA <= 0.0) return inertiaB;
    if (inertiaB <= 0.0) return inertiaA;
    return inertiaA * inertiaB / (inertiaA + inertiaB);
  }

  double _localInertia(RigidBodyHandle? body, Vector3d axis) {
    final local = _inertiaOfBody(body);
    if (body == null || local == null) return 0.0;
    final n = Vector3d.copy(axis);
    final length = n.length;
    if (!(length > 0.0)) return 0.0;
    n.mul(1.0 / length);
    final inertia = Matrix3d.copy(local).transform(n, Vector3d());
    return n.dot(inertia);
  }

  double _effectiveInertia(RigidBodyHandle? body, int axisIndex) {
    final local = _inertiaOfBody(body);
    if (body == null || local == null) return 0.0;

    // The axis in the body's local frame: `q⁻¹ · e`.
    abi.bodyGetPose(_world, _handleOf(body), _posePtr);
    final orientation = Quaterniond(
      memory.loadFloat32(_posePtr + 12),
      memory.loadFloat32(_posePtr + 16),
      memory.loadFloat32(_posePtr + 20),
      memory.loadFloat32(_posePtr + 24),
    ).conjugate();
    final worldAxis = switch (axisIndex) {
      0 => Vector3d(1.0, 0.0, 0.0),
      1 => Vector3d(0.0, 1.0, 0.0),
      _ => Vector3d(0.0, 0.0, 1.0),
    };
    final localAxis = orientation.transform(worldAxis, Vector3d());
    final inertia = Matrix3d.copy(local).transform(localAxis, Vector3d());
    return localAxis.x * inertia.x + localAxis.y * inertia.y + localAxis.z * inertia.z;
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
}

/// A constraint handle (`PhysicsConstraintHandle` in Java,
/// `sable_rapier/.../Rapier3D.java:152-672`).
///
/// The Jolt ABI has one joint type per shape (`jolt_joint_create_hinge`,
/// `_fixed`, `_sixdof`) but one set of mutators for all of them, so this single
/// class carries the whole Java interface; [JoltGenericJointHandle] adds the
/// `GenericConstraintHandle` view for six-DOF joints.
class JoltJointHandle implements PhysicsConstraintHandle {
  final JoltPhysicsPipeline _pipeline;
  final int handle;

  /// The bodies the joint connects; `null` is the static world.
  final RigidBodyHandle? bodyA;
  final RigidBodyHandle? bodyB;

  /// The joint shape: `hinge`, `fixed` or `six-DOF`.
  final String kind;

  /// The hinge direction on body A for a hinge, `null` otherwise. The native
  /// side stores it in the constraint's local frame
  /// (`jolt_abi.cpp:599-605`).
  final Vector3d? hingeAxis;

  JoltJointHandle(
    this._pipeline,
    this.handle,
    this.kind, [
    this.bodyA,
    this.bodyB,
    this.hingeAxis,
  ]);

  /// The native joint handle.
  int get nativeHandle => handle;

  /// `isValid()`: whether the engine still holds the joint.
  @override
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

  /// `setFrame1(localPosition, localOrientation)` (`GenericConstraintHandle`).
  void setFrame1(Vector3d localPosition, Quaterniond localOrientation) =>
      setFrame(0, localPosition, localOrientation);

  /// `setFrame2(localPosition, localOrientation)` (`GenericConstraintHandle`).
  void setFrame2(Vector3d localPosition, Quaterniond localOrientation) =>
      setFrame(1, localPosition, localOrientation);

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

  /// `setMotor(axis, target, stiffness, damping, hasMaxForce, maxForce)`
  /// (`RapierConstraintHandle.java:30-33`): a PD motor on [axis], where 0-2 are
  /// linear and 3-5 angular ([ConstraintJointAxis]), as Java passes
  /// `axis.ordinal()`.
  ///
  /// A Rapier revolute joint is driven on `ANGULAR_X`
  /// (`RotaryConstraintHandle.DEFAULT_AXIS`); Jolt's [HingeConstraint] has a
  /// single motor slot that `jolt_joint_set_motor` addresses as axis 5
  /// (`jolt_abi.cpp:1625-1640`), so an angular X motor on a hinge is routed
  /// there. Every other axis of a hinge is fixed by the constraint and has no
  /// motor.
  ///
  /// Rapier takes a spring constant `k` [N/m | Nm/rad] and a damping
  /// coefficient `c` [N·s/m | Nm·s/rad]; Jolt's spring settings take a
  /// frequency [Hz] and a damping *ratio* (`ESpringMode::FrequencyAndDamping`,
  /// `jolt_abi.cpp:569-575`). The gains are converted through the joint's
  /// effective mass for the axis, `ω = √(k/m)`, `f = ω/2π`,
  /// `ζ = c / (2√(km))`, so a Java gain behaves the same here.
  @override
  void setMotor(
    int axis,
    double target,
    double stiffness,
    double damping,
    bool hasMaxForce,
    double maxForce,
  ) {
    _pipeline._requireWorld();
    final abiAxis = _abiAxis(axis);
    if (abiAxis < 0) {
      return;
    }
    final (frequency, ratio) = _springTerms(axis, stiffness, damping);
    _pipeline.abi.jointSetMotor(
      _pipeline._world,
      handle,
      abiAxis,
      target,
      frequency,
      ratio,
      hasMaxForce,
      maxForce,
    );
    // `jolt_joint_set_motor` updates the constraint but does not activate the
    // bodies (`jolt_abi.cpp:1602-1640`), so a sleeping sub-level would ignore
    // its motor. Applying a motor is an external change that must resume
    // physics, as `RigidBodyHandle.applyForces` does for forces.
    final a = bodyA;
    if (a != null) {
      _pipeline.wakeUp(a);
    }
    final b = bodyB;
    if (b != null) {
      _pipeline.wakeUp(b);
    }
  }

  /// The ABI axis for a Sable [axis], or -1 when the joint has no motor there.
  int _abiAxis(int axis) {
    if (kind != 'hinge') {
      return axis >= 0 && axis <= 5 ? axis : -1;
    }
    // The hinge's own motor slot, plus the Sable name for it.
    return axis == ConstraintJointAxis.angularX || axis == ConstraintJointAxis.angularZ
        ? ConstraintJointAxis.angularZ
        : -1;
  }

  /// Converts Rapier's `(stiffness, damping)` into Jolt's
  /// `(frequency, damping ratio)`.
  (double, double) _springTerms(int axis, double stiffness, double damping) {
    if (stiffness <= 0.0) {
      // No spring: the ABI substitutes its 550 Hz default for a non-positive
      // frequency (`springOf`, `jolt_abi.cpp:569-575`), so a zero gain has to
      // stay tiny rather than zero.
      return (1.0e-4, 0.0);
    }

    final double effective;
    if (kind == 'hinge') {
      // The hinge's rotation axis, as the native constraint stores it.
      effective = _pipeline.reducedInertiaAbout(bodyA, bodyB, hingeAxis ?? Vector3d(0, 1, 0));
    } else if (axis < 3) {
      effective = _pipeline.reducedMass(bodyA, bodyB);
    } else {
      effective = _pipeline.reducedInertia(bodyA, bodyB, axis - 3);
    }
    if (!(effective > 0.0) || !effective.isFinite) {
      // A static/static joint or a body without mass data: the ABI's own units
      // are the best available answer.
      return (stiffness, damping);
    }

    final frequency = math.sqrt(stiffness / effective) / (2 * math.pi);
    final ratio = damping / (2 * math.sqrt(stiffness * effective));
    return (frequency, ratio);
  }

  /// `setLimit(axis, min, max)` (`joints.rs:163-205`).
  void setLimit(int axis, double min, double max) {
    _pipeline._requireWorld();
    _pipeline.abi.jointSetLimit(_pipeline._world, handle, axis, min, max);
  }

  /// `lockAxes(axes)` (`joints.rs:208-240`): a mask of
  /// [ConstraintJointAxisMask] bits.
  void lockAxes(int mask) {
    _pipeline._requireWorld();
    _pipeline.abi.jointLockAxes(_pipeline._world, handle, mask);
  }

  /// `setContactsEnabled(enabled)` (`joints.rs:274-300`).
  @override
  void setContactsEnabled(bool enabled) {
    _pipeline._requireWorld();
    _pipeline.abi.jointSetContactsEnabled(_pipeline._world, handle, enabled);
  }

  /// `getJointImpulses(linearImpulseDest, angularImpulseDest)`
  /// (`joints.rs:238-272`): the solver's total lambda, linear then angular.
  @override
  void getJointImpulses(Vector3d linearImpulseDest, Vector3d angularImpulseDest) {
    _pipeline._requireWorld();
    final pointer = _pipeline._impulsePtr;
    _pipeline.abi.jointGetImpulses(_pipeline._world, handle, pointer);
    final memory = _pipeline.memory;
    linearImpulseDest.set(
      memory.loadFloat32(pointer),
      memory.loadFloat32(pointer + 4),
      memory.loadFloat32(pointer + 8),
    );
    angularImpulseDest.set(
      memory.loadFloat32(pointer + 12),
      memory.loadFloat32(pointer + 16),
      memory.loadFloat32(pointer + 20),
    );
  }

  /// `remove()` (`joints.rs:302-320`).
  @override
  void remove() {
    if (_pipeline._world == 0) {
      return;
    }
    _pipeline.abi.jointDestroy(_pipeline._world, handle);
  }
}

/// `GenericConstraintHandle`: the six-DOF view of a [JoltJointHandle].
final class JoltGenericJointHandle extends JoltJointHandle implements GenericConstraintHandle {
  JoltGenericJointHandle(
    super.pipeline,
    super.handle,
    super.kind, [
    super.bodyA,
    super.bodyB,
    super.hingeAxis,
  ]);
}

/// A sub-level's body.
final class _SubLevelBody implements RigidBodyHandle {
  final JoltPhysicsPipeline _pipeline;
  final int handle;
  final ServerSubLevel subLevel;

  /// The tracked center of mass, in plot coordinates.
  final Vector3d centerOfMass = Vector3d();

  /// The mass uploaded by [JoltPhysicsPipeline.onStatsChanged] [kg].
  double mass = 0.0;

  /// The inertia tensor uploaded by [JoltPhysicsPipeline.onStatsChanged], in
  /// the body's local frame [kg·m²].
  final Matrix3d inertiaTensor = Matrix3d.identity();

  /// The blocks of this sub-level's plot sections.
  final BlockSectionStore blocks = BlockSectionStore();

  bool removed = false;

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

  /// `RigidBodyHandle.applyForcesAndReset` sends the accumulated local force
  /// and torque as one impulse, waking the body only when the total changed
  /// (`ForceTotal.applyForces`, `ForceTotal.java:29-43`).
  @override
  void applyForcesAndReset(ForceTotal forceTotal) => forceTotal.applyForces(this);

  /// `applyImpulseAtPoint(position, force)` (`RigidBodyHandle.java:80-88`).
  @override
  void applyImpulseAtPoint(Vector3d position, Vector3d force) =>
      _pipeline.applyImpulse(this, position, force);

  /// `isValid()`: whether the engine still holds the body.
  @override
  bool get isValid =>
      !removed &&
      _pipeline._world != 0 &&
      _pipeline.abi.bodyIsValid(_pipeline._world, handle) != 0;

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

  /// The box's mass [kg] (`BoxPhysicsObject.getMass()`).
  final double mass;

  /// The inertia tensor of a solid cuboid about its centre
  /// `m/3·(hᵢ² + hⱼ²)` on the diagonal [kg·m²].
  final Matrix3d inertiaTensor;

  bool removed = false;

  JoltBoxBody(this._pipeline, this.handle, this.runtimeId, this.mass, Vector3d halfExtents)
    : inertiaTensor = Matrix3d(
        mass / 3.0 * (halfExtents.y * halfExtents.y + halfExtents.z * halfExtents.z),
        0.0,
        0.0,
        0.0,
        mass / 3.0 * (halfExtents.x * halfExtents.x + halfExtents.z * halfExtents.z),
        0.0,
        0.0,
        0.0,
        mass / 3.0 * (halfExtents.x * halfExtents.x + halfExtents.y * halfExtents.y),
      );

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
  void applyForcesAndReset(ForceTotal forceTotal) => forceTotal.applyForces(this);

  @override
  void applyImpulseAtPoint(Vector3d position, Vector3d force) =>
      _pipeline.applyImpulse(this, position, force);

  @override
  bool get isValid =>
      !removed &&
      _pipeline._world != 0 &&
      _pipeline.abi.bodyIsValid(_pipeline._world, handle) != 0;

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
