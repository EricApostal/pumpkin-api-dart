import 'package:create/src/common/direction.dart' show Direction;
import 'package:simulated/simulated.dart';
import 'package:test/test.dart';

void main() {
  group('SteeringWheelLogic', () {
    test('turns towards the target and stops there', () {
      final logic = SteeringWheelLogic();
      logic.updateTargetAngle(90, facing: Direction.north, onFloor: true);

      expect(logic.inUse, greaterThan(0));
      expect(logic.generatedSpeedForOutput, isNot(0));

      var ticks = 0;
      while (logic.inUse > 0 && ticks < 1000) {
        logic.tick(facing: Direction.north, onFloor: true);
        ticks++;
      }

      expect(ticks, lessThan(1000));
      expect(logic.angle, closeTo(90, 0.001));
      expect(logic.generatedSpeedForOutput, 0);
    });

    test('clamps the target to the angle limit', () {
      final logic = SteeringWheelLogic()..angleLimit = 45;
      logic.updateTargetAngle(180, facing: Direction.north, onFloor: true);
      expect(logic.targetAngle, 45);
    });

    test('the generated speed sign depends on facing and floor', () {
      double speedFor(Direction facing, bool onFloor) {
        final logic = SteeringWheelLogic();
        logic.updateTargetAngle(90, facing: facing, onFloor: onFloor);
        return logic.generatedSpeedForOutput;
      }

      // A wheel facing north on the floor turns the opposite way from one on
      // the ceiling.
      expect(speedFor(Direction.north, true), isNot(speedFor(Direction.north, false)));
      expect(speedFor(Direction.south, true), speedFor(Direction.north, false));
    });

    test('the analog output reports the steering input on the sides', () {
      final logic = SteeringWheelLogic()
        ..angleLimit = 180
        ..targetAngleToUpdate = 180
        ..angle = 90;

      expect(logic.analogOutput(Direction.north, Direction.north), 0);
      logic.held = true;
      expect(logic.analogOutput(Direction.north, Direction.north), 15);

      final clockwise = logic.analogOutput(Direction.north, Direction.east);
      final counter = logic.analogOutput(Direction.north, Direction.west);
      expect(clockwise, greaterThanOrEqualTo(0));
      expect(counter, lessThanOrEqualTo(0));
    });

    test('a saved state round-trips', () {
      final logic = SteeringWheelLogic()
        ..angle = 42
        ..targetAngle = 90
        ..inUse = 3
        ..generatedSpeed = 16;

      final copy = SteeringWheelLogic()..read(logic.write());
      expect(copy.angle, 42);
      expect(copy.targetAngle, 90);
      expect(copy.inUse, 3);
      expect(copy.generatedSpeed, 16);
    });

    test('steering input is the target relative to the limit', () {
      final logic = SteeringWheelLogic()
        ..angleLimit = 90
        ..targetAngleToUpdate = 45;
      expect(logic.steeringInput, closeTo(0.5, 1e-9));
    });
  });

  group('ThrottleLeverLogic', () {
    test('steps the signal and clamps it', () {
      final logic = ThrottleLeverLogic();
      for (var i = 0; i < 20; i++) {
        logic.changeState();
      }
      expect(logic.state, 15);
      expect(logic.throttle, 1);

      for (var i = 0; i < 20; i++) {
        logic.changeState(back: true);
      }
      expect(logic.state, 0);
      expect(logic.throttle, 0);
    });

    test('inverted flips the output signal', () {
      final logic = ThrottleLeverLogic()
        ..state = 4
        ..inverted = true;
      expect(logic.outputSignal, 11);

      logic.setSignal(10);
      expect(logic.state, 5);
      expect(logic.lastChange, 2);
    });

    test('the neighbour update timer runs down', () {
      final logic = ThrottleLeverLogic()..setSignal(5);
      expect(logic.tick(), isFalse);
      expect(logic.tick(), isTrue);
      expect(logic.tick(), isFalse);
    });

    test('a save round-trips', () {
      final logic = ThrottleLeverLogic()
        ..state = 9
        ..lastChange = 4;
      final data = logic.write();
      final copy = ThrottleLeverLogic()
        ..read(data['State']! as int, data['ChangeTimer']! as int, inverted: false);
      expect(copy.state, 9);
      expect(copy.lastChange, 4);
    });
  });
}
