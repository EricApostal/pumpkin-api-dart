// What state a Simulated block gets when a player places it, ported from the Java
// `getStateForPlacement` of each block.
//
// The host's placement rules (`PlacementRule`) cover `facing` and `axis`, but not
// the vanilla `FACE` (floor / wall / ceiling) pair of
// `FaceAttachedHorizontalDirectionalBlock`, and not the booleans that read the
// clicked face (`SteeringWheelBlock.ON_FLOOR`). Those blocks therefore had no
// placement state at all: the host wrote the registration's default state
// (`facing: north, face: wall`) whatever the player looked at, which is the
// "everything is placed rotated" the physics assembler was reported with. The
// port fixes the state in the block's `onPlaced`, the way Create's
// `decoration` module does it for ladders, doors, girders and placards
// (`behaviour_support.dart:fixPlacedState`).
//
// Java sources, from `simulated-neoforge-26.3-1.3.2.jar` (bytecode read with
// `javap -c`, the classes are the ones the client runs):
//
//   content/blocks/physics_assembler/PhysicsAssemblerBlock   — no override; inherits
//   content/blocks/throttle_lever/ThrottleLeverBlock         — no override; inherits
//     net/minecraft/world/level/block/FaceAttachedHorizontalDirectionalBlock.getStateForPlacement
//   content/blocks/steering_wheel/SteeringWheelBlock.getStateForPlacement
//   content/blocks/torsion_spring/TorsionSpringBlock         — `super` + POWERED
//   content/blocks/swivel_bearing/SwivelBearingBlock         — no override; inherits
//     com/simibubi/create/content/kinetics/base/DirectionalKineticBlock.getStateForPlacement
//
// `DirectionalKineticBlock` is Create's, and the port already evaluates its rule
// for the bearing family: those blocks use `bearingPlacementRules` from
// `package:create/src/contraptions/bearing/bearing_placement.dart` (the host
// applies them before the block is written, `DynamicBlock::on_place`), so this
// file only needs the vanilla face-attached pair and the steering wheel.
//
// Pure: no host imports, so the tests run on the plain Dart VM.
//
// Java: the two `getStateForPlacement` methods named above.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;

/// `BlockPlaceContext.getNearestLookingDirections()`: the player's ordering by
/// nearest look, with the opposite of the clicked face moved to the front.
///
/// ```java
/// Direction[] directions = Direction.orderedByNearest(player);
/// if (!this.replaceClicked) {
///     Direction clicked = this.getClickedFace();
///     for (int i = 0; i < directions.length; i++) {
///         if (directions[i] == clicked.getOpposite()) {
///             if (i > 0) {
///                 System.arraycopy(directions, 0, directions, 1, i);
///                 directions[0] = clicked.getOpposite();
///             }
///             break;
///         }
///     }
/// }
/// return directions;
/// ```
///
/// [orderedByNearest] is `Direction.orderedByNearest(player)`; [replacingClickedOnBlock]
/// is `BlockPlaceContext.replaceClicked`, true when the clicked block was
/// replaceable and the new block goes into the clicked position.
List<Direction> nearestLookingDirections({
  required List<Direction> orderedByNearest,
  required Direction clickedFace,
  required bool replacingClickedOnBlock,
}) {
  if (replacingClickedOnBlock) return orderedByNearest;
  final wanted = clickedFace.opposite;
  final index = orderedByNearest.indexOf(wanted);
  if (index <= 0) return orderedByNearest;
  return [
    wanted,
    ...orderedByNearest.take(index),
    ...orderedByNearest.skip(index + 1),
  ];
}

/// The first horizontal direction of `Direction.orderedByNearest(view)`: the
/// dominant horizontal look direction.
///
/// Java picks the horizontal entry of its ordered triple, which is the X-axis
/// direction when `|x| > |z|` (ties go to the Z axis) and the Z-axis direction
/// otherwise, each by the sign of its component:
///
/// ```java
/// boolean east = x > 0.0F;                 // f4 = sin(-yaw)
/// boolean south = z > 0.0F;                // f5 = cos(-yaw)
/// Direction first = |x| > |z| ? (east ? EAST : WEST) : (south ? SOUTH : NORTH);
/// ```
Direction firstHorizontalLooking((double, double, double) view) {
  final (x, _, z) = view;
  if (x.abs() > z.abs()) return x > 0 ? Direction.east : Direction.west;
  return z > 0 ? Direction.south : Direction.north;
}

/// The first vertical direction of `Direction.orderedByNearest(view)`: `up` when
/// the view vector points up, `down` otherwise (a level look counts as `down`,
/// `flag1 = f2 < 0` with `f2 = sin(pitch)`).
Direction firstVerticalLooking((double, double, double) view) =>
    view.$2 > 0 ? Direction.up : Direction.down;

/// The state a face-attached block gets, like vanilla's
/// `FaceAttachedHorizontalDirectionalBlock.getStateForPlacement`:
///
/// ```java
/// for (Direction direction : context.getNearestLookingDirections()) {
///     BlockState state;
///     if (direction.getAxis() == Direction.Axis.Y) {
///         state = defaultBlockState()
///             .setValue(FACE, direction == Direction.UP ? AttachFace.CEILING : AttachFace.FLOOR)
///             .setValue(FACING, context.getHorizontalDirection());
///     } else {
///         state = defaultBlockState()
///             .setValue(FACE, AttachFace.WALL)
///             .setValue(FACING, direction.getOpposite());
///     }
///     if (state.canSurvive(context.getLevel(), context.getClickedPos())) {
///         return state;
///     }
/// }
/// return null;
/// ```
///
/// [nearestLooking] is [nearestLookingDirections]' answer, [horizontalDirection] is
/// `context.getHorizontalDirection()` (`player.getDirection()`), and [canSurvive] is
/// `state.canSurvive(level, pos)` for the connected direction the candidate uses:
/// `FACE`'s direction for a floor or a ceiling, `FACING` for a wall (see
/// [faceAttachedConnectedDirection]). The block that is placed is the clicked block
/// itself for [nearestLookingDirections]' `replacingClickedOnBlock` case, so the
/// caller reads the support from its own position either way.
///
/// `null` is `BlockState.canSurvive` failing for every direction, which Java answers
/// with no placement at all.
BState? faceAttachedStateForPlacement({
  required BState defaultState,
  required List<Direction> nearestLooking,
  required Direction horizontalDirection,
  required bool Function(Direction connected) canSurvive,
}) {
  for (final direction in nearestLooking) {
    final connected = faceAttachedConnectedDirection(direction);
    final state = direction.isVertical
        ? defaultState
              .setValue('face', direction == Direction.up ? 'ceiling' : 'floor')
              .setDir('facing', horizontalDirection)
        : defaultState.setValue('face', 'wall').setDir('facing', direction.opposite);
    if (canSurvive(connected)) return state;
  }
  return null;
}

/// `FaceAttachedHorizontalDirectionalBlock.getConnectedDirection` for a candidate
/// direction [looking]: `down` for a ceiling, `up` for a floor, the facing for a wall.
///
/// The wall case is `FACING` itself, which is the opposite of the look direction the
/// block attached to ([looking]), so a wall-attached block hangs on the block the
/// player looked at.
Direction faceAttachedConnectedDirection(Direction looking) {
  if (!looking.isVertical) return looking.opposite;
  return looking == Direction.up ? Direction.down : Direction.up;
}

/// The state `SteeringWheelBlock.getStateForPlacement` gives:
///
/// ```java
/// BlockState state = withWater(defaultBlockState(), context);
/// boolean onFloor = switch (context.getClickedFace()) {
///     case UP -> true;
///     case DOWN -> false;
///     default -> Arrays.stream(context.getNearestLookingDirections())
///         .filter(d -> d.getAxis().isVertical()).findFirst().get() == Direction.DOWN;
/// };
/// Direction facing = Arrays.stream(context.getNearestLookingDirections())
///     .filter(d -> d.getAxis().isHorizontal()).findFirst().get();
/// return state.setValue(FACING, facing.getOpposite()).setValue(ON_FLOOR, onFloor);
/// ```
///
/// The Java reads the first vertical and the first horizontal entry of the ordered
/// look directions, which [firstVerticalLooking] and [firstHorizontalLooking] give
/// directly from the view vector (the ordered list itself is only needed for the
/// face-attached loop, where the support check picks the winner).
BState steeringWheelStateForPlacement({
  required BState defaultState,
  required (double, double, double) view,
  required Direction clickedFace,
}) {
  final onFloor = switch (clickedFace) {
    Direction.up => true,
    Direction.down => false,
    _ => firstVerticalLooking(view) == Direction.down,
  };
  return defaultState
      .setDir('facing', firstHorizontalLooking(view).opposite)
      .setFlag('on_floor', onFloor);
}