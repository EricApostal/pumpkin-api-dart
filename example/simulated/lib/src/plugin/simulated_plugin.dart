// The Pumpkin plugin: reads the config, registers the content through Create's
// registry, installs the block entity store and the host, and ticks the content
// the host does not tick for us.
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.Simulated
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:convert';

import 'package:create/src/core/block_entity.dart';
import 'package:create/src/core/registry.dart';
import 'package:create/src/core/registry_apply.dart';
import 'package:create/src/core/worlds.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../config/sim_config.dart';
import '../config/sim_config_service.dart';
import '../host/pumpkin_host.dart';
import '../host/simulated_host.dart';
import '../index/sim_lift_providers.dart';
import '../index/sim_registry.dart';
import '../service/sim_services.dart';

/// The plugin of Simulated.
final class SimulatedPlugin extends Plugin {
  /// The config file inside the plugin's data folder.
  static const String configFile = 'config.json';

  final Worlds _worlds = Worlds();
  late final BlockEntityStore _blockEntities;
  final CreateRegistry _registry = CreateRegistry();

  @override
  PluginInfo get info => const PluginInfo(
    name: 'simulated',
    version: '0.1.0',
    description: 'Server side of the Simulated mod for Pumpkin: sub-level assemblies and their blocks.',
    permissions: [
      Permissions.fsWriteData,
      Permissions.registryItems,
      Permissions.registryBlocks,
      Permissions.registryBlockEntities,
      Permissions.registryEntities,
      Permissions.registryExtra,
    ],
  );

  @override
  Future<void> onLoad(Context context) async {
    final log = logger;
    final config = _loadConfig(context);
    SimConfigService.instance.load(config);

    final blockEntities = _blockEntities = BlockEntityStore(_worlds, log.child('blockentities'));

    // Phase 1: declare.
    SimRegistry.register(
      _registry,
      lookup: <T>(String worldId, (int, int, int) pos) {
        final entity = blockEntities.at(worldId, BlockPos(x: pos.$1, y: pos.$2, z: pos.$3));
        return entity is T ? entity as T : null;
      },
    );

    // Phase 2: apply.
    await applyRegistry(_registry, context, blockEntities, log);
    _worlds.install(context);
    blockEntities.install(context);

    registerSimLiftProviders();

    SimulatedHost.instance = PumpkinSimulatedHost(_worlds, blockEntities, log);

    log.info(
      'Simulated loaded: ${_registry.blocks.entries.length} blocks, '
      '${_registry.blockEntityTypes.entries.length} block entity types.',
    );
  }

  SimConfig _loadConfig(Context context) {
    try {
      if (!context.files.exists(configFile)) return SimConfig.defaults;
      final text = context.files.readAsString(configFile);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) return SimConfig.defaults;
      return SimConfig.fromMap(decoded);
    } on Object catch (e) {
      logger.warn('Could not read $configFile, using the defaults: $e');
      return SimConfig.defaults;
    }
  }

  @override
  void onUnload(Context context) {
    _blockEntities.flushAll();
    SimulatedHost.instance = null;
    SimServices.instance = SimServices();
  }
}
