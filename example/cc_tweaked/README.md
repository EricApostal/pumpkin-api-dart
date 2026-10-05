# cc_tweaked

The **server side of [CC: Tweaked](https://github.com/cc-tweaked/CC-Tweaked)**
for Pumpkin, written in Dart. The goal is the real thing: a server the real
CC: Tweaked NeoForge client (and its real Lua ROM) can connect to. The
Pumpkin host cannot do everything that needs yet, so this plugin is built in
two layers:

* **Runs today, headless**: CraftOS computers (the real `bios.lua` and `rom/`,
  loaded from the mod jar you provide) on a Lua VM written for this plugin,
  with terminals, disks, redstone, monitors and wireless modems, driven by a
  `/cc` debug command that shows a computer's screen in chat.
* **Wired to the host's new features, unverified**: the codecs of every CC
  network payload, the registry lists and block catalogue, the NeoForge
  handshake, and (with `"neoforge": true`) the registration of CC's items,
  blocks, block entity types, menu types and data component types, computers as
  block entities, the computer GUI over `neoforge:advanced_open_screen`, the
  terminal sync and the serverbound key/mouse/paste/action/upload messages,
  pocket computers on right click. What the host provides and what is still
  missing is in [docs/host-requirements.md](docs/host-requirements.md).

> **Never run.** This package was written under rules that forbade tests,
> scripts and test clients, and no server was available: it passes
> `dart analyze` and builds to a wasm component, but no Lua program has ever
> executed in it, and the host features it now uses (block entities, menus,
> custom data components, use events, placement rules) were themselves written
> without being built or run. **Everything under "Computers in the world" is
> unverified until a rebuilt host and a real CC: Tweaked client exercise it**;
> the uncertain byte level points are listed there. Expect bugs on first
> contact; see [docs/engine.md](docs/engine.md#honest-status).

| Document | Contents |
| -------- | -------- |
| [docs/client-compat.md](docs/client-compat.md) | what the real client needs: registries, block states, every payload byte by byte, menus, block entity data, item components, the Lua dialect, ROM, APIs, time slicing |
| [docs/host-requirements.md](docs/host-requirements.md) | the prioritised list of host features, with reasoning, and an effort estimate |
| [docs/engine.md](docs/engine.md) | why ApolloVM cannot run CraftOS, what was chosen instead, the VM's design and limits |

## Build and install

The plugin is a standalone package (it is **not** in the repository's pub
workspace; its `pubspec.yaml` redirects the workspace-relative dependencies).
It needs Dart 3.14+ like every plugin of this repository (`puro use master`,
the repository's `.puro.json` already says so).

```sh
cd example/cc_tweaked
dart pub get
dart run pumpkin_tools build        # -> build/cc_tweaked.wasm  (~4.2 MB)
dart analyze                        # clean
```

1. Copy `build/cc_tweaked.wasm` into the server's `plugins/` directory and
   approve its permissions: `fs.write.data` (its data folder), and
   `registry.items`, `registry.blocks`, `registry.block-entities`,
   `registry.menus` and `registry.components` (only used with `"neoforge": true`).
2. **The ROM.** The CC: Tweaked ROM and `bios.lua` are not redistributed. Put
   the mod jar (any `.jar` file name; the jar of the mod build your players
   use) into `plugins/data/cc_tweaked/`, then restart. The plugin finds the jar
   by itself (or set `"jar": "name.jar"` in `config.json`), reads
   `data/computercraft/lua/bios.lua` and `data/computercraft/lua/rom/` out of
   it with a built-in zip reader, and logs `CraftOS image: <jar> (N ROM files),
   mod version X`. Without a jar computers boot a tiny built-in BIOS
   (`ls cat rm mkdir id label clear shutdown reboot`, a Lua prompt, and running
   programs from the disk): enough to try everything else.
3. Try it in game or from the console:

```
/cc new                    create an advanced computer (turns on)
/cc term 0                 show its screen in chat
/cc run 0 edit hello       type a line and press enter (CraftOS: opens the editor)
/cc type 0 print("hi")     type text without enter, /cc key 0 enter presses a key
/cc terminate 0            Ctrl+T
/cc attach 0 top monitor 2 2     a 2x2 monitor on the top side; /cc monitor 0 top shows it
/cc attach 0 left modem          a wireless modem; two computers with modems can rednet
/cc redstone 0 right 15          drive a redstone input
/cc status | registry            server details; what CC adds to the registries
```

Messages and permissions: `cc_tweaked:command.use` (everyone: manage your own
computers, up to `max_computers_per_player`) and `cc_tweaked:command.admin`
(operators: every computer, `status`, `registry`).

## Configuration

`plugins/data/cc_tweaked/config.json` is written on first start (edit and
restart):

| Key | Default | Meaning |
| --- | ------- | ------- |
| `jar` | `""` | file name of the CC: Tweaked jar in the data folder; empty = first usable `.jar` |
| `slice_ms` | 3 | most Lua time one computer gets per server tick |
| `tick_budget_ms` | 12 | most Lua time all computers share per tick (round robin) |
| `timeout_seconds` | 7 | execution time without yielding before "Too long without yielding" (CC: 7) |
| `abort_grace_seconds` | 1.5 | extra time before the computer is shut down (CC: 1.5) |
| `disk_quota` | 1000000 | bytes per computer disk (CC: `computer_space_limit`) |
| `maximum_open_files` | 128 | as in CC |
| `terminal_width`, `terminal_height` | 51, 19 | terminal size of computers |
| `max_computers_per_player` | 5 | 0 = unlimited |
| `default_computer_settings` | `""` | `name=value,...` (CC: `default_computer_settings`) |
| `neoforge` | `false` | install the NeoForge handshake (`NeoForgeNegotiation.full`, with the host's pre-brand hold) + registry sync, register CC's items, blocks (with placement rules), block entity types, menu types and data component types, and handle computers in the world; needs a host with `configuration-pre-brand-event`, `set-connection-flavour`, the block registry and placement rules, block entities, menus, custom data components and the use events (below) |

Data layout: `computers.json` (ids, labels, owners, power, peripherals),
`computers/<id>/` (the computer's disk, the `/` of the Lua file system).

### CC blocks in the world (`"neoforge": true`)

With the flag on, the plugin registers the 23 items first and then CC's blocks
with the host's block registry, in the order of the registry sync
(`CcRegistries.blocks`, ids `1286 + position`), links each block item to its
block (`set-block-item`) and joins the block tags (`minecraft:mineable/pickaxe`,
`wither_immune`, `computercraft:computer|monitor|turtle|wired_modem`). The
data is `lib/src/protocol/blocks.dart` (the Java class of every block is cited
there), the registration and its checks `lib/src/plugin/block_install.dart`.
It verifies, and refuses to load with a message if any is wrong: the host's
vanilla block and state counts, block ids, base state ids with no gap after
the vanilla states, state counts, the host's state ids against the numbering
of CC's own property definitions, and the item id of every link.

**What the blocks give by themselves** (by construction and offline checks;
not yet seen on a live client): a real client can place the computers (normal,
advanced, command), turtles, speakers, disk drives, printers, monitors,
wireless modems, full wired modems and cables from the creative tab; the block
stays, is drawn by the client with the state the server sent, can be mined
(pickaxe speed, strength as in CC, the command computer is unbreakable) and
drops its item. Only the computers have behaviour (next section); the other
blocks have no block entity: monitors show nothing, turtles are invisible,
speakers, drives and printers do nothing.

**Placement state.** The registration also sets the placement rules of the
host's `block-placement` interface (`CcBlockSpec.placement`, each rule cites
the Java `getStateForPlacement` it mirrors): `facing` from the player's
horizontal direction (opposite for computers, speakers, drives, printers,
monitors; the same direction for turtles and the redstone relay), the clicked
face for wireless modems, the monitor `orientation` from the pitch (66.5
degrees, as in `MonitorBlock`), and `waterlogged` from the fluid for turtles
and wireless modems. Not set: the cable's `waterlogged` and modem placement
(`CableBlockItem` places modems in code, not through `getStateForPlacement`).
If the host rejects a rule (a property value it lacks) the plugin refuses to
load with the host's message.

**State limit.** CC has **6940** block states (the cable alone has
25 x 2 x 2^6 x 2 = 6400). The host's limit per block was 4096 and is now
16384 (`MAX_STATES_PER_BLOCK` in the Rust registry, mirrored by
`BlockRegistryChecks.maxStatesPerBlock` in `pumpkin_api`), so with a current
host all 16 blocks register in full, including the cable with its 6400 states,
the `lectern` and the `redstone_relay` (the plugin plans from that constant and
logs a warning for every block that is reduced or left out when a host has a
smaller limit). Not verified on a built host.

### Computers in the world (`"neoforge": true`)

Everything below is written from the CC: Tweaked sources (the Java classes are
named in the code) and the host's WIT, and **was never run**: it needs the
rebuilt host and a real CC: Tweaked client.

| Step | What the plugin does | Source mirrored |
| ---- | -------------------- | --------------- |
| Load | registers 16 block entity types (`computercraft:<block>`, valid for the block of the same name), 7 menu types and 14 data component types with exact codecs, after the items and blocks, in the registry sync's order; verifies every id (and the host's vanilla counts) and refuses to load if one differs (`lib/src/plugin/registry_install.dart`, `protocol/components.dart`) | `ModRegistry.BlockEntities`, `.Menus`, `.DataComponents` |
| Place | the use event of the item remembers its `computer_id` and custom name; the place event (which fires before the block exists) creates the block entity one tick later with `set-block-entity-data` (save data `ComputerId`, `Label`, `On`; no client data) and restores the id | `AbstractComputerBlockEntity.saveAdditional/applyImplicitComponents` |
| First use | a computer block without an id gets a new computer when it is first opened (CC's `createServerComputer`), within `max_computers_per_player` | `AbstractComputerBlockEntity.createServerComputer` |
| Right click | `player-use-block-event` without sneaking cancels the click, turns the computer on and calls `open-menu` for `computercraft:computer` with the `ComputerContainerData` bytes as extra data (the host sends `neoforge:advanced_open_screen`), zero tracked slots, data slot 0 = `isOn` | `AbstractComputerBlock.useWithoutItem`, `ComputerContainerData` |
| While open | `computer_terminal` is sent when the terminal changed (checked every other tick), `isOn` is resent when it changes; key, key_up, char, mouse click/drag/up/scroll, paste, terminate/turn on/shut down/reboot and file uploads (`file_transfer` event, `upload_result`) feed the machine; the menu closes when the player is more than ~9 blocks away or the computer is gone | `ServerInputState`, `UserComputerInput`, `ComputerMenu` |
| Closing | `menu-closed-event` ends the session and releases held keys and buttons | `AbstractComputerMenu.removed` |
| State | the block state `state` (off, on, blinking) follows the machine with `set-block-state`; `On` and `Label` are written back to the entity when they change | `AbstractComputerBlockEntity.serverTick`, `ComputerBlockEntity.updateBlockState` |
| Chunks | `block-entity-load-event` brings the machine up again (and turns it on if `On` was set), the unload event stops it; computers in blocks are not started at plugin load, only when their chunk loads (or on first use) | `loadAdditional`, `unload` |
| Breaking | the broken block's item is given to the player with the `computer_id` component and the label (the host's drop event cannot carry components, see below); the machine stops, its disk stays under its id | `AbstractComputerBlock.playerWillDestroy`, `collectSafeComponents` |
| Pocket computers | `player-use-item-event` with a pocket computer cancels the use, creates a computer if the item has no `computer_id` (written to the held item with `set-item-in-hand`), turns it on and opens `computercraft:computer` (`computercraft:pocket_computer_no_term` from the off hand) | `PocketComputerItem.use`, `openMenu` |

`/cc ...` keeps working on all computers, in blocks too (a computer whose chunk
is not loaded is brought up for the command); `/cc open <id>` opens the GUI of
any computer through the same path, and `/cc list` shows where a computer
stands.

**What is not done.** Monitors (no entity, no `monitor_client` terminal, no
touch, and peripherals are not discovered from neighbouring blocks: the host has
no neighbour-changed callback, so `/cc attach` is still how a computer gets a
monitor or modem), disk drives and printers (menus with real slot logic: the host
has no menu behaviour), turtles, speakers, cables, redstone in the world (no
signal API), the command computer's GUI, `pocket_computer_data` (the state of a
pocket computer's item model), lecterns, `getCloneItemStack` (pick block keeps
the id), recipes, locks, the `Capacity`/`TerminalSize` of a stack are kept but
not applied to new machines. A computer item dropped by something other than a
player breaking the block (explosion, piston, a full inventory) loses its id:
the plain item is dropped, because no plugin call drops an item entity with
components. Two blocks with the same `computer_id` (a duplicated stack) do not
share a machine: the second one gets a new computer on first use.

**Uncertain, to check first on a live client** (details in
[docs/host-requirements.md](docs/host-requirements.md#open-questions-of-the-wiring)):
the client opens the menu from the host's `advanced_open_screen` payload with
zero slots and accepts `computer_terminal` for it; the block entity data the
client expects is really empty for computers; `Hand.left` is the off hand in
the use events; and the item the player gets back after breaking a computer
shows the right id.

### Combining with other NeoForge plugins

With `"neoforge": true` this plugin installs the NeoForge handshake, and **only
one plugin per server may do that**: a client answers every `neoforge:register`
query and registry sync it gets, so two handshakes would both talk to it, and a
second registry sync replaces the first (a synced registry has to contain
*every* mod's entries). A server with CC: Tweaked **and** Lonsdaleite therefore
needs one plugin that owns the NeoForge spec with both mods' registries and
channels; until then keep `neoforge` off here or run the other plugin without its
handshake. A proposal for sharing the spec between plugins (an IPC contribution
channel, an owner plugin, or JSON files) is in
[packages/pumpkin_neoforge/README.md](../../packages/pumpkin_neoforge/README.md#one-neoforge-plugin-per-server).

The handshake is the library's *full* mode: before the host's brand the plugin
sends the `neoforge:register` query, waits for the client's answer, negotiates the
16 required `computercraft:*` payloads, marks the connection as NeoForge in the
host and sends `neoforge:network`; a vanilla client (no answer) is let through
(`NonNeoForgePolicy.allow`). It also sends the elytra attribute and the empty
`neoforge:recipe_content` that a NeoForge connection needs. The registry sync
covers block, item, block entity type, data component type and menu plus
`computercraft:recipe_function`; `recipe_serializer` and `command_argument_type`
are **not** synchronised (Pumpkin has no list of their vanilla entries, see
`CcRegistries.synchronised`), which is safe because the host never writes ids of
those registries for CC's entries.

## How it is built

```
lib/src/lua/        Lua 5.1 + 5.2 features: lexer, parser, compiler, bytecode VM with
                    explicit frames (coroutines yield anywhere, preemptible), stdlib
lib/src/machine/    binding free CC machine: Terminal/Palette (= TerminalState layout),
                    FileSystem + mounts (writable quota mount, zip/ROM mount), redstone,
                    peripherals (monitor, wireless modem), the Lua APIs (term, fs, os,
                    redstone, peripheral), Computer (power state machine, event queue,
                    timers, time slicing), ComputerManager, CraftOS image from the jar
lib/src/protocol/   payload codecs (messages.dart), TerminalState, upload reassembly,
                    registry lists + NeoForge spec, block definitions with placement
                    rules (blocks.dart), data component codecs (components.dart), menu data
lib/src/plugin/     the host glue: config, data-folder storage, service, /cc, chat view,
                    network sessions + GUI (network.dart), block registration
                    (block_install.dart), block entity / menu / component type registration
                    (registry_install.dart), computers in the world (world_computers.dart),
                    block state ids (block_states.dart), the plugin class
bin/main.dart       runPlugin(CcTweakedPlugin())
```

Only `lib/src/plugin` imports host bindings; everything else analyses and
compiles on its own. The integration points:

* `CcService.create / resumeAt / suspend / computer(id)` and `Computer.tick`,
  `terminal`, `redstone`, `setPeripheral`, `createInput()`: what the block
  entities call (`CcWorldComputers`) and what `/cc` calls;
* `CcNetwork` (`plugin/network.dart`): opens the menu through the host
  (`Player.openPluginMenu` with the `ComputerContainerData` as extra data),
  the serverbound handlers (key, mouse, paste, action, upload) and the
  clientbound terminal pushes for a player with a computer open;
* `CcWorldComputers` (`plugin/world_computers.dart`): the events of the host
  (use item, use block, block place, block entity load/unload, block drop);
* `CcRegistries.serverSpec(version)` + `plugin.dart` `_installNeoForge`: the
  registry sync and channel negotiation (`NeoForgeNegotiation.full`, with the
  pre-brand hold of the host);
* `CcRegistries`, `CcBlockCatalog`, `CcRegistryIds`: what the host must register
  and the ids the client will use;
* `MonitorPeripheral.touch(x, y)` / `resizeBlocks()` for multiblock monitors.

## What maps to the real mod

| Real CC: Tweaked | Here |
| ---------------- | ---- |
| Cobalt Lua VM, `ILuaAPI`s | own Lua VM; `term`, `fs`, `os`, `redstone`/`rs`, `peripheral` natives; everything else (`rednet`, `textutils`, `settings`, `shell`, `window`, ...) is the real ROM Lua |
| `ComputerExecutor`, `TimeoutState` | `Computer` + `LuaMachine`: same states, 7 s soft abort, 1.5 s hard abort, queue limit 256, 50-tick start delay; time slicing per server tick instead of threads |
| `FileSystem`, mounts, quota | same path rules, messages, 500 byte minimum, `/rom` read-only |
| `Terminal`, `TerminalState` | same layout and colour indexes (copy to the payload is a memcpy) |
| monitors, wireless modems | `MonitorPeripheral` (text scale, terminal size formula, `monitor_touch`/`monitor_resize`), `WirelessModem` (channels, range, `modem_message`) |
| network payloads, registries | codecs and lists, byte for byte from the source |

## Not implemented

* The client link beyond computers: monitors in the world, disk drives,
  printers, turtles, speakers, wired modems/cables, redstone relays, redstone
  from the world, pocket computer state sync (see "What is not done" above and
  host-requirements.md). Computers in the world and pocket computers are wired,
  unverified.
* `http` (absent from `_G`, which is what CC does when http is disabled),
  turtles, the command computer, bundled cables between blocks, `gps` (the ROM
  program exists, no location source), the `commands` API.
* Lua: `string.pack/unpack`, `debug.getlocal/getupvalue`, `__gc`/`__mode`
  (see engine.md). Time zones: `os.date`/`os.time("local")` are UTC.
* The in-game clock follows the overworld's time of day, re-read every 100
  ticks (the day counter uses the world age); it does not follow `/time set`
  smoothly.

## Known risks (read before blaming the VM)

* Library functions that call back into Lua (`table.sort` comparators,
  `string.gsub` callbacks) cannot be interrupted: a pathological one can hold
  the server tick for up to ~2 seconds before it fails.
* Plugin timers and the host's resource handles: all host calls (world time,
  player lookup) happen in the tick callback and dispose what they create; Lua
  code never touches host resources, so a long-running script cannot leak
  handles (this was a design constraint, see `computer.dart`).
* Not tested against real `bios.lua` output: see the "never run" note.

Licence note: the CC: Tweaked ROM is MPL-2.0 licensed Lua inside a jar with
other licences; this plugin only reads it from your copy. The plugin's own code
is part of this repository.
