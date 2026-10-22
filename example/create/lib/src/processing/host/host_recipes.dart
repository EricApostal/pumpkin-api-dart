// Reads the `create:*` recipes other packages registered with the host back into this
// component's [RecipeBook].
//
// Why this exists: every plugin is its own wasm component, so a `create:*` recipe that ships in
// another package's data pack (Aeronautics' `aeronautics/*/recipe/**`, Simulated's, Offroad's)
// is invisible here — the host cannot parse `create:*` recipes, and this component reads its
// recipes from its own embedded pack (`RecipeSources.embedded`) and its own recipe folder. The
// one channel between components is the host: `registerRecipeSourcesWithHost` puts such a
// recipe in the host's plugin recipe table with its source JSON in `extra`, and this file takes
// it out again and parses it with the same parser the embedded pack uses. The machines then
// find it through the ordinary [RecipeBook] lookups.
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../recipe/recipe.dart';
import '../recipe/recipe_book.dart';
import '../recipe/recipe_json.dart';
import '../recipe/recipe_type.dart';

/// What a merge did.
final class HostRecipeReport {
  int added = 0;
  int skipped = 0;
  final List<String> errors = [];

  @override
  String toString() =>
      'added $added recipes of other components${errors.isEmpty ? '' : ' (${errors.length} failed)'}';
}

/// Adds every recipe of a `create:*` type in the host's plugin recipe table to [book], skipping
/// the ids in [seen] (and the ids the book already has, which are Create's own).
///
/// [seen] holds the ids of the recipes this function added before; the host's table is append
/// only and survives a data pack reload, so a second merge must not add them again. The recipes
/// are refreshed on a data pack reload by clearing [seen] and calling this again with a book in
/// the same state — the recipes are not removed from the host, so re-reading is enough.
HostRecipeReport loadHostRecipes(
  RecipeManager manager,
  RecipeBook book,
  Set<String> seen,
) {
  final report = HostRecipeReport();
  for (final type in CreateRecipeType.registered) {
    final List<RecipeInfo> infos;
    try {
      infos = manager.findRecipes(recipeType: type.key);
    } on Object catch (e) {
      report.errors.add('${type.key}: $e');
      continue;
    }
    for (final info in infos) {
      final id = info.id;
      if (id == null || seen.contains(id) || _bookHas(book, id)) {
        if (id != null) seen.add(id);
        report.skipped++;
        continue;
      }
      if (info.extra.isEmpty) {
        // A recipe of this component registered without its source JSON cannot be rebuilt.
        report.skipped++;
        continue;
      }
      try {
        final json = jsonDecode(utf8.decode(info.extra));
        if (json is! Map<String, dynamic>) {
          report.errors.add('$id: extra is not a recipe document');
          continue;
        }
        final recipe = parseRecipe(id, json);
        if (recipe == null) {
          report.skipped++;
          continue;
        }
        if (recipeTypeOf(json) != type) {
          report.errors.add('$id: extra says ${json['type']}, the host table says ${type.key}');
          continue;
        }
        book.add(recipe);
        seen.add(id);
        report.added++;
      } on Object catch (e) {
        report.errors.add('$id: $e');
      }
    }
  }
  return report;
}

bool _bookHas(RecipeBook book, String id) {
  if (book.byId(id) != null) return true;
  if (book.sequencedById(id) != null) return true;
  for (final MechanicalCraftingRecipe r in book.mechanicalCrafting) {
    if (r.id == id) return true;
  }
  return false;
}