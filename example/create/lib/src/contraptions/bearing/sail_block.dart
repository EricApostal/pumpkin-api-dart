// `SailBlock`: the sail frame and the sixteen dyed sails. A sail can be dyed, sheared back to the
// frame, and a sail item placed on a sail continues the row. The pure sail data (keys, colours,
// shapes, placement state) lives in `sail.dart`.
//
// Java: `content/contraptions/bearing/SailBlock`, `BlankSailBlockItem`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../api/placement.dart';
import '../../common/common.dart';
import '../../core/blocks.dart' show CreateBlock;
import 'sail.dart';

/// The block definitions of the frame and the dyed sails. The white sail is the block the sail
/// item places; the dyed sails are reached by dyeing.
///
/// The default facing is `north` (`DirectionalBlock`'s default state), so the base shapes are the
/// north ones and a [ShapeRule] covers each of the other five facings.
List<CreateBlock> buildSailBlocks({
  required BlockBehavior Function(String key, bool frame) behaviorOf,
}) => [
  manifestBlock(
    'sail_frame',
    placement: sailPlacement,
    collisionShape: BlockShape.boxes(
      sailFrameCollisionBoxes(Direction.north),
    ),
    selectionShape: BlockShape.boxes(sailFrameBoxes(Direction.north)),
    shapeRules: _sailShapeRules(frame: true),
    behavior: behaviorOf(sailFrame, true),
  ),
  for (final color in sailColors)
    manifestBlock(
      '${color}_sail',
      placement: sailPlacement,
      collisionShape: BlockShape.boxes(sailCanvasBoxes(Direction.north)),
      selectionShape: BlockShape.boxes(sailCanvasBoxes(Direction.north)),
      shapeRules: _sailShapeRules(frame: false),
      behavior: behaviorOf(dyedSail(color), false),
    ),
];

/// `getShape` / `getCollisionShape` of `SailBlock` for every facing but the default `north`: the
/// canvas is solid, the frame's collision is its open border.
List<ShapeRule> _sailShapeRules({required bool frame}) => [
  for (final facing in Direction.values)
    if (facing != Direction.north)
      ShapeRule(
        when: {'facing': facing.serializedName},
        collisionShape: BlockShape.boxes(
          frame
              ? sailFrameCollisionBoxes(facing)
              : sailCanvasBoxes(facing),
        ),
        selectionShape: BlockShape.boxes(
          frame ? sailFrameBoxes(facing) : sailCanvasBoxes(facing),
        ),
      ),
];

/// `SailBlock.applyDye`: dyes this sail, then a neighbour, then the whole connected patch.
Future<void> applySailDye(
  World world,
  Pos pos,
  BState state,
  (double, double, double) hit,
  String? color,
) async {
  final targetKey = color == null ? sailFrame : dyedSail(color);
  final facing = state.dir('facing') ?? Direction.north;
  var newState = BState(targetKey)
      .setAll({if (state['facing'] != null) 'facing': state['facing']!});

  // Dye the block itself.
  if (state.key != targetKey) {
    await setBlockState(world, pos, newState);
    return;
  }

  // Dye an adjacent sail of the same facing.
  final axis = facing.axis;
  final directions = orderedByDistanceExceptAxis(pos, hit, axis);
  for (final d in directions) {
    final offset = pos.relative(d);
    final adjacent = HostBlockGetter(world).stateAt(offset);
    if (!isSailKey(adjacent.key) || adjacent.key == sailFrame) continue;
    if (adjacent.dir('facing') != facing) continue;
    if (adjacent == state) continue;
    await setBlockState(world, offset, newState);
    return;
  }

  // Dye the whole connected patch (at most 100 blocks).
  final frontier = <Pos>[pos];
  final visited = <Pos>{};
  var timeout = 100;
  while (frontier.isNotEmpty) {
    if (timeout-- < 0) break;
    final current = frontier.removeAt(0);
    visited.add(current);
    for (final d in Direction.values) {
      if (d.axis == axis) continue;
      final offset = current.relative(d);
      if (visited.contains(offset)) continue;
      final adjacent = HostBlockGetter(world).stateAt(offset);
      if (!isSailKey(adjacent.key)) continue;
      if (adjacent.key == sailFrame && color != null) continue;
      if (adjacent.dir('facing') != facing) continue;
      if (adjacent != state) await setBlockState(world, offset, newState);
      frontier.add(offset);
      visited.add(offset);
    }
  }
}

/// The use-with-item behaviour of a sail block: continue a row of sails with a sail item, shear it
/// back to the frame, or dye it.
BlockBehavior sailBlockBehavior(String blockKey, {required bool frame}) {
  return BlockBehavior(
    onUseWithItem: (server, e) async {
      final state = HostBlockGetter.stateOfId(e.stateIndex);
      final String itemKey;
      try {
        itemKey = await e.item.getRegistryKey();
      } catch (_) {
        return BlockUseResult.pass;
      }

      final world = e.targetWorld;
      final pos = (e.pos.x, e.pos.y, e.pos.z);
      // `ray.getLocation()`: world coordinates, not the host's block-relative cursor.
      final hit = sailHitLocation(pos, e.cursor);

      // `PlacementHelper.matchesItem` comes first and is the only branch sneaking disables.
      if (isSailItemKey(itemKey) && !e.sneaking && _mayBuild(e.player)) {
        final offset = sailPlacementOffset(
          level: HostBlockGetter(world),
          state: state,
          pos: pos,
          hit: hit,
        );
        // `PlacementOffset.placeInWorld` places the item's block where it can, and the click is
        // consumed either way.
        if (offset.isSuccessful) {
          await setBlockState(
            world,
            offset.pos,
            offset.transform(BState(itemKey)),
          );
          await _consumeOne(e.player, e.hand);
        }
        return BlockUseResult.success;
      }

      if (itemKey == 'minecraft:shears') {
        await applySailDye(world, pos, state, hit, null);
        world.playSound(
          sound: Sound.entitySheepShear,
          category: SoundCategory.blocks,
          pos: pos.center,
          volume: 1,
          pitch: 1,
        );
        return BlockUseResult.success;
      }

      if (frame) return BlockUseResult.tryEmptyHand;

      final color = dyeColorOfItem(itemKey);
      if (color != null) {
        await applySailDye(world, pos, state, hit, color);
        return BlockUseResult.success;
      }

      return BlockUseResult.tryEmptyHand;
    },
  );
}

/// `Player.mayBuild()`: adventure and spectator players cannot place blocks.
bool _mayBuild(Player player) => !player.isAdventure && !player.isSpectator;

/// Takes one item from [hand] (the host exposes no item damage, so the block item is re-created
/// with one less). Creative players keep it (`BlockItem.place`).
Future<void> _consumeOne(Player player, Hand hand) async {
  if (player.isCreative) return;
  try {
    final inv = player.getInventory();
    final stack = inv.getItemInHand(hand: hand);
    if (stack == null) return;
    final key = await stack.getRegistryKey();
    final count = await stack.getCount();
    if (count <= 1) {
      await inv.setItemInHand(hand: hand, item: null);
    } else {
      await inv.setItemInHand(
        hand: hand,
        item: ItemStack.create(registryKey: key, count: count - 1),
      );
    }
  } on Object {
    // the item is left in hand; a missing consumption is better than a failed click
  }
}
