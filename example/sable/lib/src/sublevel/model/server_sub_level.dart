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
import '../api/block/block_sub_level_lift_provider.dart' as lift;
import '../api/physics.dart';
import '../config/sable_config.dart';
import '../math/bounding_box.dart';
import '../math/pose.dart';
import '../math/vector.dart';
import '../network/packets/tracking_packets.dart';
import '../physics/dimension_physics.dart';
import '../physics/floating_block_controller.dart';
import '../physics/physics_block_properties.dart';
import '../physics/reaction_wheel_manager.dart';
import '../plot/heat/sub_level_heat_map_manager.dart';
import '../storage/holding/saved_pointer.dart';
import 'level_plot.dart';
import 'mass_tracker.dart';
import 'server_level_plot.dart' show ServerLevelPlot, LiftProviderContext;
import 'sub_level.dart';
import 'sub_level_container.dart';

/// Sends one payload to every player tracking a sub-level
/// (`ServerSubLevel.playerSink`, `ServerSubLevel.java:157-166`).
///
/// The plugin installs this over the host's payload channel; the model has no
/// connection handles of its own.
typedef SubLevelPacketSink = void Function(ServerSubLevel subLevel, Object payload);

/// A sub-level in a server level.
final class ServerSubLevel extends SubLevel
    implements ServerSubLevelLike, QueuedForceTarget {
  /// Where payloads to this sub-level's tracking players go.
  ///
  /// Java's `playerSink()` sends to every tracking player's connection. The
  /// plugin installs the equivalent here (see `SubLevelTrackingSystem`'s
  /// `SablePayloadSink`). When no sink is installed the packets are dropped,
  /// which is what a server without a network layer needs.
  static SubLevelPacketSink? packetSink;

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

  /// The block-property table the floating-block and reaction-wheel models read.
  ///
  /// Java reads the global property registry
  /// (`PhysicsBlockPropertyHelper`); the Dart table is owned by the physics
  /// workstream and installed here by the plugin.
  PhysicsBlockPropertiesTable? blockProperties;

  /// The floating-block controller of this sub-level
  /// (`ServerSubLevel.java:92`, `new FloatingBlockController(this)`).
  ///
  /// Created on first use from [blockProperties]; `null` until then.
  FloatingBlockController? floatingBlockController;

  /// The reaction-wheel manager of this sub-level
  /// (`ServerSubLevel.java:93`, `new ReactionWheelManager(this)`).
  ReactionWheelManager? reactionWheelManager;


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
  /// Java's `playerSink()` (`ServerSubLevel.java:157-166`) sends to every
  /// tracking player's connection. The host connection handles live in the
  /// plugin, which installs [packetSink]; without one the payload is dropped.
  void sendToTracking(Object payload) => packetSink?.call(this, payload);

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
      // Java constructs the manager with the sub-level
      // (`ServerSubLevel.java:90-91`). The Dart manager needs the concrete
      // config for `sub_level_splitting_heatmap_steps`, so it is created on
      // the first tick that needs it.
      var heatMap = heatMapManager;
      final cfg = config;
      if (heatMap == null && cfg is SableConfig) {
        heatMap = SubLevelHeatMapManager(this, config: cfg);
        heatMapManager = heatMap;
      }
      heatMap?.tick();
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
  ///
  /// Returns whether the merged mass properties changed, which is when the
  /// caller uploads them with `PhysicsPipeline.onStatsChanged`
  /// (`MergedMassTracker.uploadData` does that upload itself in Java; the Dart
  /// model has no pipeline reference).
  bool updateMergedMassData(double partialPhysicsTick) {
    final tracker = massTracker;
    if (tracker is MergedMassTracker) {
      return tracker.update(partialPhysicsTick);
    }
    return false;
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
  /// Direct port of `ServerSubLevel.prePhysicsTick`
  /// (`ServerSubLevel.java:303-398`): block-entity actors, then lift/drag from
  /// the plot and its kinematic contraptions, the gravity velocity term, the
  /// floating-block controller, the reaction wheels, and finally one impulse
  /// pair on the body.
  ///
  /// Two boundaries are explicit rather than invented:
  ///
  /// * the lift-provider implementation is resolved through
  ///   [lift.BlockSubLevelLiftProvider.lookup], because Dart block states are
  ///   data and cannot implement the interface themselves;
  /// * a sub-level with no [blockProperties] has no floating-block controller
  ///   (Java reads the global property registry), so floating blocks contribute
  ///   nothing until the plugin installs the table.
  void prePhysicsTick(Object physicsSystem, RigidBodyHandle handle, double timeStep) {
    final plot = getPlot();
    for (final actor in plot.getBlockEntityActors()) {
      actor.sable$physicsTick(this, handle, timeStep);
    }

    final liftProviders = plot.getLiftProviders().toList(growable: false);
    final contraptions = plot.getContraptions().toList(growable: false);
    final floating = getOrCreateFloatingBlockController();
    final wheels = getOrCreateReactionWheelManager();

    if (liftProviders.isEmpty &&
        contraptions.isEmpty &&
        !(floating?.needsTicking() ?? false) &&
        !wheels.needsTicking()) {
      return;
    }

    // TODO(parity): `ServerSubLevel.java:339` takes the system itself and calls
    // `physicsSystem.getPartialPhysicsTick()`. The Dart model asks for the
    // narrow [PartialPhysicsTickSource] so it does not import the physics
    // workstream; a caller that passes anything else gets 1.0, which Java never
    // does. Fix when `prePhysicsTick` can take a `SubLevelPhysicsSystem`.
    final partialPhysicsTick =
        physicsSystem is PartialPhysicsTickSource ? physicsSystem.partialPhysicsTick : 1.0;
    final trackForces = isTrackingIndividualQueuedForces();

    final linearVelocity = handle.getLinearVelocity(Vector3d());
    final angularVelocity = handle.getAngularVelocity(Vector3d());
    final linearImpulse = Vector3d();
    final angularImpulse = Vector3d();

    final contexts = [for (final context in liftProviders) _liftContext(context)];
    final groups = trackForces
        ? lift.BlockSubLevelLiftProvider.groupLiftProviders(contexts)
        : const <lift.LiftProviderGroup>[];

    for (final context in contexts) {
      final provider = lift.BlockSubLevelLiftProvider.lookup?.call(context.state);
      if (provider == null) continue;

      provider.sable$contributeLiftAndDrag(
        context,
        this,
        null,
        timeStep,
        linearVelocity,
        angularVelocity,
        linearImpulse,
        angularImpulse,
        _groupOf(groups, context.pos),
      );
    }
    _recordLiftGroups(groups);

    if (contraptions.isNotEmpty) {
      final localContraptionPose = Pose3d();
      for (final contraption in contraptions) {
        final contraptionContexts = [
          for (final value in contraption.sable$liftProviders().values)
            if (value is LiftProviderContext) _liftContext(value),
        ];
        contraption.sable$getLocalPose(localContraptionPose, partialPhysicsTick);

        final contraptionGroups = trackForces
            ? lift.BlockSubLevelLiftProvider.groupLiftProviders(contraptionContexts)
            : const <lift.LiftProviderGroup>[];

        for (final context in contraptionContexts) {
          final provider = lift.BlockSubLevelLiftProvider.lookup?.call(context.state);
          if (provider == null) continue;

          provider.sable$contributeLiftAndDrag(
            context,
            this,
            localContraptionPose,
            timeStep,
            linearVelocity,
            angularVelocity,
            linearImpulse,
            angularImpulse,
            _groupOf(contraptionGroups, context.pos),
          );
        }
        _recordLiftGroups(contraptionGroups);
      }
    }

    // `ServerSubLevel.java:390`: `linearVelocity.fma(-1 / 2.1 * timeStep, gravity)`.
    final gravity = DimensionPhysicsData.getGravity(level);
    linearVelocity.fma(-1.0 / 2.1 * timeStep, gravity);

    // TODO(parity): `ServerSubLevel.java:392` lets the controller collect the
    // floating clusters of every contraption itself
    // (`contraption.sable$getFloatingClusterContainer()`). `KinematicContraption`
    // has no such member here, so a contraption's own floating blocks are not
    // merged into this sub-level's clusters; the sub-level's own blocks are.
    floating?.physicsTick(
      partialPhysicsTick,
      timeStep,
      linearVelocity,
      angularVelocity,
      linearImpulse,
      angularImpulse,
      gravity: gravity,
    );
    wheels.physicsTick(handle);

    handle.applyLinearAndAngularImpulse(linearImpulse, angularImpulse, false);
  }

  /// The floating-block controller of this sub-level, created on first use.
  ///
  /// Java constructs it eagerly (`ServerSubLevel.java:92`). The Dart model
  /// needs the block-property table, which the physics workstream owns; without
  /// one the controller is absent and floating blocks contribute nothing
  /// instead of a made-up material.
  ///
  /// TODO(parity): `ServerSubLevel.java:92` always constructs the controller
  /// (`new FloatingBlockController(this)`); a sub-level with no
  /// [blockProperties] here silently has none. The plugin installs the table
  /// for every server level, so this only differs for a sub-level built without
  /// one.
  FloatingBlockController? getOrCreateFloatingBlockController() {
    final existing = floatingBlockController;
    if (existing != null) return existing;

    final properties = blockProperties;
    if (properties == null) return null;

    return floatingBlockController = FloatingBlockController(
      SubLevelFloatingBlockBody(
        subLevel: this,
        properties: properties,
        pressure: (worldPosition) => DimensionPhysicsData.getAirPressure(level, worldPosition),
        inverseInertia: () => getMassTracker().getInverseInertiaTensor(),
        bodyMass: () => getMassTracker().getMass(),
      ),
      subLevel: this,
    );
  }

  /// The reaction-wheel manager of this sub-level, created on first use
  /// (`ServerSubLevel.java:93`).
  ///
  /// TODO(parity): Java reads the global `PhysicsBlockPropertyHelper` registry;
  /// the fallback table below is the all-defaults table, which matches Java only
  /// when no physics-property definition is loaded.
  ReactionWheelManager getOrCreateReactionWheelManager() =>
      reactionWheelManager ??= ReactionWheelManager(
        this,
        blockProperties ?? PhysicsBlockPropertiesTable(),
      );

  /// Converts a plot lift-provider context into the physics one.
  lift.LiftProviderContext _liftContext(LiftProviderContext context) => lift.LiftProviderContext(
    context.pos,
    lift.BlockSubLevelLiftProvider.parseState(context.state),
    Vector3d(context.dir.$1, context.dir.$2, context.dir.$3),
  );

  /// The group containing [pos], or `null` when forces are not tracked.
  static lift.LiftProviderGroup? _groupOf(List<lift.LiftProviderGroup> groups, Pos pos) {
    for (final group in groups) {
      if (group.positions.contains(pos)) return group;
    }
    return null;
  }

  /// Records the summed lift and drag of each group in the display force
  /// groups (`ServerSubLevel.java:355-362`).
  void _recordLiftGroups(Iterable<lift.LiftProviderGroup> groups) {
    for (final group in groups) {
      if (group.totalLift.lengthSquared >= 0.001 * 0.001) {
        getOrCreateQueuedForceGroup(ForceGroup.lift)
            .recordPointForce(group.liftCenter.div(group.totalLiftStrength), group.totalLift);
      }
      if (group.totalDrag.lengthSquared >= 0.001 * 0.001) {
        getOrCreateQueuedForceGroup(ForceGroup.drag)
            .recordPointForce(group.dragCenter.div(group.totalDragStrength), group.totalDrag);
      }
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
      final id = uniqueIdOrNull;
      // `ServerSubLevel.java:420-425`: the change goes to the tracking players
      // before the local name is replaced. A sub-level without an id has never
      // been sent to a client, so there is nobody to tell.
      if (id != null) sendToTracking(ClientboundChangeSubLevelNamePacket(id, name));
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
  @override
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
  /// `MassTracker.build(plot bounds)` is the default factory, so a sub-level
  /// assembled without further wiring gets a working tracker; the plugin can
  /// replace it (for example with the block-property table installed on
  /// [MassTracker.blockMass]).
  static MassData Function(ServerSubLevel subLevel)? massTrackerFactory = MassTracker.build;

  void buildMassTracker() {
    final factory = massTrackerFactory;
    if (factory == null) {
      throw StateError(
        'ServerSubLevel.buildMassTracker: no mass tracker factory is installed. '
        'Set ServerSubLevel.massTrackerFactory (the physics pipeline builds the '
        'tracker from the plot bounds).',
      );
    }
    final self = factory(this);
    // Java always wraps the built tracker in a MergedMassTracker
    // (`ServerSubLevel.java:494-497`). A factory that already returns a
    // different MassData implementation (the test fakes) is installed as-is.
    massTracker = self is MassTracker ? MergedMassTracker(this, self) : self;
  }

  /// The mass tracker for just this sub-level, not including merged masses.
  MassTracker getSelfMassTracker() {
    final tracker = getMassTracker();
    if (tracker is MergedMassTracker) return tracker.selfTracker;
    if (tracker is MassTracker) return tracker;
    throw StateError(
      'ServerSubLevel.getSelfMassTracker: the installed tracker '
      '(${tracker.runtimeType}) is not a MassTracker.',
    );
  }

  /// The last place this sub-level was saved.
  GlobalSavedSubLevelPointer? getLastSerializationPointer() => lastSerializationPointer;

  /// Sets the last place this sub-level was saved to.
  void setLastSerializationPointer(GlobalSavedSubLevelPointer? pointer) =>
      lastSerializationPointer = pointer;

  /// Sets whether individual queued forces should be tracked.
  void enableIndividualQueuedForcesTracking(bool enable) => trackIndividualQueuedForces = enable;

  /// Whether individual queued forces are being tracked.
  @override
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
