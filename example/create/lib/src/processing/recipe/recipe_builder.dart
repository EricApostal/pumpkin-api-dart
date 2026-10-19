// `ProcessingRecipeBuilder`, `StandardProcessingRecipe` and
// `SequencedAssemblyRecipeBuilder` (pure): the programmatic recipe API of the Java mod, used by
// datagen and by code that has to register a recipe at runtime. The JSON written by [toJson] is
// the same document `recipe_json.dart` reads back.
import '../common/stack.dart';
import 'heat.dart';
import 'ingredient.dart';
import 'output.dart';
import 'recipe.dart';
import 'recipe_book.dart';
import 'recipe_type.dart';
import 'sequenced.dart';

/// `ProcessingRecipeParams`: the mutable parameters a builder collects.
final class ProcessingRecipeParams {
  final List<Ingredient> ingredients;
  final List<FluidIngredient> fluidIngredients;
  final List<ProcessingOutput> results;
  final List<PFluid> fluidResults;
  int processingDuration;
  HeatCondition requiredHeat;

  /// `ItemApplicationRecipeParams.keepHeldItem`.
  bool keepHeldItem;

  ProcessingRecipeParams({
    List<Ingredient>? ingredients,
    List<FluidIngredient>? fluidIngredients,
    List<ProcessingOutput>? results,
    List<PFluid>? fluidResults,
    this.processingDuration = 0,
    this.requiredHeat = HeatCondition.none,
    this.keepHeldItem = false,
  }) : ingredients = ingredients ?? [],
       fluidIngredients = fluidIngredients ?? [],
       results = results ?? [],
       fluidResults = fluidResults ?? [];

  ProcessingRecipeParams copy() => ProcessingRecipeParams(
    ingredients: List.of(ingredients),
    fluidIngredients: List.of(fluidIngredients),
    results: List.of(results),
    fluidResults: List.of(fluidResults),
    processingDuration: processingDuration,
    requiredHeat: requiredHeat,
    keepHeldItem: keepHeldItem,
  );
}

/// `StandardProcessingRecipe`: a `ProcessingRecipe` built from [ProcessingRecipeParams].
final class StandardProcessingRecipe extends ProcessingRecipe {
  const StandardProcessingRecipe({
    required super.id,
    required super.type,
    super.ingredients,
    super.fluidIngredients,
    super.results,
    super.fluidResults,
    super.processingDuration,
    super.requiredHeat,
    super.keepHeldItem,
  });

  factory StandardProcessingRecipe.fromParams(
    String id,
    CreateRecipeType type,
    ProcessingRecipeParams params,
  ) => StandardProcessingRecipe(
    id: id,
    type: type,
    ingredients: List.of(params.ingredients),
    fluidIngredients: List.of(params.fluidIngredients),
    results: List.of(params.results),
    fluidResults: List.of(params.fluidResults),
    processingDuration: params.processingDuration,
    requiredHeat: params.requiredHeat,
    keepHeldItem: params.keepHeldItem,
  );
}

/// `ProcessingRecipe.Factory`: creates the typed recipe of a builder.
typedef ProcessingRecipeFactory<R extends ProcessingRecipe> = R Function(
  String id,
  CreateRecipeType type,
  ProcessingRecipeParams params,
);

/// `ProcessingRecipeBuilder`: accumulates ingredients, outputs and options, then builds [R].
class ProcessingRecipeBuilder<R extends ProcessingRecipe> {
  /// The id of the recipe (`create:crushing/zinc_ore`).
  final String recipeId;
  final CreateRecipeType type;
  final ProcessingRecipeFactory<R> factory;
  final ProcessingRecipeParams params;
  final List<Object?> recipeConditions = [];

  ProcessingRecipeBuilder(
    this.recipeId,
    this.type,
    this.factory, {
    ProcessingRecipeParams? params,
  }) : params = params ?? ProcessingRecipeParams();

  /// `self()` of the Java builder (the fluent methods return the builder).
  ProcessingRecipeBuilder<R> get self => this;

  ProcessingRecipeBuilder<R> withItemIngredients(
    Iterable<Ingredient> ingredients,
  ) {
    params.ingredients
      ..clear()
      ..addAll(ingredients);
    return this;
  }

  ProcessingRecipeBuilder<R> withItemOutputs(
    Iterable<ProcessingOutput> outputs,
  ) {
    params.results
      ..clear()
      ..addAll(outputs);
    return this;
  }

  ProcessingRecipeBuilder<R> withFluidIngredients(
    Iterable<FluidIngredient> ingredients,
  ) {
    params.fluidIngredients
      ..clear()
      ..addAll(ingredients);
    return this;
  }

  ProcessingRecipeBuilder<R> withFluidOutputs(Iterable<PFluid> outputs) {
    params.fluidResults
      ..clear()
      ..addAll(outputs);
    return this;
  }

  ProcessingRecipeBuilder<R> duration(int ticks) {
    params.processingDuration = ticks;
    return this;
  }

  /// `averageProcessingDuration()`.
  ProcessingRecipeBuilder<R> averageProcessingDuration() => duration(100);

  ProcessingRecipeBuilder<R> requiresHeat(HeatCondition condition) {
    params.requiredHeat = condition;
    return this;
  }

  ProcessingRecipeBuilder<R> keepHeldItem({bool keep = true}) {
    params.keepHeldItem = keep;
    return this;
  }

  // -- Datagen shortcuts -------------------------------------------------------------------

  ProcessingRecipeBuilder<R> require(Ingredient ingredient) {
    params.ingredients.add(ingredient);
    return this;
  }

  ProcessingRecipeBuilder<R> requireItem(String itemKey) =>
      require(Ingredient.item(itemKey));

  ProcessingRecipeBuilder<R> requireTag(String tag) =>
      require(Ingredient.tag(tag));

  ProcessingRecipeBuilder<R> requireFluid(String fluidKey, int amount) {
    params.fluidIngredients.add(
      FluidIngredient(fluids: [fluidKey], amount: amount),
    );
    return this;
  }

  ProcessingRecipeBuilder<R> requireFluidTag(String tag, int amount) {
    params.fluidIngredients.add(FluidIngredient(tag: tag, amount: amount));
    return this;
  }

  ProcessingRecipeBuilder<R> output(
    String item, {
    int count = 1,
    double chance = 1,
    Map<String, Object?> components = const {},
  }) {
    params.results.add(
      ProcessingOutput(
        item,
        count: count,
        chance: chance,
        components: components,
      ),
    );
    return this;
  }

  ProcessingRecipeBuilder<R> outputStack(ProcessingOutput output) {
    params.results.add(output);
    return this;
  }

  ProcessingRecipeBuilder<R> outputFluid(String fluidKey, int amount) {
    params.fluidResults.add(PFluid(fluidKey, amount));
    return this;
  }

  ProcessingRecipeBuilder<R> whenModLoaded(String modId) {
    recipeConditions.add({'type': 'neoforge:mod_loaded', 'modid': modId});
    return this;
  }

  ProcessingRecipeBuilder<R> whenModMissing(String modId) {
    recipeConditions.add({
      'type': 'neoforge:not',
      'value': {'type': 'neoforge:mod_loaded', 'modid': modId},
    });
    return this;
  }

  ProcessingRecipeBuilder<R> withCondition(Object? condition) {
    recipeConditions.add(condition);
    return this;
  }

  // -- Building ----------------------------------------------------------------------------

  /// `build()`.
  R build() => factory(recipeId, type, params.copy());

  /// Builds the recipe and adds it to [book] (the server's recipe store).
  R addTo(RecipeBook book) {
    final recipe = build();
    book.add(recipe);
    return recipe;
  }

  /// `validate()` of the built recipe.
  List<String> validate() => build().validate();

  /// The recipe document (`ProcessingRecipeParams.CODEC` plus the type).
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'type': type.key};
    final ingredients = <Object?>[
      for (final i in params.ingredients) ingredientJson(i),
      for (final f in params.fluidIngredients) fluidIngredientJson(f),
    ];
    if (ingredients.isNotEmpty) json['ingredients'] = ingredients;
    final results = <Object?>[
      for (final r in params.results) outputJson(r),
      for (final f in params.fluidResults) fluidResultJson(f),
    ];
    if (results.isNotEmpty) json['results'] = results;
    if (params.processingDuration > 0) {
      json['processing_time'] = params.processingDuration;
    }
    if (params.requiredHeat != HeatCondition.none) {
      json['heat_requirement'] = params.requiredHeat.serializedName;
    }
    if (params.keepHeldItem) json['keep_held_item'] = true;
    if (recipeConditions.isNotEmpty) {
      json['neoforge:conditions'] = recipeConditions;
    }
    return json;
  }

  /// The document of a recipe of [type] (the step form of a sequenced assembly).
  static Map<String, dynamic> processingJson(ProcessingRecipe recipe) =>
      ProcessingRecipeBuilder(
        recipe.id,
        recipe.type,
        (id, type, params) => recipe,
        params: ProcessingRecipeParams(
          ingredients: List.of(recipe.ingredients),
          fluidIngredients: List.of(recipe.fluidIngredients),
          results: List.of(recipe.results),
          fluidResults: List.of(recipe.fluidResults),
          processingDuration: recipe.processingDuration,
          requiredHeat: recipe.requiredHeat,
          keepHeldItem: recipe.keepHeldItem,
        ),
      ).toJson();
}

/// `StandardProcessingRecipe.Builder`.
final class StandardProcessingRecipeBuilder
    extends ProcessingRecipeBuilder<StandardProcessingRecipe> {
  StandardProcessingRecipeBuilder(String recipeId, CreateRecipeType type)
    : super(recipeId, type, StandardProcessingRecipe.fromParams);
}

/// `SequencedAssemblyRecipeBuilder`: threads an item through [steps] and rolls [resultPool].
final class SequencedAssemblyRecipeBuilder {
  final String recipeId;
  Ingredient? ingredient;
  ProcessingOutput? transitionalItem;
  int loops = 1;
  final List<ProcessingRecipe> steps = [];
  final List<ProcessingOutput> resultPool = [];
  final List<Object?> recipeConditions = [];

  SequencedAssemblyRecipeBuilder(this.recipeId);

  SequencedAssemblyRecipeBuilder require(Ingredient item) {
    ingredient = item;
    return this;
  }

  SequencedAssemblyRecipeBuilder requireItem(String itemKey) =>
      require(Ingredient.item(itemKey));

  SequencedAssemblyRecipeBuilder requireTag(String tag) =>
      require(Ingredient.tag(tag));

  SequencedAssemblyRecipeBuilder transitionTo(String item, {int count = 1}) {
    transitionalItem = ProcessingOutput(item, count: count);
    return this;
  }

  SequencedAssemblyRecipeBuilder withLoops(int value) {
    loops = value;
    return this;
  }

  SequencedAssemblyRecipeBuilder addOutput(
    String item, {
    double weight = 1,
    int count = 1,
  }) {
    resultPool.add(ProcessingOutput(item, count: count, chance: weight));
    return this;
  }

  /// `addStep(factory, builder)`: a step whose first ingredient and first output are the
  /// transitional item.
  SequencedAssemblyRecipeBuilder addStep(
    CreateRecipeType type,
    void Function(StandardProcessingRecipeBuilder builder) build,
  ) {
    final transitional = transitionalItem;
    if (transitional == null) {
      throw StateError('transitionTo must be called before addStep');
    }
    final builder = StandardProcessingRecipeBuilder(
      'create:sequenced_assembly/dummy',
      type,
    );
    builder
      ..require(Ingredient.item(transitional.item))
      ..output(transitional.item, count: transitional.count);
    build(builder);
    steps.add(builder.build());
    return this;
  }

  /// A pre-built step (the Java `getSequence().add(new SequencedRecipe<>(...))`).
  SequencedAssemblyRecipeBuilder addStepRecipe(ProcessingRecipe step) {
    steps.add(step);
    return this;
  }

  SequencedAssemblyRecipeBuilder withCondition(Object? condition) {
    recipeConditions.add(condition);
    return this;
  }

  /// `build()`.
  SequencedAssemblyRecipe build() {
    final start = ingredient;
    final transitional = transitionalItem;
    if (start == null) {
      throw StateError('The sequenced assembly has no ingredient');
    }
    if (transitional == null) {
      throw StateError('The sequenced assembly has no transitional item');
    }
    if (steps.isEmpty) throw StateError('The sequenced assembly has no steps');
    if (resultPool.isEmpty) {
      throw StateError('The sequenced assembly has no results');
    }
    return SequencedAssemblyRecipe.create(
      id: recipeId,
      ingredient: start,
      transitionalItem: transitional,
      steps: steps,
      resultPool: resultPool,
      loops: loops,
    );
  }

  /// Builds the recipe and adds it to [book].
  SequencedAssemblyRecipe addTo(RecipeBook book) {
    final recipe = build();
    book.add(recipe);
    return recipe;
  }

  /// The `create:sequenced_assembly` document.
  Map<String, dynamic> toJson() {
    final start = ingredient;
    final transitional = transitionalItem;
    if (start == null) {
      throw StateError('The sequenced assembly has no ingredient');
    }
    if (transitional == null) {
      throw StateError('The sequenced assembly has no transitional item');
    }
    final json = <String, dynamic>{
      'type': CreateRecipeType.sequencedAssembly.key,
      'ingredient': ingredientJson(start),
      'sequence': [
        for (final step in steps) ProcessingRecipeBuilder.processingJson(step),
      ],
      'results': [for (final r in resultPool) outputJson(r)],
      'transitional_item': outputJson(transitional),
      'loops': loops,
    };
    if (recipeConditions.isNotEmpty) {
      json['neoforge:conditions'] = recipeConditions;
    }
    return json;
  }
}

// -- JSON forms -------------------------------------------------------------------------------

/// `Ingredient.CODEC` of an ingredient.
Object? ingredientJson(Ingredient ingredient) => switch (ingredient) {
  ItemIngredient(:final key) => {'item': key},
  TagIngredient(:final tag) => {'tag': tag},
  BlockTagIngredient(:final tag) => {'type': 'neoforge:block_tag', 'tag': tag},
  AnyIngredient(:final children) => [
    for (final c in children) ingredientJson(c),
  ],
  IntersectionIngredient(:final children) => {
    'type': 'neoforge:intersection',
    'children': [for (final c in children) ingredientJson(c)],
  },
  DifferenceIngredient(:final base, :final subtracted) => {
    'type': 'neoforge:difference',
    'base': ingredientJson(base),
    'subtracted': ingredientJson(subtracted),
  },
  ComponentIngredient(:final items, :final components) => {
    'type': 'neoforge:components',
    'items': items,
    if (components.isNotEmpty) 'components': components,
  },
};

/// `SizedFluidIngredient.CODEC`.
Map<String, dynamic> fluidIngredientJson(FluidIngredient ingredient) => {
  'type': ingredient.tag != null ? 'neoforge:tag' : 'neoforge:single',
  if (ingredient.tag != null)
    'tag': ingredient.tag
  else
    'fluid': ingredient.fluids.first,
  'amount': ingredient.amount,
  if (ingredient.components.isNotEmpty) 'components': ingredient.components,
};

/// `ProcessingOutput.CODEC`.
Map<String, dynamic> outputJson(ProcessingOutput output) => {
  'id': output.item,
  'count': output.count,
  if (output.chance != 1) 'chance': output.chance,
  if (output.components.isNotEmpty) 'components': output.components,
};

/// `FluidStackTemplate.CODEC`.
Map<String, dynamic> fluidResultJson(PFluid fluid) => {
  'id': fluid.key,
  'amount': fluid.amount,
};

/// The conditions of a recipe document (kept for datagen).
List<Object?> conditionsJson(Iterable<Object?> conditions) =>
    List.of(conditions);
