// The recipe JSON shapes of the current NeoForge datagen (bare string ingredients, the
// `neoforge:ingredient_type` discriminator, `{amount, ingredient}` fluid ingredients) and the
// legacy shapes the embedded pack uses; plus one representative recipe of every AllRecipeTypes
// entry and the builder JSON round trip.
import 'dart:convert';
import 'dart:math';

import 'package:create/src/processing/common/stack.dart';
import 'package:create/src/processing/recipe/heat.dart';
import 'package:create/src/processing/recipe/ingredient.dart';
import 'package:create/src/processing/recipe/recipe.dart';
import 'package:create/src/processing/recipe/recipe_json.dart';
import 'package:create/src/processing/recipe/recipe_type.dart';
import 'package:create/src/processing/recipe/sequenced.dart';
import 'package:test/test.dart';

Map<String, dynamic> j(String s) => jsonDecode(s) as Map<String, dynamic>;

const tags = MapTagLookup(items: {
  'c:ingots/iron': {'minecraft:iron_ingot'},
});

void main() {
  group('ingredient shapes', () {
    test('bare strings are the current datagen form', () {
      final item = parseIngredient('create:zinc_ore');
      expect(item, isA<ItemIngredient>());
      expect((item as ItemIngredient).key, 'create:zinc_ore');
      final tag = parseIngredient('#c:ingots/brass');
      expect(tag, isA<TagIngredient>());
      expect((tag as TagIngredient).tag, 'c:ingots/brass');
      // A missing namespace defaults to minecraft.
      final bare = parseIngredient('stone');
      expect((bare as ItemIngredient).key, 'minecraft:stone');
    });

    test('legacy item / tag objects and arrays', () {
      expect(
        (parseIngredient({'item': 'minecraft:stone'}) as ItemIngredient).key,
        'minecraft:stone',
      );
      expect(
        (parseIngredient({'tag': 'c:ingots/brass'}) as TagIngredient).tag,
        'c:ingots/brass',
      );
      final any = parseIngredient([
        '#a:b',
        'c:d',
      ]);
      expect(any, isA<AnyIngredient>());
      expect(any.entries, hasLength(2));
    });

    test('the neoforge:ingredient_type discriminator', () {
      expect(
        parseIngredient({
          'neoforge:ingredient_type': 'neoforge:block_tag',
          'tag': 'minecraft:convertable_to_mud',
        }),
        isA<BlockTagIngredient>(),
      );
      expect(
        parseIngredient({
          'type': 'neoforge:block_tag',
          'tag': 'minecraft:convertable_to_mud',
        }),
        isA<BlockTagIngredient>(),
      );
      final compound = parseIngredient({
        'neoforge:ingredient_type': 'neoforge:compound',
        'children': [
          'a:b',
          '#c:d',
        ],
      });
      expect(compound, isA<AnyIngredient>());
      final components = parseIngredient({
        'neoforge:ingredient_type': 'neoforge:components',
        'components': {'x': 1},
        'items': ['a:b', 'c:d'],
      });
      expect(components, isA<ComponentIngredient>());
      final datagen = parseIngredient({
        'neoforge:ingredient_type': 'create:simple_datagen',
        'item': 'endergetic:x',
      });
      expect((datagen as ItemIngredient).key, 'endergetic:x');
    });
  });

  group('fluid ingredient shapes', () {
    test('current {amount, ingredient}', () {
      final simple = parseFluidIngredient(
        j('{"amount":250,"ingredient":"minecraft:water"}'),
      );
      expect(simple.fluids, ['minecraft:water']);
      expect(simple.amount, 250);
      final tag = parseFluidIngredient(
        j('{"amount":250,"ingredient":"#c:milk"}'),
      );
      expect(tag.tag, 'c:milk');
      expect(tag.amount, 250);
    });

    test('current fluid component ingredient', () {
      final ingredient = parseFluidIngredient(
        j(
          '{"amount":25,"ingredient":{"neoforge:ingredient_type":"neoforge:components",'
          '"components":{"k":"v"},"fluids":"create:potion"}}',
        ),
      );
      expect(ingredient.fluids, ['create:potion']);
      expect(ingredient.components, {'k': 'v'});
      expect(ingredient.amount, 25);
    });

    test('legacy neoforge:single / tag / components', () {
      expect(
        parseFluidIngredient(
          j('{"type":"neoforge:single","amount":250,"fluid":"minecraft:water"}'),
        ).fluids,
        ['minecraft:water'],
      );
      expect(
        parseFluidIngredient(
          j('{"type":"neoforge:tag","amount":250,"tag":"c:milk"}'),
        ).tag,
        'c:milk',
      );
      final components = parseFluidIngredient(
        j(
          '{"type":"neoforge:components","amount":25,"components":{"k":"v"},'
          '"fluids":"create:potion"}',
        ),
      );
      expect(components.fluids, ['create:potion']);
      expect(components.components, {'k': 'v'});
    });
  });

  group('current recipe documents', () {
    test('pressing with a list ingredient', () {
      final r =
          parseRecipe('create:pressing/path', j(
                '{"type":"create:pressing","ingredients":'
                '[["minecraft:dirt","minecraft:coarse_dirt"]],'
                '"results":[{"id":"minecraft:dirt_path"}]}',
              ))
              as ProcessingRecipe;
      expect(r.ingredients.single, isA<AnyIngredient>());
      expect(r.matchesSingle(const PStack('minecraft:dirt', 1), tags), isTrue);
      expect(r.matchesSingle(const PStack('minecraft:stone', 1), tags), isFalse);
    });

    test('filling with the modern fluid component ingredient', () {
      final r =
          parseRecipe('create:filling/glowstone', j(
                '{"type":"create:filling","ingredients":["create:cinder_flour",'
                '{"amount":25,"ingredient":'
                '{"neoforge:ingredient_type":"neoforge:components",'
                '"components":{"create:potion_fluid_bottle_type":"regular"},'
                '"fluids":"create:potion"}}],'
                '"results":[{"id":"minecraft:glowstone_dust"}]}',
              ))
              as ProcessingRecipe;
      expect(r.ingredients, hasLength(1));
      expect(r.fluidIngredients.single.fluids, ['create:potion']);
      expect(r.fluidIngredients.single.components, isNotEmpty);
    });

    test('mixing with modern fluids and heat', () {
      final r =
          parseRecipe('create:mixing/tea', j(
                '{"type":"create:mixing","heat_requirement":"heated",'
                '"ingredients":["#minecraft:leaves",'
                '{"amount":250,"ingredient":"minecraft:water"},'
                '{"amount":250,"ingredient":"#c:milk"}],'
                '"results":[{"amount":500,"id":"create:tea"}]}',
              ))
              as ProcessingRecipe;
      expect(r.requiredHeat, HeatCondition.heated);
      expect(r.fluidIngredients[0].fluids, ['minecraft:water']);
      expect(r.fluidIngredients[1].tag, 'c:milk');
      expect(r.fluidResults.single.amount, 500);
    });

    test('mechanical crafting with string keys', () {
      final r =
          parseRecipe('create:mechanical_crafting/crushing_wheel', j(
                '{"type":"create:mechanical_crafting","accept_mirrored":false,'
                '"key":{"A":"create:andesite_alloy","P":"#minecraft:planks"},'
                '"pattern":["A","P"],"result":{"count":2,"id":"create:crushing_wheel"}}',
              ))
              as MechanicalCraftingRecipe;
      expect(r.key['A'], isA<ItemIngredient>());
      expect(r.key['P'], isA<TagIngredient>());
      expect(r.result.count, 2);
      expect(r.acceptMirrored, isFalse);
    });

    test('sequenced assembly with a string ingredient and weighted pool', () {
      final r =
          parseRecipe('create:sequenced_assembly/sturdy_sheet', j(
                '{"type":"create:sequenced_assembly","ingredient":"#c:ingots/iron",'
                '"loops":5,"sequence":[{"type":"create:pressing",'
                '"ingredients":["create:unprocessed_obsidian_sheet"],'
                '"results":[{"id":"create:unprocessed_obsidian_sheet"}]}],'
                '"results":[{"chance":120.0,"id":"create:sturdy_sheet"},'
                '{"id":"minecraft:stone"}],'
                '"transitional_item":{"id":"create:unprocessed_obsidian_sheet"}}',
              ))
              as SequencedAssemblyRecipe;
      expect(r.loops, 5);
      expect(r.resultPool.first.chance, 120);
      expect(r.outputChance, closeTo(120 / 121, 1e-9));
      expect(r.sequence.single.recipe.ingredients.first.test(
        const PStack('minecraft:iron_ingot', 1),
        tags,
      ), isTrue);
    });
  });

  group('every AllRecipeTypes entry', () {
    test('limits and flags match the Java recipe classes', () {
      // (maxItemInputs, maxItemOutputs, maxFluidInputs, maxFluidOutputs,
      //  canRequireHeat, canSpecifyDuration, isAssemblyRecipe)
      const expected = <CreateRecipeType, (int, int, int, int, bool, bool, bool)>{
        CreateRecipeType.conversion: (1, 1, 0, 0, false, false, false),
        CreateRecipeType.crushing: (1, 7, 0, 0, false, true, false),
        CreateRecipeType.cutting: (1, 4, 0, 0, false, true, true),
        CreateRecipeType.milling: (1, 4, 0, 0, false, true, false),
        CreateRecipeType.basin: (64, 4, 2, 2, true, true, false),
        CreateRecipeType.mixing: (64, 4, 2, 2, true, true, false),
        CreateRecipeType.compacting: (64, 4, 2, 2, true, true, false),
        CreateRecipeType.pressing: (1, 2, 0, 0, false, false, true),
        CreateRecipeType.sandpaperPolishing: (1, 1, 0, 0, false, false, false),
        CreateRecipeType.splashing: (1, 12, 0, 0, false, false, false),
        CreateRecipeType.haunting: (1, 12, 0, 0, false, false, false),
        CreateRecipeType.deploying: (2, 4, 0, 0, false, false, true),
        CreateRecipeType.filling: (1, 1, 1, 0, false, false, true),
        CreateRecipeType.emptying: (1, 1, 0, 1, false, false, false),
        CreateRecipeType.itemApplication: (2, 4, 0, 0, false, false, false),
        CreateRecipeType.mechanicalCrafting: (0, 0, 0, 0, false, false, false),
        CreateRecipeType.sequencedAssembly: (0, 0, 0, 0, false, false, false),
      };
      expect(expected.keys.toSet(), CreateRecipeType.values.toSet());
      for (final e in expected.entries) {
        final t = e.key;
        final (maxIn, maxOut, maxFluidIn, maxFluidOut, heat, duration, assembly) =
            e.value;
        expect(
          [
            t.maxItemInputs,
            t.maxItemOutputs,
            t.maxFluidInputs,
            t.maxFluidOutputs,
            t.canRequireHeat,
            t.canSpecifyDuration,
            t.assembly,
          ],
          [maxIn, maxOut, maxFluidIn, maxFluidOut, heat, duration, assembly],
          reason: t.key,
        );
      }
      expect(CreateRecipeType.registered, CreateRecipeType.values);
    });

    test('one representative recipe of every type parses', () {
      final docs = <CreateRecipeType, Map<String, dynamic>>{
        CreateRecipeType.conversion: j(
          '{"type":"create:conversion","ingredients":["minecraft:andesite_alloy"],'
          '"results":[{"id":"minecraft:iron_ingot"}]}',
        ),
        CreateRecipeType.crushing: j(
          '{"type":"create:crushing","ingredients":["minecraft:emerald_ore"],'
          '"processing_time":350,"results":[{"count":2,"id":"minecraft:emerald"},'
          '{"chance":0.75,"id":"create:experience_nugget"}]}',
        ),
        CreateRecipeType.cutting: j(
          '{"type":"create:cutting","ingredients":["create:andesite_alloy_block"],'
          '"processing_time":50,"results":[{"id":"create:andesite_alloy"}]}',
        ),
        CreateRecipeType.milling: j(
          '{"type":"create:milling","ingredients":["minecraft:emerald_ore"],'
          '"processing_time":350,"results":[{"count":2,"id":"minecraft:emerald"}]}',
        ),
        CreateRecipeType.basin: j(
          '{"type":"create:basin","ingredients":["minecraft:cobblestone"],'
          '"results":[{"id":"minecraft:stone"}]}',
        ),
        CreateRecipeType.mixing: j(
          '{"type":"create:mixing","heat_requirement":"heated",'
          '"ingredients":["minecraft:cobblestone",'
          '{"amount":500,"ingredient":"minecraft:water"}],'
          '"results":[{"amount":1000,"id":"minecraft:lava"}]}',
        ),
        CreateRecipeType.compacting: j(
          '{"type":"create:compacting","ingredients":["minecraft:snowball"],'
          '"results":[{"id":"minecraft:snow_block"}]}',
        ),
        CreateRecipeType.pressing: j(
          '{"type":"create:pressing","ingredients":["minecraft:iron_ingot"],'
          '"results":[{"id":"create:iron_sheet"}]}',
        ),
        CreateRecipeType.sandpaperPolishing: j(
          '{"type":"create:sandpaper_polishing","ingredients":["minecraft:gold_ingot"],'
          '"results":[{"id":"create:golden_sheet"}]}',
        ),
        CreateRecipeType.splashing: j(
          '{"type":"create:splashing","ingredients":["minecraft:gravel"],'
          '"results":[{"id":"minecraft:flint"},{"chance":0.5,"id":"minecraft:iron_nugget"}]}',
        ),
        CreateRecipeType.haunting: j(
          '{"type":"create:haunting","ingredients":["minecraft:sand"],'
          '"results":[{"id":"minecraft:soul_sand"}]}',
        ),
        CreateRecipeType.deploying: j(
          '{"type":"create:deploying",'
          '"ingredients":["minecraft:iron_ingot","create:brass_sheet"],'
          '"keep_held_item":true,"results":[{"id":"create:precision_mechanism"}]}',
        ),
        CreateRecipeType.filling: j(
          '{"type":"create:filling","ingredients":["create:cinder_flour",'
          '{"amount":25,"ingredient":"create:potion"}],'
          '"results":[{"id":"minecraft:glowstone_dust"}]}',
        ),
        CreateRecipeType.emptying: j(
          '{"type":"create:emptying","ingredients":["minecraft:potion"],'
          '"results":[{"id":"minecraft:glass_bottle"},'
          '{"amount":250,"id":"minecraft:water"}]}',
        ),
        CreateRecipeType.itemApplication: j(
          '{"type":"create:item_application","ingredients":["#c:stripped_logs",'
          '"create:andesite_alloy"],"results":[{"id":"create:andesite_casing"}]}',
        ),
        CreateRecipeType.mechanicalCrafting: j(
          '{"type":"create:mechanical_crafting","accept_mirrored":true,'
          '"key":{"B":"#c:ingots/brass","P":"create:precision_mechanism"},'
          '"pattern":[" B ","BPB"," B "],'
          '"result":{"id":"create:wand_of_symmetry"}}',
        ),
        CreateRecipeType.sequencedAssembly: j(
          '{"type":"create:sequenced_assembly","ingredient":"#c:ingots/iron",'
          '"sequence":[{"type":"create:pressing",'
          '"ingredients":["create:unprocessed_obsidian_sheet"],'
          '"results":[{"id":"create:unprocessed_obsidian_sheet"}]}],'
          '"results":[{"id":"create:sturdy_sheet"}],'
          '"transitional_item":{"id":"create:unprocessed_obsidian_sheet"}}',
        ),
      };
      expect(docs.keys.toSet(), CreateRecipeType.values.toSet());
      for (final e in docs.entries) {
        final id = 'create:${e.key.path}/representative';
        expect(recipeTypeOf(e.value), e.key);
        final parsed = parseRecipe(id, e.value);
        expect(parsed, isNotNull, reason: e.key.key);
        expect(() => parseRecipe(id, e.value), returnsNormally);
      }
    });

    test('the two custom crafting serializers are not recipe types', () {
      // AllRecipeTypes.TOOLBOX_DYEING / ITEM_COPYING register a serializer but no recipe type
      // (they reuse minecraft:crafting) and their files carry no data.
      expect(CreateRecipeType.byKey('create:toolbox_dyeing'), isNull);
      expect(CreateRecipeType.byKey('create:item_copying'), isNull);
      expect(recipeTypeOf(j('{"type":"create:toolbox_dyeing"}')), isNull);
      expect(recipeTypeOf(j('{"type":"create:item_copying"}')), isNull);
      expect(
        () => parseRecipe('create:item_copying', j('{"type":"create:item_copying"}')),
        throwsA(isA<RecipeParseException>()),
      );
    });
  });

  group('processing semantics', () {
    test('duration, assemble and byproducts', () {
      final r =
          parseRecipe('create:crushing/emerald', j(
                '{"type":"create:crushing","ingredients":["minecraft:emerald_ore"],'
                '"processing_time":350,"results":[{"count":2,"id":"minecraft:emerald"},'
                '{"chance":0.75,"id":"create:experience_nugget"}]}',
              ))
              as ProcessingRecipe;
      expect(r.processingDuration, 350);
      expect(r.resultItem, const PStack('minecraft:emerald', 2));
      expect(r.assemble(), r.resultItem);
      expect(r.rollResults(_ZeroRandom()).first, const PStack('minecraft:emerald', 2));
      // A recipe without results assembles to nothing.
      expect(
        const ProcessingRecipe(id: 'x', type: CreateRecipeType.crushing).assemble(),
        PStack.empty,
      );
    });

    test('conditional recipes are skipped before parsing their body', () {
      final recipe = parseRecipe('create:pressing/x', j(
        '{"neoforge:conditions":[{"type":"neoforge:mod_loaded","modid":"mekanism"}],'
        '"type":"create:pressing","ingredients":["minecraft:iron_ingot"],'
        '"results":[{"id":"create:iron_sheet"}]}',
      ));
      expect(recipe, isNull);
    });
  });

  group('json round trips', () {
    test('the builder JSON parses back for every processing type', () {
      for (final type in CreateRecipeType.values.where((t) => t.processing)) {
        final builder =
            StandardProcessingRecipeBuilder('create:${type.path}/roundtrip', type)
              ..requireItem('minecraft:stone')
              ..output('minecraft:dirt');
        final json = builder.toJson();
        expect(builder.validate(), isEmpty, reason: type.key);
        final parsed = parseRecipe('create:${type.path}/roundtrip', json);
        expect(parsed, isA<ProcessingRecipe>(), reason: type.key);
        final roundTrip = parsed! as ProcessingRecipe;
        expect(roundTrip.type, type);
        expect(roundTrip.ingredients, hasLength(1));
        expect(roundTrip.results.single.item, 'minecraft:dirt');
      }
    });

    test('fluids, heat and keep_held_item round trip', () {
      final builder =
          StandardProcessingRecipeBuilder(
              'create:mixing/roundtrip',
              CreateRecipeType.mixing,
            )
            ..requireItem('minecraft:cobblestone')
            ..requireFluid('minecraft:water', 500)
            ..outputFluid('minecraft:lava', 1000)
            ..requiresHeat(HeatCondition.superheated)
            ..averageProcessingDuration();
      final parsed =
          parseRecipe('create:mixing/roundtrip', builder.toJson())!
              as ProcessingRecipe;
      expect(parsed.fluidIngredients.single.amount, 500);
      expect(parsed.fluidResults.single.key, 'minecraft:lava');
      expect(parsed.requiredHeat, HeatCondition.superheated);
      expect(parsed.processingDuration, 100);

      final deploying =
          StandardProcessingRecipeBuilder(
              'create:deploying/roundtrip',
              CreateRecipeType.deploying,
            )
            ..requireItem('minecraft:iron_ingot')
            ..requireItem('create:brass_sheet')
            ..keepHeldItem()
            ..output('create:precision_mechanism');
      final parsedDeploying =
          parseRecipe('create:deploying/roundtrip', deploying.toJson())!
              as ProcessingRecipe;
      expect(parsedDeploying.keepHeldItem, isTrue);
      expect(parsedDeploying.ingredients, hasLength(2));
    });
  });
}

/// A [Random] that rolls the lowest possible value, so chance outputs keep every item and
/// weighted pools pick their first entry.
final class _ZeroRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}
