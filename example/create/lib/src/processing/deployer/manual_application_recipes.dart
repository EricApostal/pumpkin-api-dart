// The pure half of `ManualApplicationRecipe.manualApplicationRecipesApplyInWorld`
// (`ManualApplicationRecipe.java:49-125`): which `create:item_application` recipe a block and a
// held item match, what the block becomes and what the recipe drops. The host side (the click
// hook) is in `manual_application.dart`.
//
// Pure (no host bindings), so the recipe logic is testable on the Dart VM.
import 'dart:math';

import '../../manifest/manifest.dart';
import '../common/stack.dart';
import '../recipe/ingredient.dart' show TagLookup;
import '../recipe/recipe.dart';
import '../recipe/recipe_applier.dart' show addToList;
import '../recipe/recipe_book.dart';
import '../recipe/recipe_type.dart';

/// The recipe side of the manual application.
abstract final class ManualApplicationRecipes {
  /// The recipe [held] applies to the block whose item form is [blockItem]
  /// (`manualApplicationRecipesApplyInWorld`: the first recipe of the type whose first
  /// ingredient matches the block and whose second matches the held item).
  static ProcessingRecipe? findRecipe(
    RecipeBook book,
    TagLookup tags,
    PStack blockItem,
    PStack held,
  ) {
    if (blockItem.isEmpty || held.isEmpty) return null;
    for (final recipe in book.ofType(CreateRecipeType.itemApplication)) {
      if (recipe.ingredients.length < 2) continue;
      if (recipe.matchesApplication(blockItem, held, tags)) return recipe;
    }
    return null;
  }

  /// `transformBlock(in, random)`: the block the main result is, or `null` for air (the result
  /// is not a block item).
  static String? transformedBlock(ProcessingRecipe recipe, Random random) {
    if (recipe.results.isEmpty) return null;
    final rolled = recipe.results.first.roll(random);
    if (rolled.isEmpty || !isBlockItem(rolled.key)) return null;
    return rolled.key;
  }

  /// `output.getItem() instanceof BlockItem`. The manifest names Create's items (without the
  /// `create:` namespace) and whether they are block items; every `create:item_application`
  /// recipe results in one of them (a vanilla item that is also a block would need the host's
  /// block registry, which is not available here).
  static bool isBlockItem(String itemKey) {
    final path = _createPath(itemKey);
    for (final item in kItems) {
      if (item.key == path) return item.isBlockItem;
    }
    return false;
  }

  /// `rollResults` of a `ManualApplicationRecipe`: the results without the block of the first
  /// one (`getRollableResultsExceptBlock`), merged like every recipe roll.
  static List<PStack> rolledItems(
    ProcessingRecipe recipe,
    Random random,
    String? block,
  ) {
    final out = <PStack>[];
    for (var i = 0; i < recipe.results.length; i++) {
      if (i == 0 && block != null) continue;
      addToList(recipe.results[i].roll(random), out);
    }
    return out;
  }

  /// The item form of the block [blockKey] (`in.getBlock().asItem()`): the block item a manifest
  /// entry links, else the block key itself (vanilla items are named after their block).
  static String blockItemKey(String blockKey) {
    final path = _createPath(blockKey);
    for (final item in kItems) {
      if (item.blockKey == path) return 'create:${item.key}';
    }
    return blockKey;
  }

  /// The manifest key of a `create:*` key (`create:andesite_casing` -> `andesite_casing`).
  static String _createPath(String key) =>
      key.startsWith('create:') ? key.substring('create:'.length) : key;
}