// The `recipes` category of the embedded data pack: every `create:*` recipe category of
// `src/generated/resources/data/create/recipe` is present, the counts match, and every recipe of
// a `create:*` recipe type parses (the two `AllRecipeTypes` custom crafting serializers,
// `toolbox_dyeing` and `item_copying`, are present in the pack but are not recipe types).
import 'dart:convert';

import 'package:create/src/data/datapack.g.dart';
import 'package:create/src/data/pack_format.dart';
import 'package:create/src/processing/common/stack.dart';
import 'package:create/src/processing/recipe/ingredient.dart';
import 'package:create/src/processing/recipe/recipe_book.dart';
import 'package:create/src/processing/recipe/recipe_json.dart';
import 'package:create/src/processing/recipe/recipe_network.dart';
import 'package:create/src/processing/recipe/recipe_type.dart';
import 'package:test/test.dart';

/// Every `.json` file of the embedded `data/create/recipe` tree.
final List<PackFile> recipeFiles = [
  for (final blob in datapackBlobs)
    if (blob.category == 'recipes')
      for (final f in blob.unpack())
        if (f.path.startsWith('data/create/recipe/') && f.path.endsWith('.json'))
          f,
];

Map<String, dynamic> recipeJson(PackFile f) =>
    jsonDecode(utf8.decode(f.bytes)) as Map<String, dynamic>;

/// The files without a recipe type directory (stonecutting and compat stonecutting recipes).
const int expectedTopLevel = 615;

/// The recipe type directories of the Java `src/generated/resources/data/create/recipe` tree.
const Map<String, int> expectedDirs = {
  'blasting': 26,
  'campfire_cooking': 1,
  'compacting': 7,
  'crafting': 369,
  'crushing': 211,
  'cutting': 32,
  'deploying': 167,
  'emptying': 5,
  'filling': 19,
  'haunting': 22,
  'item_application': 8,
  'mechanical_crafting': 4,
  'milling': 246,
  'mixing': 14,
  'pressing': 43,
  'sandpaper_polishing': 1,
  'sequenced_assembly': 3,
  'smelting': 36,
  'smoking': 1,
  'splashing': 51,
};

/// Every `create:*` recipe of the pack, per type, before the load conditions are evaluated.
const Map<CreateRecipeType, int> expectedRawCounts = {
  CreateRecipeType.compacting: 7,
  CreateRecipeType.crushing: 211,
  CreateRecipeType.cutting: 32,
  CreateRecipeType.deploying: 167,
  CreateRecipeType.emptying: 5,
  CreateRecipeType.filling: 19,
  CreateRecipeType.haunting: 22,
  CreateRecipeType.itemApplication: 8,
  CreateRecipeType.mechanicalCrafting: 4,
  CreateRecipeType.milling: 246,
  CreateRecipeType.mixing: 14,
  CreateRecipeType.pressing: 43,
  CreateRecipeType.sandpaperPolishing: 1,
  CreateRecipeType.sequencedAssembly: 3,
  CreateRecipeType.splashing: 51,
};

/// The recipes that survive their load conditions on a server with only vanilla, NeoForge and
/// Create: every compat recipe (a `neoforge:mod_loaded` of another mod) is skipped.
const Map<CreateRecipeType, int> expectedParsedCounts = {
  CreateRecipeType.compacting: 7,
  CreateRecipeType.crushing: 82,
  CreateRecipeType.cutting: 2,
  CreateRecipeType.deploying: 167,
  CreateRecipeType.emptying: 2,
  CreateRecipeType.filling: 10,
  CreateRecipeType.haunting: 20,
  CreateRecipeType.itemApplication: 8,
  CreateRecipeType.mechanicalCrafting: 4,
  CreateRecipeType.milling: 47,
  CreateRecipeType.mixing: 11,
  CreateRecipeType.pressing: 8,
  CreateRecipeType.sandpaperPolishing: 1,
  CreateRecipeType.sequencedAssembly: 3,
  CreateRecipeType.splashing: 17,
};

void main() {
  final tags = MapTagLookup();

  test('the pack holds every recipe category of the Java datagen', () {
    final dirs = <String, int>{};
    var topLevel = 0;
    for (final f in recipeFiles) {
      final parts = f.path.split('/');
      if (parts.length == 4) {
        topLevel++;
      } else {
        dirs[parts[3]] = (dirs[parts[3]] ?? 0) + 1;
      }
    }
    expect(dirs, expectedDirs);
    expect(topLevel, expectedTopLevel);
  });

  test('the create:* recipe types have the expected number of files', () {
    final raw = <CreateRecipeType, int>{};
    final parsed = <CreateRecipeType, int>{};
    final failures = <String>[];
    for (final f in recipeFiles) {
      final json = recipeJson(f);
      final type = recipeTypeOf(json);
      if (type == null) continue;
      raw[type] = (raw[type] ?? 0) + 1;
      try {
        if (parseRecipe(f.path, json) != null) {
          parsed[type] = (parsed[type] ?? 0) + 1;
        } else {
          // Only a load condition may skip a file: a compat recipe for a mod we do not have.
          expect(json['neoforge:conditions'], isNotNull, reason: f.path);
        }
      } on Object catch (e) {
        failures.add('${f.path}: $e');
      }
    }
    expect(failures, isEmpty);
    expect(raw, expectedRawCounts);
    expect(parsed, expectedParsedCounts);
    // `conversion` is a JEI only type and `basin` an abstract base class: neither has recipes,
    // their concrete descendants (mixing / compacting) do.
    expect(raw.containsKey(CreateRecipeType.conversion), isFalse);
    expect(raw.containsKey(CreateRecipeType.basin), isFalse);
  });

  test('the custom crafting serializers are present but not recipe types', () {
    final special = recipeFiles
        .where(
          (f) =>
              f.path.endsWith('/item_copying.json') ||
              f.path.endsWith('/toolbox_dyeing.json'),
        )
        .toList();
    expect(
      special.map((f) => f.path.split('/').last),
      unorderedEquals(['item_copying.json', 'toolbox_dyeing.json']),
    );
    for (final f in special) {
      final json = recipeJson(f);
      expect(recipeTypeOf(json), isNull);
    }
  });

  test('the pack assembles into the recipe book the machines query', () {
    final book = RecipeBook(tags);
    for (final f in recipeFiles) {
      final json = recipeJson(f);
      if (recipeTypeOf(json) == null) continue;
      final parsed = parseRecipe(f.path, json);
      if (parsed != null) book.add(parsed);
    }
    expect(book.sequencedAssemblies, hasLength(3));
    expect(book.mechanicalCrafting, hasLength(4));
    expect(
      book.forInput(
        CreateRecipeType.crushing,
        const PStack('minecraft:coal_ore', 1),
      ),
      isNotEmpty,
    );
    expect(
      book.forInput(CreateRecipeType.crushing, const PStack('minecraft:glass', 1)),
      isEmpty,
    );
  });

  test('sequenced assemblies only chain assembling recipe types', () {
    var assemblies = 0;
    for (final f in recipeFiles) {
      final json = recipeJson(f);
      if (json['type'] != 'create:sequenced_assembly') continue;
      assemblies++;
      final sequence = json['sequence']! as List<Object?>;
      expect(sequence, isNotEmpty);
      for (final step in sequence) {
        final map = (step as Map<Object?, Object?>).cast<String, dynamic>();
        final type = recipeTypeOf(map);
        expect(type, isNotNull);
        expect(type!.assembly, isTrue, reason: '$f: ${map['type']}');
        expect(map['type'], isNot('create:sequenced_assembly'));
      }
    }
    expect(assemblies, 3);
  });

  test('the network encoder can represent nearly the whole pack', () {
    // The host syncs a recipe only when its content is exactly encodable, so Create clients get
    // the recipes only when the encoder accepts them.
    const ids = RecipeNetworkIds(item: _one, fluid: _one, serializer: _one);
    const encoder = RecipeNetworkEncoder(ids);
    var encodable = 0;
    var total = 0;
    for (final f in recipeFiles) {
      final json = recipeJson(f);
      if (recipeTypeOf(json) == null) continue;
      final parsed = parseRecipe(f.path, json);
      if (parsed == null) continue;
      total++;
      if (encoder.encode(parsed) != null) encodable++;
    }
    expect(total, expectedParsedCounts.values.reduce((a, b) => a + b));
    expect(encodable, greaterThan(total * 0.95));
  });
}

int _one(String _) => 1;
