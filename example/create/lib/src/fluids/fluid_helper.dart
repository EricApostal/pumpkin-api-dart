// `FluidHelper` (pure): fluid identity, sounds, the properties the machines look at, and the
// exchange between a tank and an item.
import 'fluid_stack.dart';
import 'fluid_storage.dart';

/// The properties of a fluid type that the fluids module needs (`FluidType`): light, density,
/// whether it fills a world block. Fluids of other mods can be added with [register].
final class FluidTypeInfo {
  final int luminance;

  /// Negative for fluids lighter than air (`FluidType.isLighterThanAir`).
  final int density;
  final int viscosity;
  final int temperature;

  /// The fluid has a block that holds it in the world (`FluidHelper.hasBlockState`).
  final bool hasBlock;

  const FluidTypeInfo({this.luminance = 0, this.density = 1000, this.viscosity = 1000, this.temperature = 300, this.hasBlock = false});
}

abstract final class FluidTypes {
  static final Map<String, FluidTypeInfo> _types = {
    FluidKeys.water: const FluidTypeInfo(hasBlock: true),
    FluidKeys.lava: const FluidTypeInfo(luminance: 15, density: 3000, viscosity: 6000, temperature: 1300, hasBlock: true),
    FluidKeys.milk: const FluidTypeInfo(),
    FluidKeys.potion: const FluidTypeInfo(),
    FluidKeys.tea: const FluidTypeInfo(),
    FluidKeys.honey: const FluidTypeInfo(density: 1400, viscosity: 2000, hasBlock: true),
    FluidKeys.chocolate: const FluidTypeInfo(density: 1400, viscosity: 1500, hasBlock: true),
  };

  /// Registers (or replaces) the type of the still fluid [key].
  static void register(String key, FluidTypeInfo info) => _types[FluidKeys.still(key)] = info;

  static FluidTypeInfo of(String key) => _types[FluidKeys.still(key)] ?? const FluidTypeInfo();
}

abstract final class FluidHelper {
  /// `isWater`.
  static bool isWater(String fluid) => FluidKeys.still(fluid) == FluidKeys.water;

  /// `isLava`.
  static bool isLava(String fluid) => FluidKeys.still(fluid) == FluidKeys.lava;

  /// `isSame(stack, stack)`: the same fluid, ignoring the amount and data.
  static bool isSame(FStack a, FStack b) => a.fluid == b.fluid;

  /// `hasBlockState(fluid)`: the fluid has a block that holds it in the world.
  static bool hasBlockState(String fluid) => FluidTypes.of(fluid).hasBlock;

  /// `copyStackWithAmount`.
  static FStack copyStackWithAmount(FStack fs, int amount) => fs.withAmount(amount);

  /// `convertToFlowing` / `convertToStill`.
  static String convertToFlowing(String fluid) => FluidKeys.flowing(fluid);
  static String convertToStill(String fluid) => FluidKeys.still(fluid);

  /// `getFillSound`: the sound of a bucket being filled with the fluid.
  static String getFillSound(FStack fluid) =>
      isLava(fluid.fluid) ? 'minecraft:item.bucket.fill_lava' : 'minecraft:item.bucket.fill';

  /// `getEmptySound`.
  static String getEmptySound(FStack fluid) =>
      isLava(fluid.fluid) ? 'minecraft:item.bucket.empty_lava' : 'minecraft:item.bucket.empty';

  /// `FluidType.getLightLevel(stack)`.
  static int lightLevel(FStack fluid) => fluid.isEmpty ? 0 : FluidTypes.of(fluid.fluid).luminance;

  /// `FluidType.isLighterThanAir`.
  static bool isLighterThanAir(FStack fluid) => fluid.isNotEmpty && FluidTypes.of(fluid.fluid).density < 0;

  /// `exchange`: moves one batch between a tank and an item, preferring [preferred]. Returns the
  /// direction that happened, or `null`.
  static FluidExchange? exchange(FluidStorage fluidTank, FluidStorage fluidItem, FluidExchange preferred, int maxAmount) =>
      _exchange(fluidTank, fluidItem, preferred, true, maxAmount);

  /// `exchangeAll`.
  static FluidExchange? exchangeAll(FluidStorage fluidTank, FluidStorage fluidItem, FluidExchange preferred) =>
      _exchange(fluidTank, fluidItem, preferred, false, 0x7fffffff);

  static FluidExchange? _exchange(
    FluidStorage fluidTank,
    FluidStorage fluidItem,
    FluidExchange preferred,
    bool singleOp,
    int maxTransferAmountPerTank,
  ) {
    FluidExchange? lockedExchange;
    for (var tankSlot = 0; tankSlot < fluidTank.tanks; tankSlot++) {
      for (var slot = 0; slot < fluidItem.tanks; slot++) {
        final fluidInTank = fluidTank.fluidInTank(tankSlot);
        final tankCapacity = fluidTank.tankCapacity(tankSlot) - fluidInTank.amount;
        final tankEmpty = fluidInTank.isEmpty;
        final fluidInItem = fluidItem.fluidInTank(tankSlot);
        final itemCapacity = fluidItem.tankCapacity(tankSlot) - fluidInItem.amount;
        final itemEmpty = fluidInItem.isEmpty;
        final undecided = lockedExchange == null;
        final canMoveToTank = (undecided || lockedExchange == FluidExchange.itemToTank) && tankCapacity > 0;
        final canMoveToItem = (undecided || lockedExchange == FluidExchange.tankToItem) && itemCapacity > 0;

        if (!tankEmpty && !itemEmpty && !fluidInItem.isSameFluid(fluidInTank)) continue;

        if (((tankEmpty || itemCapacity <= 0) && canMoveToTank) || undecided && preferred == FluidExchange.itemToTank) {
          final take = maxTransferAmountPerTank < tankCapacity ? maxTransferAmountPerTank : tankCapacity;
          final amount = fluidTank.fill(fluidItem.drain(take, simulate: false), simulate: false);
          if (amount > 0) {
            lockedExchange = FluidExchange.itemToTank;
            if (singleOp) return lockedExchange;
            continue;
          }
        }

        if (((itemEmpty || tankCapacity <= 0) && canMoveToItem) || undecided && preferred == FluidExchange.tankToItem) {
          final take = maxTransferAmountPerTank < itemCapacity ? maxTransferAmountPerTank : itemCapacity;
          final amount = fluidItem.fill(fluidTank.drain(take, simulate: false), simulate: false);
          if (amount > 0) {
            lockedExchange = FluidExchange.tankToItem;
            if (singleOp) return lockedExchange;
            continue;
          }
        }
      }
    }
    return null;
  }
}

/// `FluidHelper.FluidExchange`.
enum FluidExchange { itemToTank, tankToItem }
