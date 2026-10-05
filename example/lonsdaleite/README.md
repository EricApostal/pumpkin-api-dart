# Lonsdaleite for Pumpkin

The server side of the [Lonsdaleite Tools](https://modrinth.com/mod/lonsdaleite-tools)
NeoForge mod (Minecraft 26.3, NeoForge `26.3.0.7-beta`) as a Pumpkin plugin, so a
real NeoForge client with the mod can join a Pumpkin server:

* it registers the mod's **32 items** and **21 item tags** with the server
  (`item-registry`, permission `registry.items`), with the mod's tool, armor and
  weapon components;
* it registers the **wardframe block** (`block-registry`, permission
  `registry.blocks`): 64 states that connect to each other, hardness 5, needs a
  diamond pickaxe, drops itself, and links it to its item;
* it answers NeoForge's **registry sync** (via `packages/pumpkin_neoforge`) so the
  client learns the numeric ids of the mod's items and block and agrees to join;
* it keeps the mod's server behaviour that Pumpkin can run (see "What works").

Everything about the content is in `data/manifest.json` (generated from the mod,
[docs/content.md](docs/content.md)); how it is registered, byte by byte, is in
[docs/registration.md](docs/registration.md); what the mod does on a server and
what Pumpkin lacks for it is in [docs/server-logic.md](docs/server-logic.md).

> **The wardframe works, with two gaps.** Placing it, the auto-connecting
> faces, mining it with a diamond pickaxe and its drop work on the server; letting
> *tamed pets* through and the omnitool's block transformations do not (the client
> lets players through by itself). Details at the [end](#the-wardframe). This part
> needs a Pumpkin build with the `block-registry` interface and was **not run
> against a server yet** (see [What works, and what is verified](#what-is-verified)).

> **Weapons and armor have no attribute modifiers on the server (yet).** The
> host's network reader for `attribute_modifiers` throws the values away, so a
> Lonsdaleite sword hits like a hand and armor protects nothing, until Pumpkin keeps
> them ([docs/registration.md](docs/registration.md#what-the-host-keeps)). The plugin
> already sends them.

## What you need

* A Pumpkin build **from the working tree** that has the `item-registry` and
  `block-registry` interfaces and the configuration hooks (the uncommitted work in
  `/Users/eric/Documents/development/languages/rust/Pumpkin`). A release build of
  Pumpkin without them cannot load the plugin: the host refuses it because the
  plugin imports `pumpkin:plugin/item-registry` and `pumpkin:plugin/block-registry`.
* The plugin: `build/lonsdaleite.wasm` (rebuild it as below if in doubt).
* A Minecraft **26.3** client with **NeoForge `26.3.0.7-beta` or newer** and the
  **Lonsdaleite Tools** mod (`2.3.0`) in its `mods` folder.

## Steps

### 1. Build the server (your own terminal)

```sh
cd /Users/eric/Documents/development/languages/rust/Pumpkin
cargo build --release          # produces target/release/pumpkin
```

### 2. Build the plugin (optional, one is already in `build/`)

```sh
cd example/lonsdaleite
dart run pumpkin_tools build   # puro dart run pumpkin_tools build
# -> build/lonsdaleite.wasm
```

### 3. Set up a server folder

```sh
mkdir -p ~/lonsdaleite-server/plugins && cd ~/lonsdaleite-server
cp /path/to/pumpkin-api-dart/example/lonsdaleite/build/lonsdaleite.wasm plugins/
/Users/eric/Documents/development/languages/rust/Pumpkin/target/release/pumpkin
```

The first start writes `pumpkin.toml` in the folder you ran it from. The plugin
needs **two permissions, `registry.items` and `registry.blocks`** (register items
and item tags, register blocks and block tags; nothing else: no files, no network).
Pumpkin asks at the first load, in the console:

```
Plugin "lonsdaleite" (0.1.0) requests the following permissions:
  - registry.items: Allows the plugin to register custom items and item tags.
  - registry.blocks: Allows the plugin to register custom blocks and block tags.
Do you want to allow these permissions and load the plugin? [y/N]:
```

Answer `y` (the answer is cached in `plugins/permission_cache.json` for this exact
file). To skip the question put this in `pumpkin.toml` and restart:

```toml
[plugins]
allowed_permissions = ["registry.items", "registry.blocks"]
```

`allow_unsigned` is `true` by default, so the unsigned `.wasm` loads. Do not list
either permission in `blocked_permissions`.

### 4. Choose `online_mode`

In `pumpkin.toml`, section `[networking.java]`:

* **`online_mode = true`, `encryption = true`** (the default): the server checks
  accounts with Mojang, as a normal server. Join with your normal Microsoft account
  in the official launcher (or any launcher with a real account). Use this for
  anything that is not a throw-away test.
* **`online_mode = false`, `encryption = false`**: the server does not check who
  joins; anyone can use any name. The client still connects with whatever account
  the launcher has (the official launcher joins offline servers with your real
  account, and launchers that offer an "offline account", such as Prism, work too),
  but the server will treat you as a *different player* than on an online server (new
  inventory, no op status, no skin for others). Only for a LAN or a test.

`encryption` must be `true` when `online_mode` is `true`. The NeoForge exchange
happens after login, so it works the same in both modes.

### 5. Install NeoForge and the mod in the client

1. Install NeoForge `26.3.0.7-beta` (or newer) for Minecraft 26.3 from
   <https://neoforged.net> into a launcher profile (or create a NeoForge instance in
   Prism / MultiMC / CurseForge).
2. Download **Lonsdaleite Tools** `2.3.0` from
   <https://modrinth.com/mod/lonsdaleite-tools> (the CurseForge page of the same
   mod works too) and put the jar in that instance's `mods/` folder.
3. Start the instance with the NeoForge profile, add the server (`localhost` if on
   the same machine, or its address) and connect.

A client **without** the mod, or a vanilla client, is refused with a message (the
plugin uses the library's default `NonNeoForgePolicy.reject`): it would break on the
first stack of a modded item. A vanilla client sees the refusal after about 3
seconds (the wait for the client to announce itself).

### Only one NeoForge plugin per server

This plugin installs the NeoForge handshake (`NeoForgeServer.install`), and
**only one plugin per server may do that**: a client answers every registry sync
and every `neoforge:register` query it receives, so two plugins would talk to the
same client at once, and the second registry sync replaces the id tables of the
first (the snapshot of a registry must contain *every* mod's entries). A server
that runs Lonsdaleite **and** another NeoForge mod's plugin (for example
`example/cc_tweaked` with `"neoforge": true`) needs **one** plugin that owns the
NeoForge spec with both mods' registries. Until that exists, run only one of the
two with its handshake on (CC's is off by default). How the spec could be shared
between plugins is proposed in
[packages/pumpkin_neoforge/README.md](../../packages/pumpkin_neoforge/README.md#one-neoforge-plugin-per-server).

### `adhoc` or `full` negotiation

The plugin uses the library's **`adhoc`** negotiation (`lonsdaleiteNegotiation` in
`lib/src/neoforge.dart`, a constant: the plugin has no config file). The mod has
no payloads of its own, so nothing needs negotiating, and the registry sync with
its acknowledgement proves that the client has all of the mod. `full` (the real
NeoForge order, with the host's pre-brand hold) makes the client treat the connection
as NeoForge for good, which needs the plugin to send the elytra attribute and
`neoforge:recipe_content` and relies on host and client agreeing on more details
(see `packages/pumpkin_neoforge/README.md`, "Full mode"). Change the constant to
`NeoForgeNegotiation.full` to try it with a live client; the plugin then also
installs the play helpers.

## What to expect

**Log lines at server start** (the `[...]` prefixes are the plugin loggers):

```
Plugin lonsdaleite registered item lonsdaleite:lonsdaleite_wardframe with id 1658     (host, once per item, ids 1658..1689)
Lonsdaleite Tools 2.3.0: registered 32 items (ids 1658 to 1689) and 21 item tags.
Skipped component, minecraft:block_transformer on 6 item(s): the host has no reader for it ...
Skipped component, minecraft:interact_animation on 32 item(s): the host has no reader for it
Plugin lonsdaleite registered block lonsdaleite:lonsdaleite_wardframe with id 1286 and 64 states from state id 35723   (host)
Plugin lonsdaleite linked item lonsdaleite:lonsdaleite_wardframe to block lonsdaleite:lonsdaleite_wardframe            (host)
Registered block lonsdaleite:lonsdaleite_wardframe: id 1286, 64 states from state id 35723 (default state 35786), item id 1658, 2 block tags (minecraft:mineable/pickaxe, minecraft:needs_diamond_tool).
NeoForge registry sync installed: Lonsdaleite Tools 2.3.0, 32 items (ids 1658 to 1689), block lonsdaleite:lonsdaleite_wardframe (id 1286, 64 states from state id 35723), negotiation adhoc.
```

If the item ids are not what the client will be told, the plugin **stops loading with
a message** instead: *"The server has N vanilla items, but the registry sync was built
for 1658"* (a different Pumpkin build than the one the vanilla lists were generated
from), or *"... got id X, but the registry sync tells clients Y ... Another plugin has
registered items before this one"* (load order). Other failures at this point:
*"registering items needs the 'registry.items' permission"* (permission blocked) and
*"items can only be registered before players connect"* (not at load time).

The same goes for the block, which is registered right after the items: the plugin
**stops loading** with *"The server has N vanilla blocks, but the registry sync was
built for 1286"* (or *"... N vanilla block states, ... 35723"*), *"... got block id X,
but the registry sync tells clients 1286 ... Another plugin has registered blocks
before this one"*, *"The states of ... start at id X on the host, but clients number
them from 35723"*, *"The state {...} of ... has id X on the host, but the client will
compute Y ... disagree about the state order"* (the host and the plugin number the
64 states differently), or the host's own message: *"registering blocks needs the
'registry.blocks' permission"*, *"blocks can only be registered before players
connect"* or *"... is a vanilla item, only custom items can place custom blocks"*.

**When your client joins:**

```
[neoforge] <name> joined with NeoForge (2 registries synced)
```

and in the client: a *Lonsdaleite* creative tab and the mod's items in the vanilla
creative tabs (these come from the client's own mod code, not from the server). A
client that fails the sync is disconnected with the message of the failed step and the
server logs `[neoforge] <name> was refused: ...`. `/lonsdaleite` (permission
`lonsdaleite:command.lonsdaleite`) lists who joined with the handshake.

**In the game**

| Try | Expected |
| --- | --- |
| `/give @s lonsdaleite:refined_lonsdaleite` (or any id of `data/manifest.json`) | the item arrives with the right model and name (the client has them) |
| creative tab / creative inventory | all 32 items, taking them works |
| mine with a Lonsdaleite pickaxe, axe, shovel or hoe | mines like netherite (speed 8.2, the perfect tier 9.0), drops as the pickaxe rules say, loses 1 durability per block; the omnitools mine with all four families |
| put on Lonsdaleite armor (right click or the armor slots) | it equips in the right slot with the right equip sound; **no armor points** (see the note at the top); armor slots may refuse it when clicked in (`is_helmet()` uses static tags) |
| repair at an anvil with `refined_lonsdaleite` (perfect gear: `perfect_lonsdaleite`) | uses the `repairable` tags, which the plugin registers |
| enchantability | the `enchantable` values are in; which enchantments apply depends on static tags in Pumpkin |
| hitting mobs | durability use per hit (`weapon`) works, **damage does not use the sword's value** |
| the omnitool right click (strip, till, path) | **does nothing**: needs a host call that does not exist yet. The handler is guarded and leaves the click alone |
| place the wardframe item (creative tab or `/give @s lonsdaleite:lonsdaleite_wardframe`) | the block is placed like a vanilla block (replacing, entity obstruction, protection checks); next to another wardframe the faces that touch it turn `true` on both blocks (auto-connect, also when you break one) |
| mine a wardframe with a **diamond or netherite** pickaxe (a Lonsdaleite one too) | breaks (hardness 5, so slowly) and **drops the item**; with a wooden, stone, iron or copper pickaxe, a hand or no pickaxe it breaks (slower) and **drops nothing**; in creative it breaks at once |
| light, sounds | light level 7 on every state, no occlusion; the client chooses the amethyst sounds |
| walk through a wardframe as a player | the **client** lets you through (the mod's own collision); the server does not stop you and does not hurt you (not suffocating) |
| tamed pets, mounts with a rider | **not through**: on the server they collide with the wardframe like with a full block |
| spear lunge, mace smash, sweeping | **not implemented** for the mod's items (static tags/ids in Pumpkin) |
| crafting and smelting the items | **not provided**: the plugin installs no recipes, and Pumpkin's furnaces read only the static cooking table. `--datapack` in `tool/generate_manifest.dart` exports the mod's data as a data pack (docs/content.md); whether the crafting recipes work through it is untested |

## Check the protocol without the game

`example/modbridge/testclient` has a strict NeoForge client written in Python (it
emulates the client's half of the NeoForge exchange and verifies the registry sync
the way the real client does). It needs an **offline** server; `with_server.sh`
starts a throw-away one (offline mode, no encryption, port 35965, scratch folder),
runs your command and always stops it:

```sh
cd example/modbridge/testclient
PUMPKIN_BIN=/Users/eric/Documents/development/languages/rust/Pumpkin/target/release/pumpkin \
PLUGINS="$PWD/../../lonsdaleite/build/lonsdaleite.wasm" \
ALLOW_PERMISSIONS="registry.items registry.blocks" \
./with_server.sh python3 neoforge_client.py --port 35965 --neoforge-mod mods/lonsdaleite.json
```

`ALLOW_PERMISSIONS` pre-approves the permissions (there is no console to answer the
prompt; space separated). The client prints PASS/FAIL per check and exits 0 on PASS; the server log
path is printed at the end. `--lenient` downgrades the two checks that are stricter
than the real client (contiguous ids, every entry gets an id). Without the plugin
the same command fails at the registry sync, which is the point of the check. Its own
test suite (no server needed): `python3 test_neoforge_client.py`.

## What works, and what is verified

<a id="what-is-verified"></a>

**Verified here (without a server):** the manifest and its validation; the component
encoder against golden bytes derived from Pumpkin's readers, plus a second encoder
in Python for all 32 items; the registration sequence (order, ids, tags, the checks
and their messages) against a fake host, for the items and for the block (a fake
that numbers the 64 states the way Pumpkin's Rust code does, independently of the
Dart computation); the wardframe's state numbering against the mod's own state
table in the manifest; the NeoForge spec equals `lonsdaleiteSpec()` and the Python
client's `mods/lonsdaleite.json`; the plugin compiles to a component that imports
`pumpkin:plugin/item-registry@0.2.0` and `pumpkin:plugin/block-registry@0.2.0` and
declares both permissions.

```sh
cd example/lonsdaleite && dart test && dart analyze
cd packages/pumpkin_api && dart test            # codec, tables, checks, block state ids
cd packages/pumpkin_neoforge && dart test
cd example/modbridge/testclient && python3 test_client.py && python3 test_neoforge_client.py
```

**Not verified (needs the rebuilt server, and for the last part the real client):**

* that the built server accepts the plugin and every `register-item` call (the
  bytes follow the Rust readers by reading, not by running them);
* the Rust side of the block registry (written, **not compiled** when this was
  wired): `register-block`, `register-block-tag`, `set-block-item`, that the host
  reports 1286 / 35723 / 64 and numbers the states as the plugin computes (the plugin
  checks that at load), placing, auto-connecting, mining and the drop;
* that the ids the host assigns are `1658 + index` (the plugin checks it at load and
  refuses to continue otherwise) and that `get-vanilla-items` equals Pumpkin's
  `items.json` (also checked at load);
* the strict Python client against the server (the command above);
* everything with the real NeoForge client: that it accepts the sync (the whole
  library is written from the NeoForge source and was never run against a live
  client; `docs/neoforge-protocol.md` lists the open questions), that the creative
  tab and items show up, `/give`, mining, equipping, anvil repair, and what happens
  when a client places, connects and mines the wardframe, and that the chunk data the
  host sends for it (state ids from 35723) is read right by the client.
* whether Pumpkin's `/give`, creative inventory, saving and loading handle items with
  ids above the vanilla range everywhere (`Item::from_id` has a dynamic fallback; not
  every path was read).

## The wardframe

The mod's block has 64 states (six booleans: `north south east west up down`), collision
that lets players through, light level 7 and a loot table. The plugin registers it with
the host's `block-registry` right after the items
([docs/registration.md](docs/registration.md#the-wardframe) has the exact sequence):

| | |
| --- | --- |
| key / ids | `lonsdaleite:lonsdaleite_wardframe`, block id **1286** (after the 1286 vanilla blocks), states **35723..35786** (after the 35723 vanilla states), default state 35786 (all faces `false`) |
| values | hardness 5.0, blast resistance 1200.0, requires the correct tool, sound `amethyst`, light 7, does not occlude, **not suffocating**, full cube for collision and outline |
| connecting | each face property follows the neighbour on that side being a wardframe (placement and every neighbour change), like glass panes |
| mining | tags `minecraft:mineable/pickaxe` and `minecraft:needs_diamond_tool` (registered with `register-block-tag`); the host also puts it in the `incorrect_for_*` tags of the lower tiers, so only a diamond or better tool is correct |
| drops | one wardframe item (`self-item`), like the mod's loot table (`survives_explosion` applies) |
| item | `lonsdaleite:lonsdaleite_wardframe` (id 1658, registered first) is linked with `set-block-item`: using it places the block |

**What works:** placing, auto-connecting, mining with a diamond pickaxe, the drop, the
item tag `minecraft:doors`, the world save/load (name and properties).

**What does not:**

* **Per-entity pass-through.** The mod's collision shape is empty for a player, a tamed
  pet and anything with a player on it, full for everything else. Players pass because
  their *client* has the mod's shape; the server has one shape per state, so tamed
  animals and mounts collide with it there. The plugin chose `suffocating = false` so
  a player standing inside is not hurt.
* **The omnitool's block transformations** (strip, till, path) need a host call that does
  not exist ([docs/server-logic.md](docs/server-logic.md#the-omnitool)); this is
  independent of the wardframe.
* Block entities, redstone power, random ticks and waterlogging are not available for
  custom blocks (the wardframe needs none).
* The recipe that makes the item exists in the manifest only; the plugin installs no
  recipes.

Do not register blocks from another plugin before this one: the ids and state ids the
client is told would shift, and the plugin refuses to load (the message names the other
block).

## Files

| Path | |
| --- | --- |
| `data/manifest.json`, `lib/src/manifest*.dart` | the content, generated; parsed at load |
| `lib/src/plugin.dart` | `onLoad`: the order of everything |
| `lib/src/item_install.dart` | register items and tags, verify ids (binding-free) |
| `lib/src/block_definition.dart` | the wardframe as a `BlockDefinition` from the manifest, and the check of its state numbering against the mod's table |
| `lib/src/block_install.dart` | register the block, link its item, register the block tags, verify ids and states (binding-free) |
| `lib/src/component_codec.dart` | manifest item -> encoded components, skipped log |
| `lib/src/host_adapter.dart` | the host-facing glue (`HostItemRegistrar`, the missing transformer call); the block registry is `BlockRegistries.host` from `pumpkin_api` |
| `lib/src/neoforge.dart`, `neoforge_spec.dart` | `NeoForgeServer` and the sync spec from the manifest |
| `lib/src/omnitool.dart` | right click decision logic (needs the missing host call) |
| `tool/golden_components.py`, `test/fixtures/component_bytes.json` | second encoder and its golden bytes |
| `docs/` | content, registration, server logic |
