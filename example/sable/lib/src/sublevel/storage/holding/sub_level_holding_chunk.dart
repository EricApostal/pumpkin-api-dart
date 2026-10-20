// `dev.ryanhcode.sable.sublevel.storage.holding.SubLevelHoldingChunk`: a
// chunk-sized container of unloaded sub-level data held in memory.
//
// A holding chunk is keyed by the chunk the sub-level's position is in. It
// keeps the local pointers stored in that chunk's region entry, and the
// half-loaded sub-levels the pointers resolve to. When every chunk of a
// sub-level's bounds is loaded, `collectReadySubLevels` hands it to the map to
// be fully loaded.
//
// Pure: no host imports (chunk load state comes from `PlotChunkHost`).
import '../../host/sub_level_host.dart';
import '../../math/bounding_box.dart';
import '../holding_sub_level.dart';
import '../holding/saved_pointer.dart';
import '../serialization/sub_level_data.dart';

/// A chunk-sized container of unloaded sub-level data in memory.
final class SubLevelHoldingChunk {
  final List<HoldingSubLevel> alsoLoad = [];
  final List<SavedSubLevelPointer> pointers = [];
  final Map<String, HoldingSubLevel> loadedHoldingSubLevels = {};
  final (int, int) pos;
  final Set<String> visitedSet = {};
  bool keepLoaded = false;

  SubLevelHoldingChunk(this.pos);

  /// Adds a holding sub-level to this chunk.
  void acceptHoldingSubLevel(HoldingSubLevel subLevelData) =>
      loadedHoldingSubLevels[subLevelData.data.uuid] = subLevelData;

  /// The holding sub-levels of this chunk.
  Iterable<HoldingSubLevel> getLoadedHoldingSubLevels() => loadedHoldingSubLevels.values;

  /// Removes a holding sub-level by UUID.
  void removeHoldingSubLevel(String uniqueId) => loadedHoldingSubLevels.remove(uniqueId);

  /// Snatches a sub-level by ID, alongside all of its loading dependencies.
  ///
  /// Returns `null` when the sub-level is not in this chunk.
  List<HoldingSubLevel>? snatch(String subLevelId) {
    final holdingSubLevel = loadedHoldingSubLevels.remove(subLevelId);
    if (holdingSubLevel == null) return null;

    final snatched = <HoldingSubLevel>[holdingSubLevel];
    for (final uuid in holdingSubLevel.data.relations) {
      final dependency = loadedHoldingSubLevels.remove(uuid);
      if (dependency != null) snatched.add(dependency);
    }
    return snatched;
  }

  /// Collects all sub-levels that are completely ready for loading, removing
  /// them from this chunk and putting them into [readySubLevels].
  void collectReadySubLevels(PlotChunkHost level, Map<String, HoldingSubLevel> readySubLevels) {
    if (loadedHoldingSubLevels.isEmpty) return;

    visitedSet.clear();
    final keys = loadedHoldingSubLevels.keys.toList();

    checkingLoop:
    for (final key in keys) {
      if (visitedSet.contains(key)) continue;

      final holdingSubLevel = loadedHoldingSubLevels[key];
      if (holdingSubLevel == null) continue;

      final data = holdingSubLevel.data;
      final relations = data.relations;

      visitedSet.add(key);
      visitedSet.addAll(relations);

      for (final uuid in relations) {
        final dependency = loadedHoldingSubLevels[uuid];
        if (dependency == null) {
          // The dependency does not exist in this chunk: drop the sub-level.
          loadedHoldingSubLevels.remove(key);
          continue checkingLoop;
        }
        if (!canLoadSubLevel(level, dependency.data)) {
          continue checkingLoop;
        }
      }

      if (canLoadSubLevel(level, data)) {
        readySubLevels[data.uuid] = holdingSubLevel;
        loadedHoldingSubLevels.remove(key);

        for (final uuid in relations) {
          final dependency = loadedHoldingSubLevels[uuid];
          if (dependency != null) alsoLoad.add(dependency);
        }
      }
    }

    for (final holdingSubLevel in alsoLoad) {
      final uuid = holdingSubLevel.data.uuid;
      loadedHoldingSubLevels.remove(uuid);
      readySubLevels[uuid] = holdingSubLevel;
    }
    alsoLoad.clear();
  }

  /// Whether every chunk the sub-level's bounds touch is loaded enough.
  static bool canLoadSubLevel(PlotChunkHost level, SubLevelData data) {
    final bounds = data.bounds;

    final chunkBounds = BoundingBox3i.values(
      (bounds.minX - 1.0).floor() >> 4,
      (bounds.minY - 1.0).floor() >> 4,
      (bounds.minZ - 1.0).floor() >> 4,
      (bounds.maxX + 1.0).floor() >> 4,
      (bounds.maxY + 1.0).floor() >> 4,
      (bounds.maxZ + 1.0).floor() >> 4,
    );

    for (var x = chunkBounds.minX; x <= chunkBounds.maxX; x++) {
      for (var z = chunkBounds.minZ; z <= chunkBounds.maxZ; z++) {
        if (!level.isChunkLoadedEnough(x, z)) return false;
      }
    }
    return true;
  }

  /// `SubLevelHoldingChunk.from(pos, tag)`: reads the pointers of the chunk.
  static SubLevelHoldingChunk from((int, int) pos, Map<String, Object?> tag) {
    final chunk = SubLevelHoldingChunk(pos);
    final raw = tag['pointers'];
    if (raw is List) {
      for (final packed in raw) {
        chunk.pointers.add(SavedSubLevelPointer.unpack((packed as num).toInt()));
      }
    }
    return chunk;
  }

  /// `writeTo(tag)`: writes the packed pointers.
  void writeTo(Map<String, Object?> tag) =>
      tag['pointers'] = [for (final pointer in pointers) pointer.packed()];

  /// The chunk position.
  (int, int) getChunkPos() => pos;

  /// The pointers stored in this chunk.
  List<SavedSubLevelPointer> getSubLevelPointers() => pointers;

  /// Marks the chunk as kept loaded (it is in the player's view).
  void markKeepLoaded() => keepLoaded = true;

  /// Whether the chunk should stay loaded.
  bool shouldKeepLoaded() => keepLoaded;

  /// Whether the chunk holds nothing.
  bool isEmpty() => pointers.isEmpty && loadedHoldingSubLevels.isEmpty;

  @override
  String toString() => 'SubLevelHoldingChunk{pos=$pos, keepLoaded=$keepLoaded, pointers=$pointers}';
}
