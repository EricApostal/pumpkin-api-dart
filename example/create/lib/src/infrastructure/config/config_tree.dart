// The values of one config file as a tree (pure): lookup by path, loading and
// saving as nested JSON maps, TOML rendering in the layout of NeoForge's
// `ModConfigSpec` (what `create-server.toml` looks like), and change tracking.
import 'config_values.dart';

/// The values of one file (`create-server.toml`).
final class ConfigTree {
  /// The file name as NeoForge writes it.
  final String fileName;
  final Map<String, ConfigValue<Object>> _values = {};
  final List<String> _order = [];
  final Map<String, List<String>> _groupComments = {};

  ConfigTree(this.fileName);

  /// Adds [value]; throws on a duplicate path.
  V add<V extends ConfigValue<Object>>(V value) {
    if (_values.containsKey(value.path)) throw StateError('Duplicate config path ${value.path}');
    _values[value.path] = value;
    _order.add(value.path);
    return value;
  }

  /// A comment for the table at [groupPath] (`kinetics.encasedFan`).
  void groupComment(String groupPath, List<String> comment) => _groupComments[groupPath] = comment;

  Iterable<ConfigValue<Object>> get values => _order.map((p) => _values[p]!);

  ConfigValue<Object>? operator [](String path) => _values[path];

  int get length => _values.length;

  /// Sets [path] from [raw]; returns an error text or `null`.
  String? setPath(String path, Object? raw) {
    final v = _values[path];
    if (v == null) return 'Unknown config value $path';
    if (!v.set(raw)) return 'Invalid value for $path: $raw';
    return null;
  }

  /// Applies nested JSON overrides (`{"kinetics": {"maxBeltLength": 30}}`). Unknown keys and invalid
  /// values are reported in [warnings] and ignored.
  void load(Map<String, dynamic> json, {List<String>? warnings}) {
    void walk(String prefix, Map<String, dynamic> map) {
      for (final e in map.entries) {
        final path = prefix.isEmpty ? e.key : '$prefix.${e.key}';
        final v = e.value;
        if (v is Map<String, dynamic>) {
          walk(path, v);
        } else {
          final err = setPath(path, v);
          if (err != null) warnings?.add('config: $err (ignored)');
        }
      }
    }

    walk('', json);
  }

  /// The values as nested JSON, all values, in declaration order.
  Map<String, dynamic> toJson() {
    final root = <String, dynamic>{};
    for (final v in values) {
      final parts = v.path.split('.');
      var cur = root;
      for (var i = 0; i < parts.length - 1; i++) {
        cur = cur.putIfAbsent(parts[i], () => <String, dynamic>{}) as Map<String, dynamic>;
      }
      cur[parts.last] = v.toJson();
    }
    return root;
  }

  /// Only the values that differ from their defaults, as nested JSON.
  Map<String, dynamic> overridesJson() {
    final root = <String, dynamic>{};
    for (final v in values) {
      if (v.isDefault) continue;
      final parts = v.path.split('.');
      var cur = root;
      for (var i = 0; i < parts.length - 1; i++) {
        cur = cur.putIfAbsent(parts[i], () => <String, dynamic>{}) as Map<String, dynamic>;
      }
      cur[parts.last] = v.toJson();
    }
    return root;
  }

  /// Renders the file like NeoForge's toml writer: one `[table]` per group (parents first), values
  /// with their comments and range, in declaration order inside each table.
  String toToml() {
    final tables = <String, List<ConfigValue<Object>>>{'': []};
    void ensure(String table) {
      if (tables.containsKey(table)) return;
      final dot = table.lastIndexOf('.');
      ensure(dot < 0 ? '' : table.substring(0, dot));
      tables[table] = [];
    }

    for (final v in values) {
      final dot = v.path.lastIndexOf('.');
      final table = dot < 0 ? '' : v.path.substring(0, dot);
      ensure(table);
      tables[table]!.add(v);
    }
    final out = StringBuffer();
    for (final e in tables.entries) {
      if (e.value.isEmpty) continue;
      final depth = e.key.isEmpty ? 0 : e.key.split('.').length;
      if (e.key.isNotEmpty) {
        if (out.isNotEmpty) out.writeln();
        for (final line in _groupComments[e.key] ?? const <String>[]) {
          out.writeln('#$line');
        }
        out.writeln('[${e.key.split('.').map(_key).join('.')}]');
      }
      final indent = '\t' * depth;
      for (final v in e.value) {
        for (final line in v.comment) {
          out.writeln('$indent#$line');
        }
        if (v.rangeComment.isNotEmpty) out.writeln('$indent#${v.rangeComment}');
        out.writeln('$indent${_key(v.name)} = ${v.toToml(v.value)}');
      }
    }
    return out.toString();
  }

  static final RegExp _bare = RegExp(r'^[A-Za-z0-9_-]+$');

  static String _key(String k) => _bare.hasMatch(k) ? k : '"$k"';
}
