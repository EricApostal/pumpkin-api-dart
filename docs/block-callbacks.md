# Block callbacks, redstone and ticks

Logic for plugin blocks (`block-callbacks.wit`, plus the redstone and tick
functions of `world.wit`). Wrappers: `BlockBehavior`, `Context.registerBlockBehavior`
and the `WorldRedstone` extension (`block_callbacks.dart`).

* Permission: `registry.blocks` ([block-registry.md](block-registry.md)).
* The callbacks are set while the server loads (`Plugin.onLoad`, before it
  accepts connections). Setting the same callbacks again is fine; other
  callbacks for a block that already has some fail with a `HostException`.
* A block only costs the host something for the hooks it opted into. All blocks
  share the event stream, so the wrapper compares the event's `block` key with
  yours and your handler only sees its own block. The comparison happens in the
  guest: the wrapper registers one host handler per hook and runs the blocks'
  handlers itself, so an event of a hook costs the plugin one host→guest round
  trip (and one per block behaviour would cost one *each*).

```dart
context.registerBlockBehavior(
  'my_plugin:lever_lamp',
  BlockBehavior(
    onNeighborUpdate: (server, e) async {
      final powered = await e.targetWorld.hasRedstoneNeighborSignal(e.pos);
      await e.targetWorld.setRedstoneOutput(e.pos, weak: powered ? 15 : 0);
    },
    redstoneOutput: true,
    onCanPlace: (server, e) => e.face != BlockDirection.down,
    onScheduledTick: (server, e) => logger.info('tick at ${e.pos.x}'),
  ),
);
```

## Hooks

| `BlockBehavior` field | Event | Result |
| --- | --- | --- |
| `onNeighborUpdate` | `Events.customBlockNeighborUpdate` | none |
| `onPlaced` (placed + player-placed) | `Events.customBlockPlaced` (`player` set when a player placed it) | none |
| `onStateReplaced` | `Events.customBlockStateReplaced` | none |
| `onBroken` | `Events.customBlockBroken` | none |
| `onScheduledTick`, `onRandomTick` | `Events.customBlockScheduledTick` / `customBlockRandomTick` | none |
| `onEntityCollision`, `onEntityStep` | `Events.customBlockEntityCollision` / `customBlockEntityStep` | none |
| `onCanPlace` | `Events.customBlockCanPlace` | `bool` |
| `onUpdateShape` | `Events.customBlockUpdateShape` | new `stateIndex` or `null` |
| `onWeakPower`, `onStrongPower` | `Events.customBlockRedstonePower` (`strong` tells them apart) | power 0..15 |
| `onComparatorOutput` | `Events.customBlockComparatorOutput` | 0..15 or `null` |
| `redstoneOutput`, `comparatorOutput` | no event, see below | |
| `onShape` | `Events.customBlockShape` (`kind`: collision, selection, visual) | `List<BlockBox>` or `null` |
| `onUse` (or `onUseWithItem` / `onUseWithoutItem`) | `Events.customBlockUse` (`withItem`, `hand`, `face`, `cursor`) | `BlockUseResult` |
| `onAttack` | `Events.customBlockAttack` | none |
| `onCloneItem` | `Events.customBlockCloneItem` | `ItemStack?` |
| `onPlayerWillDestroy` | `Events.customBlockPlayerWillDestroy` | `false` cancels |
| `onFriction`, `onSpeedFactor`, `onJumpFactor` | `Events.customBlockPhysics` (`kind`) | `double`, cached per position |
| `canEntityDestroy`, `isPathfindable`, `canConnectRedstone` | `Events.customBlockCondition` (`condition`) | `bool` |
| `onLandedUpon` | `Events.customBlockLanded` | fall damage multiplier |
| `soundType` | `Events.customBlockSoundType` | sound type name |
| `onFireSpread` | `Events.customBlockFireSpread` | `(spreadChance:, burnChance:)` |

The hooks with a result run as blocking handlers (`intercept`). The
`neighbor-update`, `update-shape`, `entity-collision` and `entity-step` hooks and
the power events run very often: keep the handlers fast, and prefer stored
output where you can. `stateIndex` counts like the states of the block registry;
add it to the block's `baseStateId` for the state id.

It is **not** a state id: a block with six states reports `0..5`, so passing it
straight to a state lookup reads a vanilla block whose properties are missing and
whose fallbacks silently apply. Read the state at `event.pos` instead (it is the
`BlockState` the hook is about, and it cannot be stale); only `state-replaced`
(the position has the new block) and `can-place` (the block is not there yet)
need `baseStateId + stateIndex`.

## Shapes

Static shapes per state belong in the block definition: `shapeRules` (see
[block-registry.md](block-registry.md)). A shape that depends on more than the
state, like a copycat taking the shape of another block, uses `onShape`. The
answer is cached per position (as are friction, speed and jump factor), so call
`world.invalidateShape(pos)` whenever it changes, for example when the block
entity gets a new material. Replacing the block clears it on its own.
`event.boxes` converts the event's shapes (the start of the list is the
registered shapes) into `BlockBox`es.

```dart
BlockBehavior(
  onShape: (server, e) async => e.kind == BlockShapeKind.visual ? null : [BlockBox.unit],
  onUse: (server, e) => e.withItem ? BlockUseResult.pass : BlockUseResult.success,
  onFriction: (server, e) => 0.98,
  onPlayerWillDestroy: (server, e) => e.stateIndex != 0,   // false cancels
)
```

## Redstone

A machine usually knows its output from its own state. Store it instead of
answering events:

```dart
await world.setRedstoneOutput(pos, weak: 15, strong: 0);   // updates neighbours
await world.setRedstoneOutput(pos, face: BlockDirection.north, weak: 7);
await world.setComparatorOutput(pos, 9);
```

The output lives in memory only and is dropped when the block is replaced or
moved: store it again after a restart. Reading signals:
`redstonePower(pos, dir)`, `directRedstonePower`, `hasRedstoneNeighborSignal`,
`bestNeighborSignal`, `analogSignal`, plus `notifyNeighbors(pos)` and
`updateComparators(pos: ...)`. All are `Future`s ([async.md](async.md)).

## Block ticks

`world.scheduleTick(pos, 5.ticks, priority: TickPriority.high)` schedules a
tick of the block at `pos` (at most 255 ticks) which arrives as `onScheduledTick`.
`Events.blockEntityTick` and `Events.worldTick` are the batched and per-world
tick events; see [events-and-time.md](events-and-time.md).
