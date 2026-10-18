import 'bindings.g.dart';
import 'host_result.dart';
import 'recipes.dart' show Ingredients;

/// Builds a recipe of a plugin defined recipe type (`recipe.wit`), for machines
/// like presses and mixers. The recipes are plugin side data: they are not sent
/// to clients and are never removed.
///
/// ```dart
/// final manager = server.getRecipeManager();
/// manager.defineRecipeType('my_plugin:pressing');
/// (CustomRecipeBuilder('my_plugin:iron_sheet')
///   ..ingredient('iron_ingot')
///   ..result('my_plugin:iron_sheet', count: 2))
///     .register(manager, 'my_plugin:pressing');
/// ```
final class CustomRecipeBuilder {
  /// Unique `namespace:path` id, not in the `minecraft` namespace.
  final String id;

  final List<SizedIngredient> _ingredients = [];
  final List<RecipeOutput> _results = [];
  final List<RecipeFluid> _fluidIngredients = [];
  final List<RecipeFluid> _fluidResults = [];

  /// Whatever else the machine needs, at most 64 KiB. The server never reads it.
  List<int> extra = const [];

  /// The recipe's encoding for NeoForge clients: the bytes of the recipe
  /// serializer's stream codec (everything after the serializer id), at most
  /// 32 KiB. Sent as they are in `neoforge:recipe_content` when the type is
  /// declared with `Context.declareSyncedRecipeTypes`. Without data a recipe is
  /// not synced.
  List<int>? networkData;

  CustomRecipeBuilder(this.id);

  /// Adds an ingredient: an item id, `#tag`, a list of ids, or an `Ingredient`
  /// (see [Ingredients.from]), needed [count] times.
  void ingredient(Object ingredient, {int count = 1}) => _ingredients.add(
    SizedIngredient(ingredient: Ingredients.from(ingredient), count: count),
  );

  /// Adds an output item that is produced with probability [chance].
  void result(String item, {int count = 1, double chance = 1.0}) => _results.add(
    RecipeOutput(item: item.contains(':') ? item : 'minecraft:$item', count: count, chance: chance),
  );

  /// Adds a fluid ingredient in millibuckets (`#namespace:path` for a tag).
  void fluidIngredient(String fluid, int amount) =>
      _fluidIngredients.add(RecipeFluid(fluid: fluid, amount: amount));

  /// Adds a fluid output in millibuckets.
  void fluidResult(String fluid, int amount) =>
      _fluidResults.add(RecipeFluid(fluid: fluid, amount: amount));

  CustomRecipe build() => CustomRecipe(
    id: id,
    ingredients: _ingredients,
    results: _results,
    fluidIngredients: _fluidIngredients,
    fluidResults: _fluidResults,
    extra: extra,
  );

  /// Registers the recipe for [recipeType]. Throws a [HostException] on failure
  /// (needs `registry.recipes`).
  void register(RecipeManager manager, String recipeType) =>
      manager.addCustomRecipe(recipeType, build(), networkData: networkData);
}

/// Recipe types, plugin recipes and recipe queries.
extension RecipeQueries on RecipeManager {
  /// Registers a recipe type key (`namespace:path`, not `minecraft`). Throws a
  /// [HostException] on failure.
  void defineRecipeType(String key) =>
      unwrapHost(registerRecipeType(key: key), 'Registering the recipe type $key');

  /// Registers [recipe] for [recipeType].
  ///
  /// With [networkData] the recipe is also synced to NeoForge clients, see
  /// `CustomRecipeBuilder.networkData`.
  void addCustomRecipe(String recipeType, CustomRecipe recipe, {List<int>? networkData}) =>
      unwrapHost(
        networkData == null
            ? registerCustomRecipe(recipeType: recipeType, recipe: recipe)
            : registerCustomRecipeWithNetworkData(
                recipeType: recipeType,
                recipe: recipe,
                networkData: networkData,
              ),
        'Registering the recipe ${recipe.id}',
      );

  /// The crafting recipe a grid matches, or `null`. [rows] holds the item key
  /// of each cell (`null` for empty), row by row; all rows have the same length.
  CraftingResult? matchCrafting(List<List<String?>> rows) {
    if (rows.isEmpty) return null;
    final width = rows.first.length;
    if (rows.any((r) => r.length != width)) {
      throw ArgumentError.value(rows, 'rows', 'All rows need the same length');
    }
    return findCraftingRecipe(
      width: width,
      height: rows.length,
      grid: [for (final r in rows) ...r],
    );
  }

  /// The recipe that cooks [item] in the station [type], or `null`.
  CookingResult? matchCooking(String item, CookingType type) =>
      findSmeltingRecipe(item: item, stationType: type);
}
