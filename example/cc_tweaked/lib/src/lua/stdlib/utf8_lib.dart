// The `utf8` library (Lua 5.3), over byte strings.
import '../lexer.dart';
import '../value.dart';
import '../vm.dart';
import 'args.dart';

/// Decodes one character at [pos]: its code point and byte length, or null if
/// the bytes are not valid UTF-8.
(int, int)? _decode(String s, int pos) {
  final c = s.codeUnitAt(pos);
  if (c < 0x80) return (c, 1);
  if (c < 0xC2 || c > 0xF4) return null;
  final length = c < 0xE0 ? 2 : (c < 0xF0 ? 3 : 4);
  if (pos + length > s.length) return null;
  var code = c & (0x3F >> (length - 1));
  for (var i = 1; i < length; i++) {
    final next = s.codeUnitAt(pos + i);
    if (next & 0xC0 != 0x80) return null;
    code = (code << 6) | (next & 0x3F);
  }
  if (length == 3 && code < 0x800) return null;
  if (length == 4 && (code < 0x10000 || code > 0x10FFFF)) return null;
  if (code >= 0xD800 && code <= 0xDFFF) return null;
  return (code, length);
}

bool _isContinuation(String s, int pos) =>
    pos < s.length && s.codeUnitAt(pos) & 0xC0 == 0x80;

int _relative(int position, int length) {
  if (position >= 0) return position;
  if (-position > length) return 0;
  return length + position + 1;
}

void installUtf8(LuaVm vm) {
  final lib = LuaTable();
  vm.globals.setString('utf8', lib);
  lib.setString('charpattern', '[\x00-\x7F\xC2-\xFD][\x80-\xBF]*');

  define(lib, 'char', (list) {
    final args = Args('char', list);
    final out = StringBuffer();
    for (var i = 0; i < list.length; i++) {
      final code = args.integer(i);
      if (code < 0 || code > 0x7FFFFFFF) args.bad(i, 'value out of range');
      out.write(utf8Encode(code));
    }
    return one(out.toString());
  });

  define(lib, 'codepoint', (list) {
    final args = Args('codepoint', list);
    final s = args.string(0);
    final i = _relative(args.optInteger(1, 1), s.length);
    final j = _relative(args.optInteger(2, i), s.length);
    if (i < 1) args.bad(1, 'out of range');
    if (j > s.length) args.bad(2, 'out of range');
    final out = <Object?>[];
    var pos = i - 1;
    while (pos < j) {
      final decoded = _decode(s, pos);
      if (decoded == null) throw LuaError.message('invalid UTF-8 code');
      out.add(decoded.$1.toDouble());
      pos += decoded.$2;
    }
    return out;
  });

  define(lib, 'len', (list) {
    final args = Args('len', list);
    final s = args.string(0);
    var pos = _relative(args.optInteger(1, 1), s.length) - 1;
    final end = _relative(args.optInteger(2, -1), s.length);
    var count = 0;
    while (pos < end) {
      final decoded = _decode(s, pos);
      if (decoded == null) return <Object?>[null, (pos + 1).toDouble()];
      pos += decoded.$2;
      count++;
    }
    return one(count.toDouble());
  });

  define(lib, 'offset', (list) {
    final args = Args('offset', list);
    final s = args.string(0);
    var n = args.integer(1);
    var pos = _relative(args.optInteger(2, n > 0 ? 1 : s.length + 1), s.length) - 1;
    if (pos < 0 || pos > s.length) args.bad(2, 'position out of range');
    if (n == 0) {
      while (pos > 0 && _isContinuation(s, pos)) {
        pos--;
      }
      return one((pos + 1).toDouble());
    }
    if (_isContinuation(s, pos)) {
      throw LuaError.message('initial position is a continuation byte');
    }
    if (n < 0) {
      while (n < 0 && pos > 0) {
        do {
          pos--;
        } while (pos > 0 && _isContinuation(s, pos));
        n++;
      }
    } else {
      n--;
      while (n > 0 && pos < s.length) {
        do {
          pos++;
        } while (_isContinuation(s, pos));
        n--;
      }
    }
    return n == 0 ? one((pos + 1).toDouble()) : one(null);
  });

  define(lib, 'codes', (list) {
    final s = Args('codes', list).string(0);
    final iterator = NativeFunction('codes_iterator', (state) {
      var pos = (state[1]! as double).toInt();
      // Skip the rest of the current character.
      while (pos > 0 && pos <= s.length && _isContinuation(s, pos)) {
        pos++;
      }
      if (pos >= s.length) return one(null);
      final decoded = _decode(s, pos);
      if (decoded == null) throw LuaError.message('invalid UTF-8 code');
      return <Object?>[(pos + 1).toDouble(), decoded.$1.toDouble()];
    });
    return <Object?>[iterator, s, 0.0];
  });
}
