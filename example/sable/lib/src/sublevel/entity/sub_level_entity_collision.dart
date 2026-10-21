// Entity collision with sub-levels.
//
// Java patches `Entity.move` and resolves the motion against the voxel shapes
// of every sub-level the entity overlaps (`SubLevelEntityCollision`, 689 lines:
// oriented-box sweeps, step-up, scaffolding, bounce). A plugin cannot patch the
// host's entities, so the port flips the direction: it hands the host a set of
// world-space boxes through `entity-collision.set-entity-collision-boxes`, and
// the host clips its own entities (and pushes players out of the boxes) with
// them. The boxes are axis aligned in world space, so a rotated sub-level is
// represented by each block's world-aligned bounds — the host never rotates a
// box, by contract.
//
// The pieces of the Java algorithm that stay on the plugin side are the ones
// that *produce* geometry, and they are here:
//
// * `collectBoxes`: the world-space bounds of the blocks of every sub-level,
// * `transformEntityBoundsCenter` / `transformEntityBoundingBox`: the anchor and
//   up-vector corrections an entity needs when it stands on a rotated
//   sub-level,
// * `getHitBoxYaw`: the yaw that keeps an entity's hitbox axis-aligned with the
//   sub-level's snapped orientation.
//
// Pure: no host imports.
import 'dart:math' as math;

import '../host/sub_level_host.dart';
import '../math/bounding_box.dart';
import '../math/pose.dart';
import '../math/vector.dart';
import '../model/server_sub_level.dart';
import '../model/server_sub_level_container.dart';
import '../model/sub_level_container.dart';
import '../util/sable_math_utils.dart';

/// Where the collision boxes go: the host's `entity-collision` interface.
abstract interface class EntityCollisionSink {
  /// `set-entity-collision-boxes(world, boxes)`.
  void setEntityCollisionBoxes(String dimensionId, List<BoundingBox3d> boxes);

  /// `clear-entity-collision-boxes(world)`.
  void clearEntityCollisionBoxes(String dimensionId);
}

/// The collision boxes of one sub-level, in world space.
final class SubLevelCollisionBoxes {
  final ServerSubLevel subLevel;
  final List<BoundingBox3d> boxes;

  SubLevelCollisionBoxes(this.subLevel, this.boxes);
}

/// Builds and publishes the collision boxes of sub-levels.
abstract final class SubLevelEntityCollision {
  /// The world-space bounds of every non-air block of [subLevel].
  ///
  /// With [perSection] the blocks of one chunk section are merged into one
  /// conservative box (cheap, and enough to stop an entity walking through a
  /// hull); the default is one box per block, which is exact for the host's
  /// axis-aligned test.
  static List<BoundingBox3d> boxesOf(
    ServerSubLevel subLevel, {
    bool perSection = false,
    double inflate = 0.0,
  }) {
    final plot = subLevel.getPlot();
    final pose = subLevel.logicalPose;
    final boxes = <BoundingBox3d>[];

    for (final holder in plot.getLoadedChunks()) {
      final chunk = holder.getChunk();
      final chunkX = holder.pos.$1 << 4;
      final chunkZ = holder.pos.$2 << 4;

      for (var sectionIndex = 0; sectionIndex < chunk.sectionsCount; sectionIndex++) {
        if (chunk.sectionHasOnlyAir(sectionIndex)) continue;
        final sectionMinY = chunk.sectionMinY(sectionIndex);

        BoundingBox3d? sectionBox;
        for (var y = 0; y < 16; y++) {
          for (var x = 0; x < 16; x++) {
            for (var z = 0; z < 16; z++) {
              if (chunk.blockAt(x, y + sectionMinY, z) == 'minecraft:air') continue;

              final worldX = (chunkX + x).toDouble();
              final worldY = (y + sectionMinY).toDouble();
              final worldZ = (chunkZ + z).toDouble();

              if (perSection) {
                final box = sectionBox ??= BoundingBox3d.full(
                  worldX,
                  worldY,
                  worldZ,
                  worldX + 1,
                  worldY + 1,
                  worldZ + 1,
                );
                box.expandToValues(worldX + 1, worldY + 1, worldZ + 1);
              } else {
                boxes.add(_worldBox(pose, worldX, worldY, worldZ, inflate));
              }
            }
          }
        }

        if (perSection && sectionBox != null) {
          boxes.add(_transformBox(pose, sectionBox, inflate));
        }
      }
    }

    return boxes;
  }

  /// The boxes of every sub-level of [container], grouped by sub-level.
  static List<SubLevelCollisionBoxes> collectBoxes(
    ServerSubLevelContainer container, {
    bool perSection = false,
    double inflate = 0.0,
  }) {
    final result = <SubLevelCollisionBoxes>[];
    for (final subLevel in container.serverSubLevels()) {
      if (subLevel.isRemoved()) continue;
      result.add(
        SubLevelCollisionBoxes(
          subLevel,
          boxesOf(subLevel, perSection: perSection, inflate: inflate),
        ),
      );
    }
    return result;
  }

  /// Publishes the boxes of every sub-level of [container] to [sink], or clears
  /// them when nothing is left.
  ///
  /// Call once per tick (or whenever a sub-level moves); the host replaces the
  /// plugin's boxes on every call.
  static void publish(
    ServerSubLevelContainer container,
    EntityCollisionSink sink, {
    bool perSection = false,
    double inflate = 0.0,
  }) {
    final dimension = container.level.dimensionId;
    final boxes = <BoundingBox3d>[];
    for (final subLevel in container.serverSubLevels()) {
      if (subLevel.isRemoved()) continue;
      boxes.addAll(boxesOf(subLevel, perSection: perSection, inflate: inflate));
    }

    if (boxes.isEmpty) {
      sink.clearEntityCollisionBoxes(dimension);
    } else {
      sink.setEntityCollisionBoxes(dimension, boxes);
    }
  }

  /// `transformEntityBoundsCenter`: corrects the entity's centre for the
  /// anchor offset of a rotated sub-level.
  static void transformEntityBoundsCenter(
    Quaterniond? customOrientation,
    Vector3d center,
    double eyeHeight,
    double boundingBoxHeight,
  ) {
    if (customOrientation == null) return;

    final offset = Vector3d(0.0, eyeHeight - boundingBoxHeight / 2.0, 0.0);
    final transformed = Vector3d();
    customOrientation.transform(offset, transformed);
    center.add(offset).sub(transformed);
  }

  /// `transformEntityBoundingBox`: rotates the entity's bounds and up vector
  /// into the sub-level's frame.
  static void transformEntityBoundingBox(
    Quaterniond? customOrientation,
    Quaterniond bounds,
    Vector3d upDir,
  ) {
    if (customOrientation == null) return;
    bounds.premul(customOrientation);
    customOrientation.transform(upDir, upDir);
  }

  /// `getHitBoxYaw(subLevelPose)`: the yaw that aligns the entity's hitbox with
  /// the sub-level's nearest grid orientation.
  ///
  /// `SubLevelEntityCollision.java:505-513` snaps to `GridQuats.REAL`, not to
  /// every grid quaternion: only the identity, the three quarter turns and the
  /// corner rotation keep an entity's hitbox upright.
  static double getHitBoxYaw(Pose3dc subLevelPose) {
    final orientation = subLevelPose.orientation();
    final snapped = SableMathUtils.clampQuaternionToGrid(
      orientation,
      GridQuats.real.quaternions,
      Quaterniond(),
    );
    final relative = Quaterniond.copy(orientation).div(snapped, Quaterniond());

    final dot = relative.y;
    return -2.0 * math.atan2(-dot, relative.w);
  }

  /// The world-space bounds of one block, after the sub-level transform.
  static BoundingBox3d _worldBox(Pose3dc pose, double x, double y, double z, double inflate) =>
      _transformBox(
        pose,
        BoundingBox3d.full(x, y, z, x + 1.0, y + 1.0, z + 1.0),
        inflate,
      );

  /// Transforms the eight corners of [box] by [pose] and returns their
  /// world-aligned bounds, inflated by [inflate].
  static BoundingBox3d _transformBox(Pose3dc pose, BoundingBox3d box, double inflate) {
    final matrix = pose.bakeIntoMatrix(Matrix4d());
    final result = BoundingBox3d();
    var first = true;

    for (var i = 0; i < 8; i++) {
      final corner = Vector3d(
        i & 1 == 0 ? box.minX : box.maxX,
        i & 2 == 0 ? box.minY : box.maxY,
        i & 4 == 0 ? box.minZ : box.maxZ,
      );
      final world = matrix.transformPosition(corner, corner);
      if (first) {
        result.setValues(world.x, world.y, world.z, world.x, world.y, world.z);
        first = false;
      } else {
        result.expandToValues(world.x, world.y, world.z);
      }
    }

    return inflate == 0 ? result : result.expand(inflate);
  }

  /// The sub-levels whose global bounds contain [position] in [level].
  static Iterable<ServerSubLevel> overlapping(
    SableLevel level,
    Vector3d position,
  ) {
    final container = SubLevelContainer.of(level);
    if (container is! ServerSubLevelContainer) return const [];
    return container
        .serverSubLevels()
        .where((subLevel) => !subLevel.isRemoved() && subLevel.boundingBox.contains(position));
  }
}
