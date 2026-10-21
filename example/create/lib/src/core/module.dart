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

  /// Phase 3: the server finished loading (`Events.serverLoad`). Return a
  /// future to keep using [CreateRuntime.server] across awaits: the server is
  /// released when the event callback returns.
  FutureOr<void> onServerLoaded(CreateRuntime runtime) {}

  /// The plugin unloads (reverse module order).
  void onUnload() {}
}

/// Handles one world tick; registered with `CreateContext.onWorldTick`.
typedef WorldTickHandler = FutureOr<void> Function(WorldTick t);

/// One world-tick handler and the name the `[perf-tick]` report shows it under.
typedef NamedWorldTickHandler = ({String label, WorldTickHandler run});

/// The state shared by all modules.
final class CreateCore {
  final CreateConfig config;
  final CreateServices services = CreateServices();
  final CreateRegistry registry = CreateRegistry();
  final Worlds worlds = Worlds();

  /// The world tick handlers, in registration order: the framework's first, then
  /// the modules' in module order. The plugin runs them from one host listener
  /// per world tick ([WorldTick] resolves the world id at most once).
  final List<NamedWorldTickHandler> worldTickHandlers = [];

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

  /// The module's name, as in `CreateModule.name`. Also the label prefix its
  /// world-tick handlers are reported under.
  final String name;

  /// The module's logger (`create.<module>`).
  final Logger log;

  /// How many world-tick handlers this module registered, for their labels.
  int _worldTicks = 0;

  CreateContext(this._core, this._host, String moduleName)
    : name = moduleName,
      log = _core.log.child(moduleName);

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

  /// Registers a per-world-tick handler: it runs for every world on every tick,
  /// from the plugin's single `worldTick` host listener, in registration order.
  ///
  /// Check your module's state first and return early when there is nothing to
  /// do — [WorldTick.worldId] and [WorldTick.playersInWorld] are host calls and
  /// are only made when the handler asks for them, so an idle tick is free.
  ///
  /// [label] names the handler in the `[perf-tick]` breakdown; the default is the
  /// module name and the handler's position in it, which is what the report uses
  /// to tell one handler from another (`conveyance#0`).
  void onWorldTick(WorldTickHandler handler, {String? label}) =>
      _core.worldTickHandlers.add((
        label: label ?? '$name#${_worldTicks++}',
        run: handler,
      ));
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
