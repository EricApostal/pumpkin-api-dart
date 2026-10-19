// The NeoForge declaration of the mod, built from the registry content. The host
// numbers what plugins register through the registry interfaces (items, blocks,
// block entity types, menus, data components, fluids, entity types, sounds,
// particles, plugin synced registries, datapack entries); the declaration only
// carries the mod, its payload channels and what the host does not know.
// See docs/neoforge-host.md of pumpkin_api.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/registry.dart';

const String createModId = 'create';

/// The declaration for the mod at [modVersion] (`mod_version` of Create's
/// gradle.properties; it is the version string of the channels).
NeoForgeDeclaration createNeoForgeDeclaration(CreateRegistry registry, {required String modVersion}) {
  return NeoForgeDeclaration(
    mod: NeoForgeMod(id: createModId, version: modVersion, displayName: 'Create'),
    channels: [
      for (final p in registry.payloads.declared)
        NeoForgeChannel(
          id: p.id,
          version: p.version,
          flow: p.serverbound ? ChannelFlow.serverbound : ChannelFlow.clientbound,
          optional: p.optional,
        ),
    ],
    configFiles: registry.neoForgeConfigFiles,
    dataMaps: registry.dataMaps,
    policy: NonNeoForgeClientPolicy.allow,
  );
}
