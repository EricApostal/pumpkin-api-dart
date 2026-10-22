// `AbstractDirectionalAxisBlock`'s placement: the `facing` a click gives and the
// `axis_along_first` that goes with it. Shared by the borehead bearing and the rock
// cutting wheel (both are `AbstractDirectionalAxisBlock`s in Java).
//
// Pure: no host imports, so the VM tests can check every clicked face.
//
// Java: `simulated/common/.../content/blocks/util/AbstractDirectionalAxisBlock.java:32-53`
//       (`getStateForPlacement`), `:97-100` (`getFacingForPlacement`),
//       `:50-53` (`getAxisAlignmentForPlacement`).
// ignore_for_file: implementation_imports
import 'package:create/src/common/direction.dart' show Axis, Direction;

/// `Direction.fromYRot(yaw)` (`BlockPlaceContext.getHorizontalDirection()`): the
/// horizontal direction a player looking at [yaw] degrees faces.
///
/// `Direction.horizontals` is Java's `get2DDataValue` order (south, west, north, east),
/// which is the order `from2DDataValue` numbers.
Direction horizontalLookDirection(double yaw) =>
    Direction.horizontals[((yaw / 90) + 0.5).floor() & 3];

/// `AbstractDirectionalAxisBlock.getStateForPlacement`:
/// `AXIS_ALONG_FIRST_COORDINATE = isSecondaryUseActive() != alongFirst`.
///
/// `alongFirst` is the clicked face's own axis being `Z` when the face is horizontal, and
/// the player's horizontal look axis being `Z` when it is vertical
/// (`getAxisAlignmentForPlacement`, the case a click on the top or bottom face gives).
/// [facing] is `getFacingForPlacement(...) = context.getClickedFace()`; [sneaking] is
/// `isSecondaryUseActive()`.
bool axisAlongFirstForPlacement({
  required Direction facing,
  required Direction horizontalLook,
  required bool sneaking,
}) {
  final faceAxis = facing.axis;
  final alongFirst = faceAxis.isHorizontal ? faceAxis == Axis.z : horizontalLook.axis == Axis.z;
  return sneaking != alongFirst;
}