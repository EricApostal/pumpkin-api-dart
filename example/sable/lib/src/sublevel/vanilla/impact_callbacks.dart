// The block collision callbacks vanilla blocks get in Java by being patched:
// fragile blocks (leaves, ice), beehives, bells and TNT.
//
// In Java these are `BlockWithSubLevelCollisionCallback` implemented on the
// vanilla block classes by mixins; the port looks callbacks up in a registry
// keyed by block, so the same behaviour is installed here for the vanilla
// blocks that need it. Everything the callbacks touch goes through
// [ImpactHostPort], so the decisions stay testable.
//
// Java: dev.ryanhcode.sable.physics.callback.FragileBlockCallback
// Java: dev.ryanhcode.sable.physics.callback.BeehiveBlockCallback
// Java: dev.ryanhcode.sable.physics.callback.BellBlockCallback
// Java: dev.ryanhcode.sable.physics.callback.ExplosiveBlockCallback
// Java: dev.ryanhcode.sable.mixin.impact.BeehiveBlockMixin
// Java: dev.ryanhcode.sable.mixin.impact.BellBlockMixin
// Java: dev.ryanhcode.sable.mixin.impact.TntBlockMixin
//
// Pure: no host imports.
//
// create's block-state type is not exported from its public barrel yet, so it is
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/pos.dart' show Pos;

import '../api/block/block_with_sub_level_collision_callback.dart';
import '../api/physics/callback/block_sub_level_collision_callback.dart';
import '../math/vector.dart';

/// What the impact callbacks may do to the world.
abstract interface class ImpactHostPort {
  /// The block state at a plot position.
  BState stateAt(Pos plotBlock);

  /// `Level#destroyBlock(pos, drop)`.
  void destroyBlock(Pos plotBlock, {required bool dropLoot});

  /// `Level#setBlock(pos, state, flags)`.
  void setBlock(Pos plotBlock, BState state);

  /// `Level#getBlockState(pos).liquid()`.
  bool isLiquid(Pos plotBlock);

  /// Rings a bell at [plotBlock] in the horizontal direction [facing]
  /// (`north`, `south`, `east`, `west`).
  void ringBell(Pos plotBlock, String facing);

  /// Empties a beehive of its bees (`BeeReleaseStatus.EMERGENCY`).
  void emptyBeehive(Pos plotBlock);

  /// Spawns a primed TNT entity at the block's centre.
  void spawnPrimedTnt(Pos plotBlock, int fuse);
}

/// Blocks that break when hit hard enough.
///
/// `FragileBlockCallback.INSTANCE`: also the fallback for states that carry the
/// `sable:fragile` property.
class FragileBlockCallback implements BlockSubLevelCollisionCallback {
  const FragileBlockCallback(this.host);

  /// The world the callbacks act on.
  final ImpactHostPort host;

  /// The impact velocity (m/s) below which nothing happens.
  double get triggerVelocity => 4.0;

  /// Whether [state] has a dedicated hit behaviour instead of simply breaking.
  bool shouldTriggerFor(BState state) => false;

  @override
  CollisionResult sable$onCollision(
    Pos hitBlockPos,
    Pos? otherHitBlockPos,
    Vector3d impactPosition,
    double impactVelocity,
  ) =>
      handle(
        hitBlockPos: hitBlockPos,
        impactPosition: impactPosition,
        impactVelocity: impactVelocity,
        fragileFlag: true,
      );

  /// The collision, with the fragile flag made explicit.
  ///
  /// [fragileFlag] is whether the state was looked up through the `fragile`
  /// property; a callback registered for a specific block ignores it because
  /// [shouldTriggerFor] already matched.
  CollisionResult handle({
    required Pos hitBlockPos,
    required Vector3d impactPosition,
    required double impactVelocity,
    required bool fragileFlag,
  }) {
    if (impactVelocity * impactVelocity < triggerVelocity * triggerVelocity) {
      return CollisionResult.none;
    }

    final state = host.stateAt(hitBlockPos);

    // A persistent leaves block never breaks on impact: it was placed, not
    // grown, and the player meant to keep it.
    if (state.key == 'minecraft:leaves' && state.flag('persistent')) {
      return CollisionResult.none;
    }

    if (shouldTriggerFor(state)) {
      return onHit(hitBlockPos, state, impactPosition);
    }

    if (!fragileFlag) return CollisionResult.none;

    host.destroyBlock(hitBlockPos, dropLoot: true);

    // Ice that breaks with something liquid below turns into water instead of
    // disappearing.
    if (state.key == 'minecraft:ice') {
      final below = (hitBlockPos.$1, hitBlockPos.$2 - 1, hitBlockPos.$3);
      if (host.isLiquid(below)) {
        host.setBlock(hitBlockPos, const BState('minecraft:water'));
      }
    }

    return CollisionResult(Vector3d(), true);
  }

  /// What happens when [state] is hit: break it, by default.
  CollisionResult onHit(Pos hitBlockPos, BState state, Vector3d impactPosition) {
    host.destroyBlock(hitBlockPos, dropLoot: true);
    return CollisionResult(Vector3d(), true);
  }
}

/// Beehives and bee nests empty themselves when a ship slams into them.
class BeehiveBlockCallback extends FragileBlockCallback {
  const BeehiveBlockCallback(super.host);

  @override
  double get triggerVelocity => 9.0;

  @override
  bool shouldTriggerFor(BState state) =>
      state.key == 'minecraft:beehive' || state.key == 'minecraft:bee_nest';

  @override
  CollisionResult onHit(Pos hitBlockPos, BState state, Vector3d impactPosition) {
    host.emptyBeehive(hitBlockPos);
    return CollisionResult(Vector3d(), false);
  }
}

/// Bells ring in the direction the impact came from.
class BellBlockCallback extends FragileBlockCallback {
  const BellBlockCallback(super.host);

  @override
  bool shouldTriggerFor(BState state) => state.key == 'minecraft:bell';

  @override
  CollisionResult onHit(Pos hitBlockPos, BState state, Vector3d impactPosition) {
    host.ringBell(hitBlockPos, bellRingDirection(hitBlockPos, state, impactPosition));
    return CollisionResult(Vector3d(), false);
  }

  /// `Direction.getApproximateNearest(hitDir.x * xMul, 0, hitDir.z * zMul)`
  /// opposite, where the multipliers come from the bell's facing unless it hangs
  /// from the ceiling.
  static String bellRingDirection(Pos bellPos, BState state, Vector3d impactPosition) {
    final centreX = bellPos.$1 + 0.5;
    final centreZ = bellPos.$3 + 0.5;
    var hitX = centreX - impactPosition.x;
    var hitZ = centreZ - impactPosition.z;

    if (state['attachment'] != 'ceiling') {
      final facing = state['facing'] ?? 'north';
      final onXAxis = facing == 'east' || facing == 'west';
      if (!onXAxis) hitX = 0.0;
      if (onXAxis) hitZ = 0.0;
    }

    // The nearest horizontal direction, then its opposite: the bell swings away
    // from the hit.
    if (hitX.abs() >= hitZ.abs()) {
      return hitX >= 0 ? 'west' : 'east';
    }
    return hitZ >= 0 ? 'north' : 'south';
  }
}

/// TNT lights itself when a ship hits it fast enough.
class ExplosiveBlockCallback extends FragileBlockCallback {
  const ExplosiveBlockCallback(super.host);

  @override
  double get triggerVelocity => 5.0;

  @override
  bool shouldTriggerFor(BState state) => state.key == 'minecraft:tnt';

  @override
  CollisionResult onHit(Pos hitBlockPos, BState state, Vector3d impactPosition) {
    host.spawnPrimedTnt(hitBlockPos, 4);
    host.setBlock(hitBlockPos, BState.air);
    return CollisionResult(Vector3d(), true);
  }
}

/// Installs the vanilla impact callbacks over [host].
///
/// Call once, after the block registry is available. The fragile callback also
/// becomes the fallback for states with the `fragile` property, which is how
/// Java's block-state property lookup behaves.
void registerVanillaImpactCallbacks(ImpactHostPort host) {
  BlockWithSubLevelCollisionCallback
    ..fragileCallback = FragileBlockCallback(host)
    ..register('minecraft:beehive', BeehiveBlockCallback(host))
    ..register('minecraft:bee_nest', BeehiveBlockCallback(host))
    ..register('minecraft:bell', BellBlockCallback(host))
    ..register('minecraft:tnt', ExplosiveBlockCallback(host));
}
