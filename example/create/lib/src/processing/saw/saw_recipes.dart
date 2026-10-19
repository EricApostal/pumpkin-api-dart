// The recipes the mechanical saw works through (`SawBlockEntity.getRecipes`): the cutting recipe
// (or the next step of a sequenced assembly) and vanilla stonecutting recipes. Pure: the stone
// cutting table is handed in, loaded from the host recipe manager by the part.
import 'dart:math';

import '../common/stack.dart';
import '../recipe/ingredient.dart';
import '../recipe/recipe_applier.dart';
import '../recipe/recipe_book.dart';
import '../recipe/recipe_type.dart';

/// A vanilla stonecutting recipe (`StonecutterRecipe`): one ingredient and the item it cuts to.
final class StonecuttingRecipe {
  final String id;
  final Ingredient ingredient;
  final PStack output;

  const StonecuttingRecipe(this.id, this.ingredient, this.output);

  bool matches(PStack stack, TagLookup tags) => ingredient.test(stack, tags);

  @override
  String toString() => 'stonecutting($id, $output)';
}

/// `AllRecipeTypes.CAN_BE_AUTOMATED` / `shouldIgnoreInAutomation`: recipe ids ending in
/// `_manual_only` are not used by machines.
bool ignoredInAutomation(String recipeId) {
  final path = recipeId.contains(':')
      ? recipeId.substring(recipeId.indexOf(':') + 1)
      : recipeId;
  return path.endsWith('_manual_only');
}

/// One entry of `SawBlockEntity.getRecipes()`: a Create cutting recipe (possibly the step of a
/// sequenced assembly) or a vanilla stonecutting recipe.
final class SawRecipe {
  /// The Create recipe, `null` for a stonecutting recipe.
  final RecipeMatch? match;

  /// The stonecutting output, `null` for a Create recipe.
  final PStack? stonecutting;

  const SawRecipe.cutting(RecipeMatch this.match) : stonecutting = null;

  const SawRecipe.stonecutting(PStack this.stonecutting) : match = null;

  bool get isCutting => match != null;

  /// `RecipeApplier.getResultItem` (the first output).
  PStack get resultItem => match?.recipe.resultItem ?? stonecutting!;

  String get id => match?.recipe.id ?? 'minecraft:stonecutting';

  /// `CuttingRecipe.getProcessingDuration()`; stonecutting takes 50 ticks.
  int get duration => match?.recipe.processingDuration ?? 50;

  /// `applyRecipe`: every item of [input] is rolled on its own, with the crafting remainder of
  /// the item when the machine returns it.
  List<PStack> apply(PStack input, Random random) {
    final m = match;
    if (m != null) {
      return applyRecipeOn(
        input,
        m.recipe,
        random,
        returnProcessingRemainder: true,
        rollFirst: m.sequenced?.forcedResult(random),
      );
    }
    return applyResultOn(input, stonecutting!);
  }

  @override
  String toString() => isCutting
      ? 'cutting(${match!.recipe.id})'
      : 'stonecutting($stonecutting)';
}

/// `SawBlockEntity.getRecipes`: the sequenced assembly step for [input] when its result passes
/// [filter], otherwise every matching cutting and stonecutting recipe.
///
/// [stonecutting] is only consulted when [allowStonecutting] is set (`recipes.allowStonecuttingOnSaw`).
List<SawRecipe> sawRecipes(
  RecipeBook book,
  PStack input, {
  required bool Function(PStack stack) filter,
  bool allowStonecutting = true,
  List<StonecuttingRecipe> stonecutting = const [],
}) {
  if (input.isEmpty) return const [];

  final sequenced = book.firstSequenced(CreateRecipeType.cutting, input);
  if (sequenced != null && filter(sequenced.recipe.resultItem)) {
    return [SawRecipe.cutting(sequenced)];
  }

  final out = <SawRecipe>[];
  for (final recipe in book.forInput(CreateRecipeType.cutting, input)) {
    if (ignoredInAutomation(recipe.id)) continue;
    if (!filter(recipe.resultItem)) continue;
    out.add(SawRecipe.cutting(RecipeMatch(recipe)));
  }
  if (allowStonecutting) {
    for (final recipe in stonecutting) {
      if (ignoredInAutomation(recipe.id)) continue;
      if (!filter(recipe.output)) continue;
      if (!recipe.matches(input, book.tags)) continue;
      out.add(SawRecipe.stonecutting(recipe.output));
    }
  }
  return out;
}
