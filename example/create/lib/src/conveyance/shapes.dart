// Block shapes of the conveyance blocks (pure): a port of catnip's `VoxelShaper` and of the
// `AllShapes`, `BeltShapes`, `ChuteShapes` and `BeltTunnelShapes` entries these blocks use.
// A shape is a list of boxes in block units (a block is 0..1; boxes may reach outside, like the
// funnels and the belt's slope slices do).
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;

import '../api/block_state.dart' show BState;
import '../common/direction.dart';

/// A shape: the union of its boxes.
typedef Shape = List<BlockBox>;

/// `Block.box(...)` (arguments in 1/16 block).
BlockBox box16(double x1, double y1, double z1, double x2, double y2, double z2) =>
    BlockBox(x1 / 16, y1 / 16, z1 / 16, x2 / 16, y2 / 16, z2 / 16);

/// `Shapes.block()`.
const Shape fullBlock = <BlockBox>[BlockBox.unit];

/// `Shapes.empty()`.
const Shape emptyShape = <BlockBox>[];

/// `Shapes.or`.
Shape union(Iterable<Shape> shapes) => [for (final s in shapes) ...s];

/// `VoxelShape.move(x, y, z)`.
Shape move(Shape s, double x, double y, double z) => [
  for (final b in s) BlockBox(b.minX + x, b.minY + y, b.minZ + z, b.maxX + x, b.maxY + y, b.maxZ + z),
];

/// `Shapes.joinUnoptimized(a, b, AND)`: the intersection of two shapes.
Shape intersect(Shape a, Shape b) {
  final out = <BlockBox>[];
  for (final x in a) {
    for (final y in b) {
      final minX = math.max(x.minX, y.minX), minY = math.max(x.minY, y.minY), minZ = math.max(x.minZ, y.minZ);
      final maxX = math.min(x.maxX, y.maxX), maxY = math.min(x.maxY, y.maxY), maxZ = math.min(x.maxZ, y.maxZ);
      if (minX < maxX && minY < maxY && minZ < maxZ) out.add(BlockBox(minX, minY, minZ, maxX, maxY, maxZ));
    }
  }
  return out;
}

double _round(double v) {
  final r = (v * 1e9).roundToDouble() / 1e9;
  return r == 0 ? 0.0 : r;
}

(double, double, double) _rotate((double, double, double) v, double deg, Axis axis) {
  if (deg == 0) return v;
  final angle = deg / 180.0 * math.pi;
  final sin = math.sin(angle), cos = math.cos(angle);
  final (x, y, z) = v;
  return switch (axis) {
    Axis.x => (x, y * cos - z * sin, z * cos + y * sin),
    Axis.y => (x * cos + z * sin, y, z * cos - x * sin),
    Axis.z => (x * cos - y * sin, y * cos + x * sin, z),
  };
}

/// `VoxelShaper.rotatedCopy`: every box rotated around the block centre by [rotation] degrees
/// about x, then y, then z.
Shape rotatedCopy(Shape shape, (double, double, double) rotation) {
  if (rotation == (0.0, 0.0, 0.0)) return shape;
  const c = 0.5;
  return [
    for (final b in shape)
      () {
        (double, double, double) turn((double, double, double) v) {
          v = _rotate(v, rotation.$1, Axis.x);
          v = _rotate(v, rotation.$2, Axis.y);
          return _rotate(v, rotation.$3, Axis.z);
        }

        final v1 = turn((b.minX - c, b.minY - c, b.minZ - c));
        final v2 = turn((b.maxX - c, b.maxY - c, b.maxZ - c));
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

/// `VoxelShaper`: one shape per direction, all rotations of the same base shape.
final class VoxelShaper {
  final Map<Direction, Shape> _shapes;

  const VoxelShaper._(this._shapes);

  Shape get(Direction d) => _shapes[d] ?? (throw ArgumentError('No shape for $d'));

  /// `get(Axis)`: the shape of the positive direction of [axis].
  Shape getAxis(Axis axis) => get(axis.positive);

  /// `VoxelShaper.forDirectionsWithRotation`.
  static VoxelShaper forDirectionsWithRotation(
    Shape shape,
    Direction facing,
    Iterable<Direction> directions,
    (double, double, double) Function(Direction) rotationValues,
  ) => VoxelShaper._({
    for (final d in directions)
      d: () {
        if (facing == d) return shape;
        final f = rotationValues(facing), t = rotationValues(d);
        return rotatedCopy(shape, (-f.$1 + t.$1, -f.$2 + t.$2, -f.$3 + t.$3));
      }(),
  });

  static VoxelShaper forHorizontal(Shape shape, Direction facing) =>
      forDirectionsWithRotation(shape, facing, Direction.planeHorizontal, _horizontalRotation);

  static VoxelShaper forHorizontalAxis(Shape shape, [Axis along = Axis.z]) =>
      forDirectionsWithRotation(shape, along.positive, const [Direction.south, Direction.east], _horizontalRotation);

  static VoxelShaper forDirectional(Shape shape, [Direction facing = Direction.up]) =>
      forDirectionsWithRotation(shape, facing, Direction.values, _defaultRotation);

  static VoxelShaper forAxis(Shape shape, [Axis along = Axis.y]) => forDirectionsWithRotation(
    shape,
    along.positive,
    const [Direction.south, Direction.east, Direction.up],
    _defaultRotation,
  );
}

// -- AllShapes ----------------------------------------------------------------------------

/// `AllShapes.CASING_13PX`.
final VoxelShaper casing13px = VoxelShaper.forDirectional([box16(0, 0, 0, 16, 13, 16)]);

/// `AllShapes.CASING_11PX`.
final VoxelShaper casing11px = VoxelShaper.forDirectional([box16(0, 0, 0, 16, 11, 16)]);

/// `AllShapes.CRATE_BLOCK_SHAPE`.
final Shape crateShape = [box16(1, 0, 1, 15, 14, 15)];

/// `AllShapes.BELT_COLLISION_MASK`.
final Shape beltCollisionMask = [box16(0, 0, 0, 16, 19, 16)];

/// `AllShapes.FUNNEL_COLLISION`.
final VoxelShaper funnelCollision = VoxelShaper.forDirectional([box16(0, 0, 0, 16, 4, 16)]);

/// `AllShapes.BELT_FUNNEL_RETRACTED`.
final VoxelShaper beltFunnelRetracted =
    VoxelShaper.forHorizontal([box16(2, -2, 14, 14, 14, 18), box16(0, -5, 8, 16, 16, 14)], Direction.north);

/// `AllShapes.BELT_FUNNEL_EXTENDED`.
final VoxelShaper beltFunnelExtended = VoxelShaper.forHorizontal([
  box16(2, -2, 14, 14, 14, 18),
  box16(3, -4, 10, 13, 13, 14),
  box16(2, -4, 6, 14, 14, 10),
  box16(0, -5, 0, 16, 16, 6),
], Direction.north);

/// `AllShapes.BELT_FUNNEL_PERPENDICULAR`.
final VoxelShaper beltFunnelPerpendicular = VoxelShaper.forHorizontal([
  box16(2, -2, 14, 14, 14, 18),
  box16(1, 8, 12, 15, 15, 14),
  box16(0.1, 13, 7, 15.9, 15, 11),
  box16(0.1, 9, 8, 15.9, 13, 12),
  box16(0.1, 5, 9, 15.9, 9, 13),
  box16(0.1, 1, 10, 15.9, 5, 14),
  box16(0.1, -3, 11, 15.9, 1, 15),
], Direction.north);

/// `AllShapes.FUNNEL_WALL`.
final VoxelShaper funnelWall = VoxelShaper.forHorizontal([
  box16(2, 2, 14, 14, 14, 18),
  box16(1, 8, 12, 15, 15, 14),
  box16(0.1, 13, 7, 15.9, 15, 11),
  box16(0.1, 9, 8, 15.9, 13, 12),
  box16(0.1, 5, 9, 15.9, 9, 13),
  box16(0.1, 1, 10, 15.9, 5, 14),
  box16(0.1, -1, 11, 15.9, 1, 15),
], Direction.north);

/// `AllShapes.FUNNEL_FLOOR`.
final Shape funnelFloor = [box16(2, -2, 2, 14, 8, 14), box16(1, 1, 1, 15, 8, 15), box16(0, 4, 0, 16, 10, 16)];

/// `AllShapes.FUNNEL_CEILING`.
final Shape funnelCeiling = [box16(2, 8, 2, 14, 18, 14), box16(1, 8, 1, 15, 15, 15), box16(0, 6, 0, 16, 12, 16)];

/// `AllShapes.ITEM_HATCH`.
final VoxelShaper itemHatch = VoxelShaper.forHorizontal([
  box16(1, 0, 0, 15, 16, 2),
  box16(2, 2, 0, 14, 13, 3.8),
  box16(2, 4, 0, 14, 11, 5.8),
  box16(2, 6, 0, 14, 9, 7.8),
], Direction.south);

/// `AllShapes.CHUTE`.
final Shape chuteVertical = [box16(1, 8, 1, 15, 16, 15), box16(2, 0, 2, 14, 8, 14)];

/// `ChuteShapes.createSlope()` (one panel per sixteenth, moved along the slope).
Shape _chuteSlope() {
  final panel = [box16(1, -15, 0, 15, 4, 1)];
  final out = <BlockBox>[];
  for (var i = 0; i < 16; i++) {
    final offset = i / 16;
    out.addAll(move(panel, 0, offset, offset));
  }
  return out;
}

/// `AllShapes.CHUTE_SLOPE`.
final VoxelShaper chuteSlope = VoxelShaper.forHorizontal(_chuteSlope(), Direction.south);

// -- Belts ---------------------------------------------------------------------------------

/// `BeltShapes`: the shape of a belt block by state (facing, part, slope, casing).
abstract final class BeltShapes {
  static final Shape _southMask = [box16(0, -5, 8, 16, 16 + 5, 16)];
  static final Shape _northMask = [box16(0, -5, 0, 16, 16 + 5, 8)];

  static Shape _compose(Shape southPart, Shape northPart) =>
      union([intersect(_southMask, southPart), intersect(_northMask, northPart)]);

  static Shape _slopePart(bool ascendingInstead) {
    final slice = [box16(1, 0, 15, 15, 11, 16)];
    final out = <BlockBox>[];
    for (var i = 0; i < 16; i++) {
      final yOffset = ascendingInstead ? 10 - i : i - 5;
      out.addAll(move(slice, 0, yOffset / 16, -i / 16));
    }
    return out;
  }

  static final Shape _slopeDescPart = _slopePart(false);
  static final Shape _slopeAscPart = _slopePart(true);
  static final Shape _sidewaysFullPart = [box16(3, 1, 0, 13, 15, 16)];
  static final Shape _sidewaysEndPart = [box16(4, 1, 0, 12, 15, 16), box16(3, 1, 1, 13, 15, 15)];
  static final Shape _flatFullPart = [box16(1, 3, 0, 15, 13, 16)];
  static final Shape _flatEndPart = [box16(1, 4, 0, 15, 12, 16), box16(1, 3, 1, 15, 13, 15)];

  static VoxelShaper _vertical(Shape southBeltShape) => VoxelShaper.forDirectionsWithRotation(
    rotatedCopy(southBeltShape, (-90.0, 0.0, 0.0)),
    Direction.south,
    Direction.planeHorizontal,
    (d) => (d.axisDirection == AxisDirection.positive ? 0.0 : 180.0, -d.toYRot, 0.0),
  );

  static final VoxelShaper _verticalFull = _vertical(_flatFullPart);
  static final VoxelShaper _verticalEnd = _vertical(_compose(_flatEndPart, _flatFullPart));
  static final VoxelShaper _verticalStart = _vertical(_compose(_flatFullPart, _flatEndPart));
  static final VoxelShaper _flatFull = VoxelShaper.forHorizontalAxis(_flatFullPart, Axis.z);
  static final VoxelShaper _flatEnd = VoxelShaper.forHorizontal(_compose(_flatEndPart, _flatFullPart), Direction.south);
  static final VoxelShaper _flatStart = VoxelShaper.forHorizontal(_compose(_flatFullPart, _flatEndPart), Direction.south);
  static final VoxelShaper _sideFull = VoxelShaper.forHorizontalAxis(_sidewaysFullPart, Axis.z);
  static final VoxelShaper _sideEnd =
      VoxelShaper.forHorizontal(_compose(_sidewaysEndPart, _sidewaysFullPart), Direction.south);
  static final VoxelShaper _sideStart =
      VoxelShaper.forHorizontal(_compose(_sidewaysFullPart, _sidewaysEndPart), Direction.south);
  static final VoxelShaper _slopeDesc = VoxelShaper.forHorizontal(_slopeDescPart, Direction.south);
  static final VoxelShaper _slopeAsc = VoxelShaper.forHorizontal(_slopeAscPart, Direction.south);
  static final VoxelShaper _slopeDescEnd =
      VoxelShaper.forHorizontal(_compose(_flatEndPart, _slopeDescPart), Direction.south);
  static final VoxelShaper _slopeDescStart =
      VoxelShaper.forHorizontal(_compose(_slopeDescPart, _flatEndPart), Direction.south);
  static final VoxelShaper _slopeAscEnd =
      VoxelShaper.forHorizontal(_compose(_flatEndPart, _slopeAscPart), Direction.south);
  static final VoxelShaper _slopeAscStart =
      VoxelShaper.forHorizontal(_compose(_slopeAscPart, _flatEndPart), Direction.south);
  static final VoxelShaper _partialCasing = VoxelShaper.forHorizontal([box16(0, 0, 5, 16, 11, 16)], Direction.south);

  static final Map<BState, Shape> _cache = {};
  static final Map<BState, Shape> _collisionCache = {};

  /// `BeltShapes.getShape` of the default state (`facing=north, part=start, slope=horizontal,
  /// casing=false`, the manifest's `defaultState`).
  ///
  /// This is the shape a belt block *registers*. Its Java shapes are per state (160
  /// combinations, more than the host's 64 static shape rules), so the real one is computed per
  /// state through the dynamic shape hook; the registered shape is the base the host falls back
  /// to, and — unlike the manifest's full-cube default — it is what the host derives the state
  /// flags and the light opacity from. `BeltShapes` is never a full cube, so `BeltBlock`'s
  /// `getLightDampening()` is 0: a belt does not occlude light.
  static final Shape registeredShape = _flatStart.get(Direction.north);

  /// `BeltShapes.getCollisionShape` of the default state.
  static final Shape registeredCollision = intersect(beltCollisionMask, registeredShape);

  /// `BeltShapes.getShape(state)`.
  static Shape getShape(BState state) =>
      _cache[state] ??= union([_beltShape(state), _casingShape(state)]);

  /// `BeltShapes.getCollisionShape(state)`.
  static Shape getCollisionShape(BState state) =>
      _collisionCache[state] ??= intersect(beltCollisionMask, getShape(state));

  static Shape _beltShape(BState state) {
    final facing = state.dir('facing') ?? Direction.north;
    final axis = facing.axis;
    final part = state['part'] ?? 'start';
    final slope = state['slope'] ?? 'horizontal';
    final middle = part == 'middle' || part == 'pulley';
    switch (slope) {
      case 'vertical':
        if (middle) return _verticalFull.getAxis(axis);
        return (part == 'start' ? _verticalStart : _verticalEnd).get(facing);
      case 'horizontal':
        if (middle) return _flatFull.getAxis(axis);
        return (part == 'start' ? _flatStart : _flatEnd).get(facing);
      case 'sideways':
        if (middle) return _sideFull.getAxis(axis);
        return (part == 'start' ? _sideStart : _sideEnd).get(facing);
    }
    final downward = slope == 'downward';
    if (middle) return (downward ? _slopeDesc : _slopeAsc).get(facing);
    if (part == 'start') return (downward ? _slopeDescStart : _slopeAscStart).get(facing);
    if (part == 'end') return (downward ? _slopeDescEnd : _slopeAscEnd).get(facing);
    return emptyShape;
  }

  static Shape _casingShape(BState state) {
    if (!state.flag('casing')) return emptyShape;
    final facing = state.dir('facing') ?? Direction.north;
    final part = state['part'] ?? 'start';
    final slope = state['slope'] ?? 'horizontal';
    if (slope == 'vertical' || slope == 'sideways') return emptyShape;
    if (slope == 'horizontal') return casing11px.get(Direction.up);
    final upward = slope == 'upward';
    if (part == 'middle' || part == 'pulley') {
      return _partialCasing.get(upward ? facing : facing.opposite);
    }
    if (part == 'start') {
      return upward ? casing11px.get(Direction.up) : _partialCasing.get(facing.opposite);
    }
    if (part == 'end') {
      return slope == 'downward' ? casing11px.get(Direction.up) : _partialCasing.get(facing);
    }
    return fullBlock;
  }
}

// -- Chutes --------------------------------------------------------------------------------

/// `ChuteShapes`.
abstract final class ChuteShapes {
  static final Shape _intersectionMask = [box16(0, -16, 0, 16, 16, 16)];
  static final Shape _collisionMask = [box16(0, 0, 0, 16, 24, 16)];

  /// `ChuteShapes.createShape` for a chute (`create:chute`) or smart chute (`create:smart_chute`).
  static Shape getShape(BState state) {
    if (state.key == 'create:smart_chute') return fullBlock;
    final direction = state.dir('facing') ?? Direction.down;
    final shape = state['shape'] ?? 'normal';
    final intersection = shape == 'intersection' || shape == 'encased';
    if (direction == Direction.down) return intersection ? fullBlock : chuteVertical;
    final combineWith = intersection ? fullBlock : emptyShape;
    var result = union([combineWith, chuteSlope.get(direction)]);
    if (intersection) result = intersect(_intersectionMask, result);
    return result;
  }

  static Shape getCollisionShape(BState state) => intersect(_collisionMask, getShape(state));
}

// -- Tunnels -------------------------------------------------------------------------------

/// `BeltTunnelShapes`.
abstract final class BeltTunnelShapes {
  static final Shape _block = [box16(0, -5, 0, 16, 16, 16)];
  static final VoxelShaper _opening = VoxelShaper.forHorizontal([box16(2, -5, 14, 14, 10, 16)], Direction.south);

  /// `Shapes.join(a, b, NOT_SAME)` for a block minus openings: the openings lie at the borders
  /// of the block, so the result is the block with those boxes carved out.
  static Shape _carve(Shape block, Shape openings) {
    var result = block;
    for (final o in openings) {
      result = _subtract(result, o);
    }
    return result;
  }

  static Shape _subtract(Shape shape, BlockBox cut) {
    final out = <BlockBox>[];
    for (final b in shape) {
      final minX = math.max(b.minX, cut.minX), minY = math.max(b.minY, cut.minY), minZ = math.max(b.minZ, cut.minZ);
      final maxX = math.min(b.maxX, cut.maxX), maxY = math.min(b.maxY, cut.maxY), maxZ = math.min(b.maxZ, cut.maxZ);
      if (!(minX < maxX && minY < maxY && minZ < maxZ)) {
        out.add(b);
        continue;
      }
      // Up to six slabs around the cut.
      if (b.minX < minX) out.add(BlockBox(b.minX, b.minY, b.minZ, minX, b.maxY, b.maxZ));
      if (maxX < b.maxX) out.add(BlockBox(maxX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ));
      if (b.minY < minY) out.add(BlockBox(minX, b.minY, b.minZ, maxX, minY, b.maxZ));
      if (maxY < b.maxY) out.add(BlockBox(minX, maxY, b.minZ, maxX, b.maxY, b.maxZ));
      if (b.minZ < minZ) out.add(BlockBox(minX, minY, b.minZ, maxX, maxY, minZ));
      if (maxZ < b.maxZ) out.add(BlockBox(minX, minY, maxZ, maxX, maxY, b.maxZ));
    }
    return out;
  }

  static final VoxelShaper _straight = VoxelShaper.forHorizontalAxis(
    _carve(_block, union([_opening.get(Direction.south), _opening.get(Direction.north)])),
    Axis.z,
  );
  static final VoxelShaper _tee = VoxelShaper.forHorizontal(
    _carve(
      _block,
      union([_opening.get(Direction.north), _opening.get(Direction.west), _opening.get(Direction.east)]),
    ),
    Direction.south,
  );
  static final Shape _cross = _carve(
    _block,
    union([
      _opening.get(Direction.south),
      _opening.get(Direction.north),
      _opening.get(Direction.west),
      _opening.get(Direction.east),
    ]),
  );

  /// `BeltTunnelShapes.getShape` (the tunnel's `axis` is `HORIZONTAL_AXIS`).
  static Shape getShape(BState state) {
    final shape = state['shape'] ?? 'straight';
    final axis = state.axisOf('axis') ?? Axis.x;
    if (shape == 'cross') return _cross;
    if (shape == 'straight' || shape == 'window' || shape == 'closed') return _straight.getAxis(axis);
    if (shape == 't_left') return _tee.get(axis == Axis.z ? Direction.east : Direction.north);
    if (shape == 't_right') return _tee.get(axis == Axis.z ? Direction.west : Direction.south);
    return fullBlock;
  }
}
