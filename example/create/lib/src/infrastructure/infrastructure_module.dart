// The `infrastructure` module: configs and their sync, the /create command tree, Catnip's config
// payloads and commands, world generation, the server speed sync and debug info.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/infra.dart';
import '../api/payloads.dart';
import '../core/module.dart';
import '../core/registry.dart';
import 'commands/command_parsing.dart';
import 'commands/create_commands.dart';
import 'config/config_service.dart';
import 'config/create_configs.dart';
import 'server_speed.dart';
import 'worldgen/create_worldgen.dart';

/// Provides [CreateConfigs] (`AllConfigs`), [ServerConfigService], [DebugInformation]; registers
/// `/create` (`/c`) and `/catnip`, the ores, and handles `catnip:set_config_values`.
final class InfrastructureModule extends CreateModule {
  final InfraCommandState _state = InfraCommandState();
  final ServerSpeedSync _speed = ServerSpeedSync();
  CreateWorldgen? _worldgen;
  ServerConfigService? _config;
  CreateContext? _ctx;

  @override
  String get name => 'infrastructure';

  @override
  void register(CreateRegistry registry) => registerInfrastructureCommands(registry, _state);

  @override
  void onLoad(CreateContext ctx) {
    final log = ctx.log;
    _ctx = ctx;
    final config = _config = ServerConfigService.load(ctx.config, ctx.host, log);
    final debug = DebugInfoRegistry();
    ctx.services.provide<CreateConfigs>(config.configs);
    ctx.services.provide<ServerConfigService>(config);
    ctx.services.provide<DebugInformation>(debug);

    _state
      ..services = ctx.services
      ..config = config
      ..worlds = ctx.worlds
      ..debug = debug
      ..log = log;

    _registerDebugInfo(debug, ctx, config.configs);

    // catnip:set_config_values (owners only, like ConfigHelper.CAN_CHANGE_CONFIGS).
    final bus = ctx.services.find<PayloadBus>();
    if (bus == null) {
      log.warn('No payload bus: config changes from the config screen and the server speed sync are off');
    } else {
      bus.onServerbound('catnip:set_config_values', (player, fields) => _setConfigValues(player, fields, config, log));
    }

    // ServerSpeedProvider.serverTick
    ctx.listen(Events.serverTickEnd, (server, event) {
      if (!_speed.tick(config.configs.server.tickrateSyncTimer.value)) return;
      final b = ctx.services.find<PayloadBus>();
      if (b == null) return;
      b.sendClientboundAll('create:server_speed', b.roster.players, const {});
    });

    // World generation.
    final worldgen = _worldgen = CreateWorldgen(config.configs, log);
    worldgen.register(ctx.host);
  }

  @override
  void onServerLoaded(CreateRuntime runtime) {
    final ctx = _ctx;
    if (ctx != null) _worldgen?.initSeeds(ctx.host, runtime.server);
    final config = _config;
    if (config != null && config.configs.serverTree.overridesJson().isNotEmpty) {
      // Clients that join get the configured values, not the defaults declared at load.
      config.pushToClients();
    }
  }

  @override
  void onUnload() {
    _config?.dispose();
  }

  void _registerDebugInfo(DebugInfoRegistry debug, CreateContext ctx, CreateConfigs configs) {
    final modVersion = ctx.config.core.modVersion;
    DebugInfoSection.builder('Create')
        .put('Mod Version', modVersion)
        .put('Server', 'Pumpkin plugin (Dart, dart2wasm)')
        .put('Modules', ctx.config.core.modules.entries.map((e) => '${e.key}=${e.value}').join(', '))
        .put('Changed Config Values', () {
          final changed = configs.serverTree.values.where((v) => !v.isDefault).map((v) => '${v.path} = ${v.value}').toList();
          return changed.isEmpty ? 'none' : changed.join('\n');
        })
        .build()
        .let(debug.registerServerInfo);
  }

  Future<void> _setConfigValues(Player player, Map<String, Object?> fields, ServerConfigService config, Logger log) async {
    // ConfigHelper.CAN_CHANGE_CONFIGS = Commands.LEVEL_OWNERS
    if (player.getPermissionLevel().index < PermissionLevel.four.index) {
      log.warn('Ignoring catnip:set_config_values from unprivileged player ${player.getName()}');
      return;
    }
    final modId = fields['modId'] as String? ?? '';
    final id = CatnipConfigId(modId, CatnipConfigSide.server);
    if (!config.hasServerConfig(id)) {
      log.warn('Ignoring catnip:set_config_values targeting unknown config $id');
      return;
    }
    final changes = fields['changes'];
    if (changes is! Map<Object?, Object?>) return;
    for (final e in changes.entries) {
      final components = (e.key as List<Object?>).cast<String>();
      final variant = e.value as PayloadVariant;
      final wrapped = wrapPayloadVariant(variant.variant, variant.value);
      if (wrapped == null) {
        log.warn('Ignoring config value update with an invalid value: ${variant.variant}');
        continue;
      }
      try {
        final error = config.setFromWrapped(id, CatnipConfigPath(components), wrapped);
        if (error != null) log.error('Ignoring config value update due to an invalid value [$id/${components.join('.')}]: $error');
      } on ArgumentParseException catch (e) {
        log.warn('Ignoring config value change for invalid path: ${e.message}');
      }
    }
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T v) f) => f(this);
}
