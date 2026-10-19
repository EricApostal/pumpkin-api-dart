// `ConnectedPillarBlock` (pure): the north/east/south/west flags of a palette pillar say
// whether the pillar continues on that side of a column of pillars, so the client can pick
// the connected texture. Port of `updateColumn`, `updateShape`, `connection(axis, side)`.
import '../api/block_state.dart';
import '../common/data.dart';
import '../common/direction.dart';
import '../common/pos.dart';

/// `ConnectedPillarBlock.connection(axis, side)`: the property name for [side] of a pillar
/// along [axis], or `null` for the sides along the axis and for unmapped sides.
String? pillarConnectionProperty(Axis axis, Direction side) {
  if (side.axis == axis) return null;
  switch (axis) {
    case Axis.x:
      return switch (side) {
        Direction.up => 'east',
        Direction.north => 'north',
        Direction.south => 'south',
        Direction.down => 'west',
        _ => null,
      };
    case Axis.y:
      return switch (side) {
        Direction.east => 'east',
        Direction.north => 'north',
        Direction.south => 'south',
        Direction.west => 'west',
        _ => null,
      };
    case Axis.z:
      return switch (side) {
        Direction.up => 'west',
        Direction.west => 'south',
        Direction.east => 'north',
        Direction.down => 'east',
        _ => null,
      };
  }
}

/// `ConnectedPillarBlock.getConnection`.
bool pillarGetConnection(BState state, Direction side) {
  final axis = state.axisOf('axis');
  if (axis == null) return false;
  final p = pillarConnectionProperty(axis, side);
  return p != null && state.flag(p);
}

/// `ConnectedPillarBlock.setConnection`.
BState pillarSetConnection(BState state, Direction side, bool connect) {
  final axis = state.axisOf('axis');
  if (axis == null) return state;
  final p = pillarConnectionProperty(axis, side);
  return p == null ? state : state.setFlag(p, connect);
}

/// `ConnectedPillarBlock.canConnect(state, other)`: the same block on the same axis.
bool pillarCanConnect(BState state, BState other) =>
    other.key == state.key && state.axisOf('axis') == other.axisOf('axis');

/// `ConnectedPillarBlock.updateColumn`: walks both ways along the pillar axis and connects a
/// side when every pillar of the column (as far as it is loaded, at most 1000 blocks) has a
/// pillar next to it on that side too.
BState pillarUpdateColumn(BlockGetter level, Pos pos, BState state) {
  final axis = state.axisOf('axis');
  if (axis == null) return state;
  for (final connection in Iterate.directions) {
    if (connection.axis == axis) continue;
    var connect = true;
    move:
    for (final movement in Iterate.directionsInAxis(axis)) {
      var current = pos;
      for (var i = 0; i < 1000; i++) {
        if (!level.isLoaded(current)) break;
        final other1 = current == pos ? state : level.stateAt(current);
        final other2 = level.stateAt(current.relative(connection));
        final col1 = pillarCanConnect(state, other1);
        final col2 = pillarCanConnect(state, other2);
        current = current.relative(movement);
        if (!col1 && !col2) break;
        if (col1 && col2) continue;
        connect = false;
        break move;
      }
    }
    state = pillarSetConnection(state, connection, connect);
  }
  return state;
}

/// `ConnectedPillarBlock.updateShape`: the new state of the pillar [state] after the
/// neighbour [neighbour] in direction [direction] changed.
BState pillarUpdateShape(BState state, Direction direction, BState neighbour) {
  if (!pillarCanConnect(state, neighbour)) return pillarSetConnection(state, direction, false);
  if (direction.axis == state.axisOf('axis')) {
    // `withPropertiesOf(neighbourState)`: adopt the neighbour's connections.
    return neighbour.key == state.key ? neighbour : state;
  }
  return pillarSetConnection(state, direction, pillarGetConnection(neighbour, direction.opposite));
}

/// `LayeredBlock.getStateForPlacement` / `RotatedPillarBlock`: the axis of a placed pillar is the
/// clicked face's axis, or the axis of the pillar it is placed against (unless sneaking).
String pillarPlacementAxis({required Direction clickedFace, BState? placedOn, required String selfKey, bool sneaking = false}) {
  if (placedOn != null && placedOn.key == selfKey && !sneaking) {
    return placedOn['axis'] ?? clickedFace.axis.serializedName;
  }
  return clickedFace.axis.serializedName;
}
