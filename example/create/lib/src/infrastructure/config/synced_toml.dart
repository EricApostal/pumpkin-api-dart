// The body of a synced server config (`neoforge:config_file`): a TOML document
// with one `[table]` per group and the values indented with a tab, the layout
// NeoForge's `ModConfigSpec` writer produces for a mod's `<modid>-synced.toml`.
//
// The host sends the file to a NeoForge client with the handshake, and the
// client parses it into the mod's `ModConfigSpec`: from then on the mod's
// `ConfigValue.get()` reads *this* body, and a path that is missing here falls
// back to the client's own default (`ConfigValue.getRaw` ->
// `Config.getOrElse(path, defaultSupplier)`). Before the file arrives the
// client's config is not loaded at all and every read throws
// `IllegalStateException: Cannot get config value before config is loaded`.
//
// Pure: no host imports.
import 'config_values.dart' show tomlDouble;

/// Builds a TOML document table by table.
final class SyncedToml {
  final StringBuffer _out = StringBuffer();

  /// Opens the table [path] (`kinetics.stressValues.v2.impact`). The first table
  /// of the document gets no leading blank line.
  void table(String path) {
    if (_out.isNotEmpty) _out.writeln();
    _out.writeln('[${path.split('.').map(_tomlKey).join('.')}]');
  }

  /// Writes `key = value` into the open table. A `null` value writes nothing, so
  /// a setting the port does not model stays the client's own default.
  void value(String key, Object? value) {
    if (value == null) return;
    _out.writeln('\t${_tomlKey(key)} = ${_tomlLiteral(value)}');
  }

  /// Whether nothing has been written (an empty document is a valid body: the
  /// client then uses all of its defaults).
  bool get isEmpty => _out.isEmpty;

  @override
  String toString() => _out.toString();
}

/// The TOML literal of a config value: a bool, an int or a double.
String _tomlLiteral(Object value) => switch (value) {
  bool v => v ? 'true' : 'false',
  int v => '$v',
  double v => tomlDouble(v),
  _ => throw ArgumentError.value(value, 'value', 'a config value is a bool, an int or a double'),
};

final RegExp _bareKey = RegExp(r'^[A-Za-z0-9_-]+$');

/// A TOML key: bare when it can be, quoted otherwise (Simulated's
/// `"Primary Disassembly"` is a Java config key with a space in it).
String _tomlKey(String key) =>
    _bareKey.hasMatch(key) ? key : '"${key.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
