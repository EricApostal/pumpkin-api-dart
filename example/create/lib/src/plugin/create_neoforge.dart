// The NeoForge declaration of a mod, built from a registry. The host numbers
// what plugins register through the registry interfaces (items, blocks, block
// entity types, menus, data components, fluids, entity types, sounds, particles,
// plugin synced registries, datapack entries); the declaration carries the mod,
// its payload channels and the *vouch* for the registries whose content is
// verified.
//
// The function is generic over the mod: Create calls it with `createModId`, and
// an addon calls it with its own mod id through `createAddonNeoForgeDeclaration`
// (`create_addon.dart`). No mod's channels are named here.
//
// See docs/neoforge-host.md of pumpkin_api.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/registry.dart';

const String createModId = 'create';

/// The declaration of [mod] from everything [registry] holds: the channels with
/// handlers and the declared-only ones, in registration order, plus the config
/// files and data maps.
///
/// The host merges this with every other plugin's declaration, so [mod] may be
/// any mod that builds on Create — the addons' own mods included.
///
/// [contentVerified] is the claim the host cannot check: that every block, item,
/// block entity type, ... [registry] holds is *the client's*, name by name, in
/// this order. When it is true, the declaration names the registries the content
/// went into (`minecraft:block`, `minecraft:item`, ...) and the host sends them
/// to `NeoForge` clients; when false, the declaration announces the channels
/// only and the content stays server-side. A `NeoForge` client that receives a
/// registry entry it does not have disconnects with "The server sent registries
/// with unknown keys", which is why the default for an addon is false (see
/// `CreateAddon.contentVerified`) and Create itself passes true.
NeoForgeDeclaration createNeoForgeDeclaration(
  CreateRegistry registry, {
  required NeoForgeMod mod,
  bool contentVerified = true,
}) {
  return NeoForgeDeclaration(
    mod: mod,
    channels: [
      for (final p in registry.payloads.declared)
        NeoForgeChannel(
          id: p.id,
          version: p.version,
          flow: p.serverbound ? ChannelFlow.serverbound : ChannelFlow.clientbound,
          optional: p.optional,
        ),
    ],
    registries: contentVerified ? contentRegistries(registry) : const [],
    configFiles: registry.neoForgeConfigFiles,
    dataMaps: registry.dataMaps,
    policy: NonNeoForgeClientPolicy.allow,
  );
}

/// The registries [registry] put content in, as the declaration's vouch for them.
///
/// Naming one of these is what makes the host send the mod's entries in it; the
/// entries themselves are the host's (its dynamic registry, in registration
/// order), so the list is empty. A registry [registry] registered nothing in is
/// not named: sending it would replace the client's own entries with the host's
/// partial list for no gain.
///
/// `create:*` registries the host does not number (`create:fan_processing_type`)
/// are named too — their key only exists on the client because the mod creates
/// it, so the declaration has to say that it does.
List<NeoForgeRegistryAddition> contentRegistries(CreateRegistry registry) {
  final registries = <NeoForgeRegistryAddition>[];
  void add(String key, int count) {
    if (count > 0) registries.add(NeoForgeRegistryAddition(key, const []));
  }

  add('minecraft:block', registry.blocks.length);
  add('minecraft:item', registry.items.length);
  add('minecraft:block_entity_type', registry.blockEntityTypes.length);
  add('minecraft:menu', registry.menus.length);
  add('minecraft:data_component_type', registry.dataComponents.length);
  add('minecraft:fluid', registry.fluids.length);
  add('minecraft:entity_type', registry.entityTypes.length);
  add('minecraft:sound_event', registry.sounds.length);
  add('minecraft:particle_type', registry.particles.length);
  add('minecraft:mob_effect', registry.mobEffects.length);
  // The recipe types are synced separately (`declareSyncedRecipeTypes`), but the
  // two registries they add entries to are gated like every other one.
  final syncedRecipes = registry.recipeTypes.entries.where((e) => e.value).length;
  add('minecraft:recipe_type', syncedRecipes);
  add('minecraft:recipe_serializer', syncedRecipes);
  for (final spec in registry.syncedRegistries.entries) {
    add(spec.value.key, spec.value.entries.length);
  }
  return registries;
}
