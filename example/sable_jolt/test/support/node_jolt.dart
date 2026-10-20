// The test bridge: the same `JoltAbi`/`JoltMemory` surface as
// `lib/src/jolt/native.dart`, but every call is forwarded to a Node process
// that instantiated `native/jolt/jolt.wasm`.
//
// `package:test` runs on the Dart VM, which cannot instantiate wasm, so the
// pipeline is driven here through two FIFOs: the bridge writes one JSON request
// per call and blocks until the host answers. Reads and writes are synchronous,
// which keeps `JoltAbi` synchronous exactly as the wasm binding is.
//
// This is a test double for the *transport*, not for the engine: the module
// that runs is the checked-in `jolt.wasm`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sable_jolt/sable_jolt.dart';

/// A running Node host with the Jolt module loaded.
final class NodeJolt implements JoltAbi, JoltMemory {
  final Process _process;
  final RandomAccessFile _requests;
  final RandomAccessFile _responses;
  final Directory _directory;

  NodeJolt._(this._process, this._requests, this._responses, this._directory);

  /// Starts the host for [wasmPath].
  static Future<NodeJolt> start(String wasmPath) async {
    if (!File(wasmPath).existsSync()) {
      throw StateError(
        'Jolt module not found at $wasmPath; run native/jolt/build.sh.',
      );
    }
    final directory = Directory.systemTemp.createTempSync('sable_jolt_test');
    final request = '${directory.path}/requests.fifo';
    final response = '${directory.path}/responses.fifo';
    final mkfifo = Process.runSync('mkfifo', [request, response]);
    if (mkfifo.exitCode != 0) {
      directory.deleteSync(recursive: true);
      throw StateError('mkfifo failed: ${mkfifo.stderr}');
    }

    final hostScript = File('test/support/jolt_host.mjs').absolute.path;
    final process = await Process.start('node', [
      hostScript,
      File(wasmPath).absolute.path,
      request,
      response,
    ]);

    // Draining the pipes keeps the child from blocking on a full buffer.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());

    final requests = File(request).openSync(mode: FileMode.writeOnly);
    final responses = File(response).openSync(mode: FileMode.read);
    return NodeJolt._(process, requests, responses, directory);
  }

  /// Stops the host and removes its temporary directory.
  void close() {
    try {
      _requests.closeSync();
    } on FileSystemException {
      // Already closed.
    }
    try {
      _responses.closeSync();
    } on FileSystemException {
      // Already closed.
    }
    _process.kill();
    try {
      _directory.deleteSync(recursive: true);
    } on FileSystemException {
      // The host may still hold the FIFOs open.
    }
  }

  // ---- Transport ----------------------------------------------------------

  Object? _request(Map<String, Object?> message) {
    _requests.writeFromSync(utf8.encode('${jsonEncode(message)}\n'));
    final bytes = <int>[];
    while (true) {
      final byte = _responses.readByteSync();
      if (byte < 0) {
        throw StateError('The Jolt host exited.');
      }
      if (byte == 0x0a) {
        break;
      }
      bytes.add(byte);
    }
    final reply = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    final error = reply['e'];
    if (error != null) {
      throw StateError('Jolt host: $error');
    }
    return reply['r'];
  }

  int _callInt(String function, List<Object?> arguments) =>
      (_request({'f': function, 'a': arguments}) as num).toInt();

  double _callDouble(String function, List<Object?> arguments) =>
      (_request({'f': function, 'a': arguments}) as num).toDouble();

  void _callVoid(String function, List<Object?> arguments) {
    _request({'f': function, 'a': arguments});
  }

  @override
  void storeFloat64(int offset, double value) =>
      _request({'m': 'w64', 'a': [offset, value]});

  @override
  void storeFloat32(int offset, double value) =>
      _request({'m': 'w32f', 'a': [offset, value]});

  @override
  void storeUint32(int offset, int value) =>
      _request({'m': 'w32', 'a': [offset, value]});

  @override
  double loadFloat32(int offset) =>
      (_request({'m': 'r32f', 'a': [offset]}) as num).toDouble();

  @override
  int loadUint32(int offset) =>
      (_request({'m': 'r32', 'a': [offset]}) as num).toInt();

  @override
  int abiVersion() =>
      _callInt('jolt_abi_version', []);

  @override
  int version() =>
      _callInt('jolt_version', []);

  @override
  int alloc(int bytes) =>
      _callInt('jolt_alloc', [bytes]);

  @override
  void free(int pointer) =>
      _callVoid('jolt_free', [pointer]);

  @override
  int worldCreate(double gx, double gy, double gz, double drag) =>
      _callInt('jolt_world_create', [gx, gy, gz, drag]);

  @override
  void worldDestroy(int world) =>
      _callVoid('jolt_world_destroy', [world]);

  @override
  void worldSetGravity(int world, double gx, double gy, double gz) =>
      _callVoid('jolt_world_set_gravity', [world, gx, gy, gz]);

  @override
  void worldSetDrag(int world, double drag) =>
      _callVoid('jolt_world_set_drag', [world, drag]);

  @override
  void worldSetSolver(int world, int velocitySteps, int positionSteps) =>
      _callVoid('jolt_world_set_solver', [world, velocitySteps, positionSteps]);

  @override
  void worldStep(int world, double timeStep) =>
      _callVoid('jolt_world_step', [world, timeStep]);

  @override
  int subLevelCreate(int world, int sableId, double px, double py, double pz, double qx, double qy, double qz, double qw,) =>
      _callInt('jolt_sublevel_create', [world, sableId, px, py, pz, qx, qy, qz, qw]);

  @override
  int boxCreate(int world, int sableId, double mass, double hx, double hy, double hz, double px, double py, double pz, double qx, double qy, double qz, double qw,) =>
      _callInt('jolt_box_create', [world, sableId, mass, hx, hy, hz, px, py, pz, qx, qy, qz, qw]);

  @override
  void bodyDestroy(int world, int body) =>
      _callVoid('jolt_body_destroy', [world, body]);

  @override
  int bodyIsValid(int world, int body) =>
      _callInt('jolt_body_is_valid', [world, body]);

  @override
  void bodySetPose(int world, int body, double px, double py, double pz, double qx, double qy, double qz, double qw,) =>
      _callVoid('jolt_body_set_pose', [world, body, px, py, pz, qx, qy, qz, qw]);

  @override
  void bodyGetPose(int world, int body, int out) =>
      _callVoid('jolt_body_get_pose', [world, body, out]);

  @override
  void bodySetCom(int world, int body, double x, double y, double z) =>
      _callVoid('jolt_body_set_com', [world, body, x, y, z]);

  @override
  void bodySetMass(int world, int body, double mass, int inertia) =>
      _callVoid('jolt_body_set_mass', [world, body, mass, inertia]);

  @override
  void bodyWake(int world, int body) =>
      _callVoid('jolt_body_wake', [world, body]);

  @override
  int bodyIsActive(int world, int body) =>
      _callInt('jolt_body_is_active', [world, body]);

  @override
  void bodyAddVelocities(int world, int body, double lx, double ly, double lz, double ax, double ay, double az, bool wake,) =>
      _callVoid('jolt_body_add_velocities', [world, body, lx, ly, lz, ax, ay, az, (wake ? 1 : 0)]);

  @override
  void bodyGetLinearVelocity(int world, int body, int out) =>
      _callVoid('jolt_body_get_linear_velocity', [world, body, out]);

  @override
  void bodyGetAngularVelocity(int world, int body, int out) =>
      _callVoid('jolt_body_get_angular_velocity', [world, body, out]);

  @override
  void bodyAddImpulse(int world, int body, double lx, double ly, double lz, double fx, double fy, double fz, bool wake,) =>
      _callVoid('jolt_body_add_impulse', [world, body, lx, ly, lz, fx, fy, fz, (wake ? 1 : 0)]);

  @override
  void bodyAddImpulseAndTorque(int world, int body, double fx, double fy, double fz, double tx, double ty, double tz, bool wake,) =>
      _callVoid('jolt_body_add_impulse_and_torque', [world, body, fx, fy, fz, tx, ty, tz, (wake ? 1 : 0)]);

  @override
  void bodyAddForce(int world, int body, double fx, double fy, double fz) =>
      _callVoid('jolt_body_add_force', [world, body, fx, fy, fz]);

  @override
  void bodyAddForceAt(int world, int body, double px, double py, double pz, double fx, double fy, double fz,) =>
      _callVoid('jolt_body_add_force_at', [world, body, px, py, pz, fx, fy, fz]);

  @override
  void bodyAddTorque(int world, int body, double tx, double ty, double tz) =>
      _callVoid('jolt_body_add_torque', [world, body, tx, ty, tz]);

  @override
  void bodyVelocityAtPoint(int world, int body, double px, double py, double pz, int out,) =>
      _callVoid('jolt_body_velocity_at_point', [world, body, px, py, pz, out]);

  @override
  double bodyMass(int world, int body) =>
      _callDouble('jolt_body_mass', [world, body]);

  @override
  int voxelColliderNew(double friction, double volume, double restitution, bool fluid,) =>
      _callInt('jolt_voxel_collider_new', [friction, volume, restitution, (fluid ? 1 : 0)]);

  @override
  void voxelColliderAddBox(int index, double minX, double minY, double minZ, double maxX, double maxY, double maxZ,) =>
      _callVoid('jolt_voxel_collider_add_box', [index, minX, minY, minZ, maxX, maxY, maxZ]);

  @override
  void voxelColliderClearBoxes(int index) =>
      _callVoid('jolt_voxel_collider_clear_boxes', [index]);

  @override
  int voxelColliderCount() =>
      _callInt('jolt_voxel_collider_count', []);

  @override
  void chunkAdd(int world, int x, int y, int z, int data, bool global, int body,) =>
      _callVoid('jolt_chunk_add', [world, x, y, z, data, (global ? 1 : 0), body]);

  @override
  void chunkRemove(int world, int x, int y, int z, bool global, int body) =>
      _callVoid('jolt_chunk_remove', [world, x, y, z, (global ? 1 : 0), body]);

  @override
  void blockChange(int world, int x, int y, int z, int packed) =>
      _callVoid('jolt_block_change', [world, x, y, z, packed]);

  @override
  int jointCreateHinge(int world, int bodyA, int bodyB, double ax, double ay, double az, double bx, double by, double bz, double axisAX, double axisAY, double axisAZ, double axisBX, double axisBY, double axisBZ,) =>
      _callInt('jolt_joint_create_hinge', [world, bodyA, bodyB, ax, ay, az, bx, by, bz, axisAX, axisAY, axisAZ, axisBX, axisBY, axisBZ]);

  @override
  int jointCreateFixed(int world, int bodyA, int bodyB, double ax, double ay, double az, double bx, double by, double bz, double qx, double qy, double qz, double qw,) =>
      _callInt('jolt_joint_create_fixed', [world, bodyA, bodyB, ax, ay, az, bx, by, bz, qx, qy, qz, qw]);

  @override
  int jointCreateSixDof(int world, int bodyA, int bodyB, double ax, double ay, double az, double qax, double qay, double qaz, double qaw, double bx, double by, double bz, double qbx, double qby, double qbz, double qbw, int lockedMask,) =>
      _callInt('jolt_joint_create_sixdof', [world, bodyA, bodyB, ax, ay, az, qax, qay, qaz, qaw, bx, by, bz, qbx, qby, qbz, qbw, lockedMask]);

  @override
  void jointDestroy(int world, int joint) =>
      _callVoid('jolt_joint_destroy', [world, joint]);

  @override
  int jointIsValid(int world, int joint) =>
      _callInt('jolt_joint_is_valid', [world, joint]);

  @override
  void jointSetFrame(int world, int joint, int side, double x, double y, double z, double qx, double qy, double qz, double qw,) =>
      _callVoid('jolt_joint_set_frame', [world, joint, side, x, y, z, qx, qy, qz, qw]);

  @override
  void jointSetAxis(int world, int joint, int side, double x, double y, double z) =>
      _callVoid('jolt_joint_set_axis', [world, joint, side, x, y, z]);

  @override
  void jointSetMotor(int world, int joint, int axis, double target, double stiffness, double damping, bool hasMaxForce, double maxForce,) =>
      _callVoid('jolt_joint_set_motor', [world, joint, axis, target, stiffness, damping, (hasMaxForce ? 1 : 0), maxForce]);

  @override
  void jointSetLimit(int world, int joint, int axis, double min, double max) =>
      _callVoid('jolt_joint_set_limit', [world, joint, axis, min, max]);

  @override
  void jointLockAxes(int world, int joint, int mask) =>
      _callVoid('jolt_joint_lock_axes', [world, joint, mask]);

  @override
  void jointSetContactsEnabled(int world, int joint, bool enabled) =>
      _callVoid('jolt_joint_set_contacts_enabled', [world, joint, (enabled ? 1 : 0)]);

  @override
  void jointGetImpulses(int world, int joint, int out) =>
      _callVoid('jolt_joint_get_impulses', [world, joint, out]);
}
