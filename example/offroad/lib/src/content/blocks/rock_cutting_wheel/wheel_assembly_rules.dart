// `RockCuttingWheelBlock`'s contraption assembly rules: whether a wheel is attached
// towards a direction, and whether it supports what that direction holds.
//
// Java registers both as `BlockMovementChecksImpl` checks in the block's static
// initializer; the host wrappers are `rockCuttingWheelAttachedCheck` /
// `rockCuttingWheelNotSupportiveCheck` in the block file, this is the rule they share.
//
// Pure: no host imports, so the VM tests check every direction.
//
// Java: `content/blocks/rock_cutting_wheel/RockCuttingWheelBlock.java:12-33`.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;

import '../../../index/offroad_ids.dart';

/// Whether [state] is a rock cutting wheel.
bool isRockCuttingWheel(BState state) => state.key == OffroadIds.rockCuttingWheel;

/// `state.getValue(FACING)` of a wheel, `north` when the state carries no facing.
Direction rockCuttingWheelFacing(BState state) => state.dir('facing') ?? Direction.north;

/// Whether the wheel's face points at [direction] (`direction.equals(state.getValue(FACING))`).
///
/// Java's *attached* check answers `SUCCESS` for every direction but that one and
/// `FAIL` for it (`:14-20`): the wheel is not attached to the block in front of it, so a
/// contraption never drags a neighbour in through the wheel's face. Its *not supportive*
/// check answers `FAIL` for that direction (`:25-31`), which stops a neighbour's capture
/// at the same face. The same comparison answers both, which is why it lives here once.
bool rockCuttingWheelFacesDirection(BState state, Direction direction) =>
    isRockCuttingWheel(state) && rockCuttingWheelFacing(state) == direction;