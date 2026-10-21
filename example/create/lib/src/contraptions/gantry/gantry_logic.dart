// The pure rules of the gantry carriage and the gantry contraption entity: the shaft axis a
// carriage can ride, the pinion modifier, the placement-time axis cycling, whether the carriage
// may stay where it is, and the end-of-shaft rule of a moving gantry. No host imports, so
// `dart test` covers the direction math.
//
// Java: `content/contraptions/gantry/{GantryCarriageBlock,GantryCarriageBlockEntity,
// GantryContraptionEntity}`.
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockStateLayout, PlacementRule;

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../kinetics/block_defs.dart';
import '../../kinetics/geometry.dart';

const String gantryCarriageKey = 'create:gantry_carriage';
const String gantryShaftKey = 'create:gantry_shaft';

/// `GantryCarriageBlock.getStateForPlacement`: `DirectionalAxisKineticBlock.getStateForPlacement`
/// builds the state from `getFacingForPlacement`, which the carriage overrides to
/// `context.getClickedFace()`; the carriage then cycles `axis_along_first` from the shaft behind
/// that facing ([gantryPlacementState]). No shaft-neighbour preference and no look fallback.
const List<PlacementRule> gantryCarriagePlacementRules = [
  PlacementRule.clickedFace('facing'),
];

/// Converts a kinetic direction to a vanilla direction.
Direction toDirection2(Dir d) => Direction.values[d.index];

/// `GantryCarriageBlock.getValidGantryShaftAxis`: the axis the carriage can ride. The shaft may
/// not run along the carriage's facing axis nor along the pinion's rotation axis.
Axis getValidGantryShaftAxis(BState state) {
  final facingAxis = state.dir('facing')?.axis ?? Axis.y;
  final rotationAxis = const DirectionalAxisBlockDef().rotationAxis(
    KState(state.key, state.props),
  );
  for (final axis in Axis.values) {
    if (axis.name != rotationAxis.name && axis != facingAxis) return axis;
  }
  return Axis.y;
}

/// `GantryCarriageBlock.getValidGantryPinionAxis`: the axis the pinion may turn around.
Axis getValidGantryPinionAxis(BState state, Axis shaftAxis) {
  final facingAxis = state.dir('facing')?.axis ?? Axis.y;
  for (final axis in Axis.values) {
    if (axis != shaftAxis && axis != facingAxis) return axis;
  }
  return Axis.y;
}

/// `GantryCarriageBlock.isValidGantryShaftAxis`.
bool isValidGantryShaftAxis(BState pinionState, BState gantryState) =>
    getValidGantryShaftAxis(pinionState) ==
    (gantryState.dir('facing')?.axis ?? Axis.y);

/// `GantryCarriageBlock.canSurvive`: a gantry shaft behind the carriage, on another axis.
bool gantryCarriageCanSurvive(BState state, BState behind) =>
    behind.key == gantryShaftKey &&
    (behind.dir('facing')?.axis ?? Axis.y) !=
        (state.dir('facing')?.axis ?? Axis.y);

/// `GantryCarriageBlock.cycleAxisIfNecessary`: the `axis_along_first` that makes the shaft behind
/// the carriage the valid shaft axis.
BState cycleGantryAxisIfNecessary(
  BState state,
  Direction direction,
  BState other,
) {
  if (other.key != gantryShaftKey) return state;
  final shaftAxis = other.dir('facing')?.axis ?? Axis.y;
  if (shaftAxis == direction.axis) return state;
  if (isValidGantryShaftAxis(state, other)) return state;
  return state.cycleFlag('axis_along_first');
}

/// `GantryCarriageBlock.updateShape` answered for the `update-shape` hook: the index of the new
/// state in [layout] (the layout of the carriage block), or `null` when the shaft leaves the state
/// unchanged.
///
/// The hook answers with a state index *of the block*, not a global state id (see [stateIndexIn]).
int? gantryCarriageShapeAnswer(
  BlockStateLayout layout,
  BState state,
  Direction side,
  BState other,
) {
  final next = cycleGantryAxisIfNecessary(state, side, other);
  if (next == state) return null;
  return stateIndexIn(layout, next);
}

/// `GantryCarriageBlock.getStateForPlacement`: the state the carriage at [pos] gets after
/// placing, with `axis_along_first` cycled to the shaft behind it.
///
/// The state is read from [level] at [pos]: that is the state the block is placed with (Java's
/// `state` argument). A block callback's `stateIndex` counts within the block, so it cannot be
/// used as a state id.
BState gantryPlacementState(BlockGetter level, Pos pos) {
  final state = level.stateAt(pos);
  final facing = state.dir('facing') ?? Direction.north;
  final behind = level.stateAt(pos.relative(facing.opposite));
  return cycleGantryAxisIfNecessary(state, facing.opposite, behind);
}

/// `GantryCarriageBlock.getGantryPinionModifier`: the rotation handedness between the shaft and
/// the carriage's pinion.
double getGantryPinionModifier(Direction shaft, Direction pinionDirection) {
  final shaftAxis = shaft.axis;
  final directionModifier = shaft.axisDirection.step;
  if (shaftAxis == Axis.y &&
      (pinionDirection == Direction.north ||
          pinionDirection == Direction.east)) {
    return -directionModifier.toDouble();
  }
  if (shaftAxis == Axis.x &&
      (pinionDirection == Direction.down ||
          pinionDirection == Direction.south)) {
    return -directionModifier.toDouble();
  }
  if (shaftAxis == Axis.z &&
      (pinionDirection == Direction.up || pinionDirection == Direction.west)) {
    return -directionModifier.toDouble();
  }
  return directionModifier.toDouble();
}

/// `GantryContraptionEntity.checkPinionShaft`: the direction the carriage moves along the shaft.
Direction gantryPinionMovementDirection(
  Direction shaftFacing,
  double pinionSpeed,
) => pinionSpeed < 0 ? shaftFacing.opposite : shaftFacing;

/// `GantryContraptionEntity.checkPinionShaft`: the gantry moves into the next block along the
/// shaft this tick (so the shaft must be able to assemble on, or the gantry disassembles).
bool gantryCrossedShaftEnd(
  double currentCoord,
  double nextCoord,
  double pinionSpeed,
  int shaftAxisStep,
) =>
    (currentCoord.floor() + .5 < nextCoord) !=
    (pinionSpeed * shaftAxisStep < 0);
