// The kinetics module: the kinetic network (shafts, cogwheels, gearboxes, motors,
// water wheels, ...) of Create. See docs/ARCHITECTURE.md, "Kinetics".
import 'dart:async';

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
import '../api/advancements.dart' show CreateAdvancements;
import '../content/advancement_ids.dart' show AllAdvancements;

final class KineticsModule extends CreateModule {
  @override
  String get name => 'kinetics';

  List<KineticBlockSpec> _specs = const [];
  KineticsRuntime? _runtime;

  /// The provided service, kept so the advancement hooks can be cleared on unload.
  KineticNetworkService? _kinetics;

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
    // `VerticalGearboxItem`: an item that places `create:gearbox` (linked in onLoad).
    registry.item(const ItemRegistration(key: 'create:vertical_gearbox'));
  }

  @override
  void onLoad(CreateContext ctx) {
    final settings = ctx.config.section(
      'kinetics',
      KineticsSettingsMapper.fromMap,
      (v) => v.toMap(),
      const KineticsSettings(),
    );
    final rt = KineticsRuntime(
      settings,
      ctx.blockEntities,
      ctx.worlds,
      ctx.log,
    );
    _runtime = rt;
    final configs = ctx.services.find<cfg.CreateConfigs>();
    if (configs != null) rt.useConfigs(configs);

    for (final spec in _specs) {
      rt.kineticBlocks[spec.block.key] = spec.block;
      final def = spec.def;
      if (def != null) rt.blocks.register(spec.block.key, def);
    }
    rt.blocks.chainDriveBlocks.addAll([
      'create:encased_chain_drive',
      'create:adjustable_chain_gearshift',
    ]);

    ctx.services.provide<KineticNetworkService>(
      KineticNetworkService(rt, [for (final s in _specs) s.block]),
    );
    ctx.services.provide<KineticSpeedLookup>(_SpeedLookup(rt));

    // `WaterWheelBlockEntity.determineAndApplyFlowScore` awards `WATER_WHEEL`/`LAVA_WHEEL` and
    // `StressGaugeBlockEntity.onObserved` awards `STRESSOMETER`(`_MAXED`); both hand the event to
    // these hooks, which nothing installed, so the advancements were unobtainable.
    final kinetics = ctx.services.find<KineticNetworkService>()!;
    _kinetics = kinetics;
    kinetics.onWaterWheelTurns = (wheel, {required lava}) => _awardNear(
      ctx,
      wheel.worldId,
      wheel.pos,
      [lava ? AllAdvancements.lavaWheel : AllAdvancements.waterWheel],
    );
    kinetics.onStressometerObserved = (gauge) => _awardNear(
      ctx,
      gauge.worldId,
      gauge.pos,
      [
        AllAdvancements.stressometer,
        if (gauge.dialTarget == 1) AllAdvancements.stressometerMaxed,
      ],
    );

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
      rt.useRecords.put(
        e.player.getId().asString,
        UseRecord(e.blockPos, face, e.sneaking, itemKey, e.cursor),
      );
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
      final placed = await cogwheelItemUseFirst(
        rt,
        server,
        e,
        key,
        rt.kineticBlocks,
      );
      return placed ? e.copyWith(useResult: ItemUseFirstResult.success) : e;
    });

    ctx.listen(Events.worldUnload, (server, e) {
      if (!e.cancelled) rt.forgetWorld(e.targetWorld.getId());
    });

    // `GearboxBlock.getDrops`: a gearbox with a horizontal axis drops the vertical
    // gearbox item, which the datapack loot table (always `create:gearbox`) cannot
    // express. Keep the rolled loot when the block did not survive the break.
    ctx.host.intercept(Events.lootModify, (server, e) {
      if (e.source != 'block' || e.loot.isEmpty) return e;
      final stateId = e.blockState;
      if (stateId == null) return e;
      final state = rt.states.decode(stateId);
      if (state.block != 'create:gearbox') return e;
      if ((state.axisOf('axis') ?? KAxis.y) == KAxis.y) return e;
      return e.copyWith(loot: [ItemStacks.plain('create:vertical_gearbox')]);
    });

    // The vertical gearbox item places the gearbox block (VerticalGearboxItem).
    if (ctx.ids.of(RegistryKind.items, 'create:vertical_gearbox') != null) {
      try {
        BlockRegistries.host.setBlockItem(
          'create:vertical_gearbox',
          'create:gearbox',
        );
      } on BlockRegistryException catch (e) {
        ctx.log.warn('Could not link the vertical gearbox item: ${e.message}');
      }
    }

    ctx.log.info(
      'Kinetics: ${_specs.length} blocks, max rotation speed ${settings.maxRotationSpeed} RPM'
      '${settings.disableStress ? ', stress disabled' : ''}.',
    );
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
      runtime.log.warn(
        'No payload bus: the stressometer, the sequencer and value settings are not handled.',
      );
    }
    final encasing = runtime.services.find<EncasingRegistry>();
    if (encasing != null) _registerEncasing(encasing, rt);
    final wrench = runtime.services.find<WrenchRegistry>();
    if (wrench != null) {
      installKineticWrench(wrench, rt, [for (final s in _specs) s.block.key]);
    } else {
      runtime.log.warn(
        'No wrench registry: the wrench does not know the kinetic blocks.',
      );
    }
  }

  @override
  void onUnload() {
    _kinetics?.onWaterWheelTurns = null;
    _kinetics?.onStressometerObserved = null;
    _kinetics = null;
    _runtime?.dispose();
    _runtime = null;
  }
}

/// Awards [ids] to the players near the block at [pos] of [worldId]. Java awards the block's owner
/// (`SmartBlockEntity.award` -> `AdvancementBehaviour`); the port tracks no per-block owner, so
/// (like the backtank) the players near the block are awarded.
void _awardNear(
  CreateContext ctx,
  String worldId,
  BlockPos pos,
  List<String> ids,
) {
  final bus = ctx.services.find<PayloadBus>();
  final advancements = ctx.services.find<CreateAdvancements>();
  if (bus == null || advancements == null) return;
  for (final p in bus.roster.players) {
    try {
      final w = p.getWorld();
      final same = w.getId() == worldId;
      w.dispose();
      if (!same) continue;
      final (x, y, z) = p.getPosition();
      final dx = x - (pos.x + 0.5), dy = y - (pos.y + 0.5), dz = z - (pos.z + 0.5);
      if (dx * dx + dy * dy + dz * dz > 16 * 16) continue;
      for (final id in ids) {
        unawaited(advancements.award(p, id));
      }
    } on Object {
      // a handle that went invalid: the player left
    }
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
          encasedShaftState(
            variant,
            KAxis.fromName(c.state['axis']) ?? KAxis.y,
          ),
        ),
      ),
    );
    for (final large in [false, true]) {
      registry.addVariant(
        large ? 'create:large_cogwheel' : 'create:cogwheel',
        EncasedVariant(
          encasedKey:
              'create:${variant}_encased${large ? '_large' : ''}_cogwheel',
          casingItemKey: casing,
          handleEncasing: (c) {
            final worldId = rt.worlds.touch(c.world);
            final level = rt.level(worldId);
            final axis = KAxis.fromName(c.state['axis']) ?? KAxis.y;
            final target = encasedCogwheelState(
              rt.blocks,
              level.stateAt,
              toKPos(c.pos),
              variant,
              large,
              axis,
            );
            return KineticOps.switchToBlockState(rt, worldId, c.pos, target);
          },
        ),
      );
    }
  }
}
