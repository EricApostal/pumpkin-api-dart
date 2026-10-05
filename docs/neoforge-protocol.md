# NeoForge 26.3: network negotiation and registry synchronisation

What a NeoForge client with mods expects from a server, and what a server has to
send to prove it is one, read from the NeoForge source. It is the specification
behind `packages/pumpkin_neoforge` (the server side, as a plugin library) and
`example/modbridge/testclient/neoforge_client.py` (a strict client that checks a
server against it). [loader-notes.md](loader-notes.md) has the earlier notes on
what the client does against a *non*-NeoForge server; where they differ, this
page is newer (see [Corrections](#corrections-to-loader-notesmd)).

Contents: [Summary](#summary) -
[Sources](#sources-and-method) -
[Order](#what-must-be-sent-in-which-order) -
[Packets and ids](#configuration-packets-around-the-exchange) -
[Payloads](#payload-formats) -
[Channels](#channel-announcement-and-classification) -
[Registries](#registry-synchronisation) -
[Other tasks](#the-other-configuration-tasks) -
[Failures](#what-the-client-verifies-and-how-it-fails) -
[Play](#play-phase) -
[Host](#what-the-host-has-to-provide) -
[Open questions](#what-could-not-be-determined)

## Summary

* **There is no login-phase part.** Everything happens in the *configuration*
  phase, with custom payloads (`ClientboundCustomPayloadPacket`, packet id 1
  clientbound / 2 serverbound in the 26.3 configuration protocol). Forge's
  `fml:loginwrapper` queries are gone. There is no mod list exchange either:
  a mod with no payloads is invisible to the server.
* **A real NeoForge server opens the configuration phase with the negotiation,
  before its brand**: `minecraft:unregister`, `minecraft:register`,
  `neoforge:register` (the *query*) and a ping; only after the client's pong does
  it send the brand and the rest of the configuration
  (`ServerConfigurationPacketListenerImpl.startConfiguration`/`handlePong`).
* **The registry sync (`neoforge:frozen_registry*`) is how the server dictates
  the numeric ids.** The client throws away its own id table of each synced
  registry and rebuilds it from the server's snapshot; entries the client does
  not know disconnect it ("server sent registries with unknown keys"). The
  server's snapshot must therefore be *complete* (all vanilla entries, in the
  ids the server uses, plus the modded ones).
* **A mod without payloads cannot be detected by the server**, except by
  sending the sync and requiring the acknowledgement
  (`neoforge:frozen_registry_sync_completed`, client to server): only a client
  that knows every entry in the snapshot sends it. That is the proof, in both
  directions.
* **Pumpkin's start hold fires after its brand.** A connection that only
  has that hold is classified "not NeoForge" by the client; the registry sync
  still works (over *ad hoc* channels, which the server announces with
  `minecraft:register`), but `neoforge:network` is ignored by the client. Since
  the host got the **pre-brand hold** (`configuration-pre-brand-event`) the plugin
  can speak first: `NeoForgeNegotiation.full` does the real order. See [The
  ordering problem](#the-ordering-problem) and
  [neoforge-play-codecs.md](neoforge-play-codecs.md).
* **Sending `neoforge:register` flips the client's play-phase encodings**
  (e.g. block particles get an extra optional position): the full mode sends it
  only to clients that then get `set-connection-flavour(neoforge)`, which makes
  the host write those encodings ([Play phase](#play-phase)).
* **The creative mode tab is not synchronised** and needs nothing on the wire:
  the client builds its tabs from its own code.

## Sources and method

* NeoForge `26.3.x` (<https://github.com/neoforged/NeoForge>), read at commit
  `b160270bd` ("Port to 26.3", tag `26.3.0`). Newer commits on the branch were
  diffed for the network packages: only `601801fc5` ("Rename COMMON and SERVER
  config types to LOCAL and SYNCED") touches them, with no wire change. The
  target mod (Lonsdaleite) builds against `26.3.0.7-beta`; which commit that is,
  was not determined.
* Paths below are relative to the repository root; `net/neoforged/neoforge` is
  abbreviated `NF`, so `NF/network/registration/NetworkRegistry.java` is
  `src/main/java/net/neoforged/neoforge/network/registration/NetworkRegistry.java`.
  The client code is under `src/client/java/...`. Patches to Minecraft are in
  `patches/net/minecraft/...`; a rule from a patch is cited by file and method.
* Vanilla's own classes (`ByteBufCodecs`, `Identifier`, `ConnectionProtocol`,
  `PacketDecoder`) are not in that repository. Their behaviour is taken from
  the 1.21.11 jar (unchanged primitives): the byte layouts below were
  reproduced by an independent Java program on Minecraft's codec primitives
  (`packages/pumpkin_neoforge/tool/golden/Golden.java`, output in
  `test/golden/neoforge_codecs.txt`, checked by the Dart and the Python tests).
  That `Identifier` and the enum ordinals are the same in 26.3 is assumed.
* Nothing here was observed on a live client. See
  [What could not be determined](#what-could-not-be-determined).

## What must be sent, in which order

### A. A real NeoForge server (the reference)

Source: `patches/.../ServerConfigurationPacketListenerImpl.java.patch`,
`NF/network/ConfigurationInitialization.java`, `NF/network/registration/NetworkRegistry.java`.

| # | dir | what | rule |
| - | --- | ---- | ---- |
| 1 | S->C | `minecraft:unregister` = `{minecraft:register, minecraft:unregister}` and the optional serverbound *play* channels | `getInitialServerUnregisterChannels` (NetworkRegistry 610) |
| 2 | S->C | `minecraft:register` = the 7 builtin channels | `getInitialListeningChannels` (605) |
| 3 | S->C | `neoforge:register` with an empty map (the *query*) | `startConfiguration` |
| 4 | S->C | ping, id 0 | `startConfiguration` |
| 5 | C->S | `minecraft:register` (what the client can receive) | client, on receiving 2 |
| 6 | C->S | `neoforge:register` (what the client registered), sets the client's connection type to NeoForge | client, on receiving 3 |
| 7 | C->S | pong 0 | |
| 8 | S->C | `neoforge:network` (negotiated channels), `minecraft:register` | `handleCustomPayload` -> `initializeNeoForgeConnection` (342) |
| 9 | S->C | brand, server links, resource pack, enabled features, known packs... (vanilla `runConfiguration`) | after the pong |
| 10 | S->C | **registry sync**: `neoforge:frozen_registry_sync_start`, one `neoforge:frozen_registry` per registry, `neoforge:frozen_registry_sync_completed`; **C->S** the same `..._completed` as acknowledgement | `SyncRegistries` task, added *before* vanilla's `SynchronizeRegistriesTask` "so registries sync before vanilla sends tags" |
| 11 | S->C | vanilla registry data, tags, ... | `SynchronizeRegistriesTask` |
| 12 | S<->C | `c:version` / `c:version`, `c:register` / `c:register` | `CommonVersionTask`, `CommonRegisterTask` |
| 13 | S->C | `neoforge:config_file` for each synced server config | `SyncConfig` (no reply) |
| 14 | S<->C | `neoforge:known_registry_data_maps` / `..._reply` | `RegistryDataMapNegotiation` |
| 15 | S<->C | `neoforge:extensible_enum_data` / `neoforge:extensible_enum_ack` | `CheckExtensibleEnums` |
| 16 | S<->C | `neoforge:feature_flags` / `neoforge:feature_flags_ack` | `CheckFeatureFlags` |
| 17 | C->S | `minecraft:unregister`, `minecraft:register` (play channels), then `finish_configuration` | client `handleConfigurationFinished` -> `onConfigurationFinished` |
| 18 | S->C | `minecraft:unregister`, `minecraft:register` (play phase) | server `handleConfigurationFinished` |

Steps 12-16 only run when the client announced the channels (a vanilla client
announces none and is simply let through when every payload is optional).

### B. What the plugin library sends at the hold points

Three hold points: the **pre-brand** hold (`configuration-pre-brand-event`,
before the brand; only for the full mode), the **start** hold after Pumpkin's
brand and the **finish** hold after the registry data and tags
(`login_acknowledged.rs`, `known_packs.rs`). `NeoForgeNegotiation.adhoc` (the
default) uses the last two:

| hold | dir | what |
| ---- | --- | ---- |
| start | S->C | `minecraft:register` = builtin + `frozen_registry_sync_completed`, `known_registry_data_maps_reply`, `extensible_enum_ack`, `feature_flags_ack`, `split` (what the server receives; this is what lets the client *send* the acks) |
| start | C->S | `minecraft:register` (arrives after the brand; **absent for a vanilla client**, timeout 3 s) |
| start | | decision: the client announced `neoforge:register` and `neoforge:network` = NeoForge, otherwise the policy (default: disconnect) |
| start | S->C | `neoforge:frozen_registry_sync_start`, `neoforge:frozen_registry` per registry, `neoforge:frozen_registry_sync_completed` |
| start | C->S | `neoforge:frozen_registry_sync_completed` (acknowledgement; absent = disconnect) |
| start | | release |
| finish | S<->C | `c:version`, `c:register` |
| finish | S->C | `neoforge:config_file`* ; data map / enum / feature flag checks only when the spec has something to check |
| finish | | release (Pumpkin then sends `finish_configuration`) |

`NeoForgeNegotiation.full` moves the opening in front of the brand (rows 1-8
above), with the pre-brand hold:

| hold | dir | what |
| ---- | --- | ---- |
| pre-brand | S->C | `minecraft:unregister` = `{minecraft:register, minecraft:unregister}`, `minecraft:register` (as in the start row above), `neoforge:register` with an empty map (`00`, the query), then a **ping** (configuration packet 5, body `00 00 00 00`) |
| pre-brand | C->S | `minecraft:register`, `neoforge:register` (what the client registered), **pong** (packet 5); a vanilla client answers the ping only |
| pre-brand | | decision: no query answer within the timeout (the pong shortcuts this: answer or not, 1 s after the pong) = not NeoForge: the policy (default: disconnect; `allow`: release, the connection stays `vanilla`) |
| pre-brand | | the answer is negotiated (a failure sends `neoforge:modded_network_setup_failed` and disconnects); host: `set-connection-flavour(neoforge)` |
| pre-brand | S->C | `neoforge:network`, a second `minecraft:register` (builtin + the negotiated configuration channels) |
| pre-brand | | release: the host sends the brand and fires the start event |
| start | S->C | `neoforge:frozen_registry_sync_start`, `neoforge:frozen_registry` per registry, `..._sync_completed` |
| start | C->S | `..._sync_completed` (acknowledgement) |
| start | | release |
| finish | S<->C | `c:version`, `c:register`; `neoforge:config_file` with an **empty** `neoforge-server.toml` (a client classified before the brand expects the synced config; an empty file gives the defaults; the name is an option, `neoForgeConfigFiles`: a later NeoForge commit renamed the type, so the file may be `neoforge-synced.toml`; not verified for 26.3.0.7-beta), then as above |

The rest of the exchange (rows 9 onwards) is the same.

### C. What the client sends (strict client, `neoforge_client.py`)

After its brand and client information: `minecraft:register` when it
classifies the connection ([Channels](#channel-announcement-and-classification)),
the `neoforge:register` answer to a query, `c:version`/`c:register` answers,
the acknowledgements, and `minecraft:unregister` + `minecraft:register` right
before its `finish_configuration` ack.

## Configuration packets around the exchange

26.3 configuration packet ids (`mc_ids.py`, from Pumpkin's generated `packet.rs`):

| packet | S->C | C->S |
| ------ | ---- | ---- |
| custom payload | 1 | 2 |
| finish configuration | 3 | 3 |
| keep alive | 4 | 4 |
| ping / pong | 5 | 5 |
| registry data | 7 | |
| update enabled features | 13 | |
| update tags | 14 | |
| select known packs | 15 | 7 |

A custom payload packet is `string channel` (UTF-8 with a VarInt length, the
identifier as `namespace:path`) followed by the payload bytes up to the end of
the packet. Clientbound payloads may be 1 048 576 bytes, serverbound 32 767
(`ClientboundCustomPayloadPacket` patch: `MAX_PAYLOAD_SIZE`; the serverbound
limit is vanilla's). **Trailing bytes in a payload the client knows are a
decode error** (vanilla `PacketDecoder`: "was larger than I expected, found N
bytes extra"), so every layout below must be exact. A payload decode failure
disconnects ("Failed decoding custom payload", `CustomPacketPayload.codec`
patch).

## Payload formats

Notation: `VarInt`, `string` = VarInt byte length + UTF-8 (max 32 767 chars),
`id` = `string` holding `namespace:path` (lower case `[a-z0-9_.-]`, path also
`/`), `bool` = 1 byte, `list<T>` / `set<T>` / `map<K,V>` = VarInt count then the
elements (`ByteBufCodecs.collection` / `map`), `opt<T>` = `bool`, then `T` if
true. Enums are VarInt ordinals (`FriendlyByteBuf.writeEnum`).

Enums: `ConnectionProtocol`: handshake 0, **play 1**, status 2, login 3,
**configuration 4**; string ids `"play"`, `"configuration"`. `PacketFlow`:
**serverbound 0, clientbound 1**.

### `minecraft:register` / `minecraft:unregister` (both directions)

`NF/network/payload/MinecraftRegisterPayload.java`, `MinecraftUnregisterPayload.java`,
`DinnerboneProtocolUtils.java` (28-60).

| bytes | meaning |
| ----- | ------- |
| repeated: ASCII bytes of `namespace:path`, `0x00` | a channel; **no length prefix, no count**; order irrelevant (a `Set`) |

The reader splits at `0x00`, reads bytes as chars, and ignores names that are not
valid identifiers (logs "Invalid channel"). An empty payload is valid. Receiving
`register` adds the names to the connection's *ad hoc channels*
(`NetworkRegistry.onMinecraftRegister`, 586), `unregister` removes them (598).

Example: `minecraft:register` + `c:version` ->
`6d 69 6e 65 63 72 61 66 74 3a 72 65 67 69 73 74 65 72 00 63 3a 76 65 72 73 69 6f 6e 00`.

### `neoforge:register` (query, `ModdedNetworkQueryPayload`)

`NF/network/payload/ModdedNetworkQueryPayload.java` (32-46), `ModdedNetworkQueryComponent.java`.
Server -> client: an empty map. Client -> server: everything it registered.

| field | type | notes |
| ----- | ---- | ----- |
| protocols | `map<VarInt, list<component>>` | key = `ConnectionProtocol` ordinal (1 play, 4 configuration); the client sends exactly these two |
| component.id | `id` | the payload channel |
| component.version | `string` | `"1"` for NeoForge's own |
| component.flow | `opt<VarInt>` | `PacketFlow` ordinal; absent = both directions |
| component.optional | `bool` | |

Empty query: `00`. One configuration component, optional, both directions,
`neoforge:frozen_registry_sync_completed` v1:
`01 04 01 27 <"neoforge:frozen_registry_sync_completed"> 01 31 00 01`.

What a NeoForge client without mod payloads sends (all optional, version `"1"`;
`NetworkInitialization.java` 42-101, `GenericPacketSplitter.java` 61-63):

| protocol | channel | flow |
| -------- | ------- | ---- |
| configuration, play | `neoforge:config_file` | clientbound |
| configuration, play | `neoforge:split` | both |
| configuration | `neoforge:frozen_registry_sync_start`, `neoforge:frozen_registry`, `neoforge:known_registry_data_maps`, `neoforge:extensible_enum_data`, `neoforge:feature_flags` | clientbound |
| configuration | `neoforge:frozen_registry_sync_completed` | both |
| configuration | `neoforge:known_registry_data_maps_reply`, `neoforge:extensible_enum_ack`, `neoforge:feature_flags_ack` | serverbound |
| play | `neoforge:advanced_add_entity`, `advanced_open_screen`, `auxiliary_light_data`, `registry_data_map_sync`, `advanced_container_set_data`, `recipe_content`, `sync_attachments` | clientbound |

### `neoforge:network` (`ModdedNetworkPayload`, server -> client)

`NF/network/payload/ModdedNetworkPayload.java`, `registration/NetworkPayloadSetup.java` (30-34),
`NetworkChannel.java` (22-25).

| field | type |
| ----- | ---- |
| protocols | `map<VarInt, map<id, channel>>` (key = protocol ordinal) |
| channel | `id` (**the id again**, inside the value), `string` chosen version |

`01 04 01 18 <"neoforge:frozen_registry"> 18 <"neoforge:frozen_registry"> 01 31`
is `{configuration: {neoforge:frozen_registry: "1"}}`.

### `neoforge:modded_network_setup_failed` (server -> client)

`ModdedNetworkSetupFailedPayload.java` (27-33): `map<id, component>` where the
component is **network NBT** (`ComponentSerialization.TRUSTED_CONTEXT_FREE_STREAM_CODEC`):
tag type byte, then the payload, no name. A literal text is a string tag
(`08 <u16 length> <modified UTF-8>`); a translatable one is a compound
`{translate: string, with: list<compound{text|translate}>}`. The client stores the
map (`failureReasons`) and shows `ModMismatchDisconnectedScreen` when the server
then disconnects. The negotiator's reasons are translatable
(`neoforge.network.negotiation.failure.*`, below).

### `c:version` and `c:register` (both directions)

`CommonVersionPayload.java` (26-30), `CommonRegisterPayload.java` (28-34),
`NetworkRegistry.checkCommonVersion` (631) / `onCommonRegister` (655).

| payload | fields |
| ------- | ------ |
| `c:version` | `list<VarInt>` supported versions; only **1** exists. `01 01` |
| `c:register` | `VarInt` version (1), `string` protocol id (`"play"`), `set<id>` channels. `01 04 "play" 01 05 "c:foo"` |

On receiving `c:version` the client checks that 1 is in the list (else
disconnect "Unsupported common network version...") and, in the configuration
phase, answers with its own `c:version [1]`. On `c:register` it replaces the
common channels of that protocol with the list and answers with `c:register 1
"play" <its optional clientbound play channels>`. The server's tasks
(`CommonVersionTask`, `CommonRegisterTask`) finish when the answer arrives. The
server sends `c:register` with the optional *serverbound* play channels it has.

### Registry sync payloads

`FrozenRegistrySyncStartPayload.java` (27-33), `FrozenRegistryPayload.java` (24-30),
`FrozenRegistrySyncCompletedPayload.java`, `registries/RegistrySnapshot.java` (28-60).

| channel | dir | body |
| ------- | --- | ---- |
| `neoforge:frozen_registry_sync_start` | S->C | `list<id>` registry names the server will send |
| `neoforge:frozen_registry` | S->C | `id` registry name, then the snapshot: `map<VarInt, id>` **numeric id -> entry**, then `map<id, id>` aliases (old -> new) |
| `neoforge:frozen_registry_sync_completed` | S->C and C->S | empty |

The snapshot's id map is written in increasing id order (a sorted map); the
client applies the entries in that order, so the order matters. Example
(`minecraft:item`, ids 0, 1, 300 and no aliases):
`0e <"minecraft:item"> 03 00 0d <"minecraft:air"> 01 0f <"minecraft:stone"> ac 02 1b <"lonsdaleite:raw_lonsdaleite"> 00`.

### Data maps

`KnownRegistryDataMapsPayload.java`, `KnownRegistryDataMapsReplyPayload.java`.

| channel | dir | body |
| ------- | --- | ---- |
| `neoforge:known_registry_data_maps` | S->C | `map<id registry, list<(id dataMap, bool mandatory)>>` |
| `neoforge:known_registry_data_maps_reply` | C->S | `map<id registry, list<id dataMap>>` (all the client knows) |

### Extensible enums and feature flags

`ExtensibleEnumDataPayload.java`, `CheckExtensibleEnums.java` (233-262),
`FeatureFlagDataPayload.java`.

| channel | dir | body |
| ------- | --- | ---- |
| `neoforge:extensible_enum_data` | S->C | `list<entry>`; entry = `string` Java class name, `string` network check (`"CLIENTBOUND"`, `"SERVERBOUND"`, `"BIDIRECTIONAL"`), `opt<(VarInt vanillaCount, VarInt totalCount, list<string> addedNames)>` |
| `neoforge:extensible_enum_ack` | C->S | empty |
| `neoforge:feature_flags` | S->C | `set<id>` modded flags |
| `neoforge:feature_flags_ack` | C->S | empty |

### `neoforge:config_file` (S->C, `ConfigFilePayload.java`)

`string` file name (`neoforge-server.toml`), `byte[]` (VarInt length + bytes) file
contents. Not acknowledged.

## Channel announcement and classification

The core rules, all in `NF/network/registration/NetworkRegistry.java` and
`NF/client/network/registration/ClientNetworkRegistry.java`.

**The client may only send a channel the server announced.** `checkPacket`
(425-460) throws `UnsupportedOperationException("Payload X may not be sent to
the server!")` for a serverbound custom payload that is not builtin
(`neoforge:register`, `neoforge:network`, `neoforge:modded_network_setup_failed`,
`c:version`, `c:register`, `minecraft:register`, `minecraft:unregister`), not in
the `minecraft:` namespace, and not in `hasChannel` (483-514): the negotiated
payload setup of the protocol, the `c:register` channels, or the *ad hoc*
channels (what the other side announced with `minecraft:register`). The server
side is the same for clientbound payloads.

**A clientbound payload is readable if the client has an optional registration
for it** (`hasAdhocChannel`, 471: registered, optional, flow matches),
announced or not. A payload without any registration is decoded as a
`DiscardedPayload` and ignored.

**Classification of the connection** (`ClientConfigurationPacketListenerImpl`
patch, `handleCustomPayload`, `handleEnabledFeatures`, `handleConfigurationFinished`;
`ClientNetworkRegistry.initializeOtherConnection` 226, `runConnectionInitialization` 308):

| event on the client | effect |
| ------------------- | ------ |
| receives `neoforge:register` | the *listener's* connection type becomes NEOFORGE; the client answers with its registrations |
| receives `minecraft:register` before any classification | adds the names, then sends its own `minecraft:register` = the 7 builtin channels + its optional *clientbound configuration* payloads (`sendInitialListeningChannels`, 283) |
| receives `neoforge:network` | `initializeNeoForgeConnection` (203): stores the payload setup, sets the channel type, sends `minecraft:register` (builtin + negotiated configuration channels) -- **only if the connection was not initialised before** |
| receives the server's `minecraft:brand` while the type is still "other" | `initializeOtherConnection`: payload setup = **empty**, checks the mod's payloads against an empty server (a non-optional one disconnects: "You are trying to connect to a server that is not running NeoForge, but you have mods that require it"), enum/feature flag checks, loads default server configs, sends `minecraft:register` |
| receives `update_enabled_features` / sends `finish_configuration` while the type is "other" | the same fallback |
| a modded payload while no payload setup exists | disconnect `multiplayer.disconnect.incompatible` "NeoForge <version> (No Payload Setup)" |
| a modded payload that is neither in the setup nor optional | disconnect "(No Channel for <id>)"; a registered payload without handler: "(No Handler for <id>)" |

"Initialised" is a once-only flag per connection (`runConnectionInitialization`).
**After the brand-triggered initialisation, `neoforge:network` is a no-op**: the
setup stays empty and the channel type stays "other", though the *listener's*
type became NEOFORGE when the query arrived.

### The ordering problem

A real server sends the query before the brand, so the connection is
classified NeoForge before the brand arrives. Pumpkin sends the brand first
unless a plugin holds the connection *before* it (the pre-brand hold), so there
are two modes, and the table says what each means for a plugin:

| | brand first (Pumpkin, start hold only) | query first (real NeoForge; Pumpkin with the pre-brand hold) |
| - | --------------------- | ------------------------------------------ |
| classification | other (empty setup, ad hoc channels) | NeoForge (negotiated setup) |
| registry sync | works: the three sync payloads are optional registrations (readable ad hoc); the ack needs the server's `minecraft:register` | works |
| `neoforge:network` | ignored | applied |
| server configs | the client loads the *defaults* of the synced configs (`loadDefaultServerConfigs`) | the server must send `neoforge:config_file` for `neoforge-server.toml`, else the client's synced config stays unloaded |
| play encodings | vanilla (if the plugin did not send `neoforge:register`) | NeoForge ([Play phase](#play-phase)) |

`NeoForgeNegotiation.adhoc` (the default) is the brand-first mode: no query is
sent, so the listener stays "other" and nothing in the play phase changes.
`NeoForgeNegotiation.full` is the query-first mode, done in the pre-brand
hold; the connection is then really NeoForge for the client, which has the
consequences listed in [neoforge-play-codecs.md](neoforge-play-codecs.md)
(elytra, `recipe_content`, the server config).

## Registry synchronisation

### Who defines the ids

The server. `RegistryManager.applySnapshot` (NF/registries/RegistryManager.java
130-189), per received registry:

1. `unfreeze`, `clear(false)`: **the id table is cleared** (the entries
   themselves stay);
2. for each `(id, name)` in increasing id order: if the client's registry has no
   entry `name`, the key is *missing* (and no further ids are mapped for that
   registry); otherwise `registerIdMapping(name, id)` (patch
   `MappedRegistry`: grows the id list with `null`s up to `id`);
3. aliases are added, `freeze`.

Missing keys disconnect the client (`neoforge.network.registries.sync.server-with-unknown-keys`,
"The server sent registries with unknown keys: ResourceKey[minecraft:item / x:y], ...")
and the registries revert to the frozen state. A registry name the client does
not know is ignored if its snapshot is empty, otherwise an
`IllegalStateException` ("Tried to applied snapshot with registry name X but was
not found") disconnects it. The sync completes only when every registry named
in `..._sync_start` arrived, else `neoforge.network.registries.sync.missing`
("Not all expected registries were received from the server! (missing: ...)").
The handlers are in `NF/client/.../ClientPayloadHandler.java` 85-110, enqueued
on the main thread (`MainThreadPayloadHandler`). On success the client replies
`neoforge:frozen_registry_sync_completed`. After a disconnect the client
reverts the registries (`Minecraft.disconnect` patch).

### What "missing" and "extra" mean

| situation | client behaviour |
| --------- | ---------------- |
| the snapshot has an entry the client does not have | **disconnect** (unknown keys) |
| the client has an entry the snapshot lacks (a vanilla entry omitted, or a mod entry the server does not know) | **no error**: the entry keeps no id (`-1`); anything that later uses it breaks. The real NeoForge server never causes this because it sends every entry of the registry |
| ids with a gap (e.g. 0, 1, 3) | no error; the id list gets a `null` hole that crashes iteration later |
| the server never sends a sync | no error; the client keeps its own ids: vanilla first (the vanilla order), mod entries appended in registration order |
| the server sends only `..._completed` | the client has nothing to apply and acknowledges |
| client without the mod, server with its entries | `minecraft:item` snapshot contains unknown keys -> the client disconnects itself; a *vanilla* client never answers (the payload is discarded) |

`neoforge_client.py` fails the second and third rows by default ("stricter than
NeoForge", `--lenient` downgrades) and requires that the mod's registries were
synced and acknowledged.

### Which registries are synced

`NF/registries/NeoForgeRegistriesSetup.java` 32-62 (`VANILLA_SYNC_REGISTRIES`):
`sound_event`, `mob_effect`, `block`, `entity_type`, `item`, `fluid`,
`particle_type`, `block_entity_type`, `menu`, `command_argument_type`,
`stat_type`, `villager_type`, `villager_profession`, `data_component_type`,
`recipe_serializer`, `attribute`, `potion`, `number_format_type`,
`custom_stat`, `position_source_type`, `map_decoration_type`,
`consume_effect_type`, `recipe_display`, `slot_display`,
`recipe_book_category`, `recipe_type`, `point_of_interest_type`, `game_event`,
`debug_subscription` (all `minecraft:`; 29), plus NeoForge's own
`neoforge:entity_data_serializers`, `neoforge:fluid_type`,
`neoforge:holder_set_type`, `neoforge:ingredient_serializer`,
`neoforge:fluid_ingredient_type` and `neoforge:synced_attachment_types`
(`NeoForgeRegistries.java` 34-41, `AttachmentSync.java` 51-63), and every mod
registry built with `.sync(true)`. A real server sends all of them
(`RegistryManager.generateRegistryPackets`), **with all vanilla entries**, in
registry (key) order. **`creative_mode_tab` is not synced**, nor are the datapack
registries.

The vanilla entries come first with their vanilla ids (they are registered
first), then the mods' entries in registration order (`DeferredRegister`
order; Lonsdaleite: block `lonsdaleite_wardframe`, items in declaration order,
the block item first). A server only has to send the registries that contain
modded entries (`minecraft:item` and `minecraft:block` for Lonsdaleite): for the
others the client keeps ids that equal the vanilla ones.

The ids a plugin sends must be **the ids its host puts on the wire**: for the
vanilla entries Pumpkin's own (`assets/items.json`, `blocks.json`, ... which
`pumpkin_neoforge`'s generator reads), the modded ones appended, **and the host
must use the appended ids when it sends one of them** (an `ItemStack` of a
modded item carries the id from this snapshot).

**Block state ids follow the block snapshot.** Every `freeze` (also the one at
the end of `applySnapshot`) rebuilds the client's block state id map by walking
the block registry in id order and appending each block's states
(`NeoForgeRegistryCallbacks.BlockCallbacks.onClear`/`onBake`, 40-96). So the
order of `minecraft:block` in the snapshot *is* the numbering of block states in
chunk data: it must be the vanilla block order (Pumpkin's `blocks.json` ids,
which its own block state ids follow), and an omitted or reordered vanilla block
shifts every state after it. Modded blocks, appended last, get their states
after all vanilla ones.

### Creative mode tabs, menus and the rest

`minecraft:creative_mode_tab` is a normal registry that is *not* synced. A mod's
tab and its contents (`displayItems`, `BuildCreativeModeTabContentsEvent`) are
built by client code from item objects; the server sends nothing about them.
`minecraft:menu` is synced (`ClientboundOpenScreenPacket` ids); mods with their
own menus need entries there and `neoforge:advanced_open_screen` in play.

## The other configuration tasks

* **Data maps** (`RegistryDataMapNegotiation`): the server sends its known data
  maps; the client compares only the *mandatory* ones (both directions, messages
  `neoforge.network.data_maps.missing_our/missing_their`) and replies with all it
  knows. NeoForge's own data maps (`neoforge:oxidizables`, ...) are not
  mandatory. Without the exchange, play-phase data map syncs
  (`neoforge:registry_data_map_sync`) never happen.
* **Extensible enums**: the client compares the server's entries with its own
  (`CheckExtensibleEnums.handleClientboundPayload` 74-157). A class where
  neither side added entries is skipped, so an empty list is accepted by a
  client whose mods add no enum values (NeoForge itself adds none:
  `NetworkedEnum`-annotated vanilla enums are only *extensible*). Mismatch:
  `neoforge.network.extensible_enums.enum_entry_mismatch`.
* **Feature flags**: the client compares the *modded* flags as sets
  (`CheckFeatureFlags.handleClientboundPayload` 53-78); mismatch `neoforge.network.feature_flags.entry_mismatch`.
* **Config sync**: `neoforge:config_file` per `SERVER` config. NeoForge's own is
  `neoforge-server.toml`. Only needed when the client was classified NeoForge
  before the brand ([ordering](#the-ordering-problem)): the full mode sends an
  empty one in the finish hold.

## What the client verifies and how it fails

| check | where | failure |
| ----- | ----- | ------- |
| a payload arrives before classification | `handleModdedPayload` 143-179 | `multiplayer.disconnect.incompatible` "NeoForge X (No Payload Setup / No Channel for ... / No Handler for ...)" |
| a payload it sends was not announced | `checkPacket` | `UnsupportedOperationException` (the client crashes out of the connection) |
| required mod payloads against a non-NeoForge server | `initializeOtherConnection` | "You are trying to connect to a server that is not running NeoForge, but you have mods that require it. A connection could not be established." |
| unknown registry keys, missing registries, apply errors | `ClientPayloadHandler` | `neoforge.network.registries.sync.server-with-unknown-keys` / `.missing` / `.failed` |
| mandatory data maps | `ClientRegistryManager.handleKnownDataMaps` | `neoforge.network.data_maps.missing_our` / `missing_their` |
| enums, feature flags | `CheckExtensibleEnums`, `CheckFeatureFlags` | `neoforge.network.extensible_enums.enum_entry_mismatch`, `neoforge.network.feature_flags.entry_mismatch` |
| `c:version` | `checkCommonVersion` | "Unsupported common network version. This installation of NeoForge only supports: 1" |
| channel negotiation (server side, `NetworkComponentNegotiator`, 55-198) | server | `neoforge:modded_network_setup_failed` then a disconnect; the client shows the mismatch screen |

The negotiator: an optional channel the other side lacks is dropped; a
non-optional one the other side lacks fails (`missing.client.server`: "This
channel is missing on the server side, but required on the client!",
`missing.server.client`); a channel both have must have the same flow
(`flow.client|server.missing|mismatch`) and the same version string
(`version.mismatch`, "The client wants the payload to be version: %s, but the
server wants it to be version: %s!"); each reason is wrapped with the mod's
display name (`neoforge.network.negotiation.failure.mod`: "Channel of mod \"%1$s\"
failed to connect: %2$s") when a mod with that id is installed.

The mismatch screen is `ModMismatchDisconnectedScreen` (shown when
`modded_network_setup_failed` arrived). There is no mod list or server-list ping
data in 26.3: the `fml.menu.multiplayer.*` language keys remain but nothing in
the source uses them. NeoForge's disconnect for an incompatible peer carries
the translatable `multiplayer.disconnect.incompatible`.

## Play phase

Nothing has to be sent or answered for a client with a registry-only mod:

* The client sends `minecraft:unregister` and `minecraft:register` right before
  its `finish_configuration` (step 17) and the server sends the same pair when it
  starts the play phase (`onConfigurationFinished`: unregister the initial and
  negotiated configuration channels, register `register`, `unregister`, and for
  NeoForge connections `neoforge:register`, otherwise the optional clientbound
  play channels). They may be ignored.
* Optional NeoForge play payloads: `neoforge:recipe_content` (before
  recipes, NeoForge servers only; without it mods get no `RecipesReceivedEvent`),
  `neoforge:registry_data_map_sync`, `neoforge:sync_attachments`,
  `neoforge:advanced_*`, `neoforge:auxiliary_light_data`, `neoforge:config_file`.
* **The connection type changes play encodings.** `RegistryFriendlyByteBuf`
  carries it, and `NeoForgeStreamCodecs.connectionAware` (used by
  `BlockParticleOption`) differs: on a NEOFORGE connection a block particle
  option reads an extra `opt<BlockPos>` after the block state id; on an "other"
  connection nothing. Also: recipe book settings (extra entries for modded
  recipe book types only), custom ingredients and holder sets (only written for
  NeoForge connections), `ItemAttributeModifiers` (only written; filtered for
  "other"). A host that sends vanilla encodings must therefore **not** make the
  client treat the connection as NeoForge. Which type the play phase gets is the
  *listener's* (set by `neoforge:register`, copied into the `CommonListenerCookie`),
  so the adhoc mode (no query) is the safe one.

## What the host has to provide

* the two hold points with the semantics in [configuration.md](configuration.md);
  the **start hold must be early enough** that the sync completes before the
  host sends tags (it is: right after the brand, before known packs);
* custom payloads of up to ~100 KB per message (the item snapshot is ~50 KB);
* in the play phase, ids of modded entries that agree with the snapshot (see
  [Registries](#which-registries-are-synced));
* for `NeoForgeNegotiation.full`: sending the query *before the brand*
  (`configuration-pre-brand-event`, provided) and NeoForge play encodings
  (`BlockParticleOption` etc.) for clients that answered it
  (`server.set-connection-flavour`, provided; see
  [neoforge-play-codecs.md](neoforge-play-codecs.md)).

## What could not be determined

* **Anything about a live client.** No client was run. The strict test client
  encodes the source's rules; where the source (patches and NeoForge classes)
  does not show Minecraft's own code, behaviour is taken from the 1.21.11 jar.
* Whether Pumpkin's *vanilla* handling of unknown serverbound configuration
  payloads (`neoforge:*`, `c:*`, `minecraft:register`) is harmless: the host
  fires them as `configuration-payload-event` and only special-cases the brand
  (`pending.rs` `handle_plugin_message`).
* Whether the real client in the brand-first case ("other" classification plus a
  later query) has any other effect than the ones listed. The adhoc mode avoids
  the query entirely; the `full` mode sends it before the brand (untested on a
  live client).
* The exact NeoForge version `26.3.0.7-beta` corresponds to; whether any network
  code changed between it and `b160270bd`.
* Whether `Identifier.STREAM_CODEC`, the `ConnectionProtocol` ordinals and
  `ByteBufCodecs.map`/`collection` are unchanged from 1.21.11 in 26.3 (assumed).
* Whether Pumpkin's generated registry lists (`items.json` ...) equal the
  26.3 client's vanilla registries in content: sizes and ids are what Pumpkin
  puts on the wire for vanilla clients; an entry the client lacks would
  disconnect it ("unknown keys"), an entry missing would lose its id. The lists
  for registries other than item, block, entity type and fluid (sounds,
  particles, effects, ...) were not cross-checked against a vanilla dump.
* Which of NeoForge's registries a Lonsdaleite client has entries in that this
  document does not cover (it registers items, one block and a tab; no data
  components, payloads, data maps, or registries, per the source).

## Corrections to loader-notes.md

* "Mods that add registry entries ... are rejected the same way": **not found in
  the source.** `initializeOtherConnection` negotiates only *payloads*
  (`NetworkComponentNegotiator` against an empty server list), the enum and
  feature flag checks, and nothing about registries. A client with a
  registry-only mod joins a server that is not NeoForge; the server just does
  not know the modded ids. The handshake in this document is for *proving* the
  server knows the mod and for giving the modded entries their ids, not for
  getting past a check. (To be confirmed live.)
* "The server does **not** send `neoforge:*` packets": fine for payload-only
  mods; for the registry sync the server sends `neoforge:frozen_registry*` and
  announces the channels it receives.
