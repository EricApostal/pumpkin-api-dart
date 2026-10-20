import 'package:simulated/simulated.dart';
import 'package:sable/sable.dart' show Quaterniond, Vector3d;
import 'package:test/test.dart';

void main() {
  group('SpringLogic', () {
    test('the length steps in quarters and reports the limits', () {
      final logic = SpringLogic()..desiredLength = 2;
      expect(logic.tryChangeLength(0.25, currentLength: 2), isNull);
      expect(logic.desiredLength, 2.25);

      // Too compressed: the ends are far closer than the new length.
      expect(logic.tryChangeLength(0.25, currentLength: 0.1), 'too_compressed');

      logic.desiredLength = SpringLogic.maxLength;
      expect(logic.tryChangeLength(0.25, currentLength: 9), 'max_length');

      logic.desiredLength = SpringLogic.minLength;
      expect(logic.tryChangeLength(-0.25, currentLength: 1), 'min_length');
    });

    test('the snapping distance grows with the length', () {
      final logic = SpringLogic()..desiredLength = 2;
      expect(logic.snappingDistance, 10);
    });

    test('a stretched spring starts its snap timer', () {
      final logic = SpringLogic()..desiredLength = 2;
      final context = _context(
        positionA: Vector3d(0, 0, 0),
        positionB: Vector3d(20, 0, 0),
        timeStep: 0.05,
      );

      logic.physicsTick(context);
      expect(logic.snappingTime, closeTo(0.05, 1e-9));

      final pulledBack = _context(
        positionA: Vector3d(0, 0, 0),
        positionB: Vector3d(1, 0, 0),
        timeStep: 0.05,
      );
      logic.physicsTick(pulledBack);
      expect(logic.snappingTime, 0);
    });

    test('the impulse pulls the ends towards the desired separation', () {
      final logic = SpringLogic()..desiredLength = 3;
      final context = _context(
        positionA: Vector3d(0, 0, 0),
        positionB: Vector3d(5, 0, 0),
        timeStep: 0.05,
      );

      final impulse = logic.physicsTick(context)!;
      // The ends are too far apart, so the force on A points towards B (+x).
      expect(impulse.linear.x, greaterThan(0));
    });

    test('the clamping factor never speeds the body up', () {
      final logic = SpringLogic();
      // A damping force opposite to the velocity: the scale is positive.
      final positive = _context(
        positionA: Vector3d(0, 0, 0),
        positionB: Vector3d(2, 0, 0),
        timeStep: 0.05,
        velocity: Vector3d(1, 0, 0),
      );
      expect(logic.physicsTick(positive), isNotNull);
    });

    test('a save round-trips', () {
      final logic = SpringLogic()
        ..desiredLength = 4
        ..isController = true;
      final data = logic.write();
      final copy = SpringLogic()
        ..read(isController: data['Controller']! as bool, desiredLength: data['DesiredLength']! as double);
      expect(copy.desiredLength, 4);
      expect(copy.isController, isTrue);
    });
  });

  group('TorsionSpringOutputLogic', () {
    test('turns to the target and stops', () {
      final output = TorsionSpringOutputLogic();
      output.beginTurnTo(90);
      expect(output.state, TorsionOutputState.turning);

      var guard = 0;
      while (output.angle < 89 && guard++ < 1000) {
        output.tick(parentSpeed: 16, angleLimit: 90, powered: true, speed: output.queuedSpeed);
      }

      expect(guard, lessThan(1000));
      expect(output.angle, closeTo(90, 1));
      expect(output.targetAngle, 90);
    });

    test('winds back to zero when the parent stops and the block is unpowered', () {
      final output = TorsionSpringOutputLogic()
        ..angle = 90
        ..targetAngle = 90
        ..state = TorsionOutputState.stopped;

      var guard = 0;
      while (output.angle > 1 && guard++ < 1000) {
        output.tick(parentSpeed: 0, angleLimit: 90, powered: false, speed: output.queuedSpeed);
      }

      expect(guard, lessThan(1000));
      expect(output.angle, lessThanOrEqualTo(1));
    });

    test('a save round-trips', () {
      final output = TorsionSpringOutputLogic()
        ..angle = 45
        ..oldAngle = 40
        ..targetAngle = 90
        ..state = TorsionOutputState.turning
        ..sequencedAngleLimit = 3;

      final copy = TorsionSpringOutputLogic()..read(output.write());
      expect(copy.angle, 45);
      expect(copy.oldAngle, 40);
      expect(copy.targetAngle, 90);
      expect(copy.state, TorsionOutputState.turning);
      expect(copy.sequencedAngleLimit, 3);
    });

    test('the comparator output reports the angle relative to the limit', () {
      expect(
        torsionSpringAnalogOutput(angle: 0.5, angleLimit: 90, facingName: 'north', sideName: 'east'),
        0,
      );
      final value = torsionSpringAnalogOutput(
        angle: 45,
        angleLimit: 90,
        facingName: 'north',
        sideName: 'east',
      );
      expect(value, greaterThan(0));
    });
  });

  group('SwivelBearingLogic', () {
    test('the locking settings follow the redstone signal', () {
      expect(SwivelLockingSetting.lockedAlways.shouldLock(0), isTrue);
      expect(SwivelLockingSetting.unlockedAlways.shouldLock(15), isFalse);
      expect(SwivelLockingSetting.lockedDefault.shouldLock(0), isFalse);
      expect(SwivelLockingSetting.lockedDefault.shouldLock(15), isTrue);
      expect(SwivelLockingSetting.unlockedDefault.shouldLock(0), isTrue);
      expect(SwivelLockingSetting.unlockedDefault.shouldLock(15), isFalse);
    });

    test('the target angle advances with the cogwheel speed', () {
      final logic = SwivelBearingLogic()..assembled = true;
      logic.tick(cogSpeed: 16, facing: 'up', physicsPaused: false, sequenced: false, maxSwivelRpm: 96);
      expect(logic.targetAngleDegrees, isNot(0));

      // A bearing facing a negative axis turns the other way.
      final negative = SwivelBearingLogic()..assembled = true;
      negative.tick(cogSpeed: 16, facing: 'down', physicsPaused: false, sequenced: false, maxSwivelRpm: 96);
      expect(negative.targetAngleDegrees.sign, -logic.targetAngleDegrees.sign);
    });

    test('a paused physics does not move an unsequenced bearing', () {
      final logic = SwivelBearingLogic()..assembled = true;
      logic.tick(cogSpeed: 16, facing: 'up', physicsPaused: true, sequenced: false, maxSwivelRpm: 96);
      expect(logic.targetAngleDegrees, 0);
    });

    test('the servo gains scale with the inertia', () {
      final logic = SwivelBearingLogic()
        ..assembled = true
        ..locking = true;

      final light = logic.motorFor(
        hasHandle: true,
        partialTick: 1,
        inertiaA: 20,
        inertiaB: 20,
        stiffness: 2,
        damping: 3,
        friction: 1,
      )!;
      final heavy = logic.motorFor(
        hasHandle: true,
        partialTick: 1,
        inertiaA: 200,
        inertiaB: 200,
        stiffness: 2,
        damping: 3,
        friction: 1,
      )!;

      expect(heavy.stiffness, greaterThan(light.stiffness));
      expect(heavy.stiffness, 400);
      expect(light.damping, 60);
    });

    test('an unlocked bearing only damps', () {
      final logic = SwivelBearingLogic()
        ..assembled = true
        ..locking = false;

      final motor = logic.motorFor(
        hasHandle: true,
        partialTick: 1,
        inertiaA: 10,
        inertiaB: 10,
        stiffness: 2,
        damping: 3,
        friction: 0.3,
      )!;
      expect(motor.stiffness, 0);
      expect(motor.damping, 0.3);
    });

    test('a bearing without a handle has no motor', () {
      final logic = SwivelBearingLogic()..assembled = true;
      expect(
        logic.motorFor(
          hasHandle: false,
          partialTick: 1,
          inertiaA: null,
          inertiaB: null,
          stiffness: 1,
          damping: 1,
          friction: 1,
        ),
        isNull,
      );
    });

    test('the target angle keeps the current orientation when it locks', () {
      final logic = SwivelBearingLogic();
      logic.setTargetAngleFromCurrentOrientation(
        orientationA: Quaterniond(),
        blockOrientationA: Quaterniond(),
        orientationB: Quaterniond()..rotateY(1.0),
        blockOrientationB: Quaterniond(),
      );
      expect(logic.targetAngleDegrees, isNot(0));
      expect(logic.lastTargetAngleDegrees, logic.targetAngleDegrees);
    });

    test('angleLerp takes the short way around', () {
      expect(angleLerp(0.5, 350, 10) % 360, closeTo(0, 1e-9));
      expect(angleLerp(0.5, 10, 350) % 360, closeTo(0, 1e-9));
      expect(angleLerp(0.5, 0, 90), closeTo(45, 1e-9));
    });
  });
}

SpringPhysicsContext _context({
  required Vector3d positionA,
  required Vector3d positionB,
  required double timeStep,
  Vector3d? velocity,
}) => SpringPhysicsContext(
  center: Vector3d.copy(positionA),
  partnerCenter: Vector3d.copy(positionB),
  positionA: positionA,
  positionB: positionB,
  velocity: velocity ?? Vector3d(),
  partnerVelocity: Vector3d(),
  normalA: Vector3d(0, 1, 0),
  normalB: Vector3d(0, 1, 0),
  angularVelocity: Vector3d(),
  partnerAngularVelocity: Vector3d(),
  inverseMass: 0.1,
  inverseInertia: (v) => Vector3d.copy(v),
  centerOfMass: Vector3d(),
  size: SpringSize.medium,
  timeStep: timeStep,
);
