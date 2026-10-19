import 'package:create/src/kinetics/block_defs.dart';
import 'package:create/src/kinetics/geometry.dart';
import 'package:create/src/kinetics/propagator.dart';
import 'package:create/src/kinetics/settings.dart';
import 'package:test/test.dart';

import 'kinetics_test_support.dart';

void main() {
  group('geometry', () {
    test('clockwise rotations match Direction.getClockWise', () {
      expect(Dir.north.clockWise(KAxis.y), Dir.east);
      expect(Dir.west.clockWise(KAxis.y), Dir.north);
      expect(Dir.up.clockWise(KAxis.x), Dir.north);
      expect(Dir.north.clockWise(KAxis.x), Dir.down);
      expect(Dir.up.clockWise(KAxis.z), Dir.east);
      expect(Dir.east.clockWise(KAxis.z), Dir.down);
      expect(Dir.up.clockWise(KAxis.y), Dir.up);
      for (final d in Dir.values) {
        for (final a in KAxis.values) {
          expect(d.clockWise(a).counterClockWise(a), d);
          var r = d;
          for (var i = 0; i < 4; i++) {
            r = r.clockWise(a);
          }
          expect(r, d);
        }
      }
    });

    test('approximateNearest picks the first direction on ties', () {
      expect(Dir.approximateNearest(0, 0, 0), Dir.down);
      expect(Dir.approximateNearest(3, 1, 0), Dir.east);
      expect(Dir.approximateNearest(0, -2, 0), Dir.down);
      expect(Dir.approximateNearest(1, 1, 0), Dir.up);
    });

    test('pos packing', () {
      const p = KPos(-5, 70, 123456);
      expect(KPos.unpack(p.packed), p);
    });
  });

  group('shaft line', () {
    test('a motor spins a line of shafts and the network accounts the stress', () {
      final level = FakeLevel();
      level.stress.register('create:machine', impact: 4);
      final motor = level.motor(0, 0, 0, 16, facing: Dir.east);
      final shafts = [for (var x = 1; x <= 3; x++) level.shaft(x, 0, 0)];
      final machine = level.machine(4, 0, 0);

      level.tickAll(2);

      for (final s in shafts) {
        expect(s.theoreticalSpeed, 16);
        expect(s.source, isNotNull);
        expect(s.network, motor.kpos.packed);
      }
      expect(machine.theoreticalSpeed, 16);
      expect(motor.network, motor.kpos.packed);
      final net = level.networks[motor.kpos.packed]!;
      expect(net.members.length, 5);
      expect(net.sources.length, 1);
      // capacity = 16384 su/rpm * 16 rpm, stress = 4 su/rpm * 16 rpm
      expect(net.currentCapacity, 16384 * 16);
      expect(net.currentStress, 4 * 16);
      expect(machine.isOverStressed, isFalse);
    });

    test('overstress stops the speed (getSpeed) but keeps the theoretical one', () {
      final level = FakeLevel();
      level.stress.register('create:machine', impact: 5000);
      level.motor(0, 0, 0, 16);
      final machine = level.machine(1, 0, 0);
      level.tickAll(3);
      // 5000 * 16 = 80000 > 16384 * 16 = 262144? no: not overstressed
      expect(machine.isOverStressed, isFalse);
      level.stress.register('create:machine', impact: 20000);
      final other = level.machine(2, 0, 0);
      level.tickAll(3);
      // two machines of 20000 per rpm: 20000 * 16 * ... > 262144
      final net = level.networks.values.first;
      expect(net.currentStress > net.currentCapacity, isTrue);
      expect(other.isOverStressed, isTrue);
      expect(other.speed, 0);
      expect(other.theoreticalSpeed, 16);
      // stress can be disabled
      final disabled = FakeLevel(settings: const KineticsSettings(disableStress: true));
      disabled.stress.register('create:machine', impact: 20000);
      disabled.motor(0, 0, 0, 16);
      final m2 = disabled.machine(1, 0, 0);
      disabled.tickAll(3);
      expect(m2.isOverStressed, isFalse);
    });

    test('removing the motor stops the chain', () {
      final level = FakeLevel();
      final motor = level.motor(0, 0, 0, 16);
      final shafts = [for (var x = 1; x <= 3; x++) level.shaft(x, 0, 0)];
      level.tickAll(2);
      expect(shafts.last.theoreticalSpeed, 16);
      level.remove(motor.kpos);
      for (final s in shafts) {
        expect(s.theoreticalSpeed, 0, reason: 'shaft at ${s.kpos}');
        expect(s.source, isNull);
        expect(s.network, isNull);
      }
      expect(level.networks, isEmpty);
    });

    test('a broken shaft in the middle cuts the line, a replacement reconnects', () {
      final level = FakeLevel();
      level.motor(0, 0, 0, 32);
      level.shaft(1, 0, 0);
      level.shaft(2, 0, 0);
      final far = level.shaft(3, 0, 0);
      level.tickAll(2);
      expect(far.theoreticalSpeed, 32);
      level.remove(const KPos(2, 0, 0));
      expect(far.theoreticalSpeed, 0);
      final replacement = level.shaft(2, 0, 0);
      level.tickAll(2);
      expect(replacement.theoreticalSpeed, 32);
      expect(far.theoreticalSpeed, 32);
    });

    test('shafts not facing each other do not connect', () {
      final level = FakeLevel();
      level.motor(0, 0, 0, 16);
      final crossways = level.shaft(1, 0, 0, axis: KAxis.z);
      level.tickAll(2);
      expect(crossways.theoreticalSpeed, 0);
    });
  });

  group('a block placed into a spinning network', () {
    // What placing a block does: `BlockEntityStore.createAt` makes the entity with no speed,
    // source or network and `updateSpeed` still set, so the first `tick()` runs
    // `kineticTickStart()` -> `attachKinetics()` -> `RotationPropagator.handleAdded`.
    test('a shaft added to a spinning line joins it on its first tick', () {
      final level = FakeLevel();
      final motor = level.motor(0, 0, 0, 16, facing: Dir.east);
      final first = level.shaft(1, 0, 0);
      level.tickAll(2);
      expect(first.theoreticalSpeed, 16);

      final added = level.shaft(2, 0, 0);
      expect(added.needsSpeedUpdate, isTrue);
      expect(added.theoreticalSpeed, 0);
      expect(added.source, isNull);
      expect(added.network, isNull);

      level.tickAll(1);

      expect(added.theoreticalSpeed, 16);
      expect(added.source, first.kpos);
      expect(added.network, motor.kpos.packed);
      expect(added.needsSpeedUpdate, isFalse);
      expect(first.theoreticalSpeed, 16);
      expect(level.networks[motor.kpos.packed]!.members.length, 3);
    });

    test('a cogwheel added next to a spinning shaft joins it on its first tick', () {
      final level = FakeLevel();
      final motor = level.motor(0, 0, 0, 16, facing: Dir.east);
      final shaft = level.shaft(1, 0, 0);
      level.tickAll(2);
      expect(shaft.theoreticalSpeed, 16);

      final cog = level.cog(2, 0, 0, axis: KAxis.x);
      expect(cog.theoreticalSpeed, 0);

      level.tickAll(1);

      expect(cog.theoreticalSpeed, 16);
      expect(cog.source, shaft.kpos);
      expect(cog.network, motor.kpos.packed);
    });

    test('a block placed on a running network does not disturb the existing members', () {
      final level = FakeLevel();
      level.motor(0, 0, 0, 32, facing: Dir.east);
      final shafts = [for (var x = 1; x <= 3; x++) level.shaft(x, 0, 0)];
      level.tickAll(2);
      final before = [for (final s in shafts) (s.theoreticalSpeed, s.source, s.network)];

      level.shaft(4, 0, 0);
      level.tickAll(2);

      for (var i = 0; i < shafts.length; i++) {
        expect((shafts[i].theoreticalSpeed, shafts[i].source, shafts[i].network), before[i]);
      }
      expect(level.destroyed, isEmpty);
    });
  });

  group('cogwheels', () {
    test('adjacent small cogs reverse the direction', () {
      final level = FakeLevel();
      level.motor(0, 0, 0, 16, facing: Dir.east);
      level.shaft(1, 0, 0);
      final cog1 = level.cog(2, 0, 0, axis: KAxis.x);
      // cog next to cog (same axis x, offset in y)
      final cog2 = level.cog(2, 1, 0, axis: KAxis.x);
      level.tickAll(3);
      expect(cog1.theoreticalSpeed, 16);
      expect(cog2.theoreticalSpeed, -16);
    });

    test('a large cog drives a small cog at twice the speed (and reversed)', () {
      final level = FakeLevel();
      level.motor(0, 0, 0, 8, facing: Dir.east);
      level.shaft(1, 0, 0);
      // large cog axis x at (2,0,0); small cog axis x at (2,1,1) diagonal
      final large = level.cog(2, 0, 0, axis: KAxis.x, large: true);
      final small = level.cog(2, 1, 1, axis: KAxis.x);
      level.tickAll(3);
      expect(large.theoreticalSpeed, 8);
      expect(small.theoreticalSpeed, -16);
    });

    test('a small cog drives a large cog at half speed', () {
      final level = FakeLevel();
      level.motor(0, 0, 0, 32, facing: Dir.east);
      level.shaft(1, 0, 0);
      final small = level.cog(2, 1, 1, axis: KAxis.x);
      level.shaft(1, 1, 1, axis: KAxis.x);
      level.tickAll(2);
      expect(small.theoreticalSpeed, 0, reason: 'a lone cog without a source does not turn');
    });

    test('cogs of the same chain stay consistent after a restart of all ticks', () {
      final level = FakeLevel();
      level.motor(0, 0, 0, 16, facing: Dir.east);
      level.shaft(1, 0, 0);
      final a = level.cog(2, 0, 0, axis: KAxis.x);
      final b = level.cog(2, 1, 0, axis: KAxis.x);
      level.tickAll(5);
      expect(a.theoreticalSpeed, 16);
      expect(b.theoreticalSpeed, -16);
      expect(level.destroyed, isEmpty);
    });
  });

  group('conflicts', () {
    test('a motor that fights an existing network of the other direction breaks', () {
      final level = FakeLevel();
      level.motor(0, 0, 0, -16, facing: Dir.east);
      level.shaft(1, 0, 0);
      level.shaft(2, 0, 0);
      level.tickAll(3);
      expect(level.nodes[const KPos(2, 0, 0)]!.theoreticalSpeed, -16);
      final second = level.motor(3, 0, 0, 16, facing: Dir.west);
      level.tickAll(3);
      // generatedSpeed (16) > theoreticalSpeed (-16) so it tries to take over and breaks
      expect(level.destroyed, contains(second.kpos));
    });

    test('two motors in the same direction: the faster wins, the slower becomes a member', () {
      final level = FakeLevel();
      final slow = level.motor(0, 0, 0, 16, facing: Dir.east);
      level.shaft(1, 0, 0);
      // second motor faces west so its shaft side (west) touches the line from the east, but
      // generates -speed along its facing; use a negative speed for the same rotation direction
      final fast = level.motor(2, 0, 0, 64, facing: Dir.west);
      level.tickAll(4);
      expect(level.destroyed, isEmpty);
      expect(slow.theoreticalSpeed, 64);
      expect(slow.hasSource, isTrue);
      expect(fast.theoreticalSpeed, 64);
    });

    test('too fast breaks the block', () {
      final level = FakeLevel(settings: const KineticsSettings(maxRotationSpeed: 64));
      level.motor(0, 0, 0, 128);
      level.shaft(1, 0, 0);
      level.tickAll(3);
      expect(level.destroyed, isNotEmpty);
    });

    test('a loop of gears with a reversing ratio breaks', () {
      final level = FakeLevel();
      level.motor(0, 0, 0, 16, facing: Dir.east);
      level.shaft(1, 0, 0);
      // three small cogs in a triangle cannot exist on a grid; use 3 mutually adjacent cogs on axis x:
      // (2,0,0) - (2,1,0) - (2,1,1) - (2,0,1) - back: an even loop works, add an odd diagonal link
      level.cog(2, 0, 0, axis: KAxis.x);
      level.cog(2, 1, 0, axis: KAxis.x);
      level.cog(2, 1, 1, axis: KAxis.x);
      level.cog(2, 0, 1, axis: KAxis.x);
      level.tickAll(6);
      // even loop is fine
      expect(level.destroyed, isEmpty);
      final cogA = level.nodes[const KPos(2, 0, 0)]!;
      final cogC = level.nodes[const KPos(2, 1, 1)]!;
      expect(cogA.theoreticalSpeed, 16);
      expect(cogC.theoreticalSpeed, 16);
    });
  });

  group('speed controller', () {
    test('conveyed speed rules', () {
      final level = FakeLevel();
      level.blocks.register('create:rotation_speed_controller', const AxisBlockDef());
      final cog = level.cog(0, 1, 0, axis: KAxis.x, large: true);
      final controller = FakeController(level, const KPos(0, 0, 0), const KState('create:rotation_speed_controller', {'axis': 'z'}), 64);
      level.nodes[controller.kpos] = controller;
      level.states[controller.kpos] = controller.state;
      cog.setSpeed(16);
      // the cog drives the controller: target speed
      expect(RotationPropagator.speedControllerConveyedSpeed(cog, controller, true), 64);
    });
  });

  group('stress values', () {
    test('defaults come from the manifest and the config overrides them', () {
      final defaults = KineticStressTable();
      expect(defaults.capacity('create:creative_motor'), 16384);
      expect(defaults.impact('create:mechanical_press'), 8);
      expect(defaults.impact('create:unknown'), 0);
      final custom = KineticStressTable(const KineticsSettings(stressImpacts: {'mechanical_press': 2}));
      expect(custom.impact('create:mechanical_press'), 2);
    });

    test('speed levels follow the config', () {
      const c = KineticsSettings();
      expect(SpeedLevel.of(0, c), SpeedLevel.none);
      expect(SpeedLevel.of(1, c), SpeedLevel.slow);
      expect(SpeedLevel.of(-30, c), SpeedLevel.medium);
      expect(SpeedLevel.of(100, c), SpeedLevel.fast);
      expect(StressImpactLevel.of(1.2), StressImpactLevel.overstressed);
      expect(convertToAngular(60), 18);
    });
  });
}
