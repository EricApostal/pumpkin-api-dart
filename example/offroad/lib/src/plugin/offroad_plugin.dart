// The Pumpkin plugin of Offroad: reads the config, registers the content
// through Create's registry, installs the block entity store and runs the
// module, then declares the mod and its payload channel.
//
// Offroad's content is slice S14 of `docs/aero-port-inventory.md`. Create names
// no Offroad symbol: `OffroadAddon` implements its generic `CreateAddon`, and
// the content is registered into Create's `CreateRegistry` like any module.
//
// Host: this file uses `pumpkin_api`.
//
// Java: `dev.ryanhcode.offroad.Offroad`
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:convert';

import 'package:create/create.dart';
import 'package:create/src/core/registry_apply.dart' show applyRegistry;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../config/offroad_config.dart';
import '../config/offroad_synced_config.dart';
import '../content/blocks/borehead_bearing/borehead_bearing_block.dart'
    show boreheadBearingKey, boreheadBearingKineticDef;
import '../content/blocks/rock_cutting_wheel/rock_cutting_wheel_block.dart'
    show rockCuttingWheelKey, rockCuttingWheelKineticDef;
import '../content/blocks/wheel_mount/wheel_mount_block.dart'
    show wheelMountKey, wheelMountKineticDef;
import '../host/offroad_hooks.dart';
import '../offroad_module.dart';
import 'offroad_addon.dart';

/// The plugin of Offroad.
final class OffroadPlugin extends Plugin {
  /// The config file inside the plugin's data folder.
  static const String configFile = 'config.json';

  late final BlockEntityStore _blockEntities;
  CreateCore? _core;

  /// The caller half of Create's kinetic network (see `onLoad`).
  KineticsBridge? _kinetics;

  @override
  PluginInfo get info => const PluginInfo(
    name: 'offroad',
    version: '0.1.0',
    description: 'Server side of Offroad for Pumpkin: borehead bearings, wheel mounts and tires.',
    permissions: [
      Permissions.fsWriteData,
      Permissions.registryItems,
      Permissions.registryBlocks,
      Permissions.registryBlockEntities,
      Permissions.registryEntities,
      Permissions.registryExtra,
      Permissions.registryComponents,
      Permissions.neoforge,
    ],
  );

  @override
  Future<void> onLoad(Context context) async {
    final log = logger;
    _loadConfig(context);

    final core = _core = CreateCore(CreateConfig.parse(null), log);
    // The per-world adapters resolve a world by id through this table once the
    // handle of the callback that created them is gone.
    OffroadHooks.worlds = core.worlds;
    // The store resolves worlds through the table the core installs below. A
    // second, never-installed `Worlds` used to be handed to it, so every
    // `CreateBlockEntity.world` was `null`.
    final blockEntities = _blockEntities = BlockEntityStore(core.worlds, log.child('blockentities'));
    // The wheel mount is a Create kinetic block entity and the borehead bearing a
    // contraption actuator: their lifecycle runs in this component and reads
    // Create's module state, which only Create's own plugin would install — in
    // its own component.
    installHostedModuleState(blockEntities: blockEntities, worlds: core.worlds, log: log);
    final module = OffroadModule();

    // Phase 1: declare.
    module.register(core.registry);

    // Phase 2: apply to the host, then the framework and the module.
    core.ids = await applyRegistry(core.registry, context, blockEntities, log);
    core.worlds.install(context);
    blockEntities.install(context);
    core.savedData.install(context, saveIntervalTicks: 20);

    // The framework's per-world tick (the store's pending writes and the module
    // handlers): without it this component's block entities are published once, at
    // creation, and never update.
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

    // The kinetic network is Create's plugin's, not this component's: the same
    // rules (and stress impacts) are registered with it, and this component's
    // blocks are announced as they load, so a Create shaft drives the borehead
    // bearing and the wheel mount (`docs/kinetics-across-plugins.md`). When no
    // Create plugin is loaded the bridge stays disarmed and this component's own
    // runtime propagates.
    final kinetics = _kinetics = installConsumerKinetics(context: context, log: log);
    kinetics
      ..addRule(boreheadBearingKey, boreheadBearingKineticDef, impact: OffroadConfig.boreheadBearingImpact)
      ..addRule(wheelMountKey, wheelMountKineticDef, impact: OffroadConfig.wheelMountImpact)
      ..addRule(rockCuttingWheelKey, rockCuttingWheelKineticDef);

    // Phase 3: declare the mod and its payload channel, so a client that has
    // Offroad installed completes the NeoForge negotiation instead of being
    // refused. The mod's SYNCED server config goes with the declaration: the
    // client parses it into the mod's `ModConfigSpec`, and Create's `KineticStats`
    // reads it through `BlockStressValues.getImpact` (Offroad's borehead bearing
    // is an `IRotate`), so a client the server never sent it to crashes on the
    // first hover of that item.
    core.registry.neoForgeConfigFile(
      offroadSyncedConfigFile,
      utf8.encode(offroadSyncedToml(OffroadConfig.server)),
    );
    context.declareNeoForge(createAddonNeoForgeDeclaration(const OffroadAddon(), registry: core.registry));

    log.info(
      'Offroad loaded: ${core.registry.blocks.length} blocks, '
      '${core.registry.blockEntityTypes.length} block entity types.',
    );
  }

  /// Reads `config.json` into [OffroadConfig.server]; a missing or broken file
  /// keeps the Java defaults.
  void _loadConfig(Context context) {
    OffroadConfig.reset();
    try {
      if (!context.files.exists(configFile)) return;
      final decoded = jsonDecode(context.files.readAsString(configFile));
      if (decoded is! Map<String, Object?>) return;
      OffroadConfig.server = OffroadServerConfig.fromMap(decoded);
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
    OffroadConfig.reset();
  }
}
