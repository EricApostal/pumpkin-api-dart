// Regression tests for the kinetic-network audit: an overstressed network keeps
// its source (Java validates against the theoretical speed field), and water
// wheels only survive next to wheels that share their axis.
import 'package:create/src/kinetics/geometry.dart';
import 'package:create/src/kinetics/water_wheel_logic.dart';
import 'package:test/test.dart';

import 'kinetics_test_support.dart';

void main() {
  group('source validation', () {
    test('dependents keep their source while the network is overstressed', () {
      final level = FakeLevel();
      level.stress.register('create:machine', impact: 20000);
      final motor = level.motor(0, 0, 0, 16);
      final shaft = level.shaft(1, 0, 0);
      final machine = level.machine(2, 0, 0);
      level.tickAll(3);

      // The network is overstressed: `getSpeed()` is 0, but the theoretical
      // speed still drives the members.
      expect(motor.isOverStressed, isTrue);
      expect(motor.speed, 0);
      expect(motor.theoreticalSpeed, 16);

      // `validateKinetics` compares the protected `speed` field (theoretical),
      // so the members must stay attached through a validation interval.
      level.tickAll(61);
      expect(shaft.hasSource, isTrue);
      expect(shaft.theoreticalSpeed, 16);
      expect(machine.hasSource, isTrue);
      expect(machine.theoreticalSpeed, 16);
    });

    test('a healthy source is kept', () {
      final level = FakeLevel();
      final motor = level.motor(0, 0, 0, 16);
      final shaft = level.shaft(1, 0, 0);
      level.tickAll(70);

      expect(motor.isOverStressed, isFalse);
      expect(shaft.hasSource, isTrue);
      expect(shaft.theoreticalSpeed, 16);
    });
  });

  group('water wheel canSurvive', () {
    KState Function(KPos) world(Map<KPos, KState> m) =>
        (p) => m[p] ?? KState.air;
    const north = KState('create:water_wheel', {'facing': 'north'});

    test('a lone wheel survives', () {
      expect(waterWheelCanSurvive(world({}), KPos.zero, north), isTrue);
    });

    test('wheels touching along their axis survive', () {
      final m = {const KPos(0, 0, 1): north};
      expect(waterWheelCanSurvive(world(m), KPos.zero, north), isTrue);
    });

    test('a wheel beside another on a different axis does not survive', () {
      final m = {const KPos(1, 0, 0): north};
      expect(waterWheelCanSurvive(world(m), KPos.zero, north), isFalse);
    });

    test('a wheel with a different facing does not survive', () {
      final m = {
        const KPos(0, 0, 1): const KState('create:water_wheel', {
          'facing': 'east',
        }),
      };
      expect(waterWheelCanSurvive(world(m), KPos.zero, north), isFalse);
    });
  });
}
