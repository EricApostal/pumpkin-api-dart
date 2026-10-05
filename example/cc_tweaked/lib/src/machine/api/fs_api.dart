// The `fs` API and the file handles it returns.
import 'dart:typed_data';

import '../../lua/lua.dart';
import '../filesystem.dart';

/// Builds the global `fs` table. [fileSystem] returns the computer's file
/// system while it is on.
LuaTable buildFsApi(FileSystem Function() fileSystem) {
  final table = LuaTable();

  void define1(String name, List<Object?> Function(Args args, FileSystem fs) body) {
    table.setString(name, NativeFunction(name, (list) {
      try {
        return body(Args(name, list), fileSystem());
      } on FileSystemException catch (e) {
        throw LuaError.message(e.message);
      }
    }));
  }

  define1('list', (args, fs) {
    final names = fs.list(args.string(0));
    final result = LuaTable();
    for (var i = 0; i < names.length; i++) {
      result.setInt(i + 1, names[i]);
    }
    return one(result);
  });

  table.setString('combine', NativeFunction('combine', (list) {
    final args = Args('combine', list);
    final out = StringBuffer(FileSystem.sanitizePath(args.string(0), allowWildcards: true));
    for (var i = 1; i < list.length; i++) {
      final part = FileSystem.sanitizePath(args.string(i), allowWildcards: true);
      if (out.length != 0 && part.isNotEmpty) out.write('/');
      out.write(part);
    }
    return one(FileSystem.sanitizePath(out.toString(), allowWildcards: true));
  }));

  define1('getName', (args, _) => one(FileSystem.nameOf(args.string(0))));
  define1('getDir', (args, _) => one(FileSystem.directoryOf(args.string(0))));
  define1('getSize', (args, fs) => one(fs.size(args.string(0)).toDouble()));

  define1('exists', (args, fs) {
    try {
      return one(fs.exists(args.string(0)));
    } on FileSystemException {
      return one(false);
    }
  });

  define1('isDir', (args, fs) {
    try {
      return one(fs.isDirectory(args.string(0)));
    } on FileSystemException {
      return one(false);
    }
  });

  define1('isReadOnly', (args, fs) {
    try {
      return one(fs.isReadOnly(args.string(0)));
    } on FileSystemException {
      return one(false);
    }
  });

  define1('makeDir', (args, fs) {
    fs.makeDirectory(args.string(0));
    return noValues;
  });

  define1('move', (args, fs) {
    fs.move(args.string(0), args.string(1));
    return noValues;
  });

  define1('copy', (args, fs) {
    fs.copy(args.string(0), args.string(1));
    return noValues;
  });

  define1('delete', (args, fs) {
    fs.delete(args.string(0));
    return noValues;
  });

  define1('getDrive', (args, fs) {
    final path = args.string(0);
    return fs.exists(path) ? one(fs.mountLabel(path)) : one(null);
  });

  define1('getFreeSpace', (args, fs) => one(fs.freeSpace(args.string(0)).toDouble()));

  define1('getCapacity', (args, fs) {
    final capacity = fs.capacity(args.string(0));
    return one(capacity?.toDouble());
  });

  define1('attributes', (args, fs) {
    final path = args.string(0);
    final attributes = fs.attributes(path);
    final millis = attributes.modified.millisecondsSinceEpoch.toDouble();
    final result = LuaTable()
      ..setString('modification', millis)
      ..setString('modified', millis)
      ..setString('created', attributes.created.millisecondsSinceEpoch.toDouble())
      ..setString('size', attributes.isDirectory ? 0.0 : attributes.size.toDouble())
      ..setString('isDir', attributes.isDirectory)
      ..setString('isReadOnly', fs.isReadOnly(path));
    return one(result);
  });

  table.setString('open', NativeFunction('open', (list) {
    final args = Args('open', list);
    final path = args.string(0);
    final mode = args.string(1);
    if (mode.isEmpty) throw LuaError.message(unsupportedMode);
    final fs = fileSystem();
    final binary = mode.contains('b');
    try {
      final OpenFile file;
      switch (mode) {
        case 'r':
        case 'rb':
          file = fs.openRead(path);
        case 'w':
        case 'wb':
          file = fs.openWrite(path);
        case 'a':
        case 'ab':
          file = fs.openWrite(path, append: true, truncate: false);
        case 'r+':
        case 'r+b':
          file = fs.openWrite(path, truncate: false, readable: true);
        case 'w+':
        case 'w+b':
          file = fs.openWrite(path, readable: true);
        default:
          throw LuaError.message(unsupportedMode);
      }
      return one(_handle(file, binary, seekable: mode != 'a' && mode != 'ab'));
    } on FileSystemException catch (e) {
      return <Object?>[null, e.message];
    }
  }));

  return table;
}

const String unsupportedMode = 'Unsupported mode';

Uint8List _bytes(String s) => Uint8List.fromList(s.codeUnits);

/// The Lua handle of a file transferred to the computer (`file_transfer`): a
/// binary read handle.
LuaTable buildBinaryReadHandle(OpenFile file) => _handle(file, true, seekable: true);

LuaTable _handle(OpenFile file, bool binary, {required bool seekable}) {
  final handle = LuaTable();

  void method(String name, List<Object?> Function(Args args) body) {
    handle.setString(name, NativeFunction(name, (list) {
      if (file.isClosed) throw LuaError.message('attempt to use a closed file');
      try {
        return body(Args(name, list));
      } on FileSystemException catch (e) {
        throw LuaError.message(e.message);
      }
    }));
  }

  if (file.readable) {
    method('read', (args) {
      if (binary && args.isNone(0)) {
        final byte = file.readByte();
        return one(byte < 0 ? null : byte.toDouble());
      }
      final count = args.optInteger(0, 1);
      if (count < 0) {
        throw LuaError.message('Cannot read a negative number of bytes');
      }
      if (count == 0) return one(file.position >= file.length ? null : '');
      final bytes = file.read(count);
      return one(bytes == null ? null : String.fromCharCodes(bytes));
    });
    method('readAll', (args) => one(String.fromCharCodes(file.readAll())));
    method('readLine', (args) {
      final line = file.readLine(args.boolean(0));
      return one(line == null ? null : String.fromCharCodes(line));
    });
  }

  if (file.writable) {
    method('write', (args) {
      final value = args.any(0);
      if (binary && value is double) {
        file.write([value.toInt() & 0xFF]);
      } else if (value is String) {
        file.write(_bytes(value));
      } else if (value is double) {
        file.write(_bytes(formatNumber(value)));
      } else {
        args.wrongType(0, 'string');
      }
      return noValues;
    });
    method('writeLine', (args) {
      final value = args.any(0);
      final text = value is String
          ? value
          : (value is double ? formatNumber(value) : args.wrongType(0, 'string'));
      file.write(_bytes(text));
      file.write(const [10]);
      return noValues;
    });
    method('flush', (args) {
      file.flush();
      return noValues;
    });
  }

  if (file.readable || seekable) {
    method('seek', (args) {
      final whence = args.optString(0, 'cur');
      if (whence != 'set' && whence != 'cur' && whence != 'end') {
        throw LuaError.message("bad argument #1 to 'seek' (invalid option '$whence'");
      }
      final position = file.seek(whence, args.optInteger(1, 0));
      return position == null
          ? <Object?>[null, 'Position is negative']
          : one(position.toDouble());
    });
  }

  handle.setString('close', NativeFunction('close', (_) {
    if (file.isClosed) throw LuaError.message('attempt to use a closed file');
    try {
      file.close();
    } on FileSystemException catch (e) {
      throw LuaError.message(e.message);
    }
    return noValues;
  }));
  return handle;
}
