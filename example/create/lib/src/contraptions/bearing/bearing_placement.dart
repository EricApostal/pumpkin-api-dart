// The placement and click rules of the bearing family as pure functions: which `facing` a placed
// bearing gets, where a click on a bearing places the held block, and whether a right click
// assembles the bearing or leaves the click to the held item.
//
// Java: `content/kinetics/base/DirectionalKineticBlock.getStateForPlacement` and
// `getPreferredFacing` (the `facing` property), `content/contraptions/bearing/BearingBlock`
// (`hasShaftTowards`), and `useItemOn` of `MechanicalBearingBlock`, `WindmillBearingBlock` and
// `ClockworkBearingBlock`.
//
// No host imports: the placement tests use this file on the plain Dart VM.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api_core.dart'
    show PlacementRule, PlacementSourceKind, ShaftKind, ShaftNeighbour;

import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../kinetics/block_data.dart'
    show facingShaftTag, reverseFacingShaftTag, shaftTag;

/// The neighbours that count for a bearing's `getPreferredFacing`, each with the property that
/// says where its shaft points (the tags are the sets in `kinetics/block_data.dart`):
///
/// * [shaftTag]: `hasShaftTowards(face) == (face.getAxis() == axis)`, [ShaftKind.axis].
/// * [facingShaftTag]: `face == FACING.getOpposite()`, so `FACING` points from the bearing to
///   the neighbour, [ShaftKind.facing].
/// * [reverseFacingShaftTag]: `face == FACING`, so `FACING` points from the neighbour to the
///   bearing, [ShaftKind.facingOpposite].
const List<ShaftNeighbour> bearingShaftNeighbours = [
  ShaftNeighbour(shaftTag, 'axis', ShaftKind.axis),
  ShaftNeighbour(facingShaftTag, 'facing', ShaftKind.facing),
  ShaftNeighbour(reverseFacingShaftTag, 'facing', ShaftKind.facingOpposite),
];

/// The placement rules the host applies when a bearing is placed, in Java's order:
///
/// ```java
/// Direction preferred = getPreferredFacing(context);
/// if (preferred == null || (player != null && player.isShiftKeyDown())) {
///     Direction nearest = context.getNearestLookingDirection();
///     return defaultBlockState().setValue(FACING,
///         sneaking ? nearest : nearest.getOpposite());
/// }
/// return defaultBlockState().setValue(FACING, preferred.getOpposite());
/// ```
///
/// The host evaluates these before it writes the block (`DynamicBlock::on_place` in
/// `crates/pumpkin-core/src/block/blocks/dynamic.rs`), so no `placed` hook has to rewrite the
/// state — rewriting it there re-enters the placed hook and recursed once.
const List<PlacementRule> bearingPlacementRules = [
  // A neighbouring shaft decides, unless the player sneaks: `preferred.getOpposite()`.
  PlacementRule.neighbourShaft(
    'facing',
    bearingShaftNeighbours,
    opposite: true,
    whenSneaking: false,
  ),
  // No shaft, not sneaking: the bearing faces the player (`nearest.getOpposite()`).
  PlacementRule.lookingDirection('facing', opposite: true, whenSneaking: false),
  // Sneaking keeps the look direction, whatever the neighbours are.
  PlacementRule.lookingDirection('facing', whenSneaking: true),
];

/// `DirectionalKineticBlock.getPreferredFacing`: the side a neighbouring shaft sticks into.
///
/// [shaftTowards] is `IRotate.hasShaftTowards(level, neighbour, neighbourState, side.opposite)`
/// for the neighbour on [side]. Java gives up when two neighbours on different axes both connect.
Direction? bearingPreferredFacing(
  Pos pos,
  bool Function(Pos neighbour, Direction side) shaftTowards,
) {
  Direction? preferred;
  for (final side in Direction.values) {
    if (!shaftTowards(pos.relative(side), side)) continue;
    if (preferred != null && preferred.axis != side.axis) return null;
    preferred = side;
  }
  return preferred;
}

/// `DirectionalKineticBlock.getStateForPlacement`: the `facing` of the placed bearing.
///
/// ```java
/// Direction preferred = getPreferredFacing(context);
/// if (preferred == null || (player != null && player.isShiftKeyDown())) {
///     Direction nearest = context.getNearestLookingDirection();
///     return state.setValue(FACING, sneaking ? nearest : nearest.getOpposite());
/// }
/// return state.setValue(FACING, preferred.getOpposite());
/// ```
Direction bearingFacingForPlacement({
  required Direction nearestLooking,
  required bool sneaking,
  required bool hasPlayer,
  Direction? preferred,
}) {
  if (preferred == null || (hasPlayer && sneaking)) {
    return hasPlayer && sneaking ? nearestLooking : nearestLooking.opposite;
  }
  return preferred.opposite;
}

/// [bearingPlacementRules] evaluated like the host does: the first rule that applies and gives a
/// value wins (`DynamicBlockInfo::state_for_placement` in
/// `crates/pumpkin-data/src/block_registry.rs`). This is the `facing` a placed bearing gets, and
/// it must equal [bearingFacingForPlacement].
///
/// [shaftTowards] is the same callback as [bearingPreferredFacing]'s.
Direction bearingFacingFromRules(
  Pos pos, {
  required Direction nearestLooking,
  required bool sneaking,
  required bool Function(Pos neighbour, Direction side) shaftTowards,
}) {
  for (final rule in bearingPlacementRules) {
    if (rule.whenSneaking != null && rule.whenSneaking != sneaking) continue;
    final value = switch (rule.source) {
      PlacementSourceKind.neighbourShaft => () {
        final preferred = bearingPreferredFacing(pos, shaftTowards);
        return preferred == null
            ? null
            : (rule.opposite ? preferred.opposite : preferred).serializedName;
      }(),
      PlacementSourceKind.lookingDirection =>
        (rule.opposite ? nearestLooking.opposite : nearestLooking)
            .serializedName,
      _ => throw StateError('the bearing rules use ${rule.source.name}'),
    };
    final direction = value == null ? null : Direction.byName(value);
    if (direction != null) return direction;
  }
  // `bearingPlacementRules` ends with an unconditional look rule, so this cannot happen.
  throw StateError('the bearing placement rules gave no facing');
}

/// `BlockPlaceContext.getNearestLookingDirection()` from the player's look.
///
/// `Direction.orderedByNearest(entity)`: the dominant of the six directions of the view vector,
/// where a look that is not straight up or down counts as its horizontal direction.
Direction nearestLookingFromLook(double yawDegrees, double pitchDegrees) {
  const radians = math.pi / 180;
  final yaw = yawDegrees * radians;
  final pitch = pitchDegrees * radians;
  final look = (
    -math.sin(yaw) * math.cos(pitch),
    -math.sin(pitch),
    math.cos(yaw) * math.cos(pitch),
  );
  return Direction.orderedByNearest(look.$1, look.$2, look.$3).first;
}

/// What a right click on a bearing does (`useItemOn`).
enum BearingUse {
  /// Assemble (or, when running, disassemble) the bearing.
  assemble,

  /// `InteractionResult.FAIL`: the click is not handled, other actions still run.
  fail,

  /// `InteractionResult.TRY_WITH_EMPTY_HAND`: not handled, the held item may place its block.
  tryEmptyHand,
}

/// `MechanicalBearingBlock.useItemOn` as a decision.
///
/// Java only assembles for an *empty* stack; with an item it returns `TRY_WITH_EMPTY_HAND`, so
/// the item is used and a held block is placed against the bearing. The host fires the
/// `useWithoutItem` hook for any click the held item did not handle, with the held stack in
/// `event.item` (see `fire_use` in the host's `block/blocks/dynamic.rs`), so the Dart handler must
/// make the same distinction: [holdingItem] is `!stack.isEmpty()`.
BearingUse bearingUse({
  required bool mayBuild,
  required bool sneaking,
  required bool holdingItem,
}) {
  // `player.mayBuild()`: adventure and spectator players cannot use a bearing.
  if (!mayBuild) return BearingUse.fail;
  if (sneaking) return BearingUse.fail;
  if (holdingItem) return BearingUse.tryEmptyHand;
  return BearingUse.assemble;
}

/// Where a click on [clickedPos]'s [clickedFace] places the held block.
///
/// The host replaces the clicked block when it can be replaced (air, water, a replaceable
/// block), otherwise the new block goes into the neighbour on the clicked face. A bearing is not
/// replaceable, so a click on its end places into the block next to that end.
Pos bearingPlacementPos(
  Pos clickedPos,
  Direction clickedFace, {
  bool replaceable = false,
}) => replaceable ? clickedPos : clickedPos.relative(clickedFace);

/// `BearingBlock.hasShaftTowards`: the shaft connects through the face opposite the bearing's
/// `facing`, so the `facing` side is the end a block can be placed against.
bool bearingHasShaftTowards(Direction facing, Direction face) =>
    face == facing.opposite;
