/// The public API of the processing module (published by `processing`): Create's machines,
/// recipes and sequenced assembly. Import as `package:create/src/api/processing.dart`.
///
/// ```dart
/// final book = ctx.services.require<RecipeBook>();            // all create:* recipes
/// final match = book.findForInput(CreateRecipeType.crushing, PStack('create:zinc_ore', 1));
/// final results = match?.rollResults(random);                  // honours sequenced assembly
/// final storage = ctx.services.require<StorageLookup>();      // machine / host item storage
/// ```
///
/// * Recipes: [RecipeBook], [ProcessingRecipe], [MechanicalCraftingRecipe],
///   [SequencedAssemblyRecipe], [CreateRecipeType], ingredients and outputs, [HeatCondition].
/// * Values: [PStack] / [PFluid] (item and fluid stacks), [ItemStorage] / [FluidStorage],
///   [SmartInventory], [SmartFluidTank].
/// * Conveyance contract: [TransportedItemStack], [BeltProcessingBehaviour],
///   [TransportedItemStackHandlerBehaviour], [DirectBeltInputBehaviour]. Belts, funnels and chutes
///   (conveyance module) implement the handler / input behaviours; the machines of this module use
///   the processing behaviour.
/// * [StorageLookup], [ItemStorageProvider], [FluidStorageProvider]: capabilities.
/// * Per machine API: see the exports below.
library;

export 'boiler/blaze_burner_fuel.dart';
export 'data/all_ingredients.dart';
export 'data/all_triggers.dart';
export '../processing/common/capabilities.dart';
export '../processing/common/stack.dart';
export '../processing/common/storage.dart';
export '../processing/host/stack_host.dart' show HostStacks, StackNbt;
export '../processing/host/storage_lookup.dart' show StorageLookup;
export '../processing/processing_module.dart' show ProcessingModule;
export '../processing/processing_part.dart' show ProcessingPart;
export '../processing/processing_runtime.dart' show ProcessingRuntime;
export '../processing/processing_settings.dart' show ProcessingSettings;
export '../processing/recipe/conditions.dart';
export '../processing/recipe/heat.dart';
export '../processing/recipe/ingredient.dart';
export '../processing/recipe/output.dart';
export '../processing/recipe/recipe.dart';
export '../processing/recipe/recipe_applier.dart';
export '../processing/recipe/recipe_book.dart';
export '../processing/recipe/recipe_json.dart'
    show RecipeParseException, parseIngredient, parseOutput, parseRecipe;
export '../processing/recipe/recipe_type.dart';
export '../processing/recipe/sequenced.dart';
export '../processing/sequenced_items.dart'
    show sequencedAssemblyItemKeys, sequencedBarColor, sequencedBarWidth;
export '../processing/transport/transport_behaviours.dart';
export '../processing/transport/transported_stack.dart';
// Per machine families (each file is owned by its part):
export '../processing/arm/api.dart';
export '../processing/basin/api.dart';
export '../processing/burner/api.dart';
export '../processing/crafter/api.dart';
export '../processing/crusher/api.dart';
export '../processing/depot/api.dart';
export '../processing/deployer/api.dart';
export '../processing/drill/api.dart';
export '../processing/fan/api.dart';
export '../processing/millstone/api.dart';
export '../processing/mixer/api.dart';
export '../processing/press/api.dart';
export '../processing/saw/api.dart';
