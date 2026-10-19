// The item side of the fluids module (host side): what the host knows about the
// fluid contents of items (buckets, container items) and the `create:filling` /
// `create:emptying` recipes of the processing module. The conversions themselves
// are in the pure `generic_item_fluid.dart`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../processing/common/stack.dart';
import '../processing/recipe/ingredient.dart';
import '../processing/recipe/recipe.dart';
import '../processing/recipe/recipe_book.dart';
import '../processing/recipe/recipe_type.dart';
import 'fluid_host.dart';
import 'fluid_stack.dart';
import 'generic_item_fluid.dart';

/// The [ItemFluidRules] over the host's bucket registry, with the module's
/// built-in buckets as the fallback.
ItemFluidRules hostItemFluidRules() {
  final fallback = ItemFluidRules();
  return ItemFluidRules(
    fluidFromBucket: (itemKey) {
      final stack = FluidRegistries.fromBucket(itemKey);
      return stack == null
          ? fallback.fluidFromBucket(itemKey)
          : fromHostFluid(stack);
    },
    bucketFor: (fluidKey) =>
        FluidRegistries.bucketFor(fluidKey) ?? fallback.bucketFor(fluidKey),
  );
}

/// [FluidItemRecipes] over the processing module's [RecipeBook].
final class RecipeFluidItemRecipes implements FluidItemRecipes {
  final RecipeBook book;

  const RecipeFluidItemRecipes(this.book);

  TagLookup get _tags => book.tags;

  static PStack _stack(FluidItemSpec item) => PStack(item.key, item.count);

  static FluidItemSpec _item(PStack stack) => stack.isEmpty
      ? FluidItemSpec.empty
      : FluidItemSpec(stack.key, stack.count);

  static FStack _fluid(PFluid fluid) =>
      fluid.isEmpty ? FStack.empty : FStack(fluid.key, fluid.amount);

  @override
  EmptyingResult? findEmptying(FluidItemSpec item) {
    final stack = _stack(item.withCount(1));
    if (stack.isEmpty) return null;
    for (final recipe in book.ofType(CreateRecipeType.emptying)) {
      if (!recipe.matchesSingle(stack, _tags)) continue;
      if (recipe.fluidResults.isEmpty) continue;
      return EmptyingResult(
        _fluid(recipe.fluidResults.first),
        _item(recipe.resultItem),
      );
    }
    return null;
  }

  /// The filling recipe of [item] whose fluid ingredient accepts [available].
  ProcessingRecipe? _fillingRecipe(FluidItemSpec item, FStack available) {
    final stack = _stack(item.withCount(1));
    if (stack.isEmpty || available.isEmpty) return null;
    final fluid = PFluid(available.fluid, available.amount);
    bool accepts(ProcessingRecipe recipe) =>
        recipe.fluidIngredients.isNotEmpty &&
        recipe.fluidIngredients.first.testFluid(fluid, _tags);
    final sequenced = book.firstSequenced(
      CreateRecipeType.filling,
      stack,
      filter: (recipe) => recipe.matchesSingle(stack, _tags) && accepts(recipe),
    );
    if (sequenced != null) return sequenced.recipe;
    for (final recipe in book.ofType(CreateRecipeType.filling)) {
      if (!recipe.matchesSingle(stack, _tags)) continue;
      if (!accepts(recipe)) continue;
      return recipe;
    }
    return null;
  }

  @override
  FillingResult? findFilling(FluidItemSpec item, FStack available) {
    final recipe = _fillingRecipe(item, available);
    if (recipe == null) return null;
    return FillingResult(
      recipe.fluidIngredients.first.amount,
      _item(recipe.resultItem),
    );
  }

  @override
  bool canBeFilled(FluidItemSpec item) {
    final stack = _stack(item.withCount(1));
    if (stack.isEmpty) return false;
    if (book.firstSequenced(
          CreateRecipeType.filling,
          stack,
          filter: (r) => r.matchesSingle(stack, _tags),
        ) !=
        null) {
      return true;
    }
    return book
        .ofType(CreateRecipeType.filling)
        .any((r) => r.matchesSingle(stack, _tags));
  }
}
