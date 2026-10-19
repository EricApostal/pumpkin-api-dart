// Host side of the placement helpers: reads the world for `HelperWorld`, places
// the block of a `PlacementOffset` like `PlacementOffset.placeInWorld` does, and
// the `CogwheelBlockItem.onItemUseFirst` hook.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/blocks.dart';
import 'block_factory.dart';
import 'geometry.dart';
import 'kinetic_block_entity.dart';
import 'placement_helpers.dart';
import 'runtime.dart';

/// The world as the helpers read it.
HelperWorld helperWorldFor(KineticsRuntime rt, String worldId, World world) {
  final level = rt.level(worldId);
  return HelperWorld(
    level.stateAt,
    (p) {
      final s = world.getBlockState(pos: toBlockPos(p));
      return s.isAir || s.replaceable;
    },
    rt.blocks,
    placementAssistRange: rt.placementAssistRange,
  );
}

/// `PlacementOffset.placeInWorld`: places [blockKey] (the held block item) at the
/// offset with the transformed default state. Returns whether it was placed.
Future<bool> placeOffset(
  KineticsRuntime rt,
  World world,
  String worldId,
  PlacementOffset offset,
  CreateBlock block,
  Player player,
  Hand hand,
) async {
  if (!offset.success) return false;
  final bp = toBlockPos(offset.pos);
  final current = world.getBlockState(pos: bp);
  if (!(current.isAir || current.replaceable)) return false;

  var state = offset.transform(KState(block.key, block.definition.defaultState));
  if (state.has('waterlogged')) {
    final f = world.fluidAt(bp);
    state = state.setFlag('waterlogged', f != null && f.isSource && f.fluid == 'minecraft:water');
  }
  await setKState(rt, world, bp, state);

  final be = rt.store.at(worldId, bp);
  if (be is KineticBlockEntity) be.queueRotationIndicators();

  if (!player.isCreative) {
    final stack = player.getItemInHand(hand: hand);
    if (stack != null) {
      final count = await stack.getCount();
      if (count <= 1) {
        await player.setItemInHand(hand: hand, stack: null);
      } else {
        await stack.setCount(count: count - 1);
        await player.setItemInHand(hand: hand, stack: stack);
      }
    }
  }
  return true;
}

/// `CogwheelBlockItem.onItemUseFirst`: a cogwheel item used on a cogwheel (or any
/// block with an integrated cog) is placed by the helper. Returns whether it placed one.
Future<bool> cogwheelItemUseFirst(
  KineticsRuntime rt,
  Server server,
  ItemUseFirstEventData e,
  String itemKey,
  Map<String, CreateBlock> blocks,
) async {
  final large = itemKey == 'create:large_cogwheel';
  if (!large && itemKey != 'create:cogwheel') return false;
  final player = e.player;
  if (player.asEntity().isSneaking()) return false;

  final record = rt.useRecords.matching(player.getId().asString, e.blockPos);
  if (record == null || record.clicked.x != e.blockPos.x || record.clicked.y != e.blockPos.y || record.clicked.z != e.blockPos.z) {
    return false;
  }
  final world = player.getWorld();
  final worldId = rt.worlds.touch(world);
  final w = helperWorldFor(rt, worldId, world);
  final pos = toKPos(e.blockPos);
  final state = rt.level(worldId).stateAt(pos);
  final hit = (e.blockPos.x + record.cursor.$1, e.blockPos.y + record.cursor.$2, e.blockPos.z + record.cursor.$3);
  final face = Dir.fromName(e.face.name) ?? Dir.up;

  final offset = cogwheelItemOffset(w, pos, state, face, hit, large: large);
  if (!offset.success) return false;
  final block = blocks[itemKey];
  if (block == null) return false;
  return placeOffset(rt, world, worldId, offset, block, player, e.hand);
}
