// Explosions and sub-levels.
//
// Two separate Java patches:
//
// * `ServerLevel#explode` projects the centre of an explosion out of the
//   sub-level that contains it, so an explosion inside a ship happens in world
//   space instead of inside the plot. A plugin can do that from the explosion
//   event: rewrite the position.
// * `ServerExplosion#calculateExplodedPositions` walks the blast ray and, where
//   the world block is air, repeats the resistance/should-explode query for
//   every sub-level the ray point is in, destroying those blocks and pushing
//   the body back. That walk lives inside vanilla's loop, so a plugin cannot
//   reproduce it from events; [SubLevelExplosions.walk] is the algorithm, kept
//   pure so the host can call it once it exposes the ray hook (see
//   `host_gap.dart`, gap `explosion-ray`).
//
// Java: dev.ryanhcode.sable.mixin.explosion.ExplosionMixin
// Java: dev.ryanhcode.sable.mixin.explosion.ServerLevelMixin
//
// Pure: no host imports.
import '../math/vector.dart';
import '../model/sub_level.dart';

/// Asks how much a block resists the blast (`null` when the block has no
/// resistance of its own, like vanilla's `Optional.empty`).
typedef SubLevelBlockResistance = double? Function(SubLevel subLevel, (int, int, int) localPos);

/// Asks whether a block should be destroyed (`ExplosionDamageCalculator
/// #shouldBlockExplode`).
typedef SubLevelBlockExplodeTest = bool Function(SubLevel subLevel, (int, int, int) localPos, double power);

/// One impulse handed to a sub-level body.
final class ExplosionImpulse {
  final SubLevel subLevel;

  /// The block centre, in the plot's coordinates.
  final Vector3d position;

  /// The force, in the body's local frame.
  final Vector3d force;

  const ExplosionImpulse(this.subLevel, this.position, this.force);

  @override
  String toString() => 'ExplosionImpulse(${subLevel.uniqueIdOrNull}, $position, $force)';
}

/// The outcome of one blast-ray point against the sub-levels there.
final class SubLevelExplosionResult {
  /// The power left after the sub-levels' resistance was subtracted.
  final double power;

  /// Blocks the blast destroys, in the plot's coordinates.
  final List<(int, int, int)> destroyed;

  /// Impulses to apply to the bodies.
  final List<ExplosionImpulse> impulses;

  const SubLevelExplosionResult(this.power, this.destroyed, this.impulses);

  static const SubLevelExplosionResult none = SubLevelExplosionResult(0, [], []);
}

/// Explosion helpers.
abstract final class SubLevelExplosions {
  /// `ServerLevelMixin#sable$preExplode`: an explosion whose centre is inside a
  /// sub-level is moved to world space first.
  ///
  /// [containing] is the sub-level containing [centre] (or `null`).
  static Vector3d projectCentre(SubLevel? containing, Vector3d centre) {
    if (containing == null) return Vector3d.copy(centre);
    return containing.logicalPose.transformPosition(Vector3d.copy(centre));
  }

  /// The block-destruction walk for one ray point (`ExplosionMixin`).
  ///
  /// [rayPoint] is the world position vanilla is about to query; [centre] is the
  /// explosion centre, also in world space. [subLevels] are the sub-levels whose
  /// bounds contain the ray point. [power] is the blast power left at this
  /// point; [wind] is true for wind charges, which destroy the block the ray
  /// dies on regardless of the remaining power.
  ///
  /// [exploded] is the caller's set of already-hit blocks (plot coordinates, per
  /// sub-level), shared across the whole walk so a block is only pushed once.
  static SubLevelExplosionResult walk({
    required Vector3d rayPoint,
    required Vector3d centre,
    required Iterable<SubLevel> subLevels,
    required double power,
    required SubLevelBlockResistance resistance,
    required SubLevelBlockExplodeTest shouldBlockExplode,
    bool wind = false,
    double impulseStrength = 5.0,
    Set<(String, int, int, int)>? exploded,
  }) {
    final destroyed = <(int, int, int)>[];
    final impulses = <ExplosionImpulse>[];
    final hit = exploded ?? <(String, int, int, int)>{};
    var remaining = power;

    for (final subLevel in subLevels) {
      final pose = subLevel.logicalPose;
      final localRay = pose.transformPositionInverse(Vector3d.copy(rayPoint));
      final localCentre = pose.transformPositionInverse(Vector3d.copy(centre));

      final blockPos = (localRay.x.floor(), localRay.y.floor(), localRay.z.floor());
      final canExplodeBefore = remaining > 0.0;

      final blockResistance = resistance(subLevel, blockPos);
      if (blockResistance != null) {
        remaining -= (blockResistance + 0.3) * 0.3;
      }

      if (remaining > 0.0 && shouldBlockExplode(subLevel, blockPos, remaining)) {
        destroyed.add(blockPos);
      }

      final addKey = (subLevel.uniqueIdOrNull ?? '', blockPos.$1, blockPos.$2, blockPos.$3);
      if (canExplodeBefore && (remaining < 0.0 || wind) && hit.add(addKey)) {
        final blockCentre = Vector3d(blockPos.$1 + 0.5, blockPos.$2 + 0.5, blockPos.$3 + 0.5);
        final direction = Vector3d(
          blockCentre.x - localCentre.x,
          blockCentre.y - localCentre.y,
          blockCentre.z - localCentre.z,
        );
        final length = direction.length;
        final force = length == 0
            ? Vector3d()
            : Vector3d(
                direction.x / length * impulseStrength,
                direction.y / length * impulseStrength,
                direction.z / length * impulseStrength,
              );
        impulses.add(ExplosionImpulse(subLevel, blockCentre, force));
      }
    }

    return SubLevelExplosionResult(remaining, destroyed, impulses);
  }
}
