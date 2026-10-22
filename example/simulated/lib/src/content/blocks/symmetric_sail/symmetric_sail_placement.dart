// Where a symmetric sail gets its axis when it is placed, and where a sail item
// goes when it is used on a sail.
//
// Java has two halves:
//
//  * `SymmetricSailBlock.getStateForPlacement` — the axis of
//    `getNearestLookingDirection()`, which is the promoted click direction
//    (`BlockPlaceContext.getNearestLookingDirections` puts `clickedFace.getOpposite()`
//    first), i.e. the clicked face's axis: the block's `PlacementRule.clickedAxis`
//    (`sim_blocks.dart`).
//  * `SymmetricSailPlacementHelper` (`util/placement_helpers`) — the same item
//    predicate and `getOffset` Create's sails use: the next sail of the sheet goes
//    to the neighbour closest to the click that can be replaced, never along the
//    clicked sail's own axis, and it keeps that axis.
//
// Pure: the offset helper and the predicate take no host imports, so the tests run
// on the plain Dart VM. The axis fix is host glue.
//
// Java: dev.simulated_team.simulated.content.blocks.symmetric_sail.SymmetricSailBlock,
//       dev.simulated_team.simulated.util.placement_helpers.SymmetricSailPlacementHelper
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState, BlockGetter;
import 'package:create/src/api/placement.dart';
import 'package:create/src/common/direction.dart' show Axis;
import 'package:create/src/common/pos.dart';



/// `SymmetricSailBlock.checkItem`: the held item places a symmetric sail, so it is
/// a block item of one of the sixteen sails. Only the white sail registers an item
/// in Java (`SimBlocks.java:775-800`), so in practice this is that item.
///
/// The key test is the one `SymmetricSailDye.colourOf` makes; it is repeated here
/// because that file (the lift provider) imports sable, whose runtime is
/// wasm-only, and this file is pure so the tests can run on the VM.
bool isSymmetricSailItem(String itemKey) {
  const prefix = 'simulated:';
  const suffix = '_symmetric_sail';
  return itemKey.startsWith(prefix) &&
      itemKey.endsWith(suffix) &&
      itemKey.length > prefix.length + suffix.length;
}

/// `SymmetricSailPlacementHelper.getOffset`: the neighbour of the clicked sail the
/// next one goes to.
///
/// ```java
/// List<Direction> validDir = IPlacementHelper.orderedByDistanceExceptAxis(pos, ray.getLocation(), axis);
/// for (Direction dir : validDir) {
///     if (!world.getBlockState(pos.relative(dir)).canBeReplaced()) continue;
///     return PlacementOffset.success(pos.relative(dir), s -> s.setValue(AXIS, axis));
/// }
/// return PlacementOffset.fail();
/// ```
///
/// [hit] is the click in world coordinates (`BlockHitResult.getLocation()`): the
/// host reports it as `0..1` inside the clicked block, so the caller adds the
/// block position (`Sym`, the sail behaviour).
PlacementOffset symmetricSailOffset({
  required BlockGetter level,
  required BState state,
  required Pos pos,
  required (double, double, double) hit,
}) {
  final axisName = state['axis'];
  final axis = switch (axisName) {
    'x' => Axis.x,
    'y' => Axis.y,
    'z' => Axis.z,
    _ => null,
  };
  if (axis == null) return PlacementOffset.fail;
  for (final dir in orderedByDistanceExceptAxis(pos, hit, axis)) {
    final offset = pos.relative(dir);
    if (!level.canBeReplaced(offset)) continue;
    // The item's default state in the plugin carries no property values, and
    // `BState.setValue` leaves a state without the property unchanged, so the axis is
    // added rather than set (the same note as Create's `sailPlacementOffset`).
    return PlacementOffset.at(offset, (s) => BState(s.key, {...s.props, 'axis': axisName!}));
  }
  return PlacementOffset.fail;
}
