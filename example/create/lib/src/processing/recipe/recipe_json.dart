// Parses the recipe JSON of Create (pure): `ProcessingRecipeParams.CODEC`,
// `ItemApplicationRecipeParams.CODEC`, the shaped mechanical crafting recipe and the
// sequenced assembly serializer. Ingredient forms: `{"item"}`, `{"tag"}`, arrays and NeoForge's
// `block_tag`, `components`, `nbt`, `compound`, `intersection`, `difference`.
import '../common/stack.dart';
import 'conditions.dart';
import 'heat.dart';
import 'ingredient.dart';
import 'output.dart';
import 'raw_recipe.dart';
import 'recipe.dart';
import 'recipe_type.dart';
import 'sequenced.dart';

/// An invalid recipe file.
final class RecipeParseException implements Exception {
  final String message;
  const RecipeParseException(this.message);
  @override
  String toString() => 'RecipeParseException: $message';
}

String _id(Object? v, String what) {
  if (v is String) return v.contains(':') ? v : 'minecraft:$v';
  throw RecipeParseException('$what: expected a resource location, got $v');
}

/// `Ingredient.CODEC`.
Ingredient parseIngredient(Object? json) {
  if (json is List) return Ingredient.anyOf([for (final e in json) parseIngredient(e)]);
  if (json is! Map) throw RecipeParseException('Invalid ingredient: $json');
  final type = json['type'];
  if (type == null) {
    if (json.containsKey('item')) return Ingredient.item(_id(json['item'], 'ingredient item'));
    if (json.containsKey('tag')) return Ingredient.tag(_tag(json['tag']));
    throw RecipeParseException('Invalid ingredient: $json');
  }
  switch (type) {
    case 'neoforge:block_tag':
      return BlockTagIngredient(_tag(json['tag']));
    case 'neoforge:components':
    case 'neoforge:nbt':
    case 'neoforge:partial_nbt':
      final items = json['items'] ?? json['item'];
      final list = items is List ? items : [items];
      return ComponentIngredient(
        [for (final i in list) _id(i, 'ingredient items')],
        (json['components'] as Map?)?.cast<String, Object?>() ?? const {},
      );
    case 'neoforge:compound':
    case 'neoforge:any':
      return Ingredient.anyOf([for (final c in (json['children'] as List? ?? const [])) parseIngredient(c)]);
    case 'neoforge:intersection':
      return IntersectionIngredient([for (final c in (json['children'] as List? ?? const [])) parseIngredient(c)]);
    case 'neoforge:difference':
      return DifferenceIngredient(parseIngredient(json['base']), parseIngredient(json['subtracted']));
    default:
      throw RecipeParseException('Unknown ingredient type $type');
  }
}

String _tag(Object? v) {
  if (v is! String) throw RecipeParseException('Expected a tag, got $v');
  final t = v.startsWith('#') ? v.substring(1) : v;
  return t.contains(':') ? t : 'minecraft:$t';
}

/// `SizedFluidIngredient`: `neoforge:single`, `neoforge:tag`, `neoforge:components`.
FluidIngredient parseFluidIngredient(Map<Object?, Object?> json) {
  final amount = (json['amount'] as num?)?.toInt() ?? 1000;
  switch (json['type']) {
    case 'neoforge:tag':
      return FluidIngredient(tag: _tag(json['tag']), amount: amount);
    case 'neoforge:components':
      final f = json['fluids'];
      final list = f is List ? f : [f];
      return FluidIngredient(
        fluids: [for (final x in list) _id(x, 'fluids')],
        amount: amount,
        components: (json['components'] as Map?)?.cast<String, Object?>() ?? const {},
      );
    case 'neoforge:single':
    case null:
      return FluidIngredient(fluids: [_id(json['fluid'], 'fluid')], amount: amount);
    default:
      throw RecipeParseException('Unknown fluid ingredient type ${json['type']}');
  }
}

/// `ProcessingOutput.CODEC` (new form `{id, count, chance, components}` and the old
/// `{item: ..., count, chance}`).
ProcessingOutput parseOutput(Object? json) {
  if (json is! Map) throw RecipeParseException('Invalid result: $json');
  final Object? idValue;
  if (json.containsKey('id')) {
    idValue = json['id'];
  } else {
    final old = json['item'];
    idValue = old is Map ? old['id'] : old;
  }
  final comps = (json['components'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
  final count = (json['count'] as num?)?.toInt() ?? 1;
  if (count < 1 || count > 99) throw RecipeParseException('Result count $count outside 1..99');
  final chance = (json['chance'] as num?)?.toDouble() ?? 1.0;
  if (chance <= 0) throw RecipeParseException('Result chance must be positive');
  return ProcessingOutput(_id(idValue, 'result id'), count: count, chance: chance, components: comps);
}

PFluid _parseFluidStack(Map<Object?, Object?> json) {
  final amount = (json['amount'] as num?)?.toInt() ?? 0;
  if (amount <= 0) throw RecipeParseException('Fluid result amount must be positive');
  return PFluid(_id(json['id'] ?? json['fluid'], 'fluid result'), amount);
}

/// Parses [json] (one recipe file) into a recipe model with the id [id]. Returns `null`
/// when its load conditions do not hold. Types other than the `create:*` processing types
/// throw a [RecipeParseException]; use [recipeTypeOf] to filter first.
Object? parseRecipe(String id, Map<String, dynamic> json, {ConditionContext ctx = const DefaultConditionContext()}) {
  final raw = RawRecipeMapper.fromMap(json);
  if (!conditionsHold(raw.conditions, ctx)) return null;
  final type = CreateRecipeType.byKey(raw.type);
  if (type == null) throw RecipeParseException('Not a Create recipe type: ${raw.type}');
  switch (type) {
    case CreateRecipeType.mechanicalCrafting:
      return _parseMechanicalCrafting(id, raw);
    case CreateRecipeType.sequencedAssembly:
      return _parseSequenced(id, raw, ctx);
    default:
      return _parseProcessing(id, type, raw);
  }
}

/// The Create recipe type named by the file, or `null` for other types (vanilla recipes, the
/// two special crafting recipes `create:toolbox_dyeing` and `create:item_copying`).
CreateRecipeType? recipeTypeOf(Map<String, dynamic> json) {
  final t = json['type'];
  return t is String ? CreateRecipeType.byKey(t) : null;
}

ProcessingRecipe _parseProcessing(String id, CreateRecipeType type, RawRecipe raw) {
  final items = <Ingredient>[];
  final fluids = <FluidIngredient>[];
  for (final e in raw.ingredients ?? const <Object?>[]) {
    if (e is Map && e.containsKey('amount')) {
      fluids.add(parseFluidIngredient(e));
    } else {
      items.add(parseIngredient(e));
    }
  }
  final outputs = <ProcessingOutput>[];
  final fluidResults = <PFluid>[];
  for (final e in raw.results ?? const <Object?>[]) {
    if (e is Map && e.containsKey('amount')) {
      fluidResults.add(_parseFluidStack(e));
    } else {
      outputs.add(parseOutput(e));
    }
  }
  final heat = raw.heatRequirement == null
      ? HeatCondition.none
      : (HeatCondition.byName(raw.heatRequirement!) ?? (throw RecipeParseException('Unknown heat ${raw.heatRequirement}')));
  final recipe = ProcessingRecipe(
    id: id,
    type: type,
    ingredients: items,
    fluidIngredients: fluids,
    results: outputs,
    fluidResults: fluidResults,
    processingDuration: raw.processingTime ?? 0,
    requiredHeat: heat,
    keepHeldItem: raw.keepHeldItem ?? false,
  );
  final errors = recipe.validate();
  if (errors.isNotEmpty) throw RecipeParseException('${errors.join('\n')}\n$id failed validation');
  return recipe;
}

MechanicalCraftingRecipe _parseMechanicalCrafting(String id, RawRecipe raw) {
  final pattern = raw.pattern;
  if (pattern == null || pattern.isEmpty) throw RecipeParseException('$id: missing pattern');
  final width = pattern.first.length;
  if (pattern.any((r) => r.length != width)) throw RecipeParseException('$id: rows of different length');
  final key = <String, Ingredient>{
    for (final e in (raw.key ?? const <String, Object?>{}).entries) e.key: parseIngredient(e.value),
  };
  for (final row in pattern) {
    for (var i = 0; i < row.length; i++) {
      final ch = row[i];
      if (ch != ' ' && !key.containsKey(ch)) throw RecipeParseException("$id: pattern uses '$ch' with no key");
    }
  }
  return MechanicalCraftingRecipe(
    id: id,
    pattern: pattern,
    key: key,
    result: parseOutput(raw.result),
    acceptMirrored: raw.acceptMirrored ?? false,
    category: raw.category,
    group: raw.group,
    showNotification: raw.showNotification ?? true,
  );
}

SequencedAssemblyRecipe _parseSequenced(String id, RawRecipe raw, ConditionContext ctx) {
  final steps = <ProcessingRecipe>[];
  var i = 0;
  for (final s in raw.sequence ?? const <Object?>[]) {
    if (s is! Map) throw RecipeParseException('$id: invalid sequence step');
    final parsed = parseRecipe('$id/step$i', s.cast<String, dynamic>(), ctx: ctx);
    if (parsed is! ProcessingRecipe || !parsed.type.assembly) {
      throw RecipeParseException('$id: ${s['type']} is not supported in Sequenced Assembly');
    }
    steps.add(parsed);
    i++;
  }
  if (steps.isEmpty) throw RecipeParseException('$id: empty sequence');
  final results = [for (final r in raw.results ?? const <Object?>[]) parseOutput(r)];
  if (results.isEmpty) throw RecipeParseException('$id: no results');
  return SequencedAssemblyRecipe.create(
    id: id,
    ingredient: parseIngredient(raw.ingredient),
    transitionalItem: parseOutput(raw.transitionalItem),
    steps: steps,
    resultPool: results,
    loops: raw.loops ?? 1,
  );
}
