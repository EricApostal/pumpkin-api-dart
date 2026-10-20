// The `aeronautics` module: the blocks, the block entity types, the balloon
// save data and the per-tick wiring.
//
// Java: `Aeronautics` (the mod entry point), `index/AeroBlocks`,
// `index/AeroBlockEntityTypes`, `index/AeroLiftingGasTypes`.
// ignore_for_file: implementation_imports
import 'package:create/create.dart';
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:pumpkin_api/pumpkin_api.dart';

import 'aeronautics_hooks.dart';
import 'config/aero_config.dart';
import 'content/blocks/hot_air/envelope_blocks.dart';
import 'content/blocks/hot_air/hot_air_burner_block.dart';
import 'content/blocks/propeller/gyroscopic_propeller_bearing_block.dart';
import 'content/blocks/propeller/propeller_bearing_block.dart';
import 'content/blocks/propeller/small_propeller_blocks.dart';
import 'hot_air/balloon_map.dart';
import 'simulated_bridge.dart';

/// The saved data of the balloons that unloaded.
final SavedDataType<BalloonSave> balloonSaveType = SavedDataType<BalloonSave>(
  'aeronautics_unloaded_balloons',
  create: BalloonSave.new,
  fromMap: BalloonSave.fromMap,
  toMap: (value) => value.toMap(),
);

/// `aeronautics_unloaded_balloons`: the gas of the balloons whose last heater
/// unloaded.
final class BalloonSave {
  final List<SavedBalloon> balloons = [];

  BalloonSave();

  Map<String, dynamic> toMap() => {
    'balloons': [for (final balloon in balloons) balloon.toMap()],
  };

  static BalloonSave fromMap(Map<String, dynamic> map) {
    final save = BalloonSave();
    final entries = (map['balloons'] as List?) ?? const [];
    for (final entry in entries) {
      save.balloons.add(SavedBalloon.fromMap((entry as Map).cast<String, Object?>()));
    }
    return save;
  }
}

/// The module.
final class AeronauticsModule extends CreateModule {
  @override
  String get name => 'aeronautics';

  @override
  void register(CreateRegistry registry) {
    for (final block in [
      ...buildSmallPropellerBlocks(),
      buildPropellerBearingBlock(),
      buildGyroscopicPropellerBearingBlock(),
      buildHotAirBurnerBlock(),
      ...buildEnvelopeBlocks(),
    ]) {
      registry.block(block);
    }

    void type(String key, List<String> blocks, CreateBlockEntity Function(String worldId, BlockPos pos) create) {
      if (registry.blockEntityTypes.contains(key)) return;
      registry.blockEntityType(
        BlockEntityTypeSpec(key: key, validBlocks: blocks, create: create, tickInterval: 1),
      );
    }

    type(
      'aeronautics:wooden_propeller',
      [SmallPropellerKeys.wooden],
      WoodenPropellerBlockEntity.new,
    );
    type(
      'aeronautics:andesite_propeller',
      [SmallPropellerKeys.andesite],
      AndesitePropellerBlockEntity.new,
    );
    type(
      'aeronautics:smart_propeller',
      [SmallPropellerKeys.smart],
      SmartPropellerBlockEntity.new,
    );
    type(
      propellerBearingKey,
      [propellerBearingKey],
      PropellerBearingBlockEntity.new,
    );
    type(
      gyroscopicPropellerBearingKey,
      [gyroscopicPropellerBearingKey],
      GyroscopicPropellerBearingBlockEntity.new,
    );
    type(
      hotAirBurnerKey,
      [hotAirBurnerKey],
      HotAirBurnerBlockEntity.new,
    );
  }

  @override
  void onLoad(CreateContext ctx) {
    // The balloon save data is written when a balloon unloads or merges.
    AeronauticsHooks.onBalloonsDirty = (worldId) => ctx.savedData.markDirty(worldId, balloonSaveType);

    // Balloons follow the physics assembler, and a split re-checks them.
    ctx.listen(Events.serverTickStart, (server, event) {
      for (final worldId in ctx.worlds.ids.toList()) {
        final world = ctx.worlds.byId(worldId);
        if (world == null) continue;
        SimulatedBridge.install(AeronauticsHooks.of(world).balloonWorld);
        AeronauticsHooks.tickWorld(world, ctx.blockEntities);
        _flushBalloonSave(ctx, world);
      }
    });

    // A block change can open or close a balloon.
    ctx.listen(Events.blockBreak, (server, event) {
      final world = _worldOf(server, event.blockPos);
      if (world == null) return;
      AeronauticsHooks.blockChanged(world, event.blockPos, BState(event.block), BState.air);
      AeronauticsHooks.forgetActor(world.getId(), event.blockPos);
    });

    ctx.listen(Events.blockPlace, (server, event) {
      final world = _worldOf(server, event.blockPos);
      if (world == null) return;
      final id = world.getBlockStateId(pos: event.blockPos);
      AeronauticsHooks.blockChanged(world, event.blockPos, BState.air, HostBlockGetter.stateOfId(id));
    });
  }

  /// The world whose chunk holds [pos]; a server has a handful of dimensions and
  /// a block position is loaded in at most one of them.
  World? _worldOf(Server server, BlockPos pos) {
    for (final world in server.getAllWorlds()) {
      if (world.isLoaded(pos: pos)) return world;
    }
    return null;
  }

  /// Writes the unloaded balloons of [world] into the world's saved data.
  void _flushBalloonSave(CreateContext ctx, World world) {
    final runtime = AeronauticsHooks.of(world);
    final unloaded = runtime.balloons.unloadedBalloons;
    if (unloaded.isEmpty) return;

    final save = ctx.savedData.get(world, balloonSaveType);
    save.balloons
      ..clear()
      ..addAll(unloaded);
    ctx.savedData.markDirty(world.getId(), balloonSaveType);
  }

  @override
  void onUnload() {
    SimulatedBridge.reset();
    AeronauticsHooks.clear();
  }
}

/// The modules of the mod, in load order.
final List<CreateModule> aeronauticsModules = [AeronauticsModule()];

/// The server configuration, for the plugin's config file.
AeroServerConfig get aeronauticsConfig => AeroConfig.server;
