// `VanillaFluidTargets` (pure): blocks that give or take fluid without a fluid capability
// (beehives, cauldrons).
import '../api/block_state.dart';
import 'fluid_stack.dart';
import 'fluid_world.dart';

abstract final class VanillaFluidTargets {
  /// `canProvideFluidWithoutCapability`.
  static bool canProvideFluidWithoutCapability(BState state) {
    if (state.has('honey_level')) return true;
    return state.key == 'minecraft:cauldron' || state.key == 'minecraft:lava_cauldron' || state.key == 'minecraft:water_cauldron';
  }

  /// `drainBlock(level, pos, state, simulate)`.
  static FStack drainBlock(FluidWorld world, (int, int, int) pos, BState state, {required bool simulate}) {
    if (state.has('honey_level') && state.intValue('honey_level') >= 5) {
      if (!simulate) world.setBlock(pos, state.setInt('honey_level', 0));
      return const FStack(FluidKeys.honey, 250);
    }

    if (state.key == 'minecraft:lava_cauldron') {
      if (!simulate) world.setBlock(pos, const BState('minecraft:cauldron'));
      return const FStack(FluidKeys.lava, 1000);
    }

    if (state.key == 'minecraft:water_cauldron') {
      // `LayeredCauldronBlock.isFull`: level 3.
      if (state.intValue('level') != 3) return FStack.empty;
      if (!simulate) world.setBlock(pos, const BState('minecraft:cauldron'));
      return const FStack(FluidKeys.water, 1000);
    }

    return FStack.empty;
  }
}
