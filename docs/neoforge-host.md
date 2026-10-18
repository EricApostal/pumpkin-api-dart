# The host-owned NeoForge handshake

The host (`neoforge.wit`, Pumpkin `wip/create-host-features`) now runs the
NeoForge client handshake itself. A plugin that adds content NeoForge clients
must know about does not talk the protocol any more: it **declares** what its
mod has, and the host merges the declarations of all plugins into one handshake
for every connecting client.

What the host does with the declarations:

* the channel negotiation before the server brand (`neoforge:register` query,
  `neoforge:network`, `c:version`, `c:register`),
* the registry synchronisation: the vanilla entries, then everything plugins
  registered through the registry interfaces (items, blocks, block entity types,
  menus, data components, fluids, entity types ...) in registration order, then
  the `registries` of the declarations,
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
  accepts the server and numbers the entries the same way.
* The plugin only works with vanilla clients (commands, events, plugin menus):
  nothing to do. Do not declare.
* A plugin that wants to detect NeoForge players: `player.isNeoForge`
  (or `context.isNeoForgePlayer(uuid)`), no declaration needed.

Several plugins may declare at once. Before this, only one plugin per server could
run the Dart handshake (`packages/pumpkin_neoforge`), so two NeoForge mods needed
one plugin owning both specs; with the host handshake each plugin declares its own
mod. `packages/pumpkin_neoforge` stays in the repository for plugins that still run
the handshake in Dart (`example/lonsdaleite`, `example/modbridge`); a server must
not run both ways at once.

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
      // Only what the host does not know; the entries you registered through
      // ItemRegistries.host, BlockRegistries.host ... are numbered by the host.
      registries: [NeoForgeRegistryAddition('mymod:recipe_function', ['mymod:copy'])],
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
| `NeoForgeRegistryAddition` | `synced-registry` | entries after the host's own; for a registry the host does not know, the whole registry in id order |
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
