import 'dart:math';

import 'package:create/src/processing/basin/basin_recipe_ops.dart';
import 'package:create/src/processing/common/stack.dart';
import 'package:create/src/processing/common/storage.dart';
import 'package:create/src/processing/recipe/crafting_recipes.dart';
import 'package:create/src/processing/recipe/heat.dart';
import 'package:create/src/processing/recipe/ingredient.dart';
import 'package:create/src/processing/recipe/output.dart';
import 'package:create/src/processing/recipe/recipe.dart';
import 'package:create/src/processing/recipe/recipe_type.dart';
import 'package:test/test.dart';

const tags = MapTagLookup();

/// A basin without the host: an input and an output inventory and two tanks.
final class TestBasin implements BasinRecipeHost {
  final SmartInventory input = SmartInventory(2);
  final SmartInventory output = SmartInventory(2);
  final SmartFluidTank inputTank = SmartFluidTank(1000);
  final SmartFluidTank outputTank = SmartFluidTank(1000);

  HeatLevel heat = HeatLevel.kindled;
  PStack filter = PStack.empty;

  @override
  ItemStorage get recipeItems => CombinedStorage([input, output]);

  @override
  List<FluidStorage> get recipeFluidTanks => [outputTank, inputTank];

  @override
  HeatLevel get heatLevel => heat;

  @override
  bool filterAccepts(PStack stack) =>
      filter.isEmpty ||
      (stack.isNotEmpty && filter.sameItemSameComponents(stack));

  @override
  bool filterAcceptsFluid(PFluid fluid) =>
      filter.isEmpty ||
      filter.key == fluid.key ||
      filter.key == '${fluid.key}_bucket';

  @override
  bool acceptOutputs(
    List<PStack> items,
    List<PFluid> fluids, {
    required bool simulate,
  }) {
    for (final stack in items) {
      if (ItemStorages.insertStacked(
        output,
        stack,
        simulate: simulate,
      ).isNotEmpty)
        return false;
    }
    for (final fluid in fluids) {
      if (outputTank.fill(fluid, simulate: simulate) != fluid.amount)
        return false;
    }
    return true;
  }
}

final recipe = BasinRecipeRef.processing(
  ProcessingRecipe(
    id: 'create:mixing/test',
    type: CreateRecipeType.mixing,
    ingredients: const [Ingredient.item('minecraft:sand')],
    fluidIngredients: const [
      FluidIngredient(fluids: ['minecraft:water'], amount: 250),
    ],
    results: const [ProcessingOutput('minecraft:clay')],
    requiredHeat: HeatCondition.heated,
  ),
);

void main() {
  TestBasin basin() {
    final b = TestBasin();
    b.input.insert(0, const PStack('minecraft:sand', 2));
    b.inputTank.fill(const PFluid('minecraft:water', 1000));
    return b;
  }

  group('basin recipes', () {
    test('a heated recipe needs a lit burner at least fading', () {
      final b = basin();
      expect(BasinRecipeOps.matches(b, recipe, tags, Random(0)), isTrue);

      b.heat = HeatLevel.smouldering;
      expect(BasinRecipeOps.matches(b, recipe, tags, Random(0)), isFalse);

      b.heat = HeatLevel.seething;
      expect(BasinRecipeOps.matches(b, recipe, tags, Random(0)), isTrue);
    });

    test('the filter tests the result item', () {
      final b = basin();
      b.filter = const PStack('minecraft:stone', 1);
      expect(BasinRecipeOps.matches(b, recipe, tags, Random(0)), isFalse);

      b.filter = const PStack('minecraft:clay', 1);
      expect(BasinRecipeOps.matches(b, recipe, tags, Random(0)), isTrue);
    });

    test('applying consumes the inputs and stores the outputs', () {
      final b = basin();
      expect(
        BasinRecipeOps.apply(b, recipe, tags, Random(0), test: false),
        isTrue,
      );

      expect(b.input.stackIn(0).count, 1);
      expect(b.inputTank.fluid.amount, 750);
      expect(b.output.stackIn(0), const PStack('minecraft:clay', 1));

      expect(
        BasinRecipeOps.apply(b, recipe, tags, Random(0), test: false),
        isTrue,
      );
      expect(b.input.stackIn(0).isEmpty, isTrue);
      expect(b.inputTank.fluid.amount, 500);
      expect(b.output.stackIn(0), const PStack('minecraft:clay', 2));

      // No sand left, so no further run matches.
      expect(BasinRecipeOps.matches(b, recipe, tags, Random(0)), isFalse);
    });

    test('a missing fluid ingredient does not match', () {
      final b = basin();
      b.inputTank.drainAny(900);
      expect(BasinRecipeOps.matches(b, recipe, tags, Random(0)), isFalse);
    });

    test('a full output inventory refuses the run', () {
      final b = basin();
      b.output.insert(0, const PStack('minecraft:stone', 64));
      b.output.insert(1, const PStack('minecraft:dirt', 64));
      expect(BasinRecipeOps.matches(b, recipe, tags, Random(0)), isFalse);
      expect(b.input.stackIn(0).count, 2);
    });
  });

  group('vanilla crafting recipes in a basin', () {
    // `minecraft:iron_block`: a 3x3 square of iron ingots, which the press compresses.
    final ironBlock = BasinRecipeRef.crafting(
      CraftingRecipeEntry(
        id: 'minecraft:crafting_shaped/iron_block',
        shaped: true,
        ingredients: [
          for (var i = 0; i < 9; i++) const Ingredient.item('minecraft:iron_ingot'),
        ],
        result: const PStack('minecraft:iron_block', 1),
      ),
    );

    // `minecraft:bread`: three wheat, a shapeless recipe the mixer mixes.
    final bread = BasinRecipeRef.crafting(
      const CraftingRecipeEntry(
        id: 'minecraft:crafting_shapeless/bread',
        shaped: false,
        ingredients: [
          Ingredient.item('minecraft:wheat'),
          Ingredient.item('minecraft:wheat'),
          Ingredient.item('minecraft:wheat'),
        ],
        result: PStack('minecraft:bread', 1),
      ),
    );

    test('a square of one ingredient is a compressible square', () {
      expect(
        CraftingRecipeEntry(
          id: 'test:square',
          shaped: true,
          ingredients: ironBlock.ingredients,
          result: const PStack('minecraft:iron_block', 1),
        ).isCompressibleSquare,
        isTrue,
      );
      expect(
        CraftingRecipeEntry(
          id: 'test:bread',
          shaped: false,
          ingredients: bread.ingredients,
          result: const PStack('minecraft:bread', 1),
        ).isCompressibleSquare,
        isFalse,
      );
    });

    test('the square consumes one item per cell and produces the result', () {
      final b = TestBasin();
      b.input.insert(0, const PStack('minecraft:iron_ingot', 10));

      expect(BasinRecipeOps.matches(b, ironBlock, tags, Random(0)), isTrue);
      expect(
        BasinRecipeOps.apply(b, ironBlock, tags, Random(0), test: false),
        isTrue,
      );
      expect(b.input.stackIn(0).count, 1);
      expect(b.output.stackIn(0), const PStack('minecraft:iron_block', 1));

      // One ingot left is not enough for a second run.
      expect(BasinRecipeOps.matches(b, ironBlock, tags, Random(0)), isFalse);
    });

    test('a shapeless recipe consumes one item per ingredient', () {
      final b = TestBasin();
      b.input.insert(0, const PStack('minecraft:wheat', 3));

      expect(BasinRecipeOps.matches(b, bread, tags, Random(0)), isTrue);
      expect(
        BasinRecipeOps.apply(b, bread, tags, Random(0), test: false),
        isTrue,
      );
      expect(b.input.stackIn(0).isEmpty, isTrue);
      expect(b.output.stackIn(0), const PStack('minecraft:bread', 1));
    });

    test('a crafting recipe needs no heat', () {
      final b = TestBasin();
      b.input.insert(0, const PStack('minecraft:wheat', 3));
      b.heat = HeatLevel.none;
      expect(BasinRecipeOps.matches(b, bread, tags, Random(0)), isTrue);
    });
  });
}
