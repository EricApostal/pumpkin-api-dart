// Player-facing Create interactions that have to know about sub-levels: where
// a placed block faces, where a zapper beam starts, which toolbox or stock
// ticker a player can reach, and where glue selection looks.
//
// These are the pure computations; the item/block code calls them where Java
// redirected a read (`player.getLookAngle()`, `distanceToSqr`, `getBoundingBox`).
//
// Pure: no host imports.
//
// Java: `...create.tracks.TrackBlockMixin`, `...create.tracks.TrackBlockItemMixin`,
// `...create.tracks.TrackPlacementMixin`, `...create.vertical_gearbox.VerticalGearboxItemMixin`,
// `...create.zapper.ZapperItemMixin`, `...create.toolbox.ToolboxHandlerMixin`,
// `...create.super_glue.SuperGlueSelectionHandlerMixin`,
// `...create.stock_ticker.StockTickerInteractionHandlerMixin`,
// `...create.stock_ticker.EntityHatsMixin`, `...create.turntable.TurntableBlockMixin`.
//
// create's positions and block states are not exported from its public barrel
// yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:pumpkin_api/src/geometry.dart' show Vec3;

import '../../sublevel/api/sub_level_helper.dart';
import '../../sublevel/host/sub_level_host.dart';
import '../../sublevel/math/bounding_box.dart';
import '../../sublevel/math/pose.dart';
import '../../sublevel/math/vector.dart';
import '../../sublevel/model/sub_level.dart';

/// `TrackBlockMixin` / `TrackBlockItemMixin` / `TrackPlacementMixin`: the look
/// direction used to orient a placed track, in the frame of the clicked block.
abstract final class TrackPlacement {
  /// The player's look angle, rotated into the clicked block's sub-level.
  ///
  /// A track is laid out in the sub-level's frame, so a player standing on a
  /// ship and looking along it must place the track along the ship, not along
  /// the world direction they happen to face.
  static Vec3 lookAngleInSubLevel(SableLevel level, Pos clickedPos, Vec3 lookAngle) {
    final subLevel = SubLevelHelper.getContaining(level, clickedPos);
    if (subLevel == null) return lookAngle;

    final local = subLevel.logicalPose.transformNormalInverse(
      Vector3d(lookAngle.$1, lookAngle.$2, lookAngle.$3),
    );
    return (local.x, local.y, local.z);
  }

  /// `CurvedTrackDestroyPacketMixin`: the world block position of a track, for
  /// the packet's distance checks.
  static Pos worldBlockPos(SableLevel level, Pos plotPos) {
    final projected = SubLevelHelper.projectOutOfSubLevel(
      level,
      Vector3d(plotPos.$1 + 0.5, plotPos.$2 + 0.5, plotPos.$3 + 0.5),
    );
    return (projected.x.floor(), projected.y.floor(), projected.z.floor());
  }
}

/// `VerticalGearboxItemMixin`: the horizontal direction a vertical gearbox is
/// placed in, computed from the player's direction *inside* the sub-level.
abstract final class VerticalGearboxPlacement {
  /// The player's facing, rotated into [subLevel]'s frame.
  ///
  /// Java pushes the entity into the sub-level, reads `getDirection()` and pops
  /// it again; the rotation of a cardinal direction is the same operation, done
  /// without touching the entity.
  static (int, int, int) facingInSubLevel(SubLevel? subLevel, (int, int, int) playerFacing) {
    if (subLevel == null) return playerFacing;

    final local = subLevel.logicalPose.transformNormalInverse(
      Vector3d(playerFacing.$1.toDouble(), playerFacing.$2.toDouble(), playerFacing.$3.toDouble()),
    );
    return (_round(local.x), _round(local.y), _round(local.z));
  }

  static int _round(double value) => value.round();
}

/// `ZapperItemMixin`: the hit location of a zapper beam, projected out of the
/// sub-level the clicked block is in.
abstract final class ZapperBeam {
  /// The world location the beam is drawn from/to.
  static Vec3 projectHitLocation(SableLevel level, Vec3 hitLocation) {
    final projected = SubLevelHelper.projectOutOfSubLevel(
      level,
      Vector3d(hitLocation.$1, hitLocation.$2, hitLocation.$3),
    );
    return (projected.x, projected.y, projected.z);
  }
}

/// `ToolboxHandlerMixin`: which toolboxes a player can reach.
abstract final class ToolboxRange {
  /// `withinRange(player, box)`: the toolbox is in the player's level and within
  /// [maxRange], measured across sub-levels.
  static bool withinRange(
    SableLevel level,
    Vec3 playerPosition,
    Pos boxPos,
    double maxRange,
  ) => _distanceSquared(level, playerPosition, boxPos) < maxRange * maxRange;

  /// `getNearest`: the toolboxes within range, nearest first, at most
  /// [maxAmount].
  ///
  /// [toolboxes] is the world's toolbox map; [isInitialized] filters out the
  /// boxes that are not fully loaded yet.
  static List<Pos> nearest(
    SableLevel level,
    Vec3 playerPosition,
    Iterable<Pos> toolboxes,
    double maxRange,
    int maxAmount, {
    bool Function(Pos pos)? isInitialized,
  }) {
    final inRange = <(double, Pos)>[];
    for (final pos in toolboxes) {
      final distance = _distanceSquared(level, playerPosition, pos);
      if (distance >= maxRange * maxRange) continue;
      if (isInitialized != null && !isInitialized(pos)) continue;
      inRange.add((distance, pos));
    }

    inRange.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final entry in inRange.take(maxAmount)) entry.$2];
  }

  /// `ToolboxHandlerMixin.sable$getDistance`: the box centre (x + 0.5, y, z + 0.5)
  /// against the player, across sub-levels.
  static double _distanceSquared(SableLevel level, Vec3 playerPosition, Pos boxPos) =>
      SubLevelHelper.distanceSquaredWithSubLevelsTo(
        level,
        Vector3d(playerPosition.$1, playerPosition.$2, playerPosition.$3),
        boxPos.$1 + 0.5,
        boxPos.$2.toDouble(),
        boxPos.$3 + 0.5,
      );
}

/// `SuperGlueSelectionHandlerMixin` / `SuperGlueRemovalPacketMixin` /
/// `SuperGlueEntityMixin`: glue boxes and the range checks around them.
abstract final class SuperGlueSelection {
  /// `sable$projectBoundingBox`: a glue box projected out of its sub-level, so
  /// the selection ray and the outline see it where it is.
  static Aabb projectedBounds(Aabb box, Pose3dc? pose) {
    if (pose == null) return box;

    final projected = BoundingBox3d.fromAabb(box).transform(pose);
    return Aabb(projected.minX, projected.minY, projected.minZ, projected.maxX, projected.maxY, projected.maxZ);
  }

  /// `SuperGlueRemovalPacketMixin.sable$distanceSquared`: the squared distance
  /// from the player to the glue box, across sub-levels.
  static double distanceSquared(SableLevel level, Vec3 playerPosition, Vec3 target) =>
      SubLevelHelper.distanceSquaredWithSubLevels(
        level,
        Vector3d(playerPosition.$1, playerPosition.$2, playerPosition.$3),
        Vector3d(target.$1, target.$2, target.$3),
      );

  /// Whether the player is close enough to remove the glue.
  static bool withinRemovalRange(
    SableLevel level,
    Vec3 playerPosition,
    Vec3 gluePosition,
    double range,
  ) => distanceSquared(level, playerPosition, gluePosition) < range * range;
}

/// `StockTickerInteractionHandlerMixin` / `EntityHatsMixin`: which entity's
/// position decides the stock ticker a player is using.
abstract final class StockTickerLookup {
  /// The position used for the ticker lookup: the root vehicle's when the player
  /// rides something on a sub-level, the entity's own otherwise.
  ///
  /// A player riding a ship is at the ship's position, which the host reports in
  /// the plot; the vehicle is the entity that carries them, so it is the one
  /// whose chunk decides which ticker they reach.
  static Pos tickerPosition({
    required bool Function(Vec3 position) isOnSubLevel,
    required Vec3 entityPosition,
    required Vec3 vehiclePosition,
    required bool hasVehicle,
  }) {
    final position = hasVehicle && isOnSubLevel(vehiclePosition) ? vehiclePosition : entityPosition;
    return (position.$1.floor(), position.$2.floor(), position.$3.floor());
  }
}

/// `TurntableBlockMixin`: the turntable's centre and height in the world.
abstract final class TurntableGeometry {
  /// The world position of the centre of the turntable block.
  static Vec3 centerInWorld(SableLevel level, Pos pos) {
    final projected = SubLevelHelper.projectOutOfSubLevel(
      level,
      Vector3d(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5),
    );
    return (projected.x, projected.y, projected.z);
  }

  /// The world y of the turntable's lower corner, for the `entityInside` check.
  static double worldY(SableLevel level, Pos pos) {
    final projected = SubLevelHelper.projectOutOfSubLevel(
      level,
      Vector3d(pos.$1.toDouble(), pos.$2.toDouble(), pos.$3.toDouble()),
    );
    return projected.y;
  }
}
