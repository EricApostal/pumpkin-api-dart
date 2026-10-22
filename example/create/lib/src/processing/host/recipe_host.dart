// Loads Create's recipes into the [RecipeBook] and registers them with the host's recipe
// manager (host side).
//
// Sources: the embedded data pack (`lib/src/data/datapack.g.dart`, the `recipes` category: the
// host cannot parse `create:*` recipe types, so the plugin reads them itself) and the optional
// folder `<plugin data>/<folder>/**.json` for recipes of the server owner. With
// `syncRecipes`, each recipe is also handed to the host as a custom recipe with its network
// encoding so Create clients get them in `neoforge:recipe_content`.
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../data/datapack.g.dart';
import '../../data/pack_format.dart';
import '../recipe/ingredient.dart' as pure;
import '../recipe/recipe.dart';
import '../recipe/recipe_book.dart';
import '../recipe/recipe_json.dart';
import '../recipe/recipe_network.dart';
import '../recipe/recipe_type.dart';
import '../recipe/sequenced.dart';

/// What loading found.
final class RecipeLoadReport {
  int loaded = 0;
  int skippedByCondition = 0;
  int invalid = 0;
  int registeredWithHost = 0;
  int synced = 0;
  final Map<CreateRecipeType, int> perType = {};
  final List<String> errors = [];

  @override
  String toString() =>
      'loaded $loaded recipes ($skippedByCondition skipped by conditions, $invalid invalid), '
      '$registeredWithHost registered with the host, $synced synced to clients';
}

/// Reads recipe documents from the sources.
abstract final class RecipeSources {
  /// `(id, json)` of every `create:*` recipe file in the embedded pack.
  static Iterable<(String, Map<String, dynamic>)> embedded() sync* {
    for (final blob in datapackBlobs) {
      if (blob.category != 'recipes') continue;
      for (final PackFile f in blob.unpack()) {
        final parts = f.path.split('/');
        // data/<ns>/recipe/<path>.json
        if (parts.length < 4 || parts[0] != 'data' || (parts[2] != 'recipe' && parts[2] != 'recipes')) continue;
        if (!f.path.endsWith('.json')) continue;
        final Object? json;
        try {
          json = jsonDecode(utf8.decode(f.bytes));
        } on FormatException {
          continue;
        }
        if (json is! Map<String, dynamic> || recipeTypeOf(json) == null) continue;
        final name = parts.sublist(3).join('/');
        yield ('${parts[1]}:${name.substring(0, name.length - '.json'.length)}', json);
      }
    }
  }

  /// `(id, json)` of the recipes in `<folder>/<namespace>/<path>.json` of the data folder
  /// (a file `folder/foo.json` gets the id `create:foo`).
  static Iterable<(String, Map<String, dynamic>)> folder(DataFolder files, String folder) sync* {
    if (!files.exists(folder)) return;
    final stack = <(String, String)>[(folder, '')];
    var depth = 0;
    while (stack.isNotEmpty && depth++ < 2000) {
      final (path, rel) = stack.removeLast();
      for (final entry in files.list(path)) {
        final childPath = '$path/${entry.name}';
        final childRel = rel.isEmpty ? entry.name : '$rel/${entry.name}';
        if (entry.isDirectory) {
          stack.add((childPath, childRel));
        } else if (entry.name.endsWith('.json')) {
          try {
            final json = files.readJson(childPath);
            if (json is Map<String, dynamic> && recipeTypeOf(json) != null) {
              final idPath = childRel.substring(0, childRel.length - '.json'.length);
              yield (idPath.contains(':') ? idPath : 'create:$idPath', json);
            }
          } on Object {
            // unreadable files are reported by the caller through the missing recipe
          }
        }
      }
    }
  }
}

/// Parses [sources] into [book].
RecipeLoadReport loadRecipes(
  RecipeBook book,
  Iterable<(String, Map<String, dynamic>)> sources, {
  pure.TagLookup? unused,
  required RecipeLoadReport report,
  bool Function(String itemKey)? itemKnown,
}) {
  for (final (id, json) in sources) {
    try {
      final recipe = parseRecipe(id, json);
      if (recipe == null) {
        report.skippedByCondition++;
        continue;
      }
      book.add(recipe);
      report.loaded++;
      final t = recipeTypeOf(json)!;
      report.perType[t] = (report.perType[t] ?? 0) + 1;
    } on RecipeParseException catch (e) {
      report.invalid++;
      report.errors.add('$id: ${e.message}');
    } on Object catch (e) {
      report.invalid++;
      report.errors.add('$id: $e');
    }
  }
  return report;
}

// -- Host registration -------------------------------------------------------------------------

RecipeFluid _fluid(pure.FluidIngredient f) =>
    RecipeFluid(fluid: f.tag != null ? '#${f.tag}' : (f.fluids.isEmpty ? 'minecraft:empty' : f.fluids.first), amount: f.amount);

Ingredient _hostIngredient(pure.Ingredient i) {
  final entries = i.entries;
  final tags = [for (final e in entries) if (e.tag != null) e.tag!];
  final items = [for (final e in entries) if (e.item != null) e.item!];
  if (items.isEmpty && tags.isNotEmpty) return Ingredients.tag(tags.first);
  if (items.length == 1) return Ingredients.item(items.first);
  return Ingredients.oneOf(items.isEmpty ? const ['minecraft:air'] : items);
}

CustomRecipe _asCustom(Object recipe, String id, Map<String, dynamic>? source) {
  final extra = source == null ? const <int>[] : utf8.encode(jsonEncode(source));
  final cut = extra.length > 60000 ? const <int>[] : extra;
  switch (recipe) {
    case ProcessingRecipe():
      return CustomRecipe(
        id: id,
        ingredients: [for (final i in recipe.ingredients) SizedIngredient(ingredient: _hostIngredient(i), count: 1)],
        results: [
          for (final r in recipe.results) RecipeOutput(item: r.item, count: r.count, chance: r.chance),
        ],
        fluidIngredients: [for (final f in recipe.fluidIngredients) _fluid(f)],
        fluidResults: [for (final f in recipe.fluidResults) RecipeFluid(fluid: f.key, amount: f.amount)],
        extra: cut,
      );
    case MechanicalCraftingRecipe():
      return CustomRecipe(
        id: id,
        ingredients: [
          for (final c in recipe.cells)
            if (c != null) SizedIngredient(ingredient: _hostIngredient(c), count: 1),
        ],
        results: [RecipeOutput(item: recipe.result.item, count: recipe.result.count, chance: 1)],
        fluidIngredients: const [],
        fluidResults: const [],
        extra: cut,
      );
    case SequencedAssemblyRecipe():
      return CustomRecipe(
        id: id,
        ingredients: [SizedIngredient(ingredient: _hostIngredient(recipe.ingredient), count: 1)],
        results: [
          for (final r in recipe.resultPool) RecipeOutput(item: r.item, count: r.count, chance: r.chance.clamp(0.0, 1.0)),
        ],
        fluidIngredients: const [],
        fluidResults: const [],
        extra: cut,
      );
    default:
      throw ArgumentError.value(recipe, 'recipe');
  }
}

/// Registers the recipes of [sources] with the host, without a [RecipeBook].
///
/// This is the entry point of another package that ships `create:*` recipes in its *own* data
/// pack (Aeronautics does): the host cannot parse `create:*` recipe JSON, so those recipes are
/// invisible to it, and this port's machines read their recipes from the plugin's own data pack
/// (`RecipeSources.embedded`), which is per component. The recipes are registered as plugin
/// recipes of their `create:*` type, with the source JSON in `extra` — what
/// `registerRecipesWithHost` also stores, and what
/// `loadHostRecipes` reads back into the book of the Create component, which is the component
/// that runs the machines.
///
/// [sources] is `(id, json)`; an id without a namespace gets `create:`. Recipes whose type is
/// not a `create:*` type are skipped (the host reads those from the data pack itself), and the
/// counted rejections land in the returned report.
RecipeLoadReport registerRecipeSourcesWithHost(
  RecipeManager manager,
  Iterable<(String, Map<String, dynamic>)> sources,
) {
  final report = RecipeLoadReport();
  for (final (rawId, json) in sources) {
    final id = rawId.contains(':') ? rawId : 'create:$rawId';
    try {
      final type = recipeTypeOf(json);
      if (type == null) {
        report.skippedByCondition++;
        continue;
      }
      final recipe = parseRecipe(id, json);
      if (recipe == null) {
        report.skippedByCondition++;
        continue;
      }
      // Registering the same type twice does nothing on the host, and Create's own component
      // registers all of them; a component that loads first still contributes its recipes.
      manager.defineRecipeType(type.key);
      manager.addCustomRecipe(type.key, _asCustom(recipe, id, json));
      report.loaded++;
      report.registeredWithHost++;
      report.perType[type] = (report.perType[type] ?? 0) + 1;
    } on RecipeParseException catch (e) {
      report.invalid++;
      report.errors.add('$id: ${e.message}');
    } on HostException catch (e) {
      report.invalid++;
      report.errors.add('host rejected $id: ${e.message}');
    } on Object catch (e) {
      report.invalid++;
      report.errors.add('$id: $e');
    }
  }
  return report;
}

/// Registers every recipe of [book] with the host (`registerCustomRecipe`), with the network
/// encoding of [encoder] when given. Throws nothing: failures are counted in [report].
void registerRecipesWithHost(
  RecipeManager manager,
  RecipeBook book,
  RecipeLoadReport report, {
  RecipeNetworkEncoder? encoder,
  Map<String, Map<String, dynamic>> sources = const {},
}) {
  void one(Object recipe, String id, CreateRecipeType type) {
    try {
      final custom = _asCustom(recipe, id, sources[id]);
      final net = encoder?.encode(recipe);
      manager.addCustomRecipe(type.key, custom, networkData: net);
      report.registeredWithHost++;
      if (net != null) report.synced++;
    } on HostException catch (e) {
      report.errors.add('host rejected $id: ${e.message}');
    }
  }

  for (final type in CreateRecipeType.values) {
    for (final r in book.ofType(type)) {
      one(r, r.id, type);
    }
  }
  for (final r in book.mechanicalCrafting) {
    one(r, r.id, CreateRecipeType.mechanicalCrafting);
  }
  for (final r in book.sequencedAssemblies) {
    one(r, r.id, CreateRecipeType.sequencedAssembly);
  }
}
