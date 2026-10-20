# Host capability gaps

Capabilities the plugin needs that the host does not expose. Each was found while
porting a specific feature, and in each case the feature was left **unimplemented
rather than faked** — a workaround would have looked correct and behaved wrongly.

Not a gap (checked, so nobody re-proposes it): **plugin entity synced data mid-life
works.** `set-plugin-synced-entry` reaches every tracking client
(`wit/v0.2/world.wit:585-602`, `crates/pumpkin-wasm-host-v0_2/src/entity.rs:770-800`).
Only `set-plugin-spawn-data` is spawn-time-only, which matches NeoForge.

## Entity effects

*(cardboard sword: Java gives a hit mob Slowness X for 3s)*

```wit
// world.wit — on `living-entity`
/// The effect instance to add.
add-effect: async func(effect: status-effect-instance);
remove-effect: async func(effect: status-effect-instance-ref);
has-effect: func(effect: status-effect-instance-ref) -> bool;
get-effect: func(effect: status-effect-instance-ref) -> option<status-effect-instance>;

/// `Entity.getType().getCategory()` — the host drops `MobCategory` in `Entity::get_type`.
get-category: func() -> entity-category;
```

`player.wit:1010` already has `add-effect`, but it is player-only, and the mob
category is needed for the `MISC`/`CREATURE` gate. Back with
`LivingEntity::add_effect`.

Faking this with a `MOVEMENT_SPEED` modifier is **not** equivalent: wrong magnitude,
different stacking with other modifiers, no ambient flag.

## Item use duration

*(sand paper needs 32 ticks; Builder's Tea needs 42)*

```wit
// item-registry — on `item-definition`
/// Ticks the item can be used for, independent of any `consumable` component.
use-duration: option<u32>;
/// Animation played while using it.
use-animation: option<consume-animation>;
```

`ItemUseTickEvent` only fires while `item_use_time > 0`
(`crates/pumpkin-core/src/entity/living.rs:3643`), and the host sets that only for an
item carrying a `consumable`/`blocks_attacks` component
(`use_item.rs:113-131` → `ItemStack::get_max_use_time`, `item_stack/mod.rs:428`).

Declaring these items `consumable` instead would start the use but **consume a stack
item at the end** — Java's non-edible `finishUsingItem` does not. The duration must be
counted by `get_max_use_time` without a component, and the use finished without
consuming the stack.

## Auxiliary light (emission from block-entity state)

*(copycats emit their material's light: glowstone, sea lantern, shroomlight)*

```wit
// world.wit
/// Sets the light level (0 to 15) the block at `pos` **emits**, on top of its static
/// luminance, and marks the position for a light update.
set-block-light-level: func(pos: block-pos, level: u8);
/// The auxiliary emission at `pos`, 0 when none.
get-block-light-level: func(pos: block-pos) -> u8;
```

Needs core work too: `block-registry.wit:149-150` defines luminance as "the light level
**every state** emits", the host has no auxiliary-light store, and the block-callback
flag list has no light flag. The only existing light write is `world.set-block-light`,
a raw write into the engine's *stored* level for one position, which the next
recalculation overwrites — and Java's `getLightEmission` is **emission**, not stored
light. Java: `CopycatBlock.java:297-307`, `CopycatBlockEntity.java:112-131`.

## Copycat material properties

*(a copycat of obsidian should mine and resist like obsidian)*

Currently only friction, speed factor, jump factor, fall damage and the clone item are
wrapped. Java `CopycatBlock.java:310-345` also wraps `canHarvestBlock`,
`getExplosionResistance`, `addLandingEffects`, `addRunningEffects`,
`getEnchantPowerBonus`, `canEntityDestroy`, `fallOn`, `getDestroyProgress`. Needs
equivalent block-callback hooks.

## Exact item-stack component comparison

*(schematics: `isSameItemSameComponents`)*

```wit
/// The stack in `ItemStack.CODEC` form: `{id, count, components?}`.
to-nbt: func() -> nbt-tree;
```

The API never exposes a **live** stack's components as codec NBT, so an exact
`isSameItemSameComponents` is unreachable: the plugin can only compare components it
has an encoder for. `minecraft:banner_patterns` has none, and the host's own
`BannerPatternsImpl` truncates the pattern to `varint(0)`
(`pumpkin-protocol/src/java/protocol_packets/packet/play/.../data_component.rs:3079-3089`).
The comparison logic is already implemented and tested plugin-side
(`StackRequirement.matches`, `componentsMatch`) and would become exact with this hook.

## Custom item handler registration

*(item drain: one item at a time, only while empty, only from the four horizontals)*

`register-plugin-inventory` (`wit/v0.2/item-handler.wit`, `item_handlers.dart:28-49`)
only creates a generic slot inventory. The drain's `ItemDrainItemHandler` needs custom
insert/remainder/extract semantics, so hoppers and funnels cannot feed a drain.

## Block placement vocabulary

*(six gaps, from the placement audit — `example/create/docs/placement-host-gaps.md`
carries the full WIT shapes)*

`looking-axis`, `clicked-block-property`, `clicked-horizontal-face`,
`refuse-when-clicked-face-axis`, `neighbour-shaft-axis`, `when-clicked-face-axis`.

## Also worth knowing (constraints, not API gaps)

- **The console cannot `setblock` a plugin block state.** A property block such as
  `create:belt[part=middle]` is rejected by the parser
  (`pumpkin-command/src/argument_types/block.rs:126-131`) because those are not vanilla
  properties. A plain `setblock <pos> create:belt` resolves to the default state.
- **`fill` places plugin blocks but creates no plugin block entities.** A filled belt
  run is therefore inert (`initBelt` never runs), and since every segment is
  `part=start`, a run built one `setblock` per tick is destroyed as it is built. The
  only correct construction is one `placeBlocks` batch + `createAt` per segment + a
  single `initBelt` — i.e. `BeltConnectorItem.createBelts`.