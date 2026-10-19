import 'package:create/src/processing/burner/insert_result.dart';
import 'package:create/src/processing/common/stack.dart';
import 'package:create/src/processing/recipe/heat.dart';
import 'package:create/src/processing/recipe/ingredient.dart';
import 'package:create/src/processing/recipe/recipe.dart';
import 'package:create/src/processing/recipe/recipe_builder.dart';
import 'package:create/src/processing/recipe/recipe_json.dart';
import 'package:create/src/processing/recipe/recipe_type.dart';
import 'package:create/src/processing/recipe/sequenced.dart';
import 'package:test/test.dart';

void main() {
  group('processing recipe builder', () {
    test('a crushing recipe round-trips through its JSON document', () {
      final builder =
          StandardProcessingRecipeBuilder(
              'create:crushing/zinc_ore',
              CreateRecipeType.crushing,
            )
            ..requireItem('create:zinc_ore')
            ..output('create:crushed_raw_zinc')
            ..duration(250);

      final recipe = builder.build();
      expect(recipe.id, 'create:crushing/zinc_ore');
      expect(recipe.type, CreateRecipeType.crushing);
      expect(recipe.ingredients, hasLength(1));
      expect(
        (recipe.ingredients.first as ItemIngredient).key,
        'create:zinc_ore',
      );
      expect(recipe.results.single.item, 'create:crushed_raw_zinc');
      expect(recipe.processingDuration, 250);
      expect(builder.validate(), isEmpty);

      final json = builder.toJson();
      expect(json['type'], 'create:crushing');
      expect(json['ingredients'], [
        {'item': 'create:zinc_ore'},
      ]);
      expect(json['results'], [
        {'id': 'create:crushed_raw_zinc', 'count': 1},
      ]);
      expect(json['processing_time'], 250);

      final parsed = parseRecipe('create:crushing/zinc_ore', json)!;
      expect(parsed, isA<ProcessingRecipe>());
      final roundTripped = parsed as ProcessingRecipe;
      expect(roundTripped.type, CreateRecipeType.crushing);
      expect(roundTripped.ingredients, hasLength(1));
      expect(roundTripped.results.single.item, 'create:crushed_raw_zinc');
      expect(roundTripped.processingDuration, 250);
    });

    test('fluids and heat round-trip', () {
      final builder =
          StandardProcessingRecipeBuilder(
              'create:mixing/lava',
              CreateRecipeType.mixing,
            )
            ..requireItem('minecraft:cobblestone')
            ..requireFluid('minecraft:water', 500)
            ..outputFluid('minecraft:lava', 1000)
            ..requiresHeat(HeatCondition.superheated)
            ..averageProcessingDuration();

      final recipe = builder.build();
      expect(recipe.fluidIngredients.single.amount, 500);
      expect(recipe.fluidResults.single.key, 'minecraft:lava');
      expect(recipe.requiredHeat, HeatCondition.superheated);
      expect(recipe.processingDuration, 100);

      final json = builder.toJson();
      expect(json['heat_requirement'], 'superheated');
      expect((json['ingredients'] as List).last, {
        'type': 'neoforge:single',
        'fluid': 'minecraft:water',
        'amount': 500,
      });

      final parsed =
          parseRecipe('create:mixing/lava', json)! as ProcessingRecipe;
      expect(parsed.fluidIngredients.single.amount, 500);
      expect(parsed.fluidResults.single.amount, 1000);
      expect(parsed.requiredHeat, HeatCondition.superheated);
    });

    test('conditions are written and evaluated', () {
      final loaded =
          StandardProcessingRecipeBuilder(
              'create:crushing/a',
              CreateRecipeType.crushing,
            )
            ..requireItem('minecraft:cobblestone')
            ..output('minecraft:gravel')
            ..whenModLoaded('create');

      expect((loaded.toJson()['neoforge:conditions'] as List).single, {
        'type': 'neoforge:mod_loaded',
        'modid': 'create',
      });
      expect(parseRecipe('create:crushing/a', loaded.toJson()), isNotNull);

      final missing =
          StandardProcessingRecipeBuilder(
              'create:crushing/b',
              CreateRecipeType.crushing,
            )
            ..requireItem('minecraft:cobblestone')
            ..output('minecraft:gravel')
            ..whenModMissing('create');

      expect(parseRecipe('create:crushing/b', missing.toJson()), isNull);
    });

    test('a sequenced assembly keeps its steps and result pool', () {
      final builder =
          SequencedAssemblyRecipeBuilder(
              'create:sequenced_assembly/precision_mechanism',
            )
            ..requireItem('minecraft:iron_ingot')
            ..transitionTo('create:incomplete_precision_mechanism')
            ..addStep(
              CreateRecipeType.deploying,
              (step) => step.requireItem('create:brass_sheet'),
            )
            ..addStep(CreateRecipeType.pressing, (step) {})
            ..addOutput('create:precision_mechanism')
            ..withLoops(2);

      final recipe = builder.build();
      expect(recipe.sequence, hasLength(2));
      expect(recipe.loops, 2);
      expect(recipe.resultPool.single.item, 'create:precision_mechanism');
      expect(recipe.sequence.first.recipe.ingredients, hasLength(2));

      final json = builder.toJson();
      expect(json['type'], 'create:sequenced_assembly');
      expect(json['loops'], 2);
      expect((json['sequence'] as List), hasLength(2));

      final parsed = parseRecipe(
        'create:sequenced_assembly/precision_mechanism',
        json,
      )!;
      expect(parsed, isA<SequencedAssemblyRecipe>());
      final assembly = parsed as SequencedAssemblyRecipe;
      expect(assembly.sequence, hasLength(2));
      expect(assembly.loops, 2);
      expect(assembly.resultPool.single.item, 'create:precision_mechanism');
    });

    test('an invalid recipe reports its validation errors', () {
      final builder =
          StandardProcessingRecipeBuilder(
              'create:pressing/two_outputs',
              CreateRecipeType.pressing,
            )
            ..requireItem('minecraft:iron_ingot')
            ..output('minecraft:iron_ingot')
            ..output('minecraft:iron_ingot')
            ..output('minecraft:iron_ingot');

      expect(builder.validate(), isNotEmpty);
    });
  });

  group('blaze burner insert result', () {
    test('success and failure values', () {
      expect(InsertResult.success.succeeded, isTrue);
      expect(InsertResult.fail.succeeded, isFalse);
      expect(InsertResult.success.object.isEmpty, isTrue);

      const result = InsertResult(
        InsertResultType.success,
        PStack('minecraft:bucket', 1),
      );
      expect(result.result, InsertResultType.success);
      expect(result.object.key, 'minecraft:bucket');
      expect(result.object.count, 1);
    });
  });
}
