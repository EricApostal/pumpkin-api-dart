// `BasinOperatingBlockEntity`: the shared base of the machines that drive a basin two blocks
// below them (the mechanical press and the mechanical mixer). It schedules a deferred basin
// check, finds a matching recipe and applies it, mirroring `BasinOperatingBlockEntity` of
// Create.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../recipe/crafting_recipes.dart';
import '../recipe/recipe_type.dart';
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';
import 'basin_block_entity.dart';
import 'basin_recipe_ops.dart';

abstract class BasinOperatingBlockEntity extends KineticBlockEntity {
  BasinOperatingBlockEntity(super.worldId, super.pos);

  /// `basinRemoved`: set by the basin when it is removed or emptied.
  bool basinRemoved = false;

  /// `DeferralBehaviour basinChecker`: the check runs once in the next tick.
  bool _basinCheckPending = false;

  /// `currentRecipe`: the recipe a running processing cycle applies.
  BasinRecipeRef? currentRecipe;

  /// `basinChecker.scheduleUpdate()`.
  void scheduleBasinCheck() => _basinCheckPending = true;

  @override
  void tick() {
    if (basinRemoved) {
      basinRemoved = false;
      onBasinRemoved();
      sendData();
      return;
    }
    super.tick();
    if (_basinCheckPending) {
      _basinCheckPending = false;
      updateBasin();
    }
  }

  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    // Java sets `basinRemoved = true` for a zero speed and immediately back to false; only the
    // re-check of the basin is left of that.
    basinRemoved = false;
    scheduleBasinCheck();
  }

  /// `updateBasin`: start a new cycle when the basin holds a matching recipe.
  bool updateBasin() {
    if (!isSpeedRequirementFulfilled) return true;
    if (speed == 0) return true;
    if (isRunning()) return true;
    final basin = getBasin();
    if (basin == null || !basin.canContinueProcessing) return true;
    final recipes = getMatchingRecipes();
    if (recipes.isEmpty) return true;
    currentRecipe = recipes.first;
    startProcessingBasin();
    sendData();
    return true;
  }

  /// Whether the machine is in the middle of a cycle.
  bool isRunning();

  /// `startProcessingBasin`.
  void startProcessingBasin() {}

  /// `continueWithPreviousRecipe`: whether a repeated run starts without a new lookup.
  bool continueWithPreviousRecipe() => true;

  /// `matchBasinRecipe(recipe)`.
  bool matchBasinRecipe(BasinRecipeRef? recipe) {
    if (recipe == null) return false;
    final basin = getBasin();
    if (basin == null) return false;
    final rt = ProcessingRuntime.instance;
    return BasinRecipeOps.matches(basin, recipe, rt.recipes.tags, rt.random);
  }

  /// The trigger awarded when a basin cycle completes (`getProcessedRecipeTrigger`): presses
  /// return `COMPACTING`, mixers `MIXER`. `null` for operators with no recipe award.
  String? get processedRecipeAward => null;

  /// Awards [award] for a completed basin cycle (only the trigger path exists on the base type;
  /// the press and the mixer each own their players through `registerAwardables`).
  void onBasinCycleCompleted(String award) {}

  /// `applyBasinRecipe`: consume the inputs and accept the outputs.
  void applyBasinRecipe() {
    final recipe = currentRecipe;
    if (recipe == null) return;
    final basin = getBasin();
    if (basin == null) return;

    final wasEmpty = basin.canContinueProcessing;
    final rt = ProcessingRuntime.instance;
    if (!BasinRecipeOps.apply(
      basin,
      recipe,
      rt.recipes.tags,
      rt.random,
      test: false,
    ))
      return;

    // `getProcessedRecipeTrigger().ifPresent(this::award)`
    // (`BasinOperatingBlockEntity.java:120`): a completed basin cycle (only the success path,
    // after `BasinRecipe.apply` returns true) awards the trigger to the owner.
    final award = processedRecipeAward;
    if (award != null) onBasinCycleCompleted(award);

    // Continue with the same recipe when the inputs allow another run.
    if (wasEmpty && matchBasinRecipe(recipe)) {
      continueWithPreviousRecipe();
      sendData();
    }
    basin.notifyChangeOfContents();
  }

  /// `getMatchingRecipes`: every recipe the basin contents satisfy, longest first.
  ///
  /// Java searches *all* recipes of the level with the machine's `matchStaticFilters`, which for
  /// the press and the mixer also admits vanilla crafting recipes; those come from
  /// [matchingCraftingRecipes], the `create:*` ones from the recipe book.
  List<BasinRecipeRef> getMatchingRecipes() {
    final basin = getBasin();
    if (basin == null || basin.isEmpty) return [];
    final book = ProcessingRuntime.instance.recipes;
    final matches = <BasinRecipeRef>[];
    void consider(BasinRecipeRef ref) {
      if (matchBasinRecipe(ref)) matches.add(ref);
    }

    for (final type in matchingRecipeTypes) {
      for (final recipe in book.ofType(type)) {
        consider(BasinRecipeRef.processing(recipe));
      }
    }
    for (final entry in matchingCraftingRecipes) {
      consider(BasinRecipeRef.crafting(entry));
    }
    // `list.sort((r1, r2) -> r2.placementInfo().ingredients().size() - r1...)`.
    matches.sort((a, b) => b.ingredients.length - a.ingredients.length);
    return matches;
  }

  /// The recipe types this machine runs (`matchStaticFilters`).
  List<CreateRecipeType> get matchingRecipeTypes;

  /// The vanilla crafting recipes this machine runs (`matchStaticFilters`): the press takes the
  /// compressible 2x2 / 3x3 squares, the mixer the shapeless ones.
  List<CraftingRecipeEntry> get matchingCraftingRecipes => const [];

  /// `getBasin()`: the basin two blocks below.
  BasinBlockEntity? getBasin() => store.typed<BasinBlockEntity>(
    worldId,
    BlockPos(x: pos.x, y: pos.y - 2, z: pos.z),
  );

  /// `onBasinRemoved`.
  void onBasinRemoved();
}
