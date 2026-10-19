// The kinetics module: the kinetic network (shafts, cogwheels, gearboxes, motors,
// water wheels, ...) of Create. See docs/ARCHITECTURE.md, "Kinetics".
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/module.dart';
import '../core/registry.dart';
import 'block_factory.dart';
import 'geometry.dart';
import 'kinetic_block_entity.dart';
import 'kinetic_blocks_a.dart' show encasedCogwheelState, encasedShaftState;
import 'kinetic_blocks.dart';
import '../api/payloads.dart';
import '../api/decoration.dart' show EncasedVariant, EncasingRegistry;
import '../api/equipment.dart' show KineticSpeedLookup;
import '../api/wrenchable.dart';
import 'networking.dart';
import 'placement_helper_host.dart';
import '../api/config.dart' as cfg;
import 'runtime.dart';
import 'service.dart';
import 'settings.dart';
import 'use_records.dart';
import 'wrench_integration.dart';

final class KineticsModule extends CreateModule {
  @override
  String get name => 'kinetics';

  List<KineticBlockSpec> _specs = const [];
  KineticsRuntime? _runtime;

  /// The blocks this module registers (after `register`).
  List<KineticBlockSpec> get specs => _specs;

  @override
  void register(CreateRegistry registry) {
    _specs = buildKineticBlocks();
    for (final spec in _specs) {
      registry.block(spec.block);
    }
    for (final type in buildKineticBlockEntityTypes(registry)) {
      registry.blockEntityType(type);
    }
  }

  @override
  void onLoad(CreateContext ctx) {
    final settings = ctx.config.section(
      'kinetics',
      KineticsSettingsMapper.fromMap,
      (v) => v.toMap(),
      const KineticsSettings(),
    );
    final rt = KineticsRuntime(settings, ctx.blockEntities, ctx.worlds, ctx.log);
    _runtime = rt;
    final configs = ctx.services.find<cfg.CreateConfigs>();
    if (configs != null) rt.useConfigs(configs);

    for (final spec in _specs) {
      rt.kineticBlocks[spec.block.key] = spec.block;
      final def = spec.def;
      if (def != null) rt.blocks.register(spec.block.key, def);
    }
    rt.blocks.chainDriveBlocks.addAll(['create:encased_chain_drive', 'create:adjustable_chain_gearshift']);

    ctx.services.provide<KineticNetworkService>(KineticNetworkService(rt, [for (final s in _specs) s.block]));
    ctx.services.provide<KineticSpeedLookup>(_SpeedLookup(rt));

    // Remember the last block use of every player: the host's placed event carries
    // neither the clicked face nor the item.
    ctx.listen(Events.playerUseBlock, (server, e) async {
      final String itemKey;
      try {
        itemKey = await e.item.getRegistryKey();
      } catch (_) {
        return;
      }
      final face = Dir.fromName(e.face.name);
      if (face == null) return;
      rt.useRecords.put(e.player.getId().asString, UseRecord(e.blockPos, face, e.sneaking, itemKey, e.cursor));
    });

    // CogwheelBlockItem.onItemUseFirst: place the next cogwheel diagonally.
    ctx.host.intercept(Events.itemUseFirst, (server, e) async {
      if (e.useResult != ItemUseFirstResult.pass) return e;
      final String key;
      try {
        key = await e.stack.getRegistryKey();
      } catch (_) {
        return e;
      }
      if (key != 'create:cogwheel' && key != 'create:large_cogwheel') return e;
      final placed = await cogwheelItemUseFirst(rt, server, e, key, rt.kineticBlocks);
      return placed ? e.copyWith(useResult: ItemUseFirstResult.success) : e;
    });

    ctx.listen(Events.worldUnload, (server, e) {
      if (!e.cancelled) rt.forgetWorld(e.targetWorld.getId());
    });

    // The vertical gearbox item places the gearbox block (VerticalGearboxItem).
    if (ctx.ids.of(RegistryKind.items, 'create:vertical_gearbox') != null) {
      try {
        BlockRegistries.host.setBlockItem('create:vertical_gearbox', 'create:gearbox');
      } on BlockRegistryException catch (e) {
        ctx.log.warn('Could not link the vertical gearbox item: ${e.message}');
      }
    }

    ctx.log.info('Kinetics: ${_specs.length} blocks, max rotation speed ${settings.maxRotationSpeed} RPM'
        '${settings.disableStress ? ', stress disabled' : ''}.');
  }

  /// Binds to the services of modules that load after this one (wrench registry,
  /// payload bus, configs) once everything is loaded.
  @override
  void onServerLoaded(CreateRuntime runtime) {
    final rt = _runtime;
    if (rt == null) return;
    final configs = runtime.services.find<cfg.CreateConfigs>();
    if (configs != null) rt.useConfigs(configs);
    final bus = runtime.services.find<PayloadBus>();
    if (bus != null) {
      bindKineticPackets(bus);
    } else {
      runtime.log.warn('No payload bus: the stressometer, the sequencer and value settings are not handled.');
    }
    final encasing = runtime.services.find<EncasingRegistry>();
    if (encasing != null) _registerEncasing(encasing, rt);
    final wrench = runtime.services.find<WrenchRegistry>();
    if (wrench != null) {
      installKineticWrench(wrench, rt, [for (final s in _specs) s.block.key]);
    } else {
      runtime.log.warn('No wrench registry: the wrench does not know the kinetic blocks.');
    }
  }

  @override
  void onUnload() {
    _runtime?.dispose();
    _runtime = null;
  }
}

/// `KineticSpeedLookup` for the equipment module (the backtank).
final class _SpeedLookup implements KineticSpeedLookup {
  final KineticsRuntime rt;

  _SpeedLookup(this.rt);

  @override
  double? speedAt(String worldId, (int, int, int) pos) {
    final be = rt.store.at(worldId, BlockPos(x: pos.$1, y: pos.$2, z: pos.$3));
    return be is KineticBlockEntity ? be.speed : null;
  }
}

/// `EncasingRegistry.addVariant` for shafts and cogwheels (the casing items
/// encase them with a right click).
void _registerEncasing(EncasingRegistry registry, KineticsRuntime rt) {
  for (final variant in ['andesite', 'brass']) {
    final casing = 'create:${variant}_casing';
    registry.addVariant(
      'create:shaft',
      EncasedVariant(
        encasedKey: 'create:${variant}_encased_shaft',
        casingItemKey: casing,
        handleEncasing: (c) => KineticOps.switchToBlockState(
          rt,
          rt.worlds.touch(c.world),
          c.pos,
          encasedShaftState(variant, KAxis.fromName(c.state['axis']) ?? KAxis.y),
        ),
      ),
    );
    for (final large in [false, true]) {
      registry.addVariant(
        large ? 'create:large_cogwheel' : 'create:cogwheel',
        EncasedVariant(
          encasedKey: 'create:${variant}_encased${large ? '_large' : ''}_cogwheel',
          casingItemKey: casing,
          handleEncasing: (c) {
            final worldId = rt.worlds.touch(c.world);
            final level = rt.level(worldId);
            final axis = KAxis.fromName(c.state['axis']) ?? KAxis.y;
            final target = encasedCogwheelState(rt.blocks, level.stateAt, toKPos(c.pos), variant, large, axis);
            return KineticOps.switchToBlockState(rt, worldId, c.pos, target);
          },
        ),
      );
    }
  }
}
