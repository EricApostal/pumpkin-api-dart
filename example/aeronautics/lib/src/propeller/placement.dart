// The placement of the propeller family as pure functions of the click and the
// player's look, plus the host placement rules that have to agree with them.
//
// Java (`create-aeronautics-bundled` 26.3-1.3.2):
// `content/blocks/propeller/small/BasePropellerBlock.getStateForPlacement` and
// `content/blocks/propeller/small/smart_propeller/SmartPropellerBlock.getStateForPlacement`,
// on top of Create's `DirectionalKineticBlock.getPreferredFacing` and
// `HorizontalAxisKineticBlock.getStateForPlacement`.
//
// The small propellers do **not** use `DirectionalKineticBlock`'s own
// `getStateForPlacement`: `BasePropellerBlock` overrides it and falls back to the *clicked face*,
// not to the nearest looking direction:
//
//   Direction preferred = getPreferredFacing(context);
//   if (preferred == null) preferred = context.getClickedFace().getOpposite();
//   return defaultBlockState().setValue(FACING,
//       player != null && player.isShiftKeyDown() ? preferred : preferred.getOpposite());
//
// The look direction is only right while the look and the click agree: clicking a top face while
// looking level gives `up` from the click and a horizontal `facing` from the look, which is the
// measured `facing=south` on a case whose answer is `facing=up`.
//
// Pure: no host imports, so the VM tests can read the rules back.
// ignore_for_file: implementation_imports
import 'package:create/src/contraptions/bearing/bearing_placement.dart'
    show bearingShaftNeighbours;
import 'package:create/src/kinetics/geometry.dart' show Dir, KAxis, KPos, KState;
import 'package:create/src/kinetics/placement.dart'
    show PlacementContext, preferredHorizontalAxis;
import 'package:pumpkin_api/pumpkin_api_core.dart'
    show PlacementRule, PlacementSourceKind;

/// The host placement rules of the small propellers: [propellerFacingForPlacement] in order.
///
/// The host applies them before it writes the block, so the first state the client sees is the
/// right one. Every rule is guarded by [PlacementRule.whenSneaking] because Java's `sneaking`
/// term flips the facing for every source; the two `clickedFace` rules are the fallback
/// `BasePropellerBlock` adds, and they only fire when no shaft neighbour decided.
const List<PlacementRule> propellerPlacementRules = [
  // A neighbouring shaft, not sneaking: `preferred.getOpposite()`.
  PlacementRule.neighbourShaft(
    'facing',
    bearingShaftNeighbours,
    opposite: true,
    whenSneaking: false,
  ),
  // A neighbouring shaft, sneaking: `preferred`.
  PlacementRule.neighbourShaft(
    'facing',
    bearingShaftNeighbours,
    opposite: false,
    whenSneaking: true,
  ),
  // No shaft, not sneaking: `clickedFace.getOpposite().getOpposite()`, i.e. the clicked face.
  PlacementRule.clickedFace('facing', whenSneaking: false),
  // No shaft, sneaking: `clickedFace.getOpposite()`.
  PlacementRule.clickedFace('facing', opposite: true, whenSneaking: true),
];

/// `BasePropellerBlock.getStateForPlacement`: the `facing` a placed propeller gets.
///
/// [preferred] is `DirectionalKineticBlock.getPreferredFacing` (the side a neighbouring shaft
/// sticks into), `null` when there is none or two lie on different axes.
Dir propellerFacingForPlacement({
  required Dir clickedFace,
  required bool sneaking,
  required bool hasPlayer,
  Dir? preferred,
}) {
  final face = preferred ?? clickedFace.opposite;
  return hasPlayer && sneaking ? face : face.opposite;
}

/// [propellerPlacementRules] evaluated like the host does: the first rule that applies and gives
/// a value wins (`DynamicBlockInfo::state_for_placement` in
/// `crates/pumpkin-data/src/block_registry.rs`). It has to equal
/// [propellerFacingForPlacement].
///
/// [shaftTowards] is `IRotate.hasShaftTowards(level, neighbour, neighbourState, side.opposite)`
/// for the neighbour on `side`, the same callback as `bearingPreferredFacing`.
Dir propellerFacingFromRules(
  KPos pos, {
  required Dir clickedFace,
  required bool sneaking,
  required bool Function(KPos neighbour, Dir side) shaftTowards,
}) {
  for (final rule in propellerPlacementRules) {
    if (rule.whenSneaking != null && rule.whenSneaking != sneaking) continue;
    final Dir? value = switch (rule.source) {
      PlacementSourceKind.neighbourShaft => _withOpposite(
        _preferredSide(pos, shaftTowards),
        rule.opposite,
      ),
      PlacementSourceKind.clickedFace => rule.opposite
          ? clickedFace.opposite
          : clickedFace,
      _ => throw StateError('the propeller rules use ${rule.source.name}'),
    };
    if (value != null) return value;
  }
  // The last rule is an unconditional `clickedFace`, so this cannot happen.
  throw StateError('the propeller placement rules gave no facing');
}

Dir? _withOpposite(Dir? direction, bool opposite) => direction == null
    ? null
    : (opposite ? direction.opposite : direction);

/// `DirectionalKineticBlock.getPreferredFacing`: the side a neighbouring shaft sticks into.
/// `null` when there is none, or when two neighbours on different axes both connect.
Dir? _preferredSide(
  KPos pos,
  bool Function(KPos neighbour, Dir side) shaftTowards,
) {
  Dir? preferred;
  for (final side in Dir.values) {
    if (!shaftTowards(pos.relative(side), side)) continue;
    if (preferred != null && preferred.axis != side.axis) return null;
    preferred = side;
  }
  return preferred;
}

/// `SmartPropellerBlock.getStateForPlacement`'s hinge axis:
/// `HorizontalAxisKineticBlock`'s axis (the preferred horizontal axis, else
/// `getHorizontalDirection().getClockWise().getAxis()`) with the block's own swap applied.
KAxis smartPropellerHorizontalAxis(PlacementContext ctx) {
  final axis = preferredHorizontalAxis(ctx) ?? ctx.horizontal.clockWise(KAxis.y).axis;
  return axis == KAxis.x ? KAxis.z : KAxis.x;
}

/// `SmartPropellerBlock.getStateForPlacement`: the state the player's click and look give,
/// starting from the state the host placed.
KState smartPropellerPlacement(PlacementContext ctx, KState placed) => placed
    .set('horizontal_axis', smartPropellerHorizontalAxis(ctx).name)
    .setFlag('ceiling', ctx.clickedFace == Dir.down)
    .setFlag('reversed', false);
