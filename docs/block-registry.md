# Block registry (`block-registry` WIT interface)

Plugins can add blocks (with block states) to Pumpkin at runtime. This is the sibling of the
item registry (`item-registry.wit`). The WIT file is
`crates/pumpkin-plugin-wit/v0.2/block-registry.wit`, imported by the `plugin` world as
`block-registry` (`pumpkin:plugin/block-registry@0.2.0`).

* Permission: `registry.blocks` (declare it in the plugin metadata like `registry.items`).
* Registration closes when the server starts accepting connections (after `server-load-event`).
  Register in `on-load` or in the `server-load-event` handler. After that every `register-*`
  call that would change something fails; registering the *same* block again still returns the
  existing id, so a hot reload works.
* Not sent anywhere by the host itself: the client learns the ids through your registry sync
  payload (`neoforge-protocol.md`). The host does send the block tags (see below).

## Functions

```
register-block(definition: block-definition) -> result<u32, string>      // block id
register-block-tag(tag: string, entries: list<string>) -> result<_, string>
set-block-item(item-key: string, block-key: string) -> result<_, string>
get-block-id(key: string) -> option<u32>                                  // vanilla or custom
get-block-key(id: u32) -> option<string>                                  // "minecraft:" prefixed for vanilla
get-vanilla-block-count() -> u32                                          // 1286 today
get-vanilla-state-count() -> u32                                          // 35723 today
get-state-id(block: string, properties: list<property-value>) -> option<u32>
get-registered-blocks() -> list<block-entry>   // key, id, base-state-id, state-count, item-id
```

`block-definition` fields: `key`, `properties: list<block-property>` (name + `boolean` |
`int-range{min,max}` | `enumeration(list<string>)`), `default-state: list<property-value>`,
`hardness`, `blast-resistance`, `requires-correct-tool`, `sound-type` (name, kept only),
`luminance` (0..15, every state), `can-occlude`, `suffocating`, `replaceable`, `map-color`,
`collision-shape` / `selection-shape` (`empty` | `full-cube` | `boxes(list<block-box>)`),
`connect-rules: list<connect-rule>`, `drops` (`self-item` | `nothing` | `loot-table(key)`),
`tags: list<string>`.

Order of calls for a block with an item (the Lonsdaleite wardframe):

1. `register-item` (item registry, `lonsdaleite:lonsdaleite_wardframe`)
2. `register-block` (same key; items and blocks have separate id spaces)
3. `set-block-item("lonsdaleite:lonsdaleite_wardframe", "lonsdaleite:lonsdaleite_wardframe")`
4. tags: either in `definition.tags` or `register-block-tag`

`set-block-item` needs a *custom* item (not a vanilla one). Using that item then places the block
(through the same path as vanilla block items), and `drops = self-item` drops one of it.

## Ids

* Block id = `get-vanilla-block-count()` + registration index (0 for the first custom block of
  any plugin). This is the NeoForge rule too (the manifest says ids come from the registry sync;
  this is what the host sends).
* Block state ids: the states of custom blocks start at `get-vanilla-state-count()`. The first
  block's states are `[vanilla_state_count, vanilla_state_count + n0)`, the next block's states
  follow directly, and so on, in registration order. `block-entry.base-state-id` is the first id
  of a block and `state-count` how many it has.
* Both counts are `u16` ids: at most 65535 block ids and 65536 states in total. A block may have
  at most 16384 states and 32 properties.
* The ids never change while the server runs, and a world stores blocks by name and properties,
  not by id. Plugins that register blocks must be loaded in a stable order if the client side
  depends on the numbers.

## State order (what the client has to compute)

The rule is vanilla's `StateDefinition`, whatever the order of `properties` in the definition:

1. Sort the properties by name (plain byte order, `down < east < north < south < up < west`).
2. The first property is the most significant, the last one changes fastest.
3. Values of a property are indexed in declaration order: boolean `true` = 0, `false` = 1; an
   int property `min..=max` has index `value - min`; an enum property uses the order of its list.

```
count[i]  = number of values of property i (sorted order)
stride[i] = count[i+1] * count[i+2] * ... * count[last]      (1 for the last one)
state index = sum(valueIndex[i] * stride[i])                 // 0 .. product(count) - 1
state id    = base-state-id + state index
```

Dart sketch:

```dart
int stateId(int baseStateId, List<(String name, int count)> sortedProps, Map<String, int> valueIndex) {
  var index = 0;
  var stride = 1;
  for (var i = sortedProps.length - 1; i >= 0; i--) {
    index += (valueIndex[sortedProps[i].$1] ?? 0) * stride;
    stride *= sortedProps[i].$2;
  }
  return baseStateId + index;
}
```

The wardframe (six booleans `north south east west up down`, 64 states): sorted order is
`down(32) east(16) north(8) south(4) up(2) west(1)` (the strides). Index 0 is all `true`, index 63
all `false` (`down=false, east=false, north=false, south=false, up=false, west=false`). So with
`default-state` all `false` the default state id is `base-state-id + 63`. Example: `east=true`,
`up=true`, rest `false` is index `63 - 16 - 2 = 45`. This matches the manifest's
`block_state.state_order` and `default_state_index: 63`; `declaration_order` (north, south, ...)
is irrelevant for the numbering.

`get-state-id(block, properties)` does this computation on the server (properties that are not
listed take their default value) and also works for vanilla blocks.

If `default-state` leaves a property out, the host uses its **first** value (vanilla's
`StateDefinition.any()`), which is `true` for a boolean. List the booleans that should start
`false`.

## What the host does with a registered block

* Placement: the linked item places it (vanilla block placement path: replacing, entity
  obstruction, `BlockPlaceEvent`, spawn protection, ...). `connect-rules` set the placed state.
* `connect-rules` (`property`, `direction`, `target`): a boolean property is `true` when the
  neighbour in `direction` matches `target` (`same-block`, a block key, or a block tag). They are
  applied on placement and on every neighbour change, like glass panes and chorus plants.
  `direction` is the world direction (`north` = -z). One rule per property.
* Breaking: `hardness` (-1 = unbreakable), `requires-correct-tool` (a state flag, so
  creative/instant break and drops follow vanilla), tool speed and "correct tool" come from the
  block *tags* and the tool rules of the held item: add the block to `minecraft:mineable/pickaxe`
  and `minecraft:needs_diamond_tool`. Joining `needs_diamond_tool` also joins the
  `incorrect_for_{wooden,gold,copper,stone,iron}_tool` tags, like vanilla's tag includes, so only
  a diamond or better tool is correct.
* Drops: `self-item` drops one item of the linked item (also subject to the vanilla
  `survives_explosion` chance for explosions), `loot-table(key)` uses that loot table (datapack
  loot tables are looked up by key), `nothing` drops nothing. Nothing drops when a block that
  requires a correct tool is broken with the wrong one.
* Shapes: `collision-shape` is what mobs, items and projectiles collide with (`full-cube` for the
  wardframe). Player movement is client side in Pumpkin, so a client that lets players through
  needs nothing on the server, except `suffocating = false` so a player standing inside is not
  damaged (the server would treat a full block as suffocating).
* Light: `luminance` is the same for every state; `can-occlude = false` makes the block not
  occlude light (glass like).
* Tags: tags of custom blocks are part of the `update-tags` packet (block registry), with the ids
  above.
* Persistence: chunks store `Name` (`namespace:path`) and `Properties` like vanilla. A world with
  a block whose plugin is gone loads that block as air (a warning is logged) without errors.

## Gaps and things to know

* `sound-type` and `map-color` are stored, the client chooses the actual sounds/colours.
* Per-entity collision (players, tamed pets and mounts with players pass through the wardframe)
  is not modelled: the server treats it as a full cube for every entity.
* Static tag checks keyed by a generated tag constant (`block.has_tag(&tag::Block::...)`) do not
  see custom blocks; checks by tag name (tool rules, item tool components) do.
* Block entities, redstone power, random ticks and waterlogging are not available for custom
  blocks yet.

## Dart side

`package:pumpkin_api` wraps the interface like the item registry
(`docs/item-registry.md`); the generated names (`BlockRegistry`, `BlockDefinition`,
`BlockEntry`, `PropertyKind`, `ConnectRule`, `blockRegistry`, ...) are hidden.

* `Permissions.registryBlocks` (`'registry.blocks'`) in `PluginInfo.permissions`.
* `BlockRegistries.host` is the `BlockRegistryBackend` over the host:
  `register(BlockDefinition)`, `registerTag`, `setBlockItem(itemKey, blockKey)`, `idOf`,
  `keyOf`, `vanillaBlockCount`, `vanillaStateCount`, `stateId(block, {name: value})`,
  `registeredBlocks`. A failure is a `BlockRegistryException` with the host's message.
  `register` first runs `BlockDefinition.check()`, which reports every problem of the
  definition at once, before any host call.
* Binding-free, in `package:pumpkin_api/pumpkin_api_core.dart` (`lib/src/block_registry_core.dart`):
  * the model: `BlockDefinition` (properties, default state as a map, hardness, blast
    resistance, `requiresCorrectTool`, `soundType`, `luminance`, `canOcclude`,
    `suffocating`, `replaceable`, `mapColor`, `collisionShape`/`selectionShape`
    (`BlockShape.empty` / `fullCube` / `boxes`), `connectRules`, `drops`
    (`BlockDrops.selfItem` / `nothing` / `lootTable`), `tags`), `BlockProperty.boolean` /
    `intRange` / `enumeration`, `ConnectRule`/`ConnectTarget`/`ConnectDirection`;
  * `BlockStateLayout` (`definition.layout`): the state numbering of this document
    (sorted names, first most significant, `true` = 0 / `false` = 1, int `value - min`,
    enum by position): `stateCount`, `strides`, `defaultStateIndex`, `indexOf(values)`,
    `stateId(base, values)`, `valuesAt(index)`;
  * `BlockDefinition.validate()` / `check()`: the host's rules (key and namespace, finite
    hardness >= -1 and resistance >= 0, luminance <= 15, sound type and property/value names
    `a-z 0-9 _`, no duplicates, <= 32 properties, <= 256 enum values, <= 16384 states, default
    state and connect rules naming known properties (rules only on booleans, one per
    property), shape boxes finite and ordered, <= 64 boxes, loot table key not empty);
  * `BlockRegistryChecks`: `checkVanillaCounts` (the host has the vanilla block and state
    counts the sync was built for), `checkAssigned` (ids `vanillaBlockCount + index`, base
    state ids from `vanillaStateCount` onwards, state counts), `checkStateIds` (the host's
    `get-state-id` equals the computed id for every state, sampled above 4096), all failing
    with a `BlockRegistryException` that says which side to fix.
* The sequence for a block with an item: `register-item` (item registry), `register-block`,
  verify, `set-block-item`, `register-block-tag`, read back. `example/lonsdaleite`
  (`lib/src/block_install.dart`) is the complete example.
* `packages/pumpkin_neoforge` has `vanillaBlockStateCount` (35723, generated from
  `blocks.json`) for the NeoForge sync: a client numbers the states of the mod's blocks after
  the vanilla ones.

```dart
final id = BlockRegistries.host.register(
  BlockDefinition(
    key: 'my_plugin:ruby_block',
    hardness: 5,
    blastResistance: 6,
    requiresCorrectTool: true,
  ),
);
BlockRegistries.host.setBlockItem('my_plugin:ruby_block', 'my_plugin:ruby_block');
BlockRegistries.host.registerTag('minecraft:mineable/pickaxe', ['my_plugin:ruby_block']);
```
