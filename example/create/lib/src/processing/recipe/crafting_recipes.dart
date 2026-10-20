// The vanilla crafting recipes the basin machines also run: the 2x2 / 3x3 single-ingredient
// shaped recipes of the press and the shapeless ones of the mixer
// (`MechanicalPressBlockEntity.matchStaticFilters` / `MechanicalMixerBlockEntity
// .matchStaticFilters`). Pure: the entries are loaded from the host's recipe manager by the
// processing module (`RecipeManager.findRecipes`), like the fan's cooking recipes.
import '../common/stack.dart';
import '../deployer/deployer_items.dart' show craftingRemainderOf;
import 'ingredient.dart';

/// A vanilla crafting recipe (`ShapedRecipe` / `ShapelessRecipe`) as the basin sees it.
final class CraftingRecipeEntry {
  /// `namespace:path`. Vanilla crafting recipes have no id in the host's tables
  /// (`RecipeManager.findRecipes` returns a `null` id), so the loader makes one up from the
  /// recipe type and the position in the table.
  final String id;

  /// Whether the recipe is shaped (`ShapedRecipe`): the mixer takes only the shapeless ones.
  final bool shaped;

  /// `recipe.placementInfo().ingredients()`: one entry per filled cell of the pattern (shaped)
  /// or per listed ingredient (shapeless) — empty cells are not in the list. `BasinRecipe.apply`
  /// consumes one item per entry.
  final List<Ingredient> ingredients;

  /// `recipe.getResultItem` (`assemble(CraftingInput.EMPTY)`).
  final PStack result;

  const CraftingRecipeEntry({
    required this.id,
    required this.shaped,
    required this.ingredients,
    required this.result,
  });

  /// The shape half of `MechanicalPressBlockEntity.canCompress`: 4 or 9 placement ingredients
  /// that are all the same ingredient, i.e. a full 2x2 or 3x3 square. The config half
  /// (`recipes.allowShapedSquareInPress`) is applied by the caller, because `canCompress` is also
  /// consulted by the mixer, where the config changes the answer.
  bool get isCompressibleSquare =>
      (ingredients.length == 4 || ingredients.length == 9) &&
      matchAllIngredients(ingredients);

  /// `CraftingRecipe.getRemainingItems(input)` (`defaultCraftingReminder`): one crafting
  /// remainder per consumed item.
  List<PStack> remainingItemsFor(List<PStack> consumed) => [
    for (final stack in consumed)
      if (craftingRemainderOf(stack) case final remainder?) remainder,
  ];

  @override
  String toString() => 'crafting($id -> $result)';
}

/// `ItemHelper.matchIngredients(i1, i2)`: the same items in the same order.
///
/// Java compares the tag-expanded item lists (`Ingredient.items()`); the pure ingredients keep
/// their leaves (items and tags) instead, so two ingredients match when those are equal.
bool matchIngredients(Ingredient a, Ingredient b) {
  if (identical(a, b)) return true;
  final ea = a.entries;
  final eb = b.entries;
  if (ea.length != eb.length) return false;
  for (var i = 0; i < ea.length; i++) {
    if (ea[i].item != eb[i].item || _tag(ea[i].tag) != _tag(eb[i].tag)) {
      return false;
    }
  }
  return true;
}

/// `ItemHelper.matchAllIngredients(ingredients)`.
bool matchAllIngredients(List<Ingredient> ingredients) {
  if (ingredients.length <= 1) return true;
  final first = ingredients.first;
  for (var i = 1; i < ingredients.length; i++) {
    if (!matchIngredients(first, ingredients[i])) return false;
  }
  return true;
}

String? _tag(String? tag) => tag?.startsWith('#') ?? false ? tag!.substring(1) : tag;

/// The vanilla crafting recipes of the level, by kind. Loaded by the processing module on
/// server load and on a datapack reload; `null` when the module has not loaded them.
final class CraftingRecipeCache {
  static CraftingRecipeCache? current;

  List<CraftingRecipeEntry> shaped = const [];
  List<CraftingRecipeEntry> shapeless = const [];

  /// The shaped recipes that are compressible squares (the press, when
  /// `allowShapedSquareInPress` is set).
  List<CraftingRecipeEntry> get compressibleSquares => [
    for (final entry in shaped)
      if (entry.isCompressibleSquare) entry,
  ];

  CraftingRecipeEntry? byId(String id) {
    for (final entry in shaped) {
      if (entry.id == id) return entry;
    }
    for (final entry in shapeless) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}