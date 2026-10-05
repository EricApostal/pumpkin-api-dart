// Everything CC: Tweaked adds to the registries, in registration order, and
// the NeoForge server spec built from it.
//
// Source: `shared/ModRegistry.java` (mc-26.3). A real NeoForge server numbers
// modded entries after all vanilla ones, in registration order within each
// registry (the textual order of the `register(...)` calls), and that is the
// order the lists below are in. The client takes these ids from the
// `neoforge:frozen_registry` payloads, so the host must put exactly these ids
// on the wire for CC's blocks, items and menus.
import 'dart:typed_data';

import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart';

import 'channels.dart';

abstract final class CcRegistries {
  static const String modId = 'computercraft';

  /// The file name of the mod's synced server config.
  static const String syncedConfigFile = 'computercraft-synced.toml';

  static List<String> _ids(List<String> names) => [for (final n in names) '$modId:$n'];

  /// `minecraft:block`: 16 blocks.
  static final List<String> blocks = _ids([
    'computer_normal',
    'computer_advanced',
    'computer_command',
    'turtle_normal',
    'turtle_advanced',
    'speaker',
    'disk_drive',
    'printer',
    'monitor_normal',
    'monitor_advanced',
    'wireless_modem_normal',
    'wireless_modem_advanced',
    'wired_modem_full',
    'cable',
    'lectern',
    'redstone_relay',
  ]);

  /// `minecraft:item`: 23 items (the block items, pocket computers, disks,
  /// printouts and the two cable items).
  static final List<String> items = _ids([
    'computer_normal',
    'computer_advanced',
    'computer_command',
    'pocket_computer_normal',
    'pocket_computer_advanced',
    'turtle_normal',
    'turtle_advanced',
    'disk',
    'treasure_disk',
    'printed_page',
    'printed_pages',
    'printed_book',
    'speaker',
    'disk_drive',
    'printer',
    'monitor_normal',
    'monitor_advanced',
    'wireless_modem_normal',
    'wireless_modem_advanced',
    'wired_modem_full',
    'redstone_relay',
    'cable',
    'wired_modem',
  ]);

  /// `minecraft:block_entity_type`: one per block (named like the block).
  static final List<String> blockEntityTypes = _ids([
    'monitor_normal',
    'monitor_advanced',
    'computer_normal',
    'computer_advanced',
    'computer_command',
    'turtle_normal',
    'turtle_advanced',
    'speaker',
    'disk_drive',
    'printer',
    'wired_modem_full',
    'cable',
    'wireless_modem_normal',
    'wireless_modem_advanced',
    'lectern',
    'redstone_relay',
  ]);

  /// `minecraft:data_component_type`.
  static final List<String> dataComponentTypes = _ids([
    'computer_id',
    'storage_capacity',
    'terminal_size',
    'left_turtle_upgrade',
    'right_turtle_upgrade',
    'fuel',
    'overlay',
    'top_pocket_upgrade',
    'back_pocket_upgrade',
    'computer',
    'on',
    'treasure_disk',
    'disk_id',
    'printout',
  ]);

  /// `minecraft:menu`.
  static final List<String> menus = _ids([
    'computer',
    'pocket_computer_no_term',
    'pocket_computer_lectern',
    'turtle',
    'disk_drive',
    'printer',
    'printout',
  ]);

  /// `minecraft:recipe_serializer`.
  static final List<String> recipeSerializers = _ids([
    'impostor_shaped',
    'impostor_shapeless',
    'transform_shaped',
    'transform_shapeless',
    'colour',
    'clear_colour',
    'turtle_upgrade',
    'pocket_computer_upgrade',
    'printout',
    'disk',
  ]);

  /// `minecraft:command_argument_type`.
  static final List<String> commandArgumentTypes = _ids([
    'tracking_field',
    'computer',
    'repeat',
  ]);

  /// `computercraft:recipe_function`, a mod registry created with
  /// `sync(true)`.
  static final List<String> recipeFunctions = _ids(['copy_components']);

  /// The entries of the datapack registries `computercraft:turtle_upgrade`
  /// and `computercraft:pocket_upgrade`. They are not part of the
  /// `neoforge:frozen_registry` sync: the client receives them as ordinary
  /// `minecraft:registry_data` during configuration (with network codecs
  /// registered through `NewDatapackRegistryEvent`).
  static const List<String> turtleUpgrades = [
    'computercraft:speaker',
    'computercraft:wireless_modem_advanced',
    'computercraft:wireless_modem_normal',
    'minecraft:crafting_table',
    'minecraft:diamond_axe',
    'minecraft:diamond_hoe',
    'minecraft:diamond_pickaxe',
    'minecraft:diamond_shovel',
    'minecraft:diamond_sword',
  ];

  static const List<String> pocketUpgrades = [
    'computercraft:speaker',
    'computercraft:wireless_modem_advanced',
    'computercraft:wireless_modem_normal',
  ];

  /// The additions per registry key, all of them (what the client has).
  static Map<String, List<String>> get additions => {
    'minecraft:block': blocks,
    'minecraft:item': items,
    'minecraft:block_entity_type': blockEntityTypes,
    'minecraft:data_component_type': dataComponentTypes,
    'minecraft:menu': menus,
    'minecraft:recipe_serializer': recipeSerializers,
    'minecraft:command_argument_type': commandArgumentTypes,
  };

  /// The registries the plugin *synchronises*: [additions] without the ones
  /// that have no vanilla list.
  ///
  /// The sync has to be complete for a registry it contains (all vanilla entries
  /// in their ids, then the mod's), and there is no list of the vanilla
  /// `recipe_serializer` or `command_argument_type` entries: Pumpkin's assets
  /// have neither (`assets/*.json`; only the ids of the argument types it
  /// writes in its command tree are in the Rust source, and the recipe
  /// serializers are not anywhere). They are left out, which is safe: a
  /// registry that is not synchronised keeps the client's own numbering
  /// (vanilla first, then the mod's entries in registration order, which is
  /// the numbering of the lists above), and the host never writes an id of
  /// either registry for a modded entry (no CC recipe or command argument
  /// reaches the wire from the host). Add them here once the lists exist and
  /// the host writes such ids.
  static Map<String, List<String>> get synchronised => {
    for (final entry in additions.entries)
      if (VanillaRegistries.entries(entry.key) != null) entry.key: entry.value,
  };

  /// The NeoForge server description that makes a CC: Tweaked client accept
  /// this server and number the mod's entries: the synchronised registries
  /// plus the play channels, all required with [modVersion] (the version of
  /// the jar the players run).
  static NeoForgeServerSpec serverSpec(String modVersion) {
    final spec = NeoForgeServerSpec.vanillaPlus(
      mods: [
        NeoForgeModInfo(
          id: modId,
          version: modVersion,
          displayName: 'CC: Tweaked',
        ),
      ],
      additions: synchronised,
    );
    return NeoForgeServerSpec(
      mods: spec.mods,
      registries: [
        ...spec.registries,
        RegistrySpec('$modId:recipe_function', recipeFunctions),
      ],
      channels: CcChannels.specs(modVersion),
      // The mod's synced config (`computercraft-synced.toml`, see
      // docs/client-compat.md); empty: the client uses its defaults.
      configFiles: {CcRegistries.syncedConfigFile: Uint8List(0)},
    );
  }
}

/// Numeric ids of CC's entries, as the registry sync defines them: the number
/// of vanilla entries plus the position in the mod's list.
final class CcRegistryIds {
  final Map<String, int> _firstModdedId = {};

  CcRegistryIds() {
    for (final key in CcRegistries.additions.keys) {
      // Registries without a generated vanilla list (recipe serializers,
      // command argument types) have no known first id: asking for one of
      // their ids fails in [idOf], but loading the plugin must not.
      final vanilla = VanillaRegistries.entries(key);
      if (vanilla != null) _firstModdedId[key] = vanilla.length;
    }
  }

  /// The id of `computercraft:[name]` in the registry [registry].
  int idOf(String registry, String name) {
    final list = CcRegistries.additions[registry];
    if (list == null) throw ArgumentError.value(registry, 'registry', 'not synchronised');
    final index = list.indexOf('${CcRegistries.modId}:$name');
    if (index < 0) throw ArgumentError.value(name, 'name', 'not in $registry');
    final first = _firstModdedId[registry];
    if (first == null) {
      throw StateError('The vanilla entries of $registry are not known, so the id of $name is not either.');
    }
    return first + index;
  }
}
