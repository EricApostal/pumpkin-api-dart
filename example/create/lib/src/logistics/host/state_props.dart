// State-property helpers shared by the logistics blocks (pure): the connected direction of the
// face-attached blocks (`FaceAttachedHorizontalDirectionalBlock.getConnectedDirection`) and the
// state their `getStateForPlacement` computes.
import '../../api/block_state.dart';
import '../../common/direction.dart';

/// `FaceAttachedHorizontalDirectionalBlock.getConnectedDirection(state)`: the direction from the
/// block a face-attached block hangs on towards the block itself. A `floor` block sits on the
/// block below it (`up`), a `ceiling` block hangs from the block above (`down`), a `wall` block is
/// attached to the block behind it (`facing`).
///
/// `AllShapes.STOCK_LINK` (`shape(1,0,1,15,5,15).forDirectional()`) and
/// `AllShapes.FACTORY_PANEL_FALLBACK` (`….forDirectional(UP)`) are read back with this direction,
/// so the floor/ceiling cases are not interchangeable.
Direction faceConnectedDirection(Map<String, String> properties) {
  final face = properties['face'] ?? 'floor';
  final facing =
      Direction.byName(properties['facing'] ?? 'north') ?? Direction.north;
  return switch (face) {
    'ceiling' => Direction.down,
    'floor' => Direction.up,
    _ => facing,
  };
}

/// `FaceAttachedHorizontalDirectionalBlock.getStateForPlacement`'s candidate `face`/`facing` for
/// one of the directions of [faceAttachedPlacementOrder]: the vertical directions give a
/// ceiling/floor block with the player's horizontal facing, a horizontal direction gives a wall
/// block facing back at the player.
({String face, String facing}) faceAttachedStateProps(
  Direction direction,
  Direction horizontal,
) => direction.axis == Axis.y
    ? (
        face: direction == Direction.up ? 'ceiling' : 'floor',
        facing: horizontal.serializedName,
      )
    : (face: 'wall', facing: direction.opposite.serializedName);

/// `BlockPlaceContext.getNearestLookingDirections`: the direction from the new block towards the
/// clicked block ([towardsClicked], the host's placement `face`) first, then the rest ordered by
/// the nearest look.
List<Direction> faceAttachedPlacementOrder(
  (double, double, double) look,
  Direction towardsClicked,
) => [
  towardsClicked,
  for (final d in Direction.orderedByNearest(look.$1, look.$2, look.$3))
    if (d != towardsClicked) d,
];

/// `FaceAttachedHorizontalDirectionalBlock.getStateForPlacement` as the logistics face-attached
/// blocks use it: the first direction of [faceAttachedPlacementOrder] whose state [canAttach]
/// accepts, with the block's own [adjust] applied to the winner. `null` when no direction carries
/// the block (the stock link's `canSurvive` is always true, so it always gets the first one).
///
/// `POWERED` starts false: both blocks take it from the neighbour signal after the block is there
/// (the stock link in its `neighborChanged`, the factory gauge from its behaviour).
BState? faceAttachedStateForPlacement(
  String key, {
  required (double, double, double) look,
  required double yaw,
  required Direction towardsClicked,
  required bool Function(BState state) canAttach,
  required bool waterlogged,
  BState Function(BState state)? adjust,
}) {
  final horizontal = Direction.fromYRot(yaw);
  for (final direction in faceAttachedPlacementOrder(look, towardsClicked)) {
    final candidate = faceAttachedStateProps(direction, horizontal);
    final state = BState(key, {
      'face': candidate.face,
      'facing': candidate.facing,
      'powered': 'false',
      'waterlogged': waterlogged ? 'true' : 'false',
    });
    if (!canAttach(state)) continue;
    return adjust == null ? state : adjust(state);
  }
  return null;
}
