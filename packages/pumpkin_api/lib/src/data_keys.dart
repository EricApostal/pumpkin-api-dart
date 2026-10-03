/// Typed persistent data keys. This file has no dependency on the generated
/// bindings, so the codecs can be tested on the Dart VM; the extensions that
/// connect keys to players, items, worlds and so on live in
/// `data_keys_bindings.dart`.
///
/// ```dart
/// const kills = IntKey('kills', defaultValue: 0);
/// final data = PluginData('my_plugin');
///
/// final d = player.data(data);
/// d.update(kills, (old) => old + 1);
/// print(d.get(kills));
/// ```
library;

import 'dart:convert';

/// The minimal storage a [DataKey] needs: named primitive slots. The
/// persistent data of a player, item, world... is adapted to this in
/// `data_keys_bindings.dart`; [MemoryDataStore] is an in-memory version.
abstract interface class DataStore {
  /// Whether [name] has a value.
  bool has(String name);

  /// Deletes [name].
  void remove(String name);

  /// The string stored under [name], or `null` if missing or another type.
  String? readString(String name);

  /// Stores a string.
  void writeString(String name, String value);

  /// The integer stored under [name].
  int? readLong(String name);

  /// Stores a 64-bit integer.
  void writeLong(String name, int value);

  /// The boolean stored under [name].
  bool? readBool(String name);

  /// Stores a boolean.
  void writeBool(String name, bool value);

  /// The number stored under [name].
  double? readDouble(String name);

  /// Stores a 64-bit float.
  void writeDouble(String name, double value);
}

/// A [DataStore] that keeps everything in a map. Handy for tests.
final class MemoryDataStore implements DataStore {
  final Map<String, Object> _values = {};

  @override
  bool has(String name) => _values.containsKey(name);
  @override
  void remove(String name) => _values.remove(name);
  @override
  String? readString(String name) => _values[name] is String ? _values[name] as String : null;
  @override
  void writeString(String name, String value) => _values[name] = value;
  @override
  int? readLong(String name) => _values[name] is int ? _values[name] as int : null;
  @override
  void writeLong(String name, int value) => _values[name] = value;
  @override
  bool? readBool(String name) => _values[name] is bool ? _values[name] as bool : null;
  @override
  void writeBool(String name, bool value) => _values[name] = value;
  @override
  double? readDouble(String name) => _values[name] is double ? _values[name] as double : null;
  @override
  void writeDouble(String name, double value) => _values[name] = value;
}

/// How a value of type [T] is stored in a [DataStore]. Use the built-in
/// codecs through the [DataKey] constructors, or [DataCodec.string] to store
/// anything as text.
abstract class DataCodec<T> {
  const DataCodec();

  /// Reads the value stored under [name], or `null` when missing or invalid.
  T? read(DataStore store, String name);

  /// Stores [value] under [name].
  void write(DataStore store, String name, T value);

  /// A codec that stores values as strings through [encode] and [decode].
  /// [decode] may throw for malformed text; the value then reads as missing.
  const factory DataCodec.string({
    required String Function(T value) encode,
    required T Function(String text) decode,
  }) = _StringCodec<T>;
}

final class _StringCodec<T> extends DataCodec<T> {
  final String Function(T) encode;
  final T Function(String) decode;
  const _StringCodec({required this.encode, required this.decode});

  @override
  T? read(DataStore store, String name) {
    final text = store.readString(name);
    if (text == null) return null;
    try {
      return decode(text);
    } catch (_) {
      return null;
    }
  }

  @override
  void write(DataStore store, String name, T value) =>
      store.writeString(name, encode(value));
}

final class _IntCodec extends DataCodec<int> {
  const _IntCodec();
  @override
  int? read(DataStore s, String n) => s.readLong(n);
  @override
  void write(DataStore s, String n, int v) => s.writeLong(n, v);
}

final class _StringValueCodec extends DataCodec<String> {
  const _StringValueCodec();
  @override
  String? read(DataStore s, String n) => s.readString(n);
  @override
  void write(DataStore s, String n, String v) => s.writeString(n, v);
}

final class _BoolCodec extends DataCodec<bool> {
  const _BoolCodec();
  @override
  bool? read(DataStore s, String n) => s.readBool(n);
  @override
  void write(DataStore s, String n, bool v) => s.writeBool(n, v);
}

final class _DoubleCodec extends DataCodec<double> {
  const _DoubleCodec();
  @override
  double? read(DataStore s, String n) => s.readDouble(n);
  @override
  void write(DataStore s, String n, double v) => s.writeDouble(n, v);
}

String _encodeStringList(List<String> v) => jsonEncode(v);
List<String> _decodeStringList(String t) =>
    [for (final e in jsonDecode(t) as List) e as String];

/// A named, typed slot in persistent data, with an optional default.
///
/// Keys are cheap constants; declare them once and share them:
///
/// ```dart
/// const kills = IntKey('kills', defaultValue: 0);
/// const nick = StringKey('nick');
/// final home = DataKey<List<double>>.custom('home',
///   encode: _encode, decode: _decode);
/// ```
///
/// Constructors exist for `int`, `String`, `bool`, `double` and
/// `List<String>`; the type argument picks the codec, so `DataKey<int>(...)`
/// stores a 64-bit integer. Anything else needs [DataKey.custom].
final class DataKey<T> {
  /// The key name inside the plugin namespace.
  final String name;

  /// Returned by `get` when nothing is stored; `null` means "no default".
  final T? defaultValue;

  /// How values are stored.
  final DataCodec<T> codec;

  /// A key of one of the built-in types ([int], [String], [bool], [double]
  /// or `List<String>`). Throws [ArgumentError] for other types; use
  /// [DataKey.custom] for those.
  factory DataKey(String name, {T? defaultValue}) {
    final DataCodec<Object?> codec = switch (T) {
      const (int) => const _IntCodec(),
      const (String) => const _StringValueCodec(),
      const (bool) => const _BoolCodec(),
      const (double) => const _DoubleCodec(),
      const (List<String>) => const DataCodec<List<String>>.string(
        encode: _encodeStringList,
        decode: _decodeStringList,
      ),
      _ => throw ArgumentError('No built-in codec for $T, use DataKey.custom'),
    };
    return DataKey._(name, defaultValue, codec as DataCodec<T>);
  }

  const DataKey._(this.name, this.defaultValue, this.codec);

  /// A key stored through [encode] and [decode], as a string. Suitable for
  /// JSON: `encode: (v) => jsonEncode(v.toJson())`. Not `const` (it builds a codec from
  /// closures); for a constant key use [DataKey.withCodec] with a `const`
  /// [DataCodec.string].
  DataKey.custom(
    this.name, {
    required String Function(T value) encode,
    required T Function(String text) decode,
    this.defaultValue,
  }) : codec = _StringCodec<T>(encode: encode, decode: decode);

  /// A key stored with an arbitrary [codec].
  const DataKey.withCodec(this.name, this.codec, {this.defaultValue});

  /// Reads this key from [store]: the stored value, or [defaultValue].
  T? read(DataStore store) => codec.read(store, name) ?? defaultValue;

  /// Writes [value] to [store].
  void write(DataStore store, T value) => codec.write(store, name, value);
}

/// Typed access to one [DataStore], created by `player.data(...)` and
/// friends. Plain-data wrapper, valid as long as the object it came from.
final class TypedData {
  /// The underlying store.
  final DataStore store;

  /// Wraps [store].
  TypedData(this.store);

  /// The value of [key], or its default, or `null`.
  T? getOrNull<T>(DataKey<T> key) => key.read(store);

  /// The value of [key]. Throws [StateError] if nothing is stored and the key
  /// has no default; use [getOrNull] for keys without defaults.
  T get<T>(DataKey<T> key) {
    final v = key.read(store);
    if (v == null && null is! T) {
      throw StateError('Data key "${key.name}" has no value and no default');
    }
    return v as T;
  }

  /// Stores [value] under [key].
  void set<T>(DataKey<T> key, T value) => key.write(store, value);

  /// Replaces the value of [key] with `change(current)`, where `current` is
  /// the stored value or the default. Returns the new value.
  ///
  /// ```dart
  /// data.update(kills, (old) => old + 1);
  /// ```
  T update<T>(DataKey<T> key, T Function(T current) change) {
    final next = change(get(key));
    key.write(store, next);
    return next;
  }

  /// Whether a value is stored for [key] (ignores the default).
  bool has(DataKey<Object?> key) => store.has(key.name);

  /// Deletes the stored value of [key].
  void remove(DataKey<Object?> key) => store.remove(key.name);
}

/// A plugin's persistent data namespace. Create one per plugin and pass it to
/// `data(...)` on a player, item, world...
///
/// ```dart
/// const ns = PluginData('my_plugin');
/// player.data(ns).set(kills, 5);
/// ```
final class PluginData {
  /// The namespace, normally the plugin name.
  final String namespace;

  /// A namespace called [namespace].
  const PluginData(this.namespace);
}

/// A `const` key holding an `int` (stored as a 64-bit integer).
///
/// ```dart
/// const kills = IntKey('kills', defaultValue: 0);
/// ```
final class IntKey extends DataKey<int> {
  /// A key called [name].
  const IntKey(String name, {int? defaultValue})
    : super._(name, defaultValue, const _IntCodec());
}

/// A `const` key holding a `String`.
final class StringKey extends DataKey<String> {
  /// A key called [name].
  const StringKey(String name, {String? defaultValue})
    : super._(name, defaultValue, const _StringValueCodec());
}

/// A `const` key holding a `bool`.
final class BoolKey extends DataKey<bool> {
  /// A key called [name].
  const BoolKey(String name, {bool? defaultValue})
    : super._(name, defaultValue, const _BoolCodec());
}

/// A `const` key holding a `double`.
final class DoubleKey extends DataKey<double> {
  /// A key called [name].
  const DoubleKey(String name, {double? defaultValue})
    : super._(name, defaultValue, const _DoubleCodec());
}

/// A `const` key holding a `List<String>`, stored as JSON text.
final class StringListKey extends DataKey<List<String>> {
  /// A key called [name].
  const StringListKey(String name, {List<String>? defaultValue})
    : super._(
        name,
        defaultValue,
        const DataCodec<List<String>>.string(
          encode: _encodeStringList,
          decode: _decodeStringList,
        ),
      );
}
