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

/// A failure the storage layer reports through [SubLevelStorage.onError].
///
/// With a sink installed it is only reported (Java logs and continues); without
/// one it is thrown, so a caller that never installed a sink cannot lose a
/// sub-level without noticing.
final class SubLevelStorageFailure implements Exception {
  SubLevelStorageFailure(this.message, this.cause);

  /// What the Java mod logs, e.g. `Failed to load sub-level for (0, 0)`.
  final String message;

  /// What actually went wrong (a [SubLevelPayloadException] for a codec
  /// failure).
  final Object cause;

  @override
  String toString() => '$message: $cause';
}

/// Manages the sub-level holding chunks and regions for a level.
final class SubLevelStorage {
  /// The maximum number of cached region/storage files.
  static int maxCacheSize = 128;

  /// The extension of the region files.
  static const String regionExtension = '.slvlr';

  /// Where failures go.
  ///
  /// Every read/save of the Java class logs and continues; the port has no
  /// logger of its own, so a host that wants the Java behaviour installs one
  /// here (the plugin wires this to the plugin logger). While it is null a
  /// failure **throws** instead of being swallowed: an undecodable payload must
  /// never look like an absent one — that is exactly how a whole world's
  /// sub-levels disappeared silently.
  void Function(String message, Object error, StackTrace stack)? onError;

  final SableFileStore store;
  final String folder;
  final SubLevelCodec codec;

  /// The open region files by packed region position.
  final Map<int, SubLevelRegionFile> regionCache = {};

  /// The open storage files by packed (region, index).
  final Map<int, SubLevelStorageFile> storageCache = {};

  SubLevelStorage(this.store, this.folder, this.codec);

  /// Reports [error] and returns true when a sink is installed; throws it
  /// otherwise, so nothing is lost silently.
  void _report(String message, Object error, StackTrace stack) {
    final sink = onError;
    if (sink == null) {
      Error.throwWithStackTrace(SubLevelStorageFailure(message, error), stack);
    }
    sink(message, error, stack);
  }

  /// Reports a condition Java logs at error level but does not treat as a
  /// failure (a dangling pointer, a recovery). Nothing is thrown: the callers
  /// recover, and the sink is what makes it visible.
  void _warn(String message, Object error) => onError?.call(message, error, StackTrace.current);

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
  ///
  /// `null` means "this chunk has no holding chunk". A payload that exists but
  /// does not decode is reported through [onError] (Java logs at error level),
  /// or thrown when no sink is installed.
  SubLevelHoldingChunk? attemptLoadHoldingChunk(int chunkX, int chunkZ) {
    try {
      final tag = getRegionFile(chunkX, chunkZ).read(chunkX, chunkZ);
      if (tag == null) return null;
      return SubLevelHoldingChunk.from((chunkX, chunkZ), tag);
    } on Object catch (error, stack) {
      _report('Failed to load holding chunk for ($chunkX, $chunkZ)', error, stack);
      return null;
    }
  }

  /// Saves the holding chunk at [chunkX], [chunkZ].
  void attemptSaveHoldingChunk(int chunkX, int chunkZ, SubLevelHoldingChunk holdingChunk) {
    try {
      final tag = <String, Object?>{};
      holdingChunk.writeTo(tag);
      getRegionFile(chunkX, chunkZ).trySave(chunkX & 31, chunkZ & 31, tag);
    } on Object catch (error, stack) {
      _report('Failed to save holding chunk for ($chunkX, $chunkZ)', error, stack);
    }
  }

  /// Removes the holding chunk at [chunkX], [chunkZ].
  void attemptRemoveHoldingChunk(int chunkX, int chunkZ) {
    try {
      getRegionFile(chunkX, chunkZ).tryRemove(chunkX & 31, chunkZ & 31);
    } on Object catch (error, stack) {
      _report('Failed to remove holding chunk for ($chunkX, $chunkZ)', error, stack);
    }
  }

  /// Loads a [SubLevelData] from a chunk position and pointer.
  SubLevelData? attemptLoadSubLevel(int chunkX, int chunkZ, SavedSubLevelPointer pointer) {
    try {
      final storageFile = getStorageFile(chunkX, chunkZ, pointer.storageIndex);
      final tag = storageFile.read(pointer.subLevelIndex);
      if (tag == null) {
        _warn(
          'Couldn\'t find sub-level at index ${pointer.subLevelIndex} in storage file for '
          'chunk ($chunkX, $chunkZ)',
          StateError('the holding chunk points at an empty storage slot'),
        );
        return null;
      }

      final data = SubLevelSerializer.fromData(tag);
      if (data == null) {
        _warn(
          'Failed to load sub-level at index ${pointer.subLevelIndex} in storage file for '
          'chunk ($chunkX, $chunkZ): the payload has no usable uuid/pose',
          FormatException('undecodable sub-level payload', tag),
        );
        return null;
      }

      // Recover zeroed-out bounds (a known corruption in the Java mod).
      final bounds = data.bounds;
      if (bounds.minX == 0.0 &&
          bounds.minY == 0.0 &&
          bounds.minZ == 0.0 &&
          bounds.maxX == 0.0 &&
          bounds.maxY == 0.0 &&
          bounds.maxZ == 0.0) {
        _warn(
          'Recovering zeroed out bounds for sub-level ${data.uuid} loaded at $pointer in chunk '
          '($chunkX, $chunkZ)',
          StateError('the saved bounds were zeroed out'),
        );
        final position = data.pose.position();
        bounds
            .setValues(position.x, position.y, position.z, position.x, position.y, position.z)
            .expand(1.0);
      }

      data.setOriginLoadedChunk((chunkX, chunkZ));
      return data;
    } on Object catch (error, stack) {
      _report('Failed to load sub-level for ($chunkX, $chunkZ)', error, stack);
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
    } on Object catch (error, stack) {
      _report('Failed to save sub-level for ($chunkX, $chunkZ)', error, stack);
      return null;
    }
  }

  /// Saves [subLevel] at an existing pointer (`null` clears it).
  void attemptSaveSubLevelAt(GlobalSavedSubLevelPointer pointer, SubLevelData? subLevel) {
    try {
      final storageFile = getStorageFile(pointer.chunkX, pointer.chunkZ, pointer.storageIndex);
      storageFile.write(pointer.subLevelIndex, subLevel?.fullTag);
    } on Object catch (error, stack) {
      _report('Failed to save sub-level for ${pointer.chunkX}, ${pointer.chunkZ}', error, stack);
    }
  }

  /// The folder of the storage files.
  String getFolder() => folder;

  /// Flushes every open file.
  ///
  /// One file that cannot be written does not stop the others: every failure is
  /// reported, so a save never looks complete when part of it is missing.
  void flush() {
    for (final file in regionCache.values) {
      _attempt('Failed to flush ${file.filePath}', file.flush);
    }
    for (final file in storageCache.values) {
      _attempt('Failed to flush ${file.filePath}', file.flush);
    }
  }

  /// Closes every open file, flushing each.
  void close() {
    for (final file in storageCache.values) {
      _attempt('Failed to close ${file.filePath}', file.close);
    }
    for (final file in regionCache.values) {
      _attempt('Failed to close ${file.filePath}', file.close);
    }
    storageCache.clear();
    regionCache.clear();
  }

  void _attempt(String message, void Function() operation) {
    try {
      operation();
    } on Object catch (error, stack) {
      _report(message, error, stack);
    }
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
