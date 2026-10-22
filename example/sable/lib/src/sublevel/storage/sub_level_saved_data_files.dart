// The files behind the level's deferred data (`SavedDataStorage.computeIfAbsent`).
//
// Java keeps three of these per level, all gzip NBT under the level's `data`
// folder: `sable_sub_level_occupancy` (the plot grid's `long[]` bitmap),
// `sable_sub_level_force_load_tickets` (the tickets and the pointers of the
// sub-levels they keep loaded) and `sable_tracking_points`.
//
// The payload bytes are the Java ones (`NbtIo.writeCompressed(readCompressed)`,
// which is what `SavedDataStorage` uses), so the files are readable in both
// directions; the *folder* differs, because the plugin API only mounts the
// plugin's own data folder (`host_gap`: there is no `getWorldPath(ROOT)`), so
// they live next to the level's storage files instead of in the world's `data`
// directory.
//
// Pure: no host imports (the file store is an interface).
import 'dart:typed_data';

import '../host/sub_level_host.dart';
import 'region/sub_level_storage_file.dart';

/// Reads and writes the saved-data files of one level.
final class SavedDataFiles {
  SavedDataFiles({required this.store, required this.folder, required this.codec});

  final SableFileStore store;

  /// The folder holding the `.dat` files (relative to the file store root).
  final String folder;

  /// The payload codec: the gzip NBT codec, matching `SavedDataStorage`.
  final SubLevelCodec codec;

  /// The path of the file of [name].
  String pathOf(String name) => '$folder/$name.dat';

  /// Whether [name] has been written.
  bool exists(String name) => store.exists(pathOf(name));

  /// The tag of [name], or `null` when it has never been written.
  ///
  /// Throws [SubLevelPayloadException] when the file exists but does not
  /// decode: a broken occupancy bitmap must not read as "no plots are occupied".
  Map<String, Object?>? read(String name) {
    final path = pathOf(name);
    if (!store.exists(path)) return null;
    final bytes = store.readBytes(path);
    try {
      return codec.decode(Uint8List.fromList(bytes));
    } on Object catch (error) {
      throw SubLevelPayloadException(path, 0, error);
    }
  }

  /// Writes [tag] as the content of [name], replacing it.
  void write(String name, Map<String, Object?> tag) {
    final path = pathOf(name);
    store.createDirectory(folder);
    store.writeBytes(path, codec.encode(tag));
  }

  /// Deletes the file of [name], if it exists.
  void delete(String name) {
    final path = pathOf(name);
    if (store.exists(path)) store.delete(path);
  }
}