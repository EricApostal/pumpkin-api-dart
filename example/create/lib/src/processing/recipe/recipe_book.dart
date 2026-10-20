// The in-memory recipe store the machines query (pure): every `create:*` recipe by type, with
// the lookups Create's `RecipeFinder` / `SequencedAssemblyRecipe.getRecipe` provide.
import 'dart:math';

import '../common/stack.dart';
import 'ingredient.dart';
import 'recipe.dart';
import 'recipe_type.dart';
import 'sequenced.dart';

/// A recipe and, when it comes from a sequenced assembly, the assembly step that wraps it.
final class RecipeMatch {
  final ProcessingRecipe recipe;

  /// Non-null when [recipe] is a step of a sequenced assembly: the machine must output
  /// [forcedResult] in place of the first result.
  final SequencedMatch? sequenced;

  const RecipeMatch(this.recipe, [this.sequenced]);

  /// `recipe.rollResults(random)` honouring the sequenced assembly's forced result.
  List<PStack> rollResults(Random random) => recipe.rollResults(
    random,
    forcedFirst: sequenced?.forcedResult(random),
  );
}

/// `AllRecipeTypes.CAN_BE_AUTOMATED` / `shouldIgnoreInAutomation`: a recipe whose path ends in
/// `_manual_only` is played by hand only, so no machine uses it.
bool ignoredInAutomation(String recipeId) {
  final path = recipeId.contains(':')
      ? recipeId.substring(recipeId.indexOf(':') + 1)
      : recipeId;
  return path.endsWith('_manual_only');
}

/// All loaded Create recipes.
final class RecipeBook {
  final TagLookup tags;

  final Map<CreateRecipeType, List<ProcessingRecipe>> _byType = {
    for (final t in CreateRecipeType.values) t: <ProcessingRecipe>[],
  };
  final Map<String, ProcessingRecipe> _byId = {};
  final List<MechanicalCraftingRecipe> _crafting = [];
  final List<SequencedAssemblyRecipe> _sequenced = [];

  RecipeBook(this.tags);

  // -- Adding ---------------------------------------------------------------------------------

  void add(Object recipe) {
    switch (recipe) {
      case ProcessingRecipe():
        _byType[recipe.type]!.add(recipe);
        _byId[recipe.id] = recipe;
      case MechanicalCraftingRecipe():
        _crafting.add(recipe);
      case SequencedAssemblyRecipe():
        _sequenced.add(recipe);
      default:
        throw ArgumentError.value(recipe, 'recipe', 'not a Create recipe');
    }
  }

  /// Removes everything (datapack reload).
  void clear() {
    for (final l in _byType.values) {
      l.clear();
    }
    _byId.clear();
    _crafting.clear();
    _sequenced.clear();
  }

  int get count => _byId.length + _crafting.length + _sequenced.length;

  // -- Queries --------------------------------------------------------------------------------

  /// All recipes of [type] (`RecipeManager.getAllRecipesFor`).
  List<ProcessingRecipe> ofType(CreateRecipeType type) => List.unmodifiable(_byType[type]!);

  ProcessingRecipe? byId(String id) => _byId[id];

  List<MechanicalCraftingRecipe> get mechanicalCrafting => List.unmodifiable(_crafting);
  List<SequencedAssemblyRecipe> get sequencedAssemblies => List.unmodifiable(_sequenced);

  SequencedAssemblyRecipe? sequencedById(String id) {
    for (final s in _sequenced) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// `SequencedAssemblyRecipe.getRecipes(level, item, type, class, filter)`: the steps of
  /// sequenced assemblies that [stack] is currently in (or starts) whose next step has [type].
  List<RecipeMatch> sequencedFor(
    CreateRecipeType type,
    PStack stack, {
    bool Function(ProcessingRecipe recipe)? filter,
  }) {
    final out = <RecipeMatch>[];
    if (stack.isEmpty) return out;
    for (final assembly in _sequenced) {
      if (!assembly.appliesTo(stack, tags)) continue;
      final recipe = assembly.nextRecipe(stack).recipe;
      if (recipe.type != type) continue;
      if (filter != null && !filter(recipe)) continue;
      out.add(RecipeMatch(recipe, SequencedMatch(assembly, recipe, stack)));
    }
    return out;
  }

  /// The first sequenced assembly step for [stack] (`SequencedAssemblyRecipe.getRecipe`).
  RecipeMatch? firstSequenced(CreateRecipeType type, PStack stack, {bool Function(ProcessingRecipe recipe)? filter}) {
    final l = sequencedFor(type, stack, filter: filter);
    return l.isEmpty ? null : l.first;
  }

  /// The recipes of [type] whose first ingredient accepts [stack] (the `matches` of the
  /// single-input types: crushing, milling, cutting, pressing, splashing, haunting, ...).
  List<ProcessingRecipe> forInput(CreateRecipeType type, PStack stack) {
    if (stack.isEmpty) return const [];
    return [
      for (final r in _byType[type]!)
        if (r.matchesSingle(stack, tags)) r,
    ];
  }

  /// `RecipeFinder`-style lookup for the single-input machines: a sequenced assembly step of
  /// the right type first (when [allowSequenced]), otherwise the first plain recipe. [accept]
  /// filters the plain recipes (the deployer rejects `_manual_only` ones, `CAN_BE_AUTOMATED`).
  RecipeMatch? findForInput(
    CreateRecipeType type,
    PStack stack, {
    bool allowSequenced = true,
    bool Function(ProcessingRecipe recipe)? accept,
  }) {
    if (allowSequenced) {
      final s = firstSequenced(type, stack, filter: (r) => r.matchesSingle(stack, tags));
      if (s != null) return s;
    }
    final plain = firstWhere(
      type,
      (r) => r.matchesSingle(stack, tags) && (accept?.call(r) ?? true),
    );
    return plain == null ? null : RecipeMatch(plain);
  }

  /// The first recipe of [type] satisfying [test] (basin / application lookups).
  ProcessingRecipe? firstWhere(CreateRecipeType type, bool Function(ProcessingRecipe r) test) {
    for (final r in _byType[type]!) {
      if (test(r)) return r;
    }
    return null;
  }

  /// Every recipe of [type] satisfying [test] (basin matching tries all and picks by priority).
  List<ProcessingRecipe> where(CreateRecipeType type, bool Function(ProcessingRecipe r) test) => [
    for (final r in _byType[type]!)
      if (test(r)) r,
  ];

  /// `DeployerApplicationRecipe` lookup (`DeployerBlockEntity.getRecipe`):
  /// sequenced assembly steps of type deploying first, then plain `deploying`, then
  /// `item_application`... callers pass the [types] they want in order. [accept] filters the
  /// plain recipes (`AllRecipeTypes.CAN_BE_AUTOMATED` for the deployer).
  RecipeMatch? findApplication(
    List<CreateRecipeType> types,
    PStack processed,
    PStack held, {
    bool allowSequenced = true,
    bool Function(ProcessingRecipe recipe)? accept,
  }) {
    for (final type in types) {
      if (allowSequenced) {
        final s = firstSequenced(type, processed, filter: (r) => r.matchesApplication(processed, held, tags));
        if (s != null) return s;
      }
      final plain = firstWhere(
        type,
        (r) => r.matchesApplication(processed, held, tags) && (accept?.call(r) ?? true),
      );
      if (plain != null) return RecipeMatch(plain);
    }
    return null;
  }
}
