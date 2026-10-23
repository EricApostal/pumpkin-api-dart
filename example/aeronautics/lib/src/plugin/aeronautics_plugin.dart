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

import 'package:create/create.dart'
    show
        KineticsBridge,
        installConsumerKinetics,
        installHostedModuleState,
        installHostedWorldTick;
import 'package:create/src/core/block_entity.dart';
import 'package:create/src/plugin/create_addon.dart' show createAddonNeoForgeDeclaration;
import 'package:create/src/core/config.dart';
import 'package:create/src/core/module.dart';
import 'package:create/src/core/registry_apply.dart';
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../aeronautics_plugin.dart';
import '../aeronautics_module.dart';
import '../index/aero_kinetics.dart' show aeroKineticDefs, aeroStressImpacts;
import '../config/aero_config.dart';
import '../config/aero_synced_config.dart';
import 'aeronautics_addon.dart';
import 'sable_physics_push.dart';

Object? _probeIdentity(Map<String, Object?> message) => message;

Map<String, Object?> _probeMap(Object? json) =>
    json is Map ? {for (final entry in json.entries) '${entry.key}': entry.value} : const {};

/// The plugin of Aeronautics.
final class AeronauticsPlugin extends Plugin {
  /// The config file inside the plugin's data folder.
  static const String configFile = 'config.json';

  late final BlockEntityStore _blockEntities;
  CreateCore? _core;

  /// Whether this component already pushed its physics data at server load.
  bool _physicsPushed = false;

  /// The caller half of Create's kinetic network (see `onLoad`).
  KineticsBridge? _kinetics;

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
      Permissions.registryRecipes,
      Permissions.registryExtra,
      Permissions.neoforge,
    ],
  );

  @override
  Future<void> onLoad(Context context) async {
    final log = logger;

    // TEMPORARY cross-component IPC probe: asks the sable component for a
    // sub-level lookup and prints the reply.
    const channel = IpcChannel<Map<String, Object?>>('sable.sublevels', _probeIdentity, _probeMap);
    channel.handle((sender, message) => null);
    context.command('sableping', (c) => c.runs((ctx) async {
      ctx.reply('ping: asking the sable component...');
      try {
        final listed = await channel.request('sable', {'op': 'list', 'world': 'minecraft:overworld'});
        ctx.reply('list reply: $listed');
        final containing = await channel.request('sable', {
          'op': 'containing',
          'world': 'minecraft:overworld',
          'pos': [0, -62, 0],
        });
        ctx.reply('containing reply: $containing');
        final assembled = await channel.request('sable', {
          'op': 'assemble',
          'world': 'minecraft:overworld',
          'anchor': [-4, -63, -4],
          'blocks': [
            [-4, -63, -4],
            [-3, -63, -4],
            [-4, -63, -3],
            [-3, -63, -3],
          ],
          'bounds': [-5, -64, -5, -2, -62, -2],
        });
        ctx.reply('assemble reply: $assembled');
      } on Object catch (error) {
        ctx.reply('ping failed: $error');
      }
    }));

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
    // The propeller bearings, the small propellers and the mounted potato cannon
    // are Create's kinetic block entities, and the bearings are contraption
    // actuators: their lifecycle runs in this component and reads Create's module
    // state, which only Create's own plugin would install — in its own component.
    installHostedModuleState(blockEntities: blockEntities, worlds: core.worlds, log: log);
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

    // The framework's per-world tick: the block entity store's pending writes and the
    // module handlers. Create's own plugin wires this; a component that hosts
    // Create's content must wire it too, or its block entities are published once
    // (at creation) and never update — measured on the propeller bearing, whose
    // host-side `Speed` stayed `0f` while it turned at 16 RPM in this component.
    installHostedWorldTick(
      context: context,
      worlds: core.worlds,
      // The plugin's own store: `core.blockEntities` is a second store the
      // component never installed (its `tickWorld` would flush nothing).
      blockEntities: blockEntities,
      savedData: core.savedData,
      moduleHandlers: core.worldTickHandlers,
      log: log,
    );

    module.onLoad(CreateContext(core, () => this.context, module.name));

    // The kinetic network is Create's plugin's, not this component's: register the
    // same rules (and stress values) with it and announce this component's
    // bearings as they load, so a Create shaft drives a propeller bearing
    // (`docs/kinetics-across-plugins.md`). When no Create plugin is loaded the
    // bridge stays disarmed and this component's own runtime propagates.
    final kinetics = _kinetics = installConsumerKinetics(context: context, log: log);
    for (final entry in aeroKineticDefs.entries) {
      kinetics.addRule(entry.key, entry.value, impact: aeroStressImpacts[entry.key]);
    }

    // Phase 4: the server is loaded, so the host's recipe manager and data pack manager exist.
    // The module enables the mod's data pack and merges the recipes of other components.
    context.listen(Events.serverLoad, (server, event) async {
      if (event.loadType != ServerLoadType.startup) return;
      try {
        await module.onServerLoaded(CreateRuntime(core, server, module.name));
      } on Object catch (e, s) {
        log.error('The aeronautics module failed in onServerLoaded', error: e, stackTrace: s);
      }
      // The physics data goes to the component that owns the sub-levels: this
      // component's `aeronautics:levitite` material and the
      // `#aeronautics:levitite` → `sable:floating_material` definition have to be
      // in the table the sub-level model reads, and that table is not here
      // (`sable` owns the containers). See [SablePhysicsPush].
      if (_physicsPushed) return;
      _physicsPushed = true;
      await _pushPhysicsData();
    });

    log.info(
      'Aeronautics loaded: ${core.registry.blocks.length} blocks, '
      '${core.registry.blockEntityTypes.length} block entity types, '
      '${core.registry.sounds.length} sound events, '
      '${core.registry.particles.length} particle types.',
    );
  }

  /// Pushes the pack's physics data to the component that owns the sub-levels,
  /// retrying on the following world ticks.
  ///
  /// The owner installs its operation channel when it starts, and the load order
  /// of two independent plugins is not fixed: a request that arrives first fails
  /// with no channel on the other side, and nothing would retry it. The
  /// definitions are only read when a sub-level ticks, so a few ticks of delay
  /// costs nothing, while losing the push costs levitite its lift entirely.
  ///
  /// The retry is a tick listener rather than an awaited `context.next`: the
  /// first attempt runs inside the `serverLoad` handler, and blocking that
  /// handler on a later tick would stall the load it is part of.
  Future<void> _pushPhysicsData() async {
    if (await _tryPushPhysicsData()) return;

    var attempts = 1;
    EventSubscription? subscription;
    subscription = context.listen(Events.worldTick, (server, event) async {
      if (attempts >= 100) {
        subscription?.cancel();
        logger.warn(
          'Aeronautics: gave up sending the physics data after $attempts attempts; '
          'levitite will not float on this server.',
        );
        return;
      }
      attempts++;
      if (await _tryPushPhysicsData()) subscription?.cancel();
    });
  }

  /// One attempt; whether the owner accepted the data.
  Future<bool> _tryPushPhysicsData() async {
    try {
      final reply = await SablePhysicsPush.send(log: logger);
      return reply != null && reply['ok'] == true;
    } on Object catch (e, s) {
      logger.error('Aeronautics could not send its physics data', error: e, stackTrace: s);
      return false;
    }
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
    _kinetics?.close();
    _blockEntities.flushAll();
    _core?.savedData.flushAll();
    _core?.worlds.clear();
    _core = null;
  }
}
