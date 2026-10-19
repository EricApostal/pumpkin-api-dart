// The module contract. See docs/ARCHITECTURE.md.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import 'block_entity.dart';
import 'config.dart';
import 'network.dart';
import 'registry.dart';
import 'registry_apply.dart';
import 'services.dart';
import 'world_state.dart';
import 'worlds.dart';

/// One slice of the mod (kinetics, logistics, ...). Lives in `lib/src/<name>/`
/// and is listed once in `lib/src/modules.dart`.
abstract class CreateModule {
  /// Lowercase unique name; also the key in `core.modules` of the config.
  String get name;

  /// Whether the module runs. Defaults to `core.modules.<name>` (true when absent).
  bool isEnabled(CreateConfig config) => config.moduleEnabled(name);

  /// Phase 1: declare content. No host calls here.
  void register(CreateRegistry registry);

  /// Phase 2: the registries are applied. Subscribe to events, provide
  /// services, read config sections.
  void onLoad(CreateContext ctx) {}

  /// Phase 3: the server finished loading (`Events.serverLoad`).
  void onServerLoaded(CreateRuntime runtime) {}

  /// The plugin unloads (reverse module order).
  void onUnload() {}
}

/// The state shared by all modules.
final class CreateCore {
  final CreateConfig config;
  final CreateServices services = CreateServices();
  final CreateRegistry registry = CreateRegistry();
  final Worlds worlds = Worlds();
  final Logger log;
  late final BlockEntityStore blockEntities = BlockEntityStore(
    worlds,
    log.child('blockentities'),
    saveIntervalTicks: config.core.saveIntervalTicks,
  );
  late final CreateNetwork network = CreateNetwork(registry.payloads, log.child('network'));
  late final WorldSavedData savedData = WorldSavedData(worlds, log.child('saved'));

  /// The ids assigned by the host; set after the registry was applied.
  AppliedIds ids = AppliedIds();

  CreateCore(this.config, this.log);
}

/// What a module gets in `onLoad`.
final class CreateContext {
  final CreateCore _core;
  final Context Function() _host;

  /// The module's logger (`create.<module>`).
  final Logger log;

  CreateContext(this._core, this._host, String moduleName) : log = _core.log.child(moduleName);

  /// The host's load context (kept for the lifetime of the plugin).
  Context get host => _host();
  CreateConfig get config => _core.config;
  CreateServices get services => _core.services;
  BlockEntityStore get blockEntities => _core.blockEntities;
  WorldSavedData get savedData => _core.savedData;
  Worlds get worlds => _core.worlds;
  AppliedIds get ids => _core.ids;

  /// Subscribes to a host event (see `docs/events-and-time.md` of pumpkin_api).
  EventSubscription listen<D>(
    EventKind<D> kind,
    FutureOr<void> Function(Server server, D data) handler, {
    EventPriority priority = EventPriority.normal,
  }) => host.listen(kind, handler, priority: priority);
}

/// What a module gets in `onServerLoaded`.
final class CreateRuntime {
  final CreateCore _core;

  /// The server; valid until the event callback returns.
  final Server server;
  final Logger log;

  CreateRuntime(this._core, this.server, String moduleName) : log = _core.log.child(moduleName);

  CreateConfig get config => _core.config;
  CreateServices get services => _core.services;
  BlockEntityStore get blockEntities => _core.blockEntities;
  WorldSavedData get savedData => _core.savedData;
  Worlds get worlds => _core.worlds;
  AppliedIds get ids => _core.ids;
}
