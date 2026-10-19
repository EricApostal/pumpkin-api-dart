// `FlapDisplayBlock` (pure): the multi block logic of the display board - which blocks connect into
// one board, the `up` / `down` connection flags, the placement state - over [BState] and
// [BlockGetter]. The host side (behaviour, use, ticks) is in `flap_display_blocks.dart`.
//
// Java -> Dart: `HORIZONTAL_FACING` is the `facing` property, `UP` / `DOWN` the boolean `up` /
// `down`, `WATERLOGGED` the `waterlogged` flag.
import '../../api/block_state.dart';
import '../../common/common.dart';

/// `FlapDisplayBlock`.
abstract final class FlapDisplayBlock {
  static const String key = 'create:display_board';
  static const String facingProperty = 'facing';
  static const String upProperty = 'up';
  static const String downProperty = 'down';
  static const String waterloggedProperty = 'waterlogged';

  /// `defaultBlockState()`: `up=false, down=false, waterlogged=false, facing=north`.
  static BState defaultBlockState() => const BState(key, {
    downProperty: 'false',
    facingProperty: 'north',
    upProperty: 'false',
    waterloggedProperty: 'false',
  });

  /// `HorizontalKineticBlock.getStateForPlacement` + `FlapDisplayBlock.getStateForPlacement`.
  ///
  /// [clickedFace] and [horizontalDirection] come from the placing context (`getClickedFace`,
  /// `getHorizontalDirection`), [sneaking] is `player.isShiftKeyDown()` (false without a player),
  /// [inWater] whether the clicked position holds water.
  static BState getStateForPlacement(
    BlockGetter level,
    Pos clickedPos,
    Direction clickedFace,
    Direction horizontalDirection, {
    required bool sneaking,
    required bool hasPlayer,
    required bool inWater,
  }) {
    final placedOnPos = clickedPos.relative(clickedFace.opposite);
    final blockState = level.stateAt(placedOnPos);
    var stateForPlacement = defaultBlockState();

    if (blockState.key != key || (hasPlayer && sneaking)) {
      // HorizontalKineticBlock.getStateForPlacement
      stateForPlacement = stateForPlacement.setValue(facingProperty, horizontalDirection.opposite.serializedName);
    } else {
      final otherFacing = blockState[facingProperty]!;
      stateForPlacement = stateForPlacement.setValue(facingProperty, otherFacing);
    }

    return updateColumn(level, clickedPos, stateForPlacement.setFlag(waterloggedProperty, inWater), true);
  }

  /// `updateColumn(level, pos, state, present)`: sets the `up` / `down` flags of [state] from the
  /// boards next to it along the connection axis.
  static BState updateColumn(BlockGetter level, Pos pos, BState state, bool present) {
    final axis = getConnectionAxis(state);

    for (final connection in Iterate.directionsInAxis(Axis.y)) {
      var connect = true;

      move:
      for (final movement in Iterate.directionsInAxis(axis)) {
        var currentPos = pos;
        for (var i = 0; i < 1000; i++) {
          if (!level.isLoaded(currentPos)) break;

          final other1 = currentPos == pos ? state : level.stateAt(currentPos);
          final other2 = level.stateAt(currentPos.relative(connection));
          final col1 = canConnect(state, other1);
          final col2 = canConnect(state, other2);
          currentPos = currentPos.relative(movement);

          if (!col1 && !col2) break;
          if (col1 && col2) continue;

          connect = false;
          break move;
        }
      }
      state = setConnection(state, connection, connect);
    }
    return state;
  }

  /// `canConnect(state, other)`: the same block facing the same way.
  static bool canConnect(BState state, BState other) =>
      other.key == key && state[facingProperty] == other[facingProperty];

  /// `getConnectionAxis(state)`: the axis of the clockwise neighbour of the facing.
  static Axis getConnectionAxis(BState state) => state.dir(facingProperty)!.clockWise.axis;

  /// `getConnection(state, side)`.
  static bool getConnection(BState state, Direction side) {
    final property = side == Direction.down ? downProperty : (side == Direction.up ? upProperty : null);
    return property != null && state.flag(property);
  }

  /// `setConnection(state, side, connect)`.
  static BState setConnection(BState state, Direction side, bool connect) {
    final property = side == Direction.down ? downProperty : (side == Direction.up ? upProperty : null);
    if (property != null) state = state.setFlag(property, connect);
    return state;
  }

  /// `updatedShapeInner(state, direction, neighborState, ...)` without the water tick (the caller
  /// schedules it for waterlogged states).
  static BState updatedShapeInner(BState state, Direction direction, BState neighborState) {
    if (!canConnect(state, neighborState)) return setConnection(state, direction, false);
    if (direction.axis == getConnectionAxis(state)) {
      // withPropertiesOf(neighborState), keeping the waterlogged flag
      return neighborState.setValue(waterloggedProperty, state[waterloggedProperty]!);
    }
    return setConnection(state, direction, getConnection(neighborState, direction.opposite));
  }

  /// `tick`: the state the board at [pos] should have, or `null` when it is fine (the neighbour
  /// below along the connection axis connects).
  static BState? tickState(BlockGetter level, Pos pos, BState state) {
    if (state.key != key) return null;
    final belowPos = pos.relative(
      Direction.fromAxisAndDirection(getConnectionAxis(state), AxisDirection.negative),
    );
    final belowState = level.stateAt(belowPos);
    if (!canConnect(state, belowState)) return updateColumn(level, pos, state, true);
    return null;
  }

  /// `affectNeighborsAfterRemoval`: the new states of the boards next to the removed one at [pos]
  /// that connected to it.
  static Map<Pos, BState> neighboursAfterRemoval(BlockGetter level, Pos pos, BState removed) {
    final result = <Pos, BState>{};
    for (final d in Iterate.directionsInAxis(getConnectionAxis(removed))) {
      final relative = pos.relative(d);
      final adjacent = level.stateAt(relative);
      if (canConnect(removed, adjacent)) result[relative] = updateColumn(level, relative, adjacent, false);
    }
    return result;
  }

  /// The `getController` walk: the position of the board at the top left of the board that contains
  /// [pos] with state [state] (from `FlapDisplayBlockEntity.getController`), `null` when the walk
  /// ends without a candidate. [isController] says whether the block entity at a position is a
  /// controller.
  static Pos? findControllerPos(BlockGetter level, Pos start, BState state, bool Function(Pos) isController) {
    var pos = start;
    final side = state.dir(facingProperty)!.clockWise;

    for (var i = 0; i < 64; i++) {
      final other = level.stateAt(pos);

      if (other.has(upProperty) && other.flag(upProperty)) {
        pos = pos.relative(Direction.up);
        continue;
      }

      final next = level.stateAt(pos.relative(side));
      if (!(next.has(upProperty) ? next.flag(upProperty) : true)) {
        pos = pos.relative(side);
        continue;
      }

      return isController(pos) ? pos : null;
    }

    return null;
  }

  /// `getLineIndexAt(yCoord)` for a controller at height [y] with [ySize] rows.
  static int getLineIndexAt(int y, int ySize, double yCoord) =>
      (2 * (y - yCoord + 1)).floorToDouble().clamp(0, ySize * 2).toInt();
}
