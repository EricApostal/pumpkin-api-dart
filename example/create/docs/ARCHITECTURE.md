# Create for Pumpkin: architecture

`example/create` is the server side of the [Create](../../../../java/Create) mod,
written in Dart and compiled to a Pumpkin plugin (dart2wasm component). This
document is the contract between the **foundation** (`lib/src/core`,
`lib/src/plugin`) and the **modules** (kinetics, processing, logistics, ...).
Read `docs/create-port-survey.md` of `pumpkin_api` for what the host offers.

## Layout

```text
bin/main.dart                  runPlugin(CreatePlugin())
lib/create.dart                the public API of the foundation (what modules import)
lib/src/modules.dart           THE list of modules: one line per module, in load order
lib/src/plugin/
  create_plugin.dart           CreatePlugin: phases, config, unload
  create_neoforge.dart         builds the NeoForgeDeclaration from a registry and a mod
  create_addon.dart            createAddonNeoForgeDeclaration: an addon's own declaration
lib/src/core/                  the foundation: no Create-specific game logic
  module.dart                  CreateModule, CreateContext, CreateRuntime, CreateServices
  registry.dart                CreateRegistry: everything a module registers (declarative)
  ordered_registry.dart        OrderedRegistry<T>: deterministic ids, canonical order
  registry_apply.dart          applies a CreateRegistry to the host, in the right order
  block_entity.dart            CreateBlockEntity, behaviours, BlockEntityStore, ticking
  blocks.dart                  CreateBlock, CreateProps (axis, facing, ...)
  network.dart                 payload channels over the host (send / receive)
  payload.dart                 payload descriptors, FriendlyByteBuf helpers (pure)
  addon.dart                   CreateAddon: the generic hook an addon package implements
  config.dart / config_models.dart  JSON config sections (dart_mappable)
  nbt.dart / byte_buf.dart     network NBT model and FriendlyByteBuf helpers (pure)
  world_state.dart             per-world saved data (mappable models in world custom data)
  services.dart               CreateServices (provide/require/find)
  worlds.dart                  kept World handles by id
  pos.dart                     packed block positions (pure)
lib/src/<module>/              ONE folder per module (see below)
test/                          VM unit tests (plain `dart test`) for the pure parts
docs/ARCHITECTURE.md           this file
```

"Pure" files import only `package:pumpkin_api/pumpkin_api_core.dart` (or nothing),
so `dart test` can load them. Everything that imports `package:pumpkin_api/pumpkin_api.dart`
(the host bindings) cannot run on the VM; keep logic in pure files where you can
and keep the host-touching files thin.

## The module contract

```dart
abstract class CreateModule {
  String get name;                              // lowercase, unique: 'kinetics'
  void register(CreateRegistry registry);       // phase 1: declare content
  void onLoad(CreateContext ctx) {}             // phase 2: registries are applied; listen, commands, services
  void onServerLoaded(CreateRuntime runtime) {} // phase 3: ServerLoadEvent (worlds exist, server usable)
  void onUnload() {}                            // plugin unloading (reverse module order)
}
```

Phases, all driven by `CreatePlugin`:

1. `Plugin.onLoad`: the config is read; `register()` of every enabled module runs
   in the order of `allModules`. Nothing touches the host yet, so this phase is
   deterministic and cannot fail halfway through.
2. The registry is applied to the host in a fixed order (see "Registration
   order"). Failures in id-bearing registries abort loading (the client would
   draw other things than the server means).
3. `onLoad(ctx)` of each module: subscribe to events, build services, register
   `ctx.services`. The NeoForge declaration is installed after all modules ran.
4. `onServerLoaded(runtime)` on `Events.serverLoad`.
5. `onUnload()` on shutdown, then dirty block entities and saved data are flushed.

A module that throws in `onLoad`/`onServerLoaded` is logged and skipped for that
phase; the others keep going. A module disabled in the config
(`"modules": {"kinetics": false}`) is skipped entirely. Modules talk to each other
only through `ctx.services` (`provide<T>() / require<T>() / find<T>()`) and
through shared registry keys, never by importing each other's internals.

### Adding a module

1. Create `lib/src/<name>/<name>_module.dart` with `final class <Name>Module extends CreateModule`.
2. Add `<Name>Module(),` to `allModules` in `lib/src/modules.dart` (commented lines
   already mark the planned slots; the order is the load order and the default
   registration order).
3. Put the module's content in the same folder: `blocks.dart`, `block_entities.dart`,
   `items.dart`, `network.dart`, `commands.dart`, `model.dart` (pure data/logic).
   A module's pure logic (graphs, solvers, routing) must not import the host
   bindings so it can be unit tested in `test/<name>_test.dart`.

Naming: registry keys are `create:<path>` (`CreateKeys.id('shaft')`); Dart file
names `snake_case`; block classes `<Thing>Block`, block entities `<Thing>BlockEntity`,
payloads `<Thing>Packet`; the block entity type key equals the Java registry name
(`create:mechanical_press`).

## Registering content

Everything is declared on `CreateRegistry` in `register()`; nothing is sent to the
host until phase 2.

```dart
@override
void register(CreateRegistry registry) {
  registry.blockEntityType(BlockEntityTypeSpec<CogBlockEntity>(
    key: 'create:cogwheel',
    validBlocks: ['create:cogwheel', 'create:large_cogwheel'],
    create: CogBlockEntity.new,
    tickInterval: 1,
  ));
  registry.block(CreateBlock(
    key: 'create:cogwheel',
    properties: [CreateProps.axis],
    hardness: 3.5,
    blastResistance: 6,
    blockEntityType: 'create:cogwheel',
    placement: [PlacementRule.clickedAxis('axis')],
    behavior: BlockBehavior(onNeighborUpdate: ...),
  ));
  registry.item(ItemRegistration(key: 'create:wrench', maxStackSize: 1));
  registry.fluid(...); registry.entityType(...); registry.menu('create:schematic');
  registry.dataComponent('create:filter_items', codec: ..., persistent: true);
  registry.tag(TagKind.block, 'create:wrench_pickup', ['create:cogwheel']);
  registry.serverbound<Foo>('foo', FooPacket.codec, (ctx, foo) { ... });
  final bar = registry.clientbound<Bar>('bar', BarPacket.codec); // bar.send(player, value)
  registry.command('create', (c) => ...);
}
```

What `CreateRegistry` collects (each with its `add*` method): items, blocks (a
block with `itemKey != null` also registers its block item), block entity types,
menus, data components, fluids, entity types, damage types, sounds, particles,
mob effects, recipe types, plugin synced registries (`create:*` registries the
host does not know), NeoForge-only registry additions, datapack entries and
registries, config files for the handshake, enchantments, advancements and
criterion triggers, tags, payload channels (serverbound with handler, clientbound),
commands. Event subscriptions are not in the registry: use `ctx.listen` in
`onLoad`.

Per-tick work goes through `ctx.onWorldTick` instead of `ctx.listen(Events.worldTick)`:
the plugin registers one `worldTick` host listener and runs every handler from it, in
registration order, with one `WorldTick` per world and tick. `WorldTick.worldId` and
`WorldTick.playersInWorld` are host calls and are resolved lazily, so a handler that
returns early (its module has nothing to do) costs no host call. Check the module's own
state first: `if (_dirty.isEmpty) return;`.

### Registration order

Registration order is the id: the n-th entry of a registry gets `vanillaCount + n`
and NeoForge clients are told these ids. The foundation therefore makes the order
deterministic and independent of Dart map iteration or timing:

* every registry kind has an `OrderedRegistry<T>`; entries keep the order of the
  `registry.*` calls, modules call in the order of `allModules`;
* a duplicate key throws at `register()` time;
* `registry.useOrder(RegistryKind.items, keys)` installs a **canonical order** (for
  example the order of the real mod's registry sync from the content manifest):
  listed keys come first, in that order, the rest follows in call order. Keys in
  the list that nobody registered are reported as "missing";
* across kinds the application order is fixed: items, blocks (block items first),
  block entity types, menus, data components, fluids, entity types, damage types,
  sounds/particles/mob effects, tags, recipe types, synced registries, enchantments,
  advancements, block behaviours, commands, payload listeners;
* after applying, each id the host returns is compared with `vanillaCount + index`
  and a mismatch is logged (another plugin registered first); the final ids are
  available as `ctx.ids.of(RegistryKind.blocks, 'create:cogwheel')` (`AppliedIds`).

Registration is only possible while the server loads (`Plugin.onLoad`); content
cannot be added later.

## Block entities

A block entity is a Dart object in plugin memory, bound to one position. The host
holds only the NBT (`plugin-block-entity.wit`), plus the batched tick events.

```dart
final class CounterBlockEntity extends CreateBlockEntity {
  CounterBlockEntity(super.worldId, super.pos);
  int count = 0;

  @override
  void tick() {
    count++;
    if (count % 20 == 0) markDirty();        // persists at the end of the tick
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('Count', count);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    count = tag.getInt('Count') ?? 0;
  }
}
```

* **Creation**: a `CreateBlock` with `blockEntityType` creates the entity when the
  block is placed (`onPlaced`), calls `onLoad()` and publishes the data to the host.
  When a chunk loads, the host's `block-entity-load-event` makes the store create
  the entity from the saved NBT (`read(tag, clientPacket: false)`), then `onLoad()`.
* **Lifecycle hooks**: `onLoad` (after read, in the world), `initialize` (before the
  first tick), `tick`, `lazyTick` (every `lazyTickRate` ticks, default 10, a
  countdown kept per entity), `onUnload` (chunk unloading, data stays),
  `onRemoved` (block broken or replaced, data gone).
* **Ticking**: `BlockEntityTypeSpec.tickInterval` (0 = never) is passed to
  `set-block-entity-ticking`. The host fires one `block-entity-tick-event` per
  world and type with all due positions; `TickDispatcher` looks each position up in
  the `BlockEntityStore` and calls `tick()`/`lazyTick()`. An exception in one entity
  is logged and does not stop the others. Remember that with an interval of N,
  `tick()` is called every N ticks: pass `tickInterval: 1` for machines that need
  every tick.
* **Persistence**: `markDirty()` queues the entity; at the end of the tick (the host's
  `world-tick-event`) dirty entities are written with `write(tag, clientPacket:
  false)` through `set-block-entity-data`. Throttled by the config key
  `block_entities.save_interval_ticks` (default 20). Pending writes are flushed on
  unload.
* **Client sync**: `sendData()` queues a client update; at the end of the tick the
  entity is written with `clientPacket: true` as the *client data* and published.
  Override `syncsToClient` to `false` for entities the client never needs.
  Caveat: the host replaces the client data on every `set-block-entity-data`, so a
  save-only flush re-sends the last client tag (see "Open points").
* **Behaviours**: `BlockEntityBehaviour` mirrors Create's `BlockEntityBehaviour`
  (filtering, scroll value, ...): `addBehaviour`, `getBehaviour<T>()`; their
  `read/write/tick/lazyTick/onLoad/onUnload/onRemoved` are called with the entity's.
* **Lookup**: `store.at(worldId, pos)` / `store.typed<T>(worldId, pos)`; the world
  handle is `be.world` (kept `World`, null if the world was unloaded).

Host resources (`Player`, `Server`, event `World`s) follow `docs/lifetimes.md` of
`pumpkin_api`: never store one from a callback, store ids (`worldId`, player uuid)
and look them up (`ctx.worlds.byId`, `server.getPlayerByUuid`).

## Blocks

`CreateBlock` is a declarative description (key, properties, default state, shapes,
drops, tags, placement rules, behaviour) that becomes a `BlockDefinition`, a
`BlockBehavior` registered with `Context.registerBlockBehavior`, placement rules,
the block item link, and the block entity factory. The framework wraps the
behaviour's `onPlaced` (create the entity) and keeps the entity in step with the
host (the host removes it when the block is broken or replaced). State properties:
`CreateProps` has the vanilla ones with the right value order (`axis`, `facing`,
`horizontalFacing`, `waterlogged`, `powered`, `open`, `lit`, `level(max)`); the
state index in events decodes with `block.stateOf(index)`.

## Networking

`registry.serverbound<T>(path, codec, handler)` / `registry.clientbound<T>(path, codec)`
declare `create:<path>` (or a full id when `path` has a colon) play-phase channels,
version `1`, required. Codecs are `PayloadCodec<T>` (`PayloadCodec.buffer(write:, read:)`)
over `PacketWriter`/`PacketReader`, which are Minecraft's FriendlyByteBuf primitives;
`byte_buf.dart` adds `readBlockPos`/`writeBlockPosOf`, `readNbtCompound`, `readEnum`,
`readVec3`, etc. A single listener on `Events.playerCustomPayload` dispatches by
channel; payloads that fail to decode are logged and dropped. The channels end up
in the NeoForge declaration (`create_neoforge.dart`), so a real Create client accepts
the server. Handlers get a `Player` valid until the handler first yields.

A package that extends Create declares its own mod: implement `CreateAddon`
(`core/addon.dart`; `modId`, `version`, and a `channels` table or a `contribute`
override) and call
`context.declareNeoForge(createAddonNeoForgeDeclaration(const MyAddon()))` from its
own plugin, with `Permissions.neoforge`. `registry.declareChannel(id, version:,
serverbound:)` adds a channel the declaration carries without a codec or a handler
here. The host merges every plugin's declaration into the one `neoforge:register`
answer and refuses only a duplicate channel or mod id, so Create names no addon
and adding one needs no change here.

## Config

`config.json` in the plugin data folder is one JSON object with one top-level
**section** per owner. The foundation owns `core` (`CoreSettings`: `neoforge`,
`mod_version`, `debug_smoke_test`, `save_interval_ticks`, `log_registry_ids`,
`modules: {name: bool}`). A module defines a `@MappableClass()` settings class with
constructor defaults and reads it once in `onLoad`:

```dart
final settings = ctx.config.section('kinetics', KineticsSettingsMapper.fromMap,
    (v) => v.toMap(), const KineticsSettings());
```

Missing sections or fields take the defaults; an invalid section logs a warning and
uses the defaults; the merged file (all sections with all fields, unknown keys kept)
is written back when something was missing.

## Saved data

`WorldSavedData` (`world_state.dart`): per-world named models stored as JSON in the
world's custom data (`create` namespace), cached, flushed every
`save_interval_ticks` when marked dirty and on world unload / plugin unload:

```dart
static final type = SavedDataType<LinkData>('redstone_links',
    create: LinkData.new, fromMap: LinkDataMapper.fromMap, toMap: (v) => v.toMap());
final data = ctx.savedData.get(world, LinkData.type);   // load on first use
data.add(...); ctx.savedData.markDirty(worldId, LinkData.type);
```

## Data models: dart_mappable

All plain data (config sections, saved data, block entity state, payload model
classes, anything serialised by us) is `@MappableClass()` / `@MappableEnum()` from
`dart_mappable`; the `*.mapper.dart` files are **generated** (never edit them) and
committed. After changing a model run, in `example/create`:

```sh
PATH=$HOME/.puro/envs/master/flutter/bin/cache/dart-sdk/bin:$PATH \
  dart run build_runner build --delete-conflicting-outputs
```

(`--delete-conflicting-outputs` is accepted but ignored by the current
build_runner; plain `build` is enough.) The generated code uses no mirrors, so it
compiles with dart2wasm. Use `X.toMap()` / `XMapper.fromMap(map)`; do not use the
reflection-based `MapperContainer.globals` lookups.

* **Case style**: set once in `build.yaml` (`caseStyle: snakeCase`) because Minecraft
  and Create JSON keys are snake_case. Do not repeat `caseStyle` on classes; deviate
  per class (`@MappableClass(caseStyle: CaseStyle.camelCase)`) only when a wire
  format demands another style.
* **Not mappable**: the FriendlyByteBuf wire codecs stay hand-written
  `PayloadCodec.buffer(write:, read:)` readers/writers (a payload's model class may
  be mappable, its byte layout is not); real NBT that a Create client reads
  (`write(tag, clientPacket: true)`) is written by hand; the content manifest under
  `lib/src/manifest` and `tool/` is plain const data.
* **Block entity state**: extend `MappableBlockEntity<S>`: `state` is stored as one
  JSON string under `State` in the saved NBT (plugin private, not sent to clients).
  Implement `initialState`, `stateFromMap` and `stateToMap`.
* The package pins `dart_mappable`/`dart_mappable_builder` ^4.10.0 (latest) and
  `build_runner` ^2.16.1: 2.17.x needs `build` 5, which the builder does not support yet.

## Testing

* Pure code: `dart test` in `example/create` (`test/`). Use only
  `package:pumpkin_api/pumpkin_api_core.dart` and the pure foundation files
  (`ordered_registry`, `payload`, `byte_buf`, `config`, `pos`, `services`).
* Host code is verified by `dart analyze example/create` and
  `dart run pumpkin_tools build` (+ `wasm-tools validate --features all
  build/create.wasm`), then on a server. The smoke test module (`debug_smoke_test:
  true`) registers `create:smoke_block` whose entity counts ticks and persists the
  counter; place it, restart, check the log.
* Environment: `PATH=$HOME/.puro/envs/master/flutter/bin/cache/dart-sdk/bin:$PATH`.

## Open points / host requests

* `set-block-entity-data` replaces the client data (`none` drops it); a save-only
  write re-sends the cached client tag. A "keep client data" flag in the host would
  avoid redundant packets.
* `set-block-entity-ticking` has no Dart wrapper upstream; this package uses
  `BlockEntityRegistries.setTicking` that was added to `pumpkin_api`.
* Registry canonical orders come from the content manifest (separate tool); until it
  is wired the order is module order.

## Kinetics (module `kinetics`)

The kinetic network of Create: shafts, cogwheels, encased variants, gearbox,
clutch, gearshift, (adjustable) chain drives, creative motor, hand crank, valve
handles, water wheels (large one with its structure blocks), flywheel,
speedometer / stressometer, turntable, cuckoo clocks, rotation speed controller,
sequenced gearshift, powered shaft and the kinetic half of the steam engine.
Public API: `import 'package:create/src/api/kinetics.dart';` (= `lib/src/kinetics/api.dart`).

* **Layers.** Pure (VM tests, `test/kinetics_*_test.dart`): `geometry.dart` (`Dir`, `Axis`,
  `KPos`, `KState`), `network.dart` (`KineticNetwork`), `propagator.dart`
  (`RotationPropagator`, a line by line port), `node.dart` (`KineticNodeMixin`: the logic of
  `KineticBlockEntity`, `KineticLevel`, `KineticBlockRegistry`), `generating.dart`
  (`GeneratingNodeMixin`), `block_defs.dart` (`IRotate` as data), `placement.dart`,
  `chain_drive.dart`, `wrench.dart`, `transmission.dart`, `fluid_flow.dart`. Host side:
  `kinetic_block_entity.dart`, `block_entities.dart`, `generators.dart`, `kinetic_blocks*.dart`
  (block specs from the manifest, behaviours), `runtime.dart`, `service.dart`.
* **Building on it.** Extend `KineticBlockEntity` (or `GeneratingKineticBlockEntity` for
  sources). Override `generatedSpeed`, `calculateStressApplied()` /
  `calculateAddedStressCapacity()` (default: the stress table by block key),
  `onSpeedChanged(prev)`, `propagateRotationTo(...)`, `isCustomConnection(...)`,
  `addPropagationLocations(...)` (belts / chain conveyors connect through these three),
  `onKineticInitialize()` (Java's `initialize()` override, runs in the first tick after the
  entity joined its network) and `write` / `read` (call `super`: they write `Speed`, `Source`,
  `Network {Id, Stress, Capacity, Size, AddedStress, AddedCapacity}`, `NeedsSpeedUpdate`
  exactly like Create). `speed` is 0 while overstressed, `theoreticalSpeed` is the network speed.
  Call `sendData()` / `markChanged()` as in Java; `updateGeneratedRotation()` after a
  generator's speed changed.
* **Registering a kinetic block** (in `onLoad`): `ctx.services.require<KineticNetworkService>()
  .registerKineticBlock('create:belt', def)` with a `KineticBlockDef` (`hasShaftTowards`,
  `rotationAxis`, cog flags; ready made `AxisBlockDef`, `FacingBlockDef`, ...). Stress values
  come from `AllConfigs` (infrastructure module) and the manifest table; add missing ones with
  `registerStress`. The block entity type must be registered by the module itself; this module's
  block entity types (`create:encased_shaft`, ...) take blocks of other modules through
  `kineticValidBlocks['create:encased_shaft']!.add(...)`.
* **Services provided:** `KineticNetworkService`, `KineticSpeedLookup` (equipment). Consumed when
  present: `PayloadBus` (value settings, sequencer, stressometer packets), `WrenchRegistry`
  (installs the state switcher and the kinetic overrides), `CreateConfigs` (live config; else the
  `kinetics` section of config.json), `EncasingRegistry`, `SteamEngineBoilerSource` (set by the
  fluids module: `service.boilerSource = ...`). Load it after protocol / infrastructure; the
  bindings that need later modules happen in `onServerLoaded`.
* **Placement.** The host places the block with a baseline state (clicked axis / face), then
  `buildKineticBehavior` corrects it with the Java `getStateForPlacement` (neighbouring shafts,
  look direction, sneaking) using the last `playerUseBlock` of the player (clicked face and item).
* **Placement assistance** (`placement_helpers.dart` + `placement_helper_host.dart`): shaft lines,
  diagonal cogwheels (`itemUseFirst` intercept), the speed controller's large cog and the steam
  engine shaft, ported from the catnip `IPlacementHelper`s. `rotateKineticState` /
  `mirrorKineticState` (via `KineticNetworkService.rotateState`) cover the structure transforms
  that need more than the generic `facing` / `axis` rule (encased cogwheels, chain drives, gauges).
* **Not ported (client only):** renderers / visuals, goggle tooltips, the overstress and
  rotation sound effects, ComputerCraft peripherals.
