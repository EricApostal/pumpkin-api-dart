// `PotionMixingRecipes` (pure): mirrors the brewing recipes between potion
// bottles as heated `create:mixing` recipes. Brewing is data driven, so the
// recipes are generated from a list of [BrewingRecipeSpec]s. The host exposes
// no brewing recipe query, so the module cannot feed this generator on its own;
// it is the pure part of the port, ready for a source of brewing recipes.
import '../processing/common/stack.dart';
import '../processing/recipe/heat.dart';
import '../processing/recipe/ingredient.dart';
import '../processing/recipe/recipe.dart';
import '../processing/recipe/recipe_type.dart';
import 'fluid_stack.dart';
import 'potion_data.dart';
import 'potion_fluid.dart';

/// One brewing recipe (`BrewingRecipe`): the potion input and the reagent make
/// the output bottle.
final class BrewingRecipeSpec {
  /// The output bottle item (`minecraft:potion`, splash or lingering).
  final String outputItem;

  /// The potion of the output (`minecraft:healing`).
  final String outputPotion;

  /// The reagent item (`minecraft:glowstone_dust`).
  final String reagent;

  /// The bottle items the input accepts.
  final List<String> inputItems;

  /// The potions the input accepts (empty means all potions).
  final List<String> inputPotions;

  const BrewingRecipeSpec({
    required this.outputItem,
    required this.outputPotion,
    required this.reagent,
    this.inputItems = const [
      'minecraft:potion',
      'minecraft:splash_potion',
      'minecraft:lingering_potion',
    ],
    this.inputPotions = const [],
  });
}

abstract final class PotionMixingRecipes {
  /// `PotionMixingRecipes.SUPPORTED_CONTAINERS`.
  static const List<String> supportedContainers = [
    'minecraft:potion',
    'minecraft:splash_potion',
    'minecraft:lingering_potion',
  ];

  /// `createRecipes`: one heated mixing recipe per brewing recipe, input bottle
  /// and input potion, with 1000 mB of potion fluid on both sides.
  static List<ProcessingRecipe> createRecipes(
    Iterable<BrewingRecipeSpec> brewing,
  ) {
    final recipes = <ProcessingRecipe>[];
    var index = 0;
    for (final spec in brewing) {
      if (!supportedContainers.contains(spec.outputItem)) continue;
      final outputFluid = PotionFluidData(
        spec.outputPotion,
        bottle: BottleType.fromItem(spec.outputItem),
      ).toStack(1000);
      for (final inputItem in spec.inputItems) {
        if (!supportedContainers.contains(inputItem)) continue;
        final bottle = BottleType.fromItem(inputItem);
        final potions = spec.inputPotions.isEmpty
            ? const ['minecraft:water']
            : spec.inputPotions;
        for (final potion in potions) {
          final inputFluid = PotionFluids.fluidFromPotion(
            PotionFluidData(potion, bottle: bottle),
            1000,
          );
          recipes.add(
            ProcessingRecipe(
              id: 'create:potion_mixing_${index++}',
              type: CreateRecipeType.mixing,
              ingredients: [Ingredient.item(spec.reagent)],
              fluidIngredients: [
                FluidIngredient(fluids: [inputFluid.fluid], amount: 1000),
              ],
              fluidResults: [PFluid(outputFluid.fluid, 1000)],
              requiredHeat: HeatCondition.heated,
            ),
          );
        }
      }
    }
    return recipes;
  }

  /// The recipes grouped by the item they can be started with
  /// (`sortRecipesByItem`).
  static Map<String, List<ProcessingRecipe>> sortByItem(
    List<ProcessingRecipe> recipes,
  ) {
    final byItem = <String, List<ProcessingRecipe>>{};
    for (final recipe in recipes) {
      final seen = <String>{};
      for (final ingredient in recipe.ingredients) {
        for (final entry in ingredient.entries) {
          final item = entry.item;
          if (item == null) continue;
          if (!seen.add(item)) continue;
          byItem.putIfAbsent(item, () => []).add(recipe);
        }
      }
    }
    return byItem;
  }

  /// The fluid key of a potion fluid (`create:potion`, or water).
  static String fluidKeyOf(String potion, String bottleItem) =>
      PotionFluidData(potion, bottle: BottleType.fromItem(bottleItem)).isWater
      ? FluidKeys.water
      : FluidKeys.potion;

  /// Whether [itemKey] is a potion bottle the mixing recipes support.
  static bool isSupportedContainer(String itemKey) =>
      PotionFluidHandler.isPotionItem(itemKey);
}
