// JSON configuration (pure). Server-side values with defaults, like the Java mod's
// `AllConfigs`. The file is `config.json` in the plugin data folder: one JSON
// object, one top-level key per *section*. The foundation owns the `core`
// section ([CoreSettings]); every module defines its own @MappableClass
// settings class and reads it with [CreateConfig.section].
//
//   @MappableClass()
//   class KineticsSettings with KineticsSettingsMappable {
//     final double maxStress; ...
//     const KineticsSettings({this.maxStress = 1024});
//   }
//   final k = ctx.config.section('kinetics', KineticsSettingsMapper.fromMap,
//       (v) => v.toMap(), const KineticsSettings());
//
// Sections that are missing from the file (or have missing fields) take the
// defaults of the class; the plugin writes the merged result back.
import 'dart:convert';

import 'config_models.dart';

/// The loaded configuration.
final class CreateConfig {
  final Map<String, Object?> _root;
  final Map<String, Map<String, Object?>> _declared = {};
  final List<String> warnings = [];

  CreateConfig._(this._root);

  /// A configuration that has only defaults.
  CreateConfig.defaults() : _root = {};

  /// Parses [text] (the content of the file, or `null` if there is none). A file
  /// that is not a JSON object is ignored with a warning.
  factory CreateConfig.parse(String? text) {
    if (text == null || text.trim().isEmpty) return CreateConfig._({});
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return CreateConfig._(Map<String, Object?>.of(decoded));
      return CreateConfig._({})..warnings.add('config.json is not a JSON object, using the defaults');
    } on FormatException catch (e) {
      return CreateConfig._({})..warnings.add('config.json is not valid JSON (${e.message}), using the defaults');
    }
  }

  /// The section [name] decoded with [fromMap] (the generated `XMapper.fromMap`).
  /// An invalid section adds a warning and gives [defaults]. [toMap] is used to
  /// write the section back with all fields.
  T section<T extends Object>(
    String name,
    T Function(Map<String, dynamic> map) fromMap,
    Map<String, dynamic> Function(T value) toMap,
    T defaults,
  ) {
    T value = defaults;
    final raw = _root[name];
    if (raw is Map<String, dynamic>) {
      try {
        value = fromMap(raw);
      } catch (e) {
        warnings.add('config section `$name` is invalid ($e), using the defaults');
      }
    } else if (raw != null) {
      warnings.add('config section `$name` is not an object, using the defaults');
    }
    _declared[name] = Map<String, Object?>.of(toMap(value));
    return value;
  }

  /// The foundation's own section.
  late final CoreSettings core = section('core', CoreSettingsMapper.fromMap, (v) => v.toMap(), const CoreSettings());

  /// Whether the module [name] is enabled (`core.modules.<name>`, default true).
  bool moduleEnabled(String name) => core.modules[name] ?? true;

  /// The file content: what was loaded (unknown keys are kept) plus every section
  /// that was read, with all its fields.
  String toJsonString() {
    final merged = {..._root, ..._declared};
    return const JsonEncoder.withIndent('  ').convert(merged);
  }

  /// Whether [toJsonString] differs from the loaded content, so the plugin
  /// should write the file.
  bool get needsWrite => jsonEncode({..._root, ..._declared}) != jsonEncode(_root);
}
