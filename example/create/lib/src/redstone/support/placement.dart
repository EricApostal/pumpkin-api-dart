// `getStateForPlacement` of the redstone blocks whose state depends on more than the
// host's placement rules can express (pure). The host places the block with the rules
// of its definition; for these blocks the module recomputes the state with the view of
// the placing player (see `placer.dart`) and rewrites it when it differs.
import 'dart:math' as math;

import '../../common/common.dart';

/// `BlockPlaceContext` as far as redstone blocks use it.
final class PlaceCtx {
  /// The position of the new block.
  final Pos pos;

  /// The placing player's yaw and pitch in degrees.
  final double yaw;
  final double pitch;
  final bool sneaking;

  /// The face of the clicked block (`getClickedFace`), `null` when unknown.
  final Direction? clickedFace;

  const PlaceCtx({required this.pos, required this.yaw, required this.pitch, this.sneaking = false, this.clickedFace});

  /// `getHorizontalDirection`.
  Direction get horizontalDirection => Direction.fromYRot(yaw);

  /// `getLookAngle` (the unit view vector).
  Vec3 get look {
    final yawRad = yaw * math.pi / 180;
    final pitchRad = pitch * math.pi / 180;
    final cp = math.cos(pitchRad);
    return (-math.sin(yawRad) * cp, -math.sin(pitchRad), math.cos(yawRad) * cp);
  }

  /// `getNearestLookingDirections`.
  List<Direction> get nearestLookingDirections {
    final (x, y, z) = look;
    return Direction.orderedByNearest(x, y, z);
  }

  /// `getNearestLookingDirection`.
  Direction get nearestLookingDirection => nearestLookingDirections.first;

  /// `getClickedPos().relative(...)` helper.
  Pos neighbour(Direction d) => pos.relative(d);
}

/// What the placement logic may ask about the surroundings.
abstract interface class PlaceWorld {
  /// `BlockState.isFaceSturdy(level, pos, face)` of the block at [pos].
  bool isFaceSturdy(Pos pos, Direction face);

  /// `BlockState.canBeReplaced()` of the block at [pos].
  bool canBeReplaced(Pos pos);

  /// Whether the block entity at [pos] can be observed (item or fluid handler, belt, funnel...).
  bool canDetect(Pos pos);
}

/// The result of a placement: the property values to apply on top of the placed state.
typedef PlacedProps = Map<String, String>;

/// `FaceAttachedHorizontalDirectionalBlock.getStateForPlacement` (the analog lever).
/// Returns `null` when no direction can carry the block.
PlacedProps? faceAttachedPlacement(PlaceCtx ctx, PlaceWorld world) {
  for (final direction in ctx.nearestLookingDirections) {
    final PlacedProps props;
    if (direction.axis == Axis.y) {
      props = {'face': direction == Direction.up ? 'ceiling' : 'floor', 'facing': ctx.horizontalDirection.serializedName};
    } else {
      props = {'face': 'wall', 'facing': direction.opposite.serializedName};
    }
    if (faceAttachedCanSurvive(ctx.pos, props['face']!, Direction.byName(props['facing']!)!, world)) return props;
  }
  return null;
}

/// `FaceAttachedHorizontalDirectionalBlock.getConnectedDirection`.
Direction attachedConnectedDirection(String face, Direction facing) => switch (face) {
  'ceiling' => Direction.down,
  'floor' => Direction.up,
  _ => facing,
};

/// `FaceAttachedHorizontalDirectionalBlock.canSurvive` / `canAttach`.
bool faceAttachedCanSurvive(Pos pos, String face, Direction facing, PlaceWorld world) {
  final direction = attachedConnectedDirection(face, facing).opposite;
  final neighbour = pos.relative(direction);
  return world.isFaceSturdy(neighbour, direction.opposite);
}

/// `DoubleFaceAttachedBlock.getStateForPlacement` + the nixie tube's `getStateForPlacement`
/// (facing turned clockwise for floor and ceiling tubes). `canSurvive` is always true for the
/// nixie tube. The look direction decides between `wall` and `wall_reversed`.
PlacedProps nixiePlacement(PlaceCtx ctx) {
  final direction = ctx.nearestLookingDirections.first;
  late String face;
  late Direction facing;
  if (direction.axis == Axis.y) {
    face = direction == Direction.up ? 'ceiling' : 'floor';
    facing = ctx.horizontalDirection;
  } else {
    final n = direction.clockWise.unitVec3;
    face = 'wall';
    final (lx, ly, lz) = ctx.look;
    if (lx * n.$1 + ly * n.$2 + lz * n.$3 < 0) face = 'wall_reversed';
    facing = direction.opposite;
  }
  if (face != 'wall' && face != 'wall_reversed') facing = facing.clockWise;
  return {'double_face': face, 'facing': facing.serializedName};
}

/// `RedstoneContactBlock.getStateForPlacement`. [validContactAt] says whether the block at a
/// position is a contact facing back at the direction (`hasValidContact`).
PlacedProps contactPlacement(PlaceCtx ctx, bool Function(Pos pos, Direction direction) hasValidContact) {
  var facing = ctx.nearestLookingDirection.opposite;
  final clicked = ctx.clickedFace;
  final placeDirection = clicked?.opposite;
  if (ctx.sneaking || (placeDirection != null && hasValidContact(ctx.pos, placeDirection))) {
    if (placeDirection != null) facing = placeDirection;
  }
  final powered = hasValidContact(ctx.pos, facing);
  return {'facing': facing.serializedName, 'powered': '$powered'};
}

/// `SmartObserverBlock` / `ThresholdSwitchBlock` `getStateForPlacement` (`DirectedDirectionalBlock`
/// target + facing). [detect] decides whether a neighbour can be observed; for the threshold
/// switch it is the item/fluid handler check.
PlacedProps directedPlacement(PlaceCtx ctx, bool Function(Pos pos) detect) {
  Direction? preferred;
  for (final face in ctx.nearestLookingDirections) {
    if (detect(ctx.pos.relative(face))) {
      preferred = face;
      break;
    }
  }
  if (preferred == null) {
    final facing = ctx.nearestLookingDirection;
    preferred = ctx.sneaking ? facing : facing.opposite;
  }
  var target = 'wall';
  if (preferred.axis == Axis.y) {
    target = preferred == Direction.up ? 'ceiling' : 'floor';
    preferred = ctx.horizontalDirection;
  }
  return {'target': target, 'facing': preferred.serializedName};
}

/// `RedstoneLinkBlock.canSurvive` for a link that is about to be placed at [pos]: the link
/// hangs on the block that was clicked. The host reports the placement face as
/// `CustomBlockCanPlaceEventData.face`, which points from the new block towards the clicked
/// block (`BlockPlaceContext.getClickedFace().getOpposite()`), so the support is
/// `pos.relative(face)` (Java: `pos.relative(FACING.getOpposite())`, `FACING` being the
/// clicked face).
bool linkCanSurvive(Pos pos, Direction face, bool Function(Pos support) canBeReplaced) =>
    !canBeReplaced(pos.relative(face));

/// `DirectedDirectionalBlock.getTargetDirection`.
Direction directedTargetDirection(String target, Direction facing) => switch (target) {
  'ceiling' => Direction.up,
  'floor' => Direction.down,
  _ => facing,
};

/// `ControllerRailBlock.getStateForPlacement`: `backwards` from the horizontal direction and the
/// rail axis (the host cannot connect rails to their neighbours).
PlacedProps railPlacement(PlaceCtx ctx) {
  final direction = ctx.horizontalDirection;
  final eastWest = direction == Direction.east || direction == Direction.west;
  return {
    'shape': eastWest ? 'east_west' : 'north_south',
    'backwards': '${direction.axisDirection == AxisDirection.positive}',
  };
}
