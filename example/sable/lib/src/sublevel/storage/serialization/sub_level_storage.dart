// `dev.ryanhcode.sable.sublevel.storage.serialization.SubLevelStorage`: manages
// the sub-level holding chunks and region files of one level.
//
// File names match the Java mod: `r.<regionX>.<regionZ>.slvlr` for the chunk
// table, `r.<regionX>.<regionZ>.<index>.slvls` for the storage files and
// `r.<regionX>.<regionZ>.<index>.s` for oversized payloads.
//
// Pure: no host imports (the file store is an interface).
import '../../host/sub_level_host.dart';
import '../../math/bounding_box.dart';
import '../../math/vector.dart';
import '../holding/saved_pointer.dart';
import '../holding/sub_level_holding_chunk.dart';
import '../region/sub_level_storage_file.dart';
import 'sub_level_data.dart';
import 'sub_level_serializer.dart';

/// Manages the sub-level holding chunks and regions for a level.
final class SubLevelStorage {
  /// The maximum number of cached region/storage files.
  static int maxCacheSize = 128;

  /// The extension of the region files.
  static const String regionExtension = '.slvlr';

  final SableFileStore store;
  final String folder;
  final SubLevelCodec codec;

  /// The open region files by packed region position.
  final Map<int, SubLevelRegionFile> regionCache = {};

  /// The open storage files by packed (region, index).
  final Map<int, SubLevelStorageFile> storageCache = {};

  SubLevelStorage(this.store, this.folder, this.codec);

  /// The file name of the region at [chunkX], [chunkZ].
  static String fileName(int chunkX, int chunkZ) => 'r.${chunkX >> 5}.${chunkZ >> 5}';

  static int _regionKey(int chunkX, int chunkZ) => ((chunkX >> 5) << 16) ^ ((chunkZ >> 5) & 0xFFFF);

  SubLevelRegionFile getRegionFile(int chunkX, int chunkZ) {
    final key = _regionKey(chunkX, chunkZ);
    final existing = regionCache[key];
    if (existing != null) return existing;

    if (regionCache.length >= maxCacheSize) {
      final lastKey = regionCache.keys.first;
      final last = regionCache.remove(lastKey)!;
      if (last.isEmptyFile && pruneEmptyFiles) {
        last.delete();
      } else {
        last.close();
      }
    }

    final name = fileName(chunkX, chunkZ);
    final file = SubLevelRegionFile.open(
      store,
      '$folder/$name$regionExtension',
      '$folder/$name.r',
      codec,
    );
    regionCache[key] = file;
    return file;
  }

  SubLevelStorageFile getStorageFile(int chunkX, int chunkZ, int index) {
    final key = _regionKey(chunkX, chunkZ) ^ (index << 24);
    final existing = storageCache[key];
    if (existing != null) return existing;

    if (storageCache.length >= maxCacheSize) {
      final lastKey = storageCache.keys.first;
      final last = storageCache.remove(lastKey)!;
      if (last.isEmptyFile && pruneEmptyFiles) {
        last.delete();
      } else {
        last.close();
      }
    }

    final name = fileName(chunkX, chunkZ);
    final file = SubLevelStorageFile.open(
      store,
      '$folder/$name.$index${SubLevelStorageFile.fileExtension}',
      '$folder/$name.$index.s',
      codec,
    );
    storageCache[key] = file;
    return file;
  }

  /// Whether empty files are deleted instead of kept (`SUB_LEVEL_STORAGE_PRUNING`).
  bool pruneEmptyFiles = true;

  /// Loads the holding chunk at [chunkX], [chunkZ], or `null`.
  SubLevelHoldingChunk? attemptLoadHoldingChunk(int chunkX, int chunkZ) {
    try {
      final tag = getRegionFile(chunkX, chunkZ).read(chunkX, chunkZ);
      if (tag == null) return null;
      return SubLevelHoldingChunk.from((chunkX, chunkZ), tag);
    } catch (_) {
      return null;
    }
  }

  /// Saves the holding chunk at [chunkX], [chunkZ].
  void attemptSaveHoldingChunk(int chunkX, int chunkZ, SubLevelHoldingChunk holdingChunk) {
    try {
      final tag = <String, Object?>{};
      holdingChunk.writeTo(tag);
      getRegionFile(chunkX, chunkZ).trySave(chunkX & 31, chunkZ & 31, tag);
    } catch (_) {
      // Java logs and continues.
    }
  }

  /// Removes the holding chunk at [chunkX], [chunkZ].
  void attemptRemoveHoldingChunk(int chunkX, int chunkZ) {
    try {
      getRegionFile(chunkX, chunkZ).tryRemove(chunkX & 31, chunkZ & 31);
    } catch (_) {
      // Java logs and continues.
    }
  }

  /// Loads a [SubLevelData] from a chunk position and pointer.
  SubLevelData? attemptLoadSubLevel(int chunkX, int chunkZ, SavedSubLevelPointer pointer) {
    try {
      final storageFile = getStorageFile(chunkX, chunkZ, pointer.storageIndex);
      final tag = storageFile.read(pointer.subLevelIndex);
      if (tag == null) return null;

      final data = SubLevelSerializer.fromData(tag);
      if (data == null) return null;

      // Recover zeroed-out bounds (a known corruption in the Java mod).
      final bounds = data.bounds;
      if (bounds.minX == 0.0 &&
          bounds.minY == 0.0 &&
          bounds.minZ == 0.0 &&
          bounds.maxX == 0.0 &&
          bounds.maxY == 0.0 &&
          bounds.maxZ == 0.0) {
        final position = data.pose.position();
        bounds
            .setValues(position.x, position.y, position.z, position.x, position.y, position.z)
            .expand(1.0);
      }

      data.setOriginLoadedChunk((chunkX, chunkZ));
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Saves [subLevel] to a free index in [chunkX], [chunkZ], creating a new
  /// storage file when the current one is full.
  GlobalSavedSubLevelPointer? attemptSaveSubLevel(int chunkX, int chunkZ, SubLevelData subLevel) {
    try {
      var storageIndex = 0;
      while (true) {
        final storageFile = getStorageFile(chunkX, chunkZ, storageIndex);
        final subLevelIndex = storageFile.findFreeIndex();
        if (subLevelIndex != -1 && subLevelIndex < storageFile.totalIndexCapacity) {
          storageFile.write(subLevelIndex, subLevel.fullTag);
          return GlobalSavedSubLevelPointer(chunkX, chunkZ, storageIndex, subLevelIndex);
        }
        storageIndex++;
      }
    } catch (_) {
      return null;
    }
  }

  /// Saves [subLevel] at an existing pointer (`null` clears it).
  void attemptSaveSubLevelAt(GlobalSavedSubLevelPointer pointer, SubLevelData? subLevel) {
    try {
      final storageFile = getStorageFile(pointer.chunkX, pointer.chunkZ, pointer.storageIndex);
      storageFile.write(pointer.subLevelIndex, subLevel?.fullTag);
    } catch (_) {
      // Java logs and continues.
    }
  }

  /// The folder of the storage files.
  String getFolder() => folder;

  /// Flushes every open file.
  void flush() {
    for (final file in regionCache.values) {
      file.flush();
    }
    for (final file in storageCache.values) {
      file.flush();
    }
  }

  /// Closes every open file.
  void close() {
    for (final file in storageCache.values) {
      file.close();
    }
    for (final file in regionCache.values) {
      file.close();
    }
    storageCache.clear();
    regionCache.clear();
  }

  /// Prunes empty files from the caches.
  void pruneCache() {
    for (final entry in storageCache.entries.toList()) {
      if (!entry.value.isEmptyFile) continue;
      if (pruneEmptyFiles) {
        entry.value.delete();
      } else {
        entry.value.close();
      }
      storageCache.remove(entry.key);
    }
    for (final entry in regionCache.entries.toList()) {
      if (!entry.value.isEmptyFile) continue;
      if (pruneEmptyFiles) {
        entry.value.delete();
      } else {
        entry.value.close();
      }
      regionCache.remove(entry.key);
    }
  }

  /// The chunk bounds of a sub-level's world bounds, for the ready check.
  static BoundingBox3i chunkBoundsOf(SubLevelData data) => BoundingBox3i.values(
    (data.bounds.minX - 1.0).floor() >> 4,
    (data.bounds.minY - 1.0).floor() >> 4,
    (data.bounds.minZ - 1.0).floor() >> 4,
    (data.bounds.maxX + 1.0).floor() >> 4,
    (data.bounds.maxY + 1.0).floor() >> 4,
    (data.bounds.maxZ + 1.0).floor() >> 4,
  );

  /// The vector of a saved position, for logging.
  static Vector3d positionOf(SubLevelData data) => Vector3d.copy(data.pose.position());
}
