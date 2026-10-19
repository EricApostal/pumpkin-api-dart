// `SailBlock`: the sail frame and the sixteen dyed sails. A sail can be dyed, sheared back to the
// frame, and a sail item placed on a sail continues the row.
//
// Java: `content/contraptions/bearing/SailBlock`, `BlankSailBlockItem`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart';
import '../../api/placement.dart';
import '../../common/common.dart';
import '../../core/blocks.dart' show CreateBlock;

/// `AllBlocks.SAIL_FRAME`.
const String sailFrame = 'create:sail_frame';

/// `AllBlocks.SAIL` (the white sail the item places).
const String whiteSail = 'create:white_sail';

/// The sixteen dye colours, in vanilla `DyeColor` order.
const List<String> sailColors = [
  'white',
  'orange',
  'magenta',
  'light_blue',
  'yellow',
  'lime',
  'pink',
  'gray',
  'light_gray',
  'cyan',
  'purple',
  'blue',
  'brown',
  'green',
  'red',
  'black',
];

/// `AllBlocks.DYED_SAILS.get(color)`.
String dyedSail(String color) => 'create:${color}_sail';

/// Whether [key] is the frame or one of the dyed sails.
bool isSailKey(String key) =>
    key == sailFrame ||
    key == whiteSail ||
    sailColors.any((c) => key == dyedSail(c));

/// The dye colour of a sail block, `null` for the frame.
String? sailColor(String key) {
  for (final c in sailColors) {
    if (key == dyedSail(c)) return c;
  }
  return null;
}

/// The colour of a `minecraft:<color>_dye` item, `null` for anything else.
String? dyeColorOfItem(String itemKey) {
  if (!itemKey.startsWith('minecraft:') || !itemKey.endsWith('_dye'))
    return null;
  final color = itemKey.substring(
    'minecraft:'.length,
    itemKey.length - '_dye'.length,
  );
  return sailColors.contains(color) ? color : null;
}

/// `AllShapes.SAIL` / `SAIL_FRAME`: a plate on the facing side, one pixel thick for the frame and
/// two for the canvas. The frame has a hole in the middle.
List<BlockBox> sailShapeBoxes(Direction facing, {required bool frame}) {
  final t = frame ? 1.0 : 2.0;
  // A plate at the facing side, in block units.
  final boxes = switch (facing) {
    Direction.up => [BlockBox(0, 1 - t / 16, 0, 1, 1, 1)],
    Direction.down => [BlockBox(0, 0, 0, 1, t / 16, 1)],
    Direction.north => [BlockBox(0, 0, 0, 1, 1, t / 16)],
    Direction.south => [BlockBox(0, 0, 1 - t / 16, 1, 1, 1)],
    Direction.west => [BlockBox(0, 0, 0, t / 16, 1, 1)],
    Direction.east => [BlockBox(1 - t / 16, 0, 0, 1, 1, 1)],
  };
  if (!frame) return boxes;
  // The frame is a border around the plate; approximate it with four thin bars.
  final e = 2.0 / 16;
  return switch (facing) {
    Direction.up || Direction.down => [
      BlockBox(0, boxes.first.minY, 0, 1, boxes.first.maxY, e),
      BlockBox(0, boxes.first.minY, 1 - e, 1, boxes.first.maxY, 1),
      BlockBox(0, boxes.first.minY, e, e, boxes.first.maxY, 1 - e),
      BlockBox(1 - e, boxes.first.minY, e, 1, boxes.first.maxY, 1 - e),
    ],
    Direction.north || Direction.south => [
      BlockBox(0, 0, boxes.first.minZ, 1, e, boxes.first.maxZ),
      BlockBox(0, 1 - e, boxes.first.minZ, 1, 1, boxes.first.maxZ),
      BlockBox(0, e, boxes.first.minZ, e, 1 - e, boxes.first.maxZ),
      BlockBox(1 - e, e, boxes.first.minZ, 1, 1 - e, boxes.first.maxZ),
    ],
    Direction.west || Direction.east => [
      BlockBox(boxes.first.minX, 0, 0, boxes.first.maxX, e, 1),
      BlockBox(boxes.first.minX, 1 - e, 0, boxes.first.maxX, 1, 1),
      BlockBox(boxes.first.minX, e, 0, boxes.first.maxX, 1 - e, e),
      BlockBox(boxes.first.minX, e, 1 - e, boxes.first.maxX, 1 - e, 1),
    ],
  };
}

/// The block definitions of the frame and the dyed sails. The white sail is the block the sail
/// item places; the dyed sails are reached by dyeing.
List<CreateBlock> buildSailBlocks({
  required BlockBehavior Function(String key, bool frame) behaviorOf,
}) => [
  manifestBlock(
    'sail_frame',
    placement: const [PlacementRule.clickedFace('facing', opposite: true)],
    collisionShape: BlockShape.boxes(
      sailShapeBoxes(Direction.north, frame: true),
    ),
    selectionShape: BlockShape.boxes(
      sailShapeBoxes(Direction.north, frame: true),
    ),
    behavior: behaviorOf(sailFrame, true),
  ),
  for (final color in sailColors)
    manifestBlock(
      '${color}_sail',
      placement: const [PlacementRule.clickedFace('facing', opposite: true)],
      collisionShape: BlockShape.boxes(
        sailShapeBoxes(Direction.north, frame: false),
      ),
      selectionShape: BlockShape.boxes(
        sailShapeBoxes(Direction.north, frame: false),
      ),
      behavior: behaviorOf(dyedSail(color), false),
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

/// The use-with-item behaviour of a sail block: shear it back to the frame, dye it, or place the
/// next sail of a row with a sail item.
BlockBehavior sailBlockBehavior(String blockKey, {required bool frame}) {
  return BlockBehavior(
    onUseWithItem: (server, e) async {
      if (e.sneaking && !frame) return BlockUseResult.pass;
      final state = HostBlockGetter.stateOfId(e.stateIndex);
      final String itemKey;
      try {
        itemKey = await e.item.getRegistryKey();
      } catch (_) {
        return BlockUseResult.pass;
      }

      final world = e.targetWorld;
      final pos = (e.pos.x, e.pos.y, e.pos.z);
      final hit = e.cursor;
      final facing = state.dir('facing') ?? Direction.north;

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

      final color = dyeColorOfItem(itemKey);
      if (color != null && !frame) {
        await applySailDye(world, pos, state, hit, color);
        return BlockUseResult.success;
      }

      // A sail item extends the row of sails in the direction closest to the click.
      if (isSailKey(itemKey) && !e.sneaking) {
        final level = HostBlockGetter(world);
        final directions = orderedByDistanceExceptAxis(
          pos,
          hit,
          facing.axis,
          (d) => level.canBeReplaced(pos.relative(d)),
        );
        if (directions.isEmpty) return BlockUseResult.tryEmptyHand;
        final target = pos.relative(directions.first);
        final newState = BState(itemKey).setDir('facing', facing);
        await setBlockState(world, target, newState);
        await _consumeOne(e.player);
        return BlockUseResult.success;
      }
      return BlockUseResult.tryEmptyHand;
    },
  );
}

/// Takes one item from the player's main hand (the host exposes no item damage, so the block item
/// is re-created with one less).
Future<void> _consumeOne(Player player) async {
  try {
    final inv = player.getInventory();
    final stack = inv.getItemInHand(hand: Hand.right);
    if (stack == null) return;
    final key = await stack.getRegistryKey();
    final count = await stack.getCount();
    if (count <= 1) {
      await inv.setItemInHand(hand: Hand.right, item: null);
    } else {
      await inv.setItemInHand(
        hand: Hand.right,
        item: ItemStack.create(registryKey: key, count: count - 1),
      );
    }
  } on Object {
    // the item is left in hand; a missing consumption is better than a failed click
  }
}
