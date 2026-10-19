import 'dart:convert';
import 'dart:math';

import 'package:create/src/data/datapack.g.dart';
import 'package:create/src/data/pack_format.dart';
import 'package:create/src/processing/common/stack.dart';
import 'package:create/src/processing/common/storage.dart';
import 'package:create/src/processing/recipe/heat.dart';
import 'package:create/src/processing/recipe/ingredient.dart';
import 'package:create/src/processing/recipe/output.dart';
import 'package:create/src/processing/recipe/recipe.dart';
import 'package:create/src/processing/recipe/recipe_applier.dart';
import 'package:create/src/processing/recipe/recipe_book.dart';
import 'package:create/src/processing/recipe/recipe_json.dart';
import 'package:create/src/processing/recipe/recipe_network.dart';
import 'package:create/src/processing/recipe/recipe_type.dart';
import 'package:create/src/processing/recipe/sequenced.dart';
import 'package:test/test.dart';

const tags = MapTagLookup(
  items: {
    'c:ingots/brass': {'create:brass_ingot'},
    'c:ingots/iron': {'minecraft:iron_ingot'},
    'minecraft:leaves': {'minecraft:oak_leaves'},
  },
  blocks: {
    'minecraft:convertable_to_mud': {'minecraft:dirt'},
  },
);

Map<String, dynamic> j(String s) => jsonDecode(s) as Map<String, dynamic>;

void main() {
  group('parsing', () {
    test('crushing with chances and conditions', () {
      final r = parseRecipe('create:crushing/x', j('''
        {"type":"create:crushing","ingredients":[{"item":"minecraft:emerald_ore"}],
         "processing_time":350,
         "results":[{"count":2,"id":"minecraft:emerald"},{"chance":0.75,"id":"create:experience_nugget"}]}''')) as ProcessingRecipe;
      expect(r.type, CreateRecipeType.crushing);
      expect(r.processingDuration, 350);
      expect(r.results, hasLength(2));
      expect(r.results[1].chance, 0.75);
      expect(r.matchesSingle(const PStack('minecraft:emerald_ore', 1), tags), isTrue);
      expect(r.matchesSingle(const PStack('minecraft:stone', 1), tags), isFalse);
    });

    test('mod_loaded condition skips the recipe, tag_empty does not', () {
      expect(
        parseRecipe('a:b', j('{"neoforge:conditions":[{"type":"neoforge:mod_loaded","modid":"mekanism"}],"type":"create:pressing","ingredients":[{"item":"a:b"}],"results":[{"id":"a:c"}]}')),
        isNull,
      );
      expect(
        parseRecipe('a:b', j('{"neoforge:conditions":[{"type":"neoforge:not","value":{"type":"neoforge:tag_empty","tag":"c:x"}}],"type":"create:pressing","ingredients":[{"tag":"c:x"}],"results":[{"id":"a:c"}]}')),
        isNotNull,
      );
    });

    test('mixing with fluids and heat', () {
      final r = parseRecipe('create:mixing/tea', j('''
        {"type":"create:mixing","heat_requirement":"heated",
         "ingredients":[{"tag":"minecraft:leaves"},
           {"type":"neoforge:single","amount":250,"fluid":"minecraft:water"},
           {"type":"neoforge:tag","amount":250,"tag":"c:milk"}],
         "results":[{"amount":500,"id":"create:tea"}]}''')) as ProcessingRecipe;
      expect(r.requiredHeat, HeatCondition.heated);
      expect(r.ingredients, hasLength(1));
      expect(r.fluidIngredients, hasLength(2));
      expect(r.fluidIngredients[1].tag, 'c:milk');
      expect(r.fluidResults.single.amount, 500);
      expect(r.fluidIngredients[0].test(const PFluid('minecraft:water', 300), tags), isTrue);
      expect(r.fluidIngredients[0].test(const PFluid('minecraft:water', 100), tags), isFalse);
    });

    test('block_tag ingredient', () {
      final r = parseRecipe('create:mixing/mud', j('''
        {"type":"create:mixing","ingredients":[{"type":"neoforge:block_tag","tag":"minecraft:convertable_to_mud"},
          {"type":"neoforge:single","amount":250,"fluid":"minecraft:water"}],"results":[{"id":"minecraft:mud"}]}''')) as ProcessingRecipe;
      expect(r.ingredients.single.test(const PStack('minecraft:dirt', 1), tags), isTrue);
    });

    test('validation rejects too many outputs and durations where none apply', () {
      expect(
        () => parseRecipe('a:b', j('{"type":"create:pressing","ingredients":[{"item":"a:b"}],"processing_time":10,"results":[{"id":"a:c"}]}')),
        throwsA(isA<RecipeParseException>()),
      );
    });

    test('mechanical crafting', () {
      final r = parseRecipe('create:mechanical_crafting/w', j('''
        {"type":"create:mechanical_crafting","accept_mirrored":true,"category":"misc",
         "key":{"B":{"tag":"c:ingots/brass"},"P":{"item":"create:precision_mechanism"}},
         "pattern":[" B ","BPB"," B "],"result":{"count":1,"id":"create:wand_of_symmetry"}}''')) as MechanicalCraftingRecipe;
      expect(r.width, 3);
      expect(r.height, 3);
      expect(r.acceptMirrored, isTrue);
      expect(r.cells.where((c) => c != null), hasLength(5));
    });

    test('deploying keeps the held item', () {
      final r = parseRecipe('create:deploying/x', j('''
        {"type":"create:deploying","ingredients":[{"item":"minecraft:iron_ingot"},{"item":"minecraft:honeycomb"}],
         "keep_held_item":true,"results":[{"id":"minecraft:gold_ingot"}]}''')) as ProcessingRecipe;
      expect(r.keepHeldItem, isTrue);
      expect(r.matchesApplication(const PStack('minecraft:iron_ingot', 1), const PStack('minecraft:honeycomb', 3), tags), isTrue);
      expect(r.matchesApplication(const PStack('minecraft:iron_ingot', 1), const PStack('minecraft:stone', 1), tags), isFalse);
    });
  });

  group('outputs', () {
    test('rolling a chance output rolls each item', () {
      const o = ProcessingOutput('a:b', count: 4, chance: 0.5);
      final counts = {for (var seed = 0; seed < 200; seed++) o.roll(Random(seed)).count};
      expect(counts.every((c) => c >= 0 && c <= 4), isTrue);
      expect(counts.length, greaterThan(2));
      expect(const ProcessingOutput('a:b', count: 3).roll(Random(1)), const PStack('a:b', 3));
    });
  });

  group('sequenced assembly', () {
    final recipe = parseRecipe('create:sequenced_assembly/sheet', j('''
      {"type":"create:sequenced_assembly","ingredient":{"tag":"c:ingots/iron"},
       "results":[{"id":"create:sturdy_sheet"},{"chance":4,"id":"minecraft:stone"}],
       "sequence":[
         {"type":"create:pressing","ingredients":[{"item":"create:unprocessed_obsidian_sheet"}],"results":[{"id":"create:unprocessed_obsidian_sheet"}]},
         {"type":"create:pressing","ingredients":[{"item":"create:unprocessed_obsidian_sheet"}],"results":[{"id":"create:unprocessed_obsidian_sheet"}]}],
       "transitional_item":{"id":"create:unprocessed_obsidian_sheet"},"loops":2}''')) as SequencedAssemblyRecipe;

    test('first step takes the start item or the transitional item', () {
      final first = recipe.sequence[0].recipe.ingredients[0];
      expect(first.test(const PStack('minecraft:iron_ingot', 1), tags), isTrue);
      expect(first.test(const PStack('create:unprocessed_obsidian_sheet', 1), tags), isTrue);
      final second = recipe.sequence[1].recipe.ingredients[0];
      expect(second.test(const PStack('minecraft:iron_ingot', 1), tags), isFalse);
    });

    test('advance goes through all loops, then rolls a result', () {
      var item = const PStack('minecraft:iron_ingot', 1);
      final rnd = Random(3);
      var steps = 0;
      while (item.key == 'minecraft:iron_ingot' || item.key == 'create:unprocessed_obsidian_sheet') {
        expect(recipe.appliesTo(item, tags), isTrue);
        item = recipe.advance(item, rnd);
        steps++;
        if (steps > 10) fail('does not terminate');
        if (item.key == 'create:unprocessed_obsidian_sheet') {
          final st = SequencedAssemblyState.of(item)!;
          expect(st.id, 'create:sequenced_assembly/sheet');
          expect(st.progress, closeTo(st.step / 4, 1e-6));
        }
      }
      expect(steps, 4);
      expect(['create:sturdy_sheet', 'minecraft:stone'], contains(item.key));
    });

    test('state round trip', () {
      const s = SequencedAssemblyState('create:x', 3, .75);
      expect(SequencedAssemblyState.decode(s.encode()), s);
    });

    test('book finds the step for a stack in the middle of the assembly', () {
      final book = RecipeBook(tags)..add(recipe);
      final start = book.sequencedFor(CreateRecipeType.pressing, const PStack('minecraft:iron_ingot', 1));
      expect(start, hasLength(1));
      expect(book.sequencedFor(CreateRecipeType.cutting, const PStack('minecraft:iron_ingot', 1)), isEmpty);
      final mid = recipe.advance(const PStack('minecraft:iron_ingot', 1), Random(1));
      final next = book.firstSequenced(CreateRecipeType.pressing, mid)!;
      final results = next.rollResults(Random(1));
      expect(results.single.key, 'create:unprocessed_obsidian_sheet');
      expect(SequencedAssemblyState.of(results.single)!.step, 2);
    });
  });

  group('the embedded pack', () {
    test('every create recipe parses', () {
      var total = 0;
      final failures = <String>[];
      final perType = <CreateRecipeType, int>{};
      final book = RecipeBook(tags);
      for (final PackBlob blob in datapackBlobs) {
        if (blob.category != 'recipes') continue;
        for (final f in blob.unpack()) {
          final parts = f.path.split('/');
          if (parts.length < 4 || parts[2] != 'recipe') continue;
          final json = jsonDecode(utf8.decode(f.bytes)) as Map<String, dynamic>;
          final type = recipeTypeOf(json);
          if (type == null) continue;
          total++;
          try {
            final r = parseRecipe(f.path, json);
            if (r != null) {
              book.add(r);
              perType[type] = (perType[type] ?? 0) + 1;
            }
          } on Object catch (e) {
            failures.add('${f.path}: $e');
          }
        }
      }
      expect(failures, isEmpty);
      expect(total, greaterThan(800));
      expect(perType[CreateRecipeType.crushing], greaterThan(40));
      expect(book.sequencedAssemblies, hasLength(3));
      expect(book.mechanicalCrafting, hasLength(4));
    });
  });

  group('network encoding', () {
    final ids = RecipeNetworkIds(
      item: (k) => {'minecraft:emerald_ore': 5, 'minecraft:emerald': 6, 'create:experience_nugget': 700}[k],
      fluid: (k) => {'minecraft:water': 2}[k],
      serializer: (k) => 30,
    );
    test('a crushing recipe', () {
      final r = parseRecipe('create:crushing/x', j('''
        {"type":"create:crushing","ingredients":[{"item":"minecraft:emerald_ore"}],"processing_time":350,
         "results":[{"count":2,"id":"minecraft:emerald"},{"chance":0.75,"id":"create:experience_nugget"}]}''')) as ProcessingRecipe;
      final bytes = RecipeNetworkEncoder(ids).encode(r)!;
      // 1 ingredient (set of 1 item: 2, id 5), 0 fluid ingredients, 2 results...
      expect(bytes.sublist(0, 4), [1, 2, 5, 0]);
      expect(bytes.last, 0); // heat ordinal none
    });

    test('unknown items are not synced', () {
      final r = parseRecipe('create:crushing/x', j('{"type":"create:crushing","ingredients":[{"item":"a:b"}],"results":[{"id":"a:c"}]}')) as ProcessingRecipe;
      expect(RecipeNetworkEncoder(ids).encode(r), isNull);
    });
  });

  group('storage', () {
    test('smart inventory stacks and respects the limit', () {
      final inv = SmartInventory(2, stackSize: 10);
      expect(inv.insert(0, const PStack('a:b', 7)), PStack.empty);
      expect(inv.insert(0, const PStack('a:b', 7)), const PStack('a:b', 4));
      expect(inv.stackIn(0).count, 10);
      expect(inv.insert(0, const PStack('a:c', 1)), const PStack('a:c', 1));
      expect(inv.extract(0, 4).count, 4);
      expect(ItemStorages.insertStacked(inv, const PStack('a:b', 20)).count, 6); // 4 top up slot 0, 10 into slot 1
    });

    test('fluid tank', () {
      final t = SmartFluidTank(1000);
      expect(t.fill(const PFluid('minecraft:water', 700)), 700);
      expect(t.fill(const PFluid('minecraft:water', 700)), 300);
      expect(t.fill(const PFluid('minecraft:lava', 10)), 0);
      expect(t.drainAny(400).amount, 400);
      expect(t.fluid.amount, 600);
    });
  });

  group('recipe applier', () {
    test('multipliedOutput splits into stacks', () {
      final out = multipliedOutput(const PStack('a:in', 5), const PStack('a:out', 30));
      expect(out.map((s) => s.count), [64, 64, 22]);
    });

    test('applyRecipeOn merges equal results', () {
      final r = parseRecipe('create:milling/x', j('{"type":"create:milling","ingredients":[{"item":"a:in"}],"results":[{"count":2,"id":"a:out"}],"processing_time":50}')) as ProcessingRecipe;
      final out = applyRecipeOn(const PStack('a:in', 3), r, Random(1));
      expect(out, [const PStack('a:out', 6)]);
    });
  });
}
