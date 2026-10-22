// The server config model (pure): typed values with defaults, ranges and comments
// in a tree addressed by dotted path (`kinetics.encasedFan.fanPushDistance`).
// This is the Dart side of `ConfigBase` / `ConfigValue`; the values are declared
// in `create_configs.g.dart` from the manifest (`configDefaults`).
import '../../manifest/types_network.dart';

typedef ConfigListener = void Function(ConfigValue<Object> value);

/// One config value.
sealed class ConfigValue<T extends Object> {
  /// Full dotted path inside the config file (`kinetics.maxBeltLength`).
  final String path;
  final T defaultValue;
  final List<String> comment;
  final ConfigSide side;
  T _value;
  final List<ConfigListener> _listeners = [];

  ConfigValue(this.path, this.defaultValue, this.comment, this.side) : _value = defaultValue;

  /// The last path segment (the TOML key).
  String get name => path.substring(path.lastIndexOf('.') + 1);

  /// `ConfigValue.get()`.
  T get value => _value;

  /// `CValue.get()`.
  T get() => _value;

  bool get isDefault => _value == defaultValue;

  /// Whether [v] is acceptable (range, enum values).
  bool isValid(Object? v);

  /// Converts a JSON / typed value to `T`, `null` when it does not fit the type.
  T? coerce(Object? v);

  /// Sets the value (`CValue.set`). Returns false and keeps the old value when invalid.
  bool set(Object? v) {
    final c = coerce(v);
    if (c == null || !isValid(c)) return false;
    if (c == _value) return true;
    _value = c;
    for (final l in List.of(_listeners)) {
      l(this);
    }
    return true;
  }

  void reset() => set(defaultValue);

  /// Calls [listener] after the value changed.
  void onChange(ConfigListener listener) => _listeners.add(listener);

  /// The range text of the TOML comment, empty when unbounded.
  String get rangeComment => '';

  /// The TOML literal of [v].
  String toToml(T v);

  /// The JSON value of [v].
  Object toJson() => _value;

  @override
  String toString() => '$path = $_value';
}

final class ConfigBool extends ConfigValue<bool> {
  ConfigBool(super.path, super.defaultValue, super.comment, super.side);

  @override
  bool isValid(Object? v) => v is bool;

  @override
  bool? coerce(Object? v) {
    if (v is bool) return v;
    if (v is String) {
      if (v == 'true') return true;
      if (v == 'false') return false;
    }
    return null;
  }

  @override
  String toToml(bool v) => v ? 'true' : 'false';
}

final class ConfigInt extends ConfigValue<int> {
  final int min;
  final int max;

  ConfigInt(super.path, super.defaultValue, super.comment, super.side, {this.min = -2147483648, this.max = 2147483647});

  @override
  bool isValid(Object? v) => v is int && v >= min && v <= max;

  @override
  int? coerce(Object? v) {
    if (v is int) return v;
    if (v is double && v == v.truncateToDouble()) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  @override
  String get rangeComment => (min == -2147483648 && max == 2147483647) ? '' : 'Range: $min ~ $max';

  @override
  String toToml(int v) => '$v';
}

final class ConfigDouble extends ConfigValue<double> {
  final double min;
  final double max;

  ConfigDouble(super.path, super.defaultValue, super.comment, super.side,
      {this.min = -double.maxFinite, this.max = double.maxFinite});

  @override
  bool isValid(Object? v) => v is double && !v.isNaN && v >= min && v <= max;

  @override
  double? coerce(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  @override
  String get rangeComment => 'Range: ${_fmt(min)} ~ ${_fmt(max)}';

  static String _fmt(double d) => d.abs() > 1e30 ? (d < 0 ? '-3.4028234663852886E38' : '3.4028234663852886E38') : '$d';

  @override
  String toToml(double v) => tomlDouble(v);
}

/// The TOML literal of [v]: always a float literal, so a reader that types the
/// value (`ModConfigSpec.DoubleValue`) never sees an integer.
String tomlDouble(double v) {
  if (v.isNaN) return 'nan';
  if (v.isInfinite) return v < 0 ? '-inf' : 'inf';
  final s = '$v';
  return s.contains('.') || s.contains('e') || s.contains('E') ? s : '$s.0';
}

/// An enum value, stored by its Java constant name (`CREEPERS`).
final class ConfigEnum extends ConfigValue<String> {
  final List<String> allowed;
  final String? enumClass;

  ConfigEnum(super.path, super.defaultValue, super.comment, super.side, this.allowed, {this.enumClass});

  @override
  bool isValid(Object? v) => v is String && allowed.contains(v);

  @override
  String? coerce(Object? v) {
    if (v is! String) return null;
    for (final a in allowed) {
      if (a.toLowerCase() == v.toLowerCase()) return a;
    }
    return null;
  }

  /// The value as an element of [values] (a Dart enum with the same names, any case).
  E as<E extends Enum>(List<E> values) {
    final n = _value.toLowerCase().replaceAll('_', '');
    for (final e in values) {
      if (e.name.toLowerCase().replaceAll('_', '') == n) return e;
    }
    throw StateError('$_value is not a ${values.first.runtimeType}');
  }

  @override
  String get rangeComment => 'Allowed Values: ${allowed.join(', ')}';

  @override
  String toToml(String v) => '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

/// A free string value (stress configs are doubles; unused so far, kept for completeness).
final class ConfigString extends ConfigValue<String> {
  ConfigString(super.path, super.defaultValue, super.comment, super.side);

  @override
  bool isValid(Object? v) => v is String;

  @override
  String? coerce(Object? v) => v is String ? v : null;

  @override
  String toToml(String v) => '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
