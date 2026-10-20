// A port of Sable's buoyancy and drag: `buoyancy.rs` plus the pair search of
// `algo.rs` (`sable_rapier/src/main/rust/rapier/src/`).
//
// The physics engine is not involved: Sable computes the forces itself, resets
// the body's forces and re-applies them every tick (`lib.rs:492-509` calls
// `rope::tick`, `joints::tick` and `compute_buoyancy` before each step). This
// file therefore produces world-space point forces and leaves applying them to
// the caller.
//
// Difference from the Rust original: `find_collision_pairs` (`algo.rs:17-...`)
// walks the sub-level's octree and the level's liquid octree to *prune* the
// pair search. The octree is a broadphase structure (`marten/src/octree.rs`),
// not part of the semantics: a pair is a (static fluid block, sub-level block)
// whose boxes overlap. The direct sweep below visits the cells around each
// sub-level block and lets the exact AABB overlap test decide, which yields the
// same forces without the octree.
//
// Pure: no host imports.
import 'package:sable/sable.dart'
    show BoundingBox3ic, Pose3dc, Vector3d;

import '../jolt/voxel.dart';

/// One world-space force applied at a world-space point.
final class BuoyancyForce {
  /// Where the force acts, in world space.
  final Vector3d point;

  /// The force, in world space.
  final Vector3d force;

  BuoyancyForce(this.point, this.force);

  @override
  String toString() => 'BuoyancyForce($point, $force)';
}

/// `compute_buoyancy` (`buoyancy.rs:16-131`).
///
/// [bodyBlocks] are the sub-level's solid blocks in plot coordinates, [pose] is
/// the body's pose (its position is the center of mass, as in Rapier) and
/// [centerOfMass] is the tracked center of mass in plot coordinates.
///
/// [velocityAt] returns the body's world-space velocity at a world point
/// (`RigidBody::velocity_at_point`, `buoyancy.rs:143-152`).
List<BuoyancyForce> computeBuoyancy({
  required Pose3dc pose,
  required Vector3d centerOfMass,
  required BoundingBox3ic localBounds,
  required List<(BlockPos, int)> bodyBlocks,
  required BlockColliderRegistry colliders,
  required BlockSource world,
  required Vector3d Function(Vector3d point) velocityAt,
}) {
  // `(local_bounds_max - local_bounds_min).element_sum() < 10`
  // (`buoyancy.rs:69`): small bodies are sampled at eight sub-points so a
  // coarse block does not create a single unbalanced force.
  final complex =
      (localBounds.maxX - localBounds.minX) +
          (localBounds.maxY - localBounds.minY) +
          (localBounds.maxZ - localBounds.minZ) <
      10;

  final forces = <BuoyancyForce>[];

  for (final ((blockX, blockY, blockZ), blockPacked) in bodyBlocks) {
    // The lift strength is the sub-level block's own collider volume
    // (`buoyancy.rs:112-129`: `voxel_collider_data.volume` of `dynamic_pos`).
    final bodyCollider = colliders[colliderIndexOfPacked(blockPacked)];
    if (bodyCollider == null) {
      continue;
    }

    // The world cells the block can touch. `find_collision_pairs` uses the
    // node's circumsphere (`algo.rs:84-90`); the block's world AABB expanded by
    // the largest sample half-extent covers the same cells.
    final (minX, minY, minZ, maxX, maxY, maxZ) = _worldBounds(
      pose,
      centerOfMass,
      blockX,
      blockY,
      blockZ,
    );

    for (var wx = minX; wx <= maxX; wx++) {
      for (var wy = minY; wy <= maxY; wy++) {
        for (var wz = minZ; wz <= maxZ; wz++) {
          final worldPacked = world.blockAt(wx, wy, wz);
          final worldCollider = colliders[colliderIndexOfPacked(worldPacked)];
          if (worldCollider == null || !worldCollider.fluid) {
            continue;
          }
          _accumulateBlock(
            forces: forces,
            pose: pose,
            centerOfMass: centerOfMass,
            blockX: blockX,
            blockY: blockY,
            blockZ: blockZ,
            worldX: wx,
            worldY: wy,
            worldZ: wz,
            complex: complex,
            liftStrength: bodyCollider.volume,
            velocityAt: velocityAt,
          );
        }
      }
    }
  }

  return forces;
}

/// One (static fluid block, sub-level block) pair: `do_drag` and `do_float`
/// (`buoyancy.rs:136-190`).
void _accumulateBlock({
  required List<BuoyancyForce> forces,
  required Pose3dc pose,
  required Vector3d centerOfMass,
  required int blockX,
  required int blockY,
  required int blockZ,
  required int worldX,
  required int worldY,
  required int worldZ,
  required bool complex,
  required double liftStrength,
  required Vector3d Function(Vector3d point) velocityAt,
}) {
  // `local_pos = dynamic_pos + 0.5 - center_of_mass` (`buoyancy.rs:70-71`).
  final baseX = blockX + 0.5 - centerOfMass.x;
  final baseY = blockY + 0.5 - centerOfMass.y;
  final baseZ = blockZ + 0.5 - centerOfMass.z;

  final samples = complex ? 8 : 1;
  final size = complex ? 0.25 : 0.5;

  for (var i = 0; i < samples; i++) {
    // `i & 1`, `(i >> 1) & 1`, `(i >> 2) & 1` mapped to -1/+1
    // (`buoyancy.rs:72-80`).
    final ox = complex ? ((i & 1) * 2 - 1) * 0.25 : 0.0;
    final oy = complex ? (((i >> 1) & 1) * 2 - 1) * 0.25 : 0.0;
    final oz = complex ? (((i >> 2) & 1) * 2 - 1) * 0.25 : 0.0;

    final point = _toWorld(
      pose,
      Vector3d(baseX + ox, baseY + oy, baseZ + oz),
    );

    final volume = overlapVolume(
      point.x - size,
      point.y - size,
      point.z - size,
      point.x + size,
      point.y + size,
      point.z + size,
      worldX.toDouble(),
      worldY.toDouble(),
      worldZ.toDouble(),
      worldX + 1.0,
      worldY + 1.0,
      worldZ + 1.0,
    );
    if (volume <= 0.0) {
      continue;
    }

    // Drag: `-velo * 1.7 * volume * strength` at the point
    // (`buoyancy.rs:150-152`).
    final velocity = velocityAt(point);
    final drag = velocity.mul(-1.7 * volume);

    // Lift: `10.5 * volume * strength` along +Y (`buoyancy.rs:187-189`).
    final lift = Vector3d(0.0, 10.5 * volume * liftStrength, 0.0);

    forces.add(
      BuoyancyForce(
        Vector3d(point.x, point.y, point.z),
        Vector3d(drag.x + lift.x, drag.y + lift.y, drag.z + lift.z),
      ),
    );
  }
}

/// `body.position().transform_point(point)` for a center-of-mass relative
/// [local] point: `position + rotation * local` (`buoyancy.rs:143-152`).
///
/// This deliberately does not use [Pose3dc.transformPosition]: that subtracts
/// the pose's rotation point, while `buoyancy.rs` already works in
/// center-of-mass relative coordinates.
Vector3d _toWorld(Pose3dc pose, Vector3d local) =>
    pose.orientation().transform(local, Vector3d()).add(pose.position());

/// The world-space AABB of a block's unit cube under [pose], expanded by the
/// largest sample half-extent and converted to the cell range it can touch.
(int, int, int, int, int, int) _worldBounds(
  Pose3dc pose,
  Vector3d centerOfMass,
  int blockX,
  int blockY,
  int blockZ,
) {
  var minX = double.infinity;
  var minY = double.infinity;
  var minZ = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  var maxZ = double.negativeInfinity;

  for (var corner = 0; corner < 8; corner++) {
    final world = _toWorld(
      pose,
      Vector3d(
        blockX + (corner & 1) - centerOfMass.x,
        blockY + ((corner >> 1) & 1) - centerOfMass.y,
        blockZ + ((corner >> 2) & 1) - centerOfMass.z,
      ),
    );
    if (world.x < minX) minX = world.x;
    if (world.y < minY) minY = world.y;
    if (world.z < minZ) minZ = world.z;
    if (world.x > maxX) maxX = world.x;
    if (world.y > maxY) maxY = world.y;
    if (world.z > maxZ) maxZ = world.z;
  }

  const sampleExtent = 0.5;
  return (
    (minX - sampleExtent).floor(),
    (minY - sampleExtent).floor(),
    (minZ - sampleExtent).floor(),
    (maxX + sampleExtent).ceil(),
    (maxY + sampleExtent).ceil(),
    (maxZ + sampleExtent).ceil(),
  );
}
