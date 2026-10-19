// `ServerSchematicLoader` (pure): the chunked schematic upload (`create:upload_schematic` with
// BEGIN, WRITE, FINISH), the per-player quota and the instant schematic. File access and the
// schematic table are behind interfaces so the logic runs on the Dart VM.
import 'dart:typed_data';

/// A file in the schematic store.
final class StoredSchematic {
  final String name;
  final bool isDirectory;

  /// Last modification in milliseconds since the epoch (0 when unknown).
  final int modified;

  const StoredSchematic(this.name, this.isDirectory, this.modified);
}

/// The files under `schematics/uploaded/` (the plugin data folder on the host).
abstract interface class SchematicFileStore {
  bool exists(String path);

  /// Writes [bytes] to [path]; with [append] to the end of an existing file.
  void write(String path, List<int> bytes, {bool append = false});

  /// Deletes the file; no error if it does not exist.
  void delete(String path);

  void createDirectory(String path);

  /// Files and directories directly inside [dir].
  List<StoredSchematic> list(String dir);

  Uint8List read(String path);
}

/// An in-memory [SchematicFileStore], for tests.
final class MemorySchematicStore implements SchematicFileStore {
  final Map<String, Uint8List> files = {};
  final Map<String, int> times = {};
  final Set<String> dirs = {''};
  int clock = 0;

  @override
  bool exists(String path) => files.containsKey(path);

  @override
  void write(String path, List<int> bytes, {bool append = false}) {
    final old = append ? files[path] : null;
    files[path] = Uint8List.fromList([...?old, ...bytes]);
    times[path] = ++clock;
  }

  @override
  void delete(String path) {
    files.remove(path);
    times.remove(path);
  }

  @override
  void createDirectory(String path) => dirs.add(path);

  @override
  List<StoredSchematic> list(String dir) {
    final prefix = dir.isEmpty ? '' : '$dir/';
    return [
      for (final e in files.keys)
        if (e.startsWith(prefix) && !e.substring(prefix.length).contains('/'))
          StoredSchematic(e.substring(prefix.length), false, times[e] ?? 0),
    ];
  }

  @override
  Uint8List read(String path) =>
      files[path] ?? (throw StateError('no file $path'));
}

/// The schematic table as the receiver sees it.
abstract interface class UploadTarget {
  /// `table.startUpload(schematic)`.
  void startUpload(String schematic);

  /// `uploadingProgress` and `sendUpdate`.
  void progress(double fraction);

  /// `table.finishUpload()`.
  void finishUpload();

  /// After a successful upload: `inventory.setStackInSlot(1, SchematicItem.create(...))`.
  void deliver(String schematic, String owner);

  /// Whether the target still is a schematic table (`AllBlocks.SCHEMATIC_TABLE == block`).
  bool get isValid;
}

/// The limits of `CSchematics`.
final class SchematicLimits {
  final int maxSchematics;

  /// KB.
  final int maxTotalSchematicSize;
  final int maxSchematicPacketSize;
  final int schematicIdleTimeout;

  const SchematicLimits({
    this.maxSchematics = 10,
    this.maxTotalSchematicSize = 256,
    this.maxSchematicPacketSize = 1024,
    this.schematicIdleTimeout = 600,
  });
}

/// `ServerSchematicLoader.SchematicUploadEntry`: one active upload of a player.
class SchematicUploadEntry {
  /// The table that receives the progress, or null when it was not available.
  final UploadTarget? target;
  final int totalBytes;
  int bytesUploaded = 0;
  int idleTime = 0;

  SchematicUploadEntry(this.target, this.totalBytes);
}

/// Why an upload was refused.
enum UploadResult {
  started,
  pathTraversal,
  wrongFormat,
  tooLarge,
  alreadyActive,
  noTable,
  ioError,
}

/// `ServerSchematicLoader`.
final class SchematicUploadReceiver {
  static const String root = 'schematics/uploaded';

  final SchematicFileStore store;
  SchematicLimits limits;
  void Function(String message)? warn;
  void Function(String message)? info;

  final Map<String, SchematicUploadEntry> _active = {};

  SchematicUploadReceiver(
    this.store, {
    this.limits = const SchematicLimits(),
    this.warn,
    this.info,
  });

  /// `player/name.nbt` as used for the keys and the paths below [root].
  static String schematicId(String player, String schematic) =>
      '$player/$schematic';

  /// The relative path of the file in the store.
  static String pathOf(String player, String schematic) =>
      '$root/$player/$schematic';

  /// Whether [name] is a plain file name (no separators, no `..`).
  static bool isSafeName(String name) =>
      name.isNotEmpty &&
      !name.contains('/') &&
      !name.contains('\\') &&
      !name.contains('\u0000') &&
      name != '.' &&
      name != '..' &&
      !name.contains('..');

  bool isUploading(String player, String schematic) =>
      _active.containsKey(schematicId(player, schematic));

  int get activeCount => _active.length;

  /// `tick`: idle uploads time out.
  void tick() {
    final timeout = limits.schematicIdleTimeout;
    final dead = <String>[];
    for (final e in _active.entries) {
      if (e.value.idleTime++ > timeout) {
        warn?.call('Schematic Upload timed out: ${e.key}');
        dead.add(e.key);
      }
    }
    for (final id in dead) {
      cancel(id);
    }
  }

  /// `shutdown`.
  void shutdown() {
    for (final id in _active.keys.toList()) {
      cancel(id);
    }
  }

  /// `handleNewUpload`. [onTooLarge] receives the two chat lines the player gets.
  UploadResult handleNewUpload(
    String player,
    String schematic,
    int size,
    UploadTarget? target, {
    void Function(String line1, String line2)? onTooLarge,
  }) {
    final id = schematicId(player, schematic);
    if (!isSafeName(player) || !isSafeName(schematic)) {
      warn?.call('Attempted Schematic Upload with path traversal: $id');
      return UploadResult.pathTraversal;
    }
    if (!schematic.endsWith('.nbt')) {
      warn?.call('Attempted Schematic Upload with non-supported Format: $id');
      return UploadResult.wrongFormat;
    }
    final maxFileSize = limits.maxTotalSchematicSize;
    if (size > maxFileSize * 1000) {
      onTooLarge?.call(
        'Your schematic exceeds limitations specified by the server. (${size ~/ 1000} KB).',
        'The maximum allowed schematic file size is: $maxFileSize KB',
      );
      return UploadResult.tooLarge;
    }
    if (_active.containsKey(id)) return UploadResult.alreadyActive;
    if (target == null) return UploadResult.noTable;
    try {
      store.createDirectory('$root/$player');
      final path = pathOf(player, schematic);
      store.delete(path); // delete schematic with same name
      // Too many schematics: delete the oldest file.
      final files = store.list('$root/$player');
      if (files.length >= limits.maxSchematics) {
        final candidates = files.where((f) => !f.isDirectory).toList()
          ..sort((a, b) => a.modified.compareTo(b.modified));
        if (candidates.isNotEmpty)
          store.delete('$root/$player/${candidates.first.name}');
      }
      store.write(path, const []); // open the stream
      _active[id] = SchematicUploadEntry(target, size);
      target.startUpload(schematic);
      return UploadResult.started;
    } on Object catch (e) {
      warn?.call('Exception thrown when starting upload $id: $e');
      return UploadResult.ioError;
    }
  }

  /// `handleWriteRequest`.
  void handleWriteRequest(String player, String schematic, List<int> data) {
    final id = schematicId(player, schematic);
    final entry = _active[id];
    if (entry == null) return;
    entry.bytesUploaded += data.length;
    if (data.length > limits.maxSchematicPacketSize) {
      warn?.call('Oversized Upload Packet received: $id');
      cancel(id);
      return;
    }
    if (entry.bytesUploaded > entry.totalBytes) {
      warn?.call('Received more data than Expected: $id');
      cancel(id);
      return;
    }
    try {
      store.write(pathOf(player, schematic), data, append: true);
      entry.idleTime = 0;
      final target = entry.target;
      // `getTable` returns null once the table block is gone.
      if (target != null && target.isValid) {
        target.progress(entry.bytesUploaded / entry.totalBytes);
      }
    } on Object catch (e) {
      warn?.call('Exception thrown when uploading schematic $id: $e');
      cancel(id);
    }
  }

  /// `cancelUpload`: deletes the partial file and tells the table.
  void cancel(String id) {
    final entry = _active.remove(id);
    if (entry == null) return;
    try {
      store.delete('$root/$id');
      warn?.call('Cancelled Schematic Upload: $id');
    } on Object catch (e) {
      warn?.call('Exception thrown when cancelling upload $id: $e');
    }
    entry.target?.finishUpload();
  }

  /// `handleFinishedUpload`.
  void handleFinishedUpload(String player, String schematic) {
    final id = schematicId(player, schematic);
    final entry = _active.remove(id);
    if (entry == null) return;
    info?.call('New Schematic Uploaded: $id');
    final target = entry.target;
    if (target == null || !target.isValid) return;
    target.finishUpload();
    target.deliver(schematic, player);
  }

  /// `tryDeleteOldestSchematic` for the instant schematic: makes room under the quota. Returns
  /// false if that failed.
  bool makeRoom(String player) {
    try {
      final dir = '$root/$player';
      store.createDirectory(dir);
      final files = store.list(dir);
      if (files.length < limits.maxSchematics) return true;
      final oldest =
          (files.toList()..sort((a, b) => a.modified.compareTo(b.modified)))
              .first;
      store.delete('$dir/${oldest.name}');
      return true;
    } on Object catch (e) {
      warn?.call('Error deleting oldest schematic: $e');
      return false;
    }
  }

  /// `FilesHelper.slug`: lower case with runs of non-word characters replaced by `_`.
  static String slug(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');

  /// The file name for a saved schematic (`SchematicExport.saveSchematic`): the name as given with
  /// `.nbt` when [overwrite]; otherwise the first free slug (`my_schematic.nbt`,
  /// `my_schematic_1.nbt`, ...). An empty name becomes `My Schematic`.
  String exportName(String player, String fileName, {required bool overwrite}) {
    var name = fileName.isEmpty ? 'My Schematic' : fileName;
    if (!overwrite) {
      var index = 0;
      String candidate;
      do {
        candidate = '${slug(name)}${index == 0 ? '' : '_$index'}.nbt';
        index++;
      } while (store.exists(pathOf(player, candidate)));
      name = candidate;
    }
    if (!name.endsWith('.nbt')) name += '.nbt';
    return name;
  }
}
