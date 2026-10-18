# Fluids

`fluid-registry.wit` and the fluid functions of `world.wit`. Wrappers:
`fluids.dart` (`FluidSpec`, `FluidRegistries`, `WorldFluids`).

* Permission `registry.fluids`; registration closes when the server accepts
  connections. Custom fluids get ids `vanillaCount + n`; a still fluid and its
  flowing variant are two entries.
* A fluid may be held by a plugin block (`FluidPlacement(block, flowing)`);
  without one it is virtual (registries, tanks, buckets). The server has no flow
  physics for them: move fluids with `world.scheduleFluidFlow(pos)` and your own
  block callbacks ([block-callbacks.md](block-callbacks.md)).

```dart
FluidRegistries.register(const FluidSpec(key: 'my_plugin:honey_flowing'));
FluidRegistries.register(const FluidSpec(
  key: 'my_plugin:honey',
  flowingVariant: 'my_plugin:honey_flowing',
  placement: FluidPlacement(block: 'my_plugin:honey_block', flowing: false),
  bucketItem: 'my_plugin:honey_bucket',
  viscosity: 4000, tags: ['my_plugin:sticky'],
));

final state = world.fluidAt(pos);          // FluidState? (level, isSource, height)
world.placeFluid(pos, 'minecraft:water');
final taken = world.pickupFluid(pos);      // FluidStack? in millibuckets
FluidRegistries.fromBucket('minecraft:water_bucket');
```

Register the flowing variant first, because the still fluid names it. The plugin
block and bucket item must exist already. Tag queries: `Tags.fluid(key, tag)`.
