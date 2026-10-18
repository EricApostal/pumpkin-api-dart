# Fluid handlers

`fluid-handler.wit`. Wrappers: `fluid_handlers.dart` (`FluidHandlers`,
`WorldFluidHandlers`, `ItemStackFluidHandler`, `FluidHandlerApi`). The item
version of this is [item-handlers.md](item-handlers.md); registering fluids is
[fluids.md](fluids.md).

* Permission `containers` (`Permissions.containers`). Without it the lookups
  return `null`.
* Amounts are millibuckets, a bucket holds 1000. Every function takes
  `simulate` so you can ask first.
* Three kinds of blocks have a handler: plugin block entities with tanks
  (`registerTank`, saved with the entity), cauldrons (one tank of 1000, water and
  powder snow in 3 levels of 333, so `fill` and `drain` move whole levels), and
  every spot a source can be placed or picked up (fluid blocks, waterlogged
  blocks, air, replaceable blocks; the side is ignored; needs at least 1000).
* Items have handlers too: buckets (1000, all or nothing), water bottles (250 mB
  of water) and items you register as fluid containers. A stack of more than one
  item has no tank.
* A handler is a view that keeps working after the block is gone: ask for a new
  one when the block may have changed. `FluidHandler` and `ItemFluidHandler` are
  resources, see [lifetimes.md](lifetimes.md).

```dart
// A tank on a plugin block entity (the block entity must exist already).
world.registerTank(pos, tanks: 2, capacity: 4000);

final from = world.fluidHandlerAt(pos, side: BlockDirection.up);
final to = world.fluidHandlerAt(other);
if (from != null && to != null) {
  final moved = from.transferTo(to, 250, fluidKey: 'minecraft:water'); // simulates first
}

final bucket = stack.fluidHandler;                       // ItemFluidHandler?
final inside = await bucket?.drain(maxAmount: 1000, simulate: true);

FluidHandlers.registerContainerItem('my_plugin:flask',
    capacity: 500, allowedFluids: ['minecraft:water']);   // plugin item, kept in custom data
final leftovers = world.unregisterTank(pos);              // List<FluidStack>
```

`FluidHandler` is synchronous; `ItemFluidHandler` returns `Future`s. Errors of
`registerTank`, `unregisterTank` and `registerContainerItem` throw
`HostException`. `register-plugin-tank` fails without a plugin block entity;
shrinking fails while a removed tank holds fluid.
