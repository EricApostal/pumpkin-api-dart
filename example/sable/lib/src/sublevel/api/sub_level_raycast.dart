// The block ray the `/sable` selector's `@v` needs: `Entity.pick` as far as a
// plugin can see it.
//
// Java's `@v` is `source.getEntity().pick(100.0, 1.0f, true)` followed by
// `Sable.HELPER.getContaining(level, hit.getBlockPos())`. Inside a sub-level the
// entity's blocks *are* the plot's blocks (Veil redirects the entity's chunk
// lookups into the plot), so that single ray sees the ship. The port's plot
// chunks live in memory (`host_gap.dart` `clip-raycast`: "the plugin can
// ray-trace the plot chunks itself"), so the ray is taken here instead of
// through the host's own block ray.
//
// Pure: no host imports.
import 'dart:math' as math;

import '../math/vector.dart';
import '../model/server_sub_level.dart';
import '../model/sub_level_container.dart';

/// Where a ray met a loaded plot block.
final class SubLevelRaycastHit {
  /// The sub-level whose plot was hit.
  final ServerSubLevel subLevel;

  /// The block that was hit, in global plot coordinates.
  final (int, int, int) blockPos;

  /// The exact position of the hit.
  final Vector3d position;

  /// The distance from the ray's origin, in blocks.
  final double distance;

  const SubLevelRaycastHit(
    this.subLevel,
    this.blockPos,
    this.position,
    this.distance,
  );
}

/// Ray tracing over the plot blocks of a [SubLevelContainer].
abstract final class SubLevelRaycast {
  /// How far one step of the walk is, in blocks.
  ///
  /// The blocks are a voxel grid, so a quarter of a block cannot step over one,
  /// and each step costs one chunk and one block lookup.
  static const double step = 0.25;

  /// The first non-air plot block along `[start], [start] + [direction] * t`,
  /// `null` when the ray meets none within [maxDistance].
  ///
  /// Fluids count as hits, as `Entity.pick(_, _, true)` does; a plot chunk that
  /// was never loaded is air, like the host's own unloaded chunk.
  static SubLevelRaycastHit? pick(
    SubLevelContainer container,
    Vector3d start,
    Vector3d direction,
    double maxDistance,
  ) {
    final length = direction.length;
    if (length == 0.0 || maxDistance <= 0.0) return null;

    final stepX = direction.x / length * step;
    final stepY = direction.y / length * step;
    final stepZ = direction.z / length * step;

    var x = start.x;
    var y = start.y;
    var z = start.z;
    (int, int, int)? previous;

    for (var distance = 0.0; distance <= maxDistance; distance += step) {
      if (distance > 0.0) {
        x += stepX;
        y += stepY;
        z += stepZ;
      }

      final blockX = x.floor();
      final blockY = y.floor();
      final blockZ = z.floor();
      final block = (blockX, blockY, blockZ);
      if (block == previous) continue;
      previous = block;

      final plot = container.getPlot(blockX >> 4, blockZ >> 4);
      final subLevel = plot?.getSubLevel();
      if (plot == null || subLevel is! ServerSubLevel) continue;

      // The plot's chunks are addressed by the plot's local chunk position and
      // the chunk contract takes the absolute y (`host/sub_level_host.dart`).
      final chunk = plot.getChunk(plot.toLocal((blockX >> 4, blockZ >> 4)));
      if (chunk == null) continue;

      final key = chunk.blockAt(blockX & 15, blockY, blockZ & 15);
      if (key == 'minecraft:air' ||
          key == 'minecraft:cave_air' ||
          key == 'minecraft:void_air') {
        continue;
      }

      return SubLevelRaycastHit(
        subLevel,
        block,
        Vector3d(x, y, z),
        math.min(distance, maxDistance),
      );
    }
    return null;
  }

  /// The unit vector an entity with [yaw] and [pitch] degrees looks along
  /// (`Entity#getViewVector`).
  static Vector3d lookVector(double yaw, double pitch) {
    final yawRadians = yaw * math.pi / 180.0;
    final pitchRadians = pitch * math.pi / 180.0;
    final cosPitch = math.cos(pitchRadians);
    return Vector3d(
      -math.sin(yawRadians) * cosPitch,
      -math.sin(pitchRadians),
      math.cos(yawRadians) * cosPitch,
    );
  }
}