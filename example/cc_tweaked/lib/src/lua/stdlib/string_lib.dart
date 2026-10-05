// The `string` library. Strings hold bytes (one code unit per byte), so
// everything is byte-oriented and ASCII-only like Lua in the C locale.
import '../value.dart';
import '../vm.dart';
import 'args.dart';
import 'lua_pattern.dart';
import 'string_format.dart';

void installString(LuaVm vm) {
  final lib = LuaTable();
  vm.globals.setString('string', lib);
  vm.stringMeta.setString('__index', lib);

  define(lib, 'len', (list) => one(Args('len', list).string(0).length.toDouble()));

  define(lib, 'sub', (list) {
    final args = Args('sub', list);
    final s = args.string(0);
    final l = s.length;
    var start = _posRelative(args.integer(1), l);
    var end = _posRelative(args.optInteger(2, -1), l);
    if (start < 1) start = 1;
    if (end > l) end = l;
    return one(start <= end ? s.substring(start - 1, end) : '');
  });

  define(lib, 'upper', (list) => one(_mapAscii(Args('upper', list).string(0), true)));
  define(lib, 'lower', (list) => one(_mapAscii(Args('lower', list).string(0), false)));

  define(lib, 'reverse', (list) {
    final s = Args('reverse', list).string(0);
    final out = StringBuffer();
    for (var i = s.length - 1; i >= 0; i--) {
      out.writeCharCode(s.codeUnitAt(i));
    }
    return one(out.toString());
  });

  define(lib, 'rep', (list) {
    final args = Args('rep', list);
    final s = args.string(0);
    final n = args.integer(1);
    final separator = args.optString(2, '');
    if (n <= 0) return one('');
    final total = s.length * n + separator.length * (n - 1);
    if (total > vm.maxStringLength) {
      throw LuaError.message('not enough memory');
    }
    final out = StringBuffer();
    for (var i = 0; i < n; i++) {
      if (i > 0) out.write(separator);
      out.write(s);
    }
    return one(out.toString());
  });

  define(lib, 'byte', (list) {
    final args = Args('byte', list);
    final s = args.string(0);
    final i = _posRelative(args.optInteger(1, 1), s.length);
    var start = i;
    var end = _posRelative(args.optInteger(2, i), s.length);
    if (start < 1) start = 1;
    if (end > s.length) end = s.length;
    return [for (var k = start; k <= end; k++) s.codeUnitAt(k - 1).toDouble()];
  });

  define(lib, 'char', (list) {
    final out = StringBuffer();
    for (var i = 0; i < list.length; i++) {
      final c = Args('char', list).integer(i);
      if (c < 0 || c > 255) Args('char', list).bad(i, 'invalid value');
      out.writeCharCode(c);
    }
    return one(out.toString());
  });

  define(lib, 'format', (list) => one(formatString(vm, list)));

  define(lib, 'find', (list) => _find(vm, Args('find', list), true));
  define(lib, 'match', (list) => _find(vm, Args('match', list), false));

  final gmatch = NativeFunction('gmatch', (list) {
    final args = Args('gmatch', list);
    final s = args.string(0);
    final pattern = args.string(1);
    final matcher = PatternMatcher(s, pattern);
    var position = 0;
    return one(
      NativeFunction('gmatch_iterator', (_) {
        for (var start = position; start <= s.length; start++) {
          matcher.reset();
          final end = matcher.match(start, 0);
          if (end != -1) {
            position = end == start ? end + 1 : end;
            return matcher.captures(start, end);
          }
        }
        position = s.length + 1;
        return one(null);
      }),
    );
  });
  lib.setString('gmatch', gmatch);
  lib.setString('gfind', gmatch);

  define(lib, 'gsub', (list) => _gsub(vm, Args('gsub', list)));
}

int _posRelative(int position, int length) {
  if (position >= 0) return position;
  if (-position > length) return 0;
  return length + position + 1;
}

String _mapAscii(String s, bool upper) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    var c = s.codeUnitAt(i);
    if (upper) {
      if (c >= 97 && c <= 122) c -= 32;
    } else if (c >= 65 && c <= 90) {
      c += 32;
    }
    out.writeCharCode(c);
  }
  return out.toString();
}

List<Object?> _find(LuaVm vm, Args args, bool isFind) {
  final s = args.string(0);
  final pattern = args.string(1);
  var init = _posRelative(args.optInteger(2, 1), s.length) - 1;
  if (init < 0) init = 0;
  if (init > s.length) return one(null);
  if (isFind && (args.boolean(3) || isPlainPattern(pattern))) {
    final index = s.indexOf(pattern, init);
    if (index < 0) return one(null);
    return <Object?>[(index + 1).toDouble(), (index + pattern.length).toDouble()];
  }
  final anchor = pattern.isNotEmpty && pattern.codeUnitAt(0) == 94;
  final matcher = PatternMatcher(s, pattern);
  var start = init;
  while (true) {
    matcher.reset();
    final end = matcher.match(start, anchor ? 1 : 0);
    if (end != -1) {
      if (isFind) {
        return <Object?>[
          (start + 1).toDouble(),
          end.toDouble(),
          ...matcher.captures(start, end, wholeIfNone: false),
        ];
      }
      return matcher.captures(start, end);
    }
    start++;
    if (start > s.length || anchor) return one(null);
  }
}

List<Object?> _gsub(LuaVm vm, Args args) {
  final src = args.string(0);
  final pattern = args.string(1);
  final replacement = args[2];
  if (replacement is! String &&
      replacement is! double &&
      replacement is! LuaTable &&
      replacement is! LuaFunction) {
    args.wrongType(2, 'string/function/table');
  }
  final limit = args.optInteger(3, src.length + 1);
  final anchor = pattern.isNotEmpty && pattern.codeUnitAt(0) == 94;
  final matcher = PatternMatcher(src, pattern);
  final out = StringBuffer();
  var position = 0;
  var count = 0;
  while (count < limit) {
    matcher.reset();
    final end = matcher.match(position, anchor ? 1 : 0);
    if (end != -1) {
      count++;
      _addValue(vm, matcher, out, position, end, replacement);
    }
    if (end != -1 && end > position) {
      position = end;
    } else if (position < src.length) {
      out.writeCharCode(src.codeUnitAt(position++));
    } else {
      break;
    }
    if (anchor) break;
  }
  if (position < src.length) out.write(src.substring(position));
  return <Object?>[out.toString(), count.toDouble()];
}

void _addValue(
  LuaVm vm,
  PatternMatcher matcher,
  StringBuffer out,
  int start,
  int end,
  Object? replacement,
) {
  Object? value;
  if (replacement is String || replacement is double) {
    final text = replacement is String ? replacement : formatNumber(replacement! as double);
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c != 37) {
        out.writeCharCode(c);
        continue;
      }
      i++;
      final d = i < text.length ? text.codeUnitAt(i) : 0;
      if (d == 37) {
        out.writeCharCode(37);
      } else if (d >= 48 && d <= 57) {
        final captured = d == 48
            ? matcher.src.substring(start, end)
            : matcher.capture(d - 49, start, end);
        out.write(captured is double ? formatNumber(captured) : captured);
      } else if (i < text.length) {
        // Lua 5.1 (and CC's Cobalt) keep any other character after a '%' as
        // it is, so `%.` in a replacement string stands for `.`. Lua 5.3
        // rejects this, but CC's own ROM relies on the 5.1 behaviour (the
        // `require` module escapes dots with "%%%.").
        out.writeCharCode(d);
      }
    }
    return;
  } else if (replacement is LuaTable) {
    value = vm.index(replacement, matcher.capture(0, start, end));
  } else {
    final results = vm.call(replacement, matcher.captures(start, end));
    value = results.isEmpty ? null : results.first;
  }
  if (value == null || value == false) {
    out.write(matcher.src.substring(start, end));
  } else if (value is String) {
    out.write(value);
  } else if (value is double) {
    out.write(formatNumber(value));
  } else {
    throw LuaError.message('invalid replacement value (a ${luaTypeName(value)})');
  }
}
