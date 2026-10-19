// `BasinRecipe.match` / `BasinRecipe.apply` (pure): matching a basin's items and fluids against
// a processing recipe and consuming/producing them. Used by the basin's operators (mixer,
// press) and testable without the host.
import 'dart:math';

import '../common/stack.dart';
import '../common/storage.dart';
import '../recipe/heat.dart';
import '../recipe/ingredient.dart';
import '../recipe/recipe.dart';

/// What a basin offers to [BasinRecipeOps] (implemented by `BasinBlockEntity`).
abstract interface class BasinRecipeHost {
  /// `CombinedItemHandler(inputInventory, outputInventory)`: the item handler of
  /// `TransferUtil.getItemHandler(level, pos, null)`.
  ItemStorage get recipeItems;

  /// The tanks of the combined fluid handler (`outputTank` first, then `inputTank`), each as a
  /// single-tank storage so the recipe can drain one tank at a time.
  List<FluidStorage> get recipeFluidTanks;

  /// `BasinBlockEntity.getHeatLevel()`: the heat of the block below.
  HeatLevel get heatLevel;

  /// The recipe filter's answer for an item result.
  bool filterAccepts(PStack stack);

  /// The recipe filter's answer for a fluid result.
  bool filterAcceptsFluid(PFluid fluid);

  /// `BasinBlockEntity.acceptOutputs`.
  bool acceptOutputs(
    List<PStack> items,
    List<PFluid> fluids, {
    required bool simulate,
  });
}

/// `BasinRecipe`.
abstract final class BasinRecipeOps {
  /// `BasinRecipe.match(basin, recipe)`.
  static bool matches(
    BasinRecipeHost host,
    ProcessingRecipe recipe,
    TagLookup tags,
    Random random,
  ) {
    var filterTest = host.filterAccepts(recipe.resultItem);
    // A recipe with only fluid results is filtered by its first fluid.
    if (recipe.results.isEmpty && recipe.fluidResults.isNotEmpty) {
      filterTest = host.filterAcceptsFluid(recipe.fluidResults.first);
    }
    if (!filterTest) return false;
    if (!recipe.requiredHeat.testBlazeBurner(host.heatLevel)) return false;
    return apply(host, recipe, tags, random, test: true);
  }

  /// `BasinRecipe.apply(basin, recipe)`.
  static bool apply(
    BasinRecipeHost host,
    ProcessingRecipe recipe,
    TagLookup tags,
    Random random, {
    required bool test,
  }) {
    final items = host.recipeItems;
    final tanks = host.recipeFluidTanks;
    final outputItems = <PStack>[];
    final outputFluids = <PFluid>[];

    // First the simulated pass, then the real one (`Iterate.trueAndFalse`). A match test stops
    // after the simulated pass succeeded, like Java's `if (!simulate && test) return true`.
    for (final simulate in [true, false]) {
      if (!simulate && test) return true;

      // Java re-creates the extracted counters for every pass.
      final extractedItems = List<int>.filled(items.slots, 0);
      final extractedFluids = List<int>.filled(tanks.length, 0);

      for (final ingredient in recipe.ingredients) {
        if (!_extractIngredient(
          items,
          ingredient,
          tags,
          extractedItems,
          simulate,
        ))
          return false;
      }
      for (final fluidIngredient in recipe.fluidIngredients) {
        if (!_extractFluid(
          tanks,
          fluidIngredient,
          tags,
          extractedFluids,
          simulate,
        ))
          return false;
      }

      if (simulate) {
        for (final stack in recipe.rollResults(random)) {
          if (stack.isNotEmpty) outputItems.add(stack);
        }
        for (final fluid in recipe.fluidResults) {
          if (fluid.isNotEmpty) outputFluids.add(fluid);
        }
      }

      if (!host.acceptOutputs(outputItems, outputFluids, simulate: simulate))
        return false;
    }
    return true;
  }

  /// One item of [ingredient] from the first slot that has one (Java's `Ingredients:` loop).
  static bool _extractIngredient(
    ItemStorage items,
    Ingredient ingredient,
    TagLookup tags,
    List<int> extractedFromSlot,
    bool simulate,
  ) {
    for (var slot = 0; slot < items.slots; slot++) {
      final stack = items.stackIn(slot);
      if (simulate && stack.count <= extractedFromSlot[slot]) continue;
      final extracted = items.extract(slot, 1, simulate: true);
      if (extracted.isEmpty || !ingredient.test(extracted, tags)) continue;
      if (!simulate) items.extract(slot, 1);
      extractedFromSlot[slot]++;
      return true;
    }
    return false;
  }

  /// [amount] millibuckets of [ingredient] from the tanks, in handler order.
  static bool _extractFluid(
    List<FluidStorage> tanks,
    FluidIngredient ingredient,
    TagLookup tags,
    List<int> extractedFromTank,
    bool simulate,
  ) {
    var remaining = ingredient.amount;
    for (var tank = 0; tank < tanks.length; tank++) {
      final storage = tanks[tank];
      final fluid = storage.fluidIn(0);
      final available = fluid.amount - extractedFromTank[tank];
      if (available <= 0 || !ingredient.testFluid(fluid, tags)) continue;
      final drained = remaining < available ? remaining : available;
      if (drained <= 0) continue;
      if (!simulate) storage.drainAny(drained);
      remaining -= drained;
      extractedFromTank[tank] += drained;
      if (remaining == 0) return true;
    }
    return false;
  }
}
