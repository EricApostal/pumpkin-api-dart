// The vanilla block families that the palettes are made of, ported as pure state logic:
// panes and bars (`IronBarsBlock`), walls (`WallBlock`), stairs (`StairBlock`) and slabs
// (`SlabBlock`). The host only knows the registered shapes, so the neighbour dependent parts
// of the states (connections, stair corners, wall posts) are computed here.
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;

import '../api/block_state.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import 'shapes.dart';

// -- Shape footprints --------------------------------------------------------------

/// A rectangle in the two axes other than the face axis: (min a, min b, max a, max b).
typedef Rect = (double, double, double, double);

/// The footprint of [boxes] on the face of the block that looks toward [face]
/// (`VoxelShape.getFaceShape(face)` seen from above): the rectangles of the boxes that reach the
/// face, over the axes other than the face's. For `down`/`up` the rectangles are `(x, z)`.
List<Rect> faceFootprint(List<BlockBox> boxes, Direction face) {
  const eps = 1e-7;
  final out = <Rect>[];
  for (final b in boxes) {
    final lo = face.axis.choose(b.minX, b.minY, b.minZ);
    final hi = face.axis.choose(b.maxX, b.maxY, b.maxZ);
    final touches = face.axisDirection == AxisDirection.negative
        ? lo <= eps && hi > eps
        : lo < 1 - eps && hi >= 1 - eps;
    if (!touches) continue;
    switch (face.axis) {
      case Axis.y:
        out.add((b.minX, b.minZ, b.maxX, b.maxZ));
      case Axis.x:
        out.add((b.minY, b.minZ, b.maxY, b.maxZ));
      case Axis.z:
        out.add((b.minX, b.minY, b.maxX, b.maxY));
    }
  }
  return out;
}

/// Whether [test] lies entirely inside the union of [rects] (`!Shapes.joinIsNotEmpty(test, above, ONLY_FIRST)`).
bool rectCovered(Rect test, List<Rect> rects) {
  const eps = 1e-9;
  final xs = <double>{test.$1, test.$3};
  final ys = <double>{test.$2, test.$4};
  for (final r in rects) {
    for (final x in [r.$1, r.$3]) {
      if (x > test.$1 && x < test.$3) xs.add(x);
    }
    for (final y in [r.$2, r.$4]) {
      if (y > test.$2 && y < test.$4) ys.add(y);
    }
  }
  final sx = xs.toList()..sort();
  final sy = ys.toList()..sort();
  for (var i = 0; i + 1 < sx.length; i++) {
    for (var j = 0; j + 1 < sy.length; j++) {
      final cx = (sx[i] + sx[i + 1]) / 2;
      final cy = (sy[j] + sy[j + 1]) / 2;
      if (sx[i + 1] - sx[i] < eps || sy[j + 1] - sy[j] < eps) continue;
      var covered = false;
      for (final r in rects) {
        if (cx > r.$1 && cx < r.$3 && cy > r.$2 && cy < r.$4) {
          covered = true;
          break;
        }
      }
      if (!covered) return false;
    }
  }
  return true;
}

// -- Connections ---------------------------------------------------------------------

/// `Block.isExceptionForConnection`.
bool isExceptionForConnection(BlockGetter level, Pos p) {
  final s = level.stateAt(p);
  return level.hasTag(p, 'minecraft:leaves') ||
      s.key == 'minecraft:barrier' ||
      s.key == 'minecraft:carved_pumpkin' ||
      s.key == 'minecraft:jack_o_lantern' ||
      s.key == 'minecraft:melon' ||
      s.key == 'minecraft:pumpkin' ||
      level.hasTag(p, 'minecraft:shulker_boxes');
}

/// Whether [s] is a wall state (`WallBlock`: `up` and sides that are `none`, `low` or `tall`).
bool isWallState(BState s) => s.has('up') && const {'none', 'low', 'tall'}.contains(s['north']);

/// `state.is(BlockTags.WALLS)`.
bool isWallAt(BlockGetter level, Pos p) => level.hasTag(p, 'minecraft:walls') || isWallState(level.stateAt(p));

/// Whether the block at [p] is an `IronBarsBlock` (bars and glass panes of every kind).
bool isBarsBlock(BlockGetter level, Pos p) {
  final s = level.stateAt(p);
  if (s.isAir) return false;
  if (level.hasTag(p, 'minecraft:bars') || level.hasTag(p, 'c:glass_panes')) return true;
  final path = s.key.substring(s.key.indexOf(':') + 1);
  final hasSides = s.has('north') && s.has('east') && s.has('south') && s.has('west') && s.has('waterlogged');
  if (!hasSides || s.has('up')) return false;
  return path.endsWith('_pane') || path.endsWith('_bars') || path == 'iron_bars' || path == 'glass_pane';
}

/// `Block.isFaceSturdy` of the neighbour at [npos] looking back at [from].
bool _sturdyToward(BlockGetter level, Pos npos, Direction fromNeighbourDirection) =>
    level.isFaceSturdy(npos, fromNeighbourDirection.opposite);

/// `IronBarsBlock.attachesTo(neighbour, faceSolid, direction)`; [direction] is the direction
/// from the pane to the neighbour.
bool barsAttachesTo(BlockGetter level, Pos panePos, Direction direction) {
  final npos = panePos.relative(direction);
  final faceSolid = _sturdyToward(level, npos, direction);
  return (!isExceptionForConnection(level, npos) && faceSolid) ||
      isBarsBlock(level, npos) ||
      isWallAt(level, npos);
}

const _sideProps = {
  Direction.north: 'north',
  Direction.east: 'east',
  Direction.south: 'south',
  Direction.west: 'west',
};

/// `IronBarsBlock.getStateForPlacement`: the four connections of [state] at [pos].
BState barsStateForPlacement(BlockGetter level, Pos pos, BState state, {bool inWater = false}) {
  var s = state;
  for (final d in Direction.planeHorizontal) {
    s = s.setFlag(_sideProps[d]!, barsAttachesTo(level, pos, d));
  }
  return s.setFlag('waterlogged', inWater);
}

/// `IronBarsBlock.updateShape`: the state after the neighbour in [direction] changed.
BState barsUpdateShape(BlockGetter level, Pos pos, BState state, Direction direction) {
  if (!direction.isHorizontal) return state;
  return state.setFlag(_sideProps[direction]!, barsAttachesTo(level, pos, direction));
}

/// The shape of a pane or bars state (`CrossCollisionBlock`).
Shape barsShapeOf(BState state) =>
    crossShape({for (final d in Direction.planeHorizontal) d: state.flag(_sideProps[d]!)});

// -- Walls ---------------------------------------------------------------------------

/// `WallBlock.connectsTo(state, faceSolid, direction)`; [direction] is the direction from the
/// wall to the neighbour (the face of the neighbour that looks at the wall is the opposite).
bool wallConnectsTo(BlockGetter level, Pos wallPos, Direction direction) {
  final npos = wallPos.relative(direction);
  final s = level.stateAt(npos);
  final faceSolid = _sturdyToward(level, npos, direction);
  final fenceGate = level.hasTag(npos, 'minecraft:fence_gates') &&
      (s.dir('facing')?.axis == direction.opposite.clockWise.axis);
  return isWallAt(level, npos) ||
      (!isExceptionForConnection(level, npos) && faceSolid) ||
      isBarsBlock(level, npos) ||
      fenceGate;
}

String _wallSide(BState s, Direction d) => s[_sideProps[d]!] ?? 'none';

final Shape _wallTestPost = column16(2, 0, 16);
final VoxelShaper _wallTestShapes = rotateHorizontalFromNorth(boxZ16(2, 0, 16, 0, 9));

Rect _rectOfXZ(Shape s) {
  var minX = double.infinity, minZ = double.infinity, maxX = -double.infinity, maxZ = -double.infinity;
  for (final b in s) {
    if (b.minX < minX) minX = b.minX;
    if (b.minZ < minZ) minZ = b.minZ;
    if (b.maxX > maxX) maxX = b.maxX;
    if (b.maxZ > maxZ) maxZ = b.maxZ;
  }
  return (minX, minZ, maxX, maxZ);
}

String _makeWallState(bool connects, List<Rect> above, Direction d) {
  if (!connects) return 'none';
  return rectCovered(_rectOfXZ(_wallTestShapes.get(d)), above) ? 'tall' : 'low';
}

bool _shouldRaisePost(BState state, BlockGetter level, Pos topPos, List<Rect> above) {
  final topState = level.stateAt(topPos);
  if (isWallAt(level, topPos) && topState.flag('up')) return true;
  final north = _wallSide(state, Direction.north);
  final south = _wallSide(state, Direction.south);
  final east = _wallSide(state, Direction.east);
  final west = _wallSide(state, Direction.west);
  final southNone = south == 'none';
  final westNone = west == 'none';
  final eastNone = east == 'none';
  final northNone = north == 'none';
  final hasCorner = (northNone && southNone && westNone && eastNone) || northNone != southNone || westNone != eastNone;
  if (hasCorner) return true;
  final hasHighWall = (north == 'tall' && south == 'tall') || (east == 'tall' && west == 'tall');
  if (hasHighWall) return false;
  return level.hasTag(topPos, 'minecraft:wall_post_override') || rectCovered(_rectOfXZ(_wallTestPost), above);
}

/// `WallBlock.updateShape(level, state, topPos, topNeighbour, n, e, s, w)`.
BState _wallUpdate(BlockGetter level, BState state, Pos topPos, bool n, bool e, bool s, bool w) {
  final above = faceFootprint(level.collisionBoxes(topPos), Direction.down);
  var out = state
      .setValue('north', _makeWallState(n, above, Direction.north))
      .setValue('east', _makeWallState(e, above, Direction.east))
      .setValue('south', _makeWallState(s, above, Direction.south))
      .setValue('west', _makeWallState(w, above, Direction.west));
  out = out.setFlag('up', _shouldRaisePost(out, level, topPos, above));
  return out;
}

/// `WallBlock.getStateForPlacement` for the wall [state] at [pos].
BState wallStateForPlacement(BlockGetter level, Pos pos, BState state, {bool inWater = false}) {
  final s = state.setFlag('waterlogged', inWater);
  return _wallUpdate(
    level,
    s,
    pos.above,
    wallConnectsTo(level, pos, Direction.north),
    wallConnectsTo(level, pos, Direction.east),
    wallConnectsTo(level, pos, Direction.south),
    wallConnectsTo(level, pos, Direction.west),
  );
}

/// `WallBlock.updateShape(direction)`: the wall after the neighbour in [direction] changed.
BState wallUpdateShape(BlockGetter level, Pos pos, BState state, Direction direction) {
  if (direction == Direction.down) return state;
  bool isConnected(Direction d) => _wallSide(state, d) != 'none';
  if (direction == Direction.up) {
    return _wallUpdate(
      level,
      state,
      pos.above,
      isConnected(Direction.north),
      isConnected(Direction.east),
      isConnected(Direction.south),
      isConnected(Direction.west),
    );
  }
  bool side(Direction d) => d == direction ? wallConnectsTo(level, pos, d) : isConnected(d);
  return _wallUpdate(
    level,
    state,
    pos.above,
    side(Direction.north),
    side(Direction.east),
    side(Direction.south),
    side(Direction.west),
  );
}

/// The shape (selection or collision) of a wall state.
Shape wallShapeOf(BState state, {bool collision = false}) => wallShape(
  state.flag('up'),
  {for (final d in Direction.planeHorizontal) d: _wallSide(state, d)},
  collision: collision,
);

// -- Stairs --------------------------------------------------------------------------

/// Whether [s] is a stair state (`StairBlock` has `facing`, `half` and `shape`).
bool isStairsState(BState s) {
  final shape = s['shape'];
  return s.has('facing') &&
      s.has('half') &&
      shape != null &&
      (shape == 'straight' || shape.startsWith('inner_') || shape.startsWith('outer_'));
}

bool _canTakeShape(BlockGetter level, BState state, Pos pos, Direction neighbour) {
  final n = level.stateAt(pos.relative(neighbour));
  return !isStairsState(n) || n['facing'] != state['facing'] || n['half'] != state['half'];
}

/// `StairBlock.getStairsShape`.
String stairsShapeOf(BlockGetter level, Pos pos, BState state) {
  final facing = state.dir('facing')!;
  final behind = level.stateAt(pos.relative(facing));
  if (isStairsState(behind) && state['half'] == behind['half']) {
    final behindFacing = behind.dir('facing')!;
    if (behindFacing.axis != facing.axis && _canTakeShape(level, state, pos, behindFacing.opposite)) {
      return behindFacing == facing.counterClockWise ? 'outer_left' : 'outer_right';
    }
  }
  final front = level.stateAt(pos.relative(facing.opposite));
  if (isStairsState(front) && state['half'] == front['half']) {
    final frontFacing = front.dir('facing')!;
    if (frontFacing.axis != facing.axis && _canTakeShape(level, state, pos, frontFacing)) {
      return frontFacing == facing.counterClockWise ? 'inner_left' : 'inner_right';
    }
  }
  return 'straight';
}

/// `StairBlock.getStateForPlacement` (after facing, half and waterlogged were chosen).
BState stairsStateForPlacement(BlockGetter level, Pos pos, BState state) =>
    state.setValue('shape', stairsShapeOf(level, pos, state));

/// `StairBlock.updateShape`: horizontal neighbour changes recompute the corner shape.
BState stairsUpdateShape(BlockGetter level, Pos pos, BState state, Direction direction) =>
    direction.isHorizontal ? state.setValue('shape', stairsShapeOf(level, pos, state)) : state;

/// The shape of a stairs state.
Shape stairShapeOf(BState state) => stairShape(state['half'] ?? 'bottom', state['shape'] ?? 'straight', state.dir('facing')!);

// -- Slabs ---------------------------------------------------------------------------

/// `SlabBlock.getStateForPlacement` when merging into an existing slab: `double`, not waterlogged.
BState slabMerged(BState existing) => existing.setValue('type', 'double').setFlag('waterlogged', false);

/// `SlabBlock.canBeReplaced(state, context)` for a slab item of the same block:
/// whether clicking [clickedFace] at the vertical [cursorY] (0..1 within the block) of a slab of
/// [type] turns it into a double slab. [replacingClickedOnBlock] is true when the slab block is
/// the clicked block (the usual case; the other case is placing next to a block).
bool slabCanBeReplaced(String type, {required Direction clickedFace, required double cursorY, bool replacingClickedOnBlock = true}) {
  if (type == 'double') return false;
  if (!replacingClickedOnBlock) return true;
  final above = cursorY > 0.5;
  return type == 'bottom'
      ? clickedFace == Direction.up || (above && clickedFace.axis.isHorizontal)
      : clickedFace == Direction.down || (!above && clickedFace.axis.isHorizontal);
}

/// `SlabBlock.getStateForPlacement` for a fresh slab: `bottom` or `top` from the click.
String slabPlacementType({required Direction clickedFace, required double cursorY}) =>
    clickedFace != Direction.down && (clickedFace == Direction.up || !(cursorY > 0.5)) ? 'bottom' : 'top';

/// `StairBlock` placement half from a click.
String stairPlacementHalf({required Direction clickedFace, required double cursorY}) =>
    slabPlacementType(clickedFace: clickedFace, cursorY: cursorY);
