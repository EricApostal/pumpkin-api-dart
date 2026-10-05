// A computer's file system: mounts at locations (`""` is the root, `rom` the
// read-only ROM), path handling and open files, after CC: Tweaked's
// `FileSystem` and `MountWrapper`.
import 'dart:typed_data';

const String noSuchFile = 'No such file';
const String notADirectory = 'Not a directory';
const String notAFile = 'Not a file';
const String accessDenied = 'Access denied';
const String fileExists = 'File exists';
const String cannotWriteToDirectory = 'Cannot write to directory';
const String outOfSpace = 'Out of space';

/// The smallest amount of space any file or directory uses against a quota.
const int minimumFileSize = 500;

/// A failed file system operation. [message] is what the program sees.
final class FileSystemException implements Exception {
  final String message;

  const FileSystemException(this.message);

  /// An exception about [path]: `/path: message`.
  FileSystemException.of(String path, String reason) : message = '/$path: $reason';

  @override
  String toString() => message;
}

/// Size and times of a file or directory.
final class FileAttributes {
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final DateTime created;

  const FileAttributes({
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.created,
  });
}

/// A read-only tree of files. Paths are relative to the mount and use `/`.
abstract interface class Mount {
  bool exists(String path);

  bool isDirectory(String path);

  /// The names in the directory [path].
  List<String> list(String path);

  /// The size of a file in bytes (0 for directories).
  int size(String path);

  /// The whole content of a file.
  Uint8List read(String path);

  FileAttributes attributes(String path);
}

/// A mount programs can change, with a space quota.
abstract interface class WritableMount implements Mount {
  void makeDirectory(String path);

  void delete(String path);

  void rename(String source, String destination);

  /// Replaces the content of [path] (creating it and its parents).
  void write(String path, Uint8List data);

  /// Throws if a file of [newSize] bytes at [path] would not fit.
  void checkSpace(String path, int newSize);

  /// Free space in bytes.
  int get remainingSpace;

  /// The quota in bytes.
  int get capacity;
}

/// An open file: a position in an in-memory copy of its content, written back
/// to the mount on `flush` and `close`.
final class OpenFile {
  final bool readable;
  final bool writable;
  final bool appendOnly;
  final void Function(Uint8List data)? _commit;
  final void Function(int newSize)? _checkSpace;
  final void Function(OpenFile file) _onClose;

  Uint8List _data;
  int _length;
  int _position = 0;
  bool _dirty = false;
  bool _closed = false;

  OpenFile._(
    this._data,
    this._commit,
    this._checkSpace,
    this._onClose, {
    required this.readable,
    required this.writable,
    required this.appendOnly,
  }) : _length = _data.length;

  /// A read-only file over [bytes] that is not part of any file system (the
  /// files of a `file_transfer` event).
  factory OpenFile.memory(Uint8List bytes) => OpenFile._(
    bytes,
    null,
    null,
    (_) {},
    readable: true,
    writable: false,
    appendOnly: false,
  );

  bool get isClosed => _closed;

  int get length => _length;

  int get position => _position;

  /// Reads up to [count] bytes; null at the end of the file.
  Uint8List? read(int count) {
    if (_position >= _length) return null;
    final end = _position + count > _length ? _length : _position + count;
    final bytes = Uint8List.sublistView(_data, _position, end);
    _position = end;
    return bytes;
  }

  /// Reads one byte, or -1 at the end of the file.
  int readByte() => _position >= _length ? -1 : _data[_position++];

  /// Reads the rest of the file.
  Uint8List readAll() {
    final bytes = Uint8List.sublistView(_data, _position < _length ? _position : _length, _length);
    _position = _length;
    return bytes;
  }

  /// Reads a line like CC does: `\r\n` and `\n` end it, the terminator is
  /// kept with [withTrailing]. Null at the end of the file.
  Uint8List? readLine(bool withTrailing) {
    if (_position >= _length) return null;
    final out = BytesBuilder(copy: false);
    var pendingReturn = false;
    while (true) {
      if (_position >= _length) {
        if (pendingReturn) out.addByte(13);
        return out.takeBytes();
      }
      final c = _data[_position++];
      if (c == 10) {
        if (withTrailing) {
          if (pendingReturn) out.addByte(13);
          out.addByte(10);
        }
        return out.takeBytes();
      }
      if (pendingReturn) out.addByte(13);
      pendingReturn = c == 13;
      if (!pendingReturn) out.addByte(c);
    }
  }

  /// Writes [bytes] at the position (at the end for append-only files).
  void write(List<int> bytes) {
    if (appendOnly) _position = _length;
    final end = _position + bytes.length;
    if (end > _length) _checkSpace?.call(end);
    if (end > _data.length) {
      final grown = Uint8List(end < 64 ? 64 : end * 2);
      grown.setRange(0, _length, _data);
      _data = grown;
    }
    if (_position > _length) _data.fillRange(_length, _position, 0);
    _data.setRange(_position, end, bytes);
    _position = end;
    if (end > _length) _length = end;
    _dirty = true;
  }

  /// Moves the position; returns the new one or null if it would be negative.
  int? seek(String whence, int offset) {
    final base = switch (whence) {
      'set' => 0,
      'end' => _length,
      _ => _position,
    };
    final target = base + offset;
    if (target < 0) return null;
    _position = target;
    return target;
  }

  /// Writes the content back to the mount.
  void flush() {
    final commit = _commit;
    if (commit == null || !_dirty) return;
    commit(Uint8List.sublistView(_data, 0, _length));
    _dirty = false;
  }

  void close() {
    if (_closed) return;
    try {
      flush();
    } finally {
      _closed = true;
      _onClose(this);
    }
  }
}

final class _MountEntry {
  final String label;
  final String location;
  final Mount mount;
  final WritableMount? writable;

  _MountEntry(this.label, this.location, this.mount) : writable = mount is WritableMount ? mount : null;
}

/// The file system of one computer.
final class FileSystem {
  /// How many files a program may keep open (CC: `maximum_open_files`).
  final int maxOpenFiles;

  final Map<String, _MountEntry> _mounts = {};
  final Set<OpenFile> _open = {};

  FileSystem({this.maxOpenFiles = 128});

  /// Mounts [mount] at [location] (replacing what is there).
  void mount(String label, String location, Mount mount) {
    final path = sanitizePath(location);
    if (path.contains('..')) {
      throw const FileSystemException('Cannot mount below the root');
    }
    _mounts[path] = _MountEntry(label, path, mount);
  }

  /// Flushes and closes every open file.
  void close() {
    for (final file in _open.toList()) {
      try {
        file.close();
      } on FileSystemException {
        // The data could not be saved (out of space); nothing else to do.
      }
    }
    _open.clear();
  }

  // -- Paths ----------------------------------------------------------------

  static const String _specialChars = '"*:<>?|';
  static const String _specialCharsWildcards = '":<>|';

  /// Cleans a path: no leading, trailing or repeated slashes, `.` and `..`
  /// resolved, control and special characters removed.
  static String sanitizePath(String path, {bool allowWildcards = false}) {
    final forbidden = allowWildcards ? _specialCharsWildcards : _specialChars;
    final cleaned = StringBuffer();
    for (var i = 0; i < path.length; i++) {
      final c = path[i] == '\\' ? '/' : path[i];
      if (c.codeUnitAt(0) >= 32 && !forbidden.contains(c)) cleaned.write(c);
    }
    final parts = <String>[];
    for (final raw in cleaned.toString().split('/')) {
      var part = raw.trim();
      if (part.length > 255) part = part.substring(0, 255).trim();
      if (part == '..') {
        if (parts.isEmpty || parts.last == '..') {
          parts.add('..');
        } else {
          parts.removeLast();
        }
      } else if (part.isEmpty || (part.startsWith('.') && _onlyDotsAndSpaces(part))) {
        continue;
      } else {
        parts.add(part);
      }
    }
    return parts.join('/');
  }

  static bool _onlyDotsAndSpaces(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c != '.' && c != ' ') return false;
    }
    return true;
  }

  /// `fs.combine`.
  static String combine(String path, String child) {
    final a = sanitizePath(path, allowWildcards: true);
    final b = sanitizePath(child, allowWildcards: true);
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return sanitizePath('$a/$b', allowWildcards: true);
  }

  /// `fs.getDir`.
  static String directoryOf(String path) {
    final clean = sanitizePath(path, allowWildcards: true);
    if (clean.isEmpty) return '..';
    final slash = clean.lastIndexOf('/');
    final last = clean.substring(slash < 0 ? 0 : slash + 1);
    if (last == '..') return '$clean/..';
    return slash >= 0 ? clean.substring(0, slash) : '';
  }

  /// `fs.getName`.
  static String nameOf(String path) {
    final clean = sanitizePath(path, allowWildcards: true);
    if (clean.isEmpty) return 'root';
    final slash = clean.lastIndexOf('/');
    return slash >= 0 ? clean.substring(slash + 1) : clean;
  }

  static bool _contains(String outer, String inner) {
    final a = sanitizePath(outer).toLowerCase();
    final b = sanitizePath(inner).toLowerCase();
    if (b == '..' || b.startsWith('../')) return false;
    if (b == a) return true;
    if (a.isEmpty) return true;
    return b.startsWith('$a/');
  }

  static String _toLocal(String path, String location) {
    final clean = sanitizePath(path);
    final loc = sanitizePath(location);
    final local = clean.substring(loc.length);
    return local.startsWith('/') ? local.substring(1) : local;
  }

  _MountEntry _mountFor(String path) {
    _MountEntry? match;
    var matchLength = 1 << 30;
    for (final entry in _mounts.values) {
      if (_contains(entry.location, path)) {
        final length = _toLocal(path, entry.location).length;
        if (match == null || length < matchLength) {
          match = entry;
          matchLength = length;
        }
      }
    }
    if (match == null) throw FileSystemException.of(path, 'Invalid Path');
    return match;
  }

  FileSystemException _error(_MountEntry entry, String local, String reason) {
    final full = entry.location.isEmpty
        ? local
        : (local.isEmpty ? entry.location : '${entry.location}/$local');
    return FileSystemException.of(full, reason);
  }

  // -- Queries --------------------------------------------------------------

  bool exists(String path) {
    final clean = sanitizePath(path);
    final entry = _mountFor(clean);
    return entry.mount.exists(_toLocal(clean, entry.location));
  }

  bool isDirectory(String path) {
    final clean = sanitizePath(path);
    final entry = _mountFor(clean);
    return entry.mount.isDirectory(_toLocal(clean, entry.location));
  }

  bool isReadOnly(String path) {
    final entry = _mountFor(sanitizePath(path));
    return entry.writable == null;
  }

  String mountLabel(String path) => _mountFor(sanitizePath(path)).label;

  int size(String path) {
    final clean = sanitizePath(path);
    final entry = _mountFor(clean);
    final local = _toLocal(clean, entry.location);
    if (!entry.mount.exists(local)) throw _error(entry, local, noSuchFile);
    return entry.mount.size(local);
  }

  FileAttributes attributes(String path) {
    final clean = sanitizePath(path);
    final entry = _mountFor(clean);
    final local = _toLocal(clean, entry.location);
    if (!entry.mount.exists(local)) throw _error(entry, local, noSuchFile);
    return entry.mount.attributes(local);
  }

  /// The names in directory [path], including mounts located directly in it.
  List<String> list(String path) {
    final clean = sanitizePath(path);
    final entry = _mountFor(clean);
    final local = _toLocal(clean, entry.location);
    if (!entry.mount.exists(local)) throw _error(entry, local, noSuchFile);
    if (!entry.mount.isDirectory(local)) {
      throw _error(entry, local, notADirectory);
    }
    final names = entry.mount.list(local).toList();
    for (final other in _mounts.values) {
      if (other.location.isNotEmpty && directoryOf(other.location) == clean) {
        final name = nameOf(other.location);
        if (!names.contains(name)) names.add(name);
      }
    }
    names.sort();
    return names;
  }

  /// Free space on the mount containing [path]; 0 for read-only mounts.
  int freeSpace(String path) =>
      _mountFor(sanitizePath(path)).writable?.remainingSpace ?? 0;

  /// The quota of the mount containing [path], or null if it has none.
  int? capacity(String path) => _mountFor(sanitizePath(path)).writable?.capacity;

  // -- Changes --------------------------------------------------------------

  WritableMount _writableFor(String clean, _MountEntry entry, String local) {
    final writable = entry.writable;
    if (writable == null) throw FileSystemException.of(clean, accessDenied);
    return writable;
  }

  void makeDirectory(String path) {
    final clean = sanitizePath(path);
    final entry = _mountFor(clean);
    final local = _toLocal(clean, entry.location);
    _writableFor(clean, entry, local).makeDirectory(local);
  }

  void delete(String path) {
    final clean = sanitizePath(path);
    final entry = _mountFor(clean);
    final local = _toLocal(clean, entry.location);
    _writableFor(clean, entry, local).delete(local);
  }

  void move(String source, String destination) {
    final from = sanitizePath(source);
    final to = sanitizePath(destination);
    if (isReadOnly(from) || isReadOnly(to)) {
      throw const FileSystemException(accessDenied);
    }
    if (!exists(from)) throw const FileSystemException(noSuchFile);
    if (exists(to)) throw const FileSystemException(fileExists);
    if (_contains(from, to)) {
      throw const FileSystemException("Can't move a directory inside itself");
    }
    final fromEntry = _mountFor(from);
    final toEntry = _mountFor(to);
    if (identical(fromEntry, toEntry)) {
      final writable = fromEntry.writable!;
      final localTo = _toLocal(to, toEntry.location);
      final parent = directoryOf(localTo);
      if (localTo.isNotEmpty && parent.isNotEmpty && !writable.exists(parent)) {
        writable.makeDirectory(parent);
      }
      writable.rename(_toLocal(from, fromEntry.location), localTo);
    } else {
      copy(from, to);
      delete(from);
    }
  }

  void copy(String source, String destination) {
    final from = sanitizePath(source);
    final to = sanitizePath(destination);
    if (isReadOnly(to)) throw FileSystemException.of(to, accessDenied);
    if (!exists(from)) throw FileSystemException.of(from, noSuchFile);
    if (exists(to)) throw FileSystemException.of(to, fileExists);
    if (_contains(from, to)) {
      throw FileSystemException.of(from, "Can't copy a directory inside itself");
    }
    _copyRecursive(from, to, 0);
  }

  void _copyRecursive(String from, String to, int depth) {
    if (!exists(from)) return;
    if (depth >= 128) {
      throw const FileSystemException('Too many directories to copy');
    }
    if (isDirectory(from)) {
      makeDirectory(to);
      for (final child in list(from)) {
        _copyRecursive(combine(from, child), combine(to, child), depth + 1);
      }
    } else {
      final data = _readBytes(from);
      final entry = _mountFor(to);
      final local = _toLocal(to, entry.location);
      final writable = _writableFor(to, entry, local);
      writable.checkSpace(local, data.length);
      writable.write(local, data);
    }
  }

  Uint8List _readBytes(String clean) {
    final entry = _mountFor(clean);
    final local = _toLocal(clean, entry.location);
    if (!entry.mount.exists(local) || entry.mount.isDirectory(local)) {
      throw _error(entry, local, noSuchFile);
    }
    return entry.mount.read(local);
  }

  // -- Open files -----------------------------------------------------------

  void _register(OpenFile file) {
    _open.add(file);
  }

  void _checkOpenLimit() {
    if (maxOpenFiles > 0 && _open.length >= maxOpenFiles) {
      throw const FileSystemException('Too many files already open');
    }
  }

  /// Opens [path] for reading.
  OpenFile openRead(String path) {
    final clean = sanitizePath(path);
    final entry = _mountFor(clean);
    final local = _toLocal(clean, entry.location);
    if (!entry.mount.exists(local) || entry.mount.isDirectory(local)) {
      throw _error(entry, local, noSuchFile);
    }
    _checkOpenLimit();
    final file = OpenFile._(
      Uint8List.fromList(entry.mount.read(local)),
      null,
      null,
      _open.remove,
      readable: true,
      writable: false,
      appendOnly: false,
    );
    _register(file);
    return file;
  }

  /// Opens [path] for writing. [append] keeps the content and writes at the
  /// end; [truncate] starts empty; [readable] allows reading too (`r+`/`w+`).
  OpenFile openWrite(
    String path, {
    bool append = false,
    bool truncate = true,
    bool readable = false,
  }) {
    final clean = sanitizePath(path);
    final entry = _mountFor(clean);
    final local = _toLocal(clean, entry.location);
    final writable = _writableFor(clean, entry, local);
    if (writable.isDirectory(local)) {
      throw _error(entry, local, truncate || append ? cannotWriteToDirectory : notAFile);
    }
    final existing = writable.exists(local);
    if (!existing && !truncate && !append) throw _error(entry, local, noSuchFile);
    _checkOpenLimit();
    final parent = directoryOf(local);
    if (!existing && local.isNotEmpty && parent.isNotEmpty && !writable.exists(parent)) {
      writable.makeDirectory(parent);
    }
    final initial = existing && !truncate ? Uint8List.fromList(writable.read(local)) : Uint8List(0);
    if (!existing || truncate) {
      writable.checkSpace(local, 0);
      writable.write(local, Uint8List(0));
    }
    final file = OpenFile._(
      initial,
      (data) => writable.write(local, data),
      (newSize) => writable.checkSpace(local, newSize),
      _open.remove,
      readable: readable,
      writable: true,
      appendOnly: append,
    );
    _register(file);
    return file;
  }
}
