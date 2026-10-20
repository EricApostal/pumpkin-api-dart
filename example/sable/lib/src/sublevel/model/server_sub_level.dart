// `dev.ryanhcode.sable.sublevel.ServerSubLevel`: a sub-level of a server level.
//
// Besides the base model it owns the per-tick networking state (last networked
// pose and bounds), the set of tracking players, the physics body and mass
// tracker, the split-from information used by snapshot interpolation, and the
// pointer to where it was last saved.
//
// Physics is W3: [physicsBody] and [massTracker] stay `null` until the physics
// system attaches them. Methods that cannot work without them throw a
// [StateError] naming what is missing.
//
// Pure: no host imports.
//
// create's pure helpers (positions, `Aabb`, `BlockBounds`) are not exported from
// its public barrel yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;
import '../api/physics.dart';
import '../config/sable_config.dart';
import '../math/bounding_box.dart';
import '../math/pose.dart';
import '../math/vector.dart';
import '../storage/holding/saved_pointer.dart';
import 'level_plot.dart';
import 'server_level_plot.dart';
import 'sub_level.dart';
import 'sub_level_container.dart';

/// A sub-level in a server level.
final class ServerSubLevel extends SubLevel implements ServerSubLevelLike {
  /// The latest linear velocity of this sub-level.
  final Vector3d latestLinearVelocity = Vector3d();

  /// The latest angular velocity of this sub-level.
  final Vector3d latestAngularVelocity = Vector3d();

  /// All players currently tracking this sub-level (UUIDs).
  final Set<String> trackingPlayers = {};

  /// The last pose sent out to players.
  final Pose3d lastNetworkedPose = Pose3d();

  /// The last plot bounding box sent out to players.
  final BoundingBox3i lastNetworkedBoundingBox = BoundingBox3i();

  /// The runtime ID of this sub-level.
  final int runtimeId;

  /// The physics body of this sub-level, or `null` until W3 attaches one.
  RigidBodyHandle? physicsBody;

  /// The merged mass tracker of this sub-level, or `null` before it is built.
  MassData? massTracker;

  /// The last stopped status sent out to players.
  bool lastNetworkedStopped = false;

  /// The sub-level this was split from, if any.
  String? splitFromSubLevelId;

  /// The original pose before this sub-level was projected out of its parent.
  Pose3d? splitFromPose;

  /// The last place this sub-level was saved to.
  GlobalSavedSubLevelPointer? lastSerializationPointer;

  /// The user-data tag, saved and serialized with the sub-level.
  Map<String, Object?>? userDataTag;

  /// Whether individual queued forces are tracked.
  bool trackIndividualQueuedForces = false;

  /// Queued force totals by force group, created lazily.
  Map<ForceGroup, QueuedForceGroup>? queuedForceGroups;

  /// The config this sub-level uses for its y limits.
  final SableConfigLike? config;

  /// The splitting heat map of this sub-level; `null` when splitting is off.
  SubLevelHeatMap? heatMapManager;

  /// Creates a new sub-level with the given parent level and pose.
  ///
  /// [plotX] and [plotZ] are the global plot coordinates.
  ServerSubLevel(
    super.level,
    super.plotX,
    super.plotZ,
    super.pose, {
    required this.runtimeId,
    this.config,
  });

  @override
  LevelPlot createPlot(SubLevelContainer plotContainer, int plotX, int plotZ, int logPlotSize) =>
      ServerLevelPlot(plotContainer, plotX, plotZ, logPlotSize, this);

  /// The UUIDs of the players tracking this sub-level.
  @override
  Iterable<String> get trackingPlayerIds => trackingPlayers;

  /// A packet sink to every player tracking this sub-level.
  ///
  /// HOST GAP: sending a payload to a player needs the host's connection
  /// handle; the plugin's payload bus (`create`'s `CreateNetwork`) is the
  /// implementation point.
  void sendToTracking(Object payload) {
    throw UnimplementedError(
      'HOST GAP: ServerSubLevel.playerSink needs a per-player payload send; '
      'the Pumpkin API only exposes payload channels, not arbitrary packets.',
    );
  }

  /// The last pose sent out to players.
  Pose3d lastNetworkedPoseValue() => lastNetworkedPose;

  /// The last plot bounding box sent out to players.
  BoundingBox3i lastNetworkedBoundingBoxValue() => lastNetworkedBoundingBox;

  /// The unique runtime ID of this sub-level.
  int getRuntimeId() => runtimeId;

  @override
  void onPlotBoundsChanged() {
    final bounds = getPlot().getBoundingBox();
    if (identical(bounds, BoundingBox3i.empty) || bounds.volume() <= 0) {
      markRemoved();
    }
  }

  /// Ticks this sub-level, updating the global bounding box and components.
  @override
  void tick() {
    super.tick();
    updateBoundingBox();

    final bounds = boundingBox;
    final limits = config;
    if (!isRemoved() &&
        limits != null &&
        (bounds.minY < limits.subLevelRemoveMin || bounds.maxY > limits.subLevelRemoveMax)) {
      markRemoved();
      return;
    }

    if (limits?.subLevelSplitting ?? false) {
      heatMapManager?.tick();
    }
  }

  /// The last stopped status sent out to players.
  bool getLastNetworkedStopped() => lastNetworkedStopped;

  /// Sets the last stopped status sent out to players.
  void setLastNetworkedStopped(bool stopped) => lastNetworkedStopped = stopped;

  /// Updates and merges the mass trackers for this sub-level.
  ///
  /// A sub-level without a tracker is a no-op, as in Java
  /// (`ServerSubLevel.updateMergedMassData` guards on `massTracker != null`);
  /// the system builds one in `onSubLevelAdded` before the first tick.
  void updateMergedMassData(double partialPhysicsTick) {
    // The merged tracker is a pipeline service; without one there is nothing
    // to merge, and the tick continues.
    if (massTracker == null) return;
  }

  /// Called before the physics tick begins: resets the queued force groups.
  void prePhysicsTickBegin() {
    final groups = queuedForceGroups;
    if (groups != null) {
      for (final group in groups.values) {
        group.reset();
      }
    }
  }

  /// Applies the queued forces to [handle].
  void applyQueuedForces(RigidBodyHandle handle, double timeStep) {
    final groups = queuedForceGroups;
    if (groups == null) return;
    for (final group in groups.values) {
      handle.applyForcesAndReset(group.getForceTotal());
    }
  }

  /// Called once per **physics** tick; there may be multiple per game tick.
  ///
  /// DEPENDS ON W3: lift providers, floating blocks and reaction wheels are all
  /// physics systems. The part that belongs to the world model (iterating the
  /// plot's actors) is implemented; the force contribution is not.
  void prePhysicsTick(Object physicsSystem, RigidBodyHandle handle, double timeStep) {
    final plot = getPlot();
    for (final actor in plot.getBlockEntityActors()) {
      actor.sable$physicsTick(this, handle, timeStep);
    }
  }

  /// Gets or creates the queued force group of [forceGroup].
  QueuedForceGroup getOrCreateQueuedForceGroup(ForceGroup forceGroup) {
    final groups = queuedForceGroups ??= {};
    return groups.putIfAbsent(forceGroup, () => QueuedForceGroup(this));
  }

  /// Deletes all entities inside the plot.
  void deleteAllEntities() => getPlot().kickAllEntities();

  @override
  void setName(String? name) {
    if (name != this.name) {
      // The Java version sends a `ClientboundChangeSubLevelNamePacket` to the
      // tracking players here.
      // HOST GAP: no payload channel for sub-level names has been declared, so
      // the clients keep the old name until one exists.
    }
    super.setName(name);
  }

  /// Sets that this sub-level was split from [containingSubLevel].
  void setSplitFrom(ServerSubLevel containingSubLevel, Pose3d originalPose) {
    splitFromSubLevelId = containingSubLevel.uniqueId;
    splitFromPose = Pose3d.copy(originalPose);
  }

  /// The sub-level this was split from, if any.
  String? getSplitFromSubLevel() => splitFromSubLevelId;

  /// The original pose before this sub-level was projected out of its parent.
  Pose3d? getSplitFromPose() => splitFromPose;

  /// Clears the split-from information.
  void clearSplitFrom() {
    splitFromSubLevelId = null;
    splitFromPose = null;
  }

  @override
  ServerLevelPlot getPlot() => super.getPlot() as ServerLevelPlot;

  /// The mass and inertia tracker for this sub-level.
  ///
  /// DEPENDS ON W3: the tracker is built by the physics pipeline.
  MassData getMassTracker() {
    final tracker = massTracker;
    if (tracker == null) {
      throw StateError(
        'ServerSubLevel.getMassTracker: no mass tracker has been built yet. '
        'The physics system (W3) builds it after the plot has been scanned.',
      );
    }
    return tracker;
  }

  /// Builds the mass tracker from the plot bounds.
  ///
  /// DEPENDS ON W3: `MassTracker.build(LevelAccelerator, BoundingBox3ic)` is a
  /// physics-pipeline service.
  /// Installs the mass tracker of a sub-level, or `null` while the physics
  /// workstream has not installed one.
  ///
  /// `MassTracker.build(plot bounds)` is a pipeline service, so the factory is
  /// injected rather than implemented here; the plugin sets it once at load.
  static MassData Function(ServerSubLevel subLevel)? massTrackerFactory;

  void buildMassTracker() {
    final factory = massTrackerFactory;
    if (factory == null) {
      throw StateError(
        'ServerSubLevel.buildMassTracker: no mass tracker factory is installed. '
        'Set ServerSubLevel.massTrackerFactory (the physics pipeline builds the '
        'tracker from the plot bounds).',
      );
    }
    massTracker = factory(this);
  }

  /// The mass tracker for just this sub-level, not including merged masses.
  MassData getSelfMassTracker() => getMassTracker();

  /// The last place this sub-level was saved.
  GlobalSavedSubLevelPointer? getLastSerializationPointer() => lastSerializationPointer;

  /// Sets the last place this sub-level was saved to.
  void setLastSerializationPointer(GlobalSavedSubLevelPointer? pointer) =>
      lastSerializationPointer = pointer;

  /// Sets whether individual queued forces should be tracked.
  void enableIndividualQueuedForcesTracking(bool enable) => trackIndividualQueuedForces = enable;

  /// Whether individual queued forces are being tracked.
  bool isTrackingIndividualQueuedForces() => trackIndividualQueuedForces;

  /// A map of force group to queued force groups.
  Map<ForceGroup, QueuedForceGroup>? getQueuedForceGroups() => queuedForceGroups;

  /// The user-data tag, if any, saved and serialized with this sub-level.
  Map<String, Object?>? getUserDataTag() => userDataTag;

  /// Sets the user-data tag.
  void setUserDataTag(Map<String, Object?>? tag) => userDataTag = tag;

  /// The block position containing the pose position.
  Pos get blockPosition => (
    pose.position().x.floor(),
    pose.position().y.floor(),
    pose.position().z.floor(),
  );

  @override
  String toString() => 'ServerSubLevel${super.toString()}';
}
