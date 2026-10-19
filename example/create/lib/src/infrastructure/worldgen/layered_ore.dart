// `LayerPattern`, `AllLayerPatterns` and `LayeredOreFeature` (pure). The vein
// algorithm is a port of the Java feature; instead of writing to a level it reports
// the blocks to place through a callback and can be clipped to one chunk (a plugin
// feature only sees the chunk it generates, see `striated_ores.dart`).
import 'dart:math' as math;

import 'worldgen_random.dart';

/// What a [BlockReplacement] replaces: the `RuleTest` of the Java mod.
enum OreRuleTest {
  /// `#minecraft:stone_ore_replaceables`
  stoneOreReplaceables('minecraft:stone_ore_replaceables'),

  /// `#minecraft:deepslate_ore_replaceables`
  deepslateOreReplaceables('minecraft:deepslate_ore_replaceables'),

  /// `#minecraft:base_stone_nether`
  baseStoneNether('minecraft:base_stone_nether');

  const OreRuleTest(this.tag);

  final String tag;
}

/// `OreConfiguration.TargetBlockState` / Create's `BlockReplacement`: replaces blocks matching
/// [test] with the default state of the block [stateKey].
final class BlockReplacement {
  final OreRuleTest test;
  final String stateKey;

  const BlockReplacement(this.test, this.stateKey);
}

/// `LayerPattern.Layer`.
final class Layer {
  final List<List<BlockReplacement>> targets;
  final int minSize;
  final int maxSize;
  final int weight;

  const Layer(this.targets, this.minSize, this.maxSize, this.weight);

  /// `rollBlock`: draws a target only when there is more than one (like Java).
  List<BlockReplacement> rollBlock(LegacyRandom random) {
    if (targets.length == 1) return targets[0];
    return targets[random.nextInt(targets.length)];
  }
}

/// `LayerPattern`.
final class LayerPattern {
  final List<Layer> layers;

  const LayerPattern(this.layers);

  /// `rollNext`: a weighted layer different from [previous].
  Layer rollNext(Layer? previous, LegacyRandom random) {
    var totalWeight = 0;
    for (final layer in layers) {
      if (!identical(layer, previous)) totalWeight += layer.weight;
    }
    var rolled = random.nextInt(totalWeight);
    for (final layer in layers) {
      if (identical(layer, previous)) continue;
      rolled -= layer.weight;
      if (rolled < 0) return layer;
    }
    return layers.last;
  }

  static LayerPatternBuilder builder() => LayerPatternBuilder();
}

/// `LayerPattern.Builder`.
final class LayerPatternBuilder {
  final List<Layer> _layers = [];
  bool _netherMode = false;

  LayerPatternBuilder inNether() {
    _netherMode = true;
    return this;
  }

  LayerPatternBuilder layer(void Function(LayerBuilder l) configure) {
    final b = LayerBuilder(_netherMode);
    configure(b);
    _layers.add(b.build());
    return this;
  }

  LayerPattern build() => LayerPattern(_layers);
}

/// `LayerPattern.Layer.Builder`.
final class LayerBuilder {
  final bool netherMode;
  final List<List<BlockReplacement>> _targets = [];
  int _minSize = 1, _maxSize = 1, _weight = 1;

  LayerBuilder(this.netherMode);

  /// `block(Block)`: [key] in stone and deepslate (nether mode: in nether base stone).
  LayerBuilder block(String key) {
    if (netherMode) {
      _targets.add([BlockReplacement(OreRuleTest.baseStoneNether, key)]);
      return this;
    }
    return blocks(key, key);
  }

  /// `passiveBlock()`: stone and deepslate.
  LayerBuilder passiveBlock() => blocks('minecraft:stone', 'minecraft:deepslate');

  /// `blocks(stone, deepslate)`.
  LayerBuilder blocks(String stone, String deepslate) {
    _targets.add([
      BlockReplacement(OreRuleTest.stoneOreReplaceables, stone),
      BlockReplacement(OreRuleTest.deepslateOreReplaceables, deepslate),
    ]);
    return this;
  }

  LayerBuilder weight(int w) {
    _weight = w;
    return this;
  }

  LayerBuilder size(int min, int max) {
    _minSize = min;
    _maxSize = max;
    return this;
  }

  Layer build() => Layer(_targets, _minSize, _maxSize, _weight);
}

/// `AllLayerPatterns`.
abstract final class AllLayerPatterns {
  static final LayerPattern cinnabar = LayerPattern.builder()
      .layer((l) => l.weight(2).block('create:crimsite').size(2, 5))
      .layer((l) => l.weight(1).block('minecraft:tuff').block('minecraft:deepslate').size(2, 3))
      .layer((l) => l.weight(1).blocks('minecraft:deepslate', 'minecraft:tuff').size(2, 2))
      .layer((l) => l.weight(1).block('create:limestone').size(1, 2))
      .build();

  static final LayerPattern magnetite = LayerPattern.builder()
      .layer((l) => l.weight(2).block('create:asurine').size(2, 5))
      .layer((l) => l.weight(1).block('minecraft:tuff').block('minecraft:deepslate').size(2, 3))
      .layer((l) => l.weight(1).blocks('minecraft:deepslate', 'minecraft:tuff').size(2, 2))
      .layer((l) => l.weight(1).block('minecraft:calcite').size(1, 2))
      .build();

  static final LayerPattern ochrestone = LayerPattern.builder()
      .layer((l) => l.weight(2).block('create:ochrum').size(2, 5))
      .layer((l) => l.weight(2).block('minecraft:tuff').block('minecraft:deepslate').size(2, 3))
      .layer((l) => l.weight(2).block('minecraft:dripstone_block').size(1, 2))
      .build();

  static final LayerPattern malachite = LayerPattern.builder()
      .layer((l) => l.weight(4).block('create:veridium').size(2, 5))
      .layer((l) => l.weight(2).block('minecraft:tuff').block('minecraft:andesite').size(2, 3))
      .layer((l) => l.weight(2).blocks('minecraft:tuff', 'minecraft:andesite').size(2, 2))
      .layer((l) => l.weight(3).block('minecraft:smooth_basalt').size(1, 2))
      .build();

  static final LayerPattern scoria = LayerPattern.builder()
      .layer((l) => l.weight(2).block('create:scoria').size(2, 5))
      .layer((l) => l.weight(2).block('minecraft:tuff').block('minecraft:andesite').size(2, 3))
      .layer((l) => l.weight(1).blocks('minecraft:tuff', 'minecraft:andesite').size(2, 2))
      .layer((l) => l.weight(1).block('minecraft:diorite').size(1, 2))
      .build();

  static final LayerPattern limestone = LayerPattern.builder()
      .layer((l) => l.weight(1).passiveBlock())
      .layer((l) => l.weight(2).block('minecraft:calcite'))
      .layer((l) => l.weight(1).block('minecraft:diorite'))
      .layer((l) => l.weight(2).block('create:limestone').size(2, 4))
      .build();

  static final LayerPattern scoriaNether = LayerPattern.builder()
      .inNether()
      .layer((l) => l.weight(1).passiveBlock())
      .layer((l) => l.weight(2).block('create:scoria').size(2, 5))
      .layer((l) => l.weight(1).block('minecraft:blackstone').size(1, 2))
      .layer((l) => l.weight(1).block('minecraft:basalt').block('minecraft:smooth_basalt').size(2, 3))
      .build();

  static final LayerPattern scorchiaNether = LayerPattern.builder()
      .inNether()
      .layer((l) => l.weight(4).passiveBlock())
      .layer((l) => l.weight(8).block('create:scorchia').size(2, 5))
      .layer((l) => l.weight(4).block('minecraft:soul_soil').block('minecraft:soul_sand').size(1, 3))
      .layer((l) => l.weight(1).block('minecraft:magma_block'))
      .layer((l) => l.weight(4).block('minecraft:basalt').block('minecraft:smooth_basalt').size(2, 3))
      .build();

  /// `AllConfiguredFeatures`: the overworld patterns, in order.
  static List<LayerPattern> get overworld => [scoria, cinnabar, magnetite, malachite, limestone, ochrestone];

  /// The nether patterns.
  static List<LayerPattern> get nether => [scoriaNether, scorchiaNether];
}

/// `LayeredOreConfiguration`.
final class LayeredOreConfiguration {
  final List<LayerPattern> layerPatterns;
  final int size;
  final double discardChanceOnAirExposure;

  const LayeredOreConfiguration(this.layerPatterns, this.size, this.discardChanceOnAirExposure);
}

/// Where a vein may write (inclusive block bounds of the chunk being generated, plus the build limits).
final class VeinClip {
  final int minX, maxX, minZ, maxZ;
  final int minY, maxY;

  const VeinClip(this.minX, this.maxX, this.minZ, this.maxZ, this.minY, this.maxY);

  bool contains(int x, int y, int z) => x >= minX && x <= maxX && z >= minZ && z <= maxZ && y >= minY && y <= maxY;
}

class _TempLayer {
  final Layer layer;
  final double size;
  _TempLayer(this.layer, this.size);
}

class _ResolvedLayer {
  final Layer? layer;
  final double radialThresholdMultiplier;
  final double rampStartValue;
  _ResolvedLayer(this.layer, this.radialThresholdMultiplier, this.rampStartValue);
}

/// `LayeredOreFeature.place` as a function.
///
/// Draws the vein of [config] around ([x0], [y0], [z0]) with [random]; for each block of the vein
/// inside [clip] the [apply] callback decides: it gets the [BlockReplacement]s of the rolled
/// layer block and returns true when it placed one (then the count grows). The random draws do not
/// depend on [clip] or on what [apply] does, so the same vein generated for two chunks agrees.
/// Returns the number of blocks [apply] reported.
int generateLayeredVein(
  LayeredOreConfiguration config,
  LegacyRandom random,
  int x0,
  int y0,
  int z0,
  VeinClip clip,
  bool Function(int x, int y, int z, List<BlockReplacement> targets, LegacyRandom random) apply,
) {
  final patternPool = config.layerPatterns;
  if (patternPool.isEmpty) return 0;
  final layerPattern = patternPool[random.nextInt(patternPool.length)];
  var placedAmount = 0;
  final size = config.size + 1;
  final radius = config.size * 0.5;
  final radiusBound = radius.ceil() - 1;

  final tempLayers = <_TempLayer>[];
  var layerSizeTotal = 0.0;
  Layer? current;
  while (layerSizeTotal < size) {
    final next = layerPattern.rollNext(current, random);
    final layerSize = random.randomBetween(next.minSize.toDouble(), next.maxSize.toDouble());
    tempLayers.add(_TempLayer(next, layerSize));
    layerSizeTotal += layerSize;
    current = next;
  }

  final resolved = <_ResolvedLayer>[];
  var cumulativeLayerSize = -(layerSizeTotal - size) * random.nextFloat();
  for (final temp in tempLayers) {
    final rampStartValue = resolved.isEmpty ? double.negativeInfinity : cumulativeLayerSize * (2.0 / size) - 1.0;
    cumulativeLayerSize += temp.size;
    if (cumulativeLayerSize < 0) continue;
    final radialThresholdMultiplier = random.randomBetween(0.5, 1.0);
    resolved.add(_ResolvedLayer(temp.layer, radialThresholdMultiplier, rampStartValue));
  }

  // Stacking direction.
  var gy = random.randomBetween(-1.0, 1.0);
  gy = _cbrt(gy);
  final xzRescale = math.sqrt(1.0 - gy * gy);
  final theta = random.nextFloat() * (math.pi * 2);
  final gx = math.cos(theta) * xzRescale;
  final gz = math.sin(theta) * xzRescale;
  final layerDisplacementNoise = SimplexNoise(random);
  final radiusNoise = SimplexNoise(random);

  const maxLayerDisplacement = 1.75;
  const layerNoiseFrequency = 0.125;
  const maxRadialThresholdReduction = 0.25;
  const radialNoiseFrequency = 0.125;

  for (var dzBlock = -radiusBound; dzBlock <= radiusBound; dzBlock++) {
    final dz = dzBlock * (1.0 / radius);
    if (dz * dz > 1) continue;
    for (var dxBlock = -radiusBound; dxBlock <= radiusBound; dxBlock++) {
      final dx = dxBlock * (1.0 / radius);
      if (dz * dz + dx * dx > 1) continue;
      for (var dyBlock = -radiusBound; dyBlock <= radiusBound; dyBlock++) {
        final dy = dyBlock * (1.0 / radius);
        final distanceSquared = dz * dz + dx * dx + dy * dy;
        if (distanceSquared > 1) continue;
        final currentY = y0 + dyBlock;
        if (currentY < clip.minY || currentY > clip.maxY) continue; // isOutsideBuildHeight
        final currentX = x0 + dxBlock;
        final currentZ = z0 + dzBlock;

        var rampValue = gx * dx + gy * dy + gz * dz;
        rampValue += layerDisplacementNoise.get(
              currentX * layerNoiseFrequency,
              currentY * layerNoiseFrequency,
              currentZ * layerNoiseFrequency,
            ) *
            (maxLayerDisplacement / size);

        // Collections.binarySearch semantics: the last entry whose ramp start is <= rampValue.
        var layerIndex = 0;
        for (var i = 0; i < resolved.length; i++) {
          if (resolved[i].rampStartValue <= rampValue) {
            layerIndex = i;
          } else {
            break;
          }
        }
        final entry = resolved[layerIndex];
        if (distanceSquared > entry.radialThresholdMultiplier) continue;

        final noise = radiusNoise.get(
          currentX * radialNoiseFrequency,
          currentY * radialNoiseFrequency,
          currentZ * radialNoiseFrequency,
        );
        // Mth.map(noise, -1, 1, 1 - reduction, 1)
        final thresholdNoiseValue = (1.0 - maxRadialThresholdReduction) + (noise + 1.0) / 2.0 * maxRadialThresholdReduction;
        if (distanceSquared > entry.radialThresholdMultiplier * thresholdNoiseValue) continue;

        final targetBlockStates = entry.layer!.rollBlock(random);
        if (!clip.contains(currentX, currentY, currentZ)) continue;
        if (apply(currentX, currentY, currentZ, targetBlockStates, random)) placedAmount++;
      }
    }
  }
  return placedAmount;
}

double _cbrt(double v) => v < 0 ? -math.pow(-v, 1 / 3).toDouble() : math.pow(v, 1 / 3).toDouble();
