// The live collision data of the Jolt backend: the bakery (`BlockColliderBakery`)
// and the section packer (`JoltCollisionPacker`).
//
// The engine-side contract is already covered by `pipeline_test.dart` (a packed
// section handed to the real module makes bodies collide). What is covered here
// is the *packing*: that the packer turns the level's block states into those
// words with the right collider, the right neighbourhood state and the right
// properties — and that a floor it packs stops a sub-level body.
import 'package:create/src/api/block_state.dart' show BState;
import 'package:sable/sable.dart';
import 'package:sable/src/physics/jolt.dart';
import 'package:test/test.dart';

import 'support/recording_jolt.dart';

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

/// The host's block shapes, over a map: the unit cube for the keys in [cubes],
/// `boxes` for anything in [custom], nothing for everything else.
final class _MapShapes implements BlockShapeSource {
  _MapShapes({this.custom = const {}, this.liquids = const {}});

  /// The block keys whose shape is the unit cube.
  static const Set<String> _cubes = {'minecraft:stone'};

  final Map<String, List<VoxelBox>> custom;
  final Set<String> liquids;

  @override
  List<VoxelBox>? boxesOf(String state) {
    final key = state.split('[').first;
    if (custom.containsKey(key)) return custom[key];
    if (_cubes.contains(key)) return const [VoxelBox.unit];
    return const [];
  }

  @override
  bool isLiquid(String state) => liquids.contains(state.split('[').first);
}

void main() {
  group('the bakery', () {
    late RecordingJolt abi;
    late JoltPhysicsPipeline pipeline;

    setUp(() {
      abi = RecordingJolt();
      pipeline = JoltPhysicsPipeline(abi: abi, memory: abi);
      pipeline.init(Vector3d(0.0, -9.81, 0.0), 0.0);
    });

    tearDown(() => pipeline.dispose());

    test('a full cube registers one unit box with the datapack properties', () {
      final table = PhysicsBlockPropertiesTable();
      final bakery = BlockColliderBakery(
        register: pipeline.registerVoxelCollider,
        shapes: _MapShapes(),
        properties: table,
      );

      final stone = bakery.of('minecraft:stone');
      expect(stone.colliderIndex, isNotNull);
      expect(stone.solid, isTrue);
      expect(stone.fullBlock, isTrue);
      expect(stone.liquid, isFalse);

      final collider = pipeline.colliders[stone.colliderIndex!]!;
      expect(collider.boxes, hasLength(1));
      expect(collider.boxes.single.minX, 0.0);
      expect(collider.boxes.single.maxY, 1.0);
      // No datapack definition for this table: Java's defaults.
      expect(collider.friction, 1.0);
      expect(collider.volume, 1.0);
      expect(collider.restitution, 0.0);

      // The state is baked once, however often it is asked for.
      expect(bakery.of('minecraft:stone').colliderIndex, stone.colliderIndex);
      expect(bakery.bakedStates, 1);
    });

    test('a state with no collision shape gets no collider', () {
      final bakery = BlockColliderBakery(
        register: pipeline.registerVoxelCollider,
        shapes: _MapShapes(),
      );

      final air = bakery.of('minecraft:air');
      expect(air.colliderIndex, isNull);
      expect(air.solid, isFalse);
      expect(bakery.of('minecraft:torch').colliderIndex, isNull);
    });

    test('a liquid gets a unit box and the fluid flag', () {
      final bakery = BlockColliderBakery(
        register: pipeline.registerVoxelCollider,
        shapes: _MapShapes(liquids: const {'minecraft:water'}),
      );

      final water = bakery.of('minecraft:water');
      expect(water.liquid, isTrue);
      expect(water.colliderIndex, isNotNull);
      final collider = pipeline.colliders[water.colliderIndex!]!;
      expect(collider.fluid, isTrue);
      expect(collider.boxes.single.maxY, 1.0);
    });

    test('a partial shape is clamped to the unit cube and is not a full block', () {
      final bakery = BlockColliderBakery(
        register: pipeline.registerVoxelCollider,
        shapes: _MapShapes(
          custom: {
            'minecraft:oak_slab': const [
              VoxelBox(0.0, 0.0, 0.0, 1.0, 0.5, 1.0),
            ],
            'minecraft:fence': const [
              // A fence's arms reach outside the block in vanilla's shape space.
              VoxelBox(-0.1, 0.0, 0.4, 1.1, 1.5, 0.6),
            ],
          },
        ),
      );

      final slab = bakery.of('minecraft:oak_slab');
      expect(slab.fullBlock, isFalse);
      expect(slab.solid, isTrue);
      expect(pipeline.colliders[slab.colliderIndex!]!.boxes.single.maxY, 0.5);

      final fence = bakery.of('minecraft:fence');
      final box = pipeline.colliders[fence.colliderIndex!]!.boxes.single;
      expect(box.minX, 0.0, reason: 'clamped to 0');
      expect(box.maxX, 1.0, reason: 'clamped to 1');
      expect(box.maxY, 1.0, reason: 'clamped to 1');
      expect(fence.fullBlock, isFalse, reason: 'the shape is not the unit cube');
    });
  });

  group('the section packer', () {
    late RecordingJolt abi;
    late JoltPhysicsPipeline pipeline;
    late _MapHost host;
    late JoltCollisionPacker packer;

    setUp(() {
      abi = RecordingJolt();
      pipeline = JoltPhysicsPipeline(abi: abi, memory: abi);
      pipeline.init(Vector3d(0.0, -9.81, 0.0), 0.0);
      host = _MapHost(0);
      packer = JoltCollisionPacker(
        pipeline: pipeline,
        shapes: _MapShapes(),
        blocks: host,
      );
    });

    tearDown(() => pipeline.dispose());

    test('an air-only section is all zeros without reading a block', () {
      final chunk = _MapChunk((0, 0), 0, {});
      expect(packer.packSection(chunk, 0), everyElement(0));
    });

    test('a floor packs a collider index and a FACE state', () {
      // One stone layer at y = 0 across the chunk.
      for (var x = 0; x < 16; x++) {
        for (var z = 0; z < 16; z++) {
          host.world[(x, 0, z)] = 'minecraft:stone';
        }
      }
      final chunk = _MapChunk((0, 0), 0, {
        for (var x = 0; x < 16; x++)
          for (var z = 0; z < 16; z++) (x, 0, z): 'minecraft:stone',
      });

      final packed = packer.packSection(chunk, 0);
      expect(packed, hasLength(4096));

      // `bx + (bz << 4) + (by << 8)`: y = 0 is the first 256 words.
      final word = packed[3 + (5 << 4)];
      expect(colliderIndexOfPacked(word), isNonNegative);
      expect(
        voxelStateOfPacked(word),
        VoxelPhysicsState.face,
        reason: 'a floor tile has full neighbours on x and z, air above and below',
      );
      // Above the floor is air.
      expect(packed[3 + (5 << 4) + (1 << 8)], 0);
      expect(packer.packedSections, 1);
      expect(packer.bakery.bakedStates, greaterThan(0));
    });

    test('an enclosed block is INTERIOR and an exposed one is CORNER', () {
      // A 3x3x3 stone cube at (0..2, 0..2, 0..2) in section 0.
      final blocks = <(int, int, int), String>{};
      for (var x = 0; x < 3; x++) {
        for (var y = 0; y < 3; y++) {
          for (var z = 0; z < 3; z++) {
            blocks[(x, y, z)] = 'minecraft:stone';
            host.world[(x, y, z)] = 'minecraft:stone';
          }
        }
      }
      final packed = packer.packSection(_MapChunk((0, 0), 0, blocks), 0);

      int word(int x, int y, int z) => packed[x + (z << 4) + (y << 8)];

      expect(
        voxelStateOfPacked(word(1, 1, 1)),
        VoxelPhysicsState.interior,
        reason: 'the middle of the cube is fully enclosed',
      );
      expect(
        voxelStateOfPacked(word(1, 2, 1)),
        VoxelPhysicsState.face,
        reason: 'the top face has full neighbours on x and z (bothSidesCount 2), '
            'which is neither EDGE (exactly one axis) nor CORNER',
      );
      expect(
        voxelStateOfPacked(word(0, 0, 0)),
        VoxelPhysicsState.corner,
        reason: 'a cube corner has a full neighbour on each positive axis and '
            'none on the negatives: no axis is solid on both sides',
      );
      // A neighbour outside the chunk is air: a block at the section's edge is
      // not interior.
      expect(voxelStateOfPacked(word(0, 0, 0)), isNot(VoxelPhysicsState.interior));
    });

    test('a block with a partial shape packs a CORNER state', () {
      final slabPacker = JoltCollisionPacker(
        pipeline: pipeline,
        shapes: _MapShapes(
          custom: {
            'minecraft:oak_slab': const [VoxelBox(0.0, 0.0, 0.0, 1.0, 0.5, 1.0)],
          },
        ),
        blocks: host,
      );
      host.world[(0, 0, 0)] = 'minecraft:oak_slab';
      final packed = slabPacker.packSection(
        _MapChunk((0, 0), 0, {(0, 0, 0): 'minecraft:oak_slab'}),
        0,
      );
      expect(voxelStateOfPacked(packed[0]), VoxelPhysicsState.corner);
    });

    test('the section position decides which blocks are read', () {
      // Section (1, 0, 2) of the level: block (16, 0, 32) is its local origin.
      host.world[(16, 0, 32)] = 'minecraft:stone';
      final packed = packer.packSection(_MapChunk((1, 2), 0, {(0, 0, 0): 'minecraft:stone'}), 0);
      expect(colliderIndexOfPacked(packed[0]), isNonNegative);
      expect(packed[1], 0);
    });
  });
}

