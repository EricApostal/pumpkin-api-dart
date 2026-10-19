// The geometry of belts (pure): slopes, parts, segment positions, belt chains, the belt vector,
// connector validation, and the state transforms. Ported from `BeltBlock`, `BeltHelper`,
// `BeltSlicer`, `BeltConnectorItem` and `BeltSlope` / `BeltPart`.
import 'dart:math' as math;

import '../../api/block_state.dart';
import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';

/// The axis of a belt: Java `belt.getValue(BeltBlock.HORIZONTAL_FACING).getAxis()`. The belt
/// stores a direction under `facing`, not an axis, so this reads `dir`; [Axis.x] when there is
/// no direction (e.g. a tunnel without a belt under it).
Axis beltAxis(BState belt) => belt.dir('facing')?.axis ?? Axis.x;

/// `BeltSlope`.
enum BeltSlope {
  horizontal,
  upward,
  downward,
  vertical,
  sideways;

  String get serializedName => name;

  bool get isDiagonal => this == upward || this == downward;

  static BeltSlope fromName(String? name) =>
      BeltSlope.values.firstWhere((s) => s.name == name, orElse: () => BeltSlope.horizontal);
}

/// `BeltPart`.
enum BeltPart {
  start,
  middle,
  end,
  pulley;

  String get serializedName => name;

  static BeltPart fromName(String? name) => BeltPart.values.firstWhere((s) => s.name == name, orElse: () => BeltPart.start);
}

/// The block key of belts.
const String beltKey = 'create:belt';

/// Typed access to the state of a belt block.
extension BeltState on BState {
  bool get isBelt => key == beltKey;
  Direction get beltFacing => dir('facing') ?? Direction.north;
  BeltSlope get beltSlope => BeltSlope.fromName(this['slope']);
  BeltPart get beltPart => BeltPart.fromName(this['part']);
  bool get beltCasing => flag('casing');
}

/// `BeltBlock.canTransportObjects(state)`.
bool canTransportObjects(BState state) {
  if (!state.isBelt) return false;
  final slope = state.beltSlope;
  return slope != BeltSlope.vertical && slope != BeltSlope.sideways;
}

/// `BeltBlock.getRotationAxis(state)`.
Axis beltRotationAxis(BState state) {
  if (state.beltSlope == BeltSlope.sideways) return Axis.y;
  return state.beltFacing.clockWise.axis;
}

/// `BeltBlock.nextSegmentPosition(state, pos, forward)`: the next belt block along the chain, or
/// `null` at the end of the chain.
Pos? nextSegmentPosition(BState state, Pos pos, bool forward) {
  final direction = state.beltFacing;
  final slope = state.beltSlope;
  final part = state.beltPart;
  final offset = forward ? 1 : -1;
  if ((part == BeltPart.end && forward) || (part == BeltPart.start && !forward)) return null;
  if (slope == BeltSlope.vertical) {
    return pos.aboveBy(direction.axisDirection == AxisDirection.positive ? offset : -offset);
  }
  pos = pos.relative(direction, offset);
  if (slope != BeltSlope.horizontal && slope != BeltSlope.sideways) {
    return pos.aboveBy(slope == BeltSlope.upward ? offset : -offset);
  }
  return pos;
}

/// `BeltBlock.getBeltChain(world, controllerPos)`: the belt blocks from the controller on.
List<Pos> getBeltChain(BlockGetter world, Pos controllerPos) {
  final positions = <Pos>[];
  if (!world.stateAt(controllerPos).isBelt) return positions;
  var limit = 1000;
  Pos? current = controllerPos;
  while (limit-- > 0 && current != null) {
    final state = world.stateAt(current);
    if (!state.isBelt) break;
    positions.add(current);
    current = nextSegmentPosition(state, current, true);
  }
  return positions;
}

/// `BeltHelper.getBeltVector(state)` as a vector of whole steps.
Vec3 beltVector(BState state) {
  final slope = state.beltSlope;
  final verticality = slope == BeltSlope.downward ? -1 : (slope == BeltSlope.upward ? 1 : 0);
  final facing = state.beltFacing;
  if (slope == BeltSlope.vertical) return (0, facing.axisDirection.step.toDouble(), 0);
  return (facing.stepX.toDouble(), verticality.toDouble(), facing.stepZ.toDouble());
}

/// `BlockPos.containing(BeltHelper.getBeltVector(state))`.
Pos beltVectorPos(BState state) {
  final v = beltVector(state);
  return (v.$1.floor(), v.$2.floor(), v.$3.floor());
}

/// `BeltHelper.getPositionForOffset(controller, offset)`: the block of the belt segment [offset].
Pos positionForOffset(Pos controller, BState controllerState, int beltLength, int offset) {
  final facing = controllerState.beltFacing;
  final slope = controllerState.beltSlope;
  final verticality = slope == BeltSlope.downward ? -1 : (slope == BeltSlope.upward ? 1 : 0);
  final clamped = offset.clamp(0, math.max(0, beltLength - 1)).toInt();
  return controller.offset(offset * facing.stepX, clamped * verticality, offset * facing.stepZ);
}

/// `BeltHelper.getVectorForOffset(controller, offset)`: the world position along the belt.
Vec3 vectorForOffset(Pos controller, BState controllerState, int beltLength, double offset) {
  final slope = controllerState.beltSlope;
  final verticality = slope == BeltSlope.downward ? -1 : (slope == BeltSlope.upward ? 1 : 0);
  var verticalMovement = verticality.toDouble();
  if (offset < .5) verticalMovement = 0;
  verticalMovement = verticalMovement * (math.min(offset, beltLength - .5) - .5);
  var vec = VecHelper.getCenterOf(controller);
  var horizontal = (
    controllerState.beltFacing.stepX * (offset - .5),
    0.0,
    controllerState.beltFacing.stepZ * (offset - .5),
  );
  if (slope == BeltSlope.vertical) horizontal = (0.0, 0.0, 0.0);
  vec = (vec.$1 + horizontal.$1, vec.$2 + horizontal.$2 + verticalMovement, vec.$3 + horizontal.$3);
  return vec;
}

/// Whether the part is a pulley (a block with a shaft sticking out): `BeltBlockEntity.hasPulley`.
bool beltHasPulley(BState state) => state.isBelt && state.beltPart != BeltPart.middle;

// -- Rotation, mirror and structure transforms ---------------------------------------------

/// `BeltBlock.rotate(state, rotation)`: rotates the facing and swaps start and end of vertical
/// belts whose direction flips.
BState rotateBelt(BState state, BlockRotation rot) {
  final rotated = state.setDir('facing', rot.rotate(state.beltFacing));
  if (state.beltSlope != BeltSlope.vertical) return rotated;
  if (state.beltFacing.axisDirection != rotated.beltFacing.axisDirection) {
    if (state.beltPart == BeltPart.start) return rotated.setValue('part', 'end');
    if (state.beltPart == BeltPart.end) return rotated.setValue('part', 'start');
  }
  return rotated;
}

/// `BeltBlock.mirror(state, mirror)` (`HorizontalDirectionalBlock.mirror`: the facing mirrors).
BState mirrorBelt(BState state, BlockMirror mirror) {
  if (mirror == BlockMirror.none) return state;
  final mirrored = state.setDir('facing', mirror.mirrorDirection(state.beltFacing));
  return mirrored;
}

/// `BeltBlock.transformInner` + `transform`: a structure transform with [rotationAxis] and
/// [rotation] (the number of quarter turns, `Rotation.ordinal()`) and an optional mirror.
BState transformBelt(BState state, {required Axis rotationAxis, required BlockRotation rotation, BlockMirror? mirror}) {
  if (mirror != null && mirror != BlockMirror.none) state = mirrorBelt(state, mirror);
  if (rotationAxis == Axis.y) return rotateBelt(state, rotation);
  return _transformInner(state, rotationAxis, rotation);
}

BState _transformInner(BState state, Axis rotationAxis, BlockRotation rotation) {
  final halfTurn = rotation == BlockRotation.clockwise180;
  final initialDirection = state.beltFacing;
  final diagonal = state.beltSlope == BeltSlope.downward || state.beltSlope == BeltSlope.upward;
  if (!diagonal) {
    for (var i = 0; i < rotation.index; i++) {
      final direction = state.beltFacing;
      final slope = state.beltSlope;
      final vertical = slope == BeltSlope.vertical;
      final horizontal = slope == BeltSlope.horizontal;
      final sideways = slope == BeltSlope.sideways;
      var newDirection = direction.opposite;
      var newSlope = BeltSlope.vertical;
      if (vertical) {
        if (direction.axis == rotationAxis) {
          newDirection = direction.counterClockWise;
          newSlope = BeltSlope.sideways;
        } else {
          newSlope = BeltSlope.horizontal;
          newDirection = direction;
          if (direction.axis == Axis.z) newDirection = direction.opposite;
        }
      }
      if (sideways) {
        newDirection = direction;
        if (direction.axis == rotationAxis) {
          newSlope = BeltSlope.horizontal;
        } else {
          newDirection = direction.counterClockWise;
        }
      }
      if (horizontal) {
        newDirection = direction;
        if (direction.axis == rotationAxis) {
          newSlope = BeltSlope.sideways;
        } else if (direction.axis != Axis.z) {
          newDirection = direction.opposite;
        }
      }
      state = state.setDir('facing', newDirection).setValue('slope', newSlope.name);
    }
  } else if (initialDirection.axis != rotationAxis) {
    for (var i = 0; i < rotation.index; i++) {
      final direction = state.beltFacing;
      final newDirection = direction.opposite;
      final slope = state.beltSlope;
      final upward = slope == BeltSlope.upward;
      final downward = slope == BeltSlope.downward;
      // Rotate diagonal
      final flip = (direction.axisDirection == AxisDirection.positive) ^ downward ^ (direction.axis == Axis.z);
      if (flip) {
        state = state.setValue('slope', (upward ? BeltSlope.downward : BeltSlope.upward).name);
      } else {
        state = state.setDir('facing', newDirection);
      }
    }
  } else if (halfTurn) {
    final direction = state.beltFacing;
    final newDirection = direction.opposite;
    final slope = state.beltSlope;
    final vertical = slope == BeltSlope.vertical;
    if (diagonal) {
      state = state.setValue(
        'slope',
        (slope == BeltSlope.upward ? BeltSlope.downward : (slope == BeltSlope.downward ? BeltSlope.upward : slope)).name,
      );
    } else if (vertical) {
      state = state.setDir('facing', newDirection);
    }
  }
  return state;
}

// -- BeltSlicer helpers ------------------------------------------------------------------------

/// `BeltSlicer.beltStatesCompatible`.
bool beltStatesCompatible(BState state, BState nextState) {
  final facing1 = state.beltFacing;
  final slope1 = state.beltSlope;
  final facing2 = nextState.beltFacing;
  final slope2 = nextState.beltSlope;
  switch (slope1) {
    case BeltSlope.upward:
      if (slope2 == BeltSlope.downward) return facing1 == facing2.opposite;
      return slope2 == slope1 && facing1 == facing2;
    case BeltSlope.downward:
      if (slope2 == BeltSlope.upward) return facing1 == facing2.opposite;
      return slope2 == slope1 && facing1 == facing2;
    default:
      return slope2 == slope1 && facing2.axis == facing1.axis;
  }
}

/// `BeltSlicer.flipBelt`.
BState flipBelt(BState state) {
  final facing = state.beltFacing;
  final slope = state.beltSlope;
  final part = state.beltPart;
  if (slope == BeltSlope.upward) {
    state = state.setValue('slope', 'downward');
  } else if (slope == BeltSlope.downward) {
    state = state.setValue('slope', 'upward');
  }
  if (part == BeltPart.end) {
    state = state.setValue('part', 'start');
  } else if (part == BeltPart.start) {
    state = state.setValue('part', 'end');
  }
  return state.setDir('facing', facing.opposite);
}

/// `BeltSlicer.hoveringEnd(state, hit)`: whether the hit point (absolute) is on the half of the
/// end block that is past the end of the belt.
bool hoveringEnd(BState state, Pos blockPos, Vec3 hitLocation) {
  final part = state.beltPart;
  if (part == BeltPart.middle || part == BeltPart.pulley) return false;
  final bv = beltVector(state);
  final center = VecHelper.getCenterOf(blockPos);
  final sub = (hitLocation.$1 - center.$1, hitLocation.$2 - center.$2, hitLocation.$3 - center.$3);
  final dot = sub.$1 * bv.$1 + sub.$2 * bv.$2 + sub.$3 * bv.$3;
  return (dot > 0) == (part == BeltPart.end);
}

// -- BeltConnectorItem helpers --------------------------------------------------------------------

/// `BeltConnectorItem.getSlopeBetween`.
BeltSlope getSlopeBetween(Pos start, Pos end) {
  final diff = end - start;
  if (diff.y != 0) {
    if (diff.z != 0 || diff.x != 0) return diff.y > 0 ? BeltSlope.upward : BeltSlope.downward;
    return BeltSlope.vertical;
  }
  return BeltSlope.horizontal;
}

/// `BeltConnectorItem.getFacingFromTo`.
Direction getFacingFromTo(Pos start, Pos end) {
  final beltAxis = start.x == end.x ? Axis.z : Axis.x;
  final diff = end - start;
  var axisDirection = AxisDirection.positive;
  if (diff.x == 0 && diff.z == 0) {
    axisDirection = diff.y > 0 ? AxisDirection.positive : AxisDirection.negative;
  } else {
    axisDirection = beltAxis.choose(diff.x, 0, diff.z) > 0 ? AxisDirection.positive : AxisDirection.negative;
  }
  return Direction.fromAxisAndDirection(beltAxis, axisDirection);
}

/// `BeltConnectorItem.getBeltChainBetween`.
List<Pos> getBeltChainBetween(Pos start, Pos end, BeltSlope slope, Direction direction) {
  final positions = <Pos>[];
  var limit = 1000;
  var current = start;
  do {
    positions.add(current);
    if (slope == BeltSlope.vertical) {
      current = current.aboveBy(direction.axisDirection == AxisDirection.positive ? 1 : -1);
      continue;
    }
    current = current.relative(direction);
    if (slope != BeltSlope.horizontal) current = current.aboveBy(slope == BeltSlope.upward ? 1 : -1);
  } while (current != end && limit-- > 0);
  positions.add(end);
  return positions;
}

/// `BeltConnectorItem.createBelts` positions: the belt states to place between two shafts, in
/// chain order, as (position, part, slope, facing).
List<(Pos, BeltPart, BeltSlope, Direction)> planBelts(
  Pos start,
  Pos end,
  BlockGetter world,
) {
  var slope = getSlopeBetween(start, end);
  var facing = getFacingFromTo(start, end);
  final diff = end - start;
  if (diff.x == diff.z) {
    final startAxis = world.stateAt(start).axisOf('axis');
    facing = Direction.fromAxisAndDirection(startAxis == Axis.x ? Axis.z : Axis.x, facing.axisDirection);
  }
  final out = <(Pos, BeltPart, BeltSlope, Direction)>[];
  for (final pos in getBeltChainBetween(start, end, slope, facing)) {
    var part = pos == start ? BeltPart.start : (pos == end ? BeltPart.end : BeltPart.middle);
    final shaft = world.stateAt(pos);
    final pulley = isShaftState(shaft);
    if (part == BeltPart.middle && pulley) part = BeltPart.pulley;
    if (pulley && shaft.axisOf('axis') == Axis.y) slope = BeltSlope.sideways;
    out.add((pos, part, slope, facing));
  }
  return out;
}

/// `ShaftBlock.isShaft(state)`.
bool isShaftState(BState state) => state.key == 'create:shaft';

/// `BeltConnectorItem.validateAxis` for a loaded position.
bool validateAxis(BlockGetter world, Pos pos) => world.isLoaded(pos) && isShaftState(world.stateAt(pos));

/// `BeltConnectorItem.canConnect(world, first, second)`. [speedOf] gives the theoretical
/// kinetic speed of the shaft at a position (`null`: not a kinetic block entity).
bool canConnectBelt(
  BlockGetter world,
  Pos first,
  Pos second,
  int maxLength,
  double? Function(Pos pos) speedOf,
) {
  if (!world.isLoaded(first) || !world.isLoaded(second)) return false;
  if (!_closerThan(second, first, maxLength.toDouble())) return false;
  final diff = second - first;
  final shaftAxis = world.stateAt(first).axisOf('axis');
  if (shaftAxis == null) return false;
  final x = diff.x, y = diff.y, z = diff.z;
  final sames = (x.abs() == y.abs() ? 1 : 0) + (y.abs() == z.abs() ? 1 : 0) + (z.abs() == x.abs() ? 1 : 0);
  if (shaftAxis.choose(x, y, z) != 0) return false;
  if (sames != 1) return false;
  if (shaftAxis != world.stateAt(second).axisOf('axis')) return false;
  if (shaftAxis == Axis.y && x != 0 && z != 0) return false;
  final speed1 = speedOf(first);
  final speed2 = speedOf(second);
  if (speed1 == null || speed2 == null) return false;
  if (speed1.sign != speed2.sign && speed1 != 0 && speed2 != 0) return false;
  final step = (x.sign, y.sign, z.sign);
  var limit = 1000;
  for (var current = first + step; current != second && limit-- > 0; current = current + step) {
    final state = world.stateAt(current);
    if (isShaftState(state) && state.axisOf('axis') == shaftAxis) continue;
    if (!world.canBeReplaced(current)) return false;
  }
  return true;
}

/// `Vec3i.closerThan(vec, distance)`: the Euclidean distance is below [distance].
bool _closerThan(Pos a, Pos b, double distance) {
  final dx = (a.x - b.x).toDouble(), dy = (a.y - b.y).toDouble(), dz = (a.z - b.z).toDouble();
  return dx * dx + dy * dy + dz * dz < distance * distance;
}

/// `Vec3i.closerThan` for callers outside this file.
bool posCloserThan(Pos a, Pos b, double distance) => _closerThan(a, b, distance);

/// `BeltBlock.isBlockCoveringBelt`: whether the block above a belt covers it (a collision box of at
/// least half a block in both horizontal directions that starts at the bottom of the block),
/// excluding crushing wheel controllers, side facing funnels and tunnels.
bool isBlockCoveringBelt(BlockGetter world, Pos pos) {
  final state = world.stateAt(pos);
  final boxes = world.collisionBoxes(pos);
  if (boxes.isEmpty) return false;
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxZ = -double.infinity;
  for (final b in boxes) {
    minX = math.min(minX, b.minX);
    minY = math.min(minY, b.minY);
    minZ = math.min(minZ, b.minZ);
    maxX = math.max(maxX, b.maxX);
    maxZ = math.max(maxZ, b.maxZ);
  }
  if (maxX - minX < .5 || maxZ - minZ < .5) return false;
  if (minY > 0) return false;
  if (state.key == 'create:crushing_wheel_controller') return false;
  if (_isFunnel(state) && _funnelFacing(state) != Direction.up) return false;
  if (state.key == 'create:andesite_tunnel' || state.key == 'create:brass_tunnel') return false;
  return true;
}

bool _isFunnel(BState s) =>
    s.key == 'create:andesite_funnel' ||
    s.key == 'create:brass_funnel' ||
    s.key == 'create:andesite_belt_funnel' ||
    s.key == 'create:brass_belt_funnel';

Direction? _funnelFacing(BState s) => s.dir('facing');
