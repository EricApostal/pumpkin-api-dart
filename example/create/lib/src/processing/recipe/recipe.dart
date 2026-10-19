// The recipe models (pure): `ProcessingRecipe` and its parameter variants, the mechanical
// crafting recipe and the sequenced assembly recipe.
import 'dart:math';

import '../common/stack.dart';
import 'heat.dart';
import 'ingredient.dart';
import 'output.dart';
import 'recipe_type.dart';

/// A recipe of a parameter based type (`ProcessingRecipe` with `ProcessingRecipeParams`).
class ProcessingRecipe {
  /// `namespace:path` id (the file path in the pack).
  final String id;
  final CreateRecipeType type;
  final List<Ingredient> ingredients;
  final List<FluidIngredient> fluidIngredients;
  final List<ProcessingOutput> results;
  final List<PFluid> fluidResults;
  final int processingDuration;
  final HeatCondition requiredHeat;

  /// `ItemApplicationRecipeParams.keepHeldItem` (deploying, item application).
  final bool keepHeldItem;

  const ProcessingRecipe({
    required this.id,
    required this.type,
    this.ingredients = const [],
    this.fluidIngredients = const [],
    this.results = const [],
    this.fluidResults = const [],
    this.processingDuration = 0,
    this.requiredHeat = HeatCondition.none,
    this.keepHeldItem = false,
  });

  /// `validate()`: the errors of a recipe that does not fit its type.
  List<String> validate() {
    final errors = <String>[];
    if (ingredients.length > type.maxItemInputs) {
      errors.add('Recipe has more item inputs (${ingredients.length}) than supported (${type.maxItemInputs}).');
    }
    if (results.length > type.maxItemOutputs) {
      errors.add('Recipe has more item outputs (${results.length}) than supported (${type.maxItemOutputs}).');
    }
    if (fluidIngredients.length > type.maxFluidInputs) {
      errors.add('Recipe has more fluid inputs (${fluidIngredients.length}) than supported (${type.maxFluidInputs}).');
    }
    if (fluidResults.length > type.maxFluidOutputs) {
      errors.add('Recipe has more fluid outputs (${fluidResults.length}) than supported (${type.maxFluidOutputs}).');
    }
    if (processingDuration > 0 && !type.canSpecifyDuration) {
      errors.add('Recipe specified a duration. Durations have no impact on this type of recipe.');
    }
    if (requiredHeat != HeatCondition.none && !type.canRequireHeat) {
      errors.add('Recipe specified a heat condition. Heat conditions have no impact on this type of recipe.');
    }
    return errors;
  }

  /// `getRollableResultsAsItemStacks`.
  List<PStack> get resultStacks => [for (final r in results) r.stack];

  /// `getResultItem`: the first result, or empty.
  PStack get resultItem => results.isEmpty ? PStack.empty : results.first.stack;

  /// `rollResults`: [forcedFirst] replaces the roll of the first result (sequenced assembly's
  /// `enforceNextResult`).
  List<PStack> rollResults(Random random, {PStack Function()? forcedFirst}) {
    final out = <PStack>[];
    for (var i = 0; i < results.length; i++) {
      final stack = i == 0 && forcedFirst != null ? forcedFirst() : results[i].roll(random);
      if (stack.isNotEmpty) out.add(stack);
    }
    return out;
  }

  /// Single-input matching of the standard types (`ingredients.get(0).test(stack)`).
  bool matchesSingle(PStack stack, TagLookup tags) =>
      stack.isNotEmpty && ingredients.isNotEmpty && ingredients.first.test(stack, tags);

  // -- Item application (deploying / item_application) --------------------------------------

  /// `getProcessedItem`: the ingredient for the item that is worked on.
  Ingredient get processedItem {
    if (ingredients.isEmpty) throw StateError('Item Application Recipe has no ingredient!');
    return ingredients[0];
  }

  /// `getRequiredHeldItem`: the ingredient for the held tool.
  Ingredient get requiredHeldItem {
    if (ingredients.length < 2) throw StateError('Item Application Recipe has no tool!');
    return ingredients[1];
  }

  /// `ItemApplicationRecipe.matches`.
  bool matchesApplication(PStack processed, PStack held, TagLookup tags) =>
      processedItem.test(processed, tags) && requiredHeldItem.test(held, tags);

  /// The recipe with other [ingredients] (sequenced assembly rewrites the first ingredient).
  ProcessingRecipe withIngredients(List<Ingredient> ingredients) => ProcessingRecipe(
    id: id,
    type: type,
    ingredients: ingredients,
    fluidIngredients: fluidIngredients,
    results: results,
    fluidResults: fluidResults,
    processingDuration: processingDuration,
    requiredHeat: requiredHeat,
    keepHeldItem: keepHeldItem,
  );

  @override
  String toString() => '${type.key}($id)';
}

/// `MechanicalCraftingRecipe`: a vanilla style shaped recipe with `accept_mirrored`.
final class MechanicalCraftingRecipe {
  final String id;

  /// The rows of the pattern; every row has the same length (after validation).
  final List<String> pattern;
  final Map<String, Ingredient> key;
  final ProcessingOutput result;
  final bool acceptMirrored;
  final String? category;
  final String? group;
  final bool showNotification;

  const MechanicalCraftingRecipe({
    required this.id,
    required this.pattern,
    required this.key,
    required this.result,
    this.acceptMirrored = false,
    this.category,
    this.group,
    this.showNotification = true,
  });

  int get width => pattern.isEmpty ? 0 : pattern.first.length;
  int get height => pattern.length;

  /// The ingredient of every cell, row by row; empty cells (` `) are `null`.
  List<Ingredient?> get cells => [
    for (final row in pattern)
      for (var x = 0; x < row.length; x++) key[row[x]],
  ];

  @override
  String toString() => 'mechanical_crafting($id)';
}

/// `SequencedRecipe`: one step of a sequenced assembly.
final class SequencedRecipe {
  final ProcessingRecipe recipe;

  const SequencedRecipe(this.recipe);
}
