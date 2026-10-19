// Block shapes as lists of boxes in block units (pure): a port of catnip's
// `VoxelShaper` (rotating a shape for each facing) and of the shapes of
// `AllShapes` that the decoration blocks use, plus the vanilla shapes of
// stairs, slabs, walls, panes/bars and doors.
//
// All dimensions in the `*16` helpers are in 1/16 block units like `Block.box`.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;

import '../common/direction.dart';

/// `Block.box(x1, y1, z1, x2, y2, z2)` as a [BlockBox] (the arguments are in 1/16).
BlockBox box16(double x1, double y1, double z1, double x2, double y2, double z2) =>
    BlockBox(x1 / 16, y1 / 16, z1 / 16, x2 / 16, y2 / 16, z2 / 16);

/// A shape: the union of its boxes.
typedef Shape = List<BlockBox>;

const Shape emptyShape = <BlockBox>[];

/// `Shapes.block()`.
const Shape fullBlock = <BlockBox>[BlockBox.unit];

double _round(double v) {
  // Block coordinates are multiples of 1/16 in all Create shapes; rounding to 1e-9
  // removes the noise of the rotation maths.
  final r = (v * 1e9).roundToDouble() / 1e9;
  return r == 0 ? 0.0 : r;
}

(double, double, double) _rotate((double, double, double) v, double deg, Axis axis) {
  if (deg == 0) return v;
  final angle = deg / 180.0 * math.pi;
  final sin = math.sin(angle);
  final cos = math.cos(angle);
  final (x, y, z) = v;
  switch (axis) {
    case Axis.x:
      return (x, y * cos - z * sin, z * cos + y * sin);
    case Axis.y:
      return (x * cos + z * sin, y, z * cos - x * sin);
    case Axis.z:
      return (x * cos - y * sin, y * cos + x * sin, z);
  }
}

/// `VoxelShaper.rotatedCopy`: rotates every box of [shape] around the block centre by
/// `rotation` degrees about X, then Y, then Z.
Shape rotatedCopy(Shape shape, (double, double, double) rotation) {
  if (rotation == (0.0, 0.0, 0.0)) return shape;
  const c = 0.5;
  return [
    for (final b in shape)
      () {
        var v1 = (b.minX - c, b.minY - c, b.minZ - c);
        var v2 = (b.maxX - c, b.maxY - c, b.maxZ - c);
        v1 = _rotate(v1, rotation.$1, Axis.x);
        v1 = _rotate(v1, rotation.$2, Axis.y);
        v1 = _rotate(v1, rotation.$3, Axis.z);
        v2 = _rotate(v2, rotation.$1, Axis.x);
        v2 = _rotate(v2, rotation.$2, Axis.y);
        v2 = _rotate(v2, rotation.$3, Axis.z);
        return BlockBox(
          _round(math.min(v1.$1, v2.$1) + c),
          _round(math.min(v1.$2, v2.$2) + c),
          _round(math.min(v1.$3, v2.$3) + c),
          _round(math.max(v1.$1, v2.$1) + c),
          _round(math.max(v1.$2, v2.$2) + c),
          _round(math.max(v1.$3, v2.$3) + c),
        );
      }(),
  ];
}

double _horizontalAngle(Direction d) => ((d.data2d < 0 ? 0 : d.data2d) & 3) * 90.0;

(double, double, double) _defaultRotation(Direction d) =>
    (d == Direction.up ? 0.0 : (d.isVertical ? 180.0 : 90.0), -_horizontalAngle(d), 0.0);

(double, double, double) _horizontalRotation(Direction d) => (0.0, -_horizontalAngle(d), 0.0);

Shape _rotateShape(Shape shape, Direction from, Direction to, (double, double, double) Function(Direction) values) {
  if (from == to) return shape;
  final f = values(from);
  final t = values(to);
  return rotatedCopy(shape, (-f.$1 + t.$1, -f.$2 + t.$2, -f.$3 + t.$3));
}

/// `VoxelShaper`: one shape per direction, all rotations of the same base shape.
final class VoxelShaper {
  final Map<Direction, Shape> _shapes;

  const VoxelShaper._(this._shapes);

  Shape get(Direction d) => _shapes[d] ?? (throw ArgumentError('No shape for $d'));

  /// `get(Axis)`: the shape of the positive direction of [axis].
  Shape getAxis(Axis axis) => get(axis.positive);

  static VoxelShaper _build(Shape shape, Direction facing, Iterable<Direction> dirs, (double, double, double) Function(Direction) values) =>
      VoxelShaper._({for (final d in dirs) d: _rotateShape(shape, facing, d, values)});

  /// `VoxelShaper.forHorizontal`.
  static VoxelShaper forHorizontal(Shape shape, Direction facing) =>
      _build(shape, facing, Direction.planeHorizontal, _horizontalRotation);

  /// `VoxelShaper.forHorizontalAxis` (along z by default).
  static VoxelShaper forHorizontalAxis(Shape shape, [Axis along = Axis.z]) =>
      _build(shape, along.positive, const [Direction.south, Direction.east], _horizontalRotation);

  /// `VoxelShaper.forDirectional`.
  static VoxelShaper forDirectional(Shape shape, [Direction facing = Direction.up]) =>
      _build(shape, facing, Direction.values, _defaultRotation);

  /// `VoxelShaper.forAxis` (along y by default).
  static VoxelShaper forAxis(Shape shape, [Axis along = Axis.y]) =>
      _build(shape, along.positive, const [Direction.south, Direction.east, Direction.up], _defaultRotation);
}

/// `AllShapes.Builder.add`: the union of shapes.
Shape union(Iterable<Shape> shapes) => [for (final s in shapes) ...s];

// -- Create's AllShapes (the ones the decoration blocks use) -----------------------

/// `AllShapes.CASING_3PX` (copycat panel).
final VoxelShaper casing3px = VoxelShaper.forDirectional([box16(0, 0, 0, 16, 3, 16)]);

/// `AllShapes.STEP_BOTTOM` / `STEP_TOP` (copycat step).
final VoxelShaper stepBottom = VoxelShaper.forHorizontal([box16(0, 0, 8, 16, 8, 16)], Direction.south);
final VoxelShaper stepTop = VoxelShaper.forHorizontal([box16(0, 8, 8, 16, 16, 16)], Direction.south);

/// `AllShapes.PLACARD`.
final VoxelShaper placard = VoxelShaper.forDirectional([box16(2, 0, 2, 14, 3, 14)]);

final VoxelShaper fourVoxelPole = VoxelShaper.forAxis([box16(6, 0, 6, 10, 16, 10)]);
final VoxelShaper sixVoxelPole = VoxelShaper.forAxis([box16(5, 0, 5, 11, 16, 11)]);
final VoxelShaper eightVoxelPole = VoxelShaper.forAxis([box16(4, 0, 4, 12, 16, 12)]);
final VoxelShaper tenVoxelPole = VoxelShaper.forAxis([box16(3, 0, 3, 13, 16, 13)]);

/// `AllShapes.GIRDER_BEAM`.
final VoxelShaper girderBeam = VoxelShaper.forHorizontalAxis([box16(4, 2, 0, 12, 14, 16)]);

/// `AllShapes.GIRDER_BEAM_SHAFT`: the beam along x plus a shaft pole along z, rotated to each axis.
final VoxelShaper girderBeamShaft =
    VoxelShaper.forHorizontalAxis(union([girderBeam.getAxis(Axis.x), sixVoxelPole.getAxis(Axis.z)]));

/// `AllShapes.GIRDER_CROSS`.
final Shape girderCross = union([tenVoxelPole.getAxis(Axis.y), girderBeam.getAxis(Axis.x), girderBeam.getAxis(Axis.z)]);

/// `AllShapes.SCAFFOLD_HALF` / `SCAFFOLD_FULL`.
final Shape scaffoldHalf = [box16(0, 8, 0, 16, 16, 16)];
final Shape scaffoldFull = union([
  scaffoldHalf,
  [box16(0, 0, 0, 2, 16, 2)],
  [box16(0, 0, 14, 2, 16, 16)],
  [box16(14, 0, 0, 16, 16, 2)],
  [box16(14, 0, 14, 16, 16, 16)],
]);

final Shape _whistleSmall = [box16(4, 3, 4, 12, 16, 12)];
final Shape _whistleMedium = [box16(3, 3, 3, 13, 16, 13)];
final Shape _whistleLarge = [box16(2, 3, 2, 14, 16, 14)];
final VoxelShaper _whistleBase = VoxelShaper.forDirectional(union([
  [box16(1, 0, 1, 15, 3, 15)],
  [box16(5, 0, 5, 11, 8, 11)],
]));

/// `AllShapes.WHISTLE_*_FLOOR` by size (`small`, `medium`, `large`).
final Map<String, Shape> whistleFloor = {
  'small': union([_whistleSmall, _whistleBase.get(Direction.up)]),
  'medium': union([_whistleMedium, _whistleBase.get(Direction.up)]),
  'large': union([_whistleLarge, _whistleBase.get(Direction.up)]),
};

/// `AllShapes.WHISTLE_*_WALL` by size.
final Map<String, VoxelShaper> whistleWall = {
  'small': VoxelShaper.forHorizontal(union([_whistleSmall, _whistleBase.get(Direction.north)]), Direction.south),
  'medium': VoxelShaper.forHorizontal(union([_whistleMedium, _whistleBase.get(Direction.north)]), Direction.south),
  'large': VoxelShaper.forHorizontal(union([_whistleLarge, _whistleBase.get(Direction.north)]), Direction.south),
};

/// `AllShapes.WHISTLE_EXTENDER_*` by (shape, size).
Shape whistleExtender(String shape, String size) {
  final (lo, hi) = switch (size) {
    'large' => (2.0, 14.0),
    'medium' => (3.0, 13.0),
    _ => (4.0, 12.0),
  };
  final top = switch (shape) {
    'double' => 18.0,
    'double_connected' => 16.0,
    _ => 10.0,
  };
  return [box16(lo, 0, lo, hi, top, hi)];
}

// -- Sliding doors (SlidingDoorShapes) -------------------------------------------

final Shape _seAabb = [box16(0, 0, -13, 3, 16, 3)];
final Shape _esAabb = [box16(-13, 0, 0, 3, 16, 3)];
final Shape _nwAabb = [box16(13, 0, 13, 16, 16, 29)];
final Shape _wnAabb = [box16(13, 0, 13, 29, 16, 16)];
final Shape _swAabb = [box16(13, 0, -13, 16, 16, 3)];
final Shape _wsAabb = [box16(13, 0, 0, 29, 16, 3)];
final Shape _neAabb = [box16(0, 0, 13, 3, 16, 29)];
final Shape _enAabb = [box16(-13, 0, 13, 3, 16, 16)];
final Shape _seAabbFold = [box16(0, 0, -3, 9, 16, 3)];
final Shape _esAabbFold = [box16(-3, 0, 0, 3, 16, 9)];
final Shape _nwAabbFold = [box16(7, 0, 13, 16, 16, 19)];
final Shape _wnAabbFold = [box16(13, 0, 7, 19, 16, 16)];
final Shape _swAabbFold = [box16(7, 0, -3, 16, 16, 3)];
final Shape _wsAabbFold = [box16(13, 0, 0, 19, 16, 9)];
final Shape _neAabbFold = [box16(0, 0, 13, 9, 16, 19)];
final Shape _enAabbFold = [box16(-3, 0, 7, 3, 16, 16)];

/// `SlidingDoorShapes.get(facing, hinge, fold)`; [hinge] is `true` for the right hinge.
Shape slidingDoorShape(Direction facing, bool hinge, bool fold) {
  if (fold) {
    return switch (facing) {
      Direction.south => hinge ? _esAabbFold : _wsAabbFold,
      Direction.west => hinge ? _swAabbFold : _nwAabbFold,
      Direction.north => hinge ? _wnAabbFold : _enAabbFold,
      _ => hinge ? _neAabbFold : _seAabbFold,
    };
  }
  return switch (facing) {
    Direction.south => hinge ? _esAabb : _wsAabb,
    Direction.west => hinge ? _swAabb : _nwAabb,
    Direction.north => hinge ? _wnAabb : _enAabb,
    _ => hinge ? _neAabb : _seAabb,
  };
}

// -- Vanilla shapes -----------------------------------------------------------------

/// `Shapes.rotateHorizontal(shape)` (shape given for NORTH), as a [VoxelShaper].
VoxelShaper rotateHorizontalFromNorth(Shape shape) => VoxelShaper.forHorizontal(shape, Direction.north);

/// `Block.column(size, y0, y1)`.
Shape column16(double size, double y0, double y1) {
  final lo = 8 - size / 2;
  final hi = 8 + size / 2;
  return [box16(lo, y0, lo, hi, y1, hi)];
}

/// `Block.boxZ(width, y0, y1, z0, z1)`: a box centred in x, running along z (north at z=0).
Shape boxZ16(double width, double y0, double y1, double z0, double z1) {
  final lo = 8 - width / 2;
  final hi = 8 + width / 2;
  return [box16(lo, y0, z0, hi, y1, z1)];
}

/// Vanilla stair shapes by (half, shape name, facing).
final Shape _stairOuter = union([
  column16(16, 0, 8),
  [box16(0, 8, 0, 8, 16, 8)],
]);

Shape _rotY90(Shape s) => rotatedCopy(s, (0.0, -90.0, 0.0));
Shape _flipY(Shape s) => [for (final b in s) BlockBox(b.minX, 1 - b.maxY, b.minZ, b.maxX, 1 - b.minY, b.maxZ)];

final Shape _stairStraight = union([_stairOuter, _rotY90(_stairOuter)]);
final Shape _stairInner = union([_stairStraight, _rotY90(_stairStraight)]);

Map<Direction, Shape> _rotateHorizontalFromNorth(Shape shape) {
  final v = VoxelShaper.forHorizontal(shape, Direction.north);
  return {for (final d in Direction.planeHorizontal) d: v.get(d)};
}

final Map<Direction, Shape> _stairBottomOuter = _rotateHorizontalFromNorth(_stairOuter);
final Map<Direction, Shape> _stairBottomStraight = _rotateHorizontalFromNorth(_stairStraight);
final Map<Direction, Shape> _stairBottomInner = _rotateHorizontalFromNorth(_stairInner);
final Map<Direction, Shape> _stairTopOuter = _rotateHorizontalFromNorth(_flipY(_stairOuter));
final Map<Direction, Shape> _stairTopStraight = _rotateHorizontalFromNorth(_flipY(_stairStraight));
final Map<Direction, Shape> _stairTopInner = _rotateHorizontalFromNorth(_flipY(_stairInner));

/// `StairBlock.getShape`; [shape] is `straight`, `inner_left`, `inner_right`, `outer_left`, `outer_right`.
Shape stairShape(String half, String shape, Direction facing) {
  final bottom = half == 'bottom';
  final table = switch (shape) {
    'straight' => bottom ? _stairBottomStraight : _stairTopStraight,
    'outer_left' || 'outer_right' => bottom ? _stairBottomOuter : _stairTopOuter,
    _ => bottom ? _stairBottomInner : _stairTopInner,
  };
  final dir = switch (shape) {
    'inner_left' => facing.counterClockWise,
    'outer_right' => facing.clockWise,
    _ => facing,
  };
  return table[dir]!;
}

/// `SlabBlock.getShape`.
Shape slabShape(String type) => switch (type) {
  'top' => column16(16, 8, 16),
  'bottom' => column16(16, 0, 8),
  _ => fullBlock,
};

/// `WallBlock.makeShapes(postHeight, wallTop)` for one state. [sides] maps a horizontal
/// direction to `none`, `low` or `tall`.
Shape wallShape(bool up, Map<Direction, String> sides, {bool collision = false}) {
  final postHeight = collision ? 24.0 : 16.0;
  final wallTop = collision ? 24.0 : 14.0;
  final post = column16(8, 0, postHeight);
  final low = rotateHorizontalFromNorth(boxZ16(6, 0, wallTop, 0, 11));
  final tall = rotateHorizontalFromNorth(boxZ16(6, 0, postHeight, 0, 11));
  final out = <BlockBox>[if (up) ...post];
  for (final d in Direction.planeHorizontal) {
    switch (sides[d]) {
      case 'low':
        out.addAll(low.get(d));
      case 'tall':
        out.addAll(tall.get(d));
    }
  }
  return out;
}

/// `CrossCollisionBlock.makeShapes` for panes and bars: post width 2, wall width 2.
Shape crossShape(Map<Direction, bool> sides, {bool collision = false}) {
  final post = column16(2, 0, 16);
  final arms = rotateHorizontalFromNorth(boxZ16(2, 0, 16, 0, 8));
  final out = <BlockBox>[...post];
  for (final d in Direction.planeHorizontal) {
    if (sides[d] ?? false) out.addAll(arms.get(d));
  }
  return out;
}

/// The vanilla door shapes (`DoorBlock`): a 3/16 thick panel on one side of the block.
/// [facing] is the direction the door faces, [open] and [rightHinge] as in the block state.
Shape doorShape(Direction facing, bool open, bool rightHinge) {
  // The closed door sits on the side opposite to `facing`'s front: SHAPE_SOUTH is the
  // panel at z = 0..3 for a door facing south... see DoorBlock.
  final closed = _doorClosed[facing]!;
  if (!open) return closed;
  final dir = rightHinge ? facing.counterClockWise : facing.clockWise;
  return _doorClosed[dir]!;
}

final Map<Direction, Shape> _doorClosed = {
  Direction.south: [box16(0, 0, 0, 16, 16, 3)],
  Direction.north: [box16(0, 0, 13, 16, 16, 16)],
  Direction.east: [box16(0, 0, 0, 3, 16, 16)],
  Direction.west: [box16(13, 0, 0, 16, 16, 16)],
};

/// `LadderBlock` shapes by facing (the ladder sits on the side opposite to `facing`).
final Map<Direction, Shape> ladderShapes = {
  Direction.north: [box16(0, 0, 13, 16, 16, 16)],
  Direction.south: [box16(0, 0, 0, 16, 16, 3)],
  Direction.west: [box16(13, 0, 0, 16, 16, 16)],
  Direction.east: [box16(0, 0, 0, 3, 16, 16)],
};

/// `TrapDoorBlock` shapes: 3/16 thick.
Shape trapdoorShape(Direction facing, String half, bool open) {
  if (!open) {
    return half == 'top' ? [box16(0, 13, 0, 16, 16, 16)] : [box16(0, 0, 0, 16, 3, 16)];
  }
  return ladderShapes[facing]!;
}
