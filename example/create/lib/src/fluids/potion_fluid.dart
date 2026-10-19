// `PotionFluidHandler` (the item side): which items are potion bottles, what
// fluid they hold and what bottle a potion fluid fills. The potion contents of
// a bottle cannot be read through the host, so a bottle's potion travels with
// the fluid data and a plain water bottle is recognised by its item.
import 'fluid_stack.dart';
import 'generic_item_fluid.dart';
import 'potion_data.dart';

abstract final class PotionFluidHandler {
  /// `PotionFluidHandler.SUPPORTED_CONTAINERS` / `isPotionItem`.
  static const Set<String> potionItems = {
    'minecraft:potion',
    'minecraft:splash_potion',
    'minecraft:lingering_potion',
  };

  static bool isPotionItem(String itemKey) => potionItems.contains(itemKey);

  /// `getRequiredAmountForFilledBottle`.
  static int get requiredAmountForFilledBottle =>
      PotionFluids.requiredAmountForFilledBottle();

  /// `getFluidFromPotionItem`: 250 mB of the bottle's fluid.
  static FStack getFluidFromPotionItem(FluidItemSpec item) =>
      GenericItemEmptying.potionItemFluid(item.key);

  /// `emptyPotion`: the fluid of one bottle and the empty glass bottle.
  static (FStack, FluidItemSpec) emptyPotion(
    FluidItemSpec stack, {
    required bool simulate,
  }) => (
    getFluidFromPotionItem(stack),
    const FluidItemSpec('minecraft:glass_bottle'),
  );

  /// `fillBottle`: the bottle item a potion fluid fills.
  static FluidItemSpec fillBottle(FStack fluid) =>
      FluidItemSpec(PotionFluids.bottleItemFor(fluid));

  /// The bottle type of an item (`bottleTypeFromItem`).
  static BottleType bottleTypeOf(String itemKey) =>
      BottleType.fromItem(itemKey);
}
