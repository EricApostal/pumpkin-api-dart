// Installs the module state of the Create modules a plugin hosts the *content*
// of without running those modules itself (an addon: Aeronautics, Simulated,
// Offroad). See docs/ARCHITECTURE.md, "Module state in a plugin that hosts
// Create's content".
//
// Host: this file uses `pumpkin_api`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../common/pos.dart' show Pos;
import '../contraptions/blocks/actuator_contract.dart';
import '../contraptions/blocks/actuator_runtime.dart';
import '../contraptions/core/structure_info.dart';
import '../contraptions/entity/contraption_collider.dart';
import '../contraptions/entity/host_contraption_entities.dart';
import '../contraptions/entity/translating_contraption.dart';
import '../core/block_entity.dart';
import '../core/module.dart' show NamedWorldTickHandler;
import '../core/services.dart';
import '../core/world_state.dart' show WorldSavedData;
import '../core/worlds.dart';
import '../kinetics/runtime.dart';
import '../kinetics/settings.dart';

/// Brings up the per-component module state that Create's block entities read.
///
/// One Pumpkin plugin is one wasm component, so a `static` of the Create port
/// does not cross the plugin boundary: `KineticsRuntime._instance` and
/// `ActuatorRuntime._instance` are per component, and Create's own plugin fills
/// them from `KineticsModule.onLoad` and `loadActuatorContent`. A plugin that
/// registers a block entity extending one of Create's kinetic or contraption
/// classes — Aeronautics' propeller bearings, Simulated's torsion spring,
/// swivel bearing and steering wheel, Offroad's wheel mount and borehead
/// bearing — runs that class's whole lifecycle in its own component, and the
/// lifecycle reads that state. Without this call the block entity's first
/// lifecycle callback (`onLoad`) throws `Bad state: The kinetics module is not
/// loaded`, and so does every tick and every `onRemoved` after it.
///
/// Call it from `Plugin.onLoad`, after the block entity [blockEntities] store
/// exists and before `blockEntities.install(context)`, so it is in place before
/// the first block entity loads. Create's own plugin never calls it: every one
/// of its modules installs its own state in `onLoad`, with the live config
/// values.
///
/// The settings are Create's manifest defaults (`KineticsSettings()`,
/// `DefaultContraptionSettings()`): this plugin's `config.json` is not Create's,
/// and the `infrastructure` module, which supplies the live values, is not
/// loaded in this component either. Create's kinetic block definitions are not
/// registered: this component holds none of Create's blocks. A plugin with
/// kinetic content of its own registers a definition for each of its blocks in
/// `KineticsRuntime.instance.blocks` (`blocks.register(key, def)`), which is
/// also what *this* component's propagation resolves its neighbours through —
/// and, so that Create's component's network sees the same blocks, it sends the
/// same rules over `create.kinetics` (`installConsumerKinetics`; see
/// `docs/kinetics-across-plugins.md`). That second call is what makes a Create
/// shaft drive an addon's bearing at all: without it the addon's defs exist only
/// in this component, and Create's network has no edge to them.
///
/// Only kinetics and contraptions have the state Create's library reads: no
/// class of the kinetics or contraptions library reaches `FluidsRuntime`, the
/// conveyance, equipment, processing, logistics, redstone or trains runtime, so
/// a component without those modules needs nothing from them. Their state is
/// also inseparable from their module: the conveyance and equipment runtimes
/// subscribe to host events and hold the module's hosts at construction, and
/// the processing one needs the module's recipe book.
///
/// The contraption host is installed here too, and returned, so a controller
/// that has to tick its own contraption entities can reach it.
ContraptionHost installHostedModuleState({
  required BlockEntityStore blockEntities,
  required Worlds worlds,
  required Logger log,
}) {
  KineticsRuntime(const KineticsSettings(), blockEntities, worlds, log);
  ActuatorRuntime(
    settings: DefaultContraptionSettings(),
    store: blockEntities,
    worlds: worlds,
    log: log,
    services: CreateServices(),
  );

  // The contraption host and the factories the actuators build and spawn their
  // entities through. Create's own plugin installs these in
  // `ContraptionsModule.onLoad`; a plugin that hosts only the *content* of a
  // bearing (`aeronautics:propeller_bearing`, `offroad:borehead_bearing`) never
  // loads that module, so without this every `assemble` returns at its
  // `if (level == null || factory == null) return;` guard and no bearing of the
  // component can ever capture a contraption.
  final host = ContraptionHost(
    worlds: worlds,
    blockEntities: blockEntities,
    settings: DefaultContraptionSettings(),
    log: log,
  );
  ActuatorHosts.entityFactory = HostContraptionEntityFactory(host);
  ActuatorHosts.levelFactory = host.levelOf;
  ActuatorHosts.glue = HostGlueEntityHost(host);

  ContraptionCollision.collideBlocks = ContraptionCollider.collideBlocks;
  ContraptionCollision.isCollidingWithWorld =
      (level, contraption, anchor, direction) =>
          contraption is TranslatingContraption &&
          ContraptionCollider.isCollidingWithWorld(contraption, anchor, direction);

  // Bearings, clockwork bearings and pulleys cannot be moved while they run.
  ContraptionHostHooks.isActuatorRunning = (worldId, Pos pos) =>
      switch (blockEntities.at(worldId, BlockPos(x: pos.$1, y: pos.$2, z: pos.$3))) {
        final RunningActuator actuator => actuator.isRunning,
        _ => false,
      };

  return host;
}

/// Runs this component's per-world framework tick.
///
/// Create's own plugin wires this in its `onLoad` (`lib/src/plugin/create_plugin.dart`):
/// one host `worldTick` listener that runs, in order, the block entity store's
/// pending writes, the kept saved data, and whatever a module registered with
/// `CreateContext.onWorldTick`.
///
/// A component that *hosts* Create's content must wire it too, and a component
/// that is not Create's plugin very easily forgets: without it the block entities
/// of that component are written to the host **once**, when they are created, and
/// never again — `markChanged`/`sendData` only add them to a set nothing flushes,
/// and `onWorldTick` handlers never run. Measured on
/// `aeronautics:propeller_bearing`: the block entity in its own component was
/// turning at 16 RPM (the component that runs the network read `speed 16`,
/// `network 4034`, `members 3`) while `data get block` on the host still answered
/// `Speed: 0f` and no `Network` — and that host data is what a client is sent, so
/// the propeller's rotation (and thrust) never reached it. Same for the swivel
/// bearing and every other client-visible field of an addon's block entity.
///
/// Call it from the plugin's `onLoad`, after [installHostedModuleState] and after
/// the registry was applied (so the store's types exist).
///
/// [moduleHandlers] are the component's own per-world handlers: a module that
/// registered one through `CreateContext.onWorldTick` put it in
/// `CreateCore.worldTickHandlers`, so a component with a core passes that list.
void installHostedWorldTick({
  required Context context,
  required Worlds worlds,
  required BlockEntityStore blockEntities,
  required Logger log,
  WorldSavedData? savedData,
  List<NamedWorldTickHandler> moduleHandlers = const [],
}) {
  final handlers = <NamedWorldTickHandler>[
    (label: 'core.blockEntities', run: blockEntities.tickWorld),
    if (savedData != null) (label: 'core.savedData', run: savedData.tickWorld),
    ...moduleHandlers,
  ];
  context.listen(Events.worldTick, (server, event) async {
    final tick = WorldTick(server, event, worlds);
    for (final handler in handlers) {
      try {
        final result = handler.run(tick);
        if (result is Future) await result;
      } on Object catch (error, stack) {
        log.error(
          'World tick handler ${handler.label} failed',
          error: error,
          stackTrace: stack,
        );
      }
    }
  });
}
