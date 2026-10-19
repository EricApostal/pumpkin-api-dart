// The striated (layered) ores as a plugin feature (pure core).
//
// The host calls a plugin feature once per chunk and only lets it write that chunk, but a vein of
// size 32 reaches 15 blocks past the chunk where its origin is. So instead of using the origins
// the host drew, every chunk replays the placement of the 3x3 chunks around it (rarity, position
// and height drawn from a seed that depends only on the world seed and the chunk coordinates) and
// writes the part of each vein that lies in its own chunk. Neighbours agree on the vein because
// all random draws of `generateLayeredVein` are independent of the clip.
import 'layered_ore.dart';
import 'worldgen_random.dart';

/// A chunk being generated, in chunk local x/z and absolute y.
abstract interface class OreChunk {
  /// Lowest and highest block y of the world.
  int get minY;
  int get maxY;

  int getState(int localX, int y, int localZ);

  void setState(int localX, int y, int localZ, int stateId);
}

/// Block state questions of the generator (backed by the block registry and tags on the host).
abstract interface class OreStateInfo {
  /// Whether the state matches the rule test (`#minecraft:stone_ore_replaceables`, ...).
  bool matches(int stateId, OreRuleTest test);

  /// The default state id of the block [key], `null` when it does not exist.
  int? stateOf(String key);

  /// Whether the state is solid ground for the heightmap (not air, not a fluid).
  bool isSolid(int stateId);
}

/// One placed feature rule: `create:striated_ores_overworld` / `_nether`.
final class StriatedOreFeature {
  final String key;
  final LayeredOreConfiguration config;

  /// `RarityFilter.onAverageOnceEvery(rarity)`.
  final int rarity;

  /// `HeightRangePlacement.uniform(absolute(minY), absolute(maxY))`.
  final int minHeight, maxHeight;

  /// Mixed into the seed so features do not share random streams.
  final int salt;

  const StriatedOreFeature(this.key, this.config, this.rarity, this.minHeight, this.maxHeight, this.salt);

  /// `AllConfiguredFeatures` + `AllPlacedFeatures`: the overworld feature.
  static final StriatedOreFeature overworld = StriatedOreFeature(
    'create:striated_ores_overworld',
    LayeredOreConfiguration(AllLayerPatterns.overworld, 32, 0),
    18,
    -30,
    70,
    0x5E01,
  );

  /// The nether feature.
  static final StriatedOreFeature nether = StriatedOreFeature(
    'create:striated_ores_nether',
    LayeredOreConfiguration(AllLayerPatterns.nether, 32, 0),
    18,
    40,
    90,
    0x5E02,
  );
}

/// The origin chosen for the placement cell ([cellX], [cellZ]), or `null` when the rarity
/// filter rejects it. Returns the random to continue the vein with.
({int x, int y, int z, LegacyRandom random})? rollOrigin(StriatedOreFeature f, int worldSeed, int cellX, int cellZ) {
  final random = LegacyRandom(mixSeed(worldSeed, cellX, cellZ, f.salt));
  if (random.nextFloat() >= 1.0 / f.rarity) return null; // RarityFilter
  final x = cellX * 16 + random.nextInt(16); // InSquarePlacement
  final z = cellZ * 16 + random.nextInt(16);
  final y = random.nextIntBetweenInclusive(f.minHeight, f.maxHeight); // HeightRangePlacement
  return (x: x, y: y, z: z, random: random);
}

/// Places the part of the striated ores of [feature] that lies in chunk ([chunkX], [chunkZ]).
/// Returns the number of blocks written.
int placeStriatedOresInChunk({
  required StriatedOreFeature feature,
  required int worldSeed,
  required int chunkX,
  required int chunkZ,
  required OreChunk chunk,
  required OreStateInfo info,
}) {
  final clip = VeinClip(chunkX * 16, chunkX * 16 + 15, chunkZ * 16, chunkZ * 16 + 15, chunk.minY, chunk.maxY);
  var written = 0;
  final stateCache = <String, int?>{};
  int? stateOf(String key) => stateCache.putIfAbsent(key, () => info.stateOf(key));

  for (var cz = chunkZ - 1; cz <= chunkZ + 1; cz++) {
    for (var cx = chunkX - 1; cx <= chunkX + 1; cx++) {
      final origin = rollOrigin(feature, worldSeed, cx, cz);
      if (origin == null) continue;

      // `origin.getY() >= worldGenLevel.getHeight(OCEAN_FLOOR_WG, x, z)`: only knowable for origins in
      // this chunk (the terrain of the neighbours is not visible).
      if (cx == chunkX && cz == chunkZ) {
        final lx = origin.x - chunkX * 16, lz = origin.z - chunkZ * 16;
        var solidAbove = false;
        for (var y = origin.y; y <= chunk.maxY; y++) {
          if (info.isSolid(chunk.getState(lx, y, lz))) {
            solidAbove = true;
            break;
          }
        }
        if (!solidAbove) continue;
      }

      written += generateLayeredVein(feature.config, origin.random, origin.x, origin.y, origin.z, clip, (x, y, z, targets, random) {
        final lx = x - chunkX * 16, lz = z - chunkZ * 16;
        final current = chunk.getState(lx, y, lz);
        for (final target in targets) {
          if (!info.matches(current, target.test)) continue; // canPlaceOre (air exposure check is off at 0)
          if (feature.config.discardChanceOnAirExposure > 0) {
            // Not used by Create (0); the neighbour blocks may lie in other chunks.
          }
          final replacement = stateOf(target.stateKey);
          if (replacement == null) continue;
          chunk.setState(lx, y, lz, replacement);
          return true;
        }
        return false;
      });
    }
  }
  return written;
}
