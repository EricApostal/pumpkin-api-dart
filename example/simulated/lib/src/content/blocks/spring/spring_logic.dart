// The spring: a two-ended block that pulls or pushes the sub-levels its two ends
// are attached to.
//
// Each end finds its partner through the block position saved on the other end.
// Once per physics tick the controller end applies, to both sub-levels:
//
//  * an alignment force that pulls each end towards the middle at the desired
//    separation (Hooke's law, stiffness 145),
//  * an alignment torque that turns the two end normals towards each other
//    (strength 20),
//  * damping along the spring axis, so the pair does not oscillate,
//  * a point damping force against the relative velocity of the two ends.
//
// The maths below is the Java maths. The world is a [SpringPhysicsContext] so it
// runs on the VM in tests.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.blocks.spring.SpringBlockEntity
import 'dart:math' as math;

import 'package:sable/sable.dart' show Vector3d;

/// The size of a spring (`SpringBlock.Size`).
enum SpringSize {
  small(0.5),
  medium(1.0),
  large(8.0);

  const SpringSize(this.scale);

  /// The multiplier of the forces.
  final double scale;

  /// `Size.cycle()`.
  SpringSize get next => values[(index + 1) % values.length];

  static SpringSize byName(String? name) => switch (name) {
    'small' => small,
    'large' => large,
    _ => medium,
  };
}

/// The two ends of a spring, as the physics tick sees them.
final class SpringPhysicsContext {
  /// The centre of this end, in the containing level's coordinates.
  final Vector3d center;

  /// The centre of the partner end.
  final Vector3d partnerCenter;

  /// The world position of this end.
  final Vector3d positionA;

  /// The world position of the partner end.
  final Vector3d positionB;

  /// The velocity of this end.
  final Vector3d velocity;

  /// The velocity of the partner end.
  final Vector3d partnerVelocity;

  /// The normal of this end, in world space (already transformed).
  final Vector3d normalA;

  /// The normal of the partner end, in world space.
  final Vector3d normalB;

  /// The angular velocity of this body.
  final Vector3d angularVelocity;

  /// The angular velocity of the partner.
  final Vector3d partnerAngularVelocity;

  /// The inverse mass of this body.
  final double inverseMass;

  /// The inverse inertia tensor applied to a vector (this body).
  final Vector3d Function(Vector3d) inverseInertia;

  /// The centre of mass of this body.
  final Vector3d centerOfMass;

  /// The size of the spring.
  final SpringSize size;

  /// The physics time step.
  final double timeStep;

  const SpringPhysicsContext({
    required this.center,
    required this.partnerCenter,
    required this.positionA,
    required this.positionB,
    required this.velocity,
    required this.partnerVelocity,
    required this.normalA,
    required this.normalB,
    required this.angularVelocity,
    required this.partnerAngularVelocity,
    required this.inverseMass,
    required this.inverseInertia,
    required this.centerOfMass,
    required this.size,
    required this.timeStep,
  });
}

/// The impulses the spring applies to one of its two ends.
final class SpringImpulse {
  /// The linear impulse.
  final Vector3d linear;

  /// The angular impulse.
  final Vector3d angular;

  const SpringImpulse(this.linear, this.angular);
}

/// The state machine and the force maths of a spring.
final class SpringLogic {
  /// How long the spring may stay over-extended before it snaps.
  static const double timeToSnap = 0.75;

  /// The longest spring, in blocks (`SpringItemHandler.MAX_LENGTH`).
  static const double maxLength = 9;

  /// The shortest spring, in blocks.
  static const double minLength = 1;

  /// The step the length changes by.
  static const double lengthStep = 0.25;

  /// The stiffness of the Hooke force.
  static const double hookesStiffness = 145;

  /// The strength of the alignment torque.
  static const double alignmentTorque = 20;

  /// The damping of the relative velocity.
  static const double pointDamping = 4.5;

  /// The damping of the spin along the spring axis.
  static const double angularDamping = 2;

  /// The separation the spring is set to, in blocks.
  double desiredLength = 0;

  /// How long the spring has been over-extended.
  double snappingTime = 0;

  /// Whether this end is the controller (only the controller applies forces).
  bool isController = false;

  /// Whether the spring is being moved by an assembly (then it must not break).
  bool assembling = false;

  /// Ticks without a partner before the spring breaks.
  int ticksWithoutPartner = 0;

  /// `getSnappingDistance()`: the length at which the spring snaps.
  double get snappingDistance => desiredLength * 4.0 + 2.0;

  /// `tryChangeLengthOrError(delta)`: the new length, or the reason it cannot
  /// change. [currentLength] is the distance between the two ends.
  ///
  /// The reasons are the translation suffixes the Java code sends
  /// (`max_length`, `min_length`, `too_stretched`, `too_compressed`).
  String? tryChangeLength(double delta, {required double currentLength}) {
    if (delta > 0 && desiredLength >= maxLength) return 'max_length';
    if (delta < 0 && desiredLength <= minLength) return 'min_length';

    var newDesiredLength = (desiredLength + delta).clamp(minLength, maxLength);
    newDesiredLength = (newDesiredLength / lengthStep).round() * lengthStep;

    final currentSquared = currentLength * currentLength;
    if (delta < 0 && currentSquared > newDesiredLength * newDesiredLength * 4) {
      return 'too_stretched';
    }
    if (delta > 0 && currentSquared < newDesiredLength * newDesiredLength / 4) {
      return 'too_compressed';
    }

    desiredLength = newDesiredLength;
    return null;
  }

  /// `sable$physicsTick`: the impulses for this end.
  ///
  /// [desiredLength] is the controller's length, which both ends use.
  SpringImpulse? physicsTick(SpringPhysicsContext ctx) {
    if (ctx.positionA.distanceSquared(ctx.positionB) >
        snappingDistance * snappingDistance) {
      snappingTime += ctx.timeStep;
    } else {
      snappingTime = 0;
    }

    // The desired length is measured between the block centres, which are half a
    // block inside each end, so the separation is 0.75 shorter than the value.
    final separation = desiredLength - 0.75;

    final relativeVelocity = Vector3d.copy(ctx.velocity).sub(ctx.partnerVelocity);
    final dampingPointForce = Vector3d.copy(relativeVelocity)..mul(-pointDamping);

    // Alignment torque: turn the two normals towards each other.
    final negatedNormalB = Vector3d.copy(ctx.normalB)..negate();
    final torque = ctx.normalA
        .crossInto(negatedNormalB, Vector3d())
      ..mul(alignmentTorque)
      ..mul(ctx.timeStep);

    // Alignment force: both ends want the middle at half the separation.
    final mediumNormal = Vector3d.copy(ctx.normalA).lerp(ctx.normalB, 0.5);
    final middle = Vector3d.copy(ctx.positionA).lerp(ctx.positionB, 0.5);
    final desireA = Vector3d.copy(middle)
      ..fma(-separation / 2.0, mediumNormal);
    final alignmentForce = desireA
      ..sub(ctx.positionA);
    final hookesPointForce = Vector3d.copy(alignmentForce)..mul(hookesStiffness);

    // Spin damping along the spring axis.
    final relativeAngular = Vector3d.copy(ctx.angularVelocity).sub(ctx.partnerAngularVelocity);
    final dampingTorque = Vector3d();
    if (mediumNormal.lengthSquared > 0) {
      mediumNormal.normalize();
      final dot = mediumNormal.dot(relativeAngular);
      final along = Vector3d.copy(mediumNormal)..mul(dot);
      dampingTorque.fma(-angularDamping, along);
    }

    final scale = ctx.size.scale;
    hookesPointForce.mul(scale);
    torque.mul(scale);
    dampingTorque.mul(scale);
    dampingPointForce.mul(scale);

    final (force, angular) = _localDamping(
      ctx,
      Vector3d.copy(ctx.center),
      dampingPointForce,
      dampingTorque,
      ctx.velocity,
      ctx.angularVelocity,
    );

    // The Hooke impulse is applied at the end, in world space.
    final hookeImpulse = Vector3d.copy(hookesPointForce)..mul(ctx.timeStep);
    final linear = Vector3d.copy(force)..add(hookeImpulse);
    final angularOut = Vector3d.copy(angular)..add(torque);

    return SpringImpulse(linear, angularOut);
  }

  /// `applyLocalDamping`: the damping impulse, clamped so it never reverses the
  /// velocity it damps.
  (Vector3d, Vector3d) _localDamping(
    SpringPhysicsContext ctx,
    Vector3d worldSpringPos,
    Vector3d dampingPointForce,
    Vector3d dampingTorque,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
  ) {
    final angular = Vector3d.copy(dampingTorque);
    angular.add(
      Vector3d.copy(worldSpringPos).sub(ctx.centerOfMass).crossInto(dampingPointForce, Vector3d()),
    );
    final linear = Vector3d.copy(dampingPointForce);

    final expectedLinear = Vector3d.copy(linear)
      ..mul(ctx.inverseMass)
      ..mul(ctx.timeStep);
    final linearScale = _clampingFactor(linearVelocity, expectedLinear);

    final expectedAngular = ctx.inverseInertia(Vector3d.copy(angular))..mul(ctx.timeStep);
    final angularScale = _clampingFactor(angularVelocity, expectedAngular);

    linear.mul(linearScale * ctx.timeStep);
    angular.mul(angularScale * ctx.timeStep);
    return (linear, angular);
  }

  /// `getClampingFactor(currentVelocity, expectedVelocityChange)`.
  static double _clampingFactor(Vector3d currentVelocity, Vector3d expectedVelocityChange) {
    final k = -currentVelocity.dot(expectedVelocityChange);
    final v = currentVelocity.lengthSquared;
    // Never apply friction that speeds the body up.
    if (k < 0) return 0;
    // The change is ten times smaller than the velocity: no clamping needed.
    if (10 * k < v) return 1;
    // Tiny values: scale linearly to avoid a numerical explosion.
    if (v < 1e-10) return v / (k + 1e-10);
    return v * (1 - math.exp(-k / v)) / k;
  }

  /// `write()`.
  Map<String, Object?> write() => {
    'Controller': isController,
    'DesiredLength': desiredLength,
  };

  /// `read()`.
  void read({required bool isController, required double desiredLength}) {
    this.isController = isController;
    this.desiredLength = desiredLength;
  }
}
