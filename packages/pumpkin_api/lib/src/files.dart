import 'dart:convert';

import 'package:wasm_components/wasm_components.dart' show ErrorResult, OkResult, Result;

import 'bindings.g.dart' as wasi;
import 'bindings.g.dart' show Context;

/// Why a file operation failed. See [FileException.isNotFound] and friends for
/// the common cases.
final class FileException implements Exception {
  /// The WASI error code, as a readable name like `noEntry` or `access`.
  final String code;

  /// What was being done, like `read`.
  final String operation;

  /// The path the operation was applied to, relative to the folder.
  final String path;

  FileException._(this.code, this.operation, this.path);

  /// The file or directory doesn't exist.
  bool get isNotFound => code == 'noEntry';

  /// The file or directory already exists.
  bool get alreadyExists => code == 'exist';

  /// Access was denied, usually because the plugin lacks the `fs.write.data`
  /// permission.
  bool get isAccessDenied => code == 'access' || code == 'readOnly';

  @override
  String toString() => "FileException: could not $operation '$path': $code";
}

/// What a file or directory is.
enum FileKind { file, directory, other }

/// Information about a file or directory.
final class FileInfo {
  final FileKind kind;

  /// The size in bytes (meaningful for files).
  final int size;

  /// When the content was last modified, if the file system tracks it.
  final DateTime? modified;

  FileInfo._(this.kind, this.size, this.modified);

  bool get isDirectory => kind == FileKind.directory;
  bool get isFile => kind == FileKind.file;
}

/// An entry of [DataFolder.list].
final class DirectoryEntry {
  final String name;
  final FileKind kind;

  DirectoryEntry._(this.name, this.kind);

  bool get isDirectory => kind == FileKind.directory;

  @override
  String toString() => isDirectory ? '$name/' : name;
}

/// The plugin's own folder for files that survive restarts, available as
/// `context.files`.
///
/// Paths are relative to the folder and use `/`, subdirectories are created
/// with [createDirectory]. The server only mounts the folder if the plugin asks
/// for `Permissions.fsReadData` (reading) and `Permissions.fsWriteData`
/// (writing, which includes reading) in its [PluginInfo].
///
/// Operations are synchronous: the server tick waits for the disk.
///
/// ```dart
/// final data = context.files;
/// data.writeJson('homes/steve.json', {'x': 10, 'y': 64, 'z': -3});
/// final home = data.readJson('homes/steve.json');
/// ```
final class DataFolder {
  final String _sandboxPath;

  DataFolder._(this._sandboxPath);

  /// Reads the whole file as UTF-8 text.
  String readAsString(String path) => utf8.decode(readAsBytes(path));

  /// Reads the whole file.
  List<int> readAsBytes(String path) {
    final relative = _normalize(path);
    return _withRoot((root) {
      final file = _open(root, relative, 'read', read: true);
      try {
        final bytes = <int>[];
        var offset = 0;
        while (true) {
          final (chunk, atEnd) = _check(
            file.read(length: _chunkSize, offset: offset),
            'read',
            relative,
          );
          bytes.addAll(chunk);
          offset += chunk.length;
          if (atEnd || chunk.isEmpty) return bytes;
        }
      } finally {
        file.dispose();
      }
    });
  }

  /// Reads the file as JSON.
  Object? readJson(String path) => jsonDecode(readAsString(path));

  /// Replaces the file's content with [contents] (UTF-8), creating it if
  /// needed. With [append], adds to the end instead.
  void writeAsString(String path, String contents, {bool append = false}) =>
      writeAsBytes(path, utf8.encode(contents), append: append);

  /// Replaces the file's content with [bytes], creating it if needed. With
  /// [append], adds to the end instead.
  void writeAsBytes(String path, List<int> bytes, {bool append = false}) {
    final relative = _normalize(path);
    _withRoot((root) {
      final file = _open(
        root,
        relative,
        'write',
        write: true,
        create: true,
        truncate: !append,
      );
      try {
        var offset = append
            ? _check(file.stat(), 'write', relative).size
            : 0;
        var index = 0;
        while (index < bytes.length) {
          final end = index + _chunkSize < bytes.length
              ? index + _chunkSize
              : bytes.length;
          final written = _check(
            file.write(buffer: bytes.sublist(index, end), offset: offset),
            'write',
            relative,
          );
          if (written == 0) break;
          index += written;
          offset += written;
        }
      } finally {
        file.dispose();
      }
    });
  }

  /// Writes [value] as JSON, replacing the file's content.
  void writeJson(String path, Object? value) =>
      writeAsString(path, jsonEncode(value));

  /// Whether a file or directory exists at [path].
  bool exists(String path) => stat(path) != null;

  /// Information about [path], or `null` if it doesn't exist.
  FileInfo? stat(String path) {
    final relative = _normalize(path);
    return _withRoot((root) {
      final result = root.statAt(
        pathFlags: _followLinks,
        path: relative,
      );
      if (result case ErrorResult(:final value) when value == wasi.ErrorCode.noEntry) {
        return null;
      }
      final info = _check(result, 'stat', relative);
      return FileInfo._(
        _kindOf(info.type),
        info.size,
        info.dataModificationTimestamp == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                info.dataModificationTimestamp!.seconds * 1000 +
                    info.dataModificationTimestamp!.nanoseconds ~/ 1000000,
                isUtc: true,
              ),
      );
    });
  }

  /// The entries of the directory [path] (the folder itself by default).
  List<DirectoryEntry> list([String path = '']) {
    final relative = _normalize(path);
    return _withRoot((root) {
      final directory = _open(root, relative, 'list', read: true, directory: true);
      try {
        final stream = _check(directory.readDirectory(), 'list', relative);
        try {
          final entries = <DirectoryEntry>[];
          while (true) {
            final entry = _check(stream.readDirectoryEntry(), 'list', relative);
            if (entry == null) return entries;
            entries.add(DirectoryEntry._(entry.name, _kindOf(entry.type)));
          }
        } finally {
          stream.dispose();
        }
      } finally {
        directory.dispose();
      }
    });
  }

  /// Creates the directory [path]. With [recursive] (the default), missing
  /// parents are created too and an existing directory is not an error.
  void createDirectory(String path, {bool recursive = true}) {
    final relative = _normalize(path);
    if (relative == '.') return;
    _withRoot((root) {
      if (!recursive) {
        _check(root.createDirectoryAt(path: relative), 'create directory', relative);
        return;
      }
      var current = '';
      for (final part in relative.split('/')) {
        current = current.isEmpty ? part : '$current/$part';
        final result = root.createDirectoryAt(path: current);
        if (result case ErrorResult(:final value) when value == wasi.ErrorCode.exist) {
          continue;
        }
        _check(result, 'create directory', current);
      }
    });
  }

  /// Deletes the file or empty directory at [path]. With [recursive], a
  /// directory is deleted with everything in it.
  void delete(String path, {bool recursive = false}) {
    final relative = _normalize(path);
    if (recursive && (stat(relative)?.isDirectory ?? false)) {
      for (final entry in list(relative)) {
        delete('$relative/${entry.name}', recursive: true);
      }
    }
    _withRoot((root) {
      final result = root.unlinkFileAt(path: relative);
      if (result case ErrorResult(:final value)
          when value == wasi.ErrorCode.isDirectory ||
              value == wasi.ErrorCode.notPermitted) {
        _check(root.removeDirectoryAt(path: relative), 'delete', relative);
        return;
      }
      _check(result, 'delete', relative);
    });
  }

  // -- Internals --------------------------------------------------------------

  static const _chunkSize = 64 * 1024;
  static final _followLinks = {wasi.PathFlagsFlag.symlinkFollow};

  /// Strips leading slashes and `.` segments, so `/a/./b` is `a/b`.
  static String _normalize(String path) {
    final parts = [
      for (final part in path.split('/'))
        if (part.isNotEmpty && part != '.') part,
    ];
    if (parts.contains('..')) {
      throw ArgumentError.value(path, 'path', 'Must not contain ..');
    }
    return parts.isEmpty ? '.' : parts.join('/');
  }

  /// Runs [body] with the descriptor of the data folder.
  R _withRoot<R>(R Function(wasi.Descriptor root) body) {
    final directories = wasi.preopens.getDirectories();
    if (directories.isEmpty) {
      throw StateError(
        'The data folder is not available: add Permissions.fsReadData and/or '
        'Permissions.fsWriteData to the plugin\'s permissions.',
      );
    }

    var chosen = directories.indexWhere((d) => d.$2 == _sandboxPath);
    if (chosen < 0) chosen = directories.indexWhere((d) => d.$2 == 'data');
    if (chosen < 0) chosen = 0;

    for (var i = 0; i < directories.length; i++) {
      if (i != chosen) directories[i].$1.dispose();
    }
    final root = directories[chosen].$1;
    try {
      return body(root);
    } finally {
      root.dispose();
    }
  }

  wasi.Descriptor _open(
    wasi.Descriptor root,
    String path,
    String operation, {
    bool read = false,
    bool write = false,
    bool create = false,
    bool truncate = false,
    bool directory = false,
  }) {
    return _check(
      root.openAt(
        pathFlags: _followLinks,
        path: path,
        openFlags: {
          if (create) wasi.OpenFlagsFlag.create,
          if (truncate) wasi.OpenFlagsFlag.truncate,
          if (directory) wasi.OpenFlagsFlag.directory,
        },
        flags: {
          if (read) wasi.DescriptorFlagsFlag.read,
          if (write) wasi.DescriptorFlagsFlag.write,
        },
      ),
      operation,
      path,
    );
  }

  static T _check<T>(
    Result<T, wasi.ErrorCode> result,
    String operation,
    String path,
  ) {
    return switch (result) {
      OkResult(:final value) => value,
      ErrorResult(:final value) => throw FileException._(
        value.name,
        operation,
        path,
      ),
    };
  }

  static FileKind _kindOf(wasi.DescriptorType type) => switch (type) {
    wasi.DescriptorType.regularFile => FileKind.file,
    wasi.DescriptorType.directory => FileKind.directory,
    _ => FileKind.other,
  };
}

extension DataFolderContext on Context {
  /// The plugin's folder for files that survive restarts. Needs the
  /// `fs.read.data` / `fs.write.data` permissions, see [DataFolder].
  DataFolder get files => DataFolder._(getDataFolder());
}
