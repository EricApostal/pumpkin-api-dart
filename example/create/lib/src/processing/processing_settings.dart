// The `processing` section of config.json.
import 'package:dart_mappable/dart_mappable.dart';

part 'processing_settings.mapper.dart';

@MappableClass()
class ProcessingSettings with ProcessingSettingsMappable {
  /// Read Create's recipes (`create:*` types) from the embedded data pack.
  final bool loadEmbeddedRecipes;

  /// Also read recipes from `<plugin data>/<recipeFolder>/**.json` (a server owner's own
  /// `create:crushing`, `create:mixing`, ... recipes).
  final bool loadFolderRecipes;
  final String recipeFolder;

  /// Hand the recipes to the host recipe manager and sync them to Create clients
  /// (`neoforge:recipe_content`). Machines work without it; clients need it for their
  /// recipe viewers.
  final bool syncRecipes;

  /// Number of vanilla entries of the `recipe_serializer` registry; the serializer ids of the
  /// Create recipe types follow them (needed for the network form of sequenced assemblies).
  final int vanillaRecipeSerializerCount;

  /// Number of vanilla fluids (`empty`, `flowing_water`, `water`, `flowing_lava`, `lava`).
  final int vanillaFluidCount;

  /// Log every recipe that failed to load.
  final bool logInvalidRecipes;

  const ProcessingSettings({
    this.loadEmbeddedRecipes = true,
    this.loadFolderRecipes = true,
    this.recipeFolder = 'recipes',
    this.syncRecipes = true,
    this.vanillaRecipeSerializerCount = 22,
    this.vanillaFluidCount = 5,
    this.logInvalidRecipes = true,
  });
}
