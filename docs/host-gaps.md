# Host capability gaps

Capabilities the plugin needs that the host does not expose. Each was found while
porting a specific feature, and in each case the feature was left **unimplemented
rather than faked** — a workaround would have looked correct and behaved wrongly.

Not a gap (checked, so nobody re-proposes it): **plugin entity synced data mid-life
works.** `set-plugin-synced-entry` reaches every tracking client
(`wit/v0.2/world.wit:585-602`, `crates/pumpkin-wasm-host-v0_2/src/entity.rs:770-800`).
 Only `set-plugin-spawn-data` is spawn-time-only, which matches NeoForge.

## Re-entrant world writes from a plugin event (fixed in the host)

**Fixed in the host**: the deadlock below was real, and the host no longer re-enters the
plugin from a plugin-initiated write. `PluginManager::fire_blocking` queues the event when
`plugin::in_guest_call()` reports a guest call on the current thread (the plugin runtime
installs that probe at startup, `pumpkin_plugin_runtime::is_running_guest_call`), and the
next dispatch outside a guest call delivers it through `Payload::duplicate`, which the
`Event` derive implements from `Clone`. The write itself still happens where it always
did, so `tryPickupFluid` returns the fluid to the plugin immediately and the tank fills;
only the notification of the change waits for the next host-side event. A handler
therefore cannot cancel or reshape a write the plugin itself started: its answer arrives
after the fact.

Measurements from before the fix, kept because they show what the trap looks like: with
the write inline the tank never fills; deferred to a microtask the microtask is never
drained (no event loop outside a guest call); deferred to the world tick it deadlocks
identically, because the world tick is *also* a guest call. Deferring only
`updateComparators` let the first 8 mB reach the tank and then froze.

Where the nested call was lost, from the instrumentation that found it: the guest's wasm
runs in a task that Wasmtime polls *outside* the `scope(context, …)` the store driver
applies to the guest-call job, so `ReentryContext::current()` is empty during the whole
guest execution and `inherited_context()` finds nothing. The nested call still recovered
a chain through `polled_call_context()` (it runs on the thread polling the driver) and
queued its job on the driver, but the driver cannot run it: that same thread is executing
the guest synchronously inside the write. The nested call never returns, so neither does
the guest.

Original report, with the chain as measured then:

```
host → guest (sync export, pumpkin-plugin-runtime/src/executor.rs:673 call_guest)
  → plugin does a NOTIFY_ALL write
  → pumpkin-wasm-host-v0_2/src/world.rs:857 (try_pickup_fluid) or any setBlockState
  → pumpkin-core/src/block/fluid/plugin_fluid.rs:57
        world.set_block_state(&pos, AIR, BlockFlags::NOTIFY_ALL)
  → neighbour updates re-enter the plugin while the outer guest call is still on the stack
  → the nested call_guest never gets an admission
  → the guest never returns: ticks stop, flows freeze, shutdown never completes
```

`tryPickupFluid` from a vanilla water source reached `break_block` rather than the
`set_block_state` above (`Fluid::from_state_id` does not call vanilla water dynamic), and
`break_block`'s own `BlockBreakEvent` is what hung — same deadlock, one event earlier.

Concrete victim: fluid transfer out of a world source
(`open_ended_pipe.dart:131` → `fluid_host.dart:376` → `world.rs:857`). Same class as the
`setBlockState`-inside-`onPlaced` deadlock, so the fix covers the general
plugin-initiated write path, not one call.

The Dart side is faithful to Java — no plugin change was needed.

## Entity effects

*(cardboard sword: Java gives a hit mob Slowness X for 3s; everything else about the
sword works — sound, cancel, sprint-gated knockback through `KnockbackPacket`, the attacker
slowdown)*

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
category is needed for the sword's `MISC`/`CREATURE` (never player) gate. Back with
`LivingEntity::add_effect`.

Faking this with a `MOVEMENT_SPEED` modifier is **not** equivalent: wrong magnitude,
different stacking with other modifiers, no ambient flag.

## Attack-strength scale

*(cardboard sword: the sprint bonus needs `getAttackStrengthScale(0.5f) > 0.9f`,
`CardboardSwordItem.java:83`)*

```wit
// player.wit — on `player`
/// The attack charge for the sprint-knockback gate, Java
/// `player.getAttackStrengthScale(partialTicks)`: `(last_attacked_ticks + partialTicks) /
/// attackSpeed` clamped to `0..1`, where attackSpeed comes from the held item's
/// `minecraft:base_attack_speed` (see `Player::get_attack_cooldown_progress`,
/// `pumpkin-core/src/entity/player.rs:3197-3203`, fed by `last_attacked_ticks` at
/// `:476/:794/:1425/:3007`).
get-attack-strength-scale: func(partial-ticks: f32) -> f32;
```

The host computes the same charge and resets it on every attack, but no function of
`player.wit` or `entity.wit` returns it (`player.wit:1058-1063`'s `get-cooldown` is the
item-group cooldown). Until it exists the sword applies the sprint bonus without the gate.

## Entity interaction from a plugin

*(extendo grip: Java's `ExtendoGripInteractionPacket` forwards long-range attacks **and**
interactions, `ExtendoGripItem.java:214-222`; the port forwards attacks only)*

```wit
// player.wit — on `player`
/// The interaction half of `ExtendoGripInteractionPacket.handle`: `sender.interactOn(entity,
/// hand, point)` (`pumpkin-core/src/net/java/play/interact.rs:100-120`).
interact-on: func(entity: borrow<entity>, hand: hand, point: position);
```

The host exposes no entity-interaction call at all — the only callers of
`Entity::interact` / `ItemRegistry::use_on_entity` are the raw packet path. The attack half
needs nothing (plain `living-entity.damage`; stats, mending and the charge gate are skipped
by definition, same as Java's `sender.attack` from a packet).

```wit
// item-registry — on `item-definition`
/// `ExtendoGripItem.doesSneakBypassUse` (always true): a sneaking click with the grip in hand
/// still reaches the block's use, instead of being diverted to the item.
sneak-bypass-use: bool;
```

Consulted in the host's block-use guard
(`pumpkin-core/src/net/java/play/use_item_on.rs:162`,
`if !(sneaking && (!held_item_empty || !off_hand_item_empty))`).

## Map saved data

*(station: `stationMapData.toggleStation` on a filled-map click, `StationBlock.java:121`)*

```wit
// world.wit — new resource, backed by `MapData` (`crates/pumpkin-core/src/world/map.rs`)
/// The `minecraft:map_id` component of `stack` identifies the map.
get-map-data: func(map-id: s32) -> map-data;
resource map-data {
  center-x: func() -> s32;
  center-z: func() -> s32;
  scale: func() -> u8;
  put-decoration: func(id: string, x: s32, y: s32, name: option<string>);
  remove-decoration: func(id: string);
  is-tracked-count-over-limit: func(limit: u32) -> bool;
  get-station-markers: func() -> nbt-tree;  // the `create:stations` list
  put-station-markers: func(markers: nbt-tree);
}
```

`StationMapMarkers` (the toggle/add/refresh rules, `station_map_data.dart`) is pure and
complete; the host has everything except the wiring — `MapData` already carries
`center_x/center_z/scale/decorations`, the `minecraft:map_id` component locates the right
map, decorations sync via `map_item_data.rs` — but a plugin cannot reach any of it. Until
then the block returns `BlockUseResult.fail`, exactly Java's `InteractionResult.FAIL` when
the station is absent.

## Experience orb values

*(experience nugget: Java spawns one valued orb per value; the port awards the total
instantly — same XP, no orbs)*

```wit
// world.wit — on `resource %world`
/// `ExperienceOrbEntity::spawn` (`crates/pumpkin-core/src/entity/experience_orb.rs:30-38`):
/// one Java-sized orb per value, with motion, merge pickup and mending.
spawn-experience-orb: async func(pos: position, amount: u32) -> entity;
```

A plugin-spawned `minecraft:experience_orb` always carries amount 1
(`crates/pumpkin-core/src/entity/type.rs:275`, the orb reads no NBT at
`:20-37`), and the core already knows the split. The port awards the orbs' exact total
through `Player.addExperiencePoints`, so the number is right but there is nothing to pick up.

## Tag entry removal

*(`aeronautics:converts_to_cloud_skipper` drops `aeronautics:music_disc_cloud_skipper`
through the JSON `remove` entry, so the finished disc does not convert again)*

```wit
// item-registry (and the block/entity/fluid equivalents)
/// Removes entries (item keys or `#tag` references) from a tag.
unregister-item-tag: func(tag: string, entries: list<string>) -> result<_, string>;
```

The JSON datagen supports `remove`; `dynamic_tag.rs` (`register_tag`) only adds, so the
port reproduces the removal with a predicate (the disc's own key) at check time. A removal
op would let the registration call carry the `remove` list verbatim.

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

## Vanilla block-entity data and clears

`get-block-entity-data`, `set-block-entity-data` and `clear-block-entity`
(`wit/v0.2/world.wit`; `VanillaBlockEntities` in `plugin_registries.dart`).
The same saved data `get-block-entity-nbt` serves as raw bytes, in the `nbt-tree`
form the rest of the API uses, so a contraption that moves a vanilla block
entity no longer needs a binary NBT codec. `clear-` removes the entity the move
leaves behind, which setting data cannot express. Plot chunks keep their own
copies in memory (`MemoryPlotChunk.blockEntities`).

**What `set-` does, and what is actually proven.** It is the same lazy path as
the bytes form: `World::apply_block_entity_nbt`
(`pumpkin-core/src/world/mod.rs:6748`) puts the tag into the chunk's
`pending_block_entities` — the form the chunk save and the chunk packet are
built from — and, *only when a live entity exists*, drops that entity so
`get_block_entity` rebuilds it from the tag; with no live entity it returns at
once.

- **Proven:** a moved block entity carries data out of the world and into the
  plot's store (`get-block-entity-data` returns non-null and assembly succeeds,
  live run) and the plot's store round-trips a map through the real gzip-NBT
  codec (VM test `persistence_round_trip_test.dart`). The write path is also
  proven for the modern item shape: `FixFunnelAndSetblockNbt` measured
  `data merge block …{Items:[{Slot:0b,…,count:5}]}` → read-back shows the item.
- **Not proven:** a chest's `Items` surviving a full *assemble → save → reload*
  cycle live (no player in the rig to open a container, and the VM test covers
  the plot store's map, not a live container).
- **Item-shape strictness, not a lost write** (was reported as "the primitive
  silently drops `Items`" — that reading is wrong): the reader is modern-only.
  `sync_read_items_from_nbt` (`pumpkin-inventory/src/inventory/inventory.rs:133`)
  takes `Slot` via `get_byte` and `ItemStack::read_item_stack`
  (`pumpkin-data/src/item_stack/mod.rs:844`) takes `id`/`count` **lowercase** via
  `get_int("count")`. Legacy input (`{Slot:0,Count:5}`, the spelling most wiki
  and pre-1.20.5 Java output uses) keeps `Count` as a different key, so the stack
  fails to parse and the slot is silently empty — `Items: []` after a merge that
  reported success. Vanilla normalises that through its item datafixer; Pumpkin
  has no such upgrade, so the failure is silent rather than an error.

## Plugin-owned chunks (the sub-level plot yard) — not implemented

`create-empty-chunk` is **not** in the WIT: a plugin cannot get a real loaded
chunk at a position of its choosing. This is the single primitive behind four
sub-level capabilities, so it is worth recording exactly what it needs.

What the host already has (read from source):

- `ChunkData::empty_sync(x, z)` (`pumpkin-world/src/chunk/mod.rs:656`) — a
  chunk with no blocks, `status: Full`, no generation.
- `Level.loaded_chunks` is a `DashMap<Vector2<i32>, SyncChunk>`, and
  `Level::get_or_fetch_chunk` (level.rs:661) returns a **memory hit without
  fetching**, so inserting an empty chunk *is* generation suppression for any
  caller that goes through it.
- `plugin_chunks::add_force_ticket` (`pumpkin-core/src/plugin_chunks.rs`) —
  the ticket machinery behind `force-load-chunk`.
- `ChunkData::internal_to_bytes` / `internal_from_bytes`
  (`pumpkin-world/src/chunk/format/mod.rs:506,215`) — a lossless chunk blob:
  sections, block entities, scheduled block/fluid ticks, heightmaps and light.
- Light is per chunk: every light accessor in `lighting/runtime.rs` reads
  `chunk.light_engine` of the chunk in `loaded_chunks`, so a plugin-owned chunk
  gets sky/block light with no engine of its own.

What is missing, in the order the change has to happen:

1. **A generation gate in the scheduler.** A force ticket alone is not enough:
   `schedule.rs:1101-1112` publishes the *generated* chunk unconditionally
   (`publish_chunk` is a plain `DashMap::insert`), so a ticketed yard chunk is
   overwritten by terrain. The scheduler has to learn "this position is
   plugin-owned: take the preloaded chunk straight to `ChunkLevel::Full` and
   skip the generation dag".
2. **A do-not-save mark.** `ChunkData::is_dirty()` is the existing gate the
   file manager and the unload path check (`io/file_manager.rs:487`,
   `chunk_system/schedule.rs:891`); `holds_unregistered_blocks` already uses it
   that way, so a `plugin_owned` flag that forces `is_dirty()` false is the
   natural shape and needs no save-path change.
3. **The WIT + host seam**: `create-empty-chunk(x, z) -> result<chunk, string>`
   (insert empty + force ticket + mark owned), plus `serialize-chunk(x, z)`
   / `deserialize-chunk(x, z, bytes)` wrappers over `internal_to_bytes` /
   `internal_from_bytes`, and a way to release the chunk
   (`release-chunk-ticket` already exists).

Cost: this touches the chunk pipeline, the most load-bearing system in the
server (chunk scheduling, tickets, saving), plus a WIT append and a rebuild of
every wasm. The risk is not the insert — it is the scheduler gate: a wrong
placement there stalls or double-generates chunks for players. Estimate: a day
of work plus verification.

What it unblocks, all four currently "faked or missing" for the plot yard:

- **independent chunk creation / no worldgen over the plot** (A2): the plot's
  chunks become real chunks; sable deletes its `MemoryPlotChunk` map.
- **per-chunk light** (A1): `ServerLevelPlot.initializeLight`/`correctLight`/
  `lightChunk` map onto the existing per-chunk light engine.
- **chunk serialisation** (A3): `serialize-chunk` gives a lossless blob
  (ticks and light included) for the sub-level save, replacing the port's
  per-block map.
- **client sync** (sable's invisible-physics bug): `chunk-streaming
  .send-chunk-at` ships the chunk *loaded in the world*, so today the yard
  either fails ("chunk not loaded") or — when force-loaded — ships worldgen
  terrain, which the client renders as the inside of the ship. With real
  plugin-owned chunks the host sends the plot's own blocks.

Until then, sable keeps the plot in memory and bridges the client view with a
force-loaded world mirror (`PumpkinPlotChunkHost.mirrorPlotChunk`), which is
explicitly a bridge: it writes the plot's blocks into a host chunk at the yard
and wipes them again, so the world is polluted whenever a player is sent a
plot chunk.

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
- **`data merge block` reports success but does not reach a live container.** It answers
  `Modified block data of <pos>`, yet a container's `Items` stays `[]` — two agents hit
  this independently, on both a vanilla chest and a `create:item_vault`, and the host
  writes plugin block-entity NBT into `pending_block_entities`
  (`crates/pumpkin-core/src/world/mod.rs:6498`) which the plugin's `read` never sees
  during the run. So a scenario cannot populate a container to test an observer pulse
  or a threshold switch; that half of those features has to rest on unit tests.
- **`fill` places plugin blocks but creates no plugin block entities.** A filled belt
  run is therefore inert (`initBelt` never runs), and since every segment is
  `part=start`, a run built one `setblock` per tick is destroyed as it is built. The
  only correct construction is one `placeBlocks` batch + `createAt` per segment + a
  single `initBelt` — i.e. `BeltConnectorItem.createBelts`.