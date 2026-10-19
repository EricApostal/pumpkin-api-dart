// `HarvesterMovementBehaviour`: the mechanical harvester cuts crops, leaves and small plants in
// front of it when the contraption moves it into their block.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart' show ItemStack;

import '../../../api/block_state.dart';
import '../../../api/blocks.dart' show setBlockState;
import '../../../common/common.dart';
import '../../../common/host_bridge.dart';
import '../../core/movement.dart';
import '../actor_runtime.dart';
import '../block_breaking_movement_behaviour.dart' show collectOrDropHost;

/// `HarvesterBlock.FACING`.
const String harvesterFacing = 'facing';

/// `HarvesterMovementBehaviour`.
final class HarvesterMovementBehaviour extends MovementBehaviour {
  const HarvesterMovementBehaviour();

  @override
  bool breaksBlocks() => true;

  @override
  bool isActive(MovementContext context) {
    final facing = context.state.dir(harvesterFacing) ?? Direction.north;
    return super.isActive(context) &&
        !VecHelper.isVecPointingTowards(
          context.relativeMotion,
          facing.opposite,
        );
  }

  @override
  Vec3 getActiveAreaOffset(MovementContext context) {
    final facing = context.state.dir(harvesterFacing) ?? Direction.north;
    return facing.unitVec3 * .45;
  }

  @override
  Future<void> visitNewPosition(MovementContext context, Pos pos) async {
    final world = actors?.worldOf(context);
    if (world == null) return;

    final stateVisited = context.level.stateAt(pos);
    if (stateVisited.isAir ||
        context.level.stateHasTag(stateVisited, 'create:non_harvestable'))
      return;

    var notCropButCuttable = false;
    if (!isValidCrop(context, stateVisited)) {
      if (isValidOther(context, pos, stateVisited)) {
        notCropButCuttable = true;
      } else {
        return;
      }
    }

    final isLeaves = context.level.stateHasTag(
      stateVisited,
      'minecraft:leaves',
    );
    final tool = isLeaves
        ? ItemStack.create(registryKey: 'minecraft:shears', count: 1)
        : null;
    final effectChance = isLeaves ? .45 : 1.0;

    var seedSubtracted = notCropButCuttable;
    try {
      await BlockHelper.destroyBlockAs(world, pos, null, tool, effectChance, (
        stack,
      ) async {
        final runtime = actors;
        if ((runtime?.harvesterReplants ?? true) && !seedSubtracted) {
          final key = await stack.getRegistryKey();
          if (key == stateVisited.key) {
            final count = await stack.getCount();
            if (count > 0) await stack.setCount(count: count - 1);
            seedSubtracted = true;
          }
        }
        await collectOrDropHost(context, stack);
      });
    } finally {
      tool?.dispose();
    }

    final cut = cutCrop(context, pos, stateVisited);
    await setBlockState(world, pos, cut);
  }

  /// `isValidCrop`.
  bool isValidCrop(MovementContext context, BState state) {
    final harvestPartial = actors?.harvestPartiallyGrown ?? false;
    final replant = actors?.harvesterReplants ?? true;
    final maxAge = maxAgeOf(state.key);

    if (context.level.stateHasTag(state, 'minecraft:crops')) {
      if (harvestPartial) return state.intValue('age') != 0 || !replant;
      return state.intValue('age') == maxAge;
    }

    if (context.level.stateCollisionEmpty(state) ||
        state.key == 'minecraft:cocoa') {
      if (!state.has('age')) return false;
      final age = state.intValue('age');
      if (state.key == 'minecraft:sweet_berry_bush' && age <= 1 && replant)
        return false;
      if (age == 0 && replant || !harvestPartial && maxAge != age) return false;
      return true;
    }

    return false;
  }

  /// `isValidOther`.
  bool isValidOther(MovementContext context, Pos pos, BState state) {
    if (context.level.stateHasTag(state, 'minecraft:crops')) return false;
    if (state.key == 'minecraft:sugar_cane') return true;
    if (context.level.stateHasTag(state, 'minecraft:leaves')) return true;
    if (state.key == 'minecraft:cocoa')
      return state.intValue('age') == maxAgeOf(state.key);

    if (context.level.stateCollisionEmpty(state)) {
      if (growingPlants.contains(state.key)) return true;
      if (state.has('age')) return false;
      // `BushBlock` / `SpecialPlantable`: every other plant without growth stages.
      return true;
    }
    return false;
  }

  /// `cutCrop`: what is left after harvesting.
  BState cutCrop(MovementContext context, Pos pos, BState state) {
    final replant = actors?.harvesterReplants ?? true;
    if (!replant) return airOrFluid(state);

    if (context.level.stateHasTag(state, 'minecraft:crops'))
      return state.setInt('age', 0);
    if (state.key == 'minecraft:sweet_berry_bush')
      return state.setInt('age', 1);
    if (context.level.stateHasTag(state, 'create:sugar_cane_variants') ||
        growingPlants.contains(state.key)) {
      return airOrFluid(state);
    }
    if (context.level.stateCollisionEmpty(state) ||
        state.key == 'minecraft:cocoa') {
      if (state.has('age')) return state.setInt('age', 0);
    }
    return airOrFluid(state);
  }

  /// `state.getFluidState().createLegacyBlock()`: a waterlogged block leaves its water behind.
  static BState airOrFluid(BState state) => state.flag('waterlogged')
      ? const BState('minecraft:water', {'level': '0'})
      : BState.air;

  /// `GrowingPlantBlock`: vines and kelp.
  static const Set<String> growingPlants = {
    'minecraft:cave_vines',
    'minecraft:cave_vines_plant',
    'minecraft:twisting_vines',
    'minecraft:twisting_vines_plant',
    'minecraft:weeping_vines',
    'minecraft:weeping_vines_plant',
    'minecraft:kelp',
    'minecraft:kelp_plant',
  };
}
