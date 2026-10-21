// The `aeronautics` module: the blocks, the block entity types, the balloon
// save data and the per-tick wiring.
//
// Java: `Aeronautics` (the mod entry point), `index/AeroBlocks`,
// `index/AeroBlockEntityTypes`, `index/AeroLiftingGasTypes`,
// `api/levitite_blend_crystallization/LevititeCrystallizerManager`,
// `CrystallizationWorldSaveData`, `network/packets/LevititeCatalystCrystallizationPacket`.
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:math' show Random;

import 'package:create/create.dart';
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/pos.dart' show Pos, posFromLong;
import 'package:create/src/kinetics/geometry.dart' show KState;
import 'package:create/src/kinetics/runtime.dart' show KineticsRuntime;
import 'package:pumpkin_api/pumpkin_api.dart';

import 'aeronautics_hooks.dart';
import 'config/aero_config.dart';
import 'content/items/item_behaviour.dart';
import 'hot_air/balloon_map.dart';
import 'index/aero_java_order.dart';
import 'index/aero_registry.dart';
import 'levitite/levitite_crystallization.dart';
import 'simulated_bridge.dart';

/// The saved data of the balloons that unloaded.
final SavedDataType<BalloonSave> balloonSaveType = SavedDataType<BalloonSave>(
  'aeronautics_unloaded_balloons',
  create: BalloonSave.new,
  fromMap: BalloonSave.fromMap,
  toMap: (value) => value.toMap(),
);

/// The saved data of the crystallising blend (`aeronautics_levitite_data`,
/// `api/levitite_blend_crystallization/CrystallizationWorldSaveData.java:16`).
final SavedDataType<LevititeSave> levititeSaveType = SavedDataType<LevititeSave>(
  'aeronautics_levitite_data',
  create: LevititeSave.new,
  fromMap: LevititeSave.fromMap,
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

/// `CrystallizationWorldSaveData`: the blend tickers of one world, saved under
/// `Levitite Manager Data`.
final class LevititeSave {
  final List<Map<String, Object?>> tickers = [];

  LevititeSave();

  Map<String, dynamic> toMap() => {'Levitite Manager Data': tickers};

  static LevititeSave fromMap(Map<String, dynamic> map) {
    final save = LevititeSave();
    final entries = (map['Levitite Manager Data'] as List?) ?? const [];
    for (final entry in entries) {
      if (entry is Map) save.tickers.add(entry.cast<String, Object?>());
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
    registerAeronautics(
      registry,
      lookup: <T>(String worldId, (int, int, int) pos) {
        final store = AeronauticsHooks.store;
        if (store == null) return null;
        final entity = store.at(worldId, BlockPos(x: pos.$1, y: pos.$2, z: pos.$3));
        return entity is T ? entity as T : null;
      },
    );
    checkAeroStateProperties(registry);
  }

  /// Throws unless every block of [registry] has the state properties the Java
  /// gives it (`AeroJavaOrder.stateProperties`).
  ///
  /// A property the Java does not have -- `lit` on `aeronautics:adjustable_burner`
  /// was one -- multiplies the block's states, and the base state id of every
  /// block after it moves with them, so a client that has the Java mods numbers
  /// the block's states differently forever. `CreateBlock` is behind the
  /// wasm-only `pumpkin_api`, so this cannot be a VM test; it runs here, on the
  /// real path, before anything is applied.
  static void checkAeroStateProperties(CreateRegistry registry) {
    for (final entry in registry.blocks.entries) {
      final key = entry.key;
      final expected = AeroJavaOrder.propertiesOf(key);
      if (expected == null) {
        throw StateError(
          '`$key` is registered but not in the Java order table '
          '(`aero_java_order.dart`): add it, with its state properties, so the '
          'ids of the blocks after it stay the Java ones.',
        );
      }
      final actual = [for (final property in entry.value.definition.properties) property.name];
      if (actual.length == expected.length && actual.every(expected.containsKey)) continue;
      throw StateError(
        'The state properties of `$key` are $actual, but the Java has '
        '${expected.keys.toList()} (`aero_java_order.dart`): the states of this '
        'block and the base state id of every block after it would differ from '
        'the Java.',
      );
    }
  }

  @override
  void onLoad(CreateContext ctx) {
    AeronauticsHooks.store = ctx.blockEntities;
    LevititeCrystallizationRules.breakBlocksOnCrystallize = AeroConfig.server.blocks.breakBlocksOnCrystallize;

    // The balloon save data is written when a balloon unloads or merges.
    AeronauticsHooks.onBalloonsDirty = (worldId) => ctx.savedData.markDirty(worldId, balloonSaveType);

    // The levitite blends are ticked once per world tick, like
    // `LevititeCrystallizerManager.tick(level)` in `AeronauticsCommonEvents`.
    ctx.onWorldTick((t) => _tickLevitite(ctx, t), label: 'aeronautics#levitite');

    // The two item components (`mixin/levitite/ItemEntityMixin`,
    // `mixin/item_converter/ItemEntityMixin`).
    ItemBehaviour().install(ctx);

    // The levitite crystallisation payload (`AeroPacketManager.java:11-13`).
    ctx.listen(Events.playerCustomPayload, (server, event) async {
      if (event.channel != 'aeronautics:levitite_blend_crystallize') return;
      await _handleCrystallize(event.player, event.data);
    });

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

  /// `LevititeCrystallizerManager.tick`: advances the world's blend tickers.
  ///
  /// The tickers of a world are loaded from its saved data the first time the
  /// world ticks (`CrystallizationWorldSaveData.get(level)`), and the data is
  /// marked dirty when a ticker is added or a blend crystallises, exactly where
  /// Java calls `data.setDirty()`.
  void _tickLevitite(CreateContext ctx, WorldTick t) {
    final world = t.world;
    final id = t.worldId;
    final view = _LevititeWorld(world, id);

    if (_loadedLevititeWorlds.add(id)) {
      final save = ctx.savedData.get(world, levititeSaveType);
      LevititeCrystallizerManager.loadData(id, save.tickers);
    }

    LevititeCrystallizerManager.tick(view, view.random);

    final save = ctx.savedData.get(world, levititeSaveType);
    save.tickers
      ..clear()
      ..addAll(LevititeCrystallizerManager.saveData(id));
    ctx.savedData.markDirty(id, levititeSaveType);
  }

  /// The worlds whose tickers were read from their saved data.
  final Set<String> _loadedLevititeWorlds = {};

  /// `LevititeCatalystCrystallizationPacket.handle`.
  ///
  /// The payload is `BlockPos` (one long) then `CatnipStreamCodecs.HAND` (a
  /// bool: true is the main hand).
  Future<void> _handleCrystallize(Player player, List<int> data) async {
    final reader = PacketReader(data);
    final packed = reader.readLong();
    final mainHand = reader.readBool();
    final pos = posFromLong(packed);

    final hand = mainHand ? Hand.right : Hand.left;
    final inventory = player.getInventory();
    final item = inventory.getItemInHand(hand: hand);
    if (item == null) return;

    final key = await item.getRegistryKey();
    if (!isCatalyzer(key, inTag: Tags.item)) return;

    final world = player.getWorld();
    final id = world.getId();
    final soul = isSoulCatalyzer(key, inTag: Tags.item);
    final context = soul ? const SoulCrystalPropagationContext() : const StandardCrystalPropagationContext();

    // `LevititeBlendHelper.addLevititeBlendTicker(level, pos, false, false,
    // context.getContextForSpread(level, pos))`.
    final view = _LevititeWorld(world, id);
    LevititeCrystallizerManager.addTicker(
      view,
      pos,
      requiresCatalyst: false,
      isDormant: false,
      context: context.getContextForSpread(view, pos),
      random: view.random,
    );
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
    AeronauticsHooks.store = null;
    LevititeCrystallizerManager.clear();
    _loadedLevititeWorlds.clear();
  }
}

/// `LevititeBlendHelper` over a host world.
final class _LevititeWorld implements LevititeWorld {
  _LevititeWorld(this.world, this.id);

  final World world;

  @override
  final String id;

  @override
  late final Random random = Random(world.getId().hashCode ^ world.getName().hashCode);

  BState _stateAt(Pos pos) =>
      HostBlockGetter.stateOfId(world.getBlockStateId(pos: BlockPos(x: pos.$1, y: pos.$2, z: pos.$3)));

  @override
  String blockKeyAt(Pos pos) => _stateAt(pos).key;

  @override
  String? blockPropertyAt(Pos pos, String name) => _stateAt(pos)[name];

  @override
  bool blockHasTag(Pos pos, String tag) => Tags.block(_stateAt(pos).key, tag);

  @override
  String fluidKeyAt(Pos pos) {
    final state = _stateAt(pos);
    if (state.key == 'aeronautics:levitite_blend') return levititeBlendFluid;
    return 'minecraft:empty';
  }

  @override
  void setBlock(Pos pos, String blockKey) {
    final id = KineticsRuntime.instance.states.idOf(KState(blockKey));
    if (id == null) return;
    unawaited(
      world.setBlockState(
        pos: BlockPos(x: pos.$1, y: pos.$2, z: pos.$3),
        state: id,
        updateFlags: BlockUpdateFlags.normal,
      ),
    );
  }

  @override
  void playSound(String soundKey, Pos pos, {double volume = 1, double pitch = 1}) {
    world.playCustomSound(
      soundName: soundKey,
      category: SoundCategory.blocks,
      pos: (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5),
      volume: volume,
      pitch: pitch,
    );
  }

  @override
  void spawnParticles(String particle, Pos pos, int count) {
    // `sendParticles(type, x+0.5, y+0.5, z+0.5, count, 0.3, 0.3, 0.3, 0)`.
    world.spawnPluginParticle(
      key: particle,
      pos: (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5),
      delta: (0.3, 0.3, 0.3),
      speed: 0,
      count: count,
      options: const [],
    );
  }

  @override
  void awardAdvancementNearby(String advancement, Pos pos) {
    // TODO(parity): `AeroAdvancements.UNIDENTIFIED_FLOATING_OBJECT.awardToNearby`
    // and `NOW_AVAILABLE_IN_PINK` award to players within a radius; the host's
    // `Advancements` has no "award nearby" call, only a per-player grant.
  }

  @override
  void destroyBlock(Pos pos) {
    // `BlockHelper.destroyBlock(level, pos, 1.0F)`: no drop, no xp.
    setBlock(pos, 'minecraft:air');
  }

  @override
  void markDirty() {
    // TODO(parity): the saved data is written on the plugin's save interval;
    // `CrystallizationWorldSaveData.setDirty()` has no host equivalent, so the
    // save is unconditional (`_flushLevitite`).
  }
}

/// The modules of the mod, in load order.
final List<CreateModule> aeronauticsModules = [AeronauticsModule()];

/// The server configuration, for the plugin's config file.
AeroServerConfig get aeronauticsConfig => AeroConfig.server;
