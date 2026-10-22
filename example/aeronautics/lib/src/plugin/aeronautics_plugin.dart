// The Pumpkin plugin: reads the config, registers the content through Create's
// registry, installs the block entity store and the balloon save data, and runs
// the module through its phases.
//
// Host: this file uses `pumpkin_api`.
//
// Java: `dev.eriksonn.aeronautics.Aeronautics`
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:convert';

import 'package:create/src/core/block_entity.dart';
import 'package:create/src/plugin/create_addon.dart' show createAddonNeoForgeDeclaration;
import 'package:create/src/core/config.dart';
import 'package:create/src/core/module.dart';
import 'package:create/src/core/registry_apply.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../aeronautics_plugin.dart';
import '../aeronautics_module.dart';
import '../config/aero_config.dart';
import '../config/aero_synced_config.dart';
import 'aeronautics_addon.dart';

/// The plugin of Aeronautics.
final class AeronauticsPlugin extends Plugin {
  /// The config file inside the plugin's data folder.
  static const String configFile = 'config.json';

  late final BlockEntityStore _blockEntities;
  CreateCore? _core;

  @override
  PluginInfo get info => const PluginInfo(
    name: 'aeronautics',
    version: '0.1.0',
    description: 'Server side of the Aeronautics mod for Pumpkin: propellers, hot-air balloons and envelopes.',
    permissions: [
      Permissions.fsWriteData,
      Permissions.registryItems,
      Permissions.registryBlocks,
      Permissions.registryBlockEntities,
      Permissions.registryComponents,
      Permissions.registryEntities,
      Permissions.registryFluids,
      Permissions.registryExtra,
      Permissions.neoforge,
    ],
  );

  @override
  Future<void> onLoad(Context context) async {
    final log = logger;

    // The physics scalars and the per-block limits of `AeroConfig`.
    _loadConfig(context);

    final core = _core = CreateCore(CreateConfig.parse(null), log);
    // The world adapters resolve a world by id through this table once the
    // handle of the callback that created them is gone.
    AeronauticsHooks.worlds = core.worlds;
    // The store resolves worlds through the table the core installs below. A
    // second, never-installed `Worlds` used to be handed to it, so every
    // `CreateBlockEntity.world` was `null`.
    final blockEntities = _blockEntities = BlockEntityStore(core.worlds, log.child('blockentities'));
    final module = AeronauticsModule();

    // Phase 1: declare.
    module.register(core.registry);

    // Phase 2: apply to the host, then the framework and the module.
    core.ids = await applyRegistry(core.registry, context, blockEntities, log);
    core.worlds.install(context);
    blockEntities.install(context);
    core.savedData.install(context, saveIntervalTicks: 20);

    // Phase 3: declare the mod and its payload channels, so a client that has
    // Aeronautics installed completes the NeoForge negotiation. This goes
    // through Create's generic addon hook: Create never names Aeronautics. The
    // mod's SYNCED server config goes with the declaration: the client parses it
    // into the mod's `ModConfigSpec` and reads it from `BlockStressValues
    // .getImpact` while building a kinetic block's tooltip, so a client that
    // never received it crashes on the first hover.
    core.registry.neoForgeConfigFile(
      aeroSyncedConfigFile,
      utf8.encode(aeroSyncedToml(AeroConfig.server)),
    );
    context.declareNeoForge(createAddonNeoForgeDeclaration(const AeronauticsAddon(), registry: core.registry));

    module.onLoad(CreateContext(core, () => this.context, module.name));

    log.info(
      'Aeronautics loaded: ${core.registry.blocks.length} blocks, '
      '${core.registry.blockEntityTypes.length} block entity types.',
    );
  }

  /// Reads `config.json` into [AeroConfig.server]; a missing or broken file
  /// keeps the Java defaults.
  void _loadConfig(Context context) {
    AeroConfig.reset();
    try {
      if (!context.files.exists(configFile)) return;
      final decoded = jsonDecode(context.files.readAsString(configFile));
      if (decoded is! Map<String, Object?>) return;

      final physics = decoded['physics'];
      if (physics is Map) {
        final p = AeroConfig.server.physics;
        double read(String key, double fallback) => (physics[key] as num?)?.toDouble() ?? fallback;
        p.propellerBearingThrust = read('propellerBearingThrust', p.propellerBearingThrust);
        p.propellerBearingAirflowMult = read('propellerBearingAirflow', p.propellerBearingAirflowMult);
        p.woodenPropellerThrust = read('woodenPropellerThrust', p.woodenPropellerThrust);
        p.woodenPropellerAirflow = read('woodenPropellerAirflow', p.woodenPropellerAirflow);
        p.andesitePropellerThrust = read('andesitePropellerThrust', p.andesitePropellerThrust);
        p.andesitePropellerAirflow = read('andesitePropellerAirflow', p.andesitePropellerAirflow);
        p.smartPropellerThrust = read('smartPropellerThrust', p.smartPropellerThrust);
        p.smartPropellerAirflow = read('smartPropellerAirflow', p.smartPropellerAirflow);
        p.hotAirStrength = read('hotAirStrength', p.hotAirStrength);
        p.steamStrength = read('steamStrength', p.steamStrength);
      }

      final blocks = decoded['blocks'];
      if (blocks is Map) {
        final b = AeroConfig.server.blocks;
        b.breakBlocksOnCrystallize = (blocks['break_blocks_on_levitite_crystallize'] as bool?) ?? b.breakBlocksOnCrystallize;
        b.hotAirBurnerMaxHotAir = (blocks['hot_air_burner_max'] as num?)?.toInt() ?? b.hotAirBurnerMaxHotAir;
        b.hotAirBurnerMaxRange = (blocks['hot_air_burner_max_range'] as num?)?.toInt() ?? b.hotAirBurnerMaxRange;
        b.steamVentMaxHotAir = (blocks['steam_vent_hot_air_amount'] as num?)?.toInt() ?? b.steamVentMaxHotAir;
        b.steamVentMaxRange = (blocks['steam_vent_max_range'] as num?)?.toInt() ?? b.steamVentMaxRange;
      }
    } on Object catch (e) {
      logger.warn('Could not read $configFile, using the defaults: $e');
    }
  }

  @override
  Future<void> onUnload(Context context) async {
    _blockEntities.flushAll();
    _core?.savedData.flushAll();
    _core?.worlds.clear();
    _core = null;
  }
}
