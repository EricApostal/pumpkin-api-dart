// Girders (pure): `GirderBlock`, `GirderEncasedShaftBlock` state logic, the placement helper
// (`GirderPlacementHelper`) and the wrench click (`GirderWrenchBehavior.handleClick`).
import '../api/block_state.dart';
import '../api/placement.dart';
import '../common/data.dart';
import '../common/direction.dart';
import '../common/pos.dart';

const String girderKey = 'create:metal_girder';
const String girderEncasedShaftKey = 'create:metal_girder_encased_shaft';

/// Which bracket (if any) is installed on the block at a position: the `facing` of the bracket
/// block state. Provided by the host side from the bracketed block entity behaviours.
typedef BracketFacingLookup = Direction? Function(Pos pos);

/// `GirderBlock.isGirder`.
bool isGirder(BState s) => s.key == girderKey || s.key == girderEncasedShaftKey;

/// `GirderBlock.isXGirder`.
bool isXGirder(BState s) =>
    (s.key == girderKey && s.flag('x')) || (s.key == girderEncasedShaftKey && s.axisOf('axis') == Axis.z);

/// `GirderBlock.isZGirder`.
bool isZGirder(BState s) =>
    (s.key == girderKey && s.flag('z')) || (s.key == girderEncasedShaftKey && s.axisOf('axis') == Axis.x);

/// The property of the girder that connects toward [d]: `x`, `z`, `top` or `bottom`.
String girderConnectionProperty(Direction d) => switch (d.axis) {
  Axis.x => 'x',
  Axis.z => 'z',
  Axis.y => d == Direction.up ? 'top' : 'bottom',
};

/// `NixieTubeBlock.getFacing` / `getConnectedDirection` of the nixie tube states (`double_face`).
Direction? nixieTubeFacing(BState s) {
  if (!s.key.endsWith('nixie_tube')) return null;
  return switch (s['double_face']) {
    'ceiling' => Direction.down,
    'floor' => Direction.up,
    _ => s.dir('facing'),
  };
}

/// `PlacardBlock.connectedDirection` (`FaceAttachedHorizontalDirectionalBlock.getConnectedDirection`).
Direction? placardConnectedDirection(BState s) {
  if (s.key != 'create:placard') return null;
  return attachedConnectedDirection(s);
}

/// `FaceAttachedHorizontalDirectionalBlock.getConnectedDirection`: the face a floor/wall/ceiling
/// attached block hangs on, looking from the block.
Direction? attachedConnectedDirection(BState s) => switch (s['face']) {
  'ceiling' => Direction.down,
  'floor' => Direction.up,
  'wall' => s.dir('facing'),
  _ => null,
};

/// `AbstractChuteBlock.getChuteFacing`.
Direction? chuteFacing(BState s) {
  if (s.key == 'create:chute') return s.dir('facing');
  if (s.key == 'create:smart_chute') return Direction.down;
  return null;
}

/// `GirderBlock.isFacingBracket`.
bool isFacingBracket(BracketFacingLookup brackets, Pos pos, Direction d) => brackets(pos.relative(d)) == d;

/// `GirderBlock.updateVerticalProperty`.
BState girderUpdateVerticalProperty(
  BlockGetter level,
  BracketFacingLookup brackets,
  Pos pos,
  BState state,
  String updateProperty,
  BState sideState,
  Direction d,
) {
  var canAttach = false;
  if (state.has('axis') && state.axisOf('axis') == Axis.y) {
    canAttach = true;
  } else if (isGirder(sideState) && isXGirder(sideState) == isZGirder(sideState)) {
    canAttach = true;
  } else if (isGirder(sideState)) {
    canAttach = true;
  } else if (sideState.has('up') && sideState.flag('up')) {
    // `WallBlock.UP`
    canAttach = true;
  } else if (nixieTubeFacing(sideState) == d) {
    canAttach = true;
  } else if (sideState.key == 'create:display_board') {
    canAttach = true;
  } else if (sideState.key.endsWith('lantern') && sideState.has('hanging') && (d == Direction.down) == sideState.flag('hanging')) {
    canAttach = true;
  } else if (sideState.key.endsWith('chain') && sideState.axisOf('axis') == Axis.y) {
    canAttach = true;
  } else if (sideState.has('face')) {
    if (sideState['face'] == 'ceiling' && d == Direction.down) {
      canAttach = true;
    } else if (sideState['face'] == 'floor' && d == Direction.up) {
      canAttach = true;
    }
  } else if (placardConnectedDirection(sideState) == d) {
    canAttach = true;
  } else if (isFacingBracket(brackets, pos, d)) {
    canAttach = true;
  }
  return canAttach ? state.setFlag(updateProperty, true) : state;
}

/// `GirderBlock.updateState`: connects [state] toward [d] when something is there to connect to.
BState girderUpdateState(BlockGetter level, BracketFacingLookup brackets, Pos pos, BState state, Direction d) {
  final axis = d.axis;
  final updateProperty = girderConnectionProperty(d);
  final sideState = level.stateAt(pos.relative(d));
  if (axis.isVertical) {
    return girderUpdateVerticalProperty(level, brackets, pos, state, updateProperty, sideState, d);
  }
  if (state.axisOf('axis') == axis) {
    state = state.setFlag(updateProperty, true);
  } else if (sideState.key == girderEncasedShaftKey && sideState.axisOf('axis') != axis) {
    state = state.setFlag(updateProperty, true);
  } else if (sideState.key == state.key && sideState.flag(updateProperty)) {
    state = state.setFlag(updateProperty, true);
  } else if (nixieTubeFacing(sideState) == d) {
    state = state.setFlag(updateProperty, true);
  } else if (placardConnectedDirection(sideState) == d) {
    state = state.setFlag(updateProperty, true);
  } else if (isFacingBracket(brackets, pos, d)) {
    state = state.setFlag(updateProperty, true);
  }
  for (final d2 in Iterate.directionsInAxis(axis == Axis.x ? Axis.z : Axis.x)) {
    final abovePos = pos.above.relative(d2);
    if (level.hasTag(abovePos, 'create:girdable_tracks')) {
      final shape = level.stateAt(abovePos)['shape'];
      if (shape == (axis == Axis.x ? 'xo' : 'zo')) {
        state = state.setFlag(updateProperty, true);
      }
    }
  }
  return state;
}

/// `GirderBlock.isConnected`: whether the girder [state] at [pos] connects to a solid thing
/// on [side].
bool girderIsConnected(BlockGetter level, BracketFacingLookup brackets, Pos pos, BState state, Direction side) {
  final axis = side.axis;
  if (state.key == girderKey && !state.flag(axis == Axis.x ? 'x' : 'z')) return false;
  if (state.key == girderEncasedShaftKey && state.axisOf('axis') == axis) return false;
  final relative = pos.relative(side);
  final blockState = level.stateAt(relative);
  if (blockState.isAir) return false;
  if (nixieTubeFacing(blockState) == side) return true;
  if (isFacingBracket(brackets, pos, side)) return true;
  if (placardConnectedDirection(blockState) == side) return true;
  if (level.collisionShapeEmpty(relative)) return false;
  if (level.isFaceSturdy(relative, side.opposite)) return true;
  return chuteFacing(blockState) == Direction.down;
}

/// `GirderBlock.updateShape`: the new state of the girder [state] at [pos] after the neighbour in
/// [direction] changed.
BState girderUpdateShape(BlockGetter level, BracketFacingLookup brackets, Pos pos, BState state, Direction direction) {
  final axis = direction.axis;
  if (axis != Axis.y) {
    if (state.axisOf('axis') != axis) {
      final prop = axis == Axis.x ? 'x' : 'z';
      if (!girderIsConnected(level, brackets, pos, state, direction) &&
          !girderIsConnected(level, brackets, pos, state, direction.opposite)) {
        state = state.setFlag(prop, false);
      }
    }
  } else if (state.axisOf('axis') != Axis.y) {
    if (level.supportShapeEmpty(pos.above)) state = state.setFlag('top', false);
    if (level.supportShapeEmpty(pos.below)) state = state.setFlag('bottom', false);
  }
  for (final d in Iterate.directionsInAxis(axis)) {
    state = girderUpdateState(level, brackets, pos, state, d);
  }
  return state;
}

/// `Block.updateFromNeighbourShapes` for a girder: applies `updateShape` for the six neighbours in
/// vanilla's order (west, east, north, south, down, up).
BState girderUpdateFromNeighbourShapes(BlockGetter level, BracketFacingLookup brackets, Pos pos, BState state) {
  const order = [Direction.west, Direction.east, Direction.north, Direction.south, Direction.down, Direction.up];
  var s = state;
  for (final dir in order) {
    s = state.key == girderEncasedShaftKey
        ? girderEncasedShaftUpdateShape(level, brackets, pos, s, dir, level.stateAt(pos.relative(dir)))
        : girderUpdateShape(level, brackets, pos, s, dir);
  }
  return s;
}

/// `GirderBlock.getStateForPlacement`: [state] is the default state.
BState girderStateForPlacement(
  BlockGetter level,
  BracketFacingLookup brackets,
  Pos pos,
  BState state,
  Direction clickedFace, {
  required bool inWater,
}) {
  var s = state
      .setFlag('x', clickedFace.axis == Axis.x)
      .setFlag('z', clickedFace.axis == Axis.z)
      .setValue('axis', clickedFace.axis.serializedName);
  for (final d in Iterate.directions) {
    s = girderUpdateState(level, brackets, pos, s, d);
  }
  return s.setFlag('waterlogged', inWater);
}

/// `GirderEncasedShaftBlock.updateShape`.
BState girderEncasedShaftUpdateShape(
  BlockGetter level,
  BracketFacingLookup brackets,
  Pos pos,
  BState state,
  Direction direction,
  BState neighbourState,
) {
  if (!direction.axis.isVertical) return state;
  final updateProperty = direction == Direction.up ? 'top' : 'bottom';
  if (level.supportShapeEmpty(pos.relative(direction))) state = state.setFlag(updateProperty, false);
  return girderUpdateVerticalProperty(level, brackets, pos, state, updateProperty, neighbourState, direction);
}

/// `GirderEncasedShaftBlock.getRotatedBlockState`: the girder left when the shaft is removed.
BState girderFromEncasedShaft(BState encased, BState girderDefault) {
  final axis = encased.axisOf('axis') ?? Axis.x;
  return girderDefault
      .setFlag('waterlogged', encased.flag('waterlogged'))
      .setFlag('x', axis == Axis.z)
      .setFlag('z', axis == Axis.x)
      .setValue('axis', (axis == Axis.x ? Axis.z : Axis.x).serializedName)
      .setFlag('bottom', encased.flag('bottom'))
      .setFlag('top', encased.flag('top'));
}

/// The encased shaft state a girder becomes when a shaft is used on it
/// (`GirderBlock.useItemOn`): [clickedFace] is the face the shaft was used on.
BState girderEncaseShaft(BState girder, BState encasedDefault, Direction clickedFace) =>
    encasedDefault
        .setFlag('waterlogged', girder.flag('waterlogged'))
        .setFlag('top', girder.flag('top'))
        .setFlag('bottom', girder.flag('bottom'))
        .setValue('axis', (girder.flag('x') || clickedFace.axis == Axis.z ? Axis.z : Axis.x).serializedName);

/// `GirderBlock.rotate`. Note that Create's `setValue(X, Z).setValue(Z, Z)` is reproduced as is.
BState girderRotate(BState state, BlockRotation rot) {
  final axis = state.axisOf('axis') ?? Axis.y;
  final rotated = rot.rotate(Direction.fromAxisAndDirection(axis, AxisDirection.positive)).axis;
  state = state.setValue('axis', rotated.serializedName);
  if (rot.rotate(Direction.east).axis == Axis.x) return state;
  return state.setFlag('x', state.flag('z')).setFlag('z', state.flag('z'));
}

// -- Placement helper ------------------------------------------------------------------------

/// `GirderPlacementHelper.canExtendToward`.
bool girderCanExtendToward(BState state, Direction side) {
  final axis = side.axis;
  if (state.key == girderKey) {
    final x = state.flag('x');
    final z = state.flag('z');
    if (!x && !z) return axis == Axis.y;
    if (x && z) return true;
    return axis == (x ? Axis.x : Axis.z);
  }
  if (state.key == girderEncasedShaftKey) {
    return axis != Axis.y && axis != state.axisOf('axis');
  }
  return false;
}

/// `GirderPlacementHelper.withAxis`.
BState girderWithAxis(BState state, Axis axis) {
  if (state.key == girderKey) {
    return state
        .setFlag('x', axis == Axis.x)
        .setFlag('z', axis == Axis.z)
        .setValue('axis', axis.serializedName);
  }
  if (state.key == girderEncasedShaftKey && axis.isHorizontal) {
    return state.setValue('axis', (axis == Axis.x ? Axis.z : Axis.x).serializedName);
  }
  return state;
}

/// `GirderPlacementHelper.getOffset`. [fixup] is `Block.updateFromNeighbourShapes` for the new
/// block (applied by the caller, since it needs the shapes of the neighbours).
PlacementOffset girderPlacementOffset({
  required BlockGetter level,
  required BState state,
  required Pos pos,
  required (double, double, double) hit,
  required int range,
  BState Function(Pos newPos, BState placed)? fixup,
}) {
  final directions = orderedByDistanceWhere(pos, hit, (d) => girderCanExtendToward(state, d));
  for (final dir in directions) {
    var poles = 0;
    var check = pos.relative(dir);
    while (girderCanExtendToward(level.stateAt(check), dir)) {
      poles++;
      check = check.relative(dir);
    }
    if (poles >= range) continue;
    final newPos = pos.relative(dir, poles + 1);
    if (!level.canBeReplaced(newPos)) continue;
    return PlacementOffset.at(newPos, (b) {
      final withAxis = girderWithAxis(b, dir.axis);
      return fixup == null ? withAxis : fixup(newPos, withAxis);
    });
  }
  return PlacementOffset.fail;
}

// -- Wrench ----------------------------------------------------------------------------------

enum GirderWrenchAction { single, pair }

/// `GirderWrenchBehavior.getValidDirections`.
List<(Direction, GirderWrenchAction)> girderWrenchValidDirections(BlockGetter level, Pos pos) {
  final blockState = level.stateAt(pos);
  if (blockState.key != girderKey) return const [];
  final out = <(Direction, GirderWrenchAction)>[];
  for (final direction in Iterate.directions) {
    final other = level.stateAt(pos.relative(direction));
    if (!blockState.flag('x') && !blockState.flag('z')) continue;
    if (direction.axis == Axis.y) {
      if (other.key != girderKey) {
        if (!blockState.flag('x') ^ !blockState.flag('z')) out.add((direction, GirderWrenchAction.single));
        continue;
      }
      if (blockState.flag('x') == blockState.flag('z')) continue;
      if (other.flag('x') == other.flag('z')) continue;
      out.add((direction, GirderWrenchAction.pair));
    }
  }
  return out;
}

/// `GirderWrenchBehavior.getDirectionAndAction`.
(Direction, GirderWrenchAction)? girderWrenchDirectionAndAction(
  BlockGetter level,
  Pos pos,
  (double, double, double) hit,
) {
  final valid = girderWrenchValidDirections(level, pos);
  if (valid.isEmpty) return null;
  final directions = orderedByDistance(pos, hit, valid.map((e) => e.$1));
  if (directions.isEmpty) return null;
  final dir = directions.first;
  for (final e in valid) {
    if (e.$1 == dir) return e;
  }
  return (dir, GirderWrenchAction.single);
}

BState _postProcess(BState newState) {
  if (newState.flag('top') && newState.flag('bottom')) return newState;
  if (newState.axisOf('axis') != Axis.y) return newState;
  return newState.setValue('axis', (newState.flag('x') ? Axis.x : Axis.z).serializedName);
}

/// The block changes of `GirderWrenchBehavior.handleClick` for the girder at [pos], or `null`
/// when the click does nothing. Each entry is (position, new state).
List<(Pos, BState)>? girderWrenchClick(BlockGetter level, Pos pos, (double, double, double) hit) {
  final state = level.stateAt(pos);
  final dirPair = girderWrenchDirectionAndAction(level, pos, hit);
  if (dirPair == null) return null;
  if (!state.flag('x') && !state.flag('z')) return null;
  final dir = dirPair.$1;
  final otherPos = pos.relative(dir);
  final other = level.stateAt(otherPos);
  if (dir == Direction.up) {
    return [
      (pos, _postProcess(state.cycleFlag('top'))),
      if (dirPair.$2 == GirderWrenchAction.pair && other.key == girderKey)
        (otherPos, _postProcess(other.cycleFlag('bottom'))),
    ];
  }
  if (dir == Direction.down) {
    return [
      (pos, _postProcess(state.cycleFlag('bottom'))),
      if (dirPair.$2 == GirderWrenchAction.pair && other.key == girderKey)
        (otherPos, _postProcess(other.cycleFlag('top'))),
    ];
  }
  return const [];
}
