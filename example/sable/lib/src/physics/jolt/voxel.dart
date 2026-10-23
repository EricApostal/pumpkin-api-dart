// The voxel half of Sable's physics world: the block collider registry and the
// chunk-section block store.
//
// `BlockColliderData` (`sable_rapier/src/main/rust/marten/src/level.rs:81-100`)
// holds, per block state, collision boxes in 0..1 voxel space plus the
// buoyancy/contact properties. `VoxelColliderMap` (`voxel_collider.rs:12-31`)
// keeps them in a registry; the packed block state stores `index + 1` in its
// high half so 0 means "no collider" (`voxel_collider.rs:88-92`).
//
// Pure: no host imports.
import '../../../sable.dart' show Vector3d;

/// `VoxelPhysicsState` (`marten/src/level.rs:137-151`), the low half of a
/// packed block state.
abstract final class VoxelPhysicsState {
  /// No neighbouring block: the block is alone.
  static const int empty = 0;

  /// One neighbouring block.
  static const int face = 1;

  /// Two neighbours (an edge).
  static const int edge = 2;

  /// Three neighbours (a corner).
  static const int corner = 3;

  /// Fully enclosed; contributes no collision boxes.
  static const int interior = 4;
}

/// One collision box of a block, in 0..1 voxel space.
final class VoxelBox {
  final double minX;
  final double minY;
  final double minZ;
  final double maxX;
  final double maxY;
  final double maxZ;

  const VoxelBox(
    this.minX,
    this.minY,
    this.minZ,
    this.maxX,
    this.maxY,
    this.maxZ,
  );

  /// The full block.
  static const VoxelBox unit = VoxelBox(0.0, 0.0, 0.0, 1.0, 1.0, 1.0);
}

/// `BlockColliderData`: the physics data of one block state.
final class BlockColliderData {
  /// The friction multiplier applied to contacts with this block
  /// (`hooks.rs:23-120`).
  final double friction;

  /// The buoyancy volume used by `do_float` (`buoyancy.rs:184-188`).
  final double volume;

  /// The restitution applied to contacts with this block.
  final double restitution;

  /// Whether buoyancy treats this block as a fluid (`is_fluid`,
  /// `buoyancy.rs:59-60`).
  final bool fluid;

  /// The collision boxes of the block.
  final List<VoxelBox> boxes;

  const BlockColliderData({
    this.friction = 1.0,
    this.volume = 0.0,
    this.restitution = 0.0,
    this.fluid = false,
    this.boxes = const [VoxelBox.unit],
  });

  /// A block with no collision boxes: it is never solid (`insert_block_octree`
  /// requires a non-empty box list, `lib.rs:761-793`).
  static const BlockColliderData none = BlockColliderData(boxes: []);
}

/// The process-wide registry of block colliders, mirroring Rapier's global
/// `voxel_collider_map` (`voxel_collider.rs:12-31`).
///
/// Named `BlockCollider*` rather than `VoxelCollider*` because `sable` exports
/// `api/physics/collider/voxel_collider_data.dart` (`VoxelColliderData`), the
/// *builder* the block bakery fills in; this is the engine-side record.
final class BlockColliderRegistry {
  final List<BlockColliderData> _colliders = [];

  /// `newVoxelCollider`: registers [data] and returns its index.
  int add(BlockColliderData data) {
    _colliders.add(data);
    return _colliders.length - 1;
  }

  /// The collider registered at [index], or `null` when out of range.
  BlockColliderData? operator [](int index) =>
      index >= 0 && index < _colliders.length ? _colliders[index] : null;

  /// The number of registered colliders.
  int get length => _colliders.length;
}

/// Packs a registry index and a [VoxelPhysicsState] into the word Sable sends
/// to the engine (`RapierPhysicsPipeline.packBlockState`,
/// `sable/.../RapierPhysicsPipeline.java:353-356`).
///
/// [colliderIndex] is the *registry index*; the packed value stores
/// `index + 1`, so `-1` (or any negative) packs as "no collider".
int packBlockState(int colliderIndex, int voxelState) =>
    ((colliderIndex + 1) << 16) | (voxelState & 0xFFFF);

/// The collider index stored in a packed block state, or `-1` when none.
int colliderIndexOfPacked(int packed) => (packed >> 16) - 1;

/// The voxel physics state stored in a packed block state.
int voxelStateOfPacked(int packed) => packed & 0xFFFF;

/// Whether a packed block state contributes collision boxes
/// (`isSolid` in `lib.rs:761-793`: not empty, not interior, has a collider, and
/// that collider has at least one box).
bool isSolidBlock(int packed, BlockColliderRegistry colliders) {
  final state = voxelStateOfPacked(packed);
  if (state == VoxelPhysicsState.empty || state == VoxelPhysicsState.interior) {
    return false;
  }
  final collider = colliders[colliderIndexOfPacked(packed)];
  return collider != null && collider.boxes.isNotEmpty;
}

/// A block's absolute position.
typedef BlockPos = (int x, int y, int z);

/// The block data of a set of chunk sections, keyed by section coordinates.
///
/// Sections hold 4096 packed block states indexed `x + (z << 4) + (y << 8)`,
/// the layout `RapierPhysicsPipeline.handleChunkSectionAddition` builds
/// (`sable/.../RapierPhysicsPipeline.java:335-356`).
final class BlockSectionStore {
  final Map<(int, int, int), List<int>> _sections = {};

  /// The number of stored sections.
  int get sectionCount => _sections.length;

  /// Stores (or replaces) one section.
  void setSection(int x, int y, int z, List<int> states) {
    if (states.length != 4096) {
      throw ArgumentError.value(
        states.length,
        'states',
        'a chunk section holds 4096 blocks',
      );
    }
    _sections[(x, y, z)] = List<int>.of(states, growable: false);
  }

  /// Removes one section, if present.
  void removeSection(int x, int y, int z) => _sections.remove((x, y, z));

  /// Whether a section is stored.
  bool hasSection(int x, int y, int z) => _sections.containsKey((x, y, z));

  /// The packed block state at an absolute block position, or 0 when the
  /// section is not loaded.
  int blockAt(int x, int y, int z) {
    final section = _sections[(x >> 4, y >> 4, z >> 4)];
    if (section == null) {
      return 0;
    }
    return section[(x & 15) + ((z & 15) << 4) + ((y & 15) << 8)];
  }

  /// Replaces one block. A block in an unloaded section is ignored, like
  /// `changeBlock` (`lib.rs:995-1107`), which only writes into loaded chunks.
  void setBlock(int x, int y, int z, int packed) {
    final section = _sections[(x >> 4, y >> 4, z >> 4)];
    if (section == null) {
      return;
    }
    section[(x & 15) + ((z & 15) << 4) + ((y & 15) << 8)] = packed;
  }

  /// Visits every block of every section.
  void forEachBlock(void Function(int x, int y, int z, int packed) visit) {
    for (final entry in _sections.entries) {
      final (sx, sy, sz) = entry.key;
      final states = entry.value;
      for (var i = 0; i < states.length; i++) {
        final packed = states[i];
        if (packed == 0) {
          continue;
        }
        visit(
          (sx << 4) + (i & 15),
          (sy << 4) + (i >> 8),
          (sz << 4) + ((i >> 4) & 15),
          packed,
        );
      }
    }
  }

  /// The solid blocks of this store, in absolute block coordinates, each with
  /// its packed block state.
  ///
  /// Buoyancy needs the packed state because the lift strength is the *body's*
  /// block collider volume (`buoyancy.rs:112-129`, which reads the sub-level's
  /// chunk, not the world's).
  List<(BlockPos, int)> solidBlocks(BlockColliderRegistry colliders) {
    final blocks = <(BlockPos, int)>[];
    forEachBlock((x, y, z, packed) {
      if (isSolidBlock(packed, colliders)) {
        blocks.add(((x, y, z), packed));
      }
    });
    return blocks;
  }
}

/// A world-space point, used by the buoyancy port.
typedef WorldPoint = (double x, double y, double z);

/// A read-only block source: the static level, or one sub-level's plot.
abstract interface class BlockSource {
  /// The packed block state at an absolute block position, or 0 when absent.
  int blockAt(int x, int y, int z);
}

/// Adapts a [BlockSectionStore] to [BlockSource].
final class StoreBlockSource implements BlockSource {
  final BlockSectionStore store;

  const StoreBlockSource(this.store);

  @override
  int blockAt(int x, int y, int z) => store.blockAt(x, y, z);
}

/// A vector helper used by the buoyancy port: the AABB overlap volume of two
/// boxes, or 0 when they do not overlap.
double overlapVolume(
  double aMinX,
  double aMinY,
  double aMinZ,
  double aMaxX,
  double aMaxY,
  double aMaxZ,
  double bMinX,
  double bMinY,
  double bMinZ,
  double bMaxX,
  double bMaxY,
  double bMaxZ,
) {
  final dx = _min(aMaxX, bMaxX) - _max(aMinX, bMinX);
  if (dx <= 0.0) {
    return 0.0;
  }
  final dy = _min(aMaxY, bMaxY) - _max(aMinY, bMinY);
  if (dy <= 0.0) {
    return 0.0;
  }
  final dz = _min(aMaxZ, bMaxZ) - _max(aMinZ, bMinZ);
  if (dz <= 0.0) {
    return 0.0;
  }
  return dx * dy * dz;
}

double _min(double a, double b) => a < b ? a : b;

double _max(double a, double b) => a > b ? a : b;

/// The center of a unit block, as a [Vector3d].
Vector3d blockCenter(int x, int y, int z) =>
    Vector3d(x + 0.5, y + 0.5, z + 0.5);
