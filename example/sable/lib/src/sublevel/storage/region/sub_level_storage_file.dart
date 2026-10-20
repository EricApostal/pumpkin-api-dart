// `dev.ryanhcode.sable.sublevel.storage.region.SubLevelStorageFile` and
// `SubLevelRegionFile`: the files that hold sub-level tags and holding chunks.
//
// A storage file (`.slvls`) holds up to 1024 sub-level tags; a region file
// (`.slvlr`, 32x32 chunks) maps a chunk to its holding-chunk tag. Both use the
// same sector format (`StorageFileImage`), only the sector size differs
// (4096 vs 128 bytes).
//
// The payload codec is injected: the Java mod writes gzip-compressed NBT, and
// the port must use an NBT codec to read existing worlds. `JsonSubLevelCodec`
// exists for tests and for a fresh world; it is deliberately not the default,
// so a wrong codec can never silently produce unreadable saves.
//
// Pure: no host imports (the file store is an interface).
import 'dart:convert';
import 'dart:typed_data';

import '../../host/sub_level_host.dart';
import 'storage_file_image.dart';

/// Encodes and decodes the payload of one sub-level or holding chunk.
abstract interface class SubLevelCodec {
  Uint8List encode(Map<String, Object?> tag);

  Map<String, Object?> decode(Uint8List bytes);
}

/// A UTF-8 JSON codec (fresh worlds and tests only; **not** Sable's NBT).
final class JsonSubLevelCodec implements SubLevelCodec {
  const JsonSubLevelCodec();

  @override
  Uint8List encode(Map<String, Object?> tag) => utf8.encode(jsonEncode(tag));

  @override
  Map<String, Object?> decode(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('Sub-level payload is not a JSON object');
    return Map<String, Object?>.from(decoded);
  }
}

/// A storage file for sub-levels: one file can store 1024 tags.
final class SubLevelStorageFile {
  /// The extension of a multi-index storage file.
  static const String fileExtension = '.slvls';

  /// The extension of an external (single-index) storage file.
  static const String singleFileExtension = '.slvl';

  /// Whether payloads are compressed (`COMPRESS_DATA`). The codec decides how.
  static bool compressData = true;

  /// The external payload flag (`EXTERNAL_MASK`).
  static int externalMask = StorageFileImage.externalMask;

  final SableFileStore store;
  final String path;
  final String externalDirectory;
  final SubLevelCodec codec;
  final StorageFileImage _image;
  bool _closed = false;

  SubLevelStorageFile._(this.store, this.path, this.externalDirectory, this.codec, this._image);

  /// Opens (or creates) the storage file at [path]. [externalDirectory] receives
  /// the oversized payloads.
  factory SubLevelStorageFile.open(
    SableFileStore store,
    String path,
    String externalDirectory,
    SubLevelCodec codec, {
    int sectorSize = StorageFileImage.headerSize,
  }) {
    Uint8List? existing;
    if (store.exists(path)) {
      existing = Uint8List.fromList(store.readBytes(path));
    }
    final image = StorageFileImage(sectorSize, existing: existing);
    final file = SubLevelStorageFile._(store, path, externalDirectory, codec, image);
    file._loadExternalPayloads();
    return file;
  }

  void _loadExternalPayloads() {
    if (!store.exists(externalDirectory)) return;
    for (final name in store.list(externalDirectory)) {
      if (!name.endsWith(singleFileExtension)) continue;
      final index = int.tryParse(name.substring(0, name.length - singleFileExtension.length));
      if (index == null) continue;
      _image.externalPayloads[index] = Uint8List.fromList(
        store.readBytes('$externalDirectory/$name'),
      );
    }
  }

  /// The first free index.
  int findFreeIndex() => _image.findFreeIndex();

  /// The total number of indices.
  int get totalIndexCapacity => _image.totalIndexCapacity;

  /// Whether the file holds nothing.
  bool isEmpty() => _image.isEmpty;

  /// Writes [tag] at [index]; `null` clears the index.
  void write(int index, Map<String, Object?>? tag) {
    if (tag == null) {
      clear(index);
      return;
    }
    _image.write(index, codec.encode(tag));
    _persistExternal(index);
  }

  /// Reads the tag at [index], or `null` when empty.
  Map<String, Object?>? read(int index) {
    final bytes = _image.read(index);
    return bytes == null ? null : codec.decode(bytes);
  }

  /// Clears the tag at [index].
  void clear(int index) {
    _image.clear(index);
    final externalPath = '$externalDirectory/$index$singleFileExtension';
    if (store.exists(externalPath)) store.delete(externalPath);
  }

  /// The path of the file.
  String get filePath => path;

  void _persistExternal(int index) {
    final payload = _image.externalPayloads[index];
    if (payload == null) return;
    store.createDirectory(externalDirectory);
    store.writeBytes('$externalDirectory/$index$singleFileExtension', payload);
  }

  /// Writes the file to the store.
  void flush() {
    store.createDirectory(_directoryOf(path));
    store.writeBytes(path, _image.flushBytes());
  }

  /// Deletes the file and its external payloads.
  void delete() {
    for (final index in _image.externalPayloads.keys.toList()) {
      final externalPath = '$externalDirectory/$index$singleFileExtension';
      if (store.exists(externalPath)) store.delete(externalPath);
    }
    _image.externalPayloads.clear();
    if (store.exists(path)) store.delete(path);
    _closed = true;
  }

  /// Closes the file, flushing it.
  void close() {
    if (_closed) return;
    flush();
    _closed = true;
  }

  static String _directoryOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }
}

/// A region file: a 32x32 chunk table of holding chunks.
final class SubLevelRegionFile {
  /// The extension of a region file.
  static const String fileExtension = '.slvlr';

  /// The sector size of a region file (`SECTOR_SIZE`).
  static const int sectorSize = 128;

  /// The side length of a region, in chunks.
  static const int sideLength = 32;

  /// log2(32).
  static const int logSideLength = 5;

  final SubLevelStorageFile file;

  SubLevelRegionFile._(this.file);

  /// Opens the region file at [path].
  factory SubLevelRegionFile.open(
    SableFileStore store,
    String path,
    String externalDirectory,
    SubLevelCodec codec,
  ) => SubLevelRegionFile._(
    SubLevelStorageFile.open(store, path, externalDirectory, codec, sectorSize: sectorSize),
  );

  /// `getIndex(localX, localZ)`.
  int getIndex(int localX, int localZ) => localX | (localZ << logSideLength);

  /// Writes a holding chunk at the local chunk position.
  void trySave(int localX, int localZ, Map<String, Object?> tag) =>
      file.write(getIndex(localX, localZ), tag);

  /// Removes the holding chunk at the local chunk position.
  void tryRemove(int localX, int localZ) => file.clear(getIndex(localX, localZ));

  /// Reads the holding chunk at the global chunk position, or `null`.
  Map<String, Object?>? read(int chunkX, int chunkZ) =>
      file.read(getIndex(chunkX & 31, chunkZ & 31));

  /// Writes the file.
  void flush() => file.flush();

  /// Closes the file.
  void close() => file.close();

  /// Whether the region has no entries.
  bool isEmpty() => file.isEmpty;

  /// Deletes the file.
  void delete() => file.delete();
}
