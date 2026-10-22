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

import 'package:create/create.dart' show installHostedModuleState;
import 'package:create/src/core/block_entity.dart';
import 'package:create/src/core/registry.dart';
import 'package:create/src/core/registry_apply.dart';
import 'package:create/src/core/worlds.dart';
import 'package:create/src/kinetics/block_defs.dart' show FacingBlockDef;
import 'package:create/src/kinetics/runtime.dart' show KineticsRuntime;
import 'package:create/src/plugin/create_addon.dart' show createAddonNeoForgeDeclaration;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../config/sim_config.dart';
import '../config/sim_config_service.dart';
import '../config/sim_synced_config.dart';
import '../content/blocks/portable_engine/portable_engine_block.dart' show portableEngineKey;
import '../content/blocks/portable_engine/portable_engine_logic.dart'
    show portableEngineSpeed, portableEngineStressCapacity;
import '../host/pumpkin_host.dart';
import '../host/sable_bridge.dart';
import '../util/assembly/sim_assembly_exception.dart';
import '../util/sim_assembly_helper.dart';
import '../host/simulated_host.dart';
import '../index/sim_channels.dart';
import '../network/sim_handled.dart';
import '../index/sim_blocks.dart' show SimBlockKeys;
import '../index/sim_lift_providers.dart';
import '../index/sim_registry.dart';
import '../service/sim_services.dart';
import '../util/sim_placement_fixes.dart';
import 'sim_payload_handlers.dart';

/// The plugin of Simulated.
final class SimulatedPlugin extends Plugin {
  /// The config file inside the plugin's data folder.
  static const String configFile = 'config.json';

  final Worlds _worlds = Worlds();
  final SableBridge _bridge = SableBridge(logger);
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
      Permissions.neoforge,
    ],
  );

  @override
  Future<void> onLoad(Context context) async {
    final log = logger;
    final config = _loadConfig(context);
    SimConfigService.instance.load(config);

    final blockEntities = _blockEntities = BlockEntityStore(_worlds, log.child('blockentities'));
    // The torsion spring, the swivel bearing and the steering wheel are Create's
    // kinetic block entities: their lifecycle runs in this component and reads
    // Create's module state, which only Create's own plugin would install — in
    // its own component.
    installHostedModuleState(blockEntities: blockEntities, worlds: _worlds, log: log);

    // Phase 1: declare.
    SimRegistry.register(
      _registry,
      lookup: <T>(String worldId, (int, int, int) pos) {
        final entity = blockEntities.at(worldId, BlockPos(x: pos.$1, y: pos.$2, z: pos.$3));
        return entity is T ? entity as T : null;
      },
    );

    // Phase 2: apply.
    for (final entry in SimRegistry.reports(_registry).entries) {
      final report = entry.value;
      if (report.isClean) continue;
      // Not an error: the port registers a subset of the Java content, and the
      // ids of what it does register are pinned to the Java order. The count is
      // what a client with the Java mods would number differently.
      log.info(
        '${entry.key.name}: ${report.missing.length} keys of the Java order are not ported yet'
        '${report.extra.isEmpty ? '' : ', ${report.extra.length} registered that the Java order does not list'}',
      );
    }
    await applyRegistry(_registry, context, blockEntities, log);
    _registerKinetics(context, log);
    _worlds.install(context);
    blockEntities.install(context);

    SimulatedHost.instance = PumpkinSimulatedHost(_worlds, blockEntities, log);

    // Phase 3: answer the serverbound payloads whose content is ported (the
    // assembler, the wheel, the lever, the spring, honey glue). They go through
    // Create's payload registry, which is also what the declaration is built
    // from, so a channel cannot be declared and handled twice.
    SimPayloadHandlers(blockEntities: blockEntities, log: log).install(_registry, context);

    // The placement states of the blocks whose Java `getStateForPlacement` reads
    // the clicked face or the `AttachFace` (see `util/sim_placement_fixes.dart`):
    // the click has to be recorded while it happens, because the host's `placed`
    // event does not carry it.
    (SimPlacementFixes.instance ??= SimPlacementFixes()).install(context);

    // Phase 4: declare the mod and its 37 payload channels, so a client that has
    // Simulated installed completes the NeoForge negotiation. This goes through
    // Create's generic addon hook: Create itself never names Simulated. The six
    // channels registered above are already in the registry, so the addon
    // declares only the other 31.
    //
    // The mod's SYNCED server config goes with the declaration. A client that has
    // Simulated parses it into the mod's `ModConfigSpec` and reads it while
    // building item tooltips (Create's `KineticStats` -> `BlockStressValues
    // .getImpact` -> `SimStress::getImpact`), so a client the server never sent it
    // to crashes on the first hover with "Cannot get config value before config
    // is loaded" -- exactly as it would against a Java server whose `ConfigSync`
    // skipped the file.
    _registry.neoForgeConfigFile(
      simSyncedConfigFile,
      utf8.encode(simSyncedToml(SimConfigService.instance.server)),
    );
    context.declareNeoForge(
      createAddonNeoForgeDeclaration(
        SimulatedAddon(handled: SimHandledPayloads.idSet),
        registry: _registry,
      ),
    );

    registerSimLiftProviders();

    // The sub-level model lives in the Sable plugin's component (each plugin is
    // its own wasm instance), so assembly is delegated to it over the host's
    // plugin IPC instead of calling `SubLevelAssemblyHelper` here, where the
    // container map is empty. See `host/sable_bridge.dart`.
    _bridge.install();
    await _bridge.subscribe();
    SimAssemblyHelper.assembleBlocks = (world, anchor, blocks, bounds) async {
      final reply = await _bridge.assemble(
        world: world,
        anchor: anchor,
        blocks: blocks,
        bounds: (bounds.minX, bounds.minY, bounds.minZ, bounds.maxX, bounds.maxY, bounds.maxZ),
      );
      if (!reply.ok) throw SimAssemblyException(reply.error ?? 'assembly failed');
      final ref = reply.subLevel;
      if (ref == null) return null;
      return SimAssembledSubLevel(ref.id, ref.centerBlock);
    };

    log.info(
      'Simulated loaded: ${_registry.blocks.entries.length} blocks, '
      '${_registry.blockEntityTypes.entries.length} block entity types.',
    );
  }

  /// The portable engines are kinetic generators (`PortableEngineBlock extends
  /// HorizontalKineticBlock`): a shaft on their facing side, 32 RPM and 64 stress
  /// capacity (`BlockStressValues.setGeneratorSpeed(32)`,
  /// `SimStress.setCapacity(64.0)`). Create's kinetics module owns the network,
  /// so the rules are registered on its service after the blocks are applied.
  void _registerKinetics(Context context, Logger log) {
    // `KineticsRuntime.instance` is Create's module state; `KineticNetworkService`
    // wraps exactly these two calls, and the runtime is what a block of another
    // plugin may reach.
    if (!KineticsRuntime.isLoaded) {
      log.warn("Create's kinetics module is not loaded: the portable engines will not turn.");
      return;
    }
    final runtime = KineticsRuntime.instance;
    // `PortableEngineBlock.hasShaftTowards(face) = face == HORIZONTAL_FACING`.
    const def = FacingBlockDef();
    for (final colour in SimBlockKeys.engineColours) {
      final key = portableEngineKey(colour);
      runtime.blocks.register(key, def);
      runtime.stressTable.register(
        key,
        capacity: portableEngineStressCapacity,
        generatedRpm: portableEngineSpeed,
      );
    }
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
    SimAssemblyHelper.assembleBlocks = null;
    _bridge.close();
    _blockEntities.flushAll();
    SimulatedHost.instance = null;
    SimServices.instance = SimServices();
  }
}
