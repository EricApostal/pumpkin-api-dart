// `BasinRecipe.match` / `BasinRecipe.apply` (pure): matching a basin's items and fluids against
// a recipe and consuming/producing them. Used by the basin's operators (mixer, press) and
// testable without the host.
import 'dart:math';

import '../common/stack.dart';
import '../common/storage.dart';
import '../recipe/crafting_recipes.dart';
import '../recipe/heat.dart';
import '../recipe/ingredient.dart';
import '../recipe/recipe.dart';

/// `BasinRecipe.apply` takes any `Recipe`, not just a `BasinRecipe`: the press and the mixer run
/// vanilla crafting recipes too (`matchStaticFilters`). This is that recipe as the basin needs
/// it, over a `create:*` processing recipe or a vanilla crafting recipe.
final class BasinRecipeRef {
  final ProcessingRecipe? processing;
  final CraftingRecipeEntry? crafting;

  const BasinRecipeRef.processing(ProcessingRecipe this.processing)
    : crafting = null;

  const BasinRecipeRef.crafting(CraftingRecipeEntry this.crafting)
    : processing = null;

  /// `recipe.placementInfo().ingredients()` of a crafting recipe, the processing recipe's
  /// ingredients otherwise.
  List<Ingredient> get ingredients =>
      crafting?.ingredients ?? processing!.ingredients;

  /// `recipe instanceof BasinRecipe ? getFluidIngredients() : emptyList()`.
  List<FluidIngredient> get fluidIngredients =>
      processing?.fluidIngredients ?? const [];

  /// `getFluidResults()` (`BasinRecipe` only).
  List<PFluid> get fluidResults => processing?.fluidResults ?? const [];

  /// `getRequiredHeat()`; a crafting recipe is `HeatCondition.NONE`.
  HeatCondition get requiredHeat =>
      processing?.requiredHeat ?? HeatCondition.none;

  /// `BasinRecipe.getResultItem(recipe, registryAccess)`.
  PStack get resultItem => crafting?.result ?? processing!.resultItem;

  /// `ProcessingRecipe.getProcessingDuration()`; `StandardProcessingRecipe` only, so 0 for a
  /// crafting recipe (the mixer's `processingTicks` then uses a recipe speed of 1).
  int get processingDuration => processing?.processingDuration ?? 0;

  /// `recipe.rollResults(random)`; a crafting recipe always assembles the same item
  /// (`getResultItem`), empty or not.
  List<PStack> rollResults(Random random) => crafting != null
      ? [crafting!.result]
      : processing!.rollResults(random);

  /// `BasinRecipe.apply` only takes the remaining items of a `CraftingRecipe`
  /// (`CraftingRecipe.getRemainingItems(remainderInput)`); a processing recipe produces none.
  List<PStack> remainingItemsFor(List<PStack> consumed) =>
      crafting?.remainingItemsFor(consumed) ?? const [];

  /// Whether this is the vanilla crafting kind (for the filter and the outputs).
  bool get isCrafting => crafting != null;

  @override
  String toString() => crafting?.toString() ?? processing!.toString();
}

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
    BasinRecipeRef recipe,
    TagLookup tags,
    Random random,
  ) {
    var filterTest = host.filterAccepts(recipe.resultItem);
    // A `BasinRecipe` with only fluid results is filtered by its first fluid.
    final processing = recipe.processing;
    if (processing != null &&
        processing.results.isEmpty &&
        recipe.fluidResults.isNotEmpty) {
      filterTest = host.filterAcceptsFluid(recipe.fluidResults.first);
    }
    if (!filterTest) return false;
    if (!recipe.requiredHeat.testBlazeBurner(host.heatLevel)) return false;
    return apply(host, recipe, tags, random, test: true);
  }

  /// `BasinRecipe.apply(basin, recipe)`.
  static bool apply(
    BasinRecipeHost host,
    BasinRecipeRef recipe,
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
      // `DummyCraftingContainer(availableItems, extractedItemsFromSlot)`: the consumed items in
      // extraction order, which the crafting remainders are taken from.
      final consumed = <PStack>[];

      for (final ingredient in recipe.ingredients) {
        if (!_extractIngredient(
          items,
          ingredient,
          tags,
          extractedItems,
          simulate,
          consumed,
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
        // `CraftingRecipe.getRemainingItems(remainderInput)`: only a crafting recipe has them.
        for (final remainder in recipe.remainingItemsFor(consumed)) {
          if (remainder.isNotEmpty) outputItems.add(remainder);
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
    List<PStack> consumed,
  ) {
    for (var slot = 0; slot < items.slots; slot++) {
      final stack = items.stackIn(slot);
      if (simulate && stack.count <= extractedFromSlot[slot]) continue;
      final extracted = items.extract(slot, 1, simulate: true);
      if (extracted.isEmpty || !ingredient.test(extracted, tags)) continue;
      if (!simulate) items.extract(slot, 1);
      extractedFromSlot[slot]++;
      consumed.add(extracted);
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
