// `dev.ryanhcode.sable.sublevel.storage.holding.SubLevelHoldingChunkMap`:
// keeps the sub-levels of a level in memory or on disk as the chunks under them
// load and unload.
//
// A sub-level lives "in" the chunk that contains its pose position. When that
// chunk unloads, the sub-level is serialized into that chunk's holding chunk
// (unless it is force-loaded); when the chunk loads again, the holding chunk's
// entries are loaded back once all the chunks the sub-level overlaps are
// loaded.
//
// Pure: no host imports.
import '../../host/sub_level_host.dart';
import '../../math/bounding_box.dart';
import '../../math/vector.dart';
import '../../model/server_sub_level.dart';
import '../../model/server_sub_level_container.dart';
import '../../model/sub_level_container.dart';
import '../../tracking_points/tracking_point.dart';
import '../holding_sub_level.dart';
import '../holding/saved_pointer.dart';
import '../holding/sub_level_holding_chunk.dart';
import '../serialization/sub_level_data.dart';
import '../serialization/sub_level_serializer.dart';
import '../serialization/sub_level_storage.dart';
import '../sub_level_removal_reason.dart';

/// Manages the sub-level holding chunks and regions for a level.
final class SubLevelHoldingChunkMap {
  final SubLevelContainer container;
  final SubLevelStorage storage;
  final PlotChunkHost level;

  /// All sub-levels currently in holding, by UUID.
  final Map<String, HoldingSubLevel> allHoldingSubLevels = {};

  /// All currently loaded holding chunks, by packed chunk position.
  final Map<int, SubLevelHoldingChunk> loadedHoldingChunks = {};

  /// The dirty holding chunks that need saving.
  final Set<int> dirtyHoldingChunks = {};

  /// Holding chunks that can be dropped after the next save.
  final Set<(int, int)> queuedUnloads = {};

  /// Deleted sub-levels that must be cleared from their storage.
  final Set<GlobalSavedSubLevelPointer> queuedDeletion = {};

  /// Chunk positions that unloaded in the previous tick.
  final Set<int> chunksToUnload = {};

  /// Chunk positions that loaded in the previous tick.
  final Set<int> chunksToLoad = {};

  /// The tracking point store, when the level has one (points follow the
  /// sub-level when it moves to another chunk).
  TrackingPointStore? trackingPoints;

  /// Whether verbose logging is on (`SableConfig.verboseSerializationLogging`).
  bool verboseLogging = false;

  SubLevelHoldingChunkMap(this.container, this.level, this.storage);

  /// Packs a chunk position into a map key.
  static int pack(int x, int z) => (x << 32) | (z & 0xFFFFFFFF);

  /// The chunk position of a packed key.
  static (int, int) unpack(int key) => (key >> 32, (key << 32) >> 32);

  /// Records that a chunk loaded or unloaded.
  void updateChunkStatus(int chunkX, int chunkZ, bool loaded) {
    final key = pack(chunkX, chunkZ);
    if (!loaded) {
      chunksToUnload.add(key);
      chunksToLoad.remove(key);
    } else {
      chunksToLoad.add(key);
      chunksToUnload.remove(key);
    }
  }

  void _processLoad(int chunkX, int chunkZ) {
    final pos = (chunkX, chunkZ);
    queuedUnloads.remove(pos);

    final key = pack(chunkX, chunkZ);
    final existing = loadedHoldingChunks[key];
    if (existing != null) {
      existing.markKeepLoaded();
      return;
    }

    final holdingChunk = _getOrLoadHoldingChunk(chunkX, chunkZ, false);
    holdingChunk?.markKeepLoaded();
  }

  void _processUnload(int chunkX, int chunkZ, Set<ServerSubLevel> forceLoaded) {
    final key = pack(chunkX, chunkZ);
    if (!loadedHoldingChunks.containsKey(key)) return;

    final bounds = BoundingBox3d.full(
      (chunkX << 4).toDouble(),
      double.negativeInfinity,
      (chunkZ << 4).toDouble(),
      ((chunkX << 4) + 16).toDouble(),
      double.infinity,
      ((chunkZ << 4) + 16).toDouble(),
    );

    final toUnload = <ServerSubLevel>{
      for (final subLevel in container.queryIntersecting(bounds))
        if (subLevel is ServerSubLevel) subLevel,
    };

    queuedUnloads.add((chunkX, chunkZ));
    if (toUnload.isEmpty) return;

    final holdingChunk = _getOrLoadHoldingChunk(chunkX, chunkZ, true)!;
    final visited = <ServerSubLevel>{};

    for (final subLevel in toUnload) {
      if (forceLoaded.contains(subLevel)) {
        visited.add(subLevel);
        continue;
      }
      if (visited.contains(subLevel)) continue;

      // DEPENDS ON W3: the full dependency chain comes from the assembly code.
      final chain = <ServerSubLevel>[subLevel];
      visited.addAll(chain);

      final uuids = [for (final chained in chain) chained.uniqueId];

      for (final chained in chain) {
        final data = SubLevelSerializer.toData(chained, uuids);
        final holdingSubLevel = HoldingSubLevel(data, chained.getLastSerializationPointer());
        holdingChunk.acceptHoldingSubLevel(holdingSubLevel);
        allHoldingSubLevels[data.uuid] = holdingSubLevel;

        container.removeSubLevelAt(chained, SubLevelRemovalReason.unloaded);
      }
    }
  }

  /// Saves the whole holding chunk map to disk.
  void saveAll() {
    processChanges();

    for (final deletion in queuedDeletion) {
      storage.attemptSaveSubLevelAt(deletion, null);
    }
    queuedDeletion.clear();

    final subLevels = container.getAllSubLevels().whereType<ServerSubLevel>().toList();
    final toMove = [...subLevels];
    final moved = <ServerSubLevel>{};

    for (final subLevel in toMove) {
      if (moved.contains(subLevel)) continue;

      final currentPosition = subLevel.logicalPose.position();
      final moveToChunk = (currentPosition.x.floor() >> 4, currentPosition.z.floor() >> 4);

      // DEPENDS ON W3: the loading dependency chain.
      final chain = <ServerSubLevel>[subLevel];
      moved.addAll(chain);

      final uuids = [for (final chained in chain) chained.uniqueId];
      for (final chained in chain) {
        _moveAndSaveSubLevel(chained, moveToChunk, uuids);
        _getOrLoadHoldingChunk(moveToChunk.$1, moveToChunk.$2, true)!.markKeepLoaded();
      }
    }

    for (final holdingChunk in loadedHoldingChunks.values.toList()) {
      final holdingChunkPos = holdingChunk.pos;

      for (final holdingSubLevel in holdingChunk.getLoadedHoldingSubLevels()) {
        final pointer = holdingSubLevel.pointer;
        if (pointer == null || pointer.chunkX != holdingChunkPos.$1 || pointer.chunkZ != holdingChunkPos.$2) {
          final newPointer = _moveAndSave(
            null,
            holdingSubLevel.data,
            pointer,
            holdingChunkPos,
          );
          holdingSubLevel.setPointer(newPointer);
        } else {
          storage.attemptSaveSubLevelAt(pointer, holdingSubLevel.data);
        }
      }

      if (!holdingChunk.shouldKeepLoaded() && !level.isChunkLoadedEnough(holdingChunkPos.$1, holdingChunkPos.$2)) {
        queuedUnloads.add(holdingChunkPos);
      }
      if (holdingChunk.isEmpty()) queuedUnloads.add(holdingChunkPos);
    }

    for (final unload in queuedUnloads) {
      final holdingChunk = loadedHoldingChunks[pack(unload.$1, unload.$2)];
      if (holdingChunk != null) {
        for (final holdingSubLevel in holdingChunk.getLoadedHoldingSubLevels()) {
          allHoldingSubLevels.remove(holdingSubLevel.data.uuid);
        }
        _setDirty(unload.$1, unload.$2);
      }
    }

    for (final key in dirtyHoldingChunks) {
      final pos = unpack(key);
      final holdingChunk = loadedHoldingChunks[key];
      if (holdingChunk == null) continue;
      if (holdingChunk.isEmpty()) {
        storage.attemptRemoveHoldingChunk(pos.$1, pos.$2);
      } else {
        storage.attemptSaveHoldingChunk(pos.$1, pos.$2, holdingChunk);
      }
    }

    for (final unload in queuedUnloads) {
      loadedHoldingChunks.remove(pack(unload.$1, unload.$2));
    }
    queuedUnloads.clear();

    storage.flush();
    storage.pruneCache();
  }

  void _moveAndSaveSubLevel(ServerSubLevel subLevel, (int, int) moveToChunk, List<String> uuids) {
    final lastPointer = subLevel.getLastSerializationPointer();
    final data = SubLevelSerializer.toData(subLevel, uuids);
    subLevel.setLastSerializationPointer(_moveAndSave(subLevel, data, lastPointer, moveToChunk));
  }

  /// Removes sub-level data from a previous pointer and moves it to a new one.
  GlobalSavedSubLevelPointer? _moveAndSave(
    ServerSubLevel? subLevel,
    SubLevelData data,
    GlobalSavedSubLevelPointer? lastPointer,
    (int, int) moveToChunk,
  ) {
    final oldChunk = lastPointer == null ? null : (lastPointer.chunkX, lastPointer.chunkZ);

    if (oldChunk == moveToChunk) {
      if (_getOrLoadHoldingChunk(moveToChunk.$1, moveToChunk.$2, false) == null) {
        throw StateError('this should not be possible');
      }
      storage.attemptSaveSubLevelAt(lastPointer!, data);
      _setDirty(moveToChunk.$1, moveToChunk.$2);
      return lastPointer;
    }

    final newPointer = storage.attemptSaveSubLevel(moveToChunk.$1, moveToChunk.$2, data);
    if (newPointer == null) return null;

    // Move the tracking points that follow this sub-level.
    final points = trackingPoints;
    if (points != null) {
      for (final entry in points.getAllTrackingPoints().toList()) {
        final point = entry.value;
        if (!point.inSubLevel) continue;

        final movingPointers =
            point.lastSavedSubLevelPointer != null && point.lastSavedSubLevelPointer == lastPointer;
        final pointerInSubLevel = subLevel != null && point.subLevelId == subLevel.uniqueId;

        if (movingPointers || pointerInSubLevel) {
          points.setTrackingPoint(
            entry.key,
            TrackingPoint(true, point.subLevelId, newPointer, point.point, null),
          );
        }
      }
    }

    if (oldChunk != null) {
      final oldHoldingChunk = _getOrLoadHoldingChunk(oldChunk.$1, oldChunk.$2, false);
      if (oldHoldingChunk != null) {
        oldHoldingChunk.getSubLevelPointers().remove(lastPointer!.local);
        _setDirty(oldChunk.$1, oldChunk.$2);
      }
    }

    if (lastPointer != null) {
      storage.attemptSaveSubLevelAt(lastPointer, null);
    }

    final newHoldingChunk = _getOrLoadHoldingChunk(moveToChunk.$1, moveToChunk.$2, true)!;
    newHoldingChunk.getSubLevelPointers().add(newPointer.local);
    _setDirty(moveToChunk.$1, moveToChunk.$2);

    return newPointer;
  }

  /// Gets or loads the holding chunk at [chunkX], [chunkZ].
  SubLevelHoldingChunk? _getOrLoadHoldingChunk(int chunkX, int chunkZ, bool create) {
    final key = pack(chunkX, chunkZ);
    final existing = loadedHoldingChunks[key];
    if (existing != null) return existing;

    final loaded = storage.attemptLoadHoldingChunk(chunkX, chunkZ);
    if (loaded != null) {
      for (final pointer in loaded.getSubLevelPointers().toList()) {
        final data = storage.attemptLoadSubLevel(chunkX, chunkZ, pointer);
        if (data == null) continue;

        if (container.getSubLevelById(data.uuid) != null || allHoldingSubLevels.containsKey(data.uuid)) {
          continue;
        }

        final globalPointer = GlobalSavedSubLevelPointer(
          chunkX,
          chunkZ,
          pointer.storageIndex,
          pointer.subLevelIndex,
        );
        final holdingSubLevel = HoldingSubLevel(data, globalPointer);
        loaded.acceptHoldingSubLevel(holdingSubLevel);
        allHoldingSubLevels[data.uuid] = holdingSubLevel;
      }

      loadedHoldingChunks[key] = loaded;
      return loaded;
    }

    if (create) {
      final created = SubLevelHoldingChunk((chunkX, chunkZ));
      loadedHoldingChunks[key] = created;
      return created;
    }
    return null;
  }

  /// Snatches a sub-level by pointer and UUID and force-loads it and its
  /// dependencies.
  void snatchAndLoad(GlobalSavedSubLevelPointer pointer, String subLevelId) {
    final holdingChunk = _getOrLoadHoldingChunk(pointer.chunkX, pointer.chunkZ, false);
    if (holdingChunk == null) return;

    final holdingSubLevels = holdingChunk.snatch(subLevelId);
    if (holdingSubLevels == null) return;

    _setDirty(pointer.chunkX, pointer.chunkZ);
    for (final holdingSubLevel in holdingSubLevels) {
      loadHoldingSubLevel(holdingSubLevel);
    }
  }

  void _setDirty(int chunkX, int chunkZ) => dirtyHoldingChunks.add(pack(chunkX, chunkZ));

  /// Ticks the holding chunk map, checking for sub-levels ready to load.
  void processChanges() {
    _processUnloads();

    final readySubLevels = <String, HoldingSubLevel>{};
    for (final chunk in loadedHoldingChunks.values) {
      if (queuedUnloads.contains(chunk.pos)) continue;
      chunk.collectReadySubLevels(level, readySubLevels);
    }

    for (final holdingSubLevel in readySubLevels.values) {
      loadHoldingSubLevel(holdingSubLevel);
    }
  }

  /// Fully loads a holding sub-level.
  void loadHoldingSubLevel(HoldingSubLevel holdingSubLevel) {
    final subLevel = SubLevelSerializer.fullyLoad(container, holdingSubLevel.data);
    if (subLevel != null) {
      subLevel.setLastSerializationPointer(holdingSubLevel.pointer);
    }
    allHoldingSubLevels.remove(holdingSubLevel.data.uuid);
  }

  /// The holding sub-level of [uuid], if one is waiting to be loaded.
  HoldingSubLevel? getHoldingSubLevel(String uuid) => allHoldingSubLevels[uuid];

  void _processUnloads() {
    final forceLoaded = container is ServerSubLevelContainer
        ? (container as ServerSubLevelContainer).collectForceLoadedSubLevels()
        : <ServerSubLevel>{};

    for (final key in chunksToUnload) {
      final pos = unpack(key);
      _processUnload(pos.$1, pos.$2, forceLoaded);
    }
    for (final key in chunksToLoad) {
      final pos = unpack(key);
      _processLoad(pos.$1, pos.$2);
    }
    chunksToUnload.clear();
    chunksToLoad.clear();
  }

  /// Moves [subLevel] into the holding chunk at [pos] (the chunk under it
  /// unloaded).
  void moveToUnloaded(ServerSubLevel subLevel, (int, int) pos) {
    // DEPENDS ON W3: the dependency chain.
    final chain = <ServerSubLevel>[subLevel];
    final uuids = [for (final chained in chain) chained.uniqueId];

    final holdingChunk = _getOrLoadHoldingChunk(pos.$1, pos.$2, true)!;
    for (final chained in chain) {
      final data = SubLevelSerializer.toData(chained, uuids);
      final holdingSubLevel = HoldingSubLevel(data, chained.getLastSerializationPointer());
      holdingChunk.acceptHoldingSubLevel(holdingSubLevel);
      allHoldingSubLevels[data.uuid] = holdingSubLevel;
      container.removeSubLevelAt(chained, SubLevelRemovalReason.unloaded);
    }
    _setDirty(pos.$1, pos.$2);
  }

  /// Queues a deleted sub-level for removal from its holding chunk and storage.
  void queueDeletion(ServerSubLevel subLevel) {
    final pointer = subLevel.getLastSerializationPointer();
    if (pointer == null) return;

    final holdingChunk = _getOrLoadHoldingChunk(pointer.chunkX, pointer.chunkZ, false);
    if (holdingChunk != null) {
      allHoldingSubLevels.remove(subLevel.uniqueId);
      holdingChunk.removeHoldingSubLevel(subLevel.uniqueId);
      holdingChunk.getSubLevelPointers().remove(pointer.local);
      _setDirty(pointer.chunkX, pointer.chunkZ);
    }
    queuedDeletion.add(pointer);
  }

  /// The storage of this map.
  SubLevelStorage getStorage() => storage;

  /// Closes the storage.
  void close() => storage.close();

  /// The number of sub-levels waiting in holding.
  int get holdingCount => allHoldingSubLevels.length;

  /// The vector of a saved position, for diagnostics.
  static Vector3d positionOf(SubLevelData data) => Vector3d.copy(data.pose.position());
}
