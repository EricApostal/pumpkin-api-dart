# What the real CC: Tweaked client needs from a server

This page lists, byte for byte where it matters, everything the CC: Tweaked
NeoForge mod expects from the server it connects to, read from the mod's
source. It is the specification behind `lib/src/protocol/` (the codecs and the
registry lists) and the input to [host-requirements.md](host-requirements.md).

* [0. What was read](#0-what-was-read)
* [1. Registries and what NeoForge verifies](#1-registries-and-what-neoforge-verifies)
* [2. Network payloads](#2-network-payloads)
* [3. Opening a computer: menus, block entities, item components](#3-opening-a-computer-menus-block-entities-item-components)
* [4. The Lua side](#4-the-lua-side)
* [5. Uncertain or not analysed](#5-uncertain-or-not-analysed)

## 0. What was read

| Item | Value |
| ---- | ----- |
| Repository | <https://github.com/cc-tweaked/CC-Tweaked>, branch `mc-26.3` (also exist: `mc-26.1`, `mc-26.2`, `mc-1.21.x`, ...) |
| Commit | `8b64fc4cee79b97f580431983a8cab5d8849badc` (2026-10-03, "Update mod dependencies...") |
| Mod version | `1.120.3` (`gradle.properties`, `isUnstable=true`) |
| Minecraft / NeoForge | `26.3` / `26.3.0.45-beta` (`gradle/libs.versions.toml`; the mod accepts `[26.3.0.45-beta, 26.4)`, `neoforge.mods.toml`) |
| Lua runtime | Cobalt `0.9.9` (`cc.tweaked:cobalt`, `strictly`) |
| NeoForge side | `neoforged/NeoForge` branch `26.3.x` (for `advanced_open_screen`, `ConfigFilePayload`); `neoforged/FancyModLoader` `main` (for `ModConfig`) |

Paths below are relative to the CC repository, with `common` for
`projects/common/src/main/java/dan200/computercraft`, `core` for
`projects/core/src/main/java/dan200/computercraft/core`, and `net` for
`.../shared/network`. The forge (NeoForge) entry point is
`projects/forge/src/main/java/dan200/computercraft/ComputerCraft.java`.
Nothing here was observed on a live client; "uncertain" marks what the source
does not settle.

## 1. Registries and what NeoForge verifies

Everything is registered by `shared/ModRegistry.java` through
`RegistrationHelper` -> NeoForge `DeferredRegister` in the mod id
`computercraft`. A server reproduces the **numeric ids** of these entries, in
registration order, through the `neoforge:frozen_registry` sync (see
[docs/neoforge-protocol.md](../../docs/neoforge-protocol.md)). The lists are
in `lib/src/protocol/registries.dart`; `/cc registry` prints the counts.

### 1.1 Synchronised registries

| Registry | Entries added (in id order after all vanilla ones) |
| -------- | -------------------------------------------------- |
| `minecraft:block` (16) | `computer_normal`, `computer_advanced`, `computer_command`, `turtle_normal`, `turtle_advanced`, `speaker`, `disk_drive`, `printer`, `monitor_normal`, `monitor_advanced`, `wireless_modem_normal`, `wireless_modem_advanced`, `wired_modem_full`, `cable`, `lectern`, `redstone_relay` |
| `minecraft:item` (23) | `computer_normal`, `computer_advanced`, `computer_command`, `pocket_computer_normal`, `pocket_computer_advanced`, `turtle_normal`, `turtle_advanced`, `disk`, `treasure_disk`, `printed_page`, `printed_pages`, `printed_book`, `speaker`, `disk_drive`, `printer`, `monitor_normal`, `monitor_advanced`, `wireless_modem_normal`, `wireless_modem_advanced`, `wired_modem_full`, `redstone_relay`, `cable`, `wired_modem` (the lectern has no item) |
| `minecraft:block_entity_type` (16) | one per block, named like the block, in this order: `monitor_normal`, `monitor_advanced`, `computer_normal`, `computer_advanced`, `computer_command`, `turtle_normal`, `turtle_advanced`, `speaker`, `disk_drive`, `printer`, `wired_modem_full`, `cable`, `wireless_modem_normal`, `wireless_modem_advanced`, `lectern`, `redstone_relay` |
| `minecraft:data_component_type` (14) | `computer_id`, `storage_capacity`, `terminal_size`, `left_turtle_upgrade`, `right_turtle_upgrade`, `fuel`, `overlay`, `top_pocket_upgrade`, `back_pocket_upgrade`, `computer`, `on`, `treasure_disk`, `disk_id`, `printout` |
| `minecraft:menu` (7) | `computer`, `pocket_computer_no_term`, `pocket_computer_lectern`, `turtle`, `disk_drive`, `printer`, `printout` |
| `minecraft:recipe_serializer` (10) | `impostor_shaped`, `impostor_shapeless`, `transform_shaped`, `transform_shapeless`, `colour`, `clear_colour`, `turtle_upgrade`, `pocket_computer_upgrade`, `printout`, `disk` |
| `minecraft:command_argument_type` (3) | `tracking_field`, `computer`, `repeat` (only matter if the server sends commands that use them) |
| `computercraft:recipe_function` (1) | `copy_components`. A mod registry made with `new RegistryBuilder<>(RecipeFunction.REGISTRY).sync(true)` (`ComputerCraft.registerRegistries`), so it is part of the sync |

Not synchronised and so needing nothing on the wire: `minecraft:creative_mode_tab`
(`computercraft:tab`), `minecraft:loot_condition_type` (`block_named`,
`player_creative`, `has_id`; server side only), the type registries
`computercraft:turtle_upgrade_type` / `computercraft:pocket_upgrade_type`
(created without `.sync(true)`; their entries are referred to *by name*
inside the datapack entries below), the creative tab content (built from
client code), permissions (`computercraft:command.*`, server side).

CC registers **no** entity types, fluids, sounds, mob effects, particles or
stats. `assets/computercraft/sounds.json` only defines a sound used by a test
(`computercraft:empty`), not a registry entry.

### 1.2 Block states

Each block's states are enumerated like vanilla's `StateDefinition`:
properties sorted by name, the first varying slowest, values in the order the
property lists them (booleans `true`, `false`). The client appends the states
of the modded blocks after all vanilla ones, following the `minecraft:block`
snapshot order (`NeoForgeRegistryCallbacks.BlockCallbacks`, see the NeoForge
protocol page), so the server must number block states the same way when it
writes chunks. `lib/src/protocol/blocks.dart` has the machine readable form (with the Java
class each block comes from); **6940 states** in total. (This page first said
3740: that counted the cable as 3200 states, but its nine properties multiply
to 25 x 2 x 2^6 x 2 = **6400**; the other fifteen blocks have 540.)

| Block | Properties (source: `createBlockStateDefinition`) | States |
| ----- | ------------------------------------------------ | -----: |
| `computer_normal`, `computer_advanced`, `computer_command` | `facing` (horizontal: north, east, south, west), `state` (`off`, `on`, `blinking`) | 12 each |
| `turtle_normal`, `turtle_advanced` | `facing` (horizontal), `waterlogged` | 8 each |
| `speaker` | `facing` (horizontal) | 4 |
| `disk_drive` | `facing` (horizontal), `state` (`empty`, `full`, `invalid`) | 12 |
| `printer` | `bottom`, `facing` (horizontal), `top` | 16 |
| `monitor_normal`, `monitor_advanced` | `facing` (horizontal), `orientation` (`up`, `down`, `north`), `state` (16 edge states: `none`, `l`, `r`, `lr`, `u`, `d`, `ud`, `rd`, `ld`, `ru`, `lu`, `lrd`, `rud`, `lud`, `lru`, `lrud`) | 192 each |
| `wireless_modem_normal`, `wireless_modem_advanced` | `facing` (all six: down, up, north, south, west, east), `on`, `waterlogged` | 24 each |
| `wired_modem_full` | `modem`, `peripheral` | 4 |
| `cable` | `cable`, `down`, `east`, `modem` (25 variants: `none` and `<side>_{off,on,off_peripheral,on_peripheral}` for six sides), `north`, `south`, `up`, `waterlogged`, `west` | 6400 |
| `lectern` (extends `LecternBlock`) | `facing` (horizontal), `has_book`, `powered` | 16 |
| `redstone_relay` | `facing` (horizontal) | 4 |

Block entities exist for every block (the `BlockEntityType` of the same name);
`computer_command` and the command computer use `AdminBlockEntityType`
(`onlyOpCanSetNbt`). Block settings (strength, `isRedstoneConductor` false for
computers) are server side.

### 1.3 Datapack (dynamic) registries

`ComputerCraft.registerDynamicRegistries` registers two world registries with
**network codecs** (`event.worldRegistry(REGISTRY, codec, codec)`), so their
entries are sent to the client in the configuration phase like any synchronised
dynamic registry (`minecraft:registry_data`, with the entry as NBT):

| Registry | Entries (from `data/*/computercraft/...`) |
| -------- | ----------------------------------------- |
| `computercraft:turtle_upgrade` | `computercraft:speaker`, `computercraft:wireless_modem_advanced`, `computercraft:wireless_modem_normal`, `minecraft:crafting_table`, `minecraft:diamond_axe`, `minecraft:diamond_hoe`, `minecraft:diamond_pickaxe`, `minecraft:diamond_shovel`, `minecraft:diamond_sword` |
| `computercraft:pocket_upgrade` | `computercraft:speaker`, `computercraft:wireless_modem_advanced`, `computercraft:wireless_modem_normal` |

Entry format, e.g. `{"type":"computercraft:wireless_modem","advanced":false,"item":"computercraft:wireless_modem_normal"}`,
`{"type":"computercraft:tool","adjective":{"translate":"upgrade.minecraft.diamond_pickaxe.adjective"},"item":"minecraft:diamond_pickaxe"}`,
`{"type":"computercraft:workbench","item":"minecraft:crafting_table"}`,
`{"type":"computercraft:speaker","item":"computercraft:speaker"}`. The `type`
is a name in the (unsynchronised) type registries above. The files ship in the
mod jar's data pack (`projects/common/src/generated/resources/data/...`).
Whether a known-packs exchange lets the server skip them: they belong to the
mod's own pack, not `minecraft:core`, so they have to be sent in full
(uncertain: not tested).

### 1.4 Tags and recipes

The mod's tags (`computercraft:computer`, `monitor`, `turtle`, `wired_modem`,
`disks`, `dyeable`, `pocket_computers`, `turtle_can_place`, ... under
`data/computercraft/tags/{block,item}`) are normal data pack tags sent with
`update_tags`; the client only needs those used by client code (none found
beyond rendering helpers). Recipes are not sent in full by 26.x servers
(only recipe displays for the recipe book), so the custom recipe serializers
matter only through the registry ids above.

### 1.5 What the NeoForge client verifies (and what that means here)

* **Every payload is required.** `ComputerCraft.registerNetwork` does
  `event.registrar("computercraft").versioned(ComputerCraftAPI.getInstalledVersion())`
  and registers all 16 channels (section 2) with `playToServer` / `playToClient`
  and *no* `.optional()`. `getInstalledVersion()` is the mod's version from
  `neoforge.mods.toml` (`version="${file.jarVersion}"`, here `1.120.3`; the
  plugin reads it from the jar's `META-INF/neoforge.mods.toml` and uses it as
  the channel version).
* Consequence: a connection the client classified as *not NeoForge* (it saw the
  brand before any `neoforge:register` query) runs
  `initializeOtherConnection`, which checks the mod's payloads against an
  empty server and disconnects: "You are trying to connect to a server that is
  not running NeoForge, but you have mods that require it." Therefore the
  server **must** open the configuration phase with the NeoForge negotiation
  (`neoforge:register` query *before* the brand), announce the 16 channels in
  `neoforge:network` (play protocol, matching flow and version string), and then
  speak NeoForge-flavoured encodings in the play phase. The plugin library's
  `NeoForgeNegotiation.full` is that handshake, and the host now offers the
  "before the brand" part (`configuration-pre-brand-event`) and the flavour
  (`set-connection-flavour`; subject to compile, untested live; see the ordering
  problem in [docs/neoforge-protocol.md](../../docs/neoforge-protocol.md)).
* Registry sync: unknown keys disconnect the client; the snapshot must contain
  all vanilla entries (the plugin does that with `RegistrySpec.vanillaPlus`).
* The mod registers a `ModConfig.Type.SYNCED` server config
  (`ComputerCraft` constructor, `ConfigSpec.serverSpec`). NeoForge sends the
  synced config files to the client with `neoforge:config_file` (`String`
  file name, byte array contents). The default file name is
  `<modid>-<type>.toml`, i.e. **`computercraft-synced.toml`** in the FML source
  read (`ConfigTracker.defaultConfigName`, suffix "-synced"); the older
  `neoforge-server.toml` in the NeoForge protocol page predates the rename
  (uncertain for the 26.3.0 tag). The client falls back to the defaults baked
  into `Config`/`ConfigSpec` when no file arrives (uncertain how a never loaded
  synced config behaves; sending an empty file is the safe candidate).
  Values the client reads: `computer_space_limit`, `upload_max_size`,
  `monitor_bandwidth`, terminal sizes, `monitor_distance` (client config),
  turtle/pocket fuel limits. All have defaults.
* NeoForge's play-phase optional payloads (`neoforge:advanced_open_screen`,
  `neoforge:advanced_container_set_data`, `neoforge:advanced_add_entity`,
  `neoforge:sync_attachments`, `neoforge:recipe_content`, ...) come with a
  NeoForge connection; CC uses `advanced_open_screen` (menus with extra data);
  its menu data slots are small numbers sent in the plain vanilla
  `ClientboundContainerSetDataPacket`.

## 2. Network payloads

All channel ids are `computercraft:<name>`; all are **play phase**; the
codecs are `StreamCodec<RegistryFriendlyByteBuf, T>`. The message classes are
in `net/client` and `net/server`. Primitives: `VarInt`, `bool`, `byte`,
`short`, `int` (4 bytes big endian), `float`, `double`, `string`/identifier =
VarInt length + UTF-8, `UUID` = two longs, `BlockPos` = packed long, enums as
`VarInt` ordinal (`FriendlyByteBuf.writeEnum`), `byte[]` = VarInt length + bytes,
`opt<T>` = `bool` then `T`. Trailing bytes are a decode error. The Dart codecs
are in `lib/src/protocol/messages.dart` and `terminal_state.dart`.

### 2.1 Clientbound (server -> client)

| Channel | Fields | Source |
| ------- | ------ | ------ |
| `computercraft:computer_terminal` | `VarInt containerId`, `TerminalState` | `ComputerTerminalClientMessage` |
| `computercraft:monitor_client` | `BlockPos` (the origin monitor), `opt<TerminalState>` | `MonitorClientMessage` |
| `computercraft:pocket_computer_data` | `UUID instance`, `enum ComputerState`, `VarInt lightState`, `opt<TerminalState>` | `PocketComputerDataMessage` |
| `computercraft:pocket_computer_deleted` | `UUID instance` | `PocketComputerDeletedClientMessage` |
| `computercraft:upload_result` | `VarInt containerId`, `enum UploadResult` (`QUEUED` 0, `CONSUMED` 1, `ERROR` 2), `opt<Component>` (network NBT) | `UploadResultMessage` |
| `computercraft:speaker_audio` | `UUID source`, position (see below), `EncodedAudio {VarInt charge, VarInt strength, bool previousBit, byte[] audio}`, `float volume` | `SpeakerAudioClientMessage` |
| `computercraft:speaker_move` | `UUID source`, position | `SpeakerMoveClientMessage` |
| `computercraft:speaker_play` | `UUID source`, position, `Identifier sound`, `float volume`, `float pitch` | `SpeakerPlayClientMessage` |
| `computercraft:speaker_stop` | `UUID source` | `SpeakerStopClientMessage` |
| `computercraft:play_record` | `BlockPos`, `opt<Holder<JukeboxSong>>` (holder codec: VarInt id + 1, or 0 and an inline song) | `PlayRecordClientMessage` |
| `computercraft:chat_table` | `string id` (max 16), `VarInt columns`, `bool hasHeaders`, [`columns` x Component], `VarInt rows`, rows x columns x Component, `VarInt additional` (Component = network NBT) | `ChatTableClientMessage` |

Speaker position (`SpeakerPosition.Message`): `Identifier level` (dimension),
`Vec3` (3 doubles), `opt<VarInt entityId>` (`MoreStreamCodecs.OPTIONAL_INT`).

**`TerminalState`** (`shared/computer/terminal/TerminalState.java`, `NetworkedTerminal.write`):

```
bool    colour
VarInt  width, height, cursorX, cursorY
bool    cursorBlink
byte    cursorBackground << 4 | cursorForeground      (colour indexes, 0 = white .. 15 = black)
VarInt  length, then `length` bytes:
          height x ( width x character byte,
                     width x colour byte (background << 4 | foreground) )
          16 x ( red, green, blue )                    the palette, channel * 255, palette index 0 = black
```

`length` must be `width*height*2 + 16*3`. A character byte is the terminal's
Latin-1-like code (`char & 0xFF`). A colour nibble `n` is the index
`log2(colors.xxx)` (white 0 .. black 15) and selects palette entry
`15 - n`. `Terminal.reset()` state: text colour 0, background 15, palette =
the defaults of `core/util/Colour.java` (`0x111111` black .. `0xf0f0f0`
white). The plugin's `Terminal` (`lib/src/machine/terminal.dart`) keeps exactly
this representation, so `TerminalState.of(terminal)` is a copy.

### 2.2 Serverbound (client -> server)

All except `upload_file` start with `VarInt containerId`, which must be the
id of the menu the player has open (`ComputerServerMessage.handle` checks
`player.containerMenu.containerId` and that the menu is a `ComputerMenu`).

| Channel | Fields | Effect |
| ------- | ------ | ------ |
| `computercraft:computer_action` | `containerId`, `enum Action` (`TERMINATE` 0, `TURN_ON` 1, `SHUTDOWN` 2, `REBOOT` 3) | queue `terminate`, or turn on / shut down / reboot |
| `computercraft:key_event` | `containerId`, `enum Action` (`DOWN` 0, `REPEAT` 1, `UP` 2, `CHAR` 3), `int key` | `key` (key, repeat), `key_up`, or `char` (`(byte) key`) events |
| `computercraft:mouse_event` | `containerId`, `enum Action` (`CLICK` 0, `DRAG` 1, `UP` 2, `SCROLL` 3), `VarInt arg`, `VarInt x`, `VarInt y` | `mouse_click`/`mouse_drag`/`mouse_up`/`mouse_scroll` (`arg` = button 1-3 or scroll direction; coordinates are 1-based character cells) |
| `computercraft:paste_event` | `containerId`, `byte[]` (VarInt length < 512) | `paste` event |
| `computercraft:upload_file` | see below | files dropped on the terminal: queues `file_transfer` |

`key` is a GLFW key code (CC's `keys` API numbers: `enter` 257, `backspace`
259, letters 65-90, ...). Input handling is `core/input/UserComputerInput.java`
(mouse events only for colour terminals, coordinates clamped to the terminal,
held keys released when the GUI closes), implemented in `lib/src/machine/input.dart`.

**`upload_file`** (`UploadFileMessage`, at most 30 KiB per message):

```
VarInt  containerId
UUID    upload id
byte    flags            1 = first message, 2 = last message
[if first]  VarInt fileCount (<= 32); per file: string name (<= 128), VarInt size, 32 bytes SHA-256
VarInt  sliceCount
per slice:  unsigned byte fileId, VarInt offset, unsigned short size, size bytes
```

On the last message the server checks every SHA-256, then queues a
`file_transfer` event with the files, and answers `upload_result`
(`QUEUED`, later `CONSUMED` when a program took the files, or `ERROR`).
`lib/src/protocol/upload.dart` reassembles and verifies.

### 2.3 Opening and updating a menu (play phase, vanilla + NeoForge)

Computers are opened with `player.openMenu(provider, extraDataWriter)`
(`PlatformHelperImpl.openMenu`); NeoForge's patch sends **instead of**
`ClientboundOpenScreenPacket` the custom payload
`neoforge:advanced_open_screen` when the extra data is non-empty:

```
VarInt  windowId (the menu's containerId)
VarInt  menu type id (registry minecraft:menu)
Component  title (network NBT)
byte[]  extra data (VarInt length + bytes)
```

(`AdvancedOpenScreenPayload`, `patches/net/minecraft/server/level/ServerPlayer.java.patch`.)
For `computercraft:computer` (and `turtle`) the extra data is
`ComputerContainerData` (`net/container/ComputerContainerData.java`):

```
VarInt  ComputerFamily ordinal    (NORMAL 0, ADVANCED 1, COMMAND 2)
TerminalState
ItemStack (optional form)         the "display stack" (see 3.3)
VarInt  uploadMaxSize
```

After that the server sends `computercraft:computer_terminal` whenever the
terminal changes (`ServerComputer.tickServer` -> `onTerminalChanged`, only to
players whose open menu is that computer's) and keeps `isOn` in menu data slot 0
(`SingleContainerData`, a vanilla `ClientboundContainerSetDataPacket` with a
short value).

## 3. Opening a computer: menus, block entities, item components

### 3.1 Menus

| Menu type | Factory | Slots | Data slots |
| --------- | ------- | ----- | ---------- |
| `computer` | `ContainerData.toType(ComputerContainerData.STREAM_CODEC, ComputerMenuWithoutInventory...)` | **9 invisible slots** = the player's hotbar (`InvisibleSlot` over `Inventory` 0..8) | 1 (`isOn`) |
| `pocket_computer_no_term` | same codec | same 9 | 1 |
| `pocket_computer_lectern` | `PocketComputerLecternMenu.Data` | (lectern variant) | not analysed |
| `turtle` | `TurtleMenu.ofMenuData` | 16 turtle slots (4x4 at x 175+17, y 134+1), 27 player slots, 9 hotbar, 2 upgrade slots | 1 (selected slot) |
| `disk_drive` | `new MenuType<>(DiskDriveMenu::new, FeatureFlags.VANILLA_SET)` | vanilla style: 1 disk slot + player inventory | none |
| `printer` | `new MenuType<>(PrinterMenu::new, ...)` | 1 ink + 1 paper input group + output + inventory (`PrinterMenu`) | 1 |
| `printout` | `new MenuType<>((i, c) -> PrintoutMenu.createRemote(i), ...)` | none | none |

The client builds the menu from its own factory, so the **server's menu must
have the same slot layout**: container sync packets
(`ClientboundContainerSetContentPacket`, `SetSlot`) carry slot counts and are
validated against the client's menu. The computer menu's slots do not hold
items the player can take; they exist so the hotbar is addressable.

### 3.2 Block entities: what the client needs

Only blocks whose client behaviour depends on server data need block entity
update data. Source: `getUpdateTag`/`getUpdatePacket` in the classes.

| Block entity | Client data (update tag / packet) | Rendered by |
| ------------ | --------------------------------- | ----------- |
| computer, speaker, disk drive, printer, modems, cable, redstone relay | **none**. The visible state is in the *block state* (`state`, `on`, `modem`, `top`/`bottom`, ...). `AbstractComputerBlockEntity` has no `getUpdateTag` override; `label` and ids are server side (`saveAdditional`: `ComputerId`, `Label`, `On`, `Capacity`, `TerminalSize`, `Lock`) | model JSON only |
| `monitor_*` | `ClientboundBlockEntityDataPacket` with a tag `{XIndex: int, YIndex: int, Width: int, Height: int}` (`MonitorBlockEntity.getUpdateTag`, also in the chunk's block entity list), plus the screen through `computercraft:monitor_client` for the **origin** block (`XIndex == 0 && YIndex == 0`); `MonitorWatcher.onWatch` sends it when a chunk is sent to a player, then on every change (bandwidth limit `monitor_bandwidth`, default 1 000 000 bytes per tick) | block entity renderer draws the terminal across the whole `Width x Height` wall |
| `turtle_*` | update tag from `TurtleBlockEntity.getUpdateTag`: `Label` (string), then `TurtleBrain.writeDescription`: `Fuel` (int), `Color` (int, only if dyed), `Overlay` (identifier), `LeftUpgrade`/`RightUpgrade` (`UpgradeData` codec: `{id, components?}` or a bare id string), `Animation` (int ordinal of `TurtleAnimation`) | renderer; the turtle animation plays client side from `Animation` |
| `lectern` | vanilla `LecternBlockEntity` data (the pocket computer on it) | vanilla renderer |

The tag is the *update tag* (`BlockEntity.getUpdateTag`), written both into
`ClientboundBlockEntityDataPacket` and the chunk's block entity list; it is not
the save data. When the block entity is created on the client (from chunk
data) its `loadAdditional` runs on the client with that tag
(`MonitorBlockEntity.loadAdditional` -> `onClientLoad`).

Monitor placement/resizing logic (`Expander`, `MonitorBlockEntity.expand`) is
server only; the client just sees `XIndex/YIndex/Width/Height` and the block
state `state` (edge connections).

### 3.3 Item data components

CC's items carry data components that are **network synchronised**
(`.networkSynchronized(...)` in `ModRegistry.DataComponents`), so they appear
in every item stack the server sends (`ItemStack` stream codec:
`VarInt count`, `VarInt item id`, component patch = `VarInt added`, `VarInt removed`,
added `(VarInt component type id, value)`, removed `VarInt component type id`).

| Component | Value encoding (stream codec) |
| --------- | ------------------------------ |
| `computer_id` | `VarInt` (`NonNegativeId.Computer`, id >= 0) |
| `storage_capacity` | `VarLong` (> 0) |
| `terminal_size` | `VarInt width`, `VarInt height` (1-255) |
| `left_turtle_upgrade`, `right_turtle_upgrade` | `UpgradeData`: `VarInt` holder id in the `computercraft:turtle_upgrade` registry, then a component patch |
| `top_pocket_upgrade`, `back_pocket_upgrade` | same for `computercraft:pocket_upgrade` |
| `fuel` | `VarInt` |
| `overlay` | identifier string |
| `computer` | `ServerComputerReference`: `VarInt session`, `UUID instance` (pocket computers) |
| `on` | `bool` |
| `treasure_disk` | `string name`, `string path` |
| `disk_id` | `VarInt` (`NonNegativeId.Disk`) |
| `printout` | `string title`, `VarInt n`, n x (`string text`, `string foreground`) |

The mod also uses vanilla `custom_name`, `dyed_color`, `lock`,
`tooltip_display` (`dyeableProperties`). Computer items copy `computer_id`,
`custom_name`, `storage_capacity` and `terminal_size` from the block entity
(`collectSafeComponents`); the *display stack* in the menu data is such a stack.
Pocket computers are items: their terminal reaches the client through
`pocket_computer_data` keyed by the `computer` component's instance UUID.

### 3.4 Peripherals, redstone, capabilities (server only)

Peripheral lookup (`PeripheralCapability`), wired/wireless networks, bundled
redstone providers, `IMedia` for disks, fluid/energy/item generic peripherals
and the `ILuaAPI` factories are all server side. The client sees none of them.
Interaction with the world is by ordinary vanilla packets: right-clicking a
computer block opens the menu (`AbstractComputerBlock.useWithoutItem`), right-
clicking a monitor front face on an advanced monitor sends the vanilla use-item-on
packet and the *server* converts the hit position into a character cell and
queues `monitor_touch` (`MonitorBlockEntity.monitorTouched`, with the border and
margin constants `2/16`, `0.5/16`).

## 4. The Lua side

### 4.1 Dialect

Cobalt `0.9.9`: **Lua 5.1 semantics with a long list of 5.2/5.3 features**
(`doc/reference/feature_compat.md`): `goto`/labels, `_ENV`, `\z`, `\xNN`,
`\u{}`, hex float literals, `__len`, `__pairs`, `bit32`, `load` with a mode
and environment (and `loadstring`, `unpack`, `setfenv`/`getfenv` for closures
that have an `_ENV`), `table.pack/unpack/move`, `string.rep` with separator,
`math.log` with base, `*L` file reads, `coroutine.isyieldable`,
`string.pack/unpack`, `utf8`, `table.create`, **yield across `pcall`,
metamethods and C boundaries**. Numbers are `double` only (no integer
subtype, no `//` or bitwise operators, `math.type` missing), `%g` and `%z`
patterns are not special, `collectgarbage`, `os.execute`, `os.exit`,
`string.dump` do not exist. Strings are byte strings.

### 4.2 ROM, BIOS and how a server loads them

The ROM is the directory `projects/core/src/main/resources/data/computercraft/lua/rom`
(219 files: `apis/`, `autorun/`, `help/`, `modules/main/cc/...`, `programs/`,
`startup/`, `motd.txt`, ...) plus `data/computercraft/lua/bios.lua` in the
same jar. `ComputerExecutor` mounts `rom` read-only at `/rom` over the
computer's own writable root and boots by loading `bios.lua`
(`computer.getGlobalEnvironment().createResourceFile("computercraft", "lua/bios.lua")`;
`ResourceMount` over the data pack resources). The Lua sources are licensed
**MPL-2.0** (SPDX headers); the mod as a whole declares the ComputerCraft
Public License in `neoforge.mods.toml` and ships assets under other licenses.
This plugin therefore does not embed them: it reads both from the owner's jar
(`lib/src/machine/zip.dart`, `craftos.dart`: `data/computercraft/lua/bios.lua`
and the `data/computercraft/lua/rom/` prefix), via a pure Dart zip/inflate
reader, and falls back to a tiny own BIOS (without ROM) if no jar is present.

`bios.lua` needs, from the host: `fs.open` (+ `readAll`, `close`), `loadstring`,
`load(str, name, mode, env)`, `coroutine.yield/resume/create/status/running`,
`pcall`, `select`, `table.pack/unpack/insert/remove/sort/concat`,
`string.sub/find/match/gmatch/gsub/rep/format/byte/char/lower`, `bit32`,
`term.*`, `os.startTimer`, `os.queueEvent`, `os.shutdown/reboot` (native, wrapped
in Lua), `settings` (a ROM API), `peripheral`/`redstone`/`rs` natives and
`_HOST`, `_CC_DEFAULT_SETTINGS`. The ROM additionally uses `debug.getinfo`,
`debug.getmetatable`, `debug.getregistry`, `utf8.char/codes`, `os.date/time/epoch/day/clock`,
`math.*`, `string.pack`-free code.

### 4.3 The API surface (`ILuaAPI` implementations)

Registered per computer in `ComputerExecutor` (`core/computer`), names as Lua
globals: `term` (`TermAPI`: `write`, `scroll`, `getCursorPos`, `setCursorPos`,
`getCursorBlink`, `setCursorBlink`, `getSize`, `clear`, `clearLine`,
`get/setTextColour|Color`, `get/setBackgroundColour|Color`, `isColour|Color`,
`blit`, `get/setPaletteColour|Color`, `nativePaletteColour|Color`), `redstone`
and `rs` (`RedstoneAPI`: `getSides`, `get/setOutput`, `getInput`,
`get/setAnalogOutput|AnalogueOutput`, `getAnalogInput`,
`get/setBundledOutput`, `getBundledInput`, `testBundledInput`), `fs`
(`FSAPI`: `list`, `combine`, `getName`, `getDir`, `getSize`, `exists`,
`isDir`, `isReadOnly`, `makeDir`, `move`, `copy`, `delete`, `open`,
`getDrive`, `getFreeSpace`, `getCapacity`, `attributes`), `peripheral`
(`PeripheralAPI` natives: `isPresent`, `getType`, `hasType`, `getMethods`,
`call`; `wrap`, `find`, `getNames` are Lua in the ROM), `os` (`OSAPI`:
`queueEvent`, `startTimer`, `cancelTimer`, `setAlarm`, `cancelAlarm`,
`shutdown`, `reboot`, `getComputerID|computerID`, `getComputerLabel|computerLabel`,
`setComputerLabel`, `clock`, `time`, `day`, `epoch`, `date`), `http`
(`HTTPAPI`, only if `http.enabled`; **absent from the global table when
disabled**, bios checks `if http then ...`), and for turtles/pockets/command
computers `turtle`, `pocket`, `commands`. `rednet`, `textutils`, `settings`,
`keys`, `colors`, `window`, `paintutils`, `parallel`, `vector`, `gps`, `io`,
`shell`, `multishell` are **Lua in the ROM**. Peripheral methods are
annotated Java methods; `monitor` shares `TermMethods` plus
`setTextScale/getTextScale`, `modem` has `open`, `isOpen`, `close`, `closeAll`,
`transmit`, `isWireless` (wired modems add `getNamesRemote`, `isPresentRemote`,
`getTypeRemote`, `hasTypeRemote`, `getMethodsRemote`, `callRemote`,
`getNameLocal`), `speaker` has `playNote`, `playSound`, `playAudio`, `stop`,
`drive` has `isDiskPresent`, `getDiskLabel`, `setDiskLabel`, `hasData`,
`getMountPath`, `hasAudio`, `getAudioTitle`, `playAudio`, `stopAudio`,
`ejectDisk`, `getDiskID`, `printer` has `write`, `getCursorPos`,
`setCursorPos`, `getPageSize`, `newPage`, `endPage`, `setPageTitle`,
`getInkLevel`, `getPaperLevel`.

### 4.4 Machine, events and time slicing

* One coroutine (`mainRoutine`) runs `bios.lua`. `os.pullEventRaw(filter)` is
  `coroutine.yield(filter)`: the yielded string is the **event filter**; the
  machine ignores events with another name except `terminate`
  (`CobaltLuaMachine.handleEvent`). The machine is resumed with
  `(name, args...)`; with no arguments to start it or to continue after a pause.
* Event queue: at most **256** events per computer (`QUEUE_LIMIT`), dropped when
  full or while a start/stop command is pending; cleared on start and shutdown.
  Events from the host: `key`, `key_up`, `char`, `paste`, `mouse_click/up/drag/scroll`,
  `redstone` (when an input changed), `timer` (id), `alarm` (id),
  `peripheral`/`peripheral_detach` (side), `monitor_touch` (name, x, y),
  `monitor_resize` (name), `modem_message` (name, channel, reply channel,
  payload, distance), `terminate`, `file_transfer`, `disk`/`disk_eject`,
  `http_*`, `websocket_*`, `speaker_audio_empty`, `turtle_response`,
  `task_complete`.
* Timers and alarms are driven per **server tick** (`Environment.tick`,
  `OSAPI.update`): `os.startTimer(t)` is `round(t / 0.05)` ticks; `os.clock()`
  counts ticks * 0.05; `os.time()` is the in-game time of day
  (`(dayTime + 6000) % 24000 / 1000` hours), `os.day()` the in-game day.
* **Time limits** (`TimeoutState`, `ComputerThread`): a computer thread may run
  an event for `TIMEOUT = 7 s`; then the Lua machine throws the error
  **"Too long without yielding"** at the next interrupt check (once). If the
  computer still does not yield 1.5 s later (`ABORT_TIMEOUT`) it is hard
  aborted and shut down, with the message shown on the terminal. Startup and
  shutdown get `BASE_TIMEOUT = 30 s`. Fairness: a computer that used its
  slice (50 ms latency target, 5 ms minimum period) is paused when others
  wait, and resumes later without a new event (`wasPaused`). Cobalt's
  `interruptHandler` is what makes `while true do end` safe.
* Failure display (`ComputerExecutor.displayFailure`): the terminal is reset,
  the message ("Error running computer") written in red on colour computers,
  and the reason on the next line; the computer is then shut down.
* Start delay: a computer can be started at most every 50 ticks
  (`Computer.START_DELAY`), reboot included.

### 4.5 File system and mounts

`core/filesystem`: a computer's root is a writable mount over
`<world>/computercraft/computer/<id>` (command computers
`command_computer/<id>`), limited by `computer_space_limit` (default
1 000 000 bytes; every file or directory counts at least **500** bytes,
`MountConstants.MINIMUM_FILE_SIZE`; the quota is `limit + 500`), the ROM is
mounted read-only at `/rom`, disks at `/disk`, `/disk2`, ... by drives. Path
sanitising (`FileSystem.sanitizePath`): `\` becomes `/`, control characters
and `" : < > |` (and `*`, `?` unless wildcards are allowed) removed, parts
trimmed and cut to 255 characters, `.`/`..` resolved, parts of only dots and
spaces dropped. Open files are limited to `maximum_open_files` (128). Error
messages are `/path: No such file`, `Not a directory`, `Not a file`,
`Access denied`, `File exists`, `Cannot write to directory`, `Out of space`,
`Too many files already open`, `Unsupported mode`. `fs.open` returns
`nil, message` on failure and a handle table otherwise (`read`, `readAll`,
`readLine`, `seek`, `write`, `writeLine`, `flush`, `close`; binary mode reads
single bytes as numbers).

The plugin's equivalents: `lib/src/machine/filesystem.dart` (mount table,
sanitising, open files), `mounts.dart` (`StoreMount` over the data folder with
the same quota rules, `ArchiveMount` over the jar), `api/fs_api.dart`.

## 5. Uncertain or not analysed

* The exact `neoforge.mods.toml` version string of the jar the players run
  (`${file.jarVersion}`): the channel version must equal it; the plugin reads
  it from the jar it is given and so only works if that is the *same build*
  the players have.
* The name of the synced config file in the 26.3.0 release (`computercraft-synced.toml`
  per the FML `main` source) and the effect of not sending it.
* Whether known packs let the server omit the datapack registry entries.
* The vanilla encodings assumed unchanged from 1.21.x: `ItemStack` and
  `DataComponentPatch` stream codecs, `Vec3.STREAM_CODEC` (3 doubles),
  `Identifier.STREAM_CODEC` (string), `BlockPos` packing, `Holder<JukeboxSong>`.
* Pocket computer (`PocketComputerItem`, `pocket_computer_lectern`) and turtle
  GUI details beyond the payloads (turtle upgrade slots, `TurtleAnimation` ids),
  the printer/disk drive menus' exact slot lists, wired modem network
  rendering, `ClientboundBlockEntityDataPacket`'s exact vanilla layout.
* The state numbering rule (sorted names, last property fastest) is vanilla's
  `StateDefinition` from memory, not re-read in the 26.3 sources.
