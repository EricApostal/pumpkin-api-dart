// The defects of the processing audit that are pure enough to test on the VM: the deployer's
// sandpaper branch, the basin operators' vanilla crafting filters, the component comparison of
// fluid ingredients (the potion filling recipes) and the manual application of
// `create:item_application` recipes.
import 'dart:convert';
import 'dart:math';

import 'package:create/src/processing/common/stack.dart';
import 'package:create/src/processing/deployer/deployer_items.dart';
import 'package:create/src/processing/deployer/manual_application_recipes.dart';
import 'package:create/src/processing/recipe/crafting_recipes.dart';
import 'package:create/src/processing/recipe/ingredient.dart';
import 'package:create/src/processing/recipe/output.dart';
import 'package:create/src/processing/recipe/recipe.dart';
import 'package:create/src/processing/recipe/recipe_book.dart';
import 'package:create/src/processing/recipe/recipe_type.dart';
import 'package:test/test.dart';

const tags = MapTagLookup(
  items: {
    'c:stripped_logs': {'minecraft:stripped_oak_log'},
  },
);

/// The `create:potion_contents` component of a potion fluid, as `PotionFluidData`
/// (`componentEntries`) writes it: the UTF-8 JSON of the codec form.
List<int> potionContents(String potion) =>
    utf8.encode(jsonEncode({'potion': potion}));

List<int> bottleType(String name) => utf8.encode(jsonEncode(name));

void main() {
  group('the deployer sandpaper branch', () {
    test('the two SandPaperItems are recognised, the tag name is not', () {
      // `DeployerBlockEntity.getRecipe`: `heldItem.getItem() instanceof SandPaperItem`
      // (`AllItems.java:387-395`); `create:sandpaper` is the tag of the two items.
      expect(isSandPaperItem(const PStack('create:sand_paper', 1)), isTrue);
      expect(isSandPaperItem(const PStack('create:red_sand_paper', 1)), isTrue);
      expect(isSandPaperItem(const PStack('create:sandpaper', 1)), isFalse);
    });
  });

  group('compressible squares (the press and the mixer)', () {
    CraftingRecipeEntry entry(List<Ingredient> ingredients, {bool shaped = true}) =>
        CraftingRecipeEntry(
          id: 'test',
          shaped: shaped,
          ingredients: ingredients,
          result: const PStack('minecraft:slime_block', 1),
        );

    test('a 2x2 or 3x3 square of one ingredient compresses', () {
      final nine = entry([for (var i = 0; i < 9; i++) Ingredient.item('minecraft:iron_ingot')]);
      final four = entry([for (var i = 0; i < 4; i++) Ingredient.item('minecraft:sand')]);
      expect(nine.isCompressibleSquare, isTrue);
      expect(four.isCompressibleSquare, isTrue);
    });

    test('mixed or non-square recipes do not', () {
      final mixed = entry([
        Ingredient.item('minecraft:iron_ingot'),
        Ingredient.item('minecraft:gold_ingot'),
        Ingredient.item('minecraft:iron_ingot'),
        Ingredient.item('minecraft:iron_ingot'),
      ]);
      final two = entry([
        Ingredient.item('minecraft:iron_ingot'),
        Ingredient.item('minecraft:iron_ingot'),
      ]);
      expect(mixed.isCompressibleSquare, isFalse);
      expect(two.isCompressibleSquare, isFalse);
    });

    test('the cache collects the squares of both tables', () {
      // Java's `canCompress` asks the placement ingredients, which a shapeless recipe has too.
      final cache = CraftingRecipeCache()
        ..shaped = [
          entry([for (var i = 0; i < 9; i++) Ingredient.item('minecraft:iron_ingot')]),
          entry([
            Ingredient.item('minecraft:stick'),
            Ingredient.item('minecraft:stick'),
          ]),
        ]
        ..shapeless = [
          entry(
            [for (var i = 0; i < 4; i++) Ingredient.item('minecraft:sand')],
            shaped: false,
          ),
        ];
      expect(cache.compressibleSquares.length, 2);
      expect(
        cache.compressibleSquares.last.result.key,
        'minecraft:slime_block',
      );
    });
  });

  group('fluid ingredient components', () {
    // The three `create:filling` potion recipes differ only in these components
    // (`data/create/recipe/filling/{glowstone,gunpowder,redstone}.json`).
    final nightVision = FluidIngredient(
      fluids: const ['create:potion'],
      amount: 25,
      components: const {
        'create:potion_fluid_bottle_type': 'regular',
        'minecraft:potion_contents': {'potion': 'minecraft:night_vision'},
      },
    );

    PFluid potion(String name) => PFluid(
      'create:potion',
      25,
      comps: [
        ('create:potion_fluid_bottle_type', bottleType('regular')),
        ('minecraft:potion_contents', potionContents(name)),
      ],
    );

    test('the potion decides which recipe applies', () {
      expect(nightVision.test(potion('minecraft:night_vision'), tags), isTrue);
      expect(nightVision.test(potion('minecraft:harming'), tags), isFalse);
      expect(nightVision.test(potion('minecraft:strength'), tags), isFalse);
    });

    test('a fluid without the components never matches', () {
      // What the port did before: only the fluid key was compared.
      expect(nightVision.test(const PFluid('create:potion', 25), tags), isFalse);
    });

    test('the bottle type is compared too', () {
      final splash = PFluid(
        'create:potion',
        25,
        comps: [
          ('create:potion_fluid_bottle_type', bottleType('splash')),
          ('minecraft:potion_contents', potionContents('minecraft:night_vision')),
        ],
      );
      expect(nightVision.test(splash, tags), isFalse);
    });

    test('an ingredient without components still matches any potion', () {
      const plain = FluidIngredient(fluids: ['create:potion'], amount: 25);
      expect(plain.test(potion('minecraft:strength'), tags), isTrue);
    });

    test('the required amount is still checked', () {
      expect(
        nightVision.test(potion('minecraft:night_vision').withAmount(24), tags),
        isFalse,
      );
    });
  });

  group('manual application', () {
    final book = RecipeBook(tags)
      ..add(
        const ProcessingRecipe(
          id: 'create:item_application/andesite_casing_from_log',
          type: CreateRecipeType.itemApplication,
          ingredients: [
            Ingredient.tag('c:stripped_logs'),
            Ingredient.item('create:andesite_alloy'),
          ],
          results: [ProcessingOutput('create:andesite_casing')],
        ),
      );

    final strippedLog = PStack('minecraft:stripped_oak_log', 1);
    final alloy = PStack('create:andesite_alloy', 1);

    test('the item form of the block and the held item are the two ingredients', () {
      final recipe = ManualApplicationRecipes.findRecipe(book, tags, strippedLog, alloy);
      expect(recipe?.id, 'create:item_application/andesite_casing_from_log');
      // The wrong tool, or a block the recipe does not know.
      expect(
        ManualApplicationRecipes.findRecipe(book, tags, strippedLog, const PStack('create:zinc_ingot', 1)),
        isNull,
      );
      expect(
        ManualApplicationRecipes.findRecipe(book, tags, const PStack('minecraft:stone', 1), alloy),
        isNull,
      );
    });

    test('the block key of the item is the manifest block item', () {
      // `in.getBlock().asItem()`: a `create:*` block item is named after its block.
      expect(
        ManualApplicationRecipes.blockItemKey('create:andesite_casing'),
        'create:andesite_casing',
      );
    });

    test('a block result transforms the block, a non-block result is air', () {
      const casing = ProcessingRecipe(
        id: 'a',
        type: CreateRecipeType.itemApplication,
        results: [ProcessingOutput('create:andesite_casing')],
      );
      const notABlock = ProcessingRecipe(
        id: 'b',
        type: CreateRecipeType.itemApplication,
        results: [ProcessingOutput('minecraft:gunpowder', count: 4)],
      );
      expect(ManualApplicationRecipes.transformedBlock(casing, Random(1)), 'create:andesite_casing');
      expect(ManualApplicationRecipes.transformedBlock(notABlock, Random(1)), isNull);
    });

    test('the rolled items skip the block of the first result', () {
      // `getRollableResultsExceptBlock`: the block is placed, not popped.
      const recipe = ProcessingRecipe(
        id: 'a',
        type: CreateRecipeType.itemApplication,
        results: [
          ProcessingOutput('create:andesite_casing'),
          ProcessingOutput('minecraft:gunpowder', count: 2),
        ],
      );
      final rolled = ManualApplicationRecipes.rolledItems(
        recipe,
        Random(1),
        'create:andesite_casing',
      );
      expect(rolled.length, 1);
      expect(rolled.single.key, 'minecraft:gunpowder');
      expect(rolled.single.count, 2);
    });

    test('a non-block result is rolled with the items', () {
      const recipe = ProcessingRecipe(
        id: 'a',
        type: CreateRecipeType.itemApplication,
        results: [ProcessingOutput('minecraft:gunpowder', count: 2)],
      );
      final rolled = ManualApplicationRecipes.rolledItems(recipe, Random(1), null);
      expect(rolled.single.key, 'minecraft:gunpowder');
    });
  });
}