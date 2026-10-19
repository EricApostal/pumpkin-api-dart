// `KineticNetworkService`: what other modules use of the kinetic network.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/blocks.dart';
import 'block_defs.dart';
import 'block_entities.dart';
import 'generators.dart';
import 'geometry.dart';
import 'kinetic_block_entity.dart';
import 'network.dart';
import 'node.dart';
import 'runtime.dart';
import 'settings.dart';
import 'transform.dart';

/// The public face of the kinetics module (`ctx.services.require<KineticNetworkService>()`).
///
/// * register the kinetic blocks of your module with [registerKineticBlock] in
///   `onLoad` (so shafts connect to them) and extend [KineticBlockEntity];
/// * read speeds and networks with [kineticAt] / [networkOf];
/// * change the block of a kinetic block entity with [switchToBlockState];
/// * stress values and config: [settings], [stress].
final class KineticNetworkService {
  final KineticsRuntime runtime;
  final Map<String, CreateBlock> _blocks;

  KineticNetworkService(this.runtime, Iterable<CreateBlock> blocks) : _blocks = {for (final b in blocks) b.key: b};

  /// The [CreateBlock] of a block of this module (`create:shaft`).
  CreateBlock? blockOf(String blockKey) => _blocks[blockKey];

  KineticConfig get settings => runtime.settings;
  StressSource get stress => runtime.stress;
  KineticBlockRegistry get blocks => runtime.blocks;

  /// Registers the connection rules of a kinetic block (`IRotate`). Call it in
  /// `onLoad` for every block of your module whose block entity is a
  /// [KineticBlockEntity]. [isChainDrive] marks encased chain drives.
  void registerKineticBlock(String blockKey, KineticBlockDef def, {bool isChainDrive = false}) {
    runtime.blocks.register(blockKey, def);
    if (isChainDrive) runtime.blocks.chainDriveBlocks.add(blockKey);
  }

  /// Registers the stress impact / capacity per RPM of a block of another module
  /// (the manifest table is already loaded; use this for additions only).
  void registerStress(String blockKey, {double? impact, double? capacity, int? generatedRpm, bool mayGenerateLess = false}) =>
      runtime.stressTable.register(blockKey, impact: impact, capacity: capacity, generatedRpm: generatedRpm, mayGenerateLess: mayGenerateLess);

  /// The module providing boiler efficiencies for steam engines (fluids module).
  set boilerSource(SteamEngineBoilerSource? source) => runtime.boilerSource = source;

  /// The kinetic block entity at [pos] of world [worldId].
  KineticBlockEntity? kineticAt(String worldId, BlockPos pos) {
    final be = runtime.store.at(worldId, pos);
    return be is KineticBlockEntity ? be : null;
  }

  /// The network the block entity at [pos] belongs to.
  KineticNetwork? networkAt(String worldId, BlockPos pos) => kineticAt(worldId, pos)?.getOrCreateNetwork();

  /// `getSpeed()` of the block at [pos] (0 when there is none or it is overstressed).
  double speedAt(String worldId, BlockPos pos) => kineticAt(worldId, pos)?.speed ?? 0;

  /// The kinetic view of a world (state reading, network table).
  KineticLevel levelOf(String worldId) => runtime.level(worldId);

  /// The state of the block at [pos] (decoded and cached).
  KState stateAt(String worldId, BlockPos pos) => runtime.level(worldId).stateAt(toKPos(pos));

  /// The global state id of [state], `null` when unknown.
  int? stateId(KState state) => runtime.states.idOf(state);

  /// `KineticBlockEntity.switchToBlockState`.
  Future<void> switchToBlockState(String worldId, BlockPos pos, KState state) =>
      KineticOps.switchToBlockState(runtime, worldId, pos, state);

  /// `BlockState.rotate(Rotation)` for the kinetic blocks whose rotation needs more than the
  /// generic `facing` / `axis` rule (encased cogwheels, chain drives, gauges); `null` for
  /// the others. [clockwiseTurns] is `Rotation.ordinal()` (0 none, 1 cw90, 2 cw180, 3 ccw90).
  KState? rotateState(KState state, int clockwiseTurns) => rotateKineticState(state, clockwiseTurns, runtime.blocks);

  /// `BlockState.mirror(Mirror)` for those blocks, `null` for the others.
  KState? mirrorState(KState state, {required bool frontBack, required bool leftRight}) =>
      mirrorKineticState(state, frontBack: frontBack, leftRight: leftRight);

  /// Whether [blockKey] is a kinetic block known to the module.
  bool isKineticBlock(String blockKey) => runtime.blocks.defOf(blockKey) != null;

  /// Called when a stressometer was looked at with goggles (advancements).
  set onStressometerObserved(void Function(StressGaugeBlockEntity gauge)? hook) =>
      StressGaugeBlockEntity.onObservedHook = hook;

  /// Called when a water or lava wheel turns (advancements).
  set onWaterWheelTurns(void Function(WaterWheelBlockEntity wheel, {required bool lava})? hook) =>
      WaterWheelBlockEntity.onWheelTurnsHook = hook;
}
