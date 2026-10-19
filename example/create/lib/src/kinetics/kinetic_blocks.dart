// The list of kinetic blocks and block entity types of this module.
import 'dart:collection';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/block_entity.dart';
import '../core/registry.dart';
import '../manifest/manifest.dart';
import 'block_entities.dart';
import 'block_factory.dart';
import 'generators.dart';
import 'kinetic_block_entity.dart';
import 'kinetic_blocks_a.dart';
import 'kinetic_blocks_b.dart';
import 'steam_engine.dart';

/// The specs of every block this module registers, in manifest order.
List<KineticBlockSpec> buildKineticBlocks() {
  final specs = <KineticBlockSpec>[
    shaftSpec(),
    cogwheelSpec(large: false),
    cogwheelSpec(large: true),
    encasedShaftSpec('andesite'),
    encasedShaftSpec('brass'),
    encasedCogwheelSpec('andesite', large: false),
    encasedCogwheelSpec('brass', large: false),
    encasedCogwheelSpec('andesite', large: true),
    encasedCogwheelSpec('brass', large: true),
    gearboxSpec(),
    gearshiftSpec(clutch: true),
    gearshiftSpec(clutch: false),
    chainDriveSpec(gearshift: false),
    chainDriveSpec(gearshift: true),
    creativeMotorSpec(),
    waterWheelSpec(),
    largeWaterWheelSpec(),
    waterWheelStructureSpec(),
    turntableSpec(),
    handCrankSpec(),
    cuckooClockSpec(mysterious: false),
    cuckooClockSpec(mysterious: true),
    gaugeSpec(stress: false),
    gaugeSpec(stress: true),
    valveHandleSpec(null),
    for (final c in dyeColors) valveHandleSpec(c),
    steamEngineSpec(),
    poweredShaftSpec(),
    sequencedGearshiftSpec(),
    flywheelSpec(),
    speedControllerSpec(),
  ];
  final order = {for (final b in kBlocks) 'create:${b.key}': b.index};
  specs.sort((a, b) => order[a.block.key]!.compareTo(order[b.block.key]!));
  return specs;
}

/// The blocks of a block entity type, computed when the registry is applied: the manifest
/// list filtered to the blocks that were registered (some belong to other modules, like
/// `create:metal_girder_encased_shaft`) plus the [extra] blocks others added.
final class _LazyValidBlocks extends ListBase<String> {
  final CreateRegistry registry;
  final List<String> candidates;
  final List<String> extra = [];

  _LazyValidBlocks(this.registry, this.candidates);

  List<String> _compute() => [
    for (final b in candidates)
      if (registry.blocks.contains(b)) b,
    for (final b in extra)
      if (!candidates.contains(b)) b,
  ];

  @override
  int get length => _compute().length;

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  String operator [](int index) => _compute()[index];

  @override
  void operator []=(int index, String value) => throw UnsupportedError('read only');

  @override
  void add(String element) => extra.add(element);
}

/// The valid blocks of each block entity type of this module, by type key
/// (`create:encased_shaft`). Other modules may `add` blocks that use one of these
/// block entities in their `register()` (the blocks of the Java mod's lists are
/// found on their own); the lists are read when the registry is applied.
final Map<String, List<String>> kineticValidBlocks = {};

/// The block entity types (manifest key -> factory).
List<BlockEntityTypeSpec> buildKineticBlockEntityTypes(CreateRegistry registry) {
  final defs = {for (final d in kBlockEntityTypes) d.key: d};

  BlockEntityTypeSpec spec(String key, CreateBlockEntity Function(String worldId, BlockPos pos) create) {
    final def = defs[key] ?? (throw StateError('No block entity type $key in the manifest'));
    final valid = _LazyValidBlocks(registry, [for (final b in def.validBlocks) 'create:$b']);
    kineticValidBlocks['create:$key'] = valid;
    return BlockEntityTypeSpec(key: 'create:$key', validBlocks: valid, create: create);
  }

  return [
    spec('simple_kinetic', (w, p) => BracketedKineticBlockEntity(w, p)),
    spec('motor', (w, p) => CreativeMotorBlockEntity(w, p)),
    spec('gearbox', (w, p) => GearboxBlockEntity(w, p)),
    spec('encased_shaft', (w, p) => KineticBlockEntity(w, p)),
    spec('encased_cogwheel', (w, p) => SimpleKineticBlockEntity(w, p)),
    spec('encased_large_cogwheel', (w, p) => SimpleKineticBlockEntity(w, p)),
    spec('adjustable_chain_gearshift', (w, p) => ChainGearshiftBlockEntity(w, p)),
    spec('clutch', (w, p) => ClutchBlockEntity(w, p)),
    spec('gearshift', (w, p) => GearshiftBlockEntity(w, p)),
    spec('turntable', (w, p) => TurntableBlockEntity(w, p)),
    spec('hand_crank', (w, p) => HandCrankBlockEntity(w, p)),
    spec('valve_handle', (w, p) => ValveHandleBlockEntity(w, p)),
    spec('cuckoo_clock', (w, p) => CuckooClockBlockEntity(w, p)),
    spec('steam_engine', (w, p) => SteamEngineBlockEntity(w, p)),
    spec('powered_shaft', (w, p) => PoweredShaftBlockEntity(w, p)),
    spec('flywheel', (w, p) => FlywheelBlockEntity(w, p)),
    spec('water_wheel', (w, p) => WaterWheelBlockEntity(w, p)),
    spec('large_water_wheel', (w, p) => LargeWaterWheelBlockEntity(w, p)),
    spec('sequenced_gearshift', (w, p) => SequencedGearshiftBlockEntity(w, p)),
    spec('rotation_speed_controller', (w, p) => SpeedControllerBlockEntity(w, p)),
    spec('speedometer', (w, p) => SpeedGaugeBlockEntity(w, p)),
    spec('stressometer', (w, p) => StressGaugeBlockEntity(w, p)),
  ];
}
