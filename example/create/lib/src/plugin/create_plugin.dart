// The Pumpkin plugin: reads the config, runs the modules through their phases,
// applies the registry to the host, installs the framework listeners and the
// optional NeoForge declaration. See docs/ARCHITECTURE.md.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/config.dart';
import '../core/module.dart';
import '../core/registry.dart';
import '../core/registry_apply.dart';
import '../manifest/canonical_order.dart';
import '../modules.dart';
import 'create_neoforge.dart';

final class CreatePlugin extends Plugin {
  /// [modules] replaces [allModules] (tests, tools).
  CreatePlugin({List<CreateModule>? modules}) : _all = modules ?? allModules;

  final List<CreateModule> _all;
  final List<CreateModule> _active = [];
  CreateCore? _core;

  static const String configFile = 'config.json';

  @override
  PluginInfo get info => const PluginInfo(
    name: 'create',
    version: '0.1.0',
    description: 'Server side of the Create mod for Pumpkin.',
    // Modules that need more host features add their permission here.
    permissions: [
      Permissions.fsWriteData,
      Permissions.registryItems,
      Permissions.registryBlocks,
      Permissions.registryBlockEntities,
      Permissions.registryMenus,
      Permissions.registryComponents,
      Permissions.registryEntities,
      Permissions.registryFluids,
      Permissions.registryDamageTypes,
      Permissions.registryRecipes,
      Permissions.registryExtra,
      Permissions.registryWorldgen,
      Permissions.fakePlayers,
      Permissions.containers,
      Permissions.entityFlags,
      Permissions.neoforge,
    ],
  );

  CreateConfig _loadConfig(Context context) {
    final files = context.files;
    String? text;
    try {
      if (files.exists(configFile)) text = files.readAsString(configFile);
    } on FileException catch (e) {
      logger.warn('Could not read $configFile: $e');
    }
    return CreateConfig.parse(text);
  }

  @override
  Future<void> onLoad(Context context) async {
    final log = Logger('create');
    final config = _loadConfig(context);
    final core = _core = CreateCore(config, log);

    // Phase 1: declare.
    final seen = <String>{};
    for (final module in _all) {
      if (!seen.add(module.name))
        throw StateError('Two modules are called ${module.name}');
      if (!module.isEnabled(config)) {
        log.info('Module ${module.name} is disabled');
        continue;
      }
      try {
        module.register(core.registry);
        _active.add(module);
      } catch (e, s) {
        log.error(
          'Module ${module.name} failed to register, skipped',
          error: e,
          stackTrace: s,
        );
        rethrow; // A half registered module would shift the ids of everything after it.
      }
    }
    // The host ids must match the Java mod's registration order for a Create
    // client to understand them.
    applyCanonicalOrder(core.registry);

    for (final kind in RegistryKind.values) {
      final report = core.registry.reportOf(kind);
      if (!report.isClean) {
        log.warn(
          '${kind.name}: ${report.missing.length} canonical keys not registered, ${report.extra.length} not in the canonical order',
        );
      }
    }

    // Phase 2: apply to the host, then the framework and the modules.
    core.ids = await applyRegistry(
      core.registry,
      context,
      core.blockEntities,
      log,
      logIds: config.core.logRegistryIds,
    );
    core.worlds.install(context);
    core.blockEntities.install(context);
    core.savedData.install(
      context,
      saveIntervalTicks: config.core.saveIntervalTicks,
    );
    core.network.install(context);

    for (final module in _active) {
      try {
        module.onLoad(CreateContext(core, () => this.context, module.name));
      } catch (e, s) {
        log.error(
          'Module ${module.name} failed in onLoad',
          error: e,
          stackTrace: s,
        );
      }
    }

    if (config.core.neoforge) {
      try {
        context.declareNeoForge(
          createNeoForgeDeclaration(
            core.registry,
            modVersion: config.core.modVersion,
          ),
        );
      } on HostException catch (e) {
        log.error(
          'Could not declare Create to the NeoForge handshake: ${e.message}',
        );
        rethrow;
      }
    }

    // Phase 3.
    context.listen(Events.serverLoad, (server, event) {
      if (event.loadType != ServerLoadType.startup) return;
      core.worlds.refresh(server);
      for (final module in _active) {
        try {
          module.onServerLoaded(CreateRuntime(core, server, module.name));
        } catch (e, s) {
          log.error(
            'Module ${module.name} failed in onServerLoaded',
            error: e,
            stackTrace: s,
          );
        }
      }
    });

    for (final w in config.warnings) {
      log.warn(w);
    }
    if (config.needsWrite) {
      try {
        context.files.writeAsString(configFile, config.toJsonString());
      } on FileException catch (e) {
        log.warn('Could not write $configFile: $e');
      }
    }
    log.info(
      'Create loaded: ${_active.length} modules, ${core.ids.all(RegistryKind.blocks).length} blocks, '
      '${core.registry.items.length} items, ${core.registry.payloads.ids.length} channels.',
    );
  }

  @override
  Future<void> onUnload(Context context) async {
    final core = _core;
    for (final module in _active.reversed) {
      try {
        module.onUnload();
      } catch (e, s) {
        logger.error('Module ${module.name} failed in onUnload: $e\n$s');
      }
    }
    if (core != null) {
      core.blockEntities.flushAll();
      core.savedData.flushAll();
      core.worlds.clear();
    }
    _active.clear();
    _core = null;
  }
}
