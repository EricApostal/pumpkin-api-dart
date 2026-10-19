import 'package:dart_mappable/dart_mappable.dart';

part 'datapack_settings.mapper.dart';

/// The `datapack` section of `config.json`. The switches name the embedded
/// categories (see `tool/package_datapack.dart`).
@MappableClass()
class DatapackSettings with DatapackSettingsMappable {
  /// Master switch: write the pack and enable it.
  final bool enabled;

  /// Enable the pack through the host when it is available but disabled, and
  /// reload the datapacks after the files changed.
  final bool autoEnable;

  /// Create's recipes (`data/create/recipe`, all types; the host ignores types it
  /// cannot parse).
  final bool recipes;
  final bool lootTables;

  /// The advancement tree (`create:*` advancements, without the recipe unlocks).
  final bool advancements;

  /// The recipe book unlock advancements (about a thousand files; off by default).
  final bool recipeAdvancements;

  /// Block, item, fluid, entity type, ... tags of the `create`, `c` and
  /// `minecraft` namespaces.
  final bool tags;

  /// Structure templates (`data/create/structure`).
  final bool structures;

  /// Damage types, enchantments, worldgen, data maps. Off by default: the plugin
  /// registers damage types and enchantments itself, and a second definition can
  /// shift the registry ids the NeoForge client expects.
  final bool registries;

  /// Anything else in the data directories (currently nothing).
  final bool other;

  const DatapackSettings({
    this.enabled = true,
    this.autoEnable = true,
    this.recipes = true,
    this.lootTables = true,
    this.advancements = true,
    this.recipeAdvancements = false,
    this.tags = true,
    this.structures = true,
    this.registries = false,
    this.other = false,
  });

  /// The categories that are switched on (names as in the embedded blobs).
  Set<String> get categories => {
    if (recipes) 'recipes',
    if (lootTables) 'loot_tables',
    if (advancements) 'advancements',
    if (recipeAdvancements) 'recipe_advancements',
    if (tags) 'tags',
    if (structures) 'structures',
    if (registries) 'registries',
    if (other) 'other',
  };
}
