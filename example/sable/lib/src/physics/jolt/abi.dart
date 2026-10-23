// The C ABI of the Jolt core module (`native/jolt/src/jolt_abi.cpp`), split
// from its wasm binding so the pipeline can be exercised from the Dart VM.
//
// Every method maps one-to-one onto an exported function of the module; the
// numbers are plain Dart values (`int` for `u32`/`i32`, `double` for
// `float`/`double`) and pointers are byte offsets into the module's own linear
// memory, which is why the memory is a separate interface.
//
// Pure: no host imports, so `package:test` can implement both interfaces.
// ignore_for_file: avoid_positional_boolean_parameters

/// The exported functions of the Jolt module.
abstract interface class JoltAbi {
  /// `jolt_abi_version`: the version of this ABI.
  int abiVersion();

  /// `jolt_version`: `JPH_VERSION_ID` of the Jolt build.
  int version();

  /// `jolt_alloc`: allocates [bytes] in the module's memory.
  int alloc(int bytes);

  /// `jolt_free`.
  void free(int pointer);

  // ---- Scene lifecycle ----------------------------------------------------

  /// `jolt_world_create`: a scene with gravity and universal drag.
  int worldCreate(double gx, double gy, double gz, double drag);

  /// `jolt_world_destroy`.
  void worldDestroy(int world);

  /// `jolt_world_set_gravity`.
  void worldSetGravity(int world, double gx, double gy, double gz);

  /// `jolt_world_set_drag`: the damping of bodies created afterwards.
  void worldSetDrag(int world, double drag);

  /// `jolt_world_set_solver`.
  void worldSetSolver(int world, int velocitySteps, int positionSteps);

  /// `jolt_world_step`: one `PhysicsSystem::Update`.
  void worldStep(int world, double timeStep);

  // ---- Bodies -------------------------------------------------------------

  /// `jolt_sublevel_create`: a dynamic body with an empty shape, at a pose.
  int subLevelCreate(
    int world,
    int sableId,
    double px,
    double py,
    double pz,
    double qx,
    double qy,
    double qz,
    double qw,
  );

  /// `jolt_box_create`: a dynamic cuboid body.
  int boxCreate(
    int world,
    int sableId,
    double mass,
    double hx,
    double hy,
    double hz,
    double px,
    double py,
    double pz,
    double qx,
    double qy,
    double qz,
    double qw,
  );

  /// `jolt_body_destroy`.
  void bodyDestroy(int world, int body);

  /// `jolt_body_is_valid`.
  int bodyIsValid(int world, int body);

  /// `jolt_body_set_pose`: teleport (and wake).
  void bodySetPose(
    int world,
    int body,
    double px,
    double py,
    double pz,
    double qx,
    double qy,
    double qz,
    double qw,
  );

  /// `jolt_body_get_pose`: writes seven `f32` (`pos.xyz`, `quat.xyzw`) at [out].
  void bodyGetPose(int world, int body, int out);

  /// `jolt_body_set_com`: moves the shape's origin to the center of mass.
  void bodySetCom(int world, int body, double x, double y, double z);

  /// `jolt_body_set_mass`: [inertia] is nine `f32` (column-major) or 0.
  void bodySetMass(int world, int body, double mass, int inertia);

  /// `jolt_body_wake`.
  void bodyWake(int world, int body);

  /// `jolt_body_is_active`.
  int bodyIsActive(int world, int body);

  /// `jolt_body_add_velocities`.
  void bodyAddVelocities(
    int world,
    int body,
    double lx,
    double ly,
    double lz,
    double ax,
    double ay,
    double az,
    bool wake,
  );

  /// `jolt_body_get_linear_velocity`: writes three `f32` at [out].
  void bodyGetLinearVelocity(int world, int body, int out);

  /// `jolt_body_get_angular_velocity`: writes three `f32` at [out].
  void bodyGetAngularVelocity(int world, int body, int out);

  /// `jolt_body_add_impulse`: plot-local lever arm and force.
  void bodyAddImpulse(
    int world,
    int body,
    double lx,
    double ly,
    double lz,
    double fx,
    double fy,
    double fz,
    bool wake,
  );

  /// `jolt_body_add_impulse_and_torque`: body-local force and torque.
  void bodyAddImpulseAndTorque(
    int world,
    int body,
    double fx,
    double fy,
    double fz,
    double tx,
    double ty,
    double tz,
    bool wake,
  );

  /// `jolt_body_add_force`: a world-space force at the center of mass.
  void bodyAddForce(int world, int body, double fx, double fy, double fz);

  /// `jolt_body_add_force_at`: a world-space force at a world-space point.
  void bodyAddForceAt(
    int world,
    int body,
    double px,
    double py,
    double pz,
    double fx,
    double fy,
    double fz,
  );

  /// `jolt_body_add_torque`.
  void bodyAddTorque(int world, int body, double tx, double ty, double tz);

  /// `jolt_body_velocity_at_point`: writes three `f32` at [out].
  void bodyVelocityAtPoint(
    int world,
    int body,
    double px,
    double py,
    double pz,
    int out,
  );

  /// `jolt_body_mass`.
  double bodyMass(int world, int body);

  // ---- Voxel colliders ----------------------------------------------------

  /// `jolt_voxel_collider_new`: registers a block's collider data, returning its
  /// index (0-based; packed block states store `index + 1`).
  int voxelColliderNew(
    double friction,
    double volume,
    double restitution,
    bool fluid,
  );

  /// `jolt_voxel_collider_add_box`: one box in 0..1 voxel space.
  void voxelColliderAddBox(
    int index,
    double minX,
    double minY,
    double minZ,
    double maxX,
    double maxY,
    double maxZ,
  );

  /// `jolt_voxel_collider_clear_boxes`.
  void voxelColliderClearBoxes(int index);

  /// `jolt_voxel_collider_count`.
  int voxelColliderCount();

  // ---- Voxel world --------------------------------------------------------

  /// `jolt_chunk_add`: [data] points at 4096 `u32` packed block states.
  void chunkAdd(
    int world,
    int x,
    int y,
    int z,
    int data,
    bool global,
    int body,
  );

  /// `jolt_chunk_remove`.
  void chunkRemove(int world, int x, int y, int z, bool global, int body);

  /// `jolt_block_change`: [x],[y],[z] are absolute block coordinates.
  void blockChange(int world, int x, int y, int z, int packed);

  // ---- Constraints --------------------------------------------------------

  /// `jolt_joint_create_hinge`; [bodyA]/[bodyB] 0 means the static world.
  int jointCreateHinge(
    int world,
    int bodyA,
    int bodyB,
    double ax,
    double ay,
    double az,
    double bx,
    double by,
    double bz,
    double axisAX,
    double axisAY,
    double axisAZ,
    double axisBX,
    double axisBY,
    double axisBZ,
  );

  /// `jolt_joint_create_fixed`.
  int jointCreateFixed(
    int world,
    int bodyA,
    int bodyB,
    double ax,
    double ay,
    double az,
    double bx,
    double by,
    double bz,
    double qx,
    double qy,
    double qz,
    double qw,
  );

  /// `jolt_joint_create_sixdof`.
  int jointCreateSixDof(
    int world,
    int bodyA,
    int bodyB,
    double ax,
    double ay,
    double az,
    double qax,
    double qay,
    double qaz,
    double qaw,
    double bx,
    double by,
    double bz,
    double qbx,
    double qby,
    double qbz,
    double qbw,
    int lockedMask,
  );

  /// `jolt_joint_destroy`.
  void jointDestroy(int world, int joint);

  /// `jolt_joint_is_valid`.
  int jointIsValid(int world, int joint);

  /// `jolt_joint_set_frame`.
  void jointSetFrame(
    int world,
    int joint,
    int side,
    double x,
    double y,
    double z,
    double qx,
    double qy,
    double qz,
    double qw,
  );

  /// `jolt_joint_set_axis` (hinge only).
  void jointSetAxis(int world, int joint, int side, double x, double y, double z);

  /// `jolt_joint_set_motor`.
  void jointSetMotor(
    int world,
    int joint,
    int axis,
    double target,
    double stiffness,
    double damping,
    bool hasMaxForce,
    double maxForce,
  );

  /// `jolt_joint_set_limit`.
  void jointSetLimit(int world, int joint, int axis, double min, double max);

  /// `jolt_joint_lock_axes`.
  void jointLockAxes(int world, int joint, int mask);

  /// `jolt_joint_set_contacts_enabled`.
  void jointSetContactsEnabled(int world, int joint, bool enabled);

  /// `jolt_joint_get_impulses`: writes six `f32` at [out].
  void jointGetImpulses(int world, int joint, int out);
}

/// The linear memory of the Jolt module.
///
/// Offsets are byte offsets; [storeFloat32]/[loadFloat32] take a byte offset as
/// well, so the pipeline can lay out the same buffers the C ABI expects.
abstract interface class JoltMemory {
  void storeFloat64(int offset, double value);

  void storeFloat32(int offset, double value);

  void storeUint32(int offset, int value);

  double loadFloat32(int offset);

  int loadUint32(int offset);
}
