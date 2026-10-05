# pumpkin_neoforge

The server side of NeoForge's network negotiation and registry synchronisation,
as a library for Pumpkin plugins. A plugin that installs a `NeoForgeServer` looks
like a NeoForge server to a NeoForge 26.3 client that has the server's mods
installed: the client joins, and the server tells it which numeric ids the mod's
registry entries have.

Why: a NeoForge client only takes a server's word for its mods through the
registry sync, and a mod without payloads leaves no other trace. The protocol,
byte by byte, with the NeoForge source it comes from, is in
[docs/neoforge-protocol.md](../../docs/neoforge-protocol.md). **Nothing here was
run against a live client yet**; the strict test client
(`example/modbridge/testclient/neoforge_client.py`) is how to check a server.

## Use

```dart
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge.dart';

final neoforge = NeoForgeServer(
  NeoForgeServerSpec.vanillaPlus(
    mods: [NeoForgeModInfo(id: 'lonsdaleite', version: '2.3.0', displayName: 'Lonsdaleite Tools')],
    // the mod's entries, in registration order; vanilla entries come first
    additions: {
      'minecraft:block': ['lonsdaleite:lonsdaleite_wardframe'],
      'minecraft:item': ['lonsdaleite:lonsdaleite_wardframe', 'lonsdaleite:raw_lonsdaleite'],
    },
  ),
);

final class MyPlugin extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(name: 'mypack', version: '1.0.0', description: '...');

  @override
  void onLoad(Context context) {
    neoforge.install(context);                 // Context.onConfiguration, both hold points
    neoforge.onClient((client) {               // decided: accepted / rejected / not NeoForge / left
      logger.info('${client.username}: ${client.outcome.name}, brand ${client.brand}');
    });
  }
}
```

For Lonsdaleite there is a ready made spec: `lonsdaleiteSpec()` from
`package:pumpkin_neoforge/lonsdaleite.dart`. The complete plugin (items,
registry sync, README with the steps to try it) is `example/lonsdaleite`, which
builds its spec from its content manifest instead.

### What a connection goes through

`install` registers `context.onConfiguration` with the start hold and the finish
hold, plus the pre-brand hold in the full mode (docs/configuration.md). For
every client:

0. **pre-brand hold** (`NeoForgeNegotiation.full` only; before Pumpkin's brand):
   `minecraft:unregister`, `minecraft:register`, the `neoforge:register` query
   and a ping; wait for the client's answer and pong (a vanilla client never
   answers the query: not NeoForge, the `nonNeoForge` policy decides); negotiate
   the channels, mark the connection as NeoForge in the host
   (`ConfigurationConnection.setFlavour`), send `neoforge:network` and a second
   `minecraft:register`, release (the host sends the brand);
1. **start hold** (after Pumpkin's brand, before registries and tags): (ad hoc mode:
   announce the channels the server receives (`minecraft:register`), read the
   client's own announcement (a vanilla client sends none), decide whether it
   is NeoForge), send the registry sync (`neoforge:frozen_registry_sync_start`, one
   `neoforge:frozen_registry` per registry, `..._sync_completed`) and wait for the
   client's acknowledgement, then release;
2. **finish hold** (after registries and tags): the `c:version` / `c:register`
   exchange, synced config files, and the data map / extensible enum / feature
   flag checks if the spec has any; then release.

A client that is not NeoForge, answers wrongly, or does not acknowledge in time
is disconnected with a reason (`NeoForgeMessages`) and the `NeoForgeClient`
result says why. A handler that throws also disconnects (fail closed).

### Per-connection results

`NeoForgeClient` (from `onClient`, `server.clientOf(uuid)`, `server.clients`):
`outcome` (`accepted`, `notNeoForge`, `rejected`, `disconnected`),
`failureReason`, `brand`, `announcedChannels` (the client's `minecraft:register`),
`query` / `setup` (negotiation, `full` mode), `syncedRegistries`,
`registriesAcknowledged`, `commonVersions`, `commonPlayChannels`,
`clientDataMaps`, `modNamespaces` (namespaces of the client's payload channels,
i.e. its mods that have networking) and an `events` log. Results are kept per
UUID (`maxRetainedClients`); call `forget(uuid)` when a player leaves.

### Options

`NeoForgeServerOptions`:

| option | default | |
| ------ | ------- | - |
| `negotiation` | `adhoc` | `adhoc`: no `neoforge:register` query, vanilla play encodings; `full`: the real handshake, before the brand (see below) |
| `nonNeoForge` | `reject` | `allow` lets vanilla clients through without the modded entries |
| `announceTimeout` | 3 s | wait for the client's `minecraft:register` (ad hoc) or its query answer (full); also the delay a vanilla client sees |
| `queryTimeout` | 5 s | full: wait for the client's `minecraft:register` that comes with its query answer |
| `preBrandGrace` | 1 s | full: how long after the client's pong to still wait for its query answer (a vanilla client answers the ping only, so this is how fast it is recognised) |
| `preBrandHoldTimeout` | 30 s | full: the hold before the brand |
| `neoForgeConfigFiles` | `['neoforge-server.toml']` | full: names of NeoForge's own synced config, sent empty in the finish hold (a later NeoForge commit renamed it to `neoforge-synced.toml`; `[]` sends none) |
| `syncTimeout` | 20 s | the client applies the registries and acknowledges |
| `taskTimeout` | 10 s | each step of the finish hold |
| `holdTimeout`, `finishHoldTimeout` | 45 s | |
| `commonHandshake` | true | |
| `alwaysNegotiateDataMaps`, `alwaysCheckEnums`, `alwaysCheckFeatureFlags` | false | by default only when the spec has data maps / enums / flags |

## Full mode (`NeoForgeNegotiation.full`)

The handshake as a NeoForge server does it: the negotiation comes **before the
brand**, so the client classifies the connection as NeoForge. It needs a host
with the pre-brand hold and `set-connection-flavour` (Pumpkin's
`configuration-pre-brand-event`); the library then:

1. holds the connection before the brand (`onPreBrand`), sends `minecraft:unregister`,
   `minecraft:register`, `neoforge:register` (empty) and a ping, and waits for
   the answer and the pong;
2. a client that **answers** is NeoForge: its channels are negotiated (a mismatch
   sends the failure reasons for the mismatch screen, then disconnects),
   `setFlavour(neoforge)` makes the host write NeoForge encodings in its play
   phase, `neoforge:network` and the second `minecraft:register` go out, and the
   hold is released (the host sends the brand);
3. a client that **does not answer** (vanilla: it ignores the payloads but
   answers the ping, so this is recognised about a second after the pong) is not
   NeoForge: `nonNeoForge` decides. `reject` (default) disconnects it,
   `allow` releases it; its connection stays `vanilla`, so it never receives
   bytes it cannot read;
4. the start hold does the registry sync, the finish hold the rest (plus an empty
   `neoforge-server.toml`, which a client classified before the brand expects).

Turn it on:

```dart
final neoforge = NeoForgeServer(
  spec,
  options: const NeoForgeServerOptions(negotiation: NeoForgeNegotiation.full),
);
// in onLoad:
neoforge.install(context);
neoforge.installPlay(context);   // the play-phase extras below
```

### What a NeoForge-flagged connection costs

The client treats the connection as NeoForge for good, so besides the encodings
the host handles (block particles; see
[docs/neoforge-play-codecs.md](../../docs/neoforge-play-codecs.md)) two things
need the plugin. `neoforge.installPlay(context)` does both for the connections
the full handshake marked (and nothing for the others):

* **Elytra.** A NeoForge client starts a glide only when the attribute
  `neoforge:gliding_flight` is greater than 0 (vanilla looks at the worn items).
  A plugin *can* send it: `Player.asJava().sendPacket(update_attributes)` exists.
  `installPlay` checks the chest slot (default every 500 ms, per flagged player)
  and sends the attribute with NeoForge's modifier
  (`neoforge:glider_component_flight`, +1) while one of `gliderItems` (default
  `minecraft:elytra`) is worn, without it otherwise, and again after respawn and
  world changes. The attribute's registry id on the client is the number of
  vanilla attributes followed by NeoForge's own (`swim_speed`, `creative_flight`,
  `gliding_flight`: `neoForgeOwnAttributes`), or the position in the spec's
  `minecraft:attribute` registry when the spec syncs one (then it must contain
  those three, in that order, after the vanilla ones; mod additions after them).
  Pass `GlidingFlightOptions(attributeId: ...)` to override, `glidingFlight: null`
  to switch it off. **Unverified**: that Pumpkin's 40 vanilla attributes equal
  the client's, and the client's reaction, are not tested live; a worn elytra
  with 1 durability left counts as worn here but not for the client's own rule.
  If you cannot accept that risk, use `adhoc`.
* **`neoforge:recipe_content`.** A NeoForge client gets its `RecipesReceivedEvent`
  from this payload (without it mods that wait for the event never see it).
  `installPlay` sends the empty payload (`00 00`) on join (`recipeContent: false`
  to skip). Unverified live; the host does not send recipe content itself.

Use `adhoc` when you cannot or do not want any of this (no query is sent, the
play phase stays vanilla, elytra work as usual).

## One NeoForge plugin per server

**Only one plugin per server may install the NeoForge handshake.** A client
answers every `neoforge:register` query and every registry sync it receives, so
two plugins that both install a `NeoForgeServer` would both talk to the same
client:

* the registry sync *replaces* the id tables of the registries it contains (the
  client rebuilds each synced registry from the last snapshot it got), so the
  snapshot of a registry must contain *every* mod's entries, and two plugins
  each syncing only their own would undo each other;
* both would ask for and wait for the client's `minecraft:register`, query
  answer and `..._sync_completed` acknowledgement, and each could take the
  other's answer for its own;
* in the full mode both would send the query and `neoforge:network` before the
  brand, and mark the connection, a classification the client does once.

A server with two NeoForge mods (for example Lonsdaleite and CC: Tweaked)
therefore needs **one** plugin to own the NeoForge spec, with both mods'
registries (`NeoForgeServerSpec.vanillaPlus(additions: ...)` with the
additions of both merged: all vanilla entries, then the mods' in the order the
client numbers them, which for several mods follows the client's mod load order
(not verified) and must equal the ids the host assigns), both mods' payload
channels, data maps and so on.

How to share the spec between plugins (a proposal in prose, **not implemented**).
Plugins are separate WASM modules; what they have is the host's IPC
(`pumpkin_api` `ipc.dart`: `ipc.requestJson(plugin, payload)`, synchronous, by
plugin name, answered by `ipcHandlers`/`IpcChannel.handle`), so:

1. **Pull (recommended).** Every content plugin (Lonsdaleite, CC) registers its
   entries in the host as it does today and answers one IPC request,
   `{"op": "neoforge_contribution"}`, with a JSON description of its
   contribution: mod id/version/display name, per registry the additions *with
   the host ids it got*, payload channels, data maps, config files. One owner
   plugin (a small plugin that depends on `pumpkin_neoforge`, or one of the
   content plugins by a flag) asks the plugins named in its own config once the
   server has loaded (`Events.serverLoad`, when all plugins are loaded and before
   players can connect), merges the answers into one `NeoForgeServerSpec` and
   installs the single `NeoForgeServer`. The merge refuses two plugins that claim
   the same entry and checks that each registry is the vanilla list followed by
   the mods' entries without gaps, in the ids the host uses. The sync must not
   start before the merge: the owner holds the configuration (the library's holds
   do that) or rejects joins until it is ready.
2. **Push.** Each plugin sends its contribution to the owner in its `onLoad`
   (`ipc.requestJson('neoforge_owner', ...)`). Simpler for the plugins, but the
   owner has to be loaded first, which the plugin load order does not guarantee.
3. **Declarative.** Each plugin writes its contribution as a JSON file into a
   shared data folder that the owner reads on load: no IPC and no load order, but
   the ids have to be known then, which means generating it from the same content
   manifest the plugin registers from (Lonsdaleite already has one).

In all variants the host ids a plugin registers must equal the merged snapshot,
so registration order across plugins has to be fixed (or the owner assigns the
ids and hands them back before the others register).

## The registries (what the spec must contain)

The sync **defines the numeric ids** on the client, so each synced registry must
be *complete*: all vanilla entries in the ids the host uses on the wire, then the
mod's entries appended in registration order (that is also how a NeoForge server
numbers them). `RegistrySpec.vanillaPlus(key, additions)` builds that from the
generated vanilla lists, which come from Pumpkin's assets:

```sh
cd packages/pumpkin_neoforge
puro dart run tool/generate_vanilla_registries.dart [--assets <Pumpkin>/assets]
```

writes `lib/src/vanilla_registries.g.dart` (embedded in plugins) and
`data/vanilla_registries.json` (read by the Python client). Generated lists:
item, block, entity type, fluid, mob effect, potion, attribute, data component
type, particle type, sound event, game event, custom stat, menu, block entity
type (Minecraft 26.3). The first four are the ones Pumpkin certainly agrees with
a vanilla client on (it uses these ids in its own packets); the others are
unverified against a vanilla dump.

Only registries that **contain modded entries** need to be in the spec (for most
content mods `minecraft:item` and `minecraft:block`): for the others the client
keeps ids that equal vanilla's. The creative mode tab is not synchronised.

The numeric id the host must use for a modded entry is its index in the list
(`RegistrySpec.entries`); for the block registry the order also fixes block state
ids. See [docs/neoforge-protocol.md](../../docs/neoforge-protocol.md#which-registries-are-synced).

Not covered: custom registries, data components, data maps' play-phase sync
(`neoforge:registry_data_map_sync`), recipe content other than the empty one,
config file content (you can pass `configFiles`), mod payload handling after
the handshake. Vanilla lists exist for the registries listed above; NeoForge's
own registries (`neoforge:*`) and, in this version, `recipe_serializer` and
`command_argument_type` are not generated (see the tool's output).

## Layout

| file | |
| ---- | - |
| `lib/pumpkin_neoforge_core.dart` | binding-free: codecs, negotiation, spec, handshake. Used by tests and tools |
| `lib/pumpkin_neoforge.dart` | + `NeoForgeServer` (the plugin glue) |
| `lib/lonsdaleite.dart` | the Lonsdaleite spec |
| `lib/src/payloads.dart` | encoders/decoders of every payload |
| `lib/src/handshake.dart` | the exchange, on a `ConfigurationConnection` (pre-brand, start and finish handlers) |
| `lib/src/play_core.dart`, `lib/src/play.dart` | the play-phase extras of a flagged connection (`neoforge:recipe_content`, `neoforge:gliding_flight`) |
| `test/golden/neoforge_codecs.txt` | byte vectors from `tool/golden/Golden.java` (Java, Minecraft's own codec primitives) |
| `test/transcript_test.dart` | records what the library sends; replayed by the Python client |

## Tests

```sh
puro dart test                                   # codecs, negotiation, handshake, specs
cd ../../example/modbridge/testclient
python3 test_neoforge_client.py                  # the strict client, mock server, transcripts
UPDATE_TRANSCRIPTS=1 puro dart test test/transcript_test.dart   # regenerate after a protocol change
```

Against a real Pumpkin with the plugin installed (offline mode, no encryption;
see `with_server.sh`):

```sh
python3 neoforge_client.py --port 35965 --neoforge-mod mods/lonsdaleite.json
```
