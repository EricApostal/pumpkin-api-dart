// The sail model as pure data: block keys and dye colours, the canvas/frame shapes, and the
// placement state a sail gets. `sail_block.dart` holds the block definitions and the use
// behaviour.
//
// Java: `content/contraptions/bearing/SailBlock`.
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox, PlacementRule;

import '../../api/block_state.dart';
import '../../api/placement.dart';
import '../../common/common.dart';

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
  if (!itemKey.startsWith('minecraft:') || !itemKey.endsWith('_dye')) {
    return null;
  }
  final color = itemKey.substring(
    'minecraft:'.length,
    itemKey.length - '_dye'.length,
  );
  return sailColors.contains(color) ? color : null;
}

/// `SailBlock.getStateForPlacement`: `WrenchableDirectionalBlock` takes the player's nearest
/// looking direction (`Direction.orderedByNearest(player)[0]`) and the sail turns it around. The
/// canvas therefore faces the player who placed it: head-on against a wall it faces out of the
/// wall, and placed on the floor while looking down it faces up.
const List<PlacementRule> sailPlacement = [
  PlacementRule.lookingDirection('facing', opposite: true),
];

/// `PlacementHelper.getItemPredicate`: the white sail item (the item of every dyed sail, see
/// `BlankSailBlockItem.registerBlocks`) and the frame item continue a row of sails.
bool isSailItemKey(String itemKey) =>
    itemKey == whiteSail || itemKey == sailFrame;

/// `BlockHitResult.getLocation()`: the click point in world coordinates.
///
/// The host reports a click as [cursor], `0..1` inside the block, while the placement helpers
/// order directions by the distance from the block centre to the exact hit (Java:
/// `ray.getLocation()`). Adding the block position first is what makes a row grow to the side the
/// player clicked rather than to a fixed side.
(double, double, double) sailHitLocation(Pos pos, (double, double, double) cursor) =>
    (pos.x + cursor.$1, pos.y + cursor.$2, pos.z + cursor.$3);

/// `SailBlock.PlacementHelper.getOffset`: the next sail of a row goes to the neighbour closest to
/// the click that can be replaced, never along the sail's facing axis (the row lies in the plane
/// of the canvas). The new sail keeps the clicked sail's `facing` (upstream
/// `PlacementOffset.success(pos, s -> s.setValue(FACING, state.getValue(FACING)))`).
///
/// [hit] is the click point in world coordinates (`BlockHitResult.getLocation()`); see
/// [sailHitLocation].
PlacementOffset sailPlacementOffset({
  required BlockGetter level,
  required BState state,
  required Pos pos,
  required (double, double, double) hit,
}) {
  final facing = state.dir('facing') ?? Direction.north;
  final directions = orderedByDistanceExceptAxis(
    pos,
    hit,
    facing.axis,
    (d) => level.canBeReplaced(pos.relative(d)),
  );
  if (directions.isEmpty) return PlacementOffset.fail;
  // The item's default state in the plugin carries no property values, and `BState.setValue`
  // leaves a state without the property unchanged, so the facing is added rather than set.
  return PlacementOffset.at(
    pos.relative(directions.first),
    (s) => BState(s.key, {...s.props, 'facing': facing.serializedName}),
  );
}

/// `AllShapes.SAIL`: the canvas, a plate five pixels thick centred in the block and perpendicular
/// to `facing`.
///
/// The shapes are the ones `VoxelShaper.forDirectional()` produces from the up-facing box
/// `(0, 5, 0, 16, 10, 16)` rotated about the block centre. The plate is not symmetric about the
/// centre, so the two sides of an axis differ by one pixel: `up` 5..10 vs `down` 6..11, and
/// `north`/`south` are `z` 5..10, `east` is `x` 5..10, `west` is `x` 6..11.
List<BlockBox> sailCanvasBoxes(Direction facing) => switch (facing) {
  Direction.up => [BlockBox(0, 5 / 16, 0, 1, 10 / 16, 1)],
  Direction.down => [BlockBox(0, 6 / 16, 0, 1, 11 / 16, 1)],
  Direction.north || Direction.south => [BlockBox(0, 0, 5 / 16, 1, 1, 10 / 16)],
  Direction.east => [BlockBox(5 / 16, 0, 0, 10 / 16, 1, 1)],
  Direction.west => [BlockBox(6 / 16, 0, 0, 11 / 16, 1, 1)],
};

/// `AllShapes.SAIL_FRAME`: the wooden frame's plate, four pixels thick (the canvas is five), with
/// the same rotations as [sailCanvasBoxes].
List<BlockBox> sailFrameBoxes(Direction facing) => switch (facing) {
  Direction.up => [BlockBox(0, 5 / 16, 0, 1, 9 / 16, 1)],
  Direction.down => [BlockBox(0, 7 / 16, 0, 1, 11 / 16, 1)],
  Direction.north || Direction.south => [BlockBox(0, 0, 5 / 16, 1, 1, 9 / 16)],
  Direction.east => [BlockBox(5 / 16, 0, 0, 9 / 16, 1, 1)],
  Direction.west => [BlockBox(7 / 16, 0, 0, 11 / 16, 1, 1)],
};

/// `AllShapes.SAIL_FRAME_COLLISION`: the frame's plate with its middle erased
/// (`shape(0, 5, 0, 16, 9, 16).erase(2, 0, 2, 14, 16, 14)`), so a frame is a two-pixel border
/// around an opening and an entity can pass through it. The canvas itself is solid.
List<BlockBox> sailFrameCollisionBoxes(Direction facing) {
  const e = 2 / 16;
  return switch (facing) {
    Direction.up => [
      BlockBox(0, 5 / 16, 0, 1, 9 / 16, e),
      BlockBox(0, 5 / 16, 1 - e, 1, 9 / 16, 1),
      BlockBox(0, 5 / 16, e, e, 9 / 16, 1 - e),
      BlockBox(1 - e, 5 / 16, e, 1, 9 / 16, 1 - e),
    ],
    Direction.down => [
      BlockBox(0, 7 / 16, 0, 1, 11 / 16, e),
      BlockBox(0, 7 / 16, 1 - e, 1, 11 / 16, 1),
      BlockBox(0, 7 / 16, e, e, 11 / 16, 1 - e),
      BlockBox(1 - e, 7 / 16, e, 1, 11 / 16, 1 - e),
    ],
    Direction.north || Direction.south => [
      BlockBox(0, 1 - e, 5 / 16, 1, 1, 9 / 16),
      BlockBox(0, 0, 5 / 16, 1, e, 9 / 16),
      BlockBox(1 - e, e, 5 / 16, 1, 1 - e, 9 / 16),
      BlockBox(0, e, 5 / 16, e, 1 - e, 9 / 16),
    ],
    Direction.east => [
      BlockBox(5 / 16, 1 - e, 0, 9 / 16, 1, 1),
      BlockBox(5 / 16, 0, 0, 9 / 16, e, 1),
      BlockBox(5 / 16, e, 1 - e, 9 / 16, 1 - e, 1),
      BlockBox(5 / 16, e, 0, 9 / 16, 1 - e, e),
    ],
    Direction.west => [
      BlockBox(7 / 16, 1 - e, 0, 11 / 16, 1, 1),
      BlockBox(7 / 16, 0, 0, 11 / 16, e, 1),
      BlockBox(7 / 16, e, 1 - e, 11 / 16, 1 - e, 1),
      BlockBox(7 / 16, e, 0, 11 / 16, 1 - e, e),
    ],
  };
}
