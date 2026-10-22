// Installs the module state of the Create modules a plugin hosts the *content*
// of without running those modules itself (an addon: Aeronautics, Simulated,
// Offroad). See docs/ARCHITECTURE.md, "Module state in a plugin that hosts
// Create's content".
//
// Host: this file uses `pumpkin_api`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../contraptions/blocks/actuator_runtime.dart';
import '../contraptions/core/structure_info.dart';
import '../core/block_entity.dart';
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
/// also what the kinetic network resolves its neighbours through.
///
/// Only kinetics and contraptions have the state Create's library reads: no
/// class of the kinetics or contraptions library reaches `FluidsRuntime`, the
/// conveyance, equipment, processing, logistics, redstone or trains runtime, so
/// a component without those modules needs nothing from them. Their state is
/// also inseparable from their module: the conveyance and equipment runtimes
/// subscribe to host events and hold the module's hosts at construction, and
/// the processing one needs the module's recipe book.
void installHostedModuleState({
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
  );
}