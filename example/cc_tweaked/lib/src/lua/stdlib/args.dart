// Argument access for library functions, with Lua's error messages.
import '../value.dart';

/// The arguments of one call of the library function [name].
final class Args {
  final String name;
  final List<Object?> values;

  const Args(this.name, this.values);

  int get count => values.length;

  Object? operator [](int index) => index < values.length ? values[index] : null;

  bool has(int index) => index < values.length;

  /// Whether argument [index] is absent or nil.
  bool isNone(int index) => index >= values.length || values[index] == null;

  Never bad(int index, String message) =>
      throw LuaError.message("bad argument #${index + 1} to '$name' ($message)");

  Never wrongType(int index, String expected) => bad(
    index,
    '$expected expected, got ${index >= values.length ? 'no value' : luaTypeName(values[index])}',
  );

  /// Any value, but not "no value".
  Object? any(int index) {
    if (index >= values.length) bad(index, 'value expected');
    return values[index];
  }

  String string(int index) {
    final value = this[index];
    if (value is String) return value;
    if (value is double) return formatNumber(value);
    wrongType(index, 'string');
  }

  String optString(int index, String fallback) =>
      isNone(index) ? fallback : string(index);

  double number(int index) {
    final value = this[index];
    if (value is double) return value;
    if (value is String) {
      final parsed = parseLuaNumber(value);
      if (parsed != null) return parsed;
    }
    wrongType(index, 'number');
  }

  double optNumber(int index, double fallback) =>
      isNone(index) ? fallback : number(index);

  /// An integer argument (fractions are truncated, like a C cast).
  int integer(int index) {
    final value = number(index);
    if (value.isNaN) return 0;
    if (value >= 9.2e18) return 9223372036854775807;
    if (value <= -9.2e18) return -9223372036854775808;
    return value.toInt();
  }

  int optInteger(int index, int fallback) =>
      isNone(index) ? fallback : integer(index);

  bool boolean(int index) => isTruthy(this[index]);

  LuaTable table(int index) {
    final value = this[index];
    if (value is LuaTable) return value;
    wrongType(index, 'table');
  }

  LuaFunction function(int index) {
    final value = this[index];
    if (value is LuaFunction) return value;
    wrongType(index, 'function');
  }
}

/// Adds the native function [name] to [table].
void define(LuaTable table, String name, NativeImpl impl) =>
    table.setString(name, NativeFunction(name, impl));

/// A list holding one value.
List<Object?> one(Object? value) => <Object?>[value];
