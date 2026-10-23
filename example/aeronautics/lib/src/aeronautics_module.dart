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
import 'package:create/src/contraptions/entity/contraption_entity_ticking.dart'
    show ContraptionEntityTicking;
import 'package:create/src/contraptions/entity/host_contraption_entities.dart'
    show ContraptionHostHooks;
import 'package:create/src/kinetics/geometry.dart' show KState;
import 'package:create/src/kinetics/runtime.dart' show KineticsRuntime;
import 'package:pumpkin_api/pumpkin_api.dart';

import 'aeronautics_hooks.dart';
import 'aeronautics_runtime.dart';
import 'config/aero_config.dart';
import 'content/items/item_behaviour.dart';
import 'content/blocks/propeller/propeller_bearing_contraption_entity.dart';
import 'data/aeronautics_data.dart';
import 'hot_air/balloon_map.dart';
import 'hot_air/balloon_save.dart';
import 'index/aero_java_order.dart';
import 'index/aero_kinetics.dart' show registerAeroKinetics;
import 'index/aero_registry.dart';
import 'levitite/levitite_crystallization.dart';
import 'simulated_bridge.dart';

/// The saved data of the crystallising blend (`aeronautics_levitite_data`,
/// `api/levitite_blend_crystallization/CrystallizationWorldSaveData.java:16`).
final SavedDataType<LevititeSave> levititeSaveType = SavedDataType<LevititeSave>(
  'aeronautics_levitite_data',
  create: LevititeSave.new,
  fromMap: LevititeSave.fromMap,
  toMap: (value) => value.toMap(),
);

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

  /// The mod's data pack and the recipe contribution to the host.
  final AeronauticsData data = AeronauticsData();

  @override
  Future<void> onServerLoaded(CreateRuntime runtime) => data.onServerLoaded(runtime);

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
    checkAeroFluidPairs(registry);
  }

  /// Throws unless every still fluid names a flowing variant that is registered,
  /// and that variant follows it in id order.
  ///
  /// The host rejects a still fluid whose flowing variant never registers
  /// (`FluidRegistrationError::UnknownFluid`) and numbers fluids in registration
  /// order, so a pair split across the two rules would fail the load or shift the
  /// ids. `CreateRegistry` is behind the wasm-only `pumpkin_api`, so this runs
  /// here, on the real path, rather than in a VM test.
  static void checkAeroFluidPairs(CreateRegistry registry) {
    final problems = fluidPairProblems({
      for (final entry in registry.fluids.entries) entry.key: entry.value.flowingVariant,
    });
    if (problems.isEmpty) return;
    throw StateError(
      'The fluid registration is not the Java pair: ${problems.join('; ')} '
      '(`aero_java_order.dart`).',
    );
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

    // The mod's data pack (`data/aeronautics/**`, `data/minecraft/tags/**`) and its `create:*`
    // recipes, which the host cannot read out of a pack.
    data.onLoad(ctx);

    // The kinetic rules of the propeller family (`IRotate`). A Pumpkin plugin
    // owns its own `KineticsRuntime`, so they are registered on that instance;
    // without them `defFor` is null for every aeronautics key, no shaft
    // connects to a propeller bearing and its `speed` stays 0, so the sails
    // never turn into thrust.
    if (KineticsRuntime.isLoaded) {
      registerAeroKinetics(KineticsRuntime.instance);
    } else {
      ctx.log.warn('The kinetic runtime is not loaded: the propellers will not turn.');
    }

    // The balloon save data is written when a balloon unloads or merges.
    AeronauticsHooks.onBalloonsDirty = (worldId) => ctx.savedData.markDirty(worldId, balloonSaveType);

    // The levitite blends are ticked once per world tick, like
    // `LevititeCrystallizerManager.tick(level)` in `AeronauticsCommonEvents`.
    ctx.onWorldTick((t) => _tickLevitite(ctx, t), label: 'aeronautics#levitite');

    // The two item components (`mixin/levitite/ItemEntityMixin`,
    // `mixin/item_converter/ItemEntityMixin`).
    ItemBehaviour().install(ctx);

    // The advancement ids (`Aeronautics.java`'s `AeroAdvancements.init`), the gust spawn hook and
    // the `aeronautics:gust` tick. Without this call no gust is spawned and no aeronautics
    // advancement exists — the code is in the artifact but unreachable.
    AeroRuntime.install(ctx);

    // `PropellerBearingBlockEntity.assemble` builds a `PropellerBearingContraptionEntity`
    // (`PropellerBearingBlockEntity.java:350-355`), the subclass that carries the gyroscopic tilt:
    // without the kind the client would receive a plain `create:stationary_contraption` and no tilt
    // transform, and its entity type would never be ticked.
    ContraptionHostHooks.registerControlledEntity(
      key: propellerBearingContraptionEntityKey,
      type: PropellerBearingContraptionEntity,
      create: PropellerBearingContraptionEntity.new,
    );
    ctx.tickContraptionEntityTypes(const [propellerBearingContraptionEntityKey]);

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
        // `BalloonLevelSavedData.get` on every tick: reads the saved balloons back into the map
        // once per world, then keeps the save's list in step (unloaded balloons *and* every live
        // one — the old path wrote only the unloaded list, which is how balloon gas was lost on a
        // restart).
        AeroBalloonSave.pump(ctx, world);
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

  @override
  void onUnload() {
    SimulatedBridge.reset();
    AeroRuntime.clear();
    AeroBalloonSave.clear();
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
    // `AeroAdvancements.UNIDENTIFIED_FLOATING_OBJECT.awardToNearby` and `NOW_AVAILABLE_IN_PINK`
    // (`LevititeCrystalPropagationContext.java:36`, `LevititeSoulCrystalPropagationContext.java:36`):
    // plants a crystal next to another player, so the players near it see the toast.
    AeroRuntime.awardNearby(world, pos, advancement);
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
