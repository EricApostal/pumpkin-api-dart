// How kinetic blocks choose their state when a player places them
// (`getStateForPlacement` of the Java blocks), as pure functions of the
// surroundings and the player's look. The host places the block with a
// baseline state; the module corrects it with these (`KineticPlacement`).
import 'dart:math' as math;

import 'geometry.dart';
import 'node.dart';

/// What `BlockPlaceContext` knows.
final class PlacementContext {
  /// Where the block is placed (`getClickedPos`).
  final KPos pos;

  /// The face of the block that was clicked (`getClickedFace`).
  final Dir clickedFace;

  /// `getNearestLookingDirection()`.
  final Dir nearestLooking;

  /// `getHorizontalDirection()`.
  final Dir horizontal;

  /// Whether the placing player sneaks (`false` when there is no player).
  final bool sneaking;

  /// `getPlayer() != null`.
  final bool hasPlayer;

  /// `getLevel().getBlockState`.
  final KState Function(KPos pos) stateAt;

  final KineticBlockRegistry blocks;

  const PlacementContext({
    required this.pos,
    required this.clickedFace,
    required this.nearestLooking,
    required this.horizontal,
    required this.sneaking,
    required this.stateAt,
    required this.blocks,
    this.hasPlayer = true,
  });

  /// The position the block was placed against.
  KPos get placedOnPos => pos.relative(clickedFace.opposite);
}

/// `Direction.orderedByNearest(entity)`: all six directions, the one the player
/// looks at first (yaw / pitch in degrees, Minecraft's convention).
List<Dir> orderedByNearest(double yaw, double pitch) {
  final f = pitch * (math.pi / 180);
  final g = -yaw * (math.pi / 180);
  final h = math.sin(f);
  final i = math.cos(f);
  final j = math.sin(g);
  final k = math.cos(g);
  final bl = j > 0;
  final bl2 = h < 0;
  final bl3 = k > 0;
  final l = bl ? j : -j;
  final m = bl2 ? -h : h;
  final n = bl3 ? k : -k;
  final o = l * i;
  final p = n * i;
  final direction = bl ? Dir.east : Dir.west;
  final direction2 = bl2 ? Dir.up : Dir.down;
  final direction3 = bl3 ? Dir.south : Dir.north;
  List<Dir> make(Dir a, Dir b, Dir c) => [a, b, c, c.opposite, b.opposite, a.opposite];
  if (l > n) {
    if (m > o) return make(direction2, direction, direction3);
    return p > m ? make(direction, direction3, direction2) : make(direction, direction2, direction3);
  } else if (m > p) {
    return make(direction2, direction3, direction);
  } else {
    return o > m ? make(direction3, direction, direction2) : make(direction3, direction2, direction);
  }
}

/// `getNearestLookingDirection()`.
Dir nearestLookingDirection(double yaw, double pitch) => orderedByNearest(yaw, pitch).first;

/// `Entity.getDirection()`: the horizontal facing from the yaw.
Dir horizontalDirection(double yaw) {
  final index = (yaw / 90 + .5).floor() & 3;
  return Dir.horizontals[index]; // from2DDataValue: south, west, north, east
}

// -- Preferred orientation next to existing shafts ------------------------------------

/// `RotatedPillarKineticBlock.getPreferredAxis`.
KAxis? preferredAxis(PlacementContext ctx) {
  KAxis? preferred;
  for (final side in Dir.values) {
    final neighbourPos = ctx.pos.relative(side);
    final state = ctx.stateAt(neighbourPos);
    final def = ctx.blocks.defFor(state);
    if (def != null && def.hasShaftTowards(state, side.opposite)) {
      if (preferred != null && preferred != side.axis) {
        preferred = null;
        break;
      } else {
        preferred = side.axis;
      }
    }
  }
  return preferred;
}

/// `DirectionalKineticBlock.getPreferredFacing`.
Dir? preferredFacing(PlacementContext ctx) => _preferredSide(ctx, Dir.values);

/// `HorizontalKineticBlock.getPreferredHorizontalFacing`.
Dir? preferredHorizontalFacing(PlacementContext ctx) => _preferredSide(ctx, Dir.horizontals);

Dir? _preferredSide(PlacementContext ctx, List<Dir> sides) {
  Dir? preferred;
  for (final side in sides) {
    final neighbourPos = ctx.pos.relative(side);
    final state = ctx.stateAt(neighbourPos);
    final def = ctx.blocks.defFor(state);
    if (def != null && def.hasShaftTowards(state, side.opposite)) {
      if (preferred != null && preferred.axis != side.axis) {
        preferred = null;
        break;
      } else {
        preferred = side;
      }
    }
  }
  return preferred;
}

/// `HorizontalAxisKineticBlock.getPreferredHorizontalAxis`.
KAxis? preferredHorizontalAxis(PlacementContext ctx) => preferredHorizontalFacing(ctx)?.axis;

/// `CogWheelBlock.isValidCogwheelPosition`.
bool isValidCogwheelPosition(
  bool large,
  KState Function(KPos pos) stateAt,
  KineticBlockRegistry blocks,
  KPos pos,
  KAxis cogAxis,
) {
  for (final facing in Dir.values) {
    if (facing.axis == cogAxis) continue;

    final offsetPos = pos.relative(facing);
    final state = stateAt(offsetPos);
    final axisProp = state.axisOf('axis');
    if (axisProp != null && facing.axis == axisProp) continue;

    if (blocks.isLargeCog(state) || (large && blocks.isSmallCog(state))) return false;
  }
  return true;
}

// -- Per block placement ----------------------------------------------------------------

/// `RotatedPillarKineticBlock.getStateForPlacement`: the axis.
KAxis rotatedPillarAxis(PlacementContext ctx) {
  final preferred = preferredAxis(ctx);
  if (preferred != null && !ctx.sneaking) return preferred;
  return preferred != null && ctx.sneaking ? ctx.clickedFace.axis : ctx.nearestLooking.axis;
}

/// `AbstractEncasedShaftBlock.getStateForPlacement`.
KAxis encasedShaftAxis(PlacementContext ctx) {
  if (ctx.sneaking) return rotatedPillarAxis(ctx);
  return preferredAxis(ctx) ?? ctx.nearestLooking.axis;
}

/// `DirectionalKineticBlock.getStateForPlacement`: the facing.
Dir directionalFacing(PlacementContext ctx) {
  final preferred = preferredFacing(ctx);
  if (preferred == null || (ctx.hasPlayer && ctx.sneaking)) {
    final nearest = ctx.nearestLooking;
    return ctx.hasPlayer && ctx.sneaking ? nearest : nearest.opposite;
  }
  return preferred.opposite;
}

/// `CreativeMotorBlock.getStateForPlacement`.
Dir creativeMotorFacing(PlacementContext ctx) {
  final preferred = preferredFacing(ctx);
  if ((ctx.hasPlayer && ctx.sneaking) || preferred == null) return directionalFacing(ctx);
  return preferred;
}

/// `HandCrankBlock.getStateForPlacement`.
Dir handCrankFacing(PlacementContext ctx) {
  final preferred = preferredFacing(ctx);
  if (preferred == null || (ctx.hasPlayer && ctx.sneaking)) return ctx.clickedFace;
  return preferred.opposite;
}

/// `CogWheelBlock.getAxisForPlacement`.
KAxis cogwheelAxis(PlacementContext ctx, {required bool large}) {
  if (ctx.hasPlayer && ctx.sneaking) return ctx.clickedFace.axis;

  final stateBelow = ctx.stateAt(ctx.pos.below());
  if (stateBelow.isCreate('rotation_speed_controller') && large) {
    return stateBelow.axisOf('axis') == KAxis.x ? KAxis.z : KAxis.x;
  }

  final placedAgainst = ctx.stateAt(ctx.placedOnPos);
  final def = ctx.blocks.defFor(placedAgainst);
  if (def != null && def.isSmallCog) return def.rotationAxis(placedAgainst);

  return preferredAxis(ctx) ?? ctx.clickedFace.axis;
}

/// `EncasedCogwheelBlock.getStateForPlacement`: the axis.
KAxis encasedCogwheelAxis(PlacementContext ctx) {
  final placedOn = ctx.stateAt(ctx.placedOnPos);
  final def = ctx.blocks.defFor(placedOn);
  var axis = rotatedPillarAxis(ctx);
  if (def != null && def.isSmallCog) axis = def.rotationAxis(placedOn);
  return axis;
}

/// `SpeedControllerBlock.getStateForPlacement`: the horizontal axis.
KAxis speedControllerAxis(PlacementContext ctx) {
  final above = ctx.stateAt(ctx.pos.above());
  if (ctx.blocks.isLargeCog(above)) {
    final a = above.axisOf('axis');
    if (a != null && a.isHorizontal) return a == KAxis.x ? KAxis.z : KAxis.x;
  }
  // HorizontalAxisKineticBlock
  final preferred = preferredHorizontalAxis(ctx);
  if (preferred != null) return preferred;
  return ctx.horizontal.clockWise(KAxis.y).axis;
}

/// `CuckooClockBlock.getStateForPlacement`: the facing.
Dir cuckooClockFacing(PlacementContext ctx) {
  final preferred = preferredHorizontalFacing(ctx);
  if (preferred != null) return preferred.opposite;
  return ctx.horizontal.opposite;
}

/// `GaugeBlock.getStateForPlacement`.
({Dir facing, bool alongFirst}) gaugePlacement(PlacementContext ctx) {
  final face = ctx.clickedFace;
  final placedOnPos = ctx.placedOnPos;
  final placedOnState = ctx.stateAt(placedOnPos);
  final def = ctx.blocks.defFor(placedOnState);

  if (def != null && def.hasShaftTowards(placedOnState, face)) {
    final horizontalFacing = ctx.horizontal;
    final lookPositive = ctx.nearestLooking.isPositive;
    if (face.axis == KAxis.x) {
      return (facing: lookPositive ? Dir.north : Dir.south, alongFirst: true);
    } else if (face.axis == KAxis.y) {
      return (facing: horizontalFacing.opposite, alongFirst: horizontalFacing.axis == KAxis.x);
    } else {
      return (facing: lookPositive ? Dir.west : Dir.east, alongFirst: false);
    }
  }

  // DirectionalAxisKineticBlock.getStateForPlacement with the gauge's overrides.
  final facing = ctx.clickedFace; // getFacingForPlacement
  var alongFirst = false;
  final faceAxis = facing.axis;
  bool prefers(KPos pos, Dir dir, bool shaftAxis) {
    if (!shaftAxis) return false;
    final neighbourPos = pos.relative(dir);
    final state = ctx.stateAt(neighbourPos);
    final d = ctx.blocks.defFor(state);
    return d != null && d.hasShaftTowards(state, dir.opposite);
  }

  if (faceAxis.isHorizontal) {
    alongFirst = faceAxis == KAxis.z;
    final positivePerpendicular = faceAxis == KAxis.x ? Dir.south : Dir.east;

    final shaftAbove = prefers(ctx.pos, Dir.up, true);
    final shaftBelow = prefers(ctx.pos, Dir.down, true);
    final preferLeft = prefers(ctx.pos, positivePerpendicular, false);
    final preferRight = prefers(ctx.pos, positivePerpendicular.opposite, false);

    if (shaftAbove || shaftBelow || preferLeft || preferRight) alongFirst = faceAxis == KAxis.x;
  }

  if (faceAxis.isVertical) {
    alongFirst = ctx.horizontal.axis != KAxis.x; // getAxisAlignmentForPlacement of the gauge
    Dir? preferredSide;

    for (final side in Dir.horizontals) {
      if (!prefers(ctx.pos, side, true) && !prefers(ctx.pos, side.clockWise(KAxis.y), false)) continue;
      if (preferredSide != null && preferredSide.axis != side.axis) {
        preferredSide = null;
        break;
      }
      preferredSide = side;
    }

    if (preferredSide != null) alongFirst = preferredSide.axis == KAxis.x;
  }

  return (facing: facing, alongFirst: alongFirst);
}
