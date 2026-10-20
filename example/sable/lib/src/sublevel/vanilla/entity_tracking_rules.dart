// Which sub-level an entity is "on", and the position queries that follow from
// it.
//
// Java keeps this state on `Entity` itself (a mixin field) and updates it from
// `Entity#tick`. A plugin cannot add fields to host entities, so the same state
// lives in [TrackingState] here and the plugin keeps one per entity it cares
// about (the host does not hand out a stable per-entity object).
//
// Java: dev.ryanhcode.sable.mixin.entity.entity_sublevel_collision.EntityMixin
// Java: dev.ryanhcode.sable.mixin.entity.entity_sublevel_collision.AbstractMinecartMixin
// Java: dev.ryanhcode.sable.mixin.entity.entity_sublevel_collision.ItemEntityMixin
// Java: dev.ryanhcode.sable.mixin.entity.entities_stick_sublevels.effects.EntityMixin
// Java: dev.ryanhcode.sable.mixinhelper.entity.entity_riding_sub_level_vehicle.EntityRidingSubLevelVehicleHelper
// Java: dev.ryanhcode.sable.ActiveSableCompanion (distance helpers)
//
// Pure: no host imports.
import '../api/entity/sub_level_entity.dart';
import '../api/sub_level_helper.dart';
import '../host/sub_level_host.dart';
import '../math/bounding_box.dart';
import '../math/vector.dart';
import '../model/sub_level.dart';

/// What one tick of an entity decided about its sub-level state.
final class TrackingResolution {
  /// The sub-level the entity is standing on / locked to, or `null`.
  final SubLevel? tracking;

  /// The sub-level whose plot contains the entity's position, or `null`.
  final SubLevel? containing;

  const TrackingResolution(this.tracking, this.containing);

  /// `EntityMovementExtension.sable$getTrackingSubLevel() != null`.
  bool get isTracking => tracking != null;

  @override
  String toString() =>
      'TrackingResolution(tracking=$tracking, containing=$containing)';
}

/// The per-entity state the Java mixin keeps in fields.
final class TrackingState {
  /// `sable$trackingSubLevel`.
  SubLevel? tracking;

  /// `sable$lastTrackingSubLevelId`, kept so a death message can name the ship
  /// the entity fell off after the tracking was cleared.
  String? lastTrackingId;

  TrackingState([this.tracking, this.lastTrackingId]);
}

/// Rules for resolving and maintaining an entity's sub-level state.
abstract final class SubLevelEntityRules {
  /// The tick-time resolution of `EntityMixin#tick`.
  ///
  /// An entity is either inside a sub-level or on top of one, never both: a
  /// containing sub-level clears the tracking state. Otherwise a ridden vehicle
  /// decides — the sub-level it is inside, else the sub-level it stands on, else
  /// nothing — and with no vehicle the previous state is kept.
  ///
  /// [vehicleContaining] is the sub-level containing the entity's vehicle,
  /// [vehicleTracking] the sub-level that vehicle is standing on, and
  /// [hasVehicle] whether the entity rides anything at all (a vehicle with no
  /// sub-level clears the tracking state rather than keeping it).
  static TrackingResolution resolve({
    required SubLevel? containing,
    required SubLevel? vehicleContaining,
    required SubLevel? vehicleTracking,
    required SubLevel? currentTracking,
    bool hasVehicle = false,
  }) {
    SubLevel? tracking;

    if (containing != null) {
      tracking = null;
    } else if (hasVehicle) {
      tracking = vehicleContaining ?? vehicleTracking;
    } else {
      tracking = currentTracking;
    }

    if (tracking != null && tracking.isRemoved()) tracking = null;

    return TrackingResolution(tracking, containing);
  }

  /// `getTrackingOrVehicleSubLevel`: the tracking sub-level, else the sub-level
  /// the entity rides in.
  static SubLevel? trackingOrVehicle(
    SubLevel? tracking,
    SubLevel? vehicleContaining,
  ) => tracking ?? vehicleContaining;

  /// Whether an entity of [typeId] must be destroyed once it leaves the plot of
  /// the sub-level it is in (`#sable:destroy_when_leaving_plot`).
  ///
  /// The Java check compares the entity's bounding box with the plot's block
  /// bounds grown by [inflate] (0.5 for minecarts, 1.0 for the general case).
  static bool shouldDestroyWhenLeavingPlot({
    required SubLevel? containing,
    required BoundingBox3dc entityBox,
    required Set<String> destroyWhenLeavingPlot,
    required String typeId,
    double inflate = 1.0,
  }) {
    if (containing == null) return false;
    if (!destroyWhenLeavingPlot.contains(typeId)) return false;

    final plotBounds = BoundingBox3d.fromBoundingBox3i(
      containing.getPlot().getBoundingBox(),
    );
    if (plotBounds.minX > plotBounds.maxX) return false; // empty plot bounds
    return !entityBox.intersects(plotBounds.expand(inflate));
  }

  /// The block position an entity's *feet* are in, in the plot's own
  /// coordinates, for `getInBlockState` / `getOnPos` style queries.
  ///
  /// Java adds a tiny upward bias so an entity standing exactly on a block
  /// boundary resolves to the block above it.
  static (int, int, int) localBlockPos(
    SubLevel tracking,
    Vector3d globalPosition, {
    double yBias = 0.001,
  }) {
    final local = tracking.logicalPose.transformPositionInverse(
      Vector3d(globalPosition.x, globalPosition.y + yBias, globalPosition.z),
    );
    return (local.x.floor(), local.y.floor(), local.z.floor());
  }

  /// The global block position of a plot-local block, as `getNextNodePos` and
  /// the block-outline code need it (the block centre is transformed).
  static (int, int, int) globalBlockPos(
    SubLevel subLevel,
    (int, int, int) local,
  ) {
    final centre = Vector3d(local.$1 + 0.5, local.$2 + 0.5, local.$3 + 0.5);
    final global = subLevel.logicalPose.transformPosition(centre);
    return (global.x.floor(), global.y.floor(), global.z.floor());
  }

  /// The entity's feet, ignoring the custom-orientation offset the Java code
  /// reads from `EntitySubLevelUtil.getCustomEntityOrientation` (the port always
  /// returns `null` for that, so the offset is zero).
  static Vector3d feetPos(Vector3d position, double distanceDown) =>
      Vector3d(position.x, position.y - distanceDown, position.z);

  /// `distanceSquaredWithSubLevels`: both points are projected out of the
  /// sub-level that contains them before the distance is taken, so a player in
  /// a plot and an entity outside it are compared in world space.
  static double distanceSquaredWithSubLevels(
    SableLevel level,
    Vector3d a,
    Vector3d b,
  ) {
    final globalA = SubLevelHelper.projectOutOfSubLevel(
      level,
      Vector3d.copy(a),
    );
    final globalB = SubLevelHelper.projectOutOfSubLevel(
      level,
      Vector3d.copy(b),
    );
    return globalA.distanceSquared(globalB);
  }

  /// `rectilinearDistanceWithSubLevels` (Chebyshev distance), used by the world
  /// border and by `ConduitBlockEntity`.
  static double rectilinearDistanceWithSubLevels(
    SableLevel level,
    Vector3d a,
    Vector3d b,
  ) {
    final globalA = SubLevelHelper.projectOutOfSubLevel(
      level,
      Vector3d.copy(a),
    );
    final globalB = SubLevelHelper.projectOutOfSubLevel(
      level,
      Vector3d.copy(b),
    );
    final dx = (globalB.x - globalA.x).abs();
    final dy = (globalB.y - globalA.y).abs();
    final dz = (globalB.z - globalA.z).abs();
    return dx > dy ? (dx > dz ? dx : dz) : (dy > dz ? dy : dz);
  }

  /// Whether an item entity must be ticked every tick even though it is at
  /// rest: an item standing on a sub-level has to follow it.
  static bool forceItemEntityTick(SubLevel? tracking) => tracking != null;

  /// The position an entity riding a vehicle inside a sub-level is kicked to.
  ///
  /// The eye offset is transformed instead of the position so the entity does
  /// not sink into the vehicle when the sub-level is rotated, and the offset is
  /// then removed again (`EntityRidingSubLevelVehicleHelper`).
  static Vector3d kickRidingEntity(
    SubLevelEntity entity,
    SubLevel subLevel, {
    bool shouldKick = true,
  }) {
    final position = entity.position;
    if (!shouldKick) return position;

    final eyePosition = entity.eyePosition;
    final eyeOffset = Vector3d(
      eyePosition.x - position.x,
      eyePosition.y - position.y,
      eyePosition.z - position.z,
    );
    final transformed = subLevel.logicalPose.transformPosition(
      Vector3d(
        position.x + eyeOffset.x,
        position.y + eyeOffset.y,
        position.z + eyeOffset.z,
      ),
    );
    return Vector3d(
      transformed.x - eyeOffset.x,
      transformed.y - eyeOffset.y,
      transformed.z - eyeOffset.z,
    );
  }

  /// `Entity#getLastTrackingSubLevel`: the sub-level the entity last stood on,
  /// resolved by id because the object itself may be gone.
  ///
  /// [lookup] is the container's id lookup; the plugin passes
  /// `SubLevelContainer.of(level)?.getSubLevel(uuid)`.
  static SubLevel? lastTrackingSubLevel(
    String? lastTrackingId,
    SubLevel? Function(String id) lookup,
  ) => lastTrackingId == null ? null : lookup(lastTrackingId);

  /// Clears the remembered id once the entity has been on the ground and is no
  /// longer tracking anything (`death_message/EntityMixin`), so a later fall
  /// does not credit the old ship.
  static String? updatedLastTrackingId({
    required SubLevel? tracking,
    required bool onGround,
    required String? lastTrackingId,
  }) {
    if (tracking == null && onGround) return null;
    return lastTrackingId;
  }
}
