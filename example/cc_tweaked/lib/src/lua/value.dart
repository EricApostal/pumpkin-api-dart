// The value model of the Lua VM.
//
// Lua values are plain Dart objects:
//
// | Lua       | Dart                                  |
// | --------- | ------------------------------------- |
// | nil       | `null`                                |
// | boolean   | `bool`                                |
// | number    | `double` (CC has no integer subtype)  |
// | string    | `String`, one UTF-16 unit per *byte*  |
// | table     | [LuaTable]                            |
// | function  | [LuaFunction]                         |
// | thread    | `Coroutine` (see vm.dart)             |
//
// Strings hold bytes, like in real Lua: every code unit is in 0..255, so a
// UTF-8 file read as Latin-1 round-trips untouched and `#s` is a byte count.
import 'bytecode.dart';

/// A heap box for a local variable captured by a closure.
final class Cell {
  Object? value;

  Cell(this.value);
}

/// An error raised by Lua code or by a library function.
///
/// [value] is the Lua error value, usually a string. When [needsPosition] is
/// set the VM prefixes the position (`chunk:line:`) of the running Lua
/// function the first time the error passes through it.
final class LuaError implements Exception {
  Object? value;
  bool needsPosition;

  /// A Lua traceback, filled in when the error leaves a coroutine.
  String? traceback;

  LuaError(this.value, {this.needsPosition = false});

  /// An error message that should get a source position, like the errors of
  /// library functions.
  LuaError.message(String message) : value = message, needsPosition = true;

  @override
  String toString() => value is String ? value! as String : 'error object';
}

/// Something callable from Lua.
sealed class LuaFunction {
  const LuaFunction();

  /// A name for error messages and tracebacks.
  String get name;
}

/// A compiled Lua function with its captured variables and environment.
final class LuaClosure extends LuaFunction {
  final FunctionProto proto;
  final List<Cell> upvalues;

  /// The table global names resolve against (Lua 5.1 `setfenv`).
  LuaTable env;

  LuaClosure(this.proto, this.upvalues, this.env);

  @override
  String get name => proto.name;
}

/// What a [NativeFunction] needs from the VM beyond a plain call.
enum NativeKind {
  /// An ordinary library function.
  normal,

  /// `pcall`.
  pcall,

  /// `xpcall`.
  xpcall,

  /// `coroutine.yield`.
  yield,

  /// `coroutine.resume`.
  resume,

  /// The function returned by `coroutine.wrap`.
  wrap,
}

/// The signature of library functions: arguments in, results out.
typedef NativeImpl = List<Object?> Function(List<Object?> args);

/// A function implemented in Dart.
final class NativeFunction extends LuaFunction {
  @override
  final String name;
  final NativeImpl impl;
  final NativeKind kind;

  /// The coroutine of a [NativeKind.wrap] function.
  final Object? data;

  NativeFunction(
    this.name,
    this.impl, {
    this.kind = NativeKind.normal,
    this.data,
  });
}

/// The shared empty result list.
const List<Object?> noValues = <Object?>[];

/// The largest integer a `double` represents exactly.
const double _maxExactInt = 9007199254740992;

/// A Lua table with an array part and an insertion-ordered hash part.
///
/// * `arr[i]` holds key `i + 1` and never ends with `nil`, so `arr.length` is
///   a valid border for `#t`.
/// * The hash part keeps removed entries as tombstones until the next growth,
///   so `next` keeps working while a traversal clears fields.
/// * Number keys are `double`s; `-0.0` is normalised and `NaN` is rejected.
final class LuaTable {
  final List<Object?> arr = <Object?>[];
  Map<Object, int>? _index;
  List<Object?>? _keys;
  List<Object?>? _values;
  int _tombstones = 0;

  /// The metatable, if any.
  LuaTable? meta;

  LuaTable();

  /// The length border (`#t` without metamethods).
  int get length => arr.length;

  /// Number of entries in the hash part, including tombstones.
  int get hashSize => _keys?.length ?? 0;

  /// The value for [key], or null.
  Object? get(Object? key) {
    if (key == null) return null;
    if (key is double) {
      if (key >= 1 && key <= arr.length) {
        final i = key.toInt();
        if (i.toDouble() == key) return arr[i - 1];
      } else if (key == 0) {
        return _hashGet(0.0);
      }
    }
    return _hashGet(key);
  }

  /// The value for the string [key].
  Object? getString(String key) => _hashGet(key);

  /// The value for the integer [key].
  Object? getInt(int key) {
    if (key >= 1 && key <= arr.length) return arr[key - 1];
    return _hashGet(key.toDouble());
  }

  Object? _hashGet(Object key) {
    final index = _index;
    if (index == null) return null;
    final slot = index[key];
    return slot == null ? null : _values![slot];
  }

  /// Sets `this[key] = value`. The caller has checked that [key] is neither
  /// nil nor NaN.
  void set(Object key, Object? value) {
    if (key is double) {
      if (key >= 1 && key <= _maxExactInt) {
        final i = key.toInt();
        if (i.toDouble() == key) {
          _setInt(i, value);
          return;
        }
      } else if (key == 0) {
        key = 0.0;
      }
    }
    _hashSet(key, value);
  }

  /// Sets the string [key].
  void setString(String key, Object? value) => _hashSet(key, value);

  /// Sets the integer [key].
  void setInt(int key, Object? value) => _setInt(key, value);

  void _setInt(int i, Object? value) {
    final n = arr.length;
    if (i >= 1 && i <= n) {
      if (value == null && i == n) {
        arr.removeLast();
        while (arr.isNotEmpty && arr.last == null) {
          arr.removeLast();
        }
      } else {
        arr[i - 1] = value;
      }
      return;
    }
    if (i == n + 1) {
      if (value == null) {
        _hashSet(i.toDouble(), null);
        return;
      }
      arr.add(value);
      _migrate();
      return;
    }
    _hashSet(i.toDouble(), value);
  }

  /// Moves keys that now continue the array part out of the hash part.
  void _migrate() {
    final index = _index;
    if (index == null || index.isEmpty) return;
    while (true) {
      final key = (arr.length + 1).toDouble();
      final slot = index[key];
      if (slot == null) return;
      final value = _values![slot];
      if (value == null) return;
      _values![slot] = null;
      _tombstones++;
      arr.add(value);
    }
  }

  void _hashSet(Object key, Object? value) {
    var index = _index;
    if (index == null) {
      if (value == null) return;
      index = _index = <Object, int>{};
      _keys = <Object?>[];
      _values = <Object?>[];
    }
    final slot = index[key];
    if (slot != null) {
      final old = _values![slot];
      _values![slot] = value;
      if (old == null && value != null) _tombstones--;
      if (old != null && value == null) _tombstones++;
      return;
    }
    if (value == null) return;
    if (_tombstones > 16 && _tombstones * 2 > _keys!.length) _compact();
    index[key] = _keys!.length;
    _keys!.add(key);
    _values!.add(value);
  }

  void _compact() {
    final keys = _keys!;
    final values = _values!;
    final newKeys = <Object?>[];
    final newValues = <Object?>[];
    final index = _index!;
    index.clear();
    for (var i = 0; i < keys.length; i++) {
      final value = values[i];
      if (value == null) continue;
      index[keys[i]!] = newKeys.length;
      newKeys.add(keys[i]);
      newValues.add(value);
    }
    _keys = newKeys;
    _values = newValues;
    _tombstones = 0;
  }

  /// The entry after [key] in traversal order (`null` starts), or `null` at
  /// the end. Throws [LuaError] if [key] is not in the table.
  (Object?, Object?)? next(Object? key) {
    var arrayPos = 0;
    var hashPos = 0;
    if (key != null) {
      var found = false;
      if (key is double && key >= 1 && key <= arr.length) {
        final i = key.toInt();
        if (i.toDouble() == key) {
          arrayPos = i;
          found = true;
        }
      }
      if (!found) {
        final index = _index;
        final slot = index == null ? null : index[key is double && key == 0 ? 0.0 : key];
        if (slot != null) {
          arrayPos = arr.length;
          hashPos = slot + 1;
        } else if (key is double && key >= 1) {
          // An array entry cleared (and trimmed) during the traversal: carry
          // on with the hash part.
          arrayPos = arr.length;
        } else {
          throw LuaError.message("invalid key to 'next'");
        }
      }
    }
    for (var i = arrayPos; i < arr.length; i++) {
      final value = arr[i];
      if (value != null) return ((i + 1).toDouble(), value);
    }
    final keys = _keys;
    if (keys == null) return null;
    final values = _values!;
    for (var i = hashPos; i < keys.length; i++) {
      final value = values[i];
      if (value != null) return (keys[i], value);
    }
    return null;
  }
}

/// The Lua type name of [value].
String luaTypeName(Object? value) {
  if (value == null) return 'nil';
  if (value is bool) return 'boolean';
  if (value is double) return 'number';
  if (value is String) return 'string';
  if (value is LuaTable) return 'table';
  if (value is LuaFunction) return 'function';
  return 'thread';
}

/// Whether [value] counts as true in a condition.
bool isTruthy(Object? value) => value != null && value != false;

/// Converts a Lua string to a number the way `tonumber` and arithmetic do, or
/// returns null.
double? parseLuaNumber(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && _isSpace(text.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isSpace(text.codeUnitAt(end - 1))) {
    end--;
  }
  if (start == end) return null;
  final s = text.substring(start, end);
  var i = 0;
  var negative = false;
  if (s[0] == '-' || s[0] == '+') {
    negative = s[0] == '-';
    i = 1;
  }
  if (i + 1 < s.length && s[i] == '0' && (s[i + 1] == 'x' || s[i + 1] == 'X')) {
    final value = _parseHex(s, i + 2);
    if (value == null) return null;
    return negative ? -value : value;
  }
  if (!_decimal.hasMatch(s)) return null;
  return double.tryParse(s);
}

final RegExp _decimal = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');

bool _isSpace(int c) => c == 32 || (c >= 9 && c <= 13);

double? _parseHex(String s, int start) {
  var i = start;
  var mantissa = 0.0;
  var exponent = 0;
  var digits = 0;
  while (i < s.length) {
    final d = _hexDigit(s.codeUnitAt(i));
    if (d < 0) break;
    mantissa = mantissa * 16 + d;
    digits++;
    i++;
  }
  if (i < s.length && s[i] == '.') {
    i++;
    while (i < s.length) {
      final d = _hexDigit(s.codeUnitAt(i));
      if (d < 0) break;
      mantissa = mantissa * 16 + d;
      exponent -= 4;
      digits++;
      i++;
    }
  }
  if (digits == 0) return null;
  if (i < s.length && (s[i] == 'p' || s[i] == 'P')) {
    i++;
    var sign = 1;
    if (i < s.length && (s[i] == '+' || s[i] == '-')) {
      if (s[i] == '-') sign = -1;
      i++;
    }
    var value = 0;
    var any = false;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c < 48 || c > 57) break;
      value = value * 10 + (c - 48);
      any = true;
      i++;
    }
    if (!any) return null;
    exponent += sign * value;
  }
  if (i != s.length) return null;
  var result = mantissa;
  if (exponent > 0) {
    for (var k = 0; k < exponent && result.isFinite; k++) {
      result *= 2;
    }
  } else {
    for (var k = 0; k < -exponent && result != 0; k++) {
      result /= 2;
    }
  }
  return result;
}

int _hexDigit(int c) {
  if (c >= 48 && c <= 57) return c - 48;
  if (c >= 97 && c <= 102) return c - 87;
  if (c >= 65 && c <= 70) return c - 55;
  return -1;
}

/// Formats a number like `tostring` does (`%.14g`).
String formatNumber(double value) {
  if (value.isNaN) return 'nan';
  if (value.isInfinite) return value < 0 ? '-inf' : 'inf';
  if (value == value.truncateToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return formatG(value, 14);
}

/// C's `%.<precision>g` for a finite number.
String formatG(
  double value,
  int precision, {
  bool alternate = false,
  bool upper = false,
}) {
  if (value.isNaN) return upper ? 'NAN' : 'nan';
  if (value.isInfinite) {
    final text = value < 0 ? '-inf' : 'inf';
    return upper ? text.toUpperCase() : text;
  }
  final p = precision == 0 ? 1 : precision;
  if (value == 0) {
    final zero = value.isNegative ? '-0' : '0';
    return alternate && p > 1 ? '$zero.${'0' * (p - 1)}' : zero;
  }
  final exponential = value.toStringAsExponential(p > 21 ? 20 : p - 1);
  final ePos = exponential.indexOf('e');
  final exponent = int.parse(exponential.substring(ePos + 1));
  String text;
  if (exponent >= -4 && exponent < p) {
    final decimals = p - 1 - exponent;
    if (decimals <= 20) {
      text = value.toStringAsFixed(decimals);
      if (!alternate && text.contains('.')) text = _trimZeros(text);
      return text;
    }
  }
  var mantissa = exponential.substring(0, ePos);
  if (!alternate && mantissa.contains('.')) mantissa = _trimZeros(mantissa);
  final sign = exponent < 0 ? '-' : '+';
  final digits = exponent.abs().toString().padLeft(2, '0');
  text = '$mantissa${upper ? 'E' : 'e'}$sign$digits';
  return text;
}

String _trimZeros(String text) {
  var end = text.length;
  while (end > 0 && text.codeUnitAt(end - 1) == 48) {
    end--;
  }
  if (end > 0 && text.codeUnitAt(end - 1) == 46) end--;
  return text.substring(0, end);
}

/// A `tostring` without metamethods.
String rawToString(Object? value) {
  if (value == null) return 'nil';
  if (value is bool) return value ? 'true' : 'false';
  if (value is double) return formatNumber(value);
  if (value is String) return value;
  final kind = luaTypeName(value);
  final id = identityHashCode(value).toRadixString(16).padLeft(8, '0');
  return value is NativeFunction ? 'function: builtin: $id' : '$kind: 0x$id';
}
