# Bulk block placement and structure templates

`world.wit` (set-blocks and friends) and `structures.wit`. Wrappers:
`bulk_placement.dart` (`WorldBulkBlocks`, `BlockPlacementChange`,
`BlockUpdateFlags`) and `structures.dart` (`StructureTemplates`,
`WorldStructures`, `StructureTemplateApi`).

## Bulk placement

All blocks of a batch are written first, then neighbour, shape and light
updates run once for the whole batch (like vanilla `fill` and structure
placement), so no block sees half placed neighbours. Positions outside the build
height or in unloaded chunks are skipped. The update flags are a
`Set<BlockFlagsFlag>`; `BlockUpdateFlags` has `normal`, `withIndirect` (strong
redstone power), `clientsOnly` and `moved` (a contraption disassembling: no
drops, no shape updates, no block entity spill).

```dart
final placed = await world.placeBlocks([
  BlockPlacementChange(pos, stoneStateId),
  BlockPlacementChange(pos2, chestStateId, blockEntityNbt: nbtWithId),
  BlockPlacementChange(pos3, myBlockStateId,
      pluginBlockEntityType: 'my_plugin:machine', pluginBlockEntitySave: saveTag),
], flags: BlockUpdateFlags.moved);                         // changed count

await world.clearBlocks(positions);                         // air, or water if waterlogged
await world.breakBlock(pos, drop: true, breaker: player);   // events, loot, particles, sound
await world.updateNeighborShapes(pos);
await world.notifyBlockChange(pos, oldState: a, newState: b); // writes nothing
final e = await world.spawnFromNbt(entityNbt, (x, y, z));     // new uuid; null if unknown/cancelled
```

`placeBlocks` throws a `HostException` only when a block entity could not be
created, after everything else was placed. `breakBlock` returns false for air or
a cancelled event.

### Block callbacks of a bulk write

The host fires `BlockBehavior.onPlaced` for every block it writes, and each of
those callbacks is a round trip of its own: measured on a live server, one such
callback costs tens of milliseconds while the handler itself runs in
microseconds. A batch of a few hundred blocks is therefore better off writing
without the callback and running it once per position itself:

```dart
final changed = await world.placeBlocks(changes, flags: {
  ...BlockUpdateFlags.normal,
  BlockFlagsFlag.skipBlockAddedCallback,
});
for (final (pos, state) in changes) {
  await CustomBlockBehaviors.firePlaced(
    targetWorld: world,
    pos: pos.toBlockPos(),
    blockKey: state.key,
    stateIndex: stateId - baseStateId,     // `state id = baseStateId + stateIndex`
    oldStateId: oldStateIdAt(pos),
  );
}
```

`skipBlockAddedCallback` skips the whole `placed` hook of the host (`onPlace` of
the block, its fluid, and the vanilla block entity a state with a block entity
type would get). Nothing else changes: the flags still notify neighbours and
clients, `state-replaced` still runs, and the light, neighbour and shape passes
of the batch still run. `CustomBlockBehaviors.firePlaced` re-runs exactly the
`onPlaced` handlers the plugin registered for the block, with the event data the
host would have sent (`player: null` and `oldStateId` set, like a `placed` event;
a `player-placed` event is a player's own write, not a batch). Blocks a plugin
registered without a behavior are skipped, so only the plugin's own blocks cost
anything.

Two related notes:

- `BlockBehavior.onUpdateShape` is asked once per neighbour per written block: an
  `updateShape` handler that keeps the state (returns `null`) is a round trip
  that changes nothing, so do not register one for a block whose shape update is
  only "keep the state".
- A shape pass is skipped altogether by `BlockFlagsFlag.skipShapeUpdate` (the
  neighbours are then not asked at all - vanilla `fill`-style), which is only
  right when the batch already carries every resulting state.

## Structure templates

Vanilla `.nbt` structure format. Template positions are relative to the origin
(the 0,0,0 corner); placing mirrors first, then rotates around that corner.

```dart
final bytes = await world.saveStructure(min, max);          // gzip .nbt, <= 16M blocks
final template = StructureTemplates.load(bytes);           // gzip or raw
template.size; template.palette; template.blocks; template.entities;
final changed = await world.placeStructure(template, origin,
    rotation: Rotation.clockwise90, mirror: Mirror.leftRight,
    ignoreAir: true, integrity: 0.9);
final raw = template.encode(compress: false);
```

Blocks go through the bulk path with `flags`, block entities are created from
the template data and its entities are spawned. Structure voids are never
placed. Parse errors throw `HostException`.

Not available: hanging entities (frames, paintings) rotate wrongly in rotated
structures.
