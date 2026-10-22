# The host-owned NeoForge handshake

The host (`neoforge.wit`, Pumpkin `wip/create-host-features`) now runs the
NeoForge client handshake itself. A plugin that adds content NeoForge clients
must know about does not talk the protocol any more: it **declares** what its
mod has, and the host merges the declarations of all plugins into one handshake
for every connecting client.

What the host does with the declarations:

* the channel negotiation before the server brand (`neoforge:register` query,
  `neoforge:network`, `c:version`, `c:register`),
* the registry synchronisation: the vanilla entries, then the entries plugin
  registered through the registry interfaces (items, blocks, block entity types,
  menus, data components, fluids, entity types ...) in registration order. Only
  entries a declaration **vouches** for are sent: a declaration names the
  registries it vouches for, and declaring a mod alone vouches for none of its
  content. Entries of a plugin that named no registry stay on the server (see
  *Vouching* below),
* the config files (`neoforge:config_file`), the data map and feature flag
  checks, and the declared datapack registry entries in the registry data the
  NeoForge clients get,
* the policy for clients that do not answer the NeoForge query (vanilla,
  Fabric): if any plugin declares `reject` they are disconnected, otherwise they
  join without the NeoForge exchange. A server where no plugin declares anything
  sees no change.

The protocol itself is described in [neoforge-protocol.md](neoforge-protocol.md).

## When a plugin needs it

* The plugin adds blocks, items, menus, entity types ... that a **client mod**
  also has (a port of a NeoForge mod such as CC: Tweaked or Create): declare the
  mod, its channels and the registries the host does not know, so the client
  accepts the server and takes the server's ids for the entries.
* The plugin only works with vanilla clients (commands, events, plugin menus):
  nothing to do. Do not declare.
* A plugin that wants to detect NeoForge players: `player.isNeoForge`
  (or `context.isNeoForgePlayer(uuid)`), no declaration needed.

## Vouching: which registries are sent

A NeoForge client rebuilds a registry from the snapshot and **disconnects** on a
key it does not have (`The server sent registries with unknown keys: …`). Nothing
in the server can know what the client's copy of a mod has, so the server only
sends what a plugin said it verified — and *what it verified* is per registry,
not per plugin:

* **Declaring a mod vouches for nothing but its channels.** A declaration
  announces the mod, its payload channels and its config files; a client that has
  the mod then negotiates the channels and joins. The blocks, items and other
  entries the plugin registered stay on the server.
* **Naming a registry in `registries` is the content claim.** For a registry the
  host numbers — `minecraft:block`, `minecraft:item`,
  `minecraft:block_entity_type`, `minecraft:menu`, `minecraft:data_component_type`,
  `minecraft:fluid`, `minecraft:entity_type`, `minecraft:sound_event`,
  `minecraft:particle_type`, `minecraft:mob_effect`, `minecraft:map_decoration_type`,
  `minecraft:recipe_type`, `minecraft:recipe_serializer`,
  `neoforge:entity_data_serializers` — the entries sent are the **host's**
  dynamic-registry list (vanilla, then everything the plugin registered through
  the registry interfaces, in registration order). `NeoForgeRegistryAddition.entries`
  is ignored for those: a declaration can neither add an entry the plugin did not
  register nor leave one out. Naming the registry says "the names I registered in
  it are the client's, in this order".
* **A registry a mod owns** (`computercraft:recipe_function`,
  `create:fan_processing_type`) is a key the client only has because that mod
  creates it; it is sent only when a declaration names it, and then the host's
  registry for it is sent whole.
* **Ids are positions.** If entries of a mod that named nothing come before
  entries that did, the registry is left out entirely rather than renumbering the
  later ones on the client (a warning names the registry).
* **A second plugin shifts the ids, and that is fine.** The snapshot is the
  vanilla entries followed by *every* plugin's entries in load order, so the
  entries of a plugin that loaded later do not start at `vanilla count`: they
  start after the entries of the plugins before it. The client does not number
  anything itself — `RegistryManager.applySnapshot` puts each entry at the id the
  snapshot gives it (`registerIdMapping`) — so the ids still match. What the
  client does with them is described in
  [neoforge-protocol.md](neoforge-protocol.md#neoforge-263-network-negotiation-and-registry-synchronisation).
  The order is a function of the plugin set alone (names and declared
  dependencies, `PluginManager::topological_sort`), so a restart gives the same
  ids; a plugin must not rely on being first, and a check that fails because
  another plugin registered first is checking something the protocol does not
  require.

An incremental port therefore does not need an allowlist and cannot brick a
connection by registering a name the client lacks: it declares its mod (channels
only) while it is being ported, and names the registries once their content
matches the client's release name by name. `example/create` passes
`contentVerified: true` (its registry is verified) and names the registries it
fills; an addon gets `CreateAddon.contentVerified`, which defaults to `false`, so
a new addon announces its channels and nothing else until its author says the
content is verified. `example/cc_tweaked` names `computercraft:recipe_function`.

The host re-checks the one thing it can: an entry is sent only if a declaration
vouches for its namespace in that registry, and a registry whose sent entries are
not a prefix of the registered ones is dropped whole (`registries::syncable` in
`crates/pumpkin-core/src/net/neoforge/registries.rs`). The recipe type and
serializer extras go through the same gate.

Several plugins may declare at once. Before this, only one plugin per server could
run the Dart handshake (`packages/pumpkin_neoforge`), so two NeoForge mods needed
one plugin owning both specs; with the host handshake each plugin declares its own
mod. `packages/pumpkin_neoforge` stays in the repository for plugins that still run
the handshake in Dart (`example/lonsdaleite`, `example/modbridge`); a server must
not run both ways at once.

## Synced config files: declare them, or the client crashes

A NeoForge server sends **every** `SYNCED` config of every installed mod
(`ConfigSync.syncAllConfigs`, `ConfigFilePayload`); a Java server has no opt-out.
The client parses each body into that mod's `ModConfigSpec` and *replaces* its
config with it. Until the body arrives the spec is not loaded, and every
`ConfigValue.get()` of it throws
`IllegalStateException: Cannot get config value before config is loaded`
(`ModConfigSpec.ConfigValue.getRaw`).

That is not a server-side detail. A mod's synced config is read on the **client**,
and some of those reads happen in code no client author expects to be fatal:
Create's item tooltip asks `BlockStressValues.getImpact(block)`, which calls the
provider each addon registered, which is `CStress.getImpact` — a supplier over a
`ConfigValue` of the addon's synced config. Hovering one of that addon's kinetic
blocks in the creative inventory then throws on the render thread and the game
crashes. `create-server.toml` was declared from the start, so Create's own blocks
were fine; Simulated, Aeronautics, Offroad and Sable were not, and hovering their
blocks crashed the client against Pumpkin but not against a Java server.

So: **a plugin that ports a mod with a `SYNCED` config must declare that file**
with the same name FML gives it (`<modid>-synced.toml`, or the explicit name the
mod passes to `registerConfig`), and the body must use the mod's own config paths
— not the plugin's JSON layout. A path that is left out falls back to the client's
default for that spec (`ConfigValue.getRaw` → `Config.getOrElse`), so a partial
body is safe and an empty one is legal. `SyncedToml`
(`package:create/src/infrastructure/config/synced_toml.dart`) writes the body in
`ModConfigSpec`'s layout; `example/simulated`, `example/aeronautics`,
`example/offroad` and `example/sable` each render their own file that way, and
`example/cc_tweaked` declares an empty one.

## Usage

Needs `Permissions.neoforge` in `PluginInfo.permissions`. Declare in
`Plugin.onLoad` (players cannot connect yet); a second call replaces the
declaration, `withdrawNeoForge()` removes it. A refused declaration throws a
`HostException` (invalid identifier or channel, duplicate entries, missing
permission, players can connect already).

```dart
@override
void onLoad(Context context) {
  context.declareNeoForge(
    NeoForgeDeclaration(
      mod: NeoForgeMod(id: 'mymod', version: '1.2.0', displayName: 'My Mod'),
      channels: [
        NeoForgeChannel.clientbound('mymod:sync', '1'),
        NeoForgeChannel.serverbound('mymod:action', '1'),
        NeoForgeChannel(id: 'mymod:both', version: '1', optional: true),
      ],
      // The content claim: name a registry only when every entry you registered
      // in it matches the client's mod. The host numbers the entries itself, so
      // the list is empty for a registry it numbers; a mod's own registry is
      // sent whole (add the entries the host does not know, if any).
      registries: [
        NeoForgeRegistryAddition('minecraft:block', const []),
        NeoForgeRegistryAddition('minecraft:item', const []),
        NeoForgeRegistryAddition('mymod:recipe_function', ['mymod:copy']),
      ],
      configFiles: [NeoForgeConfigFile('mymod-server.toml', tomlBytes)],
      datapackEntries: [NeoForgeDatapackEntry('mymod:upgrade', 'mymod:speaker', nbtBytes)],
      dataMaps: [NeoForgeDataMap('minecraft:item', 'neoforge:fuel')],
      featureFlags: ['mymod:experimental'],
      policy: NonNeoForgeClientPolicy.allow, // or .reject
      rejectMessage: 'This server needs: {mods}',
    ),
  );
}
```

Later changes: `context.declareSyncedRecipeTypes([...])` (recipe types for
`neoforge:recipe_content`, see [recipes-and-tags.md](recipes-and-tags.md)) and
`context.updateNeoForgeConfigFile(modId, fileName, bytes)`, which replaces a synced
config file of the declared mod and sends it to connected NeoForge players at once
(players that join later get it with the handshake). Both throw `HostException`.

| Type | WIT | Notes |
| ---- | --- | ----- |
| `NeoForgeDeclaration` | `declaration` | `policy` defaults to `allow` |
| `NeoForgeMod` | `mod-info` | NeoForge has no mod list; the name appears in messages and on the mismatch screen |
| `NeoForgeChannel` | `network-channel` | `.serverbound` / `.clientbound` are play-phase shortcuts; `phases`, `flow` (`ChannelFlow`), `optional` otherwise |
| `NeoForgeRegistryAddition` | `synced-registry` | names a registry the mod owns and lists its entries in id order; a voucher, not an addition to a host-numbered registry |
| `NeoForgeConfigFile` | `config-file` | |
| `NeoForgeDatapackEntry` | `datapack-entry` | network NBT as a nameless compound; `null` data when the client has the entry |
| `NeoForgeDataMap` | `data-map` | `mandatory`: refuse a client without it |
| `NonNeoForgeClientPolicy` | `non-neoforge-policy` | |

The raw WIT records (`Declaration`, `ModInfo`, ...) are hidden from the
`pumpkin_api` barrel because the names are generic; the wrappers convert with
`NeoForgeDeclaration.toWire()`.

## Example

`example/cc_tweaked` (`lib/src/plugin/cc_neoforge.dart`): mod `computercraft`,
its 16 required play channels, the `computercraft:recipe_function` registry, the
empty `computercraft-synced.toml`, and the turtle and pocket upgrade entries as
datapack entries. Its config switch `"neoforge": true` now means "declare to the
host".
