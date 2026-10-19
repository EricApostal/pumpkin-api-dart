// `FluidReactions` (pure): what happens when two fluids meet in a pipe or at an open end.
import '../api/block_state.dart';
import '../common/pos.dart';
import 'fluid_helper.dart';
import 'fluid_stack.dart';
import 'fluid_world.dart';

/// Decides the block two colliding fluids turn into (`PipeCollisionEvent` listeners). Plugins add
/// their own with [FluidReactions.flowCollisions] and [FluidReactions.spillCollisions]; the first
/// answer wins.
typedef FlowCollisionHandler = BState? Function(String fluid1, String fluid2);
typedef SpillCollisionHandler = BState? Function(String worldFluid, String pipeFluid, bool worldFluidIsSource);

abstract final class FluidReactions {
  static final List<FlowCollisionHandler> flowCollisions = [];
  static final List<SpillCollisionHandler> spillCollisions = [];

  /// `AllFluids.getLavaInteraction(fluidState)`: what lava turns a Create fluid into.
  static BState? lavaInteraction(String fluid) {
    final still = FluidKeys.still(fluid);
    if (still == FluidKeys.honey) return const BState('create:limestone');
    if (still == FluidKeys.chocolate) return const BState('create:scoria');
    return null;
  }

  /// `handlePipeFlowCollision`: the pipe at [pos] breaks and may become something else.
  static void handlePipeFlowCollision(FluidWorld world, Pos pos, FStack fluid, FStack fluid2) {
    final f1 = FluidKeys.still(fluid.fluid);
    final f2 = FluidKeys.still(fluid2.fluid);
    world.award(pos, 'cross_streams');
    world.destroyBlock(pos, 1);

    BState? state;
    for (final h in flowCollisions) {
      state = h(f1, f2);
      if (state != null) break;
    }
    state ??= _flowFallback(f1, f2);
    if (state != null) world.setBlock(pos, state);
  }

  /// `handlePipeFlowCollisionFallback`.
  static BState? _flowFallback(String f1, String f2) {
    if (f1 == FluidKeys.water && f2 == FluidKeys.lava || f2 == FluidKeys.water && f1 == FluidKeys.lava) {
      return const BState('minecraft:cobblestone');
    }
    if (f1 == FluidKeys.lava && FluidHelper.hasBlockState(f2)) return lavaInteraction(f2);
    if (f2 == FluidKeys.lava && FluidHelper.hasBlockState(f1)) return lavaInteraction(f1);
    return null;
  }

  /// `handlePipeSpillCollision`: a pipe spills [pipeFluid] into [worldFluid] at [pos].
  static void handlePipeSpillCollision(FluidWorld world, Pos pos, String pipeFluid, FluidInfo worldFluid) {
    final pf = FluidKeys.still(pipeFluid);
    final wf = worldFluid.fluid;
    BState? state;
    for (final h in spillCollisions) {
      state = h(wf, pf, worldFluid.isSource);
      if (state != null) break;
    }
    state ??= _spillFallback(pf, wf, worldFluid.isSource);
    if (state != null) world.setBlock(pos, state);
  }

  /// `handlePipeSpillCollisionFallback`. [worldFlowing] distinguishes `FLOWING_LAVA` from `LAVA`.
  static BState? _spillFallback(String pf, String wf, bool worldIsSource) {
    BState? state;
    final worldFlowing = !worldIsSource;
    final pipeWater = pf == FluidKeys.water;
    if (pipeWater && wf == FluidKeys.lava && worldIsSource) {
      state = const BState('minecraft:obsidian');
    } else if (pipeWater && wf == FluidKeys.lava && worldFlowing) {
      state = const BState('minecraft:cobblestone');
    } else if (pf == FluidKeys.lava && wf == FluidKeys.water && worldIsSource) {
      state = const BState('minecraft:stone');
    } else if (pf == FluidKeys.lava && wf == FluidKeys.water && worldFlowing) {
      state = const BState('minecraft:cobblestone');
    }

    if (pf == FluidKeys.lava) {
      final lava = lavaInteraction(wf);
      if (lava != null) state = lava;
    } else if (wf == FluidKeys.lava && worldFlowing && FluidHelper.hasBlockState(pf)) {
      final lava = lavaInteraction(pf);
      if (lava != null) state = lava;
    }
    return state;
  }
}
