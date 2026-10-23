// The live collision data of the Jolt backend: Java's `RapierVoxelColliderBakery`
// (`sable_rapier/.../rapier/collider/RapierVoxelColliderBakery.java`) plus the
// packing half of `RapierPhysicsPipeline.handleChunkSectionAddition`
// (`RapierPhysicsPipeline.java:332-367`).
//
// The Dart pipeline takes the packed array instead of a `LevelChunkSection`
// (`PhysicsPipeline.handleChunkSectionAddition`), so the packing sits in front of
// it: `PhysicsChunkTicketManager.packer` must be set to a [JoltCollisionPacker]
// for any section to reach the engine at all. Without one, `_uploadSection`
// returns before the pipeline is called, the sub-level body keeps Jolt's empty
// shape and the static level stays empty — the body falls, but there is nothing
// to fall onto and nothing of its own to land with.
//
// What the bakery needs of a block state (its collision boxes and whether it is
// liquid) is a [BlockShapeSource]: the host's block registry in the plugin
// component (`src/plugin/host_block_shapes.dart`), a map in tests. Everything
// else here is the Java algorithm, unchanged.
//
// Pure: no host imports, so `package:test` can load it.
//
// create's block-state type is not exported from its public barrel yet, so it is
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/api/block_state.dart' show BState;
import '../../sable.dart';

import 'jolt/pipeline.dart';
import 'jolt/voxel.dart';

/// The collision shape of a block state, as the bakery reads it from the host.
///
/// `BlockState.getCollisionShape(blockGetter, pos)` and
/// `VoxelNeighborhoodState.isLiquid`. The state is the full state string
/// (`minecraft:oak_stairs[facing=north,half=bottom]`), which is the form the
/// block-property table and the host's registry both resolve.
abstract interface class BlockShapeSource {
  /// The collision boxes of [state] in block units, or `null` when the state is
  /// unknown to the block registry (an unregistered block, or a property value
  /// the registry does not know).
  ///
  /// Air and every other block without a collision shape answer with an empty
  /// list, which is `getPhysicsDataForBlock`'s `RapierVoxelColliderData.EMPTY`
  /// and means "no collider".
  List<VoxelBox>? boxesOf(String state);

  /// `VoxelNeighborhoodState.isLiquid(state)`: `state.liquid()` — a fluid state
  /// or a waterlogged block — or kelp.
  bool isLiquid(String state);
}

/// The physics data of one block state, as Java's bakery bakes it.
final class BakedBlock {
  /// The registry index of the state's collider, or `null` when the state has no
  /// collision boxes (`getPhysicsDataForBlock` returns `null` then).
  final int? colliderIndex;

  /// `!state.getCollisionShape(blockGetter, pos).isEmpty()` — the `isSolid` the
  /// neighbourhood state is computed with (`VoxelNeighborhoodState.isSolid`).
  final bool solid;

  /// `state.isCollisionShapeFullBlock(...)`: the collision shape is one box
  /// covering the whole block (`VoxelNeighborhoodState.isFullBlock`).
  final bool fullBlock;

  /// `VoxelNeighborhoodState.isLiquid(state)`.
  final bool liquid;

  /// `BlockWithSubLevelCollisionCallback.hasCallback(state)`.
  final bool hasCallback;

  const BakedBlock({
    required this.colliderIndex,
    required this.solid,
    required this.fullBlock,
    required this.liquid,
    required this.hasCallback,
  });
}

/// `RapierVoxelColliderBakery`: one collider per block state, registered in the
/// engine's process-wide registry (`voxel_collider_map`) on first use.
///
/// Java memoizes the builder per pipeline (`Util.memoize` on `blockPhysicsDataBuilder`),
/// so a second level's pipeline bakes the same states again; the registry is
/// global, so those are additional entries with the same data. The cache here is
/// per bakery for the same reason.
final class BlockColliderBakery {
  /// `Rapier3D.createVoxelColliderEntry`: registers a baked collider and returns
  /// its index (`JoltPhysicsPipeline.registerVoxelCollider`).
  final int Function(BlockColliderData data) register;

  /// The state-to-shape lookup.
  final BlockShapeSource shapes;

  /// The datapack's per-block physics properties
  /// (`PhysicsBlockPropertyHelper.getFriction/getVolume/getRestitution`), or
  /// `null` before the pack is loaded (Java's defaults are then used).
  final PhysicsBlockPropertiesTable? properties;

  final Map<String, BakedBlock> _baked = {};

  BlockColliderBakery({
    required this.register,
    required this.shapes,
    this.properties,
  });

  /// The baked data of [state], baking and registering it on first use.
  BakedBlock of(String state) => _baked.putIfAbsent(state, () => _bake(state));

  /// The registry index of [state]'s collider, or `null` when it has none.
  int? colliderOf(String state) => of(state).colliderIndex;

  /// The number of states baked so far.
  int get bakedStates => _baked.length;

  /// `buildPhysicsDataForBlock` (`RapierVoxelColliderBakery.java:57-100`).
  BakedBlock _bake(String state) {
    final key = BlockStateKey.parse(state);
    final callback = BlockWithSubLevelCollisionCallback.hasCallback(
      BState(key.blockId, key.properties),
    );
    final liquid = shapes.isLiquid(state);
    final source = shapes.boxesOf(state);

    if (source == null) {
      // A state the registry does not know has no shape: no collider, and it is
      // not solid. The callback still decides the neighbourhood state.
      return BakedBlock(
        colliderIndex: null,
        solid: false,
        fullBlock: false,
        liquid: liquid,
        hasCallback: callback,
      );
    }

    // `if (shape.isEmpty()) return RapierVoxelColliderData.EMPTY;` — but only
    // after the liquid branch, which gives a liquid a unit cube whatever its
    // (usually empty) collision shape is.
    if (liquid) {
      return BakedBlock(
        colliderIndex: _register(state, const [VoxelBox.unit], liquid: true),
        solid: source.isNotEmpty,
        fullBlock: false,
        liquid: true,
        hasCallback: callback,
      );
    }

    if (source.isEmpty) {
      return BakedBlock(
        colliderIndex: null,
        solid: false,
        fullBlock: false,
        liquid: false,
        hasCallback: callback,
      );
    }

    // `shape.forAllBoxes`: each box is clamped to the unit cube, "so that fences
    // / walls do not have unexpected behaviour".
    final boxes = <VoxelBox>[];
    for (final box in source) {
      boxes.add(
        VoxelBox(
          math.max(box.minX, 0.0),
          math.max(box.minY, 0.0),
          math.max(box.minZ, 0.0),
          math.min(box.maxX, 1.0),
          math.min(box.maxY, 1.0),
          math.min(box.maxZ, 1.0),
        ),
      );
    }

    return BakedBlock(
      colliderIndex: _register(state, boxes, liquid: false),
      solid: true,
      fullBlock: _isFullBlock(source),
      liquid: false,
      hasCallback: callback,
    );
  }

  int _register(String state, List<VoxelBox> boxes, {required bool liquid}) {
    final table = properties;
    return register(
      BlockColliderData(
        friction: table?.frictionOf(state) ?? 1.0,
        volume: table?.volumeOf(state) ?? 1.0,
        restitution: table?.restitutionOf(state) ?? 0.0,
        fluid: liquid,
        boxes: boxes,
      ),
    );
  }

  /// `Block.isShapeFullBlock(shape)`: the shape is one box covering the block.
  static bool _isFullBlock(List<VoxelBox> boxes) =>
      boxes.length == 1 &&
      boxes.first.minX <= 0.0 &&
      boxes.first.minY <= 0.0 &&
      boxes.first.minZ <= 0.0 &&
      boxes.first.maxX >= 1.0 &&
      boxes.first.maxY >= 1.0 &&
      boxes.first.maxZ >= 1.0;
}

/// `PhysicsChunkTicketManager`'s section packer for the Jolt backend: the
/// packing `RapierPhysicsPipeline.handleChunkSectionAddition` does in Java.
///
/// One section becomes 4096 packed words, indexed `bx + (bz << 4) + (by << 8)`,
/// each `(colliderIndex + 1) << 16 | voxelState` ([packBlockState]); a zero word
/// is air.
final class JoltCollisionPacker implements PlotSectionPacker {
  /// The collider bakery and the state-to-shape lookup.
  final BlockColliderBakery bakery;

  /// The block states of the level, for the section and its neighbourhood.
  final AssemblyBlockHost blocks;

  JoltCollisionPacker({
    required JoltPhysicsPipeline pipeline,
    required BlockShapeSource shapes,
    required this.blocks,
    PhysicsBlockPropertiesTable? properties,
  }) : bakery = BlockColliderBakery(
         register: pipeline.registerVoxelCollider,
         shapes: shapes,
         properties: properties,
       );

  /// The number of sections packed so far.
  int packedSections = 0;

  @override
  List<int> packSection(PlotChunk chunk, int sectionIndex) {
    final packed = List<int>.filled(4096, 0);
    packedSections++;

    // `if (!section.hasOnlyAir())` (`RapierPhysicsPipeline.java:341`): "if it's
    // only air, all zeros will do".
    if (chunk.sectionHasOnlyAir(sectionIndex)) {
      return packed;
    }

    final (chunkX, chunkZ) = chunk.pos;
    final baseX = chunkX << 4;
    final baseY = chunk.sectionMinY(sectionIndex);
    final baseZ = chunkZ << 4;

    // Java reads every neighbour through its `LevelAccelerator`, which caches;
    // the port reads the section's whole 18³ neighbourhood once, so a host whose
    // reads cross a wasm boundary pays one bulk call (`BulkBlockHost`) instead of
    // thousands.
    final states = _readNeighbourhood(baseX, baseY, baseZ);

    for (var by = 0; by < 16; by++) {
      for (var bz = 0; bz < 16; bz++) {
        for (var bx = 0; bx < 16; bx++) {
          final x = baseX + bx;
          final y = baseY + by;
          final z = baseZ + bz;
          final state = _stateAt(states, x, y, z);
          final block = bakery.of(state);

          packed[bx + (bz << 4) + (by << 8)] = packBlockState(
            block.colliderIndex ?? -1,
            neighbourhoodState(states, x, y, z, block, bakery),
          );
        }
      }
    }
    return packed;
  }

  /// The states of the section and its six-neighbourhood, with the outside of
  /// the section included.
  Map<(int, int, int), String> _readNeighbourhood(int baseX, int baseY, int baseZ) {
    final positions = <(int, int, int)>[
      for (var dx = -1; dx <= 16; dx++)
        for (var dy = -1; dy <= 16; dy++)
          for (var dz = -1; dz <= 16; dz++) (baseX + dx, baseY + dy, baseZ + dz),
    ];

    final states = <(int, int, int), String>{};
    if (blocks case final BulkBlockHost bulk) {
      final read = bulk.readBlockStates(positions);
      for (var i = 0; i < positions.length && i < read.length; i++) {
        states[positions[i]] = '${read[i]}';
      }
      return states;
    }
    for (final position in positions) {
      states[position] = '${blocks.blockStateAt(position.$1, position.$2, position.$3)}';
    }
    return states;
  }

  static String _stateAt(Map<(int, int, int), String> states, int x, int y, int z) =>
      states[(x, y, z)] ?? 'minecraft:air';
}

/// `VoxelNeighborhoodState.getState` (`physics/chunk/VoxelNeighborhoodState.java:97-152`).
///
/// The state says how many of the block's six neighbours are full solid blocks;
/// the engine skips `empty` and `interior` blocks and treats the three "surface"
/// states the same (`insert_block_octree`, `lib.rs:761-793`).
int neighbourhoodState(
  Map<(int, int, int), String> states,
  int x,
  int y,
  int z,
  BakedBlock centre,
  BlockColliderBakery bakery,
) {
  if (centre.liquid || centre.hasCallback) {
    return VoxelPhysicsState.corner;
  }
  if (!centre.solid) {
    return VoxelPhysicsState.empty;
  }
  if (!centre.fullBlock) {
    return VoxelPhysicsState.corner;
  }

  var allSolid = true;
  var cornerSolid = true;
  var bothSidesCount = 0;

  for (var axis = 0; axis < 3; axis++) {
    final negative = _neighbour(states, x, y, z, axis, -1, bakery);
    final positive = _neighbour(states, x, y, z, axis, 1, bakery);
    final negativeSolid = negative.solid && negative.fullBlock;
    final positiveSolid = positive.solid && positive.fullBlock;

    if (!negativeSolid || !positiveSolid) {
      allSolid = false;
    }
    if (negativeSolid && positiveSolid) {
      cornerSolid = false;
      bothSidesCount++;
    }
  }

  if (allSolid) {
    return VoxelPhysicsState.interior;
  }
  if (bothSidesCount == 1) {
    return VoxelPhysicsState.edge;
  }
  if (cornerSolid) {
    return VoxelPhysicsState.corner;
  }
  return VoxelPhysicsState.face;
}

BakedBlock _neighbour(
  Map<(int, int, int), String> states,
  int x,
  int y,
  int z,
  int axis,
  int direction,
  BlockColliderBakery bakery,
) {
  final (nx, ny, nz) = switch (axis) {
    0 => (x + direction, y, z),
    1 => (x, y + direction, z),
    _ => (x, y, z + direction),
  };
  final state = states[(nx, ny, nz)];
  // A position outside the read neighbourhood is air, like a neighbour in an
  // unloaded chunk.
  if (state == null) {
    return const BakedBlock(
      colliderIndex: null,
      solid: false,
      fullBlock: false,
      liquid: false,
      hasCallback: false,
    );
  }
  return bakery.of(state);
}
