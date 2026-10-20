// `dev.ryanhcode.sable.sublevel.system.ticket.PhysicsChunkTicketManager`: keeps
// the plot chunks a sub-level inhabits loaded and uploaded to the physics
// pipeline.
//
// Every tick it
//
// * drops the sections of chunks that stopped being loaded (and tells the
//   pipeline to forget them),
// * expires forced inhabitation tickets that no sub-level refreshed,
// * unloads a sub-level that entered an unloaded chunk (unless a player is
//   inside its bounds and `sub_levels_with_players_cannot_unload` is set),
// * uploads every section a loaded sub-level overlaps, and refreshes its
//   inhabitation ticket.
//
// The plot yard lives far outside every player's view distance, so "loaded"
// means "loaded for the plugin": `PlotChunkHost.isChunkLoadedEnough` is backed
// by the host's `chunk-tickets` interface (`force-load-chunk`), which is what
// keeps the chunks of a plot loaded and ticking with no player nearby.
//
// Pure: no host imports.
import '../host/sub_level_host.dart';
import '../math/bounding_box.dart';
import '../math/vector.dart';
import '../model/server_sub_level.dart';
import '../model/sub_level.dart';
import 'physics_system.dart';
import 'tickets.dart';
import 'plot_section_packer.dart';

/// The chunk ticket manager of one physics system.
final class PhysicsChunkTicketManager {
  /// `MAX_PREDICTION_DISTANCE`: the furthest a sub-level's bounds are extended
  /// along y for the velocity prediction.
  static const double maxPredictionDistance = 20.0;

  /// `SUB_LEVEL_LOADED_TICKET_TYPE`: the host ticket type that keeps a plot
  /// chunk loaded and simulated. The plugin maps it onto the host's
  /// `chunk-tickets.force-load-chunk`.
  static const String subLevelLoadedTicketType = 'sable:sub_level_loaded';

  /// The ticket level: entity-ticking
  /// (`ChunkLevel.byStatus(FullChunkStatus.ENTITY_TICKING)`).
  static const int subLevelLoadedTicketLevel = 31;

  /// The uploaded sections, by section position.
  final Map<(int, int, int), PhysicsChunkTicket> physicsChunks = {};

  /// The forced inhabitation tickets, by packed chunk position.
  final Map<int, Set<InhabitedChunkTicket>> forcedInhabitedChunks = {};

  /// Packs a section for the pipeline; `null` leaves sections unuploaded (the
  /// pipeline then has no collision data for the plot).
  PlotSectionPacker? packer;

  /// Sections whose blocks changed since they were last uploaded, by section
  /// position.
  final Set<(int, int, int)> dirtySections = {};

  /// The system this manager belongs to.
  final SubLevelPhysicsSystem system;

  PhysicsChunkTicketManager(this.system);

  /// `update(level, container, system, pipeline, timeStep)`.
  void update(double timeStep) {
    final container = system.container;
    final host = container.chunkHost;
    final gameTime = container.level.gameTime;

    final forceLoaded = container.collectForceLoadedSubLevels();

    _expirePhysicsChunkTickets(gameTime);

    if (system.ignoreChunks) return;

    _expireForcedInhabitedChunks(gameTime);

    final unloadedChunks = <int>{};
    final cannotUnloadPlayerInhabited = system.config.subLevelsWithPlayersCannotUnload;
    final bounds = BoundingBox3d();
    final predicted = BoundingBox3d();
    final velocity = Vector3d();

    for (final object in system.arbitraryObjects.toList(growable: false)) {
      object.getBoundingBox(bounds);
      if (_isEmpty(bounds)) continue;
      bounds.expand(1.0);
      final chunkBounds = bounds.chunkBoundsFrom();
      var unloaded = false;

      for (var x = chunkBounds.minX; x <= chunkBounds.maxX && !unloaded; x++) {
        for (var z = chunkBounds.minZ; z <= chunkBounds.maxZ; z++) {
          final packed = _packChunk(x, z);
          if (!_isChunkLoadedEnough(x, z) || unloadedChunks.contains(packed)) {
            object.onUnloaded(container.holdingChunkMap, (x, z));
            unloadedChunks.add(packed);
            unloaded = true;
            break;
          }
        }
      }
      if (unloaded) {
        system.removeObject(object);
        continue;
      }

      for (var x = chunkBounds.minX; x <= chunkBounds.maxX; x++) {
        for (var z = chunkBounds.minZ; z <= chunkBounds.maxZ; z++) {
          for (var y = chunkBounds.minY; y <= chunkBounds.maxY; y++) {
            _addTicket(x, y, z, gameTime);
          }
        }
      }
    }

    final subLevels = container.serverSubLevels();
    subLevelLoop:
    for (var i = 0; i < subLevels.length; i++) {
      final subLevel = subLevels[i];
      if (subLevel.isRemoved()) continue;

      final globalBounds = subLevel.boundingBox;
      // A sub-level with no solid blocks has an empty box (`BoundingBox3i.empty`
      // is inverted: min at INT_MAX, max at INT_MIN). It inhabits no chunk, and
      // iterating its chunk range would run for billions of steps.
      if (_isEmpty(globalBounds)) continue;

      bounds.set(globalBounds);
      predicted.set(bounds);

      // Only predict when there is some movement (1 m/s).
      if (subLevel.lastPose.position().distanceSquared(subLevel.logicalPose.position()) > 0.05 * 0.05) {
        system.getLinearVelocity(subLevel, velocity.zero()).mul(timeStep);
        predicted.move(
          0.0,
          velocity.y.clamp(-maxPredictionDistance, maxPredictionDistance),
          0.0,
        );
        bounds.expandToBox(predicted);
      }

      bounds.expand(1.0);
      final chunkBounds = bounds.chunkBoundsFrom();

      var checkedPlayerInhabited = false;
      var playerInhabited = false;
      final forceLoadedSubLevel = forceLoaded.contains(subLevel);

      for (var x = chunkBounds.minX; x <= chunkBounds.maxX; x++) {
        for (var z = chunkBounds.minZ; z <= chunkBounds.maxZ; z++) {
          final packed = _packChunk(x, z);
          final loadedEnough = _isChunkLoadedEnough(x, z);

          if (forceLoadedSubLevel) {
            _inhabitChunk(host, subLevel, gameTime, packed, x, z);
            continue;
          }

          if (loadedEnough && !unloadedChunks.contains(packed)) continue;

          // The sub-level has now entered an unloaded chunk.
          unloadedChunks.add(packed);

          if (!checkedPlayerInhabited && cannotUnloadPlayerInhabited) {
            playerInhabited = _hasPlayerInside(bounds);
            checkedPlayerInhabited = true;
          }

          if (!cannotUnloadPlayerInhabited || !playerInhabited) {
            container.holdingChunkMap.moveToUnloaded(subLevel, (x, z));
            // Java steps the index back because it iterates the container's
            // live list; this loop iterates a snapshot, so stepping back would
            // revisit the same (now unloaded) sub-level.
            continue subLevelLoop;
          }

          _inhabitChunk(host, subLevel, gameTime, packed, x, z);
        }
      }

      for (var x = chunkBounds.minX; x <= chunkBounds.maxX; x++) {
        for (var z = chunkBounds.minZ; z <= chunkBounds.maxZ; z++) {
          for (var y = chunkBounds.minY; y <= chunkBounds.maxY; y++) {
            final ticket = _addTicket(x, y, z, gameTime);
            if (SubLevelPhysicsSystem.useTicketsForQueries) {
              ticket.residentSubLevels.add(subLevel);
            }
          }
        }
      }
    }
  }

  /// `inhabitChunk`: marks the chunk as sub-level inhabited and force-loads it.
  void _inhabitChunk(
    PlotChunkHost host,
    ServerSubLevel subLevel,
    int gameTime,
    int packed,
    int x,
    int z,
  ) {
    final set = forcedInhabitedChunks.putIfAbsent(packed, () => <InhabitedChunkTicket>{});
    final ticket = InhabitedChunkTicket(subLevel.uniqueId, gameTime, (x, z));

    if (set.add(ticket)) {
      host.addChunkTicket(x, z, subLevelLoadedTicketType, subLevelLoadedTicketLevel);
      return;
    }

    // Same sub-level, same chunk: refresh the inhabitation tick.
    for (final existing in set) {
      if (existing == ticket) {
        existing.lastInhabitedTick = gameTime;
        return;
      }
    }
  }

  void _expirePhysicsChunkTickets(int gameTime) {
    final container = system.container;
    final entries = physicsChunks.entries.toList(growable: false);

    for (final entry in entries) {
      final ticket = entry.value;
      final (x, y, z) = entry.key;
      final plot = container.getPlot(x, z);

      final outdated = ticket.lastInhabitedTick < gameTime - 20 && plot == null;
      final noLongerExistent = !_isChunkLoadedEnough(x, z);

      if (outdated || noLongerExistent) {
        system.handleChunkSectionRemoval(x, y, z);
        physicsChunks.remove(entry.key);
      } else if (ticket.residentSubLevels.isNotEmpty) {
        ticket.residentSubLevels.clear();
      }
    }
  }

  void _expireForcedInhabitedChunks(int gameTime) {
    final host = system.container.chunkHost;
    final entries = forcedInhabitedChunks.entries.toList(growable: false);

    for (final entry in entries) {
      entry.value.removeWhere((ticket) => ticket.lastInhabitedTick < gameTime - 20);
      if (entry.value.isEmpty) {
        final x = entry.key & 0xFFFFFFFF;
        final z = (entry.key >>> 32) & 0xFFFFFFFF;
        host.removeChunkTicket(x, z, subLevelLoadedTicketType, subLevelLoadedTicketLevel);
        forcedInhabitedChunks.remove(entry.key);
      }
    }
  }

  /// `addTicket`: uploads the section if it is not tracked yet, and refreshes
  /// the inhabitation tick.
  PhysicsChunkTicket _addTicket(int x, int y, int z, int gameTime) {
    final sectionPos = (x, y, z);
    var ticket = physicsChunks[sectionPos];

    if (ticket == null) {
      _uploadSection(x, y, z);
      ticket = PhysicsChunkTicket(
        sectionPos,
        gameTime,
        <SubLevel>[],
      );
      physicsChunks[sectionPos] = ticket;
    }

    ticket.lastInhabitedTick = gameTime;
    return ticket;
  }

  /// `addSectionIfNotTracked`: used on a block change, to make sure the section
  /// the changed block lives in reaches the pipeline.
  void addSectionIfNotTracked(int x, int y, int z) {
    if (physicsChunks.containsKey((x, y, z))) return;
    _uploadSection(x, y, z);
    physicsChunks[(x, y, z)] = PhysicsChunkTicket((x, y, z), system.gameTime, <SubLevel>[]);
  }

  /// Marks the section containing the block at [x],[y],[z] as changed, so the
  /// next [flushDirtySections] re-uploads it.
  void markSectionDirty(int x, int y, int z) => dirtySections.add((x >> 4, y >> 4, z >> 4));

  /// Re-uploads every dirty section and clears the set.
  ///
  /// Called at the end of the physics system's tick, so a tick that changes
  /// many blocks in one section uploads it once.
  void flushDirtySections() {
    if (dirtySections.isEmpty) return;

    for (final (x, y, z) in dirtySections) {
      if (!physicsChunks.containsKey((x, y, z))) {
        // A section that is not tracked yet is uploaded by `_addTicket`.
        continue;
      }
      _uploadSection(x, y, z);
    }
    dirtySections.clear();
  }

  /// `addTicketForSection`: marks the section tracked without uploading it.
  void addTicketForSection(int x, int y, int z) {
    physicsChunks[(x, y, z)] = PhysicsChunkTicket((x, y, z), system.gameTime, <SubLevel>[]);
  }

  void _uploadSection(int x, int y, int z) {
    final packer = this.packer;
    if (packer == null) return;

    final host = system.container.chunkHost;
    final chunk = host.getLoadedChunk(x, z);
    if (chunk == null) return;

    final sectionIndex = _sectionIndex(y);
    if (sectionIndex < 0 || sectionIndex >= chunk.sectionsCount) return;

    system.handleChunkSectionAddition(x, y, z, packer.packSection(chunk, sectionIndex));
  }

  int _sectionIndex(int sectionY) {
    final level = system.container.level;
    return sectionY - (level.minY >> 4);
  }

  bool _isChunkLoadedEnough(int x, int z) {
    final container = system.container;
    if (container.inBounds(x, z)) return true;
    return container.chunkHost.isChunkLoadedEnough(x, z);
  }

  bool _hasPlayerInside(BoundingBox3d bounds) {
    final host = system.container.hostOrNull;
    if (host == null) return false;
    for (final player in host.players) {
      final (x, y, z) = player.position;
      if (bounds.containsValues(x, y, z)) return true;
    }
    return false;
  }

  /// Whether [box] is empty, i.e. inverted on any axis.
  static bool _isEmpty(BoundingBox3dc box) =>
      box.maxX < box.minX || box.maxY < box.minY || box.maxZ < box.minZ;

  static int _packChunk(int x, int z) => (x & 0xFFFFFFFF) | (z & 0xFFFFFFFF) << 32;

  /// The sections currently uploaded, for diagnostics and tests.
  Set<(int, int, int)> get trackedSections => physicsChunks.keys.toSet();

  /// Forgets every tracked section without telling the pipeline (the pipeline
  /// was disposed).
  void clear() {
    physicsChunks.clear();
    forcedInhabitedChunks.clear();
    dirtySections.clear();
  }

  @override
  String toString() =>
      'PhysicsChunkTicketManager[sections=${physicsChunks.length}, '
      'inhabited=${forcedInhabitedChunks.length}]';
}
