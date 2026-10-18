# Additive world generation

`worldgen.wit`. Wrappers: `worldgen_features.dart` (`WorldgenFeatures`,
`FeaturePlacement`, `FeatureHeight`, `Context.onFeaturePlace`). A chunk generator
that replaces all generation is separate (`worldgen.dart`, `ChunkGenerator`).

Features are added to existing biomes. Rules run after the vanilla features of
their step, with vanilla placement math (rarity, count, in-square, height range,
biome check). Vanilla generation does not change while no rule exists.
Permission `registry.worldgen` (`Permissions.registryWorldgen`); register in
`Plugin.onLoad`. Chunks that generated earlier keep what they have. Failures
throw `HostException`.

```dart
// Placed by the server like a vanilla ore, no callback.
WorldgenFeatures.registerOre('my_plugin:ruby_ore',
    targets: [OreTarget(target: '#minecraft:stone_ore_replaceables', state: 'my_plugin:ruby_ore')],
    size: 8, discardChanceOnAirExposure: 0.5);
WorldgenFeatures.addToBiomes('my_plugin:ruby_ore', const FeaturePlacement(
    biomes: ['#minecraft:is_overworld'], count: 6, rarity: 2,
    height: FeatureHeight.triangle(-64, 32)));

// Placed by the plugin.
WorldgenFeatures.register('my_plugin:ruin');
WorldgenFeatures.addToBiomes('my_plugin:ruin', const FeaturePlacement(
    biomes: ['minecraft:desert'], step: GenerationStep.surfaceStructures, rarity: 40));
context.onFeaturePlace('my_plugin:ruin', (server, e) {
  for (final pos in e.positions) { /* e.chunk.setBlock(...) with chunk-local coordinates */ }
});
```

`e.featureKey`, `e.seed`, `e.step`, `e.chunkX`/`chunkZ` and `e.targetWorld` are on
the event. Several rules can use one feature. Biomes are vanilla biome keys or
`#tag`s; plugin biome tags do not exist.
