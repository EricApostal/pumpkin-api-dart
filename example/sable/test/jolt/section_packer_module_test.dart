// End to end: sections packed by `JoltCollisionPacker` (the live bakery and
// packing path) handed to the *real* Jolt module, so a sub-level body rests on a
// static floor instead of falling through it.
//
// Its own file because `JoltPhysicsPipeline`'s collider registry is
// process-wide (it mirrors the module's global `g_colliders`): a test isolate
// that also drives a fake ABI would count collider indices the real module never
// saw. Each test file is its own isolate.
import 'dart:io';

import 'package:create/src/api/block_state.dart' show BState;
import 'package:sable/sable.dart';
import 'package:sable/src/physics/jolt.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/node_jolt.dart';

const _wasm = 'native/jolt/jolt.wasm';

/// A `PlotChunk` over a sparse map of local positions.
final class _MapChunk implements PlotChunk {
  _MapChunk(this.pos, this.minY, this.blocks);

  @override
  final (int, int) pos;

  /// The lowest block y of the level (section index 0 starts here).
  final int minY;

  /// The non-air states, by local `(x, y, z)`.
  final Map<(int, int, int), String> blocks;

  @override
  int get sectionsCount => 24;

  @override
  bool get hasOnlyAir => blocks.isEmpty;

  @override
  bool sectionHasOnlyAir(int index) => !blocks.keys.any((b) => ((b.$2 - minY) >> 4) == index);

  @override
  int sectionMinY(int index) => minY + (index << 4);

  @override
  Map<String, Object?>? blockEntityData(int x, int y, int z) => null;

  @override
  String blockAt(int x, int y, int z) => blocks[(x, y, z)] ?? 'minecraft:air';

  @override
  Map<int, PlotScheduledTick> get blockTicks => const {};

  @override
  int indexOfBlock(int x, int y, int z) => ((y & 0xFFF) << 8) | ((z & 15) << 4) | (x & 15);

  @override
  void scheduleBlockTick(int x, int y, int z, PlotScheduledTick tick) {}
}

/// The block states the packer reads, over the same map (positions outside it
/// are air), answering a whole batch at once like the Pumpkin host does.
final class _MapHost implements AssemblyBlockHost, BulkBlockHost {
  _MapHost(this.minY);

  final int minY;

  /// Non-air states by absolute position.
  final Map<(int, int, int), String> world = {};

  @override
  BState blockStateAt(int x, int y, int z) => BState(world[(x, y, z)] ?? 'minecraft:air');

  @override
  List<BState> readBlockStates(List<(int, int, int)> positions) => [
    for (final p in positions) blockStateAt(p.$1, p.$2, p.$3),
  ];

  @override
  void setBlockStateAt(int x, int y, int z, BState state) => throw UnimplementedError();

  @override
  Map<String, Object?>? blockEntityDataAt(int x, int y, int z) => null;

  @override
  void setBlockEntityDataAt(int x, int y, int z, Map<String, Object?> data) =>
      throw UnimplementedError();

  @override
  void removeBlockEntityAt(int x, int y, int z) => throw UnimplementedError();

  @override
  void notifyBlockChanged(int x, int y, int z, BState oldState, BState newState) {}
}

/// The host's block shapes: `minecraft:stone` is the unit cube, everything else
/// has no collision shape.
final class _Shapes implements BlockShapeSource {
  @override
  List<VoxelBox>? boxesOf(String state) =>
      state.split('[').first == 'minecraft:stone' ? const [VoxelBox.unit] : const [];

  @override
  bool isLiquid(String state) => false;
}

final class _Mass implements MassData {
  _Mass(this.centerOfMass, this.mass);

  final Vector3d centerOfMass;

  final double mass;

  @override
  Vector3d getCenterOfMass() => centerOfMass;

  @override
  double getInverseMass() => 1.0 / mass;

  @override
  double getMass() => mass;

  @override
  Matrix3d getInertiaTensor() => Matrix3d.identity();

  @override
  Matrix3d getInverseInertiaTensor() => Matrix3d.identity();

  @override
  bool isInvalid() => mass <= 0.0;

  @override
  BoundingBox3ic? getBounds() => BoundingBox3i.values(-1, -1, -1, 1, 1, 1);
}

void main() {
  group('packed sections in the real module', () {
    final available = File(_wasm).existsSync() &&
        (() {
          try {
            return Process.runSync('node', ['--version']).exitCode == 0;
          } on ProcessException {
            return false;
          }
        })();
    final skip = available ? null : 'needs node and $_wasm (run native/jolt/build.sh)';

    late NodeJolt abi;
    late JoltPhysicsPipeline pipeline;

    setUpAll(() async {
      if (!available) return;
      abi = await NodeJolt.start(_wasm);
    });

    tearDownAll(() => abi.close());

    setUp(() {
      if (!available) return;
      pipeline = JoltPhysicsPipeline(abi: abi, memory: abi);
      pipeline.init(Vector3d(0.0, -9.81, 0.0), 0.0);
    });

    tearDown(() {
      if (available) pipeline.dispose();
    });

    test('a body packed by the packer rests on a floor packed by the packer', () {
      final level = TestLevel();
      SubLevelContainer.register(TestContainer(level, TestChunkHost()));
      addTearDown(() => SubLevelContainer.unregister(level));

      final host = _MapHost(0);
      final packer = JoltCollisionPacker(
        pipeline: pipeline,
        shapes: _Shapes(),
        blocks: host,
      );

      // The static level: a stone floor at y = 0 over the chunk's 16x16 columns.
      final floor = <(int, int, int), String>{};
      for (var x = 0; x < 16; x++) {
        for (var z = 0; z < 16; z++) {
          floor[(x, 0, z)] = 'minecraft:stone';
          host.world[(x, 0, z)] = 'minecraft:stone';
        }
      }
      pipeline.handleChunkSectionAddition(
        0,
        0,
        0,
        packer.packSection(_MapChunk((0, 0), 0, floor), 0),
        global: true,
      );

      // The sub-level: one stone block at its plot's origin, packed by the same
      // packer and routed to its own body.
      final subLevel = ServerSubLevel(
        level,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
        Pose3d()..position().set(0.0, 3.0, 0.0),
        runtimeId: 7,
      );
      pipeline.addSubLevel(subLevel, subLevel.pose);
      final body = subLevel.physicsBody!;

      final ship = <(int, int, int), String>{(0, 0, 0): 'minecraft:stone'};
      for (final entry in ship.entries) {
        host.world[entry.key] = entry.value;
      }
      pipeline.handleChunkSectionAddition(
        0,
        0,
        0,
        packer.packSection(_MapChunk((0, 0), 0, ship), 0),
        global: false,
        subLevelRuntimeId: 7,
      );
      subLevel.massTracker = _Mass(Vector3d(0.5, 0.5, 0.5), 1.0);
      pipeline.onStatsChanged(subLevel);

      for (var i = 0; i < 240; i++) {
        pipeline.physicsTick(1.0 / 60.0);
      }

      final rest = pipeline.readPose(subLevel, Pose3d());
      // The floor block at y = 0 spans y 0..1, so its top is y = 1. The body's
      // block is centred on the body origin (half extent 0.5), so it comes to
      // rest at 1 + 0.5 minus the contact slop instead of falling through.
      expect(
        rest.position().y,
        closeTo(1.48, 0.05),
        reason: 'the body rests on the packed floor (pose ${rest.position().y})',
      );
      final velocity = pipeline.getLinearVelocity(body, Vector3d());
      expect(velocity.y.abs(), lessThan(0.1));
    }, skip: skip);
  });
}
