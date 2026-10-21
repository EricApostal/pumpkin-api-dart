// `HoldInteractionRange`: how far a player can reach a block, measured from the
// eye and across sub-levels.
//
// The three Java overloads differ only in the shape of the target (a
// `Position`, a `Vector3dc`, or the same without a reach buffer), so one
// function with a [reachBuffer] covers all three.
//
// Pure: no host imports (sable's level model is pure).
//
// Java: dev.simulated_team.simulated.util.hold_interaction.HoldInteractionRange
import 'package:sable/sable.dart' show SableLevel, SubLevelHelper, Vector3d;

/// The reach checks of the hold interactions.
abstract final class HoldInteractionRange {
  /// `getInteractionRange(player)`: the `minecraft:block_interaction_range`
  /// attribute, which is 4.5 by default and grows with modifiers.
  static double rangeOf(double blockInteractionRange) => blockInteractionRange;

  /// `inInteractionRange(player, target, reachBuffer)`.
  ///
  /// [eye] is the player's eye position, [target] a point in the level's
  /// coordinates. [level] projects the target out of its sub-level; a `null`
  /// level means the target is already in world space (a test, or a world
  /// without sable).
  static bool within({
    required Vector3d eye,
    required Vector3d target,
    required double range,
    SableLevel? level,
    double reachBuffer = 0,
  }) {
    final projected = level == null ? Vector3d.copy(target) : SubLevelHelper.projectOutOfSubLevel(level, Vector3d.copy(target));
    final distance = range + reachBuffer;
    final dx = projected.x - eye.x;
    final dy = projected.y - eye.y;
    final dz = projected.z - eye.z;
    return dx * dx + dy * dy + dz * dz < distance * distance;
  }

  /// The centre of the block at [pos], which is the target the packets use
  /// (`Vec3.atCenterOf`).
  static Vector3d blockCenter((int, int, int) pos) =>
      Vector3d(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);
}
