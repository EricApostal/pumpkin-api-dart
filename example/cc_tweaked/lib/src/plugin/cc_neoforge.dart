// CC: Tweaked's NeoForge declaration. The host runs the handshake (channel
// negotiation before the brand, the registry sync, `c:version`, `c:register`,
// config files); the plugin only describes what the mod has:
//
//   mod             computercraft, the version of the jar the players run
//   channels        the 16 required play payloads (`CcChannels`)
//   registries      the five host-numbered registries the plugin registers content
//                   in by name (`minecraft:block`, `minecraft:item`,
//                   `minecraft:block_entity_type`, `minecraft:menu`,
//                   `minecraft:data_component_type`) plus
//                   `computercraft:recipe_function`, the mod registry the host
//                   does not know (`ccDeclaredRegistries`). The host
//                   fills the host-numbered ones with the entries the plugin
//                   registered, in registration order.
//   config files    `computercraft-synced.toml`, empty: the client uses its defaults
//   datapack        the turtle and pocket upgrades, as network NBT, for the
//                   creative tab variants (`registry_data` of the clients)
//   policy          `allow`: vanilla clients still join
//
// See docs/neoforge-host.md of pumpkin_api.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../protocol/channels.dart';
import '../protocol/datapack_registries.dart';
import '../protocol/registries.dart';
import 'cc_declared_registries.dart';

/// The mod version to declare when no jar is found: the version CC's channels
/// were taken from.
const String fallbackModVersion = '1.120.3';

/// The declaration for the mod at [modVersion] (null: [fallbackModVersion]).
NeoForgeDeclaration ccNeoForgeDeclaration(CcDatapackRegistries datapack, {String? modVersion}) {
  final version = modVersion ?? fallbackModVersion;
  return NeoForgeDeclaration(
    mod: NeoForgeMod(id: CcRegistries.modId, version: version, displayName: 'CC: Tweaked'),
    channels: CcChannels.declared(version),
    registries: ccDeclaredRegistries(),
    configFiles: const [NeoForgeConfigFile(CcRegistries.syncedConfigFile)],
    datapackEntries: datapack.toDeclared(),
    policy: NonNeoForgeClientPolicy.allow,
  );
}
