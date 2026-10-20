// The host implementation of the propeller's entity push: the entities around
// a propeller and the occlusion check between it and them.
//
// Java reads `Level.getEntities(null, aabb)` and `Level.clip(...)`. The plugin
// API has neither, so this file holds the one implementation of both, shared by
// the small propellers and the propeller bearing (they used to stub it twice).
// create's positions and block states are not exported from its barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/host_bridge.dart' show PosToHost;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart' show BoundingBox3d, Pose3dc, SubLevelHelper, Vector3d;

import '../hot_air/balloon_world.dart' show BalloonWorld;
import '../host/world_balloon_world.dart' show balloonWorldOf;
import '../propeller/geometry.dart' as geo;
import '../propeller/propeller_actor_behaviour.dart'
    show PropellerPushTarget, PropellerPushWorld;

/// The push world of one propeller block entity.
final class HostPropellerPushWorld implements PropellerPushWorld {
  HostPropellerPushWorld(this.world, this.propellerPos);

  final World world;
  final Pos propellerPos;

  @override
  Pose3dc? get propellerSubLevelPose {
    final level = balloonWorldOf(world).level;
    return SubLevelHelper.getContaining(level, propellerPos)?.logicalPose;
  }

  /// `Level.getEntities(null, aabb)`.
  ///
  /// HOST GAP: the plugin API has no "entities in a box" query, only
  /// `World.getEntities()`, so this filters that list. The shape is the one
  /// `example/simulated` uses for the same gap
  /// (`PumpkinSimAssemblyEntities.entitiesIn`): one filtering layer, in the
  /// adapter, not a second one on top. Switch both to the box query when the
  /// plugin API grows one.
  ///
  /// The test is an intersection of the entity's own bounding box with [box],
  /// not its position: a boat straddling the edge of the push volume is inside
  /// it, and `getBoundingBox().getCenter()` is what the force is applied from,
  /// as in Java.
  ///
  /// This runs once per propeller per tick, so the filter is the cost of the
  /// push, not of the physics.
  @override
  Iterable<PropellerPushTarget> entitiesIn(BoundingBox3d box) {
    final out = <PropellerPushTarget>[];
    for (final entity in world.getEntities()) {
      final bounds = entity.getBoundingBox();
      if (bounds.max.$1 < box.minX || bounds.min.$1 > box.maxX) continue;
      if (bounds.max.$2 < box.minY || bounds.min.$2 > box.maxY) continue;
      if (bounds.max.$3 < box.minZ || bounds.min.$3 > box.maxZ) continue;

      final target = _HostPushTarget(entity);
      if (target.isIgnored) continue;
      out.add(target);
    }
    return out;
  }

  /// `Level.clip(new ClipContext(from, to, Block.COLLIDER, Fluid.ANY, ...))`:
  /// whether a block or a fluid sits between [from] and [to].
  ///
  /// HOST GAP: the API exposes no shape raycast, so this walks the voxels the
  /// segment crosses (Amanatides–Woo) and treats a non-air block or any fluid as
  /// a hit. That matches `COLLIDER` for every full cube; blocks without
  /// collision (grass, torches) count as a hit where vanilla would not.
  @override
  bool segmentBlocked(Vector3d from, Vector3d to) => geo.segmentBlocked(from, to, (int x, int y, int z) {
      final pos = (x, y, z).toBlockPos();
      final state = HostBlockGetter.stateOfId(world.getBlockStateId(pos: pos));
      if (!state.isAir) return true;
      return world.getFluidState(pos: pos) != null;
    });

  /// The block state at a position (for tests and diagnostics).
  BState stateAt(Pos pos) => HostBlockGetter.stateOfId(world.getBlockStateId(pos: pos.toBlockPos()));

  /// The balloon-world view of the same world.
  BalloonWorld get balloonWorld => balloonWorldOf(world);
}

/// One entity, as the push sees it.
///
/// The target wraps a live host [Entity] handle, so it is only valid for the
/// query that produced it: `pushEntities` builds its list and consumes it in the
/// same tick. A caller that held one across ticks would be holding a handle whose
/// entity may have unloaded. `example/simulated` has the same constraint on its
/// `SimAssemblyEntityRef` (its lookup map is cleared per `entitiesIn` call), so
/// both sides revisit it together if a host box query ever makes refs reusable.
final class _HostPushTarget implements PropellerPushTarget {
  _HostPushTarget(this._entity);

  final Entity _entity;

  /// `entity.getBoundingBox().getCenter()`.
  @override
  Vector3d get center {
    final bounds = _entity.getBoundingBox();
    return Vector3d(
      (bounds.min.$1 + bounds.max.$1) / 2,
      (bounds.min.$2 + bounds.max.$2) / 2,
      (bounds.min.$3 + bounds.max.$3) / 2,
    );
  }

  @override
  Vector3d get deltaMovement {
    final velocity = _entity.getVelocity();
    return Vector3d(velocity.$1, velocity.$2, velocity.$3);
  }

  @override
  bool get isShiftKeyDown => _entity.isSneaking();

  @override
  void setDeltaMovement(Vector3d motion) =>
      _entity.setVelocity(velocity: (motion.x, motion.y, motion.z));

  @override
  void resetFallDistance() => _entity.setFallDistance(distance: 0);

  /// `AbstractContraptionEntity || AirCurrent.isPlayerCreativeFlying(entity) ||
  /// DivingBootsItem.isWornBy(entity)`.
  ///
  /// Contraptions are plugin entities, so their type key is what identifies
  /// them. The diving-boot check needs an inventory read the API does not offer
  /// for arbitrary entities; it is the one part of the Java test that is missing.
  @override
  bool get isIgnored {
    final pluginType = _entity.getPluginTypeKey();
    if (pluginType != null && pluginType.contains('contraption')) return true;

    if (_entity is Player) {
      final player = _entity as Player;
      final mode = player.getGamemode();
      if (mode == GameMode.creative || mode == GameMode.spectator) {
        // `isPlayerCreativeFlying`: only while actually in the air.
        return player.isFlying();
      }
    }

    return false;
  }
}
