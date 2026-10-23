// A recording `JoltAbi`/`JoltMemory` for the tests that exercise the pipeline's
// *own* decisions rather than the engine's: which body a chunk section is
// uploaded to, and which features a pipeline declares.
//
// `NodeJolt` (`node_jolt.dart`) runs the real `jolt.wasm`, so it needs node and
// a built module; this fake keeps those tests runnable everywhere and makes the
// arguments of every `chunkAdd`/`chunkRemove` observable, which is exactly what
// the routing assertions need. Unimplemented entry points throw, so a test that
// accidentally drives the engine gets told.
//
// Pure: no host imports.
import 'dart:typed_data';

import 'package:sable/src/physics/jolt.dart';

/// One `jolt_chunk_add` / `jolt_chunk_remove` call.
final class ChunkCall {
  final bool add;
  final int x;
  final int y;
  final int z;

  /// Whether the section was uploaded as static level geometry.
  final bool global;

  /// The body handle, `0` for the static level.
  final int body;

  ChunkCall(this.add, this.x, this.y, this.z, this.global, this.body);

  @override
  String toString() => 'ChunkCall(add: $add, ($x, $y, $z), global: $global, body: $body)';
}

/// A `JoltAbi`/`JoltMemory` that records the calls the pipeline makes and
/// implements just enough of the world to run it.
final class RecordingJolt implements JoltAbi, JoltMemory {
  /// Every chunk section call, in order.
  final List<ChunkCall> chunks = [];

  /// Every `jolt_block_change` call, in order: `(x, y, z, packed)`.
  final List<(int, int, int, int)> blockChanges = [];

  /// Every `jolt_body_add_force_at` call, in order.
  final List<(int, double, double, double, double, double, double)> forces = [];

  final Uint8List _memory = Uint8List(1 << 20);
  int _nextHandle = 0x100;
  int _nextScratch = 0x80000;

  /// The next collider index.
  ///
  /// Static on purpose: `JoltPhysicsPipeline`'s collider registry is
  /// process-wide (`JoltPhysicsPipeline._colliders`, "the module's registry is
  /// process-wide, like Rapier's global `PHYSICS_STATE`"), so the index keeps
  /// counting across pipelines and tests. The fake must hand back the same
  /// indices or `registerVoxelCollider` reports the two registries as out of
  /// sync.
  static int _nextCollider = 0;

  int get _world => 0x1;

  @override
  int abiVersion() => 1;

  @override
  int version() => (5 << 16) | (6 << 8) | 1;

  @override
  int alloc(int bytes) {
    final pointer = _nextScratch;
    _nextScratch += bytes + 16;
    return pointer;
  }

  @override
  void free(int pointer) {}

  @override
  int worldCreate(double gx, double gy, double gz, double drag) => _world;

  @override
  void worldDestroy(int world) {}

  @override
  void worldStep(int world, double timeStep) {}

  @override
  int subLevelCreate(
    int world,
    int runtimeId,
    double x,
    double y,
    double z,
    double qx,
    double qy,
    double qz,
    double qw,
  ) => ++_nextHandle;

  @override
  int boxCreate(
    int world,
    int runtimeId,
    double mass,
    double hx,
    double hy,
    double hz,
    double x,
    double y,
    double z,
    double qx,
    double qy,
    double qz,
    double qw,
  ) => ++_nextHandle;

  @override
  void bodyDestroy(int world, int body) {}

  @override
  int bodyIsValid(int world, int body) => 1;

  @override
  int bodyIsActive(int world, int body) => 1;

  @override
  double bodyMass(int world, int body) => 1.0;

  @override
  void chunkAdd(int world, int x, int y, int z, int blocks, bool global, int body) =>
      chunks.add(ChunkCall(true, x, y, z, global, body));

  @override
  void chunkRemove(int world, int x, int y, int z, bool global, int body) =>
      chunks.add(ChunkCall(false, x, y, z, global, body));

  @override
  void blockChange(int world, int x, int y, int z, int packed) =>
      blockChanges.add((x, y, z, packed));

  @override
  int voxelColliderNew(double friction, double volume, double restitution, bool fluid) =>
      _nextCollider++;

  @override
  void voxelColliderAddBox(
    int index,
    double minX,
    double minY,
    double minZ,
    double maxX,
    double maxY,
    double maxZ,
  ) {}

  @override
  void voxelColliderClearBoxes(int index) {}

  @override
  int voxelColliderCount() => _nextCollider + 1;

  @override
  void bodyAddForceAt(
    int world,
    int body,
    double x,
    double y,
    double z,
    double fx,
    double fy,
    double fz,
  ) => forces.add((body, x, y, z, fx, fy, fz));

  @override
  void bodyGetPose(int world, int body, int out) {}

  @override
  void storeFloat64(int offset, double value) {}

  @override
  void storeFloat32(int offset, double value) {}

  @override
  void storeUint32(int offset, int value) {
    final view = ByteData.view(_memory.buffer);
    view.setUint32(offset, value, Endian.little);
  }

  @override
  double loadFloat32(int offset) =>
      ByteData.view(_memory.buffer).getFloat32(offset, Endian.little);

  @override
  int loadUint32(int offset) =>
      ByteData.view(_memory.buffer).getUint32(offset, Endian.little);

  /// Every other entry point (`worldSet*`, `body*`, the joint layer, …) is not
  /// needed by the tests here.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'RecordingJolt.${invocation.memberName} is not implemented by the fake; '
    'use NodeJolt for engine behaviour.',
  );
}