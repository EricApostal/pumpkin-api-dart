// `dev.ryanhcode.sable.api.sublevel.ServerSubLevelContainer`: holds all
// sub-levels and plots of a server level.
//
// On top of the base container it owns the force-load tickets (both the live
// map and the persisted one), the holding chunk map and the physics/tracking
// systems.
//
// Pure: no host imports.
import '../host/sub_level_host.dart';
import '../math/pose.dart';
import '../storage/holding/saved_pointer.dart';
import '../storage/holding/sub_level_holding_chunk_map.dart';
import '../storage/sub_level_removal_reason.dart';
import '../storage/sub_level_saved_data.dart';
import 'sub_level_container.dart';
import '../api/sub_level_ticket.dart';
import '../api/sub_level_ticket_loading_system.dart';
import 'server_sub_level.dart';

/// Holds all sub-levels and plots in a server level.
final class ServerSubLevelContainer extends SubLevelContainer {
  /// The physics system of this container (W3); `null` until attached.
  Object? physics;

  /// The tracking system of this container; `null` until attached.
  Object? tracking;

  /// The holding chunk map of this container.
  late final SubLevelHoldingChunkMap holdingChunkMap;

  /// All active sub-level loading tickets.
  final Map<ServerSubLevel, Set<SubLevelLoadingTicket<Object?>>> activeTickets = {};

  /// All sub-level loading tickets, by sub-level UUID.
  final Map<String, SubLevelTicketInfo> allTickets = {};

  /// The runtime ID counter (Java asks the physics system).
  int _nextRuntimeId = 0;

  /// Creates a container.
  ServerSubLevelContainer(
    super.level,
    super.chunkHost,
    super.logSideLength,
    super.logPlotSize,
    super.originX,
    super.originZ,
  );

  /// Initializes the parts that need the container to exist: the holding chunk
  /// map and the force-loaded sub-levels.
  void initialize(SubLevelHoldingChunkMap Function(ServerSubLevelContainer container) createHoldingMap) {
    holdingChunkMap = createHoldingMap(this);
    addObserver(SubLevelTicketLoadingSystem(this));
    loadForceLoadedSubLevels();
  }

  @override
  void tick() {
    super.tick();
    holdingChunkMap.processChanges();
  }

  /// Sets the physics system.
  void takePhysicsSystem(Object physics) => this.physics = physics;

  /// Sets the tracking system.
  void takeTrackingSystem(Object tracking) => this.tracking = tracking;

  /// The physics system; throws when none was attached.
  Object physicsSystem() =>
      physics ?? (throw StateError('No physics system attached to ${level.dimensionId}'));

  /// The tracking system; throws when none was attached.
  Object trackingSystem() =>
      tracking ?? (throw StateError('No tracking system attached to ${level.dimensionId}'));

  /// The next runtime ID for a sub-level (Java
  /// `SubLevelPhysicsSystem.getNextRuntimeID`).
  int nextRuntimeId() => _nextRuntimeId++;

  @override
  void removeSubLevel(int x, int z, SubLevelRemovalReason reason) {
    final subLevel = getSubLevel(x, z);
    if (subLevel is! ServerSubLevel) {
      throw StateError('No server sub-level at $x, $z');
    }

    if (reason == SubLevelRemovalReason.removed) {
      subLevel.deleteAllEntities();
    }

    super.removeSubLevel(x, z, reason);

    if (reason == SubLevelRemovalReason.removed) {
      markOccupancyDirty();
      holdingChunkMap.queueDeletion(subLevel);
    }
  }

  /// Marks the occupancy saved data dirty.
  void markOccupancyDirty() {
    final host = hostOrNull;
    host?.markSavedDataDirty(occupancySavedDataName);
  }

  /// The host of the level, when the container was given one.
  SubLevelHost? hostOrNull;

  @override
  ServerSubLevel createSubLevel(int globalPlotX, int globalPlotZ, Pose3d pose, String uuid) {
    final subLevel = ServerSubLevel(
      level,
      globalPlotX,
      globalPlotZ,
      pose,
      runtimeId: nextRuntimeId(),
    );
    subLevel.setUniqueId(uuid);

    final position = pose.position();
    final blockX = position.x.floor();
    final blockY = position.y.floor();
    final blockZ = position.z.floor();

    if (chunkHost.isBlockLoaded(blockX, blockY, blockZ)) {
      final biome = level.biomeAt(blockX, blockY, blockZ);
      if (biome != null) subLevel.getPlot().setBiome(biome);
    }

    return subLevel;
  }

  /// The holding chunk map of this container.
  SubLevelHoldingChunkMap getHoldingChunkMap() => holdingChunkMap;

  /// All sub-levels, typed as server sub-levels.
  List<ServerSubLevel> serverSubLevels() =>
      [for (final subLevel in getAllSubLevels()) subLevel as ServerSubLevel];

  /// Adds a force-loading ticket to [subLevel].
  ///
  /// Two tickets with the same type and key on the same sub-level cannot exist.
  /// Returns whether the ticket was added.
  bool addForceLoadTicket<T>(ServerSubLevel subLevel, SubLevelLoadingTicketType<T> ticketType, T key) {
    final uuid = subLevel.uniqueId;
    final ticket = SubLevelLoadingTicket<T>(ticketType, uuid, key);

    final loadedSet = activeTickets.putIfAbsent(subLevel, () => {});
    final info = allTickets.putIfAbsent(uuid, () => SubLevelTicketInfo());
    loadedSet.add(ticket as SubLevelLoadingTicket<Object?>);

    if (info.tickets.add(ticket as SubLevelLoadingTicket<Object?>)) {
      markTicketsDirty();
      return true;
    }
    return false;
  }

  /// Removes a force-loading ticket from [subLevel].
  ///
  /// Returns whether the ticket existed.
  bool removeForceLoadTicket<T>(ServerSubLevel subLevel, SubLevelLoadingTicketType<T> ticketType, T key) {
    final uuid = subLevel.uniqueId;
    final ticket = SubLevelLoadingTicket<T>(ticketType, uuid, key) as SubLevelLoadingTicket<Object?>;

    final loadedSet = activeTickets[subLevel];
    final info = allTickets[uuid];

    if (loadedSet != null) {
      loadedSet.remove(ticket);
      if (loadedSet.isEmpty) activeTickets.remove(subLevel);
    }

    if (info != null) {
      final existed = info.tickets.remove(ticket);
      if (info.tickets.isEmpty) allTickets.remove(uuid);
      if (existed) {
        markTicketsDirty();
        return true;
      }
    }
    return false;
  }

  /// Marks the ticket saved data dirty.
  void markTicketsDirty() => hostOrNull?.markSavedDataDirty(ticketsSavedDataName);

  /// Collects all force-loaded sub-levels, including their dependency chains.
  ///
  /// DEPENDS ON W3: `SubLevelHelper.getLoadingDependencyChain` lives with the
  /// physics/assembly code. Without it, the directly ticketed sub-levels are
  /// returned.
  Set<ServerSubLevel> collectForceLoadedSubLevels() => activeTickets.keys.toSet();

  /// The active tickets, unmodifiable.
  Map<ServerSubLevel, Set<SubLevelLoadingTicket<Object?>>> collectForceLoadTickets() =>
      Map.unmodifiable(activeTickets);

  /// Loads sub-level tickets (from the saved data).
  void loadTickets(Map<String, SubLevelTicketInfo> tickets) => allTickets.addAll(tickets);

  /// All sub-level loading tickets, unmodifiable.
  Map<String, SubLevelTicketInfo> getAllTickets() => Map.unmodifiable(allTickets);

  void loadForceLoadedSubLevels() {
    for (final entry in allTickets.entries) {
      final pointer = entry.value.pointer;
      if (pointer != null) {
        holdingChunkMap.snatchAndLoad(pointer, entry.key);
      }
      // A ticket without a pointer cannot be loaded (Java logs an error).
    }
  }

  /// Releases all native resources.
  void close() {
    for (final subLevel in serverSubLevels()) {
      removeSubLevelAt(subLevel, SubLevelRemovalReason.unloaded);
    }
    holdingChunkMap.close();
  }

  @override
  String toString() => 'ServerSubLevelContainer${super.toString()}';
}

/// The pointer to a sub-level's save location, resolved for a sub-level.
GlobalSavedSubLevelPointer? pointerOf(ServerSubLevel subLevel) => subLevel.getLastSerializationPointer();
