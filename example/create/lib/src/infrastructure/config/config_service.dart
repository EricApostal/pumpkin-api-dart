// Host side of the config: loading from / saving to the plugin's `config.json`
// (section `create_config`), pushing the synced `create-server.toml` to NeoForge
// clients and applying changes made through `/create config` or the Catnip
// config screen.
import 'dart:async';
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/config.dart';
import '../commands/command_parsing.dart';
import 'create_configs.dart';

/// Holds the values of the `create_config` section live, so the plugin config file always writes
/// the current values.
final class _LiveSection {
  final CreateConfigs configs;

  _LiveSection(this.configs);
}

/// Loads, saves and syncs [CreateConfigs].
final class ServerConfigService {
  static const String sectionName = 'create_config';

  final CreateConfigs configs;
  final CreateConfig _file;
  final Logger log;
  final Context _host;
  Timer? _pending;

  ServerConfigService._(this.configs, this._file, this.log, this._host);

  /// Reads the `create_config` section of the plugin config into [configs] (invalid values are
  /// reported and replaced by the defaults) and registers the section so the file is written back
  /// with every value.
  factory ServerConfigService.load(CreateConfig file, Context host, Logger log) {
    final configs = CreateConfigs();
    final warnings = <String>[];
    final svc = ServerConfigService._(configs, file, log, host);
    file.section<_LiveSection>(
      sectionName,
      (m) {
        configs.load(m, warnings: warnings);
        return _LiveSection(configs);
      },
      (v) => v.configs.toJson(),
      _LiveSection(configs),
    );
    for (final w in warnings) {
      log.warn(w);
    }
    return svc;
  }

  /// Rewrites `config.json` with the current values.
  void save() {
    // `section` refreshes the snapshot the file is written from.
    _file.section<_LiveSection>(sectionName, (m) => _LiveSection(configs), (v) => v.configs.toJson(), _LiveSection(configs));
    try {
      _host.files.writeAsString('config.json', _file.toJsonString());
    } on FileException catch (e) {
      log.warn('Could not save config.json: $e');
    }
  }

  /// Sends the current `create-server.toml` to the connected NeoForge clients (what NeoForge's
  /// config sync does when a synced config reloads).
  void pushToClients() {
    try {
      _host.updateNeoForgeConfigFile(CreateConfigs.modId, CreateConfigs.serverFile, utf8.encode(configs.serverToml()));
    } on HostException catch (e) {
      log.debug(() => 'Config push skipped: ${e.message}');
    }
  }

  /// Schedules [save] and [pushToClients] for the end of the tick (several changes in a row cost
  /// one write).
  void changed() {
    _pending ??= Timer(Duration.zero, () {
      _pending = null;
      save();
      pushToClients();
    });
  }

  /// `ConfigHelper.trySetValue`: sets the value of [id]/[path] from [text]. Client configs belong
  /// to the client and are refused here. Returns an error text or `null`.
  String? setFromText(CatnipConfigId id, CatnipConfigPath path, String text) {
    final value = _find(id, path);
    if (value is String) return value;
    final v = value as ConfigValue<Object>;
    final parsed = parseConfigText(v.defaultValue, text, enumValues: v is ConfigEnum ? v.allowed : null);
    if (parsed == null) return 'Invalid value';
    if (!v.set(parsed)) return 'Invalid value';
    changed();
    return null;
  }

  /// `ServerboundSetConfigValuesPacket.trySetValue` for one wrapped value.
  String? setFromWrapped(CatnipConfigId id, CatnipConfigPath path, WrappedConfigValue wrapped) {
    final value = _find(id, path);
    if (value is String) return value;
    final v = value as ConfigValue<Object>;
    final Object? raw = switch (wrapped) {
      WrappedBool(:final value) => value,
      WrappedInt(:final value) => value,
      WrappedFloat(:final value) => value,
      WrappedDouble(:final value) => value,
      WrappedString(:final value) => value,
      WrappedEnum(:final ordinal) => v is ConfigEnum && ordinal >= 0 && ordinal < v.allowed.length ? v.allowed[ordinal] : null,
    };
    if (raw == null) return 'Ordinal out of range or type mismatch: $wrapped';
    final typeOk = switch (v) {
      ConfigBool() => raw is bool,
      ConfigInt() => raw is int,
      ConfigDouble() => raw is double,
      ConfigEnum() => wrapped is WrappedEnum,
      ConfigString() => raw is String,
    };
    if (!typeOk) return 'Type mismatch: $wrapped is not ${v.defaultValue.runtimeType}';
    if (!v.set(raw)) return 'Invalid value';
    changed();
    return null;
  }

  /// The value, or an error text.
  Object _find(CatnipConfigId id, CatnipConfigPath path) {
    if (id.modId != CreateConfigs.modId) return "Couldn't find config $id";
    final tree = switch (id.side) {
      CatnipConfigSide.server => configs.serverTree,
      CatnipConfigSide.common => configs.commonTree,
      CatnipConfigSide.client => null,
    };
    if (tree == null) return "Couldn't find config $id";
    final v = tree[path.dotted];
    if (v == null) return "Couldn't find config value ${path.dotted}";
    return v;
  }

  /// Whether the server has the config [id] (client configs live on the client).
  bool hasServerConfig(CatnipConfigId id) =>
      id.modId == CreateConfigs.modId && (id.side == CatnipConfigSide.server || id.side == CatnipConfigSide.common);

  void dispose() {
    _pending?.cancel();
    _pending = null;
  }
}
