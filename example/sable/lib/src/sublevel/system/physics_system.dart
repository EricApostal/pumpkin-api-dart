// `dev.ryanhcode.sable.sublevel.system.SubLevelPhysicsSystem`: runs the physics
// pipeline over the sub-levels of one server level.
//
// One game tick is:
//
// 1. expire punch cooldowns,
// 2. refresh the plot chunk tickets and upload every section a sub-level
//    overlaps (`PhysicsChunkTicketManager`),
// 3. for each sub-level: remember the last pose and tick its block-entity
//    actors,
// 4. `pipeline.tick()` (bookkeeping that also runs while paused),
// 5. unless paused, `substepsPerTick` physics substeps:
//    `prePhysicsTickBegin` → `updateMergedMassData` → `prePhysicsTick` →
//    pre-physics event → `applyQueuedForces` → `pipeline.physicsTick` →
//    process removals → read every pose → flush queued wake-ups →
//    post-physics event,
// 6. `pipeline.postPhysicsTicks()`.
//
// A sub-level whose pose comes back as NaN is recovered by removing and
// re-adding it (and re-uploading its sections); if that fails it is removed.
//
// Pure: no host imports.
import 'dart:math' as math;

import '../api/block/block_entity_sub_level_actor.dart';
import '../api/physics.dart';
import '../api/physics_pipeline.dart';
import '../api/sub_level_observer.dart';
import '../config/sable_config.dart';
import '../math/bounding_box.dart';
import '../math/pose.dart';
import '../math/vector.dart';
import '../model/server_sub_level.dart';
import '../model/server_sub_level_container.dart';
import '../model/sub_level.dart';
import '../model/sub_level_container.dart';
import '../platform/sable_platform.dart';
import '../storage/sub_level_removal_reason.dart';
import 'arbitrary_physics_object.dart';
import 'physics_chunk_ticket_manager.dart';
import 'sable_server_config.dart';

/// Runs a physics pipeline on sub-levels.
final class SubLevelPhysicsSystem with SubLevelObserver {
  /// `DEFAULT_RESIDENT_CAPACITY`: the resident list capacity per section.
  static const int defaultResidentCapacity = 8;

  /// `USE_TICKETS_FOR_QUERIES`: whether tickets are used for queries.
  static const bool useTicketsForQueries = false;

  /// `IN_PHYSICS_STEP`: whether we are currently inside a physics step.
  static bool inPhysicsStep = false;

  /// `currentlySteppingSystem`: the system that is inside a physics step.
  static SubLevelPhysicsSystem? currentlySteppingSystem;

  /// The container this system serves.
  final ServerSubLevelContainer container;

  /// The level this system serves.
  final dynamic level;

  /// The current physics pipeline.
  final PhysicsPipeline pipeline;

  /// The settings the system reads.
  final SableConfig config;

  /// The solver settings handed to the pipeline.
  final PhysicsConfigData physicsConfig = PhysicsConfigData();

  /// The chunk ticket manager for the plot chunks.
  late final PhysicsChunkTicketManager ticketManager = PhysicsChunkTicketManager(this);

  /// Punch cooldowns, by player UUID.
  final Map<String, int> punchCooldowns = {};

  /// All arbitrary objects currently loaded.
  final Set<ArbitraryPhysicsObject> arbitraryObjects = {};

  /// Queued wake-ups for after the physics tick.
  final Set<ArbitraryPhysicsObject> queuedWakeUps = {};

  /// Listeners for the pre-physics-tick event.
  final List<void Function(SubLevelPhysicsSystem system, double timeStep)> prePhysicsTickListeners =
      [];

  /// Listeners for the post-physics-tick event.
  final List<void Function(SubLevelPhysicsSystem system, double timeStep)> postPhysicsTickListeners =
      [];

  final Pose3d _storagePose = Pose3d();

  /// Whether the physics is paused. The ticket manager and the actors keep
  /// ticking while paused; only the substeps stop.
  bool isPaused = false;

  /// The substep / physics tick we're currently on.
  int currentSubstep = 0;

  SubLevelPhysicsSystem({
    required this.container,
    required this.pipeline,
    required this.config,
    required SableServerConfig serverConfig,
  }) : level = container.level {
    physicsConfig.updateFromConfig(serverConfig);
    container.takePhysicsSystem(this);
    container.addObserver(this);
  }

  /// The physics system of [level]'s container, or `null`.
  static SubLevelPhysicsSystem? of(SubLevelContainer? container) =>
      container is ServerSubLevelContainer ? container.physics as SubLevelPhysicsSystem? : null;

  /// `getCurrentlySteppingSystem()`.
  static SubLevelPhysicsSystem getCurrentlySteppingSystem() {
    final system = currentlySteppingSystem;
    if (system == null) {
      throw StateError('No physics system is currently stepping');
    }
    return system;
  }

  /// `initialize()`: gravity, universal drag and the solver config.
  void initialize() {
    final levelRef = container.level;
    final gravity = Vector3d();
    final drag = 0.09;
    // DimensionPhysicsData is imported lazily through the helper below so this
    // file does not depend on the physics config package's host lookups.
    _applyDimensionDefaults(levelRef, gravity);
    pipeline.init(gravity, drag);
    _updatePipelineConfig();
  }

  /// Overridable dimension lookup: writes the gravity of [level] into [dest].
  ///
  /// The default is the vanilla gravity; the plugin installs the real
  /// `DimensionPhysicsData` lookup (which needs the datapack).
  static void Function(Object level, Vector3d dest) dimensionGravity = (level, dest) {
    dest.set(0.0, -11.0, 0.0);
  };

  /// Overridable dimension lookup: the universal drag of [level].
  static double Function(Object level) dimensionDrag = (level) => 0.09;

  void _applyDimensionDefaults(Object levelRef, Vector3d gravity) {
    dimensionGravity(levelRef, gravity);
  }

  void _updatePipelineConfig() {
    // The pipeline reads the solver settings through `init`; a pipeline that
    // wants them again after a config reload calls `onConfigUpdated`.
  }

  /// `onConfigUpdated()`: the physics config changed.
  void onConfigUpdated() => _updatePipelineConfig();

  // ------------------------------------------------------------- observers

  @override
  void onSubLevelAdded(SubLevel subLevel) {
    if (subLevel is! ServerSubLevel) {
      throw UnsupportedError(
        'Client sub-levels are not supported by the physics system. How did we end up here?',
      );
    }
    subLevel.buildMassTracker();
    subLevel.physicsBody = pipeline.addSubLevel(subLevel, subLevel.logicalPose);
  }

  @override
  void onSubLevelRemoved(SubLevel subLevel, SubLevelRemovalReason reason) {
    if (subLevel is! ServerSubLevel) {
      throw UnsupportedError('Client sub-levels are not supported by the physics system');
    }
    pipeline.removeSubLevel(subLevel);
    subLevel.physicsBody = null;
  }

  // ------------------------------------------------------------------ tick

  @override
  void tick(SubLevelContainer subLevels) {
    final container = subLevels as ServerSubLevelContainer;
    _tickPunchCooldowns();

    ticketManager.update(1.0 / 20.0);

    for (final subLevel in container.serverSubLevels()) {
      subLevel.updateLastPose();
      for (final BlockEntitySubLevelActor actor in subLevel.getPlot().getBlockEntityActors()) {
        actor.sable$tick(subLevel);
      }
    }

    pipeline.tick();

    if (isPaused) return;

    currentlySteppingSystem = this;
    try {
      _tickPipelinePhysics(container);
    } finally {
      currentlySteppingSystem = null;
    }
  }

  void _tickPipelinePhysics(ServerSubLevelContainer container) {
    pipeline.prePhysicsTicks();

    for (currentSubstep = 0; currentSubstep < physicsConfig.substepsPerTick; currentSubstep++) {
      final substepTimeStep = 1.0 / 20.0 / physicsConfig.substepsPerTick;
      final subLevels = container.serverSubLevels();

      for (final subLevel in subLevels) {
        if (subLevel.isRemoved()) continue;
        subLevel.prePhysicsTickBegin();
      }

      for (final subLevel in subLevels) {
        if (subLevel.isRemoved()) continue;
        subLevel.updateMergedMassData(getPartialPhysicsTick());
      }

      for (final subLevel in subLevels) {
        if (subLevel.isRemoved()) continue;
        final handle = subLevel.physicsBody;
        if (handle == null) continue;
        subLevel.prePhysicsTick(this, handle, substepTimeStep);
      }

      sablePlatform.onPhysicsTick(container.level, substepTimeStep);
      for (final listener in prePhysicsTickListeners) {
        listener(this, substepTimeStep);
      }

      for (final subLevel in subLevels) {
        if (subLevel.isRemoved()) continue;
        final handle = subLevel.physicsBody;
        if (handle == null) continue;
        subLevel.applyQueuedForces(handle, substepTimeStep);
      }

      inPhysicsStep = true;
      pipeline.physicsTick(substepTimeStep);
      inPhysicsStep = false;

      // A physics tick can remove sub-levels (fragile blocks breaking), so
      // removals are processed after every substep.
      container.processSubLevelRemovals();
      _updateAllPoses(container);

      for (final object in queuedWakeUps) {
        object.wakeUp();
      }
      queuedWakeUps.clear();

      sablePlatform.onPostPhysicsTick(container.level, substepTimeStep);
      for (final listener in postPhysicsTickListeners) {
        listener(this, substepTimeStep);
      }
    }

    pipeline.postPhysicsTicks();
    currentSubstep = physicsConfig.substepsPerTick;

    // One upload per section per tick, however many blocks changed in it.
    ticketManager.flushDirtySections();
  }

  void _updateAllPoses(ServerSubLevelContainer container) {
    for (final subLevel in container.serverSubLevels()) {
      if (subLevel.isRemoved()) continue;
      updatePose(subLevel);
    }
  }

  /// Updates the pose of [serverSubLevel] from the pipeline, plus the latest
  /// velocities.
  void updatePose(ServerSubLevel serverSubLevel) {
    pipeline.readPose(serverSubLevel, _storagePose);

    final position = _storagePose.position();
    final orientation = _storagePose.orientation();

    if (position.x.isNaN ||
        position.y.isNaN ||
        position.z.isNaN ||
        orientation.x.isNaN ||
        orientation.y.isNaN ||
        orientation.z.isNaN ||
        orientation.w.isNaN) {
      if (!recoverSubLevel(serverSubLevel)) return;
      pipeline.readPose(serverSubLevel, _storagePose);
    }

    final logicalPose = serverSubLevel.logicalPose as Pose3d;
    logicalPose.position().set(_storagePose.position().x, _storagePose.position().y, _storagePose.position().z);
    logicalPose.orientation().set(
      _storagePose.orientation().x,
      _storagePose.orientation().y,
      _storagePose.orientation().z,
      _storagePose.orientation().w,
    );

    // Latest velocities, from the pose delta of the tick.
    logicalPose
        .position()
        .subInto(serverSubLevel.lastPose.position(), serverSubLevel.latestLinearVelocity);

    final difference = logicalPose
        .orientation()
        .difference(serverSubLevel.lastPose.orientation(), Quaterniond())
        .conjugate();
    final angularVelocity = serverSubLevel.latestAngularVelocity
      ..set(difference.x, difference.y, difference.z);
    if (angularVelocity.lengthSquared <= 1E-15) {
      angularVelocity.mul(2.0 / difference.w);
    } else {
      angularVelocity.normalize().mul(2.0 * math.acos(math.min(difference.w.abs(), 1.0)));
    }

    // [m/t] to [m/s].
    serverSubLevel.latestLinearVelocity.mul(20.0);
    serverSubLevel.latestAngularVelocity.mul(20.0);
  }

  /// Attempts to recover a sub-level whose physics state went bad (NaNs) by
  /// removing and re-adding it to the pipeline, re-uploading its sections.
  bool recoverSubLevel(ServerSubLevel serverSubLevel) {
    pipeline.removeSubLevel(serverSubLevel);

    serverSubLevel.buildMassTracker();
    serverSubLevel.physicsBody = pipeline.addSubLevel(serverSubLevel, serverSubLevel.logicalPose);

    final tracker = serverSubLevel.massTracker;
    if (tracker == null || tracker.getCenterOfMass().x.isNaN) {
      // No centre of mass means the body is effectively gone.
      container.removeSubLevelAt(serverSubLevel, SubLevelRemovalReason.removed);
      return false;
    }

    for (final holder in serverSubLevel.getPlot().getLoadedChunks()) {
      final chunk = holder.getChunk();
      final global = chunk.pos;
      for (var i = 0; i < chunk.sectionsCount; i++) {
        if (chunk.sectionHasOnlyAir(i)) continue;
        ticketManager.addSectionIfNotTracked(global.$1, i + (container.level.minY >> 4), global.$2);
      }
    }

    return true;
  }

  // ---------------------------------------------------------------- punches

  void _tickPunchCooldowns() {
    final entries = punchCooldowns.entries.toList(growable: false);
    for (final entry in entries) {
      final cooldown = entry.value - 1;
      if (cooldown <= 0) {
        punchCooldowns.remove(entry.key);
      } else {
        punchCooldowns[entry.key] = cooldown;
      }
    }
  }

  /// `tryPunch(player, cooldownAttempt)`: whether the player may punch now,
  /// registering the cooldown if so.
  bool tryPunch(String player, int cooldownAttempt) {
    final cooldown = punchCooldowns[player] ?? 0;
    if (cooldown > 0) return false;

    punchCooldowns[player] = math.max(config.subLevelPunchCooldownTicks, cooldownAttempt);
    return true;
  }

  // -------------------------------------------------------------- pipeline

  /// The physics pipeline.
  PhysicsPipeline getPipeline() => pipeline;

  /// The physics handle of [subLevel]; throws when it has no body yet.
  RigidBodyHandle getPhysicsHandle(ServerSubLevel subLevel) =>
      subLevel.physicsBody ??
      (throw StateError(
        'SubLevelPhysicsSystem.getPhysicsHandle: ${subLevel.uniqueId} has no physics body. '
        'It is attached when the sub-level is added to the pipeline.',
      ));

  /// The linear velocity of [subLevel], into [dest].
  Vector3d getLinearVelocity(ServerSubLevel subLevel, Vector3d dest) {
    final handle = subLevel.physicsBody;
    if (handle == null) return dest.zero();
    return handle.getLinearVelocity(dest);
  }

  /// The angular velocity of [subLevel], into [dest].
  Vector3d getAngularVelocity(ServerSubLevel subLevel, Vector3d dest) {
    final handle = subLevel.physicsBody;
    if (handle == null) return dest.zero();
    return handle.getAngularVelocity(dest);
  }

  /// Uploads a chunk section to the pipeline.
  void handleChunkSectionAddition(int x, int y, int z, List<int> blockStates) {
    pipeline.handleChunkSectionAddition(x, y, z, blockStates, global: false);
  }

  /// Forgets a chunk section in the pipeline.
  void handleChunkSectionRemoval(int x, int y, int z) {
    pipeline.handleChunkSectionRemoval(x, y, z);
  }

  /// `handleBlockChange`: a block inside the level changed.
  ///
  /// [globalX], [globalY], [globalZ] are absolute block coordinates; [oldState]
  /// and [newState] are the block state strings the plot host reports.
  void handleBlockChange(
    int globalX,
    int globalY,
    int globalZ,
    String oldState,
    String newState, {
    String? subLevelId,
    int packedState = 0,
  }) {
    final chunkX = globalX >> 4;
    final chunkZ = globalZ >> 4;
    if (container.getPlot(chunkX, chunkZ) != null) {
      ticketManager.addSectionIfNotTracked(chunkX, globalY >> 4, chunkZ);
    }

    final subLevel = subLevelId == null ? null : container.getSubLevelById(subLevelId);
    if (subLevel is ServerSubLevel) {
      _updateMassDataFromBlockChange(subLevel, globalX, globalY, globalZ, oldState, newState, !inPhysicsStep);
    }

    ticketManager.markSectionDirty(globalX, globalY, globalZ);
    pipeline.handleBlockChange(globalX, globalY, globalZ, packedState);
    wakeUpObjectsAt(globalX, globalY, globalZ);
  }

  /// Wakes up all sub-levels that intersect the given block position.
  void wakeUpObjectsAt(int x, int y, int z) {
    final bounds = BoundingBox3d.full(x.toDouble(), y.toDouble(), z.toDouble(), x + 1.0, y + 1.0, z + 1.0)
      ..expand(0.1);

    for (final intersecting in container.queryIntersecting(bounds)) {
      if (intersecting is! ServerSubLevel || intersecting.isRemoved()) continue;
      final handle = intersecting.physicsBody;
      if (handle != null) pipeline.wakeUp(handle);
    }

    if (arbitraryObjects.isEmpty) return;

    final objectBounds = BoundingBox3d();
    for (final object in arbitraryObjects.toList(growable: false)) {
      object.getBoundingBox(objectBounds);
      if (!objectBounds.intersects(bounds)) continue;
      if (inPhysicsStep) {
        queuedWakeUps.add(object);
      } else {
        object.wakeUp();
      }
    }
  }

  void _updateMassDataFromBlockChange(
    ServerSubLevel subLevel,
    int x,
    int y,
    int z,
    String oldState,
    String newState,
    bool notifyPipeline,
  ) {
    final oldAir = oldState == 'minecraft:air';
    final newAir = newState == 'minecraft:air';

    final oldMass = oldAir ? 0.0 : _massOf(subLevel, oldState);
    final mass = newAir ? 0.0 : _massOf(subLevel, newState);
    final oldInertia = oldAir ? null : _inertiaOf(subLevel, oldState);
    final inertia = newAir ? null : _inertiaOf(subLevel, newState);

    final changed = mass != oldMass || (newState != oldState && (oldMass != 0.0 || mass != 0.0)) || oldInertia != inertia;
    if (!changed) return;

    final tracker = subLevel.massTracker;
    if (tracker is MutableMassTracker) {
      final mutable = tracker as MutableMassTracker;
      if (mass != 0.0) mutable.addBlockMass(newState, (x, y, z), mass, inertia);
      if (oldMass != 0.0) mutable.addBlockMass(oldState, (x, y, z), -oldMass, oldInertia);
    }

    if (!subLevel.isRemoved() && (tracker?.isInvalid() ?? false)) {
      subLevel.getPlot().destroyAllBlocks();
      subLevel.markRemoved();
      return;
    }

    if (notifyPipeline) {
      subLevel.updateMergedMassData(getPartialPhysicsTick());
      pipeline.onStatsChanged(subLevel);
    }
  }

  /// `PhysicsBlockPropertyHelper.getMass`; overridable so the plugin can plug in
  /// the block-property table.
  static double Function(ServerSubLevel subLevel, String state) blockMass = (subLevel, state) => 1.0;

  /// `PhysicsBlockPropertyHelper.getInertia`.
  static (double, double, double)? Function(ServerSubLevel subLevel, String state) blockInertia =
      (subLevel, state) => null;

  static double _massOf(ServerSubLevel subLevel, String state) => blockMass(subLevel, state);

  static (double, double, double)? _inertiaOf(ServerSubLevel subLevel, String state) =>
      blockInertia(subLevel, state);

  // ---------------------------------------------------------- arbitrary objects

  /// Adds an arbitrary physics object.
  void addObject(ArbitraryPhysicsObject object) {
    if (arbitraryObjects.add(object)) {
      object.onAddition(PhysicsSystemMarker.of(this));
    }
  }

  /// Removes an arbitrary physics object.
  void removeObject(ArbitraryPhysicsObject object) {
    if (arbitraryObjects.remove(object)) {
      object.onRemoved();
    }
  }

  // ------------------------------------------------------------------ state

  /// The fraction between the last physics tick and the next one.
  double getPartialPhysicsTick() =>
      (currentSubstep + 1).toDouble() / physicsConfig.substepsPerTick;

  /// `getNextRuntimeID()`.
  int getNextRuntimeId() => pipeline.getNextRuntimeId();

  /// The game time of the level.
  int get gameTime => container.level.gameTime;

  /// Whether the level's dimension ignores chunk residency (a space dimension
  /// with no chunks); set by the plugin from `DimensionPhysics.ignore_chunks`.
  bool ignoreChunks = false;

  /// Disposes the pipeline and the tickets.
  void close() {
    ticketManager.clear();
    pipeline.dispose();
    container.observers.remove(this);
  }

  @override
  String toString() => 'SubLevelPhysicsSystem[${container.level.dimensionId}, substeps=${physicsConfig.substepsPerTick}]';
}

/// A mass tracker that can take block deltas (the physics workstream's
/// `MassTracker`). Declared here so the system can update masses without
/// importing the pipeline package.
abstract interface class MutableMassTracker {
  /// `addBlockMass(level, state, pos, mass, inertia)`.
  void addBlockMass(String state, (int, int, int) pos, double mass, (double, double, double)? inertia);
}

/// Identity adapter: arbitrary objects see an opaque system marker.
///
/// `ArbitraryPhysicsObject.onAddition` takes a marker so the interface stays
/// free of the system's type; the marker carries the system for callers that
/// need it.
final class PhysicsSystemMarker implements SubLevelPhysicsSystemLike {
  final SubLevelPhysicsSystem system;

  PhysicsSystemMarker._(this.system);

  static final Expando<PhysicsSystemMarker> _markers = Expando();

  /// The marker of [system].
  static PhysicsSystemMarker of(SubLevelPhysicsSystem system) =>
      _markers[system] ??= PhysicsSystemMarker._(system);
}
