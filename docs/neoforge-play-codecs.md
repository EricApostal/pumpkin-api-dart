# NeoForge: what changes on the wire for a NeoForge connection

Which network encodings of the play and configuration phase differ when the client
treats the connection as a NeoForge one, read from the NeoForge source, and what
Pumpkin writes for connections a plugin marked as NeoForge. This page continues
[neoforge-protocol.md](neoforge-protocol.md) ("Play phase" and "The ordering
problem"); the hooks it uses are in [configuration.md](configuration.md).

Contents: [Summary](#summary) -
[Sources](#sources-and-method) -
[How a connection becomes NeoForge](#how-a-connection-becomes-neoforge) -
[Encodings that differ](#encodings-that-differ) -
[Not wire, but visible](#behaviour-that-changes-without-a-wire-change) -
[Pumpkin](#how-pumpkin-does-it) -
[Status](#status-of-every-item) -
[For the Dart plugin](#note-for-the-dart-plugin-neoforgenegotiationfull)

## Summary

* The client's connection type is `NEOFORGE` from the moment it **receives the
  `neoforge:register` query** (an empty `ModdedNetworkQueryPayload`), nothing else
  is needed. It is copied into the play phase when the configuration ends, and from
  then on every *registry friendly* play packet (`RegistryFriendlyByteBuf`) is
  decoded with it.
* **Exactly one clientbound encoding differs for vanilla data**: the block state
  options of particles (`block`, `block_marker`, `falling_dust`, `dust_pillar`,
  `block_crumble`) read an `Optional<BlockPos>` after the state id. That is the only
  thing that Pumpkin has to write differently. It is implemented.
* Three more codecs are connection aware but write the same bytes as vanilla for
  vanilla content: the recipe book settings (extra entries only for *modded* recipe
  book types), `Ingredient` (custom ingredients only) and holder sets (custom holder
  set types only). `ItemAttributeModifiers` writes everything on a NeoForge connection
  and drops non-`minecraft:` attributes on others, which is the same for vanilla
  attributes.
* **Nothing differs for serverbound packets** that a vanilla server does not already
  read, and nothing differs in the configuration phase (its packets are not
  registry friendly).
* Behaviour, not encoding: the NeoForge client **does not start elytra gliding unless
  the server sent the `neoforge:gliding_flight` attribute**
  ([below](#behaviour-that-changes-without-a-wire-change)). Marking a connection
  as NeoForge costs that unless the plugin sends the attribute.

## Sources and method

* NeoForge branch `26.3.x` at commit `6dc5dfc8e3016c40e67a6d56c7e38bade0402b21`
  (2026-10-03). `neoforge-protocol.md` was read at `b160270bd` (tag `26.3.0`); every
  file cited here was last changed in December 2025 or earlier, so both agree.
* Raw files from `raw.githubusercontent.com/neoforged/NeoForge/<commit>/<path>`;
  `NF` is `src/main/java/net/neoforged/neoforge`, patches are under
  `patches/net/minecraft/...` (`.patch` files, line numbers are those of the patch
  file, `+` lines are added code), `CLIENT` is `src/client/java/net/neoforged/neoforge`.
* All uses of the connection type were found by searching the whole tree (patches,
  `src/main`, `src/client`) for `getConnectionType`, `ConnectionType`,
  `connectionAware` and `isNeoForge`. The complete list of consumers of the type is
  below; there are no others.

  | where | what |
  | ----- | ---- |
  | `NeoForgeStreamCodecs.connectionAware` (`NF/network/codec/NeoForgeStreamCodecs.java` 93-117) | used only by `BlockParticleOption` |
  | `patches/net/minecraft/network/codec/ByteBufCodecs.java.patch` 68 | holder set encoder |
  | `NF/common/crafting/IngredientCodecs.java` 55, 81 | custom ingredients |
  | `NF/common/CommonHooks.java` 1657, 1670, 1877 | recipe book settings, `ItemAttributeModifiers` |
  | `NF/common/CommonHooks.java` 1724 | server sends `neoforge:recipe_content` payload |
  | `patches/net/minecraft/world/entity/LivingEntity.java.patch` 672-685 and `client/player/LocalPlayer.java.patch` 50-56 | gliding |
  | `CLIENT/client/ClientHooks.java` 654-660 | `RecipesReceivedEvent` for non-NeoForge connections |
  | `NF/network/filters/VanillaConnectionNetworkFilter.java` 49-62 | filters for *non*-NeoForge connections (below) |
  | `NF/network/filters/NetworkFilters.java` 42-52 | choosing the filter |

## How a connection becomes NeoForge

Client side (`patches/net/minecraft/client/multiplayer/ClientConfigurationPacketListenerImpl.java.patch`):

* line 72: on a `ModdedNetworkQueryPayload` (`neoforge:register`) the listener's
  `connectionType` becomes `NEOFORGE`; nothing else sets it, in particular not
  `neoforge:network` and not the brand;
* lines 25-26 and 49-50: when the configuration finishes the client builds the play
  protocols (clientbound *and* serverbound) with
  `RegistryFriendlyByteBuf.decorator(registries, this.connectionType)`, and passes the
  type to the play listener in the cookie (line 35, `ClientPacketListener.java.patch`
  15);
* `patches/net/minecraft/network/RegistryFriendlyByteBuf.java.patch` 7-27: the buffer
  carries it (`getConnectionType()`); the deprecated constructor means `OTHER`.

Server side (what the reference does, for comparison;
`patches/net/minecraft/server/network/ServerConfigurationPacketListenerImpl.java.patch`):

* 6-12: `startConfiguration` sends `minecraft:unregister`, `minecraft:register`,
  `neoforge:register` (`ModdedNetworkQueryPayload(Map.of())`) and a ping *instead of*
  the brand, which follows only after the client's pong (`handlePong`, 48-57);
* 38-46: the client's `neoforge:register` answer sets the server's type to NEOFORGE;
* 65-72: at the end of the configuration the outbound play protocol is bound with that
  type, and it goes into the player's cookie.

A client that receives the brand while its type is still `OTHER` classifies the
connection as non-NeoForge for good (`ClientConfigurationPacketListenerImpl.patch` 89-93,
`ClientNetworkRegistry.initializeOtherConnection` 226-243, `configureOtherConnection` 240-275; see
neoforge-protocol.md "The ordering problem"). The type itself can still become
NEOFORGE later if the query arrives (line 72 does not check), but by then the client
has rejected mods with required payloads, which is why the query has to come first.

## Encodings that differ

Notation as in neoforge-protocol.md: `opt<T>` = `bool`, then `T` when true;
`BlockPos` = one big endian `long` (x 26 bits, z 26 bits, y 12 bits).

### 1. `BlockParticleOption` (implemented)

`patches/net/minecraft/core/particles/BlockParticleOption.java.patch` 14-26 replaces

```java
ByteBufCodecs.idMapper(Block.BLOCK_STATE_REGISTRY).map(state -> new BlockParticleOption(type, state), ...)
```

by a composite of the state id and `connectionAware(optional(BlockPos.STREAM_CODEC),
uncheckedUnit(Optional.empty()))` (lines 19-22). `NeoForgeStreamCodecs.java` 97-117:
NEOFORGE selects the first codec, OTHER the second, which reads and writes nothing.

| connection | bytes of the particle options |
| ---------- | ----------------------------- |
| other | `VarInt` block state id |
| NeoForge | `VarInt` block state id, then `opt<BlockPos>` (`00` when absent, `01` + 8 bytes when present) |

* Added by "[1.21.4] Fix BlockParticleOption#pos not getting sent to the client (#1673)";
  the NeoForge server fills the position for sprint and landing particles
  (`world/entity/LivingEntity.java.patch` 50-52, `Entity.java.patch` 202-203), the
  client uses it to choose the particle texture (`client/particle/TerrainParticle.java.patch`).
  An absent position is valid.
* The vanilla particle types that use it: `block`, `block_marker`, `falling_dust`,
  `dust_pillar`, `block_crumble` (vanilla `ParticleTypes`; the class is not in the
  NeoForge repository, so this list is from the vanilla 1.21.11 source and was not
  checked against 26.3's: a type added in 26.3 that also uses `BlockParticleOption`
  is missing from Pumpkin's list, see
  `takes_block_particle_option` in `particle.rs`).
* Packets that carry a `ParticleOptions`:
  * `ClientboundLevelParticlesPacket` (Pumpkin `CParticle`, 26.3 layout: particle id,
    options, then the rest): **implemented**;
  * `ClientboundExplodePacket` (particle, and a weighted list of block particles):
    Pumpkin writes a fixed particle id and an empty list (`CExplosion`), no block
    option, nothing to do;
  * entity data of type `particle` / `particles` (area effect cloud and similar):
    Pumpkin writes none of the block types there, nothing to do (a plugin that
    writes entity data itself would have to add the `opt<BlockPos>`).
* Never serverbound.

### 2. Recipe book settings (implemented, zero entries)

`patches/net/minecraft/stats/RecipeBookSettings.java.patch` 7-20 and
`ClientboundRecipeBookSettingsPacket.java.patch` 8-9 (the packet now needs a
`RegistryFriendlyByteBuf` "to detect the connection type"); the extra codec is
`CommonHooks.MODDED_RECIPE_BOOK_TYPES_SETTINGS_STREAM_CODEC` (`CommonHooks.java`
1654-1676):

| connection | bytes after the four vanilla pairs (crafting, furnace, blast furnace, smoker) |
| ---------- | ------------------------------------------------------------------------------ |
| other | nothing |
| NeoForge | for each *extended* `RecipeBookType` value of the receiving JVM, in ordinal order: `bool open`, `bool filtering` |

The list is `MODDED_RECIPE_BOOK_TYPES` (1643-1652): the values a mod added to the
enum, and it is the **client's** list (the server writes as many pairs as its own JVM
has, and the extensible enum check, `CheckExtensibleEnums`, makes both agree when a
mod added any). A client without such a mod reads nothing extra, so Pumpkin's
`CRecipeBookSettings` is unchanged and correct. If a plugin ever has a client that
extends `RecipeBookType`, the packet needs `2 * n` more `bool`s: not implemented, the
count is not known to the host.

### 3. Things that are connection aware but identical for vanilla content

* **`Ingredient`** (`NF/common/crafting/IngredientCodecs.java` 35-89): a *custom*
  ingredient (`ICustomIngredient`) on a NeoForge connection is written as
  `VarInt -1000`, then `registry id of the ingredient type`, then its payload;
  everything else as vanilla. The reader peeks the first `VarInt` and backs up if it
  is not -1000, so vanilla ingredients (holder sets) are the same bytes. Pumpkin has
  no custom ingredients.
* **`HolderSet`** (`patches/net/minecraft/network/codec/ByteBufCodecs.java.patch` 63-72):
  a custom holder set type on a NeoForge connection is written as `VarInt (-1 - type
  id)` then the type's codec; the negative values are unused by vanilla (`0` = tag,
  `n + 1` = list of n). Pumpkin has no custom holder sets.
* **`ItemAttributeModifiers`** (`CommonHooks.java` 1864-1890,
  `world/item/component/ItemAttributeModifiers.java.patch` 8): on an `OTHER`
  connection entries whose attribute is not in the `minecraft` namespace are
  *dropped*, on a NeoForge one all are written. Same bytes for vanilla attributes.
* **Entity data serializer ids** (`CommonHooks.java` 1073-1092): modded serializers
  use ids from 256 up, vanilla ones are unchanged.
* **`ConnectionType` of payload buffers**: `RegistryFriendlyByteBuf`s that mods build
  for their own payloads (`FriendlyByteBufUtil` 31, `AttachmentSync` 251) always use
  NEOFORGE; that is inside payload bodies, not Pumpkin's business.

### 4. What a NeoForge server does *not* do for a NeoForge connection

`VanillaConnectionNetworkFilter` (`NF/network/filters/VanillaConnectionNetworkFilter.java`
49-62, injected only when the connection is not NeoForge, `NetworkFilters.java` 42-52)
cleans three packets for vanilla connections: `ClientboundUpdateAttributesPacket`
(drops non-`minecraft:` attributes, 67-77), `ClientboundCommandsPacket` (drops
argument types outside `minecraft`/`brigadier`, 79-90) and `ClientboundUpdateTagsPacket`
(drops tags of non-vanilla registries, 97-107). That is a filter on *content*, not an
encoding: Pumpkin sends only vanilla content, so it sends what the filter would leave.

### 5. Configuration phase

No configuration packet reads the connection type: the configuration protocols use
plain `FriendlyByteBuf`s (`ConfigurationProtocols.java.patch`). The one wire change
there is for all connections: serverbound `select_known_packs` accepts up to 1024
packs instead of 64 (`ServerboundSelectKnownPacks.java.patch` 9; "safe even on vanilla
connections", the client never answers with more than the server listed). Pumpkin's
`SKnownPacks` still caps at 64, which the few packs Pumpkin sends never reach.
Custom payloads are protocol aware (`CONFIG_STREAM_CODEC`, `ConfigurationProtocols.java.patch`
8) but keep the vanilla framing `identifier + bytes`.

### 6. Other differences found that are not encodings of the connection type

* Server list ping: `ServerStatus` gets `isModded` (`ServerStatus.java.patch` 4-19,
  JSON field `"isModded": true`), only a server list indicator.
* A larger payload limit is handled by `neoforge:split` payloads
  (`GenericPacketSplitter`); not needed below 1 MiB (`ClientboundCustomPayloadPacket`
  `MAX_PAYLOAD_SIZE`).
* Entity spawn extras (`IEntityWithComplexSpawn`), advanced menus, data map sync,
  attachment sync, `recipe_content`: all are **payloads** (`neoforge:advanced_add_entity`,
  `advanced_open_screen`, `registry_data_map_sync`, `sync_attachments`, `recipe_content`)
  that a NeoForge server sends *in addition to* vanilla packets (for menus: *instead
  of* `open_screen` when the menu has extra data, `ServerPlayer.java.patch` 215-240,
  and only if the client has the channel). The vanilla packets keep their encoding.
  `ItemStack` and `ItemStackTemplate` have no network changes (`ItemStack.java.patch`,
  `ItemStackTemplate.java.patch`: no codec lines).

## Behaviour that changes without a wire change

* **Elytra.** `LivingEntity.canGlide(boolean isNeoForgeConnection)`
  (`LivingEntity.java.patch` 672-685): on a NeoForge connection the client decides
  that the player may start gliding **only** from the attribute value
  `neoforge:gliding_flight > 0` (`NF/common/NeoForgeMod.java` 221, a boolean attribute,
  default 0); on other connections it looks at the worn items (`glider` component).
  `LocalPlayer.canGlide()` passes the connection type (`LocalPlayer.java.patch` 50-56).
  The NeoForge server gets the attribute from an item modifier it adds for items with
  the `glider` component and an `equippable` (`NeoForgeMod.java` 687-696,
  modifier id `neoforge:glider_component_flight`, `ADD_VALUE` 1.0, in the equippable's
  slot) and sends it with the player's attributes (`ClientboundUpdateAttributesPacket`,
  `neoforge:gliding_flight` is "syncable"). **A Pumpkin that does not send it cannot
  start a glide for a client flagged NeoForge**; this is not implemented. What it
  takes: send `update_attributes` for the player entity with the attribute's registry
  id (from the plugin's `minecraft:attribute` snapshot: `neoforge:gliding_flight` is
  one of NeoForge's own entries) with base value 0 and the modifier above while a
  glider is worn.
* **`RecipesReceivedEvent`**: a NeoForge connection is expected to get
  `neoforge:recipe_content` (before the recipes, `CommonHooks.sendRecipes` 1723-1729);
  for non-NeoForge connections the client fires the event itself with empty recipes
  (`ClientHooks.java` 654-660). A client mod that waits for the event never sees it
  on a NeoForge connection if the plugin does not send the payload (an empty
  `neoforge:recipe_content` is `VarInt 0` recipe types, `VarInt 0` recipes: set
  of registry ids then list).
* `neoforge:config_file`, data maps, `neoforge:sync_attachments` are only sent to
  NeoForge connections by the reference; clients without data to receive are fine
  without.

## How Pumpkin does it

Three parts: a hold before the brand, a per-connection flavour, and a flavour-aware
packet writer.

### The pre-brand hold (host)

`handle_login_acknowledged` now: state becomes Config, `ConfigurationPreBrandEvent`
fires, and if a (blocking) handler set `hold` the connection waits in
`HoldStage::ConfigurationPreBrand` until `server.release-configuration(id)`. Then the
brand goes out, `ConfigurationStartEvent` fires and the rest of the configuration
runs exactly as before. Without a handler for the new event nothing changes (brand,
start event, ...). While held, `send-configuration-payload` and
`send-configuration-packet` work, and the client's answers arrive as
`configuration-payload-event` and `configuration-packet-received-event`.

### The flavour (host)

`server.set-connection-flavour(connection-id, vanilla | neoforge)` stores the flavour
in the connection's plugin session (it takes effect at once), `end_plugin_session`
copies it to the pending connection, `JavaClient::from_pending` to
`JavaClient::flavour`. Default `vanilla`. It can be set until the configuration ended;
afterwards the call fails ("not logging in or configuring").

### The packet writer (host)

`pumpkin_protocol::ConnectionFlavour` (`crates/pumpkin-protocol/src/flavour.rs`) with
a scoped thread local:

* `JavaClient::serialize_packet` and `write_packet` run the serialization inside
  `flavour.scope(...)`; the world broadcasts (`World::broadcast_java_grouped`, which
  all `broadcast_*` and the entity tracker use) serialize once *per flavour* of the
  recipients (nearly always one).
* A packet that differs reads `ConnectionFlavour::current()` in its
  `ClientPacket::write_packet_data`. Today only `CParticle` does.

Why not a parameter: `write_packet_data` has hundreds of implementations and call
sites, and exactly one packet depends on the flavour. Serialization is synchronous
(no `.await` inside the scope), the previous value is restored when the scope ends
(also on panic), and code that does not set a scope writes the vanilla encoding, so
a forgotten call site degrades to vanilla instead of failing.

Paths that serialize with `serialize_packet_for_version` directly (entity data
packets built per version in `entity/mod.rs`, `world/mod.rs`, `entity_tracker.rs`)
and packets of the login/configuration phase (`PendingConnection::send_packet_now`)
always write vanilla; none of them contains a flavour dependent field today. If one
ever does, route it through `serialize_packet_for_flavour`.

`CParticle.data` stays in the vanilla encoding for every caller (plugins that build
the raw packet included); the writer appends the empty `opt<BlockPos>` for NeoForge
connections, so a plugin must **not** add it itself.

## Status of every item

| # | item | status |
| - | ---- | ------ |
| 1 | `BlockParticleOption`: `opt<BlockPos>` after the state id, `ClientboundLevelParticlesPacket` | implemented (`CParticle`, 26.3 layout) |
| 1b | same inside `ClientboundExplodePacket` block particles, entity data `particle(s)` | not applicable (Pumpkin writes no block particle options there) |
| 2 | recipe book settings, entries for modded recipe book types | implemented as "none" (correct for clients without extended `RecipeBookType`); `2 * n` bools for n modded types **not implemented** |
| 3 | `Ingredient` custom marker -1000 | not applicable (no custom ingredients) |
| 3 | `HolderSet` negative custom type ids | not applicable |
| 3 | `ItemAttributeModifiers` | same bytes for vanilla attributes, nothing to do |
| 3 | entity data serializer ids >= 256 | not applicable |
| 5 | serverbound `select_known_packs` limit 1024 | not needed (Pumpkin caps at 64, sends few packs) |
| 6 | `neoforge:gliding_flight` attribute so elytra work on a NeoForge connection | **not implemented**: needs the registry id of the attribute and `update_attributes`; layout above |
| 6 | `neoforge:recipe_content` before the recipes | not implemented (plugin payload; empty one is `00 00`) |

## Note for the Dart plugin: `NeoForgeNegotiation.full`

What the host now offers, in the order the connection runs:

1. **`Events.configurationPreBrand`** (WIT `configuration-pre-brand-event`, record
   `connection-id, uuid, username, protocol-version, hold, hold-timeout-seconds`).
   Intercept it like `configurationStart` and return the event with `hold: true` (and
   a `hold-timeout-seconds` that covers the whole exchange; the default is 30). Fired
   right after login was acknowledged, **before** `minecraft:brand`. If no plugin
   holds, the brand is sent and everything is as before.
2. In the held connection use `server.send-configuration-payload` /
   `send-configuration-packet` and wait for the answers on
   `configuration-payload-event` / `configuration-packet-received-event`. The
   sequence of a real NeoForge server (neoforge-protocol.md section A rows 1-8):
   * `minecraft:unregister`, `minecraft:register`, `neoforge:register` with an empty
     map (`00`), a ping (packet id 5, body `00 00 00 00`);
   * wait for the client's `neoforge:register` answer (a vanilla client never answers:
     time out after about 3 seconds and treat it as vanilla) and for the pong (packet
     id 5); the real server sends `neoforge:network` and the second
     `minecraft:register` after the answer;
   * for a client that answered: `server.set-connection-flavour(id, neoforge)`.
     Do it **before** releasing; it also has to be called only for clients that got
     and answered the query, a vanilla client must stay `vanilla` (its play phase
     would otherwise get the extra bytes it cannot read).
   * `server.release-configuration(id)`: the host sends the brand and the
     `configuration-start-event` fires, so the existing start handler (registry sync
     and so on) continues with a connection the client already classified as NeoForge.
3. On the Dart side, `NeoForgeNegotiation.full` is then: register an `onConfiguration`
   with a new `preBrand:` handler (or run steps 1-2 in the handler of a registration
   that asks for the pre-brand hold) and keep the existing `handler` for the start
   hold unchanged. One `ConfigurationConnection` per connection can carry over:
   `connection.id` is the same in both events.
4. What a flagged connection costs, and what the plugin should consider sending:
   `neoforge:gliding_flight` for elytra, `neoforge:recipe_content` (see above); the
   particles are handled by the host. If the plugin cannot do these, prefer
   `NeoForgeNegotiation.adhoc` (no query, flavour `vanilla`) for servers that need
   elytra.
5. `set-connection-flavour` fails with an error string when the connection is gone or
   already past the configuration, so call it from the pre-brand or start handler,
   never later.
