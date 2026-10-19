// `CouplingPhysics`: keeps two coupled carts at the coupling distance, softly (velocity) and
// hard (position), following the rail where there is one.
//
// Java: `content/contraptions/minecart/CouplingPhysics`.
import 'dart:math' as math;

import '../../api/blocks.dart' show HostBlockGetter;
import '../../common/common.dart';
import 'minecart_access.dart';
import 'minecart_sim2020.dart';

/// `tickCoupling`.
void tickCoupling(Couple<MinecartAccess> carts) {
  final couplingLength = MinecartCouplingLookup.couplingLength(
    carts.first.uuid,
  );
  if (couplingLength <= 0) return;
  softCollisionStep(carts, couplingLength);
  hardCollisionStep(carts, couplingLength);
}

/// `softCollisionStep`: corrects the velocities of the next position.
void softCollisionStep(Couple<MinecartAccess> carts, double couplingLength) {
  final maxSpeed = carts.map((c) => c.maxSpeed);
  final canAdd = carts.map(canAddMotion);

  final motions = carts.map((c) => clampVec(c.velocity, 1));
  final nextPositions = carts.map(predictNextPositionOf);

  final shapes = carts.mapWithContext((cart, first) {
    final next = nextPositions.get(first);
    final below = (next.$1.floor(), next.$2.floor() - 1, next.$3.floor());
    final level = HostBlockGetter(cart.world);
    // `MinecartSim2020`: the rail is the block below the next position, or the next position.
    final at = isRailState(level.stateAt(below))
        ? below
        : (next.$1.floor(), next.$2.floor(), next.$3.floor());
    final state = level.stateAt(at);
    return isRailState(state) ? RailShape.byName(state['shape']) : null;
  });

  final futureStress =
      couplingLength - (nextPositions.first - nextPositions.second).length;
  if (futureStress.abs() < 1.0e-5) return;

  for (final current in [true, false]) {
    final pos = nextPositions.get(current);
    final link = nextPositions.get(!current) - pos;
    var correctionMagnitude = -futureStress / 2;

    if (canAdd.get(current) != canAdd.get(!current)) {
      correctionMagnitude = !canAdd.get(current) ? 0 : correctionMagnitude * 2;
    }
    if (!canAdd.get(current)) continue;

    final shape = shapes.get(current);
    final Vec3 correction;
    if (shape != null) {
      correction =
          followLinkOnRail(link, pos, correctionMagnitude, railVec(shape)) -
          pos;
    } else {
      correction = link.normalized * correctionMagnitude;
    }

    motions.set(
      current,
      motions.get(current) + clampVec(correction, maxSpeed.get(current)),
    );
  }

  motions.replaceWithParams((v, max) => clampVec(v, max), maxSpeed);
  carts.forEachWithParams((cart, motion) => cart.setVelocity(motion), motions);
}

/// `hardCollisionStep`: corrects the positions after the move.
void hardCollisionStep(Couple<MinecartAccess> carts, double couplingLength) {
  if (!canAddMotion(carts.get(false)) && canAddMotion(carts.get(true)))
    carts = carts.swap();

  final maxSpeed = carts.map((c) => c.maxSpeed);
  var firstLoop = true;

  for (final current in [true, false, true]) {
    final cart = carts.get(current);
    final otherCart = carts.get(!current);

    final stress = couplingLength - (cart.position - otherCart.position).length;
    if (stress.abs() < 1 / 8) continue;

    final railPos = cart.railPos;
    final shape = cart.railShape;

    final pos = cart.position;
    final link = otherCart.position - pos;
    var correctionMagnitude = firstLoop ? -stress / 2 : -stress;

    if (!canAddMotion(cart)) correctionMagnitude /= 2;

    final correction = shape != null
        ? followLinkOnRail(link, pos, correctionMagnitude, railVec(shape)) - pos
        : link.normalized * correctionMagnitude;

    const maxResolveSpeed = 1.75;
    final clamped = clampVec(
      correction,
      math.min(maxResolveSpeed, maxSpeed.get(current)),
    );

    if (shape != null && railPos != null) {
      moveCartAlongTrack(cart, clamped, railPos);
    } else {
      cart.move(clamped);
      cart.setVelocity(cart.velocity * 0.95);
    }
    firstLoop = false;
  }
}

/// `followLinkOnRail`.
Vec3 followLinkOnRail(
  Vec3 link,
  Vec3 cart,
  double diffToReduce,
  Vec3 railAxis,
) {
  final dotProduct = railAxis.dot(link);
  if (dotProduct.isNaN || dotProduct == 0 || diffToReduce == 0) return cart;

  final axis = railAxis * -dotProduct.sign;
  final center = cart + link;
  final radius = link.length - diffToReduce;
  final hit = intersectSphere(cart, axis, center, radius);

  if (hit == null) return cart + project(link, axis);
  return hit;
}

/// `VecHelper.project`.
Vec3 project(Vec3 vec, Vec3 ontoVec) {
  if (ontoVec == vec3Zero) return vec3Zero;
  return ontoVec * (vec.dot(ontoVec) / ontoVec.lengthSquared);
}

/// The coupling lengths and stall state of the controllers, as the physics asks for them.
abstract final class MinecartCouplingLookup {
  static double Function(String cartUuid) couplingLength = (_) => 0;
}
