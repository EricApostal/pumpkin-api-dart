// The Pumpkin plugin: reads the config, runs the modules through their phases,
// applies the registry to the host, installs the framework listeners and the
// optional NeoForge declaration. See docs/ARCHITECTURE.md.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/config.dart';
import '../core/module.dart';
import '../core/perf.dart';
import '../core/registry.dart';
import '../core/registry_apply.dart';
import '../core/worlds.dart';
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
    Perf.log = log.info;
    try {
      // The file's content, when it is a number, is the tick interval of the per-tick
      // attribution report; an empty file keeps the default.
      final marker = context.files.readAsString('perf');
      Perf.enabled = true;
      Perf.tickReportEvery = int.tryParse(marker.trim()) ?? Perf.tickReportEvery;
      // The per-tick report carries the same numbers as a delta, so the per-200-samples
      // aggregate lines would only flood the log.
      Perf.reportEvery = 0;
      // Attributes every host→guest event callback to the event type that caused it,
      // whichever API registered the listener.
      eventTimingSink = Perf.eventTime;
    } on FileException {
      Perf.enabled = false;
    }
    final total = Stopwatch()..start();
    final config = _loadConfig(context);
    final core = _core = CreateCore(config, log);
    if (Perf.enabled) log.info('[perf] timings on (delete the `perf` file to stop)');

    // Phase 1: declare.
    Perf.measure('onLoad.register', () {
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
    });
    // The host ids must match the Java mod's registration order for a Create
    // client to understand them.
    Perf.measure('onLoad.canonicalOrder', () => applyCanonicalOrder(core.registry));

    for (final kind in RegistryKind.values) {
      final report = core.registry.reportOf(kind);
      if (!report.isClean) {
        log.warn(
          '${kind.name}: ${report.missing.length} canonical keys not registered, ${report.extra.length} not in the canonical order',
        );
      }
    }

    // Phase 2: apply to the host, then the framework and the modules.
    core.ids = await Perf.measureAsync(
      'onLoad.applyRegistry',
      () => applyRegistry(
        core.registry,
        context,
        core.blockEntities,
        log,
        logIds: config.core.logRegistryIds,
      ),
    );
    Perf.measure('onLoad.framework', () {
      core.worlds.install(context);
      core.blockEntities.install(context);
      core.savedData.install(
        context,
        saveIntervalTicks: config.core.saveIntervalTicks,
      );
      core.network.install(context);

      // One host listener for every world tick, for the framework and all
      // modules: the host calls into the plugin once per world and tick instead
      // of once per listener, and the world id and player list are fetched at
      // most once for the whole tick (`WorldTick` resolves them lazily).
      core.worldTickHandlers.add((
        label: 'core.blockEntities',
        run: core.blockEntities.tickWorld,
      ));
      core.worldTickHandlers.add((
        label: 'core.savedData',
        run: core.savedData.tickWorld,
      ));
      context.listen(Events.worldTick, (server, event) async {
        // Closes the per-tick attribution window of the previous tick and logs the
        // breakdown every `Perf.tickReportEvery` ticks (one `[perf-tick]` line).
        Perf.onTick(event.tick);
        final tick = WorldTick(server, event, core.worlds);
        for (final handler in core.worldTickHandlers) {
          try {
            final result = Perf.handler(
              handler.label,
              () => handler.run(tick),
            );
            if (result is Future) await result;
          } catch (e, s) {
            log.error('World tick handler failed', error: e, stackTrace: s);
          }
        }
      });
    });

    for (final module in _active) {
      Perf.measure('onLoad.module.${module.name}', () {
        try {
          module.onLoad(CreateContext(core, () => this.context, module.name));
        } catch (e, s) {
          log.error(
            'Module ${module.name} failed in onLoad',
            error: e,
            stackTrace: s,
          );
        }
      });
    }

    if (config.core.neoforge) {
      Perf.measure('onLoad.neoforge', () {
        try {
          context.declareNeoForge(
            createNeoForgeDeclaration(
              core.registry,
              mod: NeoForgeMod(id: createModId, version: config.core.modVersion, displayName: 'Create'),
            ),
          );
        } on HostException catch (e) {
          log.error(
            'Could not declare Create to the NeoForge handshake: ${e.message}',
          );
          rethrow;
        }
      });
    }

    // Phase 3. The listener is async and awaits every module: `server` is
    // released when the callback returns, so work that outlives the callback
    // must be part of it (docs/async.md).
    context.listen(Events.serverLoad, (server, event) async {
      if (event.loadType != ServerLoadType.startup) return;
      core.worlds.refresh(server);
      for (final module in _active) {
        try {
          await module.onServerLoaded(
            CreateRuntime(core, server, module.name),
          );
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
    if (Perf.enabled) {
      log.info('[perf] onLoad total: ${total.elapsedMilliseconds}ms');
      Perf.report('onLoad');
      Perf.reset();
      // What the instrumentation itself costs on this platform, so a `tick.*` row
      // can be read against it (a floor of a few us is the measurer, not the mod).
      Perf.selfTest();
      // The `[perf-tick]` labels of the world tick, in the order they run: what an
      // idle tick costs is the sum of these plus the host→guest callbacks.
      log.info(
        '[perf] per-tick report every ${Perf.tickReportEvery} ticks; world tick '
        'handlers: ${core.worldTickHandlers.map((h) => h.label).join(', ')}',
      );
    }
  }

  @override
  Future<void> onUnload(Context context) async {
    eventTimingSink = null;
    Perf.enabled = false;
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
