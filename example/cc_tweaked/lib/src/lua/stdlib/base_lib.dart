// The basic functions (`pcall`, `setmetatable`, `load`, `pairs`, ...).
//
// `print`, `loadfile`, `dofile` and `require` are not here: CraftOS defines
// them in Lua (`bios.lua`, `cc.require`).
import '../lexer.dart';
import '../value.dart';
import '../vm.dart';
import 'args.dart';

void installBase(LuaVm vm) {
  final g = vm.globals;
  g.setString('_G', g);
  g.setString('_VERSION', 'Lua 5.1');

  define(g, 'assert', (list) {
    final args = Args('assert', list);
    final value = args.any(0);
    if (isTruthy(value)) return list;
    if (list.length > 1) throw LuaError(list[1]);
    throw LuaError.message('assertion failed!');
  });

  define(g, 'error', (list) {
    final args = Args('error', list);
    final value = args[0];
    final level = args.optInteger(1, 1);
    if (value is String && level > 0) {
      throw LuaError('${vm.where(level)}$value');
    }
    throw LuaError(value);
  });

  g.setString(
    'pcall',
    NativeFunction(
      'pcall',
      (_) => throw StateError('pcall is handled by the VM'),
      kind: NativeKind.pcall,
    ),
  );
  g.setString(
    'xpcall',
    NativeFunction(
      'xpcall',
      (_) => throw StateError('xpcall is handled by the VM'),
      kind: NativeKind.xpcall,
    ),
  );

  define(g, 'getmetatable', (list) {
    final args = Args('getmetatable', list);
    final meta = vm.metatableOf(args.any(0));
    if (meta == null) return one(null);
    final protected = meta.getString('__metatable');
    return one(protected ?? meta);
  });

  define(g, 'setmetatable', (list) {
    final args = Args('setmetatable', list);
    final table = args.table(0);
    final meta = args[1];
    if (meta != null && meta is! LuaTable || !args.has(1)) {
      args.wrongType(1, 'nil or table');
    }
    if (table.meta?.getString('__metatable') != null) {
      throw LuaError.message('cannot change a protected metatable');
    }
    table.meta = meta as LuaTable?;
    return one(table);
  });

  define(g, 'rawequal', (list) {
    final args = Args('rawequal', list);
    return one(args.any(0) == args.any(1));
  });

  define(g, 'rawget', (list) {
    final args = Args('rawget', list);
    return one(args.table(0).get(args.any(1)));
  });

  define(g, 'rawset', (list) {
    final args = Args('rawset', list);
    final table = args.table(0);
    final key = args.any(1);
    if (key == null) throw LuaError.message('table index is nil');
    if (key is double && key.isNaN) {
      throw LuaError.message('table index is NaN');
    }
    table.set(key, args.any(2));
    return one(table);
  });

  define(g, 'rawlen', (list) {
    final args = Args('rawlen', list);
    final value = args[0];
    if (value is LuaTable) return one(value.length.toDouble());
    if (value is String) return one(value.length.toDouble());
    args.wrongType(0, 'table or string');
  });

  define(g, 'type', (list) => one(luaTypeName(Args('type', list).any(0))));

  define(g, 'tostring', (list) => one(vm.tostring(Args('tostring', list).any(0))));

  define(g, 'tonumber', (list) {
    final args = Args('tonumber', list);
    final value = args.any(0);
    if (args.isNone(1)) {
      if (value is double) return one(value);
      if (value is String) return one(parseLuaNumber(value));
      return one(null);
    }
    final base = args.integer(1);
    if (base < 2 || base > 36) args.bad(1, 'base out of range');
    final text = args.string(0).trim().toLowerCase();
    if (text.isEmpty) return one(null);
    var negative = false;
    var i = 0;
    if (text[0] == '-') {
      negative = true;
      i = 1;
    } else if (text[0] == '+') {
      i = 1;
    }
    if (i >= text.length) return one(null);
    var result = 0.0;
    for (; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      final digit = c >= 48 && c <= 57
          ? c - 48
          : c >= 97 && c <= 122
          ? c - 87
          : 99;
      if (digit >= base) return one(null);
      result = result * base + digit;
    }
    return one(negative ? -result : result);
  });

  define(g, 'select', (list) {
    final args = Args('select', list);
    final selector = args.any(0);
    final count = list.length - 1;
    if (selector == '#') return one(count.toDouble());
    var n = args.integer(0);
    if (n < 0) {
      n = count + n + 1;
    } else if (n > count) {
      return noValues;
    }
    if (n < 1) args.bad(0, 'index out of range');
    return list.sublist(n);
  });

  final nextFunction = NativeFunction('next', (list) {
    final args = Args('next', list);
    final entry = args.table(0).next(args[1]);
    return entry == null ? one(null) : <Object?>[entry.$1, entry.$2];
  });
  g.setString('next', nextFunction);

  define(g, 'pairs', (list) {
    final args = Args('pairs', list);
    final value = args.any(0);
    final handler = vm.metamethod(value, '__pairs');
    if (handler != null) {
      final results = vm.call(handler, [value]);
      return <Object?>[
        results.isNotEmpty ? results[0] : null,
        results.length > 1 ? results[1] : null,
        results.length > 2 ? results[2] : null,
      ];
    }
    return <Object?>[nextFunction, args.table(0), null];
  });

  final ipairsIterator = NativeFunction('ipairs_iterator', (list) {
    final table = list[0];
    final index = (list[1]! as double) + 1;
    final value = table is LuaTable && table.meta == null
        ? table.get(index)
        : vm.index(table, index);
    return value == null ? one(null) : <Object?>[index, value];
  });
  define(g, 'ipairs', (list) {
    final args = Args('ipairs', list);
    return <Object?>[ipairsIterator, args.any(0), 0.0];
  });

  define(g, 'unpack', (list) => unpackTable(vm, Args('unpack', list)));

  define(g, 'loadstring', (list) {
    final args = Args('loadstring', list);
    final source = args.string(0);
    return _loadChunk(vm, source, args.optString(1, source), null);
  });

  define(g, 'load', (list) {
    final args = Args('load', list);
    final chunk = args[0];
    String source;
    if (chunk is String) {
      source = chunk;
    } else if (chunk is LuaFunction) {
      final buffer = StringBuffer();
      while (true) {
        final results = vm.call(chunk, const []);
        final piece = results.isEmpty ? null : results.first;
        if (piece == null || piece == '') break;
        if (piece is! String) {
          return <Object?>[null, 'reader function must return a string'];
        }
        buffer.write(piece);
      }
      source = buffer.toString();
    } else {
      args.wrongType(0, 'string');
    }
    final mode = args.optString(2, 'bt');
    if (source.startsWith('\x1bLua')) {
      return <Object?>[null, 'attempt to load a binary chunk (not supported)'];
    }
    if (!mode.contains('t')) {
      return <Object?>[null, "attempt to load a text chunk (mode is '$mode')"];
    }
    final name = args.optString(1, chunk is String ? chunk : '=(load)');
    final env = args[3];
    return _loadChunk(vm, source, name, env is LuaTable ? env : null);
  });

  define(g, 'setfenv', (list) {
    final args = Args('setfenv', list);
    final target = args[0];
    final env = args.table(1);
    if (target is LuaClosure) {
      target.env = env;
      return one(target);
    }
    throw LuaError.message("'setfenv' cannot change environment of given object");
  });

  define(g, 'getfenv', (list) {
    final target = list.isEmpty ? null : list[0];
    if (target is LuaClosure) return one(target.env);
    if (target is double && target >= 1) {
      final co = vm.current;
      if (co != null) {
        final index = co.frames.length - target.toInt();
        if (index >= 0 && co.frames[index].closure != null) {
          return one(co.frames[index].closure!.env);
        }
      }
    }
    return one(vm.globals);
  });
}

List<Object?> _loadChunk(LuaVm vm, String source, String name, LuaTable? env) {
  try {
    return one(vm.load(source, name, env: env));
  } on LuaSyntaxError catch (e) {
    return <Object?>[null, e.message];
  }
}

/// `table.unpack` / `unpack`.
List<Object?> unpackTable(LuaVm vm, Args args) {
  final table = args.any(0);
  final first = args.optInteger(1, 1);
  final int last;
  if (args.isNone(2)) {
    last = table is LuaTable && table.meta == null
        ? table.length
        : _lengthOf(vm, table);
  } else {
    last = args.integer(2);
  }
  if (first > last) return noValues;
  if (last - first >= 250000) throw LuaError.message('too many results to unpack');
  if (table is LuaTable && table.meta == null) {
    return [for (var i = first; i <= last; i++) table.getInt(i)];
  }
  return [for (var i = first; i <= last; i++) vm.index(table, i.toDouble())];
}

int _lengthOf(LuaVm vm, Object? value) {
  final handler = vm.metamethod(value, '__len');
  if (handler != null) {
    final results = vm.call(handler, [value]);
    final first = results.isEmpty ? null : results.first;
    if (first is double) return first.toInt();
    throw LuaError.message("object length is not a number");
  }
  if (value is LuaTable) return value.length;
  if (value is String) return value.length;
  throw LuaError.message('attempt to get length of a ${luaTypeName(value)} value');
}

/// `#value` with `__len`, for library functions.
int lengthOf(LuaVm vm, Object? value) => _lengthOf(vm, value);
