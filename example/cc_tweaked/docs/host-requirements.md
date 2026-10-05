# What Pumpkin must expose so the real CC: Tweaked client works

This is the host-side (Rust) work the plugin is waiting for, in priority
order, each with the reasoning from the packets and registries in
[client-compat.md](client-compat.md). "Today" is what the WIT interface
(`wit/v0.2`, `packages/pumpkin_api`) offers now; "Plugin" is where the code
that will use the feature already sits in `example/cc_tweaked`. Nothing here
was changed in the host by this plugin: these are requests. **Update:** the host
since got the NeoForge pre-brand hold (P0.1), the connection flavour with the
NeoForge particle encoding (P0.2, **both subject to the host compiling**: they
were written without being built or run), and the block registry
(`block-registry`, part of P0.3/P1.1). **Update 2:** the host then got placement
rules, block entities of plugin types, menus, custom data component types and
the use events (`docs/host-features-for-client-mods.md`, also unbuilt), and
this plugin was wired to them: see [Status](#status-what-the-host-now-offers-and-what-the-plugin-does-with-it)
and [Open questions of the wiring](#open-questions-of-the-wiring). Recipe
serializers, redstone and the datapack registries are still missing. Sections
below (written before) say which requirement is met.

* [Status: what the host now offers and what the plugin does with it](#status-what-the-host-now-offers-and-what-the-plugin-does-with-it)
* [Open questions of the wiring](#open-questions-of-the-wiring)
* [Summary](#summary)
* [P0: the client cannot join without these](#p0-the-client-cannot-join-without-these)
* [P1: computers, monitors and modems in the world](#p1-computers-monitors-and-modems-in-the-world)
* [P2: the rest of the blocks and items](#p2-the-rest-of-the-blocks-and-items)
* [P3: polish](#p3-polish)
* [What works without any of it](#what-works-without-any-of-it)
* [Effort estimate](#effort-estimate)

## Status: what the host now offers and what the plugin does with it

> **Nothing in this section was run.** The host features were written without
> being built or run (`docs/host-features-for-client-mods.md`), and the plugin
> wiring was written against their WIT and the CC: Tweaked sources, with `dart
> analyze` and a wasm build as the only checks. The "Today" column of the
> tables further down describes the situation *before* these features and is
> kept for the reasoning; this section is the current state.

| # | Requirement | Host (WIT `v0.2`) | Plugin (`"neoforge": true`) | Verified |
| - | ----------- | ----------------- | --------------------------- | -------- |
| P0.3 | ids of block entity types, menu types, data component types | `plugin-block-entity.register-block-entity-type`, `menus.register-menu-type`, `custom-components.register-data-component-type` (ids `vanilla count + n`, closed after `server-load-event`; permissions `registry.block-entities`, `registry.menus`, `registry.components`) | registers 16 + 7 + 14 in the order of the sync after items and blocks, checks the host's vanilla counts and every id, refuses to load otherwise (`registry_install.dart`) | no. Recipe serializers and `computercraft:recipe_function` ids are still not host registries (not needed: the host never writes them for CC's entries) |
| P1.1 | block state at placement | `block-placement.set-block-placement-rules` (`registry.blocks`) | one rule list per block copied from the Java `getStateForPlacement` (`CcBlockSpec.placement`): facing, clicked face, monitor orientation by pitch, waterlogged | no |
| P1.1 | more than 4096 states per block | per-block limit raised to 16384 | all 16 blocks register in full when the host allows it | no |
| P1.2 | block entities with save data and update tag | `plugin-block-entity.get/set/sync/remove-block-entity-data`, `block-entity-load-event`, `block-entity-unload-event` | computers: save data `ComputerId`/`Label`/`On`, no client data; entity created a tick after `block-place-event`, machine resumed on load, suspended on unload | no. Monitors, turtles (client data `{XIndex, YIndex, Width, Height}`, `Label`, `Fuel`, ...) are **not** done |
| P1.3 | custom menus, `advanced_open_screen`, close event | `menus.open-menu` (extra data -> `neoforge:advanced_open_screen`), `set-menu-data`, `menu-closed-event`, `menu-click-event` | `computercraft:computer` and `pocket_computer_no_term` opened with zero slots and `ComputerContainerData` as extra data; `isOn` in data slot 0; session ends on `menu-closed-event`. Turtle, disk drive and printer menus are **not** done (no menu behaviour in the host) | no |
| P1.4 | custom data components with codecs | `custom-components` (prefix notation codec, `set/get/remove-custom-component`) | 14 types with the exact StreamCodec shapes (`protocol/components.dart`, each cites its Java codec); `computer_id` read from items and written to the dropped/held stack | no |
| P2 | interaction events with hit position, face, hand | `player-use-block-event` (with cursor), `player-use-item-event` | computer GUI on right click without sneaking; pocket computers on use; place tracking. The cursor is **not** used yet (monitor touch is not done) | no |
| P1.6 | redstone | none | none: computers do not read or drive redstone in the world | - |
| P1.5 | `turtle_upgrade` / `pocket_upgrade` datapack registries | none | none | - |

What is still missing on the host side for the rest of the mod: neighbour
changed callbacks (peripheral discovery, redstone, monitors expanding), block
entity ticking (the plugin polls from its own tick), an API to drop an item
entity with a custom stack (a broken computer's id goes straight into the
player's inventory instead), `getCloneItemStack` (pick block), menu behaviour
with real slots (disk drive, printer, turtle), a redstone signal API, the
datapack registries, recipes, and fake players for turtles.

## Open questions of the wiring

Where the plugin had to assume something the sources do not settle, so a
live test knows what to look at first:

1. **Zero-slot menu.** The computer menu of the client has nine invisible
   slots; the plugin opens it with zero tracked slots (the host then sends no
   `SetContent`/`SetSlot`) and sends only `ClientboundContainerSetData` for
   the `isOn` slot. If the client insists on a content packet or logs a slot
   count error, open it with `openPluginMenu(..., slots: 9)` (`menus.open-menu-with-slots`).
2. **The open payload.** The host builds `neoforge:advanced_open_screen` as
   `VarInt containerId, VarInt menuTypeId, Component title (network NBT),
   byte[] extraData`. The plugin supplies the `ComputerContainerData` bytes as
   `VarInt family ordinal, TerminalState, optional ItemStack (VarInt count, VarInt
   item id, patch), VarInt uploadMaxSize` (`protocol/menu_data.dart`), the
   title as the label or the translation key `block.computercraft.<name>` (pocket
   computers `item.computercraft.<name>`). Whether the client's registry sync
   gave the ids the display stack uses is part of the same open question as
   the sync itself.
3. **The terminal after the open.** `ComputerContainerData` carries the
   initial terminal; `computer_terminal` is sent only when it changes
   (checked every other tick), as CC does. A client that shows an empty
   terminal until the first change means the initial state was not applied.
4. **Block entity client data for computers is empty.** The plugin sends none
   (`AbstractComputerBlockEntity` has no `getUpdateTag`). If the client needs a
   block entity in the chunk packet for the computer to render its state, the
   state is in the block state `state`, which the plugin updates with
   `set-block-state` (flag `notify-listeners` only).
5. **Event order.** The place event is assumed to fire with the position of
   the new block before it exists, and the item use event with `clicked-pos`
   set just before it, so the plugin remembers the item's `computer_id` from
   the use event and creates the entity one tick later. If a placement does not
   restore the id, this ordering is the first suspect.
6. **`Hand`.** `Hand.right` is taken as the main hand and `Hand.left` as the
   off hand (`from_wasm_hand` in the host), which selects the
   `pocket_computer_no_term` menu.
7. **Drops.** `block-drop-item-event` hands the plugin copies and the host
   applies only `cancelled` back. The plugin cancels the drop and puts the
   item (with `computer_id` and the label as custom name) into the first empty
   main inventory slot of the player who broke the block with `set-item`
   (slots 9 to 35, then the hotbar: the host's `set-item` sends the container
   slot packet with the inventory index, which only matches the window for
   9 to 35). Whether the event fires for creative players and before or after
   `block-entity-unload-event` is not known; the plugin tolerates both orders
   for a short while after a removal.
8. **Pocket computers.** The id is written to the held item with
   `set-item-in-hand`. The host reports a use in the air after a click on a
   block, so the plugin ignores a second use within four ticks. The `computer`
   component (session and instance UUID), the `on` component and
   `pocket_computer_data` (the item's model state) are not maintained.
9. **File uploads.** `file_transfer` is queued with an own Lua table whose
   `getFiles()` returns binary read handles with `getName()`; CC's userdata
   (`TransferredFiles`, `ReadHandle`) is not reproduced exactly.
10. **Chunk load order.** Computers in blocks are started by
   `block-entity-load-event`. If the host fires it before the plugin is loaded
   (spawn chunks), computers that were on do not start until a player opens
   them. The plugin looks an entity up lazily on first use for this reason.
11. **Persistence formats.** The save data uses CC's key names (`ComputerId`,
    `Label`, `On`), but it is the host's `PluginData` wrapper that is stored,
    so a world is not interchangeable with a Java CC world.

## Summary

| # | Requirement | Why the real client needs it | Today |
| - | ----------- | ---------------------------- | ----- |
| P0.1 | NeoForge negotiation **before the brand** (`neoforge:register` query first, then `neoforge:network`) | all 16 `computercraft:*` payloads are *required*: a connection classified "not NeoForge" is disconnected by the client | **provided** by the host: `configuration-pre-brand-event` (subject to compile); used by `NeoForgeNegotiation.full` |
| P0.2 | NeoForge flavoured play encodings for connections that answered the query | the client switches encodings (e.g. block particles, recipe book, holder sets) once it is classified NeoForge | **provided** by the host: `server.set-connection-flavour` + the particle encoding (subject to compile); the rest of the flavoured codecs write the same bytes as vanilla for vanilla content (docs/neoforge-play-codecs.md) |
| P0.3 | Registering modded **block, block entity type, menu type, data component type, recipe serializer** ids so the host uses the synced ids | ids come from the registry snapshot; every packet naming a CC block/item/BE/menu/component must use them | items (`item-registry`) and blocks (`block-registry`, partly) only; block entity types, menus, data component types and recipe serializers **missing** |
| P1.1 | **Custom blocks** with block state properties and the vanilla block callbacks | computers, monitors, modems are blocks with up to 6400 states (the cable) | **registered by the plugin** (13 blocks completely, the cable with the 3200 states that have a cable; `lectern` and `redstone_relay` wait for a higher per-block state limit); the callbacks listed below are not provided |
| P1.2 | **Block entities** owned by plugins, with save data and an update tag | monitors (`XIndex`/`YIndex`/`Width`/`Height`), turtles, persistent computers | only vanilla block entity views |
| P1.3 | **Custom menus** (menu type, slot layout, data slots, open with extra data, close event) | the computer GUI opens through `neoforge:advanced_open_screen` and expects a matching menu | `Gui` supports vanilla `generic-9xN` screens |
| P1.4 | **Custom data components** on item stacks with plugin-defined encodings | `computer_id`, `storage_capacity`, ... travel in every item stack the client sees | `custom-data` and vanilla components only |
| P1.5 | Datapack/dynamic registry entries for `computercraft:turtle_upgrade` and `pocket_upgrade` | sent in `registry_data`; a client that lacks them cannot build a turtle or pocket computer | not available |
| P1.6 | Redstone: neighbour signal queries and plugin blocks as signal sources | computers read and drive redstone | no signal API |
| P2 | Interaction events with hit position, chunk watch events, block entity chunk data, creative-slot decoding of modded stacks, custom recipes, server config sync, fake players for turtles | see below | partial |

## P0: the client cannot join without these

### P0.1 The NeoForge handshake has to start before the brand

**Status: provided by the host** (`configuration-pre-brand-event`; the plugin
side is `NeoForgeNegotiation.full` of `packages/pumpkin_neoforge`, see its README;
neither was run against a live client). The text below is the original request.

`ComputerCraft.registerNetwork` registers every channel with
`registrar.versioned(<mod version>)` and without `.optional()`. NeoForge
treats such a payload as **required**. A client that sees the server's
`minecraft:brand` before any `neoforge:register` query classifies the
connection as "other" and runs `initializeOtherConnection`: the required
payloads fail against an empty server and it disconnects ("You are trying to
connect to a server that is not running NeoForge, but you have mods that
require it"). The details and the strict ordering are in
[docs/neoforge-protocol.md](../../docs/neoforge-protocol.md) ("The ordering
problem").

Needed from the host: let a plugin act at the **start** of the configuration
phase, before the brand and before `finish_configuration` machinery: send
`minecraft:unregister`/`minecraft:register`, send the `neoforge:register`
query, send a ping, wait for the answer, then send `neoforge:network` and
`minecraft:register`, and only then let the host send its brand and the rest.
In Pumpkin terms: a new hold point (`configuration-pre-brand-event`, or a flag
on `configuration-start-event` that moves the brand after the hold).

Plugin: `NeoForgeServer` with `NeoForgeNegotiation.full`, installed from
`lib/src/plugin/plugin.dart` (`_installNeoForge`) when `"neoforge": true` is
set; the channel list is `CcChannels.specs(version)` (play phase, each
direction, required, version = the jar's mod version).

### P0.2 Play-phase encodings for NeoForge connections

**Status: provided by the host** (`server.set-connection-flavour`, the flavour
aware packet writer; today only `BlockParticleOption` differs for vanilla
content, see docs/neoforge-play-codecs.md; subject to compile). Two behaviours
need the plugin and are done by `NeoForgeServer.installPlay`: the
`neoforge:gliding_flight` attribute (elytra) and the empty
`neoforge:recipe_content`. Recipe book settings for *modded* recipe book types
(`2 * n` booleans) are not written; CC adds none.

After the query the client's *listener* is NeoForge. `RegistryFriendlyByteBuf`
then carries the connection type, and codecs that are `connectionAware`
(`NeoForgeStreamCodecs`) change: block particle options get an extra optional
`BlockPos`, recipe book settings add modded categories, custom ingredients and
holder sets are written in extended form, item attribute modifiers are filtered.
The host must produce these forms for clients that answered the query (and
vanilla forms for the others, so a mixed server keeps working). The list of
affected packets is in the NeoForge section of docs/neoforge-protocol.md.

### P0.3 Ids of modded entries

**Status:** items and (via `block-registry`) blocks are provided; **block entity
types, menu types, data component types and recipe serializers are still
missing.** The plugin synchronises block, item, block entity type, data
component type and menu (plus `computercraft:recipe_function`); recipe
serializers and command argument types are *not* synchronised because Pumpkin
has no list of their vanilla entries (no asset file; `CcRegistries.synchronised`),
which is fine as long as the host does not write their ids.

The registry sync (`neoforge:frozen_registry`) **defines** the numeric ids of
CC's entries on the client (vanilla entries first, then the mod's in
registration order; the exact lists are in `lib/src/protocol/registries.dart`,
`CcRegistries`). From then on every packet that names one of them must use
that id: chunk data (block states), block entity data (`BlockEntityType` id),
`ClientboundOpenScreen` / `advanced_open_screen` (menu type id), item stacks
(item id and component type ids), `registry_data`.

Needed: a way for a plugin to register, **in a stable, ordered way**, entries of
`block`, `block_entity_type`, `menu`, `data_component_type`, `recipe_serializer`
(and the custom registry `computercraft:recipe_function`), with the host
appending them after its vanilla count and using the appended ids on the wire,
exactly as `ItemRegistry.registerItem` already does for items
(`vanillaCount + n`). Items work today: with `"neoforge": true` the plugin
registers its 23 items in sync order (`plugin.dart`, `_registerItems`) and
warns when the id it gets differs from the one the sync announces.

Block *states* need the same care: the client numbers the states of all blocks
by walking the block registry in snapshot order, so the host's state ids for
CC's blocks must be `firstFreeStateId + running sum of state counts` in the
order of `CcBlockCatalog.all` (**6940** states; per-block counts in
`blocks.dart`; this page first said 3740, which counted the cable as 3200 states
instead of 25 x 2 x 2^6 x 2 = 6400).

**Status:** the plugin registers the blocks through `block-registry` with the
checks listed in the README ("CC blocks in the world"). One host limit blocks
exactness: **a block may have at most 4096 states** (`MAX_STATES_PER_BLOCK` in
`pumpkin-data/src/block_registry.rs`, mirrored by
`BlockRegistryChecks.maxStatesPerBlock`), and the cable needs 6400. Raising the
limit to at least 6400 (the total is far below the 65536 state ids) lets the
plugin register all 16 blocks with no change (it plans from that constant);
until then the cable lacks the states without a cable and `lectern` and
`redstone_relay` are not registered, because their state ids follow the
cable's.

## P1: computers, monitors and modems in the world

### P1.1 Custom blocks

**Status:** the block registry provides blocks with state properties, a
default state, shape/drops and the block item link (so the state numbering the
client derives from the sync can be matched), and the plugin uses it for all of
CC's blocks (limits above). Placing/interaction callbacks (`onPlace`,
`neighborChanged`, `use` with the hit position, scheduled ticks, redstone
signal) and block entities are not part of it. Concretely still missing for
the blocks the plugin registers:

* **state for placement**: a placed block always gets its default state
  (`facing=north`); CC needs the player's horizontal direction (computers,
  speakers, drives, printers, monitors `facing`, the opposite for most; turtles
  and relays the same direction), the clicked face (wireless modems and cable
  modems `facing`), the player's pitch (monitor `orientation`) and the fluid
  at the position (`waterlogged`; waterlogging itself is not available for
  custom blocks either). Only boolean "neighbour" properties (`connect-rules`)
  are computed, and the cable's six sides use them;
* **shapes that depend on the state**: one collision and selection shape per
  block. Used: full cube for computers, speakers, drives, printers, monitors,
  relay and full wired modem (these are full cubes in Java too); the turtle's
  2/16 to 14/16 box; for the wireless modem the union of its six plates; for
  the cable the core, six arms and six plates together (the largest shape any
  state has, so a server side reach check never rejects what the client let
  the player hit). Per-state shapes would make these exact;
* **block loot with data**: a dropped computer or turtle is a plain item, the
  loot table of the mod copies `computer_id` & co. (needs P1.4);
* `isRedstoneConductor` false for computers (a computer conducts like stone
  today);
* **more than 4096 states per block** (see above).

Needed per block: id, **state properties** (name, values; the set in
`CcBlockCatalog`), default state, shape/collision (a full block is acceptable
for the first version; monitors and modems have thin shapes), hardness and
tool, loot (drop the item with the computer's components), `isRedstoneConductor`
false for computers, and the callbacks the mod implements:

* `onPlace` (computer reads its inputs), `neighborChanged` (re-read redstone and
  peripherals), `updateShape` (cables), `playerWillDestroy` / drops with data
  components, `getCloneItemStack` (pick block keeps `computer_id`);
* `use` (right click) with the **hit position and face** (monitor touch needs
  `hit.getLocation() - blockPos` to compute the character cell), sneaking state
  and the held item (pocket computer upgrades, dye, disks);
* `getStateForPlacement` inputs: horizontal facing, clicked face, player pitch
  (monitor orientation), fluid at the position (`waterlogged`);
* scheduled block ticks (`MonitorBlock.tick`) and per-tick block entity tickers
  (computers every tick);
* `isSignalSource`, `getSignal`, `getDirectSignal` (see P1.6).

Plugin: not written; `CcService.create`/`attach` (`lib/src/plugin/service.dart`)
are the calls a block entity will make instead of `/cc new` and `/cc attach`.

### P1.2 Block entities with plugin data

The mod's block entities keep state on the server and send a small update tag
to the client:

* **save data** per position (`ComputerId`, `Label`, `On`, `Capacity`,
  `TerminalSize` for computers; turtle inventory, fuel, upgrades; monitor
  `XIndex`/`YIndex`/`Width`/`Height`): needs persistence in the chunk and load/
  unload events;
* **update tag** (`getUpdateTag`) included in chunk data and sent with
  `ClientboundBlockEntityDataPacket` when it changes
  (`BlockEntityHelpers.updateBlock`): monitors need `{XIndex, YIndex, Width,
  Height}`, turtles `{Label, Fuel, Color, Overlay, LeftUpgrade, RightUpgrade,
  Animation}`; computers, speakers, modems, drives and printers need no
  client data (their look is in the block state);
* lifecycle callbacks: created, loaded, `setRemoved`, chunk unload (stop the
  computer), "players are watching this chunk" (`MonitorWatcher.onWatch` sends
  every monitor's screen when a chunk is sent).

Today the `BlockEntity` resource only exposes vanilla views.

### P1.3 Custom menus and `advanced_open_screen`

The computer GUI is a `computercraft:computer` menu with **9 invisible slots**
(the player's hotbar) and **1 data slot** (`isOn`). The server must:

1. register the menu type (P0.3) and create menu instances with that slot
   layout, a `stillValid` check (distance and the computer still existing),
   data slots, and a `removed` callback (the mod stops delivering input and
   releases keys when the menu closes: `inventory-close-event` must say *which*
   menu);
2. open it with a window id taken from the host's own container counter and send
   `neoforge:advanced_open_screen` (window id, menu type id, title component,
   extra data) **instead of** the vanilla open-screen packet, then
   `ClientboundContainerSetContent` for its slots and `SetData` for the data
   slot; the plugin builds the payload today (`CcNetwork.open`, using
   `AdvancedOpenScreenMessage` and `ComputerContainerData`) but cannot get a
   window id or a registered menu type;
3. for turtles: 16 + 36 + 2 slots with item transfer semantics
   (`quickMoveStack`); for disk drives and printers: vanilla-like container
   menus with slot validity rules.

The key/mouse/paste/upload messages carry that window id; the plugin's
`CcNetwork` already maps it to a computer (`_sessionFor`).

### P1.4 Custom data components

Item stacks of CC's items carry `computercraft:computer_id` (VarInt),
`storage_capacity` (VarLong), `terminal_size` (2 VarInts), `on`, `fuel`, ... and
vanilla components. Components in a patch are **not length prefixed**, so the
host cannot skip a value it does not understand: for every modded component
type the host needs a *codec description* to read stacks the client sends
(creative inventory, drag and drop, menus) and to write them.

Needed: `registerDataComponentType(key, networkSynchronized, codec)` where the
codec is either a small declarative description (sequence of VarInt, VarLong,
bool, string, identifier, byte array, nested patch, optional) interpreted by
the host, or a callback into the plugin that returns the byte length of a
value. Plus `ItemStack.setComponent` for those types, and persistence (they
are saved with the stack). Today `ItemStack.setComponent` accepts only the
`DataComponent` enum; `minecraft:custom_data` can hold the same information
server side but the client reads the mod's components, not `custom_data`.

### P1.5 Dynamic registries

`computercraft:turtle_upgrade` and `computercraft:pocket_upgrade` are
datapack registries with a network codec, sent in the configuration phase as
`registry_data` for the mod's data pack entries (lists and JSON in
client-compat.md section 1.3). The host needs to let a plugin contribute entries
(or whole registries) to `registry_data`, with the right known-packs behaviour.
Without them the client has no turtle or pocket computer upgrades; computers,
monitors and modems do not need them.

### P1.6 Redstone

* Queries: the redstone power at a neighbour position as seen from a side
  (`RedstoneUtil.getRedstoneInput`: received power, and the emitted power
  of non-conducting neighbours) and `BundledRedstone.getOutput` (a plugin
  extension point).
* Output: a plugin block must answer `getSignal`/`getDirectSignal` for its
  sides, and the host must update neighbours when the plugin says the output
  changed (`RedstoneUtil.propagateRedstoneOutput`: neighbour update on the block
  and its neighbours).

Plugin: `Computer.redstone` (`RedstoneState`) holds both directions and
`pollRedstoneChanges`-style `updateOutput()`; the block entity will poll it
every tick.

## P2: the rest of the blocks and items

* **Interaction events** carrying the hit vector, face and hand
  (`PlayerInteractEvent` / block interact), cancellable, plus the *held item*:
  monitor touch, disk drives, the pocket computer on a lectern.
* **Chunk watch events** (`player starts watching chunk`): to send monitor
  screens and pocket computer state when a client first sees them.
* **Creative inventory and click packets with modded stacks**: decoding the
  item ids and component values of CC items in `SetCreativeModeSlot`,
  `ContainerClick` (needs P1.4).
* **Custom recipes**: serializers `impostor_shaped`, `transform_shaped`,
  `colour`, `turtle_upgrade`, `disk`, ... Players cannot craft computers
  without a recipe API; until then they can be given items by command.
* **Server config sync**: `neoforge:config_file` for `computercraft-synced.toml`
  (see client-compat.md 1.5); an empty file is the likely safe minimum.
* **Turtles**: a *fake player* entity for digging, placing and attacking, item
  entity pickup, block breaking progress and drops, entity raycasts, fuel and
  a movement animation synced through the block entity update tag. This is the
  largest single item and may be deferred indefinitely.
* **Speakers**: sending the speaker payloads needs only custom payloads
  (available) plus entity ids (available); no host work.
* **Pocket computers**: item ticking while held, the `computer` component with
  the instance UUID, per-player state packets (custom payload only).

## P3: polish

Sounds registered as sound events (none needed), advancement/loot integration,
the `/computercraft` command with its custom argument types (needs
`command_argument_type` entries and server command tree support for them),
JEI/recipe book displays, `ClientboundCustomChatCompletions` for the CC chat
table messages (`computercraft:chat_table` works as a payload).

## What works without any of it

Everything under `lib/src/lua`, `lib/src/machine` and `lib/src/protocol`
runs on the server today, headless:

* computers with ids, labels, a persistent disk with quota, the real ROM and
  BIOS loaded from the mod jar (or a built-in fallback BIOS), events, timers,
  `redstone` inputs/outputs, monitors, wireless modems (so `rednet`),
  boot/shutdown/reboot with CC's timing rules, the time slicing and the 7 s
  abort;
* the `/cc` command: `new`, `list`, `on|off|reboot|terminate`, `term` (the
  terminal in chat, colours mapped to chat colours), `type`/`run`/`key`
  (input), `label`, `remove`, `attach|detach|monitor` (peripherals),
  `redstone` (inputs), `status`, `registry`;
* with `"neoforge": true` and a host with the pre-brand hold and the flavour
  (P0.1/P0.2, subject to compile): the handshake (full negotiation), the
  registry sync for the 5 registries with a vanilla list (block, item, block
  entity type, data component type, menu) plus `computercraft:recipe_function`
  (`recipe_serializer` and `command_argument_type` are not synchronised, see
  P0.3), the 23 items registered with the item registry, **CC's blocks
  registered with the block registry** (computers, turtles, speakers, drives,
  printers, monitors, modems and cables can be placed from the creative tab
  and stay in the world, can be mined and drop their item; they do nothing yet,
  and the cable is partial, see P1.1), and the codecs for every payload
  (clientbound and serverbound), the upload reassembler and the menu data.
  Block entities, menus, custom data components, the use events and the
  placement state were missing here and have been added to the host and wired
  in the plugin since (see Status at the top; unverified).

## Effort estimate

Honest numbers for someone who knows the Pumpkin code base; the plugin side
assumes the host features exist.

| Milestone | Host | Plugin |
| --------- | ---- | ------ |
| Real client **joins** and sees CC items in the creative tab | P0.1, P0.2 provided (to be verified live); P0.3 for items provided | done (flag) |
| **Computers, monitors, wireless modems** usable with the real GUI (placeable blocks, GUI, keyboard, screen, redstone, rednet, disks excluded) | P0.3 (blocks/BE/menu/components), P1.1-P1.4, P1.6: ~4-6 weeks | block entities, monitor multiblock `Expander`, menu session wiring, touch, persistence of ids: ~2-3 weeks, plus fixing what the first real `bios.lua` run reveals in the VM |
| + disk drives, printers, speakers, cables and wired modems, redstone relay, lectern, recipes | P1.5, P2 (menus with real slot logic, recipes, chunk watch) : ~2-3 weeks | ~3-4 weeks (wired network graph, printer/drive menus, DFPWM speaker) |
| + **turtles and pocket computers** (full parity) | fake player, entity/item interaction, animation: ~3-4 weeks | ~4-6 weeks (turtle API is ~30 commands over world access) |

Total for the mod's main features: roughly **3 to 5 months** of one person's
focused work, most of it on the host side of the first two milestones; a
"computers, monitors and modems only" release is a **6 to 9 week** project.
