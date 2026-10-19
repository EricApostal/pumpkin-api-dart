// `BeltMovementHandler` (host): moves entities standing on a belt. Ported from
// `content/kinetics/belt/transport/BeltMovementHandler.java`. The living-entity step height,
// slowness effect and entity collision checks of the Java version need host APIs the plugin does
// not have; the movement itself (direction, slope, centering, velocity past the end) is ported.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../kinetics/geometry.dart' show KState;
import 'belt_block_entity.dart';
import 'belt_geometry.dart' show BeltState;

/// `BeltMovementHandler.TransportedEntityInfo`: where an entity last touched a belt.
final class TransportedEntityInfo {
  int ticksSinceLastCollision = 0;
  Pos lastCollidedPos;
  KState lastCollidedState;

  TransportedEntityInfo(Pos collision, KState belt)
    : lastCollidedPos = collision,
      lastCollidedState = belt;

  void refresh(Pos collision, KState belt) {
    ticksSinceLastCollision = 0;
    lastCollidedPos = collision;
    lastCollidedState = belt;
  }

  void tick() => ticksSinceLastCollision++;
}

/// `BeltMovementHandler.canBeTransported`: players that sneak (without cardboard boots) stay put.
bool canBeTransported(Entity entity) {
  if (entity.isSneaking()) return false;
  return true;
}

/// `BeltMovementHandler.transportEntity`.
void transportEntity(
  BeltBlockEntity belt,
  Entity entity,
  TransportedEntityInfo info,
) {
  final pos = info.lastCollidedPos;
  final state = info.lastCollidedState;
  final beltFacing = _dir(state, 'facing') ?? Direction.north;
  final slope = state['slope'] ?? 'horizontal';
  final part = state['part'] ?? 'start';
  final axis = beltFacing.axis;

  final movementFacing = Direction.fromAxisAndDirection(
    axis,
    belt.speed < 0 ? AxisDirection.positive : AxisDirection.negative,
  );

  // Too slow.
  if (belt.speed.abs() < 1) return;

  // Not on top.
  if (entity.getPosition().$2 - .25 < pos.y) return;

  final movementSpeed = belt.beltMovementSpeed;
  final movementDirection = Direction.fromAxisAndDirection(
    axis,
    axis == Axis.x ? AxisDirection.negative : AxisDirection.positive,
  );
  final centeringDirection = Direction.fromAxisAndDirection(
    beltFacing.clockWise.axis,
    AxisDirection.positive,
  ).unitVec3;
  var movement = movementDirection.unitVec3 * movementSpeed;

  final entityPos = entity.getPosition();
  final diffCenter = axis == Axis.z
      ? (pos.x + .5 - entityPos.$1)
      : (pos.z + .5 - entityPos.$3);
  if (diffCenter.abs() > 48 / 64) return;

  final notHorizontal = slope != 'horizontal';
  const top = 13 / 16;
  final onSlope =
      notHorizontal &&
      (part == 'middle' ||
          part == 'pulley' ||
          part == ((slope == 'upward') ? 'end' : 'start') &&
              entityPos.$2 - pos.y < top ||
          part == ((slope == 'upward') ? 'start' : 'end') &&
              entityPos.$2 - pos.y > top);

  var movingDown =
      onSlope &&
      slope == (movementFacing == beltFacing ? 'downward' : 'upward');
  var movingUp =
      onSlope &&
      slope == (movementFacing == beltFacing ? 'upward' : 'downward');
  if (beltFacing.axis == Axis.z) {
    final b = movingDown;
    movingDown = movingUp;
    movingUp = b;
  }

  if (movingUp)
    movement = (
      movement.$1,
      movement.$2 + axis.choose(movement.$1, movement.$2, movement.$3).abs(),
      movement.$3,
    );
  if (movingDown)
    movement = (
      movement.$1,
      movement.$2 - axis.choose(movement.$1, movement.$2, movement.$3).abs(),
      movement.$3,
    );

  final centering =
      centeringDirection * (diffCenter * math.min(movementSpeed.abs(), .1) * 4);
  if (!entity.isLiving()) movement = movement + centering;

  entity.setFallDistance(distance: 0);

  if (movingUp) {
    const minVelocity = .13;
    final yMovement = -(math.max(movement.$2.abs(), minVelocity));
    entity.moveEntity(delta: (0, yMovement, 0), collide: false);
    entity.moveEntity(delta: (movement.$1, 0, movement.$3), collide: false);
  } else if (movingDown) {
    entity.moveEntity(delta: (movement.$1, 0, movement.$3), collide: false);
    entity.moveEntity(delta: (0, movement.$2, 0), collide: false);
  } else {
    entity.moveEntity(delta: movement, collide: false);
  }

  entity.setOnGround(onGround: true);

  final entityBlock = (
    entityPos.$1.floor(),
    entityPos.$2.floor(),
    entityPos.$3.floor(),
  );
  final movedPastEndingSlope =
      onSlope &&
      (belt.stateAt(entityBlock).isBelt ||
          belt.stateAt(entityBlock.below).isBelt);

  if (movedPastEndingSlope && !movingDown && movementSpeed.abs() > 0) {
    entity.moveEntity(delta: (0, movement.$2, 0), collide: false);
  }
  if (movedPastEndingSlope) entity.setVelocity(velocity: movement);
}

Direction? _dir(KState state, String name) {
  final v = state[name];
  return v == null ? null : Direction.byName(v);
}
