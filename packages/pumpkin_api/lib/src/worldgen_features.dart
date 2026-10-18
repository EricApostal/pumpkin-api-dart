import 'dart:async';

import 'bindings.g.dart' as generated;
import 'bindings.g.dart' show Context, GenerationStep, HeightShape, OreTarget, Server;
import 'events.dart';
import 'events.g.dart';
import 'host_result.dart';

/// Absolute heights a feature generates at, both ends inclusive.
final class FeatureHeight {
  final int min;
  final int max;
  final HeightShape shape;

  const FeatureHeight(this.min, this.max, {this.shape = HeightShape.uniform});

  /// Heights in the middle of the range are more likely.
  const FeatureHeight.triangle(this.min, this.max) : shape = HeightShape.triangle;
}

/// Where and how often a registered feature generates
/// (`placement-rule` in `worldgen.wit`).
///
/// ```dart
/// WorldgenFeatures.addToBiomes(
///   'my_plugin:ruby_ore',
///   const FeaturePlacement(
///     biomes: ['#minecraft:is_overworld'],
///     count: 6,
///     height: FeatureHeight.triangle(-64, 32),
///   ),
/// );
/// ```
final class FeaturePlacement {
  /// Biome keys (`minecraft:plains`, `minecraft:` optional) or `#tag`s such as
  /// `#minecraft:is_overworld`. Only vanilla biomes and tags exist.
  final List<String> biomes;
  final GenerationStep step;

  /// Attempts per chunk, after the rarity filter.
  final int count;

  /// Generates in one of `rarity` chunks, `null` for every chunk. At least 1.
  final int? rarity;
  final FeatureHeight height;

  /// Spreads the attempts over the 16 by 16 columns of the chunk, otherwise
  /// they all use the chunk corner.
  final bool inSquare;

  const FeaturePlacement({
    required this.biomes,
    this.step = GenerationStep.undergroundOres,
    this.count = 1,
    this.rarity,
    this.height = const FeatureHeight(-64, 320),
    this.inSquare = true,
  });

  generated.WorldgenPlacementRule toWire() => generated.WorldgenPlacementRule(
    biomes: biomes,
    step: step,
    count: count,
    rarity: rarity,
    height: generated.HeightRange(min: height.min, max: height.max, shape: height.shape),
    inSquare: inSquare,
  );
}

/// Additive world generation: features that plugins add to existing biomes
/// (`worldgen.wit`). Registration and rules need [Permissions.registryWorldgen];
/// register in `Plugin.onLoad`, chunks that generated earlier keep what they
/// have. Failures throw a [HostException].
abstract final class WorldgenFeatures {
  /// Registers a feature placed by the plugin: [WorldgenFeatureEvents.onFeaturePlace]
  /// gets the chunks where a rule selects it.
  static void register(String key) => unwrapHost(
    generated.worldgen.registerFeature(key: key, kind: generated.FeatureKind.plugin),
    'Registering the feature $key',
  );

  /// Registers an ore feature placed by the server like a vanilla ore, with no
  /// callback. [size] is the vein size (1 to 64); [discardChanceOnAirExposure]
  /// the chance (0 to 1) that a block touching air is skipped.
  static void registerOre(
    String key, {
    required List<OreTarget> targets,
    required int size,
    double discardChanceOnAirExposure = 0,
  }) => unwrapHost(
    generated.worldgen.registerOreFeature(
      key: key,
      targets: targets,
      size: size,
      discardChanceOnAirExposure: discardChanceOnAirExposure,
    ),
    'Registering the ore feature $key',
  );

  /// Makes the registered feature [featureKey] generate where [rule] says.
  /// Several rules can use one feature.
  static void addToBiomes(String featureKey, FeaturePlacement rule) => unwrapHost(
    generated.worldgen.addFeatureToBiomes(featureKey: featureKey, rule: rule.toWire()),
    'Adding the feature $featureKey to biomes',
  );
}

/// Placing plugin features.
extension WorldgenFeatureEvents on Context {
  /// Calls [handler] for each chunk where a rule selected the plugin feature
  /// [featureKey]. `event.positions` are the attempts of the placement math;
  /// place blocks with `event.chunk` (chunk local coordinates).
  EventSubscription onFeaturePlace(
    String featureKey,
    FutureOr<void> Function(Server server, generated.PluginFeaturePlaceEventData event) handler,
  ) => listen(Events.pluginFeaturePlace, (server, event) {
    if (event.featureKey != featureKey) return null;
    return handler(server, event);
  });
}
