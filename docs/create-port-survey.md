# What a Pumpkin plugin needs to port Create

A survey of the Create mod (`/Users/eric/Documents/development/languages/java/Create`,
the in-progress 26.3 port, 2055 Java files) against Pumpkin's plugin WIT
(`crates/pumpkin-plugin-wit/v0.2`). Six areas were read by separate readers
(kinetics, contraptions and trains, logistics and fluids, mixins and events,
equipment/redstone/decoration, client protocol) and merged here.

**Reliability.** This was read from source and the WIT only. Nothing was built or
run. The "Pumpkin today" column comes from the WIT files and the two gap notes
(`host-features-for-client-mods.md`, `example/cc_tweaked/docs/host-requirements.md`),
not from the Rust host, so "yes" means "declared", and the notes say several of
those host features were written without being built. Counts are approximate.
The Create tree does not compile yet (it is mid-port), so signatures may change.

Terms: **Create client** means the real Create mod installed on the player's
NeoForge client (needed for models, Flywheel rendering and GUIs). **Vanilla
client** means no mod, with blocks substituted.

## Summary

Create splits into three kinds of work:

1. **Pure plugin logic**, which Pumpkin already supports well enough: the
   kinetic network, train graph, signals and schedules, the redstone link
   network, logistics routing, schematic parsing, commands, configs.
2. **Plugin logic that needs a host feature**, listed below as P0 to P3.
3. **Things that cannot be done as a plugin at all today**, because the plugin
   API has no equivalent: custom entity types, fluids, custom recipe types,
   plugin-defined registries.

The Create client path additionally needs the NeoForge handshake with about 119
required play channels (see [neoforge-protocol.md](neoforge-protocol.md)).
A vanilla client can only get an imitation (see the end).

## Host features, by priority

Each item names what Create uses it for. "Today" is what the WIT offers.

### P0: nothing works without these

| # | Feature | Why Create needs it | Today |
|---|---------|---------------------|-------|
| 1 | **Block entity ticking** (batched, per chunk) and **per-world / per-entity tick events** | every kinetic block, belt, fan, drill, packager ticks; contraptions and trains run off `LevelTickEvent` (`CommonEvents.java`) | none. Only `server-tick-start/end-event` and `scheduler`, one WASM call per task |
| 2 | **Callbacks for plugin blocks**: neighbour changed, `canSurvive`, `updateShape`, `onPlace`/`onRemove`, scheduled block ticks, entity-inside / step-on | attached blocks (levers, links, girders, brackets), belts and chutes moving entities, gearshift and clutch | only `block-physics-event` and `block-redstone-event` (observation) |
| 3 | **Redstone signal API**: read neighbour signal, be a signal source, analog output, update neighbours | clutch, gearshift, analog lever, links, observer, threshold switch, redstone contact, deployer, sequencer | none (`P1.6` in the CC notes) |
| 4 | **Plugin-registered entity types** with a "virtual entity" lifecycle (id, tracking, synced data, spawn payload, passengers, persistence) | contraption entities (4 types), seat, super glue, blueprint, potato projectile, package | `entity-types.wit` is a closed vanilla enum |
| 5 | **Item entities**: spawn with a full stack (components included), read/modify/discard, pickup delay, AABB query | chutes, funnels, belts, crushers, drills, ejectors, tunnels, deployers | `spawn-entity` takes no stack; no accessors |
| 6 | **Entities-in-box query** (and a cheaper entity scan than `get-entities`) | fans, belts, crushing wheels, contraption collision | `get-nearby-entities` is a radius query, `get-entities` is the whole world |
| 7 | **NeoForge handshake owned by the host** with plugin-declared channels, registries and config files (see [create-handshake](#client-protocol)) | Create declares about 119 required payloads; adhoc mode fails them | **host side now exists** (`neoforge.wit`, [neoforge-host.md](neoforge-host.md)): plugins declare mod, channels, registries, config files, datapack entries; `example/cc_tweaked` uses it. Unbuilt/untested on a live client |

### P1: large parts of the mod need these

| # | Feature | Why Create needs it | Today |
|---|---------|---------------------|-------|
| 8 | **Item/fluid transfer layer** (capabilities with sides, insert/extract with remainder and simulate, transactions) | the whole transfer model: belts, chutes, funnels, vaults, packagers, tanks | `container-block-entity.get-inventory` for some vanilla block entities; no sides, simulate or transactions |
| 9 | **Fluids**: fluid types and stacks, fluid state read, custom fluids and buckets, fluid tick scheduling | pipes, pumps, tanks, spouts, drains, hose pulley, fluid recipes | none (only `fluid-level-change-event`) |
| 10 | **Custom recipe types and a recipe query API** (RecipeManager lookups, fluid and sized ingredients, secondary outputs) | basin, press, mixing, filling, emptying, sequenced assembly, deployer, milling, crushing, plus smelting/crafting lookups | `recipe.wit` registers shaped, shapeless and cooking only; no queries |
| 11 | **Mass block and block entity placement** with `updateShape`, neighbour updates, break particles and drops | contraption disassembly, schematic cannon | per-block async `set-block-state` |
| 12 | **Per-state collision and selection shapes**, plus block tags, push reaction and fluid state on `block-state` | tracks (about 20 shapes), girders, brackets, doors, analog lever; `BlockMovementChecks` | one shape per block; no tag or push-reaction queries |
| 13 | **Fake players** | deployer, plough, harvester, item hatch, packager, arm, `BlockItemMixin` | none (T4 in the CC notes) |
| 14 | **Loot / drop query** (`getDrops(pos, tool)`), block-break progress | drill, saw, deployer, harvester | `block-drop-item-event` can only cancel; no query |
| 15 | **Menu behaviour**: cursor stack, shift-click, drag, `ContainerButtonClick` | toolbox, schematic table, schematicannon, filters (ghost slots), stock keeper | `menus.wit` delivers click events but does not apply them |
| 16 | **Plugin-defined registries and datapack contributions**: damage types, enchantment effects, advancements/triggers, potato projectile registry | `create:*` damage types, 2 enchantments, 103 advancements, 12 `sync(true)` registries | closed damage enum; award-only advancements; enchantments partial |

### P2: needed for fidelity

- **More events:** `LivingDrops` (drops, not just XP), `LivingEquipmentChange`,
  `LivingVisibility`, `LivingBreathe`, `EntityEvent.Size`, per-player and
  per-entity tick, `PlayerEvent.StartTracking`, `EnteringSection`, knockback
  (declared but never fired), `projectile-hit` for non-arrows, reload
  listeners and `TagsUpdated`.
- **Entity movement:** collision-aware `entity.move`, setter for on-ground,
  fire-immune flag, custom pose/size.
- **Cheap `isLoaded(pos)`** (used about 29 times in kinetics alone).
- **Tag membership queries** (`block-has-tag`, item and fluid tags) and
  registration of fluid and entity-type tags.
- **Custom particles, sounds, map decorations** and their sync.
- **Data component limits:** at most 64 types (Create has 57 to 61, close to the
  cap), values are raw bytes, and stacks with custom components count as changed
  on every click (no equality or hash).
- **Worldgen additions** (biome-modifier equivalent): only a full chunk
  generator replacement exists; workaround is placing ore after chunk load.
- **Structure entities with NBT** for schematics, and a bulk structure API.
- **Entity tracking events and a force-loading query** for plugin entities.

### P3: small or workable today

Commands (`command.wit` covers `/create`), configs (plugin file in the data
folder), game rules (read), custom payloads (`player-custom-payload-event`,
`send-custom-payload`), world custom data for saved data (`world.set-custom-data`),
enchantment and attribute modifier reads, world load/unload events.

## Status in the Dart API

Written against the WIT on branch `wip/create-host-features` (regenerate with
`tool/generate_bindings.sh`). "Wrapper" means a Dart helper exists on top of the
generated binding. **Available** means the WIT declares it and Dart wraps it;
**Partly** means a part is missing (the reason is in the table); **Not
available** means neither the host nor the WIT does it. The reasons come from the
Rust implementation reports. Nothing here was run against a live server and the
host side is unbuilt in places, so "Available" is "declared", not "verified". The
tables above describe the state before these additions.

| # | Feature | Dart status | Where / reason |
|---|---------|-------------|----------------|
| 1 | Block entity ticking, per-world and per-entity tick events | Available | `Events.blockEntityTick`, `worldTick`, `playerTick`, `entityTick`, `Context.tickEntities`; [events-and-time.md](events-and-time.md), [entities.md](entities.md) |
| 2 | Block callbacks: neighbour, can-survive/place, update shape, place/remove, scheduled and random ticks, entity inside/step | Available | `BlockBehavior`; [block-callbacks.md](block-callbacks.md) |
| 2b | More block callbacks: use (with/without item), attack, clone item, will-destroy, friction/speed/jump factor, entity-destroy, pathfindable, redstone connect, landed-upon, sound type, fire spread, dynamic shape | Available | `BlockBehavior.onUse`, `onShape`, ... and the matching `Events.customBlock*`; [block-callbacks.md](block-callbacks.md) |
| 3 | Redstone signal API | Available | `WorldRedstone`; [block-callbacks.md](block-callbacks.md) |
| 4 | Plugin entity types, virtual entity lifecycle | Available | `EntityRegistries`, `World.spawnPlugin`, `PluginEntityData` (synced entries, spawn data, passenger offsets, tracking, accept-client-movement, `moveBy`, `registerDataSerializer`), `Events.pluginVehicleInput`, `entityStartTracking`; [entities.md](entities.md) |
| 4b | Entity type `pushable` / `ignoreRidersHit` fields | Available | `EntityTypeSpec`; the rider hit flag is in `EntityFlag.projectilesHitRiders` |
| 5 | Item entities | Available | `World.dropItem`, `ItemEntity`; [entities.md](entities.md) |
| 6 | Entities-in-box query | Available | `World.entitiesIn`, `itemsIn`; [entities.md](entities.md) |
| 7 | Host-owned NeoForge handshake | Available | `Context.declareNeoForge`, `Player.isNeoForge`, `declareSyncedRecipeTypes`, `updateNeoForgeConfigFile`; [neoforge-host.md](neoforge-host.md) |
| 8 | Item transfer layer | Available | `ItemHandlers` (sides, simulate); [item-handlers.md](item-handlers.md) |
| 8b | Fluid transfer layer (tank capability) | Available | `FluidHandlers`, `FluidHandlerApi`: plugin tanks, cauldrons, source spots, buckets, bottles, container items; [fluid-handlers.md](fluid-handlers.md) |
| 9 | Fluids: registry, state, place/pickup, fluid ticks, buckets | Available | `FluidRegistries`, `WorldFluids`; [fluids.md](fluids.md) |
| 9b | Fluid flow physics for registered fluids | Not available | not implemented in the host (Rust report): it schedules fluid ticks only, so the plugin must spread fluids in its own callbacks |
| 9c | Fluid pass-through checks | Available | `Events.fluidCanPassThrough`, `Events.entityFluidMovement` (flag `fluidMovementEvents`) |
| 9d | Dispenser use of plugin buckets | Not available | not implemented in the host (Rust report) |
| 10 | Custom recipe types, recipe queries, recipe sync | Available | `CustomRecipeBuilder` (`networkData`), `RecipeQueries`, `declareSyncedRecipeTypes`; [recipes-and-tags.md](recipes-and-tags.md) |
| 11 | Mass block placement | Available | `World.placeBlocks`, `clearBlocks`, `breakBlock`, `updateNeighborShapes`, `notifyBlockChange`, `spawnFromNbt`; [bulk-placement-and-structures.md](bulk-placement-and-structures.md) |
| 11b | Structure templates (`.nbt`): load, save, place with rotation and mirror | Partly | `StructureTemplates`; hanging entities (frames, paintings) do not rotate correctly in rotated structures |
| 12 | Per-state shapes, dynamic shapes, push reaction | Available | `BlockDefinition.shapeRules`, `pistonBehavior`, `BlockBehavior.onShape`; [block-registry.md](block-registry.md) |
| 12b | Block, item, fluid and entity type tag queries and registration | Available | `Tags`, `registerTag`; [recipes-and-tags.md](recipes-and-tags.md) |
| 12c | Plugin biome tags | Not available | not implemented in the host (Rust report); worldgen rules take vanilla biomes and `#tags` only |
| 13 | Fake players | Available | `FakePlayers`, `FakePlayerActions`, `Events.fakePlayerPlaceCheck`; [fake-players.md](fake-players.md) |
| 14 | Loot / drop query, loot modification | Available | `World.getBlockDrops(pos, tool)`, `Events.lootModify`; [fake-players.md](fake-players.md) |
| 15 | Menu behaviour (click rules, cursor stack) | Available | `Events.menuClick` etc., `PluginMenus`; [menus.md](menus.md) |
| 16 | Plugin damage types | Available | `DamageTypeRegistries`, `damageByKey`; [damage-types.md](damage-types.md) |
| 16b | Runtime advancements and criterion triggers | Partly | `Advancements`, `Player.fireCriterion`; the host evaluates only the `plugin_tag` condition, any other condition is kept as data and never checked; [enchantments-and-advancements.md](enchantments-and-advancements.md) |
| 16c | Enchantment effects, costs, effect types, queries | Partly | `EnchantmentManagerEffects`, `EnchantedItemStack`; the host stores and syncs the effects but does not evaluate them for plugin enchantments |
| 16d | Anvil and enchanting table support for plugin enchantments | Not available | not implemented in the host (Rust report) |
| 16e | Synced plugin registries, datapack registries | Available | `ExtraRegistries.declareSyncedRegistry`, `declareDatapackRegistry`, `addDatapackEntry`; [extra-registries.md](extra-registries.md) |
| P2 | Living drops, equipment change, breathe, visibility, entity size, entering section, start/stop tracking | Available as events | [events-and-time.md](events-and-time.md) |
| P2 | Cheap `isLoaded(pos)`, area loaded | Available | `World.isLoaded`, `isAreaLoaded` |
| P2 | Entity movement and flags: `moveBy`, on-ground, fire immunity, size/pickup/pose overrides | Available | `PluginEntityData`, `EntityFlagsApi`; [entity-flags.md](entity-flags.md) |
| P2 | Custom sounds, particles, mob effects, map decorations | Available | `ExtraRegistries`; [extra-registries.md](extra-registries.md). Mob effects have no tick hooks; particles reach NeoForge clients only |
| P2 | Worldgen additions (biome-modifier equivalent) | Available | `WorldgenFeatures`, `Context.onFeaturePlace`; [worldgen-features.md](worldgen-features.md) |
| P2 | Mixin style events: item use tick, swing, use-first, can-attack-block, item entity update | Available | `Events.itemUseTick`, `itemSwing`, `itemUseFirst`, `canAttackBlock`, `entityItemUpdate`; [events-and-time.md](events-and-time.md) |
| P2 | Reload and sync events: datapack reload, tags updated, datapack sync | Available | `Events.datapackReload`, `tagsUpdated`, `datapackSync` |
| P2 | Data component limits (64 types, raw bytes, no equality) | Not available | unchanged in the WIT (a host limit of the component registry) |
| P2 | Hanging entities rotating in structures | Not available | see 11b |

## What is already covered (and unverified in practice)

Items and blocks (`register-item`, `register-block`, 16384 states per block),
block entities with save and client data (`plugin-block-entity`), menus (as
events), custom data components, use-block/use-item events with hit position,
placement rules, play-phase custom payloads, per-tick server events, world
load/unload, commands. The notes say block entities, menus, components, use
events and placement rules were written without being built or run, so the
first job of a port is to try them.

## Area notes

### Kinetics

The kinetic graph is event driven: it only recomputes on attach, detach or
speed change. Per tick it validates and ticks block entities. Keep the graph in
plugin memory and call `sync-block-entity` only on change, because
`get-block-entity-data` copies NBT each time. The hard hot path is belts and
fans, which need an entities-in-box query and velocity writes every tick (a WASM
call per callback). Rendering (Flywheel visuals, block entity renderers) is
client-only, so a Create client is required; speed and stress reach it through
the block entity update tag.

### Contraptions and trains

Two different targets. With a **Create client**, the client already has the
contraption entity classes and renderers and does player-versus-contraption
collision itself (`ClientMotionPacket`). The server has to announce the entity
types in the registry sync, spawn them with matching ids, synced data and a
spawn payload that includes the whole contraption NBT, track viewers, simulate
mobs and items, and accept the client packets. That needs P0 item 4. Raw
packets (`c-spawn-entity`, `c-set-entity-metadata`, `c-set-passengers`) could
fake the client side, but then the server never treats those as real entities
and riding is the weakest spot. The train graph, signals, schedules and
navigation are pure server logic and the best covered; they mainly need
persistence (`world.set-custom-data`) and a tick.

### Logistics, fluids, processing

No fluid or capability concept exists in the WIT. Stock and packager networks
are plugin logic, but area scans and neighbour inventory snapshots hit the
scheduler, container access and `get-block-entity` gaps. Recipes can be kept as
plugin-private data if no client needs them, but the Create client needs real
`neoforge:recipe_content` for the mixer's potion recipes and the factory
panel's crafting lookup.

### Equipment, redstone, decoration, schematics

Wrench, zapper and similar items work off `player-use-block-event`. Redstone
cluster is blocked by P0 item 3. Schematic upload is 4 payloads and a gzip NBT
reader in the plugin; placing the structure needs P1 item 11. Copycat blocks
need a shape taken from the block entity material, which is not expressible with
one static shape per block.

### Mixins

42 common mixins (plus 21 client ones, skipped). The behavioural ones change:
fire immunity, seat bounce, lava swimming velocity, player/mob hitboxes on
contraptions, projectile hits on riders, deployer drop capture, deployer-vs-bees
and block placement, custom item-use effects, crush looting bonus, smithing
checks, water wheel fluid spread, map station markers, and the creation of 12
Create registries. Most map to a missing event or flag from P0 to P2; the
rest (accessors, datafixers, datagen) are not blockers.

## Client protocol

- 66 serverbound and 48 clientbound payloads (`AllPackets.java`), all play phase,
  all version `"1"`, none optional, plus 5 more from Catnip and Ponder, so about
  119 required channels. Flywheel adds none.
- Registry sync would have to cover: blocks (about 700 names), items, block entity
  types (about 114), menus (15), data components (57), and, with no host support
  today, entity types (9), fluids and fluid types, particle types (13), sounds
  (about 83), recipe types (17) and serializers (19), map decoration, entity data
  serializers (`create:carriage_data`), and the 12 `sync(true)` registries.
  Block state counts and order must match the client exactly.
- Datapack registries and tags: `damage_type` (9), `enchantment` (2),
  `create:potato_projectile/type`, 185 tag files (fluid and entity-type tags not
  covered), blaze burner fuel data maps (optional).
- `create-server.toml` is a SYNCED config and must be sent as
  `neoforge:config_file`.
- 6 entity types use complex spawn data (`neoforge:advanced_add_entity`).

## Vanilla client (no mod)

No Create payload is understood and no GUI, contraption or train renders.
Substituted vanilla blocks and server-side item movement keep working. An
imitation is possible with display entities, invisible armor stands and
interaction proxies, and would work for slow translating contraptions only.

## Suggested order

1. Verify the unbuilt host features (block entities, menus, components, use
   events, placement rules) with CC, which already exercises them.
2. P0 items 1 to 3 (ticking, callbacks, redstone): they unblock kinetics,
   which is the heart of the mod.
3. P0 items 5 and 6 (item entities, entity queries): belts and logistics.
4. P0 item 4 (entity registry and lifecycle): contraptions and trains.
5. P1 items 8 to 10 (transfer, fluids, recipes).
6. P0 item 7 (host-owned handshake) when a Create client has to connect.
