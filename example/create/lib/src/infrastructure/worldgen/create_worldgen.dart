// Registers Create's world generation with the host (`AllBiomeModifiers`, `AllPlacedFeatures`,
// `AllConfiguredFeatures`): zinc ore as a server placed ore, the striated ores as plugin features.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/host_bridge.dart';
import '../config/create_configs.dart';
import 'layered_ore.dart';
import 'striated_ores.dart';
import 'worldgen_random.dart';

/// Adapts a host [ChunkBuffer].
final class _HostChunk implements OreChunk {
  final ChunkBuffer buffer;
  final int _minY;
  final int _maxY;

  _HostChunk(this.buffer) : _minY = buffer.getMinY(), _maxY = buffer.getMinY() + buffer.getHeight() - 1;

  @override
  int get minY => _minY;

  @override
  int get maxY => _maxY;

  @override
  int getState(int localX, int y, int localZ) => buffer.getBlockStateId(x: localX, y: y, z: localZ);

  @override
  void setState(int localX, int y, int localZ, int stateId) =>
      buffer.setBlockStateId(x: localX, y: y, z: localZ, stateId: stateId);
}

/// Block state answers from the host, memoised (tags and registry lookups are host calls).
final class HostOreStateInfo implements OreStateInfo {
  final Map<(int, OreRuleTest), bool> _matches = {};
  final Map<int, bool> _solid = {};
  final Map<String, int?> _states = {};

  static const Set<String> _notSolid = {
    'minecraft:air',
    'minecraft:cave_air',
    'minecraft:void_air',
    'minecraft:water',
    'minecraft:lava',
    'minecraft:bubble_column',
  };

  @override
  bool matches(int stateId, OreRuleTest test) =>
      _matches.putIfAbsent((stateId, test), () => Tags.blockState(stateId, test.tag));

  @override
  int? stateOf(String key) => _states.putIfAbsent(key, () => BlockRegistry.resolveState(key));

  @override
  bool isSolid(int stateId) => _solid.putIfAbsent(stateId, () => !_notSolid.contains(BlockStates.blockKey(stateId)));
}

/// The per-world seed of the striated ores (the host gives plugin features no world seed). It is
/// created on first use and kept in the world's persistent data so a world keeps its veins.
final class WorldgenSeeds {
  static const String _key = 'worldgen_seed';
  final Map<String, int> _seeds = {};

  int? lookup(String worldId) => _seeds[worldId];

  /// Reads or creates the seed of [world].
  int ensure(World world) {
    final id = world.getId();
    final known = _seeds[id];
    if (known != null) return known;
    final data = world.persistentData('create');
    var seed = int.tryParse(data.getString(_key) ?? '');
    if (seed == null) {
      final r = math.Random.secure();
      seed = (r.nextInt(1 << 30) << 32) ^ r.nextInt(1 << 30) ^ DateTime.now().microsecondsSinceEpoch;
      data.setString(_key, '$seed');
    }
    _seeds[id] = seed;
    return seed;
  }
}

/// Registers Create's features. Call once, from `onLoad`, with the loaded config.
final class CreateWorldgen {
  final CreateConfigs configs;
  final Logger log;
  final WorldgenSeeds seeds = WorldgenSeeds();
  final HostOreStateInfo _info = HostOreStateInfo();

  CreateWorldgen(this.configs, this.log);

  /// `AllBiomeModifiers` + the features. Does nothing when `worldgen.disableWorldGen` is set (the
  /// `ConfigPlacementFilter` of the Java mod checks the same flag when a chunk generates; the host
  /// cannot evaluate a plugin filter, so the flag is read at load).
  void register(Context context) {
    if (configs.common.worldGen.disable.value) {
      log.info('worldgen.disableWorldGen is set: Create adds no ores');
      return;
    }
    try {
      WorldgenFeatures.registerOre(
        'create:zinc_ore',
        targets: const [
          OreTarget(target: '#minecraft:stone_ore_replaceables', state: 'create:zinc_ore'),
          OreTarget(target: '#minecraft:deepslate_ore_replaceables', state: 'create:deepslate_zinc_ore'),
        ],
        size: 12,
        discardChanceOnAirExposure: 0,
      );
      // CountPlacement.of(8), InSquare, uniform(-63, 70).
      WorldgenFeatures.addToBiomes(
        'create:zinc_ore',
        const FeaturePlacement(
          biomes: ['#minecraft:is_overworld'],
          step: GenerationStep.undergroundOres,
          count: 8,
          height: FeatureHeight(-63, 70),
        ),
      );
      _registerStriated(context, StriatedOreFeature.overworld, '#minecraft:is_overworld');
      _registerStriated(context, StriatedOreFeature.nether, '#minecraft:is_nether');
    } on HostException catch (e) {
      log.error('Could not register the world generation: ${e.message}');
    }
  }

  void _registerStriated(Context context, StriatedOreFeature feature, String biomes) {
    WorldgenFeatures.register(feature.key);
    // Every chunk calls the feature once (no rarity): the rarity, position and height are drawn by
    // `rollOrigin` for the chunk and its neighbours so veins cross chunk borders.
    WorldgenFeatures.addToBiomes(
      feature.key,
      FeaturePlacement(
        biomes: [biomes],
        step: GenerationStep.undergroundOres,
        count: 1,
        height: FeatureHeight(feature.minHeight, feature.maxHeight),
      ),
    );
    context.onFeaturePlace(feature.key, (server, event) {
      // `ConfigPlacementFilter` reads the flag for every placement, so a change made through
      // `/catnip config` stops (and re-enables) the striated ores without a restart. Zinc is
      // placed by the host, so it can only be skipped at registration.
      if (configs.common.worldGen.disable.value) return;
      try {
        final worldId = event.targetWorld.getId();
        final seed = seeds.lookup(worldId) ?? _ensureSeed(event.targetWorld, event.seed);
        placeStriatedOresInChunk(
          feature: feature,
          worldSeed: seed,
          chunkX: event.chunkX,
          chunkZ: event.chunkZ,
          chunk: _HostChunk(event.chunk),
          info: _info,
        );
      } on Object catch (e, s) {
        log.error('Placing ${feature.key} in chunk ${event.chunkX},${event.chunkZ} failed', error: e, stackTrace: s);
      }
    });
  }

  int _ensureSeed(World world, int fallback) {
    try {
      return seeds.ensure(world);
    } on Object {
      // Persistent data not reachable from the generation thread: a seed from the world name keeps
      // the veins consistent across chunks, only not random per world.
      return mixSeed(world.getId().codeUnits.fold(7, (h, c) => h * 31 + c));
    }
  }

  /// Reads or creates the seeds of all loaded worlds and of worlds loaded later.
  void initSeeds(Context context, Server server) {
    for (final w in server.getAllWorlds()) {
      seeds.ensure(w);
    }
    context.listen(Events.worldLoad, (server, event) {
      seeds.ensure(event.targetWorld);
    });
  }
}
