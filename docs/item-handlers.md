# Item handlers

`item-handler.wit`: moving items into and out of containers seen from a side,
with hopper rules. Wrappers: `item_handlers.dart` (`ItemHandlers`,
`PluginInventories`, `ItemHandlerApi`).

```dart
final handler = ItemHandlers.at(world, pos, side: BlockDirection.up);
if (handler != null) {
  if (await handler.canInsert(stack)) {
    final rest = await handler.insertStack(stack);   // null: everything went in
  }
  final out = handler.takeFirst(16);                  // ItemStack? taken
}
```

* A handler is a view of the slots reachable through one `side`; `null` sees
  all slots. Chests (double chests as one), barrels, shulker boxes, furnaces,
  hoppers, brewing stands, droppers and plugin inventories have handlers.
* `insert` and `isItemValid` are async (`Future`); `extract`, `getStack` are
  synchronous. With `simulate: true` nothing changes. The stack you pass is not
  changed. Returned stacks are owned resources ([lifetimes.md](lifetimes.md)).
* A handler keeps its container after the block is gone: ask for a new one when
  the block may have changed.
* `PluginInventories.register(world, pos, slotCount: 27, slotLimit: 64)` gives a
  plugin block entity (`PluginBlockEntities`) an inventory that hoppers see, and
  `unregister` returns the items. Both throw `HostException` when there is no
  plugin block entity.
