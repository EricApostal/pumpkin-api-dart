// The `dart:_wasm` binding of the Jolt core module: the `jolt.*` imports and
// the module's own linear memory.
//
// The module is linked into the component by `hook/build.dart`
// (`WasmCoreModuleAsset(name: 'jolt')`), so these declarations resolve at link
// time. This file is the only one in the package that imports `dart:_wasm`;
// everything above it (`pipeline.dart`, `buoyancy.dart`, `voxel.dart`) is plain
// Dart and runs on the VM.
//
// The module has no imports of its own (see `native/jolt/build.sh`), so nothing
// here needs a `host_call` handler — but the component still has to export
// `host_call` because the linker always instantiates the table-init module; see
// `bin/main.dart`.
// ignore_for_file: import_internal_library
import 'dart:_wasm';

import 'abi.dart';

@pragma('wasm:import', 'jolt.memory')
@pragma('wasm:memory-type', MemoryType(limits: Limits(512)))
external Memory get memory;

@pragma('wasm:import', 'jolt._initialize')
external WasmVoid _initialize();

@pragma('wasm:import', 'jolt.jolt_abi_version')
external WasmI32 _abiVersion();

@pragma('wasm:import', 'jolt.jolt_version')
external WasmI32 _version();

@pragma('wasm:import', 'jolt.jolt_alloc')
external WasmI32 _alloc(WasmI32 bytes);

@pragma('wasm:import', 'jolt.jolt_free')
external WasmVoid _free(WasmI32 pointer);

@pragma('wasm:import', 'jolt.jolt_world_create')
external WasmI32 _worldCreate(
  WasmF64 gx,
  WasmF64 gy,
  WasmF64 gz,
  WasmF64 drag,
);

@pragma('wasm:import', 'jolt.jolt_world_destroy')
external WasmVoid _worldDestroy(WasmI32 world);

@pragma('wasm:import', 'jolt.jolt_world_set_gravity')
external WasmVoid _worldSetGravity(
  WasmI32 world,
  WasmF64 gx,
  WasmF64 gy,
  WasmF64 gz,
);

@pragma('wasm:import', 'jolt.jolt_world_set_drag')
external WasmVoid _worldSetDrag(WasmI32 world, WasmF64 drag);

@pragma('wasm:import', 'jolt.jolt_world_set_solver')
external WasmVoid _worldSetSolver(
  WasmI32 world,
  WasmI32 velocitySteps,
  WasmI32 positionSteps,
);

@pragma('wasm:import', 'jolt.jolt_world_step')
external WasmVoid _worldStep(WasmI32 world, WasmF64 timeStep);

@pragma('wasm:import', 'jolt.jolt_sublevel_create')
external WasmI32 _subLevelCreate(
  WasmI32 world,
  WasmI32 sableId,
  WasmF64 px,
  WasmF64 py,
  WasmF64 pz,
  WasmF64 qx,
  WasmF64 qy,
  WasmF64 qz,
  WasmF64 qw,
);

@pragma('wasm:import', 'jolt.jolt_box_create')
external WasmI32 _boxCreate(
  WasmI32 world,
  WasmI32 sableId,
  WasmF64 mass,
  WasmF64 hx,
  WasmF64 hy,
  WasmF64 hz,
  WasmF64 px,
  WasmF64 py,
  WasmF64 pz,
  WasmF64 qx,
  WasmF64 qy,
  WasmF64 qz,
  WasmF64 qw,
);

@pragma('wasm:import', 'jolt.jolt_body_destroy')
external WasmVoid _bodyDestroy(WasmI32 world, WasmI32 body);

@pragma('wasm:import', 'jolt.jolt_body_is_valid')
external WasmI32 _bodyIsValid(WasmI32 world, WasmI32 body);

@pragma('wasm:import', 'jolt.jolt_body_set_pose')
external WasmVoid _bodySetPose(
  WasmI32 world,
  WasmI32 body,
  WasmF64 px,
  WasmF64 py,
  WasmF64 pz,
  WasmF64 qx,
  WasmF64 qy,
  WasmF64 qz,
  WasmF64 qw,
);

@pragma('wasm:import', 'jolt.jolt_body_get_pose')
external WasmVoid _bodyGetPose(WasmI32 world, WasmI32 body, WasmI32 out);

@pragma('wasm:import', 'jolt.jolt_body_set_com')
external WasmVoid _bodySetCom(
  WasmI32 world,
  WasmI32 body,
  WasmF64 x,
  WasmF64 y,
  WasmF64 z,
);

@pragma('wasm:import', 'jolt.jolt_body_set_mass')
external WasmVoid _bodySetMass(
  WasmI32 world,
  WasmI32 body,
  WasmF64 mass,
  WasmI32 inertia,
);

@pragma('wasm:import', 'jolt.jolt_body_wake')
external WasmVoid _bodyWake(WasmI32 world, WasmI32 body);

@pragma('wasm:import', 'jolt.jolt_body_is_active')
external WasmI32 _bodyIsActive(WasmI32 world, WasmI32 body);

@pragma('wasm:import', 'jolt.jolt_body_add_velocities')
external WasmVoid _bodyAddVelocities(
  WasmI32 world,
  WasmI32 body,
  WasmF64 lx,
  WasmF64 ly,
  WasmF64 lz,
  WasmF64 ax,
  WasmF64 ay,
  WasmF64 az,
  WasmI32 wake,
);

@pragma('wasm:import', 'jolt.jolt_body_get_linear_velocity')
external WasmVoid _bodyGetLinearVelocity(
  WasmI32 world,
  WasmI32 body,
  WasmI32 out,
);

@pragma('wasm:import', 'jolt.jolt_body_get_angular_velocity')
external WasmVoid _bodyGetAngularVelocity(
  WasmI32 world,
  WasmI32 body,
  WasmI32 out,
);

@pragma('wasm:import', 'jolt.jolt_body_add_impulse')
external WasmVoid _bodyAddImpulse(
  WasmI32 world,
  WasmI32 body,
  WasmF64 lx,
  WasmF64 ly,
  WasmF64 lz,
  WasmF64 fx,
  WasmF64 fy,
  WasmF64 fz,
  WasmI32 wake,
);

@pragma('wasm:import', 'jolt.jolt_body_add_impulse_and_torque')
external WasmVoid _bodyAddImpulseAndTorque(
  WasmI32 world,
  WasmI32 body,
  WasmF64 fx,
  WasmF64 fy,
  WasmF64 fz,
  WasmF64 tx,
  WasmF64 ty,
  WasmF64 tz,
  WasmI32 wake,
);

@pragma('wasm:import', 'jolt.jolt_body_add_force')
external WasmVoid _bodyAddForce(
  WasmI32 world,
  WasmI32 body,
  WasmF64 fx,
  WasmF64 fy,
  WasmF64 fz,
);

@pragma('wasm:import', 'jolt.jolt_body_add_force_at')
external WasmVoid _bodyAddForceAt(
  WasmI32 world,
  WasmI32 body,
  WasmF64 px,
  WasmF64 py,
  WasmF64 pz,
  WasmF64 fx,
  WasmF64 fy,
  WasmF64 fz,
);

@pragma('wasm:import', 'jolt.jolt_body_add_torque')
external WasmVoid _bodyAddTorque(
  WasmI32 world,
  WasmI32 body,
  WasmF64 tx,
  WasmF64 ty,
  WasmF64 tz,
);

@pragma('wasm:import', 'jolt.jolt_body_velocity_at_point')
external WasmVoid _bodyVelocityAtPoint(
  WasmI32 world,
  WasmI32 body,
  WasmF64 px,
  WasmF64 py,
  WasmF64 pz,
  WasmI32 out,
);

@pragma('wasm:import', 'jolt.jolt_body_mass')
external WasmF64 _bodyMass(WasmI32 world, WasmI32 body);

@pragma('wasm:import', 'jolt.jolt_voxel_collider_new')
external WasmI32 _voxelColliderNew(
  WasmF64 friction,
  WasmF64 volume,
  WasmF64 restitution,
  WasmI32 fluid,
);

@pragma('wasm:import', 'jolt.jolt_voxel_collider_add_box')
external WasmVoid _voxelColliderAddBox(
  WasmI32 index,
  WasmF64 minX,
  WasmF64 minY,
  WasmF64 minZ,
  WasmF64 maxX,
  WasmF64 maxY,
  WasmF64 maxZ,
);

@pragma('wasm:import', 'jolt.jolt_voxel_collider_clear_boxes')
external WasmVoid _voxelColliderClearBoxes(WasmI32 index);

@pragma('wasm:import', 'jolt.jolt_voxel_collider_count')
external WasmI32 _voxelColliderCount();

@pragma('wasm:import', 'jolt.jolt_chunk_add')
external WasmVoid _chunkAdd(
  WasmI32 world,
  WasmI32 x,
  WasmI32 y,
  WasmI32 z,
  WasmI32 data,
  WasmI32 global,
  WasmI32 body,
);

@pragma('wasm:import', 'jolt.jolt_chunk_remove')
external WasmVoid _chunkRemove(
  WasmI32 world,
  WasmI32 x,
  WasmI32 y,
  WasmI32 z,
  WasmI32 global,
  WasmI32 body,
);

@pragma('wasm:import', 'jolt.jolt_block_change')
external WasmVoid _blockChange(
  WasmI32 world,
  WasmI32 x,
  WasmI32 y,
  WasmI32 z,
  WasmI32 packed,
);

@pragma('wasm:import', 'jolt.jolt_joint_create_hinge')
external WasmI32 _jointCreateHinge(
  WasmI32 world,
  WasmI32 bodyA,
  WasmI32 bodyB,
  WasmF64 ax,
  WasmF64 ay,
  WasmF64 az,
  WasmF64 bx,
  WasmF64 by,
  WasmF64 bz,
  WasmF64 axisAX,
  WasmF64 axisAY,
  WasmF64 axisAZ,
  WasmF64 axisBX,
  WasmF64 axisBY,
  WasmF64 axisBZ,
);

@pragma('wasm:import', 'jolt.jolt_joint_create_fixed')
external WasmI32 _jointCreateFixed(
  WasmI32 world,
  WasmI32 bodyA,
  WasmI32 bodyB,
  WasmF64 ax,
  WasmF64 ay,
  WasmF64 az,
  WasmF64 bx,
  WasmF64 by,
  WasmF64 bz,
  WasmF64 qx,
  WasmF64 qy,
  WasmF64 qz,
  WasmF64 qw,
);

@pragma('wasm:import', 'jolt.jolt_joint_create_sixdof')
external WasmI32 _jointCreateSixDof(
  WasmI32 world,
  WasmI32 bodyA,
  WasmI32 bodyB,
  WasmF64 ax,
  WasmF64 ay,
  WasmF64 az,
  WasmF64 qax,
  WasmF64 qay,
  WasmF64 qaz,
  WasmF64 qaw,
  WasmF64 bx,
  WasmF64 by,
  WasmF64 bz,
  WasmF64 qbx,
  WasmF64 qby,
  WasmF64 qbz,
  WasmF64 qbw,
  WasmI32 lockedMask,
);

@pragma('wasm:import', 'jolt.jolt_joint_destroy')
external WasmVoid _jointDestroy(WasmI32 world, WasmI32 joint);

@pragma('wasm:import', 'jolt.jolt_joint_is_valid')
external WasmI32 _jointIsValid(WasmI32 world, WasmI32 joint);

@pragma('wasm:import', 'jolt.jolt_joint_set_frame')
external WasmVoid _jointSetFrame(
  WasmI32 world,
  WasmI32 joint,
  WasmI32 side,
  WasmF64 x,
  WasmF64 y,
  WasmF64 z,
  WasmF64 qx,
  WasmF64 qy,
  WasmF64 qz,
  WasmF64 qw,
);

@pragma('wasm:import', 'jolt.jolt_joint_set_axis')
external WasmVoid _jointSetAxis(
  WasmI32 world,
  WasmI32 joint,
  WasmI32 side,
  WasmF64 x,
  WasmF64 y,
  WasmF64 z,
);

@pragma('wasm:import', 'jolt.jolt_joint_set_motor')
external WasmVoid _jointSetMotor(
  WasmI32 world,
  WasmI32 joint,
  WasmI32 axis,
  WasmF64 target,
  WasmF64 stiffness,
  WasmF64 damping,
  WasmI32 hasMaxForce,
  WasmF64 maxForce,
);

@pragma('wasm:import', 'jolt.jolt_joint_set_limit')
external WasmVoid _jointSetLimit(
  WasmI32 world,
  WasmI32 joint,
  WasmI32 axis,
  WasmF64 min,
  WasmF64 max,
);

@pragma('wasm:import', 'jolt.jolt_joint_lock_axes')
external WasmVoid _jointLockAxes(WasmI32 world, WasmI32 joint, WasmI32 mask);

@pragma('wasm:import', 'jolt.jolt_joint_set_contacts_enabled')
external WasmVoid _jointSetContactsEnabled(
  WasmI32 world,
  WasmI32 joint,
  WasmI32 enabled,
);

@pragma('wasm:import', 'jolt.jolt_joint_get_impulses')
external WasmVoid _jointGetImpulses(WasmI32 world, WasmI32 joint, WasmI32 out);

WasmI32 _i32(int value) => WasmI32.fromInt(value);
WasmF64 _f64(double value) => WasmF64.fromDouble(value);

/// The Jolt module's exported functions.
final class WasmJoltAbi implements JoltAbi {
  static bool _initialized = false;

  /// Runs the module's reactor start (`_initialize`) once.
  WasmJoltAbi() {
    if (!_initialized) {
      _initialize();
      _initialized = true;
    }
  }

  @override
  int abiVersion() => _abiVersion().toIntUnsigned();

  @override
  int version() => _version().toIntUnsigned();

  @override
  int alloc(int bytes) => _alloc(_i32(bytes)).toIntUnsigned();

  @override
  void free(int pointer) => _free(_i32(pointer));

  @override
  int worldCreate(double gx, double gy, double gz, double drag) =>
      _worldCreate(_f64(gx), _f64(gy), _f64(gz), _f64(drag)).toIntUnsigned();

  @override
  void worldDestroy(int world) => _worldDestroy(_i32(world));

  @override
  void worldSetGravity(int world, double gx, double gy, double gz) =>
      _worldSetGravity(_i32(world), _f64(gx), _f64(gy), _f64(gz));

  @override
  void worldSetDrag(int world, double drag) =>
      _worldSetDrag(_i32(world), _f64(drag));

  @override
  void worldSetSolver(int world, int velocitySteps, int positionSteps) =>
      _worldSetSolver(_i32(world), _i32(velocitySteps), _i32(positionSteps));

  @override
  void worldStep(int world, double timeStep) =>
      _worldStep(_i32(world), _f64(timeStep));

  @override
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
  ) =>
      _subLevelCreate(
        _i32(world),
        _i32(sableId),
        _f64(px),
        _f64(py),
        _f64(pz),
        _f64(qx),
        _f64(qy),
        _f64(qz),
        _f64(qw),
      ).toIntUnsigned();

  @override
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
  ) =>
      _boxCreate(
        _i32(world),
        _i32(sableId),
        _f64(mass),
        _f64(hx),
        _f64(hy),
        _f64(hz),
        _f64(px),
        _f64(py),
        _f64(pz),
        _f64(qx),
        _f64(qy),
        _f64(qz),
        _f64(qw),
      ).toIntUnsigned();

  @override
  void bodyDestroy(int world, int body) =>
      _bodyDestroy(_i32(world), _i32(body));

  @override
  int bodyIsValid(int world, int body) =>
      _bodyIsValid(_i32(world), _i32(body)).toIntUnsigned();

  @override
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
  ) =>
      _bodySetPose(
        _i32(world),
        _i32(body),
        _f64(px),
        _f64(py),
        _f64(pz),
        _f64(qx),
        _f64(qy),
        _f64(qz),
        _f64(qw),
      );

  @override
  void bodyGetPose(int world, int body, int out) =>
      _bodyGetPose(_i32(world), _i32(body), _i32(out));

  @override
  void bodySetCom(int world, int body, double x, double y, double z) =>
      _bodySetCom(_i32(world), _i32(body), _f64(x), _f64(y), _f64(z));

  @override
  void bodySetMass(int world, int body, double mass, int inertia) =>
      _bodySetMass(_i32(world), _i32(body), _f64(mass), _i32(inertia));

  @override
  void bodyWake(int world, int body) => _bodyWake(_i32(world), _i32(body));

  @override
  int bodyIsActive(int world, int body) =>
      _bodyIsActive(_i32(world), _i32(body)).toIntUnsigned();

  @override
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
  ) =>
      _bodyAddVelocities(
        _i32(world),
        _i32(body),
        _f64(lx),
        _f64(ly),
        _f64(lz),
        _f64(ax),
        _f64(ay),
        _f64(az),
        _i32(wake ? 1 : 0),
      );

  @override
  void bodyGetLinearVelocity(int world, int body, int out) =>
      _bodyGetLinearVelocity(_i32(world), _i32(body), _i32(out));

  @override
  void bodyGetAngularVelocity(int world, int body, int out) =>
      _bodyGetAngularVelocity(_i32(world), _i32(body), _i32(out));

  @override
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
  ) =>
      _bodyAddImpulse(
        _i32(world),
        _i32(body),
        _f64(lx),
        _f64(ly),
        _f64(lz),
        _f64(fx),
        _f64(fy),
        _f64(fz),
        _i32(wake ? 1 : 0),
      );

  @override
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
  ) =>
      _bodyAddImpulseAndTorque(
        _i32(world),
        _i32(body),
        _f64(fx),
        _f64(fy),
        _f64(fz),
        _f64(tx),
        _f64(ty),
        _f64(tz),
        _i32(wake ? 1 : 0),
      );

  @override
  void bodyAddForce(int world, int body, double fx, double fy, double fz) =>
      _bodyAddForce(_i32(world), _i32(body), _f64(fx), _f64(fy), _f64(fz));

  @override
  void bodyAddForceAt(
    int world,
    int body,
    double px,
    double py,
    double pz,
    double fx,
    double fy,
    double fz,
  ) =>
      _bodyAddForceAt(
        _i32(world),
        _i32(body),
        _f64(px),
        _f64(py),
        _f64(pz),
        _f64(fx),
        _f64(fy),
        _f64(fz),
      );

  @override
  void bodyAddTorque(int world, int body, double tx, double ty, double tz) =>
      _bodyAddTorque(_i32(world), _i32(body), _f64(tx), _f64(ty), _f64(tz));

  @override
  void bodyVelocityAtPoint(
    int world,
    int body,
    double px,
    double py,
    double pz,
    int out,
  ) =>
      _bodyVelocityAtPoint(
        _i32(world),
        _i32(body),
        _f64(px),
        _f64(py),
        _f64(pz),
        _i32(out),
      );

  @override
  double bodyMass(int world, int body) =>
      _bodyMass(_i32(world), _i32(body)).toDouble();

  @override
  int voxelColliderNew(
    double friction,
    double volume,
    double restitution,
    bool fluid,
  ) =>
      _voxelColliderNew(
        _f64(friction),
        _f64(volume),
        _f64(restitution),
        _i32(fluid ? 1 : 0),
      ).toIntUnsigned();

  @override
  void voxelColliderAddBox(
    int index,
    double minX,
    double minY,
    double minZ,
    double maxX,
    double maxY,
    double maxZ,
  ) =>
      _voxelColliderAddBox(
        _i32(index),
        _f64(minX),
        _f64(minY),
        _f64(minZ),
        _f64(maxX),
        _f64(maxY),
        _f64(maxZ),
      );

  @override
  void voxelColliderClearBoxes(int index) =>
      _voxelColliderClearBoxes(_i32(index));

  @override
  int voxelColliderCount() => _voxelColliderCount().toIntUnsigned();

  @override
  void chunkAdd(
    int world,
    int x,
    int y,
    int z,
    int data,
    bool global,
    int body,
  ) =>
      _chunkAdd(
        _i32(world),
        _i32(x),
        _i32(y),
        _i32(z),
        _i32(data),
        _i32(global ? 1 : 0),
        _i32(body),
      );

  @override
  void chunkRemove(int world, int x, int y, int z, bool global, int body) =>
      _chunkRemove(
        _i32(world),
        _i32(x),
        _i32(y),
        _i32(z),
        _i32(global ? 1 : 0),
        _i32(body),
      );

  @override
  void blockChange(int world, int x, int y, int z, int packed) =>
      _blockChange(_i32(world), _i32(x), _i32(y), _i32(z), _i32(packed));

  @override
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
  ) =>
      _jointCreateHinge(
        _i32(world),
        _i32(bodyA),
        _i32(bodyB),
        _f64(ax),
        _f64(ay),
        _f64(az),
        _f64(bx),
        _f64(by),
        _f64(bz),
        _f64(axisAX),
        _f64(axisAY),
        _f64(axisAZ),
        _f64(axisBX),
        _f64(axisBY),
        _f64(axisBZ),
      ).toIntUnsigned();

  @override
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
  ) =>
      _jointCreateFixed(
        _i32(world),
        _i32(bodyA),
        _i32(bodyB),
        _f64(ax),
        _f64(ay),
        _f64(az),
        _f64(bx),
        _f64(by),
        _f64(bz),
        _f64(qx),
        _f64(qy),
        _f64(qz),
        _f64(qw),
      ).toIntUnsigned();

  @override
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
  ) =>
      _jointCreateSixDof(
        _i32(world),
        _i32(bodyA),
        _i32(bodyB),
        _f64(ax),
        _f64(ay),
        _f64(az),
        _f64(qax),
        _f64(qay),
        _f64(qaz),
        _f64(qaw),
        _f64(bx),
        _f64(by),
        _f64(bz),
        _f64(qbx),
        _f64(qby),
        _f64(qbz),
        _f64(qbw),
        _i32(lockedMask),
      ).toIntUnsigned();

  @override
  void jointDestroy(int world, int joint) =>
      _jointDestroy(_i32(world), _i32(joint));

  @override
  int jointIsValid(int world, int joint) =>
      _jointIsValid(_i32(world), _i32(joint)).toIntUnsigned();

  @override
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
  ) =>
      _jointSetFrame(
        _i32(world),
        _i32(joint),
        _i32(side),
        _f64(x),
        _f64(y),
        _f64(z),
        _f64(qx),
        _f64(qy),
        _f64(qz),
        _f64(qw),
      );

  @override
  void jointSetAxis(int world, int joint, int side, double x, double y, double z) =>
      _jointSetAxis(
        _i32(world),
        _i32(joint),
        _i32(side),
        _f64(x),
        _f64(y),
        _f64(z),
      );

  @override
  void jointSetMotor(
    int world,
    int joint,
    int axis,
    double target,
    double stiffness,
    double damping,
    bool hasMaxForce,
    double maxForce,
  ) =>
      _jointSetMotor(
        _i32(world),
        _i32(joint),
        _i32(axis),
        _f64(target),
        _f64(stiffness),
        _f64(damping),
        _i32(hasMaxForce ? 1 : 0),
        _f64(maxForce),
      );

  @override
  void jointSetLimit(
    int world,
    int joint,
    int axis,
    double min,
    double max,
  ) =>
      _jointSetLimit(
        _i32(world),
        _i32(joint),
        _i32(axis),
        _f64(min),
        _f64(max),
      );

  @override
  void jointLockAxes(int world, int joint, int mask) =>
      _jointLockAxes(_i32(world), _i32(joint), _i32(mask));

  @override
  void jointSetContactsEnabled(int world, int joint, bool enabled) =>
      _jointSetContactsEnabled(
        _i32(world),
        _i32(joint),
        _i32(enabled ? 1 : 0),
      );

  @override
  void jointGetImpulses(int world, int joint, int out) =>
      _jointGetImpulses(_i32(world), _i32(joint), _i32(out));
}

/// The Jolt module's linear memory.
final class WasmJoltMemory implements JoltMemory {
  const WasmJoltMemory();

  @override
  void storeFloat64(int offset, double value) =>
      memory.storeFloat64(offset, WasmF64.fromDouble(value));

  @override
  void storeFloat32(int offset, double value) =>
      memory.storeFloat32(offset, WasmF32.fromDouble(value));

  @override
  void storeUint32(int offset, int value) =>
      memory.storeInt32(offset, WasmI32.fromInt(value.toSigned(32)));

  @override
  double loadFloat32(int offset) => memory.loadFloat32(offset).toDouble();

  @override
  int loadUint32(int offset) => memory.loadInt32(offset).toIntUnsigned();
}
