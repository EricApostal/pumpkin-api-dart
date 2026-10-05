// The two kinds of mounts: a writable one over a [FileStore] (a computer's
// disk, with a quota) and a read-only one over an archive (the ROM).
import 'dart:typed_data';

import 'filesystem.dart';
import 'zip.dart';

/// What an entry of a [FileStore] is.
enum StoredKind { file, directory }

/// The storage behind a [StoreMount]: a tree of files addressed by relative
/// `/` separated paths. The plugin implements it with its data folder.
abstract interface class FileStore {
  /// What [path] is, or null if it does not exist. The empty path is the root
  /// directory.
  StoredKind? kind(String path);

  List<String> list(String path);

  int size(String path);

  Uint8List read(String path);

  /// Writes the file, replacing its content. The parent exists.
  void write(String path, Uint8List data);

  /// Creates the directory. The parent exists.
  void makeDirectory(String path);

  /// Deletes a file, or a directory with everything in it.
  void delete(String path);

  DateTime? modified(String path);
}

final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// A writable mount over a [FileStore] with a space quota, counted like CC:
/// every file and directory costs at least [minimumFileSize] bytes.
final class StoreMount implements WritableMount {
  final FileStore _store;
  final int _limit;
  int _used = 0;

  StoreMount(this._store, this._limit) {
    _used = _measure('');
  }

  int _measure(String path) {
    final kind = _store.kind(path);
    if (kind == null) return 0;
    if (kind == StoredKind.file) {
      final size = _store.size(path);
      return size < minimumFileSize ? minimumFileSize : size;
    }
    var total = minimumFileSize;
    for (final name in _store.list(path)) {
      total += _measure(path.isEmpty ? name : '$path/$name');
    }
    return total;
  }

  @override
  int get capacity => _limit;

  @override
  int get remainingSpace {
    final left = _limit + minimumFileSize - _used;
    return left < 0 ? 0 : left;
  }

  @override
  bool exists(String path) => path.isEmpty || _store.kind(path) != null;

  @override
  bool isDirectory(String path) => path.isEmpty || _store.kind(path) == StoredKind.directory;

  @override
  List<String> list(String path) {
    if (!exists(path)) throw FileSystemException.of(path, noSuchFile);
    if (!isDirectory(path)) throw FileSystemException.of(path, notADirectory);
    return _store.list(path);
  }

  @override
  int size(String path) {
    if (!exists(path)) throw FileSystemException.of(path, noSuchFile);
    return isDirectory(path) ? 0 : _store.size(path);
  }

  @override
  Uint8List read(String path) {
    if (_store.kind(path) != StoredKind.file) {
      throw FileSystemException.of(path, noSuchFile);
    }
    return _store.read(path);
  }

  @override
  FileAttributes attributes(String path) {
    if (!exists(path)) throw FileSystemException.of(path, noSuchFile);
    final modified = _store.modified(path) ?? _epoch;
    return FileAttributes(
      isDirectory: isDirectory(path),
      size: size(path),
      modified: modified,
      created: modified,
    );
  }

  @override
  void makeDirectory(String path) {
    if (path.isEmpty) return;
    final parts = path.split('/');
    var prefix = '';
    for (final part in parts) {
      prefix = prefix.isEmpty ? part : '$prefix/$part';
      final kind = _store.kind(prefix);
      if (kind == StoredKind.file) throw FileSystemException.of(prefix, fileExists);
      if (kind == null) {
        if (remainingSpace < minimumFileSize) {
          throw FileSystemException.of(prefix, outOfSpace);
        }
        _store.makeDirectory(prefix);
        _used += minimumFileSize;
      }
    }
  }

  @override
  void delete(String path) {
    if (path.isEmpty) throw FileSystemException.of(path, accessDenied);
    if (_store.kind(path) == null) return;
    _used -= _measure(path);
    _store.delete(path);
  }

  @override
  void rename(String source, String destination) {
    if (!exists(source)) throw FileSystemException.of(source, noSuchFile);
    if (exists(destination)) throw FileSystemException.of(destination, fileExists);
    _copy(source, destination);
    _store.delete(source);
    _used = _measure('');
  }

  void _copy(String source, String destination) {
    if (_store.kind(source) == StoredKind.directory) {
      _store.makeDirectory(destination);
      for (final name in _store.list(source)) {
        _copy('$source/$name', '$destination/$name');
      }
    } else {
      _store.write(destination, _store.read(source));
    }
  }

  @override
  void checkSpace(String path, int newSize) {
    final kind = _store.kind(path);
    final old = kind == StoredKind.file ? _chargeFor(_store.size(path)) : 0;
    if (_chargeFor(newSize) - old > remainingSpace) {
      throw FileSystemException.of(path, outOfSpace);
    }
  }

  static int _chargeFor(int size) => size < minimumFileSize ? minimumFileSize : size;

  @override
  void write(String path, Uint8List data) {
    final kind = _store.kind(path);
    if (kind == StoredKind.directory) {
      throw FileSystemException.of(path, cannotWriteToDirectory);
    }
    final old = kind == StoredKind.file ? _chargeFor(_store.size(path)) : 0;
    final charge = _chargeFor(data.length);
    if (charge - old > remainingSpace) {
      throw FileSystemException.of(path, outOfSpace);
    }
    _store.write(path, data);
    _used += charge - old;
  }
}

/// A read-only mount over the entries of a zip archive below a prefix, such as
/// the `rom` directory of the CC: Tweaked jar. Files are decompressed on first
/// use and kept, so all computers share one copy.
final class ArchiveMount implements Mount {
  final Map<String, ZipEntry> _files = {};
  final Set<String> _directories = {''};
  final Map<String, Uint8List> _cache = {};

  /// Mounts the files of [archive] under [prefix] (for example
  /// `data/computercraft/lua/rom/`) at the mount's root.
  ArchiveMount(ZipArchive archive, String prefix) {
    for (final entry in archive.entries) {
      if (!entry.name.startsWith(prefix) || entry.isDirectory) continue;
      final relative = entry.name.substring(prefix.length);
      if (relative.isEmpty) continue;
      _files[relative] = entry;
      var slash = relative.indexOf('/');
      while (slash >= 0) {
        _directories.add(relative.substring(0, slash));
        slash = relative.indexOf('/', slash + 1);
      }
    }
  }

  /// The number of files.
  int get fileCount => _files.length;

  @override
  bool exists(String path) => _files.containsKey(path) || _directories.contains(path);

  @override
  bool isDirectory(String path) => _directories.contains(path);

  @override
  List<String> list(String path) {
    if (!isDirectory(path)) throw FileSystemException.of(path, notADirectory);
    final prefix = path.isEmpty ? '' : '$path/';
    final names = <String>{};
    for (final name in _files.keys) {
      if (!name.startsWith(prefix)) continue;
      final rest = name.substring(prefix.length);
      final slash = rest.indexOf('/');
      names.add(slash < 0 ? rest : rest.substring(0, slash));
    }
    return names.toList();
  }

  @override
  int size(String path) => _files[path]?.size ?? 0;

  @override
  Uint8List read(String path) {
    final entry = _files[path];
    if (entry == null) throw FileSystemException.of(path, noSuchFile);
    return _cache.putIfAbsent(path, entry.read);
  }

  @override
  FileAttributes attributes(String path) {
    if (!exists(path)) throw FileSystemException.of(path, noSuchFile);
    return FileAttributes(
      isDirectory: isDirectory(path),
      size: size(path),
      modified: _epoch,
      created: _epoch,
    );
  }
}
