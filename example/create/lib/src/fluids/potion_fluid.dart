// `PotionFluidHandler` (the item side): which items are potion bottles, what
// fluid they hold and what bottle a potion fluid fills. The potion contents of
// a bottle cannot be read through the host, so a bottle's potion travels with
// the fluid data and a plain water bottle is recognised by its item.
import 'fluid_helper.dart';
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

/// `PotionFluid.PotionFluidType`: the `FluidType` of the potion fluid. Its server side is the
/// default type (density and viscosity 1000, no block); the tint and the description id are
/// derived from the potion data that travels with the stack.
final class PotionFluidType {
  const PotionFluidType();

  /// The `FluidType.Properties` of the Java type: no overrides.
  static const FluidTypeInfo info = FluidTypeInfo();

  /// `TintedFluidType.NO_TINT`.
  static const int noTint = 0xFFFFFFFF;

  /// `FluidTintSource.colorAsStack`: the color of the potion contents.
  int tintColor(FStack fluid) {
    final data = PotionFluidData.decode(fluid.data);
    if (data == null) return noTint;
    return _potionColors[data.potion] ?? noTint;
  }

  /// `getDescriptionId(stack)`: the bottle's description id and the potion.
  String descriptionId(FStack fluid) {
    final data = PotionFluidData.decode(fluid.data);
    final potion = data?.potion ?? 'minecraft:water';
    final bottle = (data?.bottle ?? BottleType.regular).itemKey;
    return '${bottle.replaceAll(':', '.')}.effect.${potion.replaceAll(':', '.')}';
  }

  /// The colors of the base game potions (`PotionContents.getColor` without custom effects).
  static const Map<String, int> _potionColors = {
    'minecraft:water': 0xFF3F76E4,
    'minecraft:night_vision': 0xFF1F1FA1,
    'minecraft:long_night_vision': 0xFF1F1FA1,
    'minecraft:invisibility': 0xFF7F8392,
    'minecraft:long_invisibility': 0xFF7F8392,
    'minecraft:leaping': 0xFF22FF4C,
    'minecraft:long_leaping': 0xFF22FF4C,
    'minecraft:strong_leaping': 0xFF22FF4C,
    'minecraft:fire_resistance': 0xFFFF9900,
    'minecraft:long_fire_resistance': 0xFFFF9900,
    'minecraft:swiftness': 0xFF7CAFC6,
    'minecraft:long_swiftness': 0xFF7CAFC6,
    'minecraft:strong_swiftness': 0xFF7CAFC6,
    'minecraft:slowness': 0xFF5A6C81,
    'minecraft:long_slowness': 0xFF5A6C81,
    'minecraft:strong_slowness': 0xFF5A6C81,
    'minecraft:water_breathing': 0xFF2E5299,
    'minecraft:long_water_breathing': 0xFF2E5299,
    'minecraft:healing': 0xFFF82423,
    'minecraft:strong_healing': 0xFFF82423,
    'minecraft:harming': 0xFF430A09,
    'minecraft:strong_harming': 0xFF430A09,
    'minecraft:poison': 0xFF4E9331,
    'minecraft:long_poison': 0xFF4E9331,
    'minecraft:strong_poison': 0xFF4E9331,
    'minecraft:regeneration': 0xFFCD5CAB,
    'minecraft:long_regeneration': 0xFFCD5CAB,
    'minecraft:strong_regeneration': 0xFFCD5CAB,
    'minecraft:strength': 0xFF932423,
    'minecraft:long_strength': 0xFF932423,
    'minecraft:strong_strength': 0xFF932423,
    'minecraft:weakness': 0xFF484D48,
    'minecraft:long_weakness': 0xFF484D48,
    'minecraft:luck': 0xFF339900,
    'minecraft:slow_falling': 0xFFF7F7F7,
    'minecraft:long_slow_falling': 0xFFF7F7F7,
    'minecraft:turtle_master': 0xFF44FFAA,
    'minecraft:long_turtle_master': 0xFF44FFAA,
    'minecraft:strong_turtle_master': 0xFF44FFAA,
    'minecraft:wind_charged': 0xFFBDC9FF,
    'minecraft:weaving': 0xFF786297,
    'minecraft:oozing': 0xFF99FFA3,
    'minecraft:infested': 0xFF8C9B8C,
  };
}
