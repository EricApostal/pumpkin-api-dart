// `MinecartSim2020`: the rail simulation the coupling uses to keep two carts a fixed distance
// apart along a track. Vanilla's rail-curve sampling (`OldMinecartBehavior.getPos`) is not exposed
// by the host, so the cart is snapped onto the rail axis instead of the curve; the rest (slope
// adjustment, speed clamp, motion restore) follows Java.
//
// Java: `content/contraptions/minecart/MinecartSim2020`.
import 'dart:math' as math;

import '../../common/common.dart';
import 'minecart_access.dart';

/// `AbstractMinecart#getSlopeAdjustment()`: 1/128.
const double slopeAdjustment = 0.0078125;

/// `predictNextPositionOf`.
Vec3 predictNextPositionOf(MinecartAccess cart) =>
    cart.position + clampVec(cart.velocity, 1);

/// `VecHelper.clamp`.
Vec3 clampVec(Vec3 v, double maxLength) =>
    v.lengthSquared > maxLength * maxLength ? v.normalized * maxLength : v;

/// `canAddMotion`: a stalled or actively pushing furnace cart cannot be corrected.
bool canAddMotion(MinecartAccess cart) {
  if (cart.isFurnaceCart) return false;
  return !MinecartStallLookup.isStalled(cart.uuid);
}

/// `moveCartAlongTrack`: moves [cart] along [trackPos]'s rail by [forcedMovement].
void moveCartAlongTrack(
  MinecartAccess cart,
  Vec3 forcedMovement,
  Pos trackPos,
) {
  if (forcedMovement == vec3Zero) return;

  final shape = cart.railShape;
  if (shape == null) {
    cart.setPosition(cart.position + forcedMovement);
    return;
  }

  final previousMotion = cart.velocity;
  var movement = forcedMovement;
  var y = cart.position.$2;

  switch (shape) {
    case RailShape.ascendingEast:
      movement = movement + (-slopeAdjustment, 0.0, 0.0);
      y += 1;
    case RailShape.ascendingWest:
      movement = movement + (slopeAdjustment, 0.0, 0.0);
      y += 1;
    case RailShape.ascendingNorth:
      movement = movement + (0.0, 0.0, slopeAdjustment);
      y += 1;
    case RailShape.ascendingSouth:
      movement = movement + (0.0, 0.0, -slopeAdjustment);
      y += 1;
    default:
      break;
  }

  final axis = railVec(shape);
  final clamped = clampVec(movement, math.min(1.75, cart.maxSpeed));
  cart
    ..setPosition(
      (cart.position.$1, y, cart.position.$3) +
          axis * _railOffset(clamped, axis),
    )
    ..setVelocity(clamped);
  cart.move(clamped);
  cart.setVelocity(previousMotion);
}

/// The distance along [axis] the forced movement travels (the projection of its horizontal part).
double _railOffset(Vec3 movement, Vec3 axis) {
  final horizontal = (movement.$1, 0.0, movement.$3);
  final length = horizontal.length;
  return axis.dot(horizontal) >= 0 ? length : -length;
}

/// The stall state the controller keeps, as `MinecartSim2020.canAddMotion` asks for it.
abstract final class MinecartStallLookup {
  static bool Function(String cartUuid) isStalled = (_) => false;
}
