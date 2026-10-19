import 'package:create/src/kinetics/geometry.dart';
import 'package:test/test.dart';

import 'kinetics_test_support.dart';

void main() {
  group('gearbox', () {
    test('the opposite side is reversed, the perpendicular sides follow the signs', () {
      final level = FakeLevel();
      level.motor(0, 0, 0, 16, facing: Dir.east); // pushes east into a shaft at x=1
      level.shaft(1, 0, 0);
      level.split('gearbox', 2, 0, 0); // axis y, input from the west
      final out = <Dir, FakeNodeRef>{};
      // shafts around the gearbox
      level.shaft(3, 0, 0); // east, opposite of the input
      level.shaft(2, 0, 1, axis: KAxis.z); // south
      level.shaft(2, 0, -1, axis: KAxis.z); // north
      level.tickAll(4);
      out[Dir.east] = FakeNodeRef(level.nodes[const KPos(3, 0, 0)]!.theoreticalSpeed);
      out[Dir.south] = FakeNodeRef(level.nodes[const KPos(2, 0, 1)]!.theoreticalSpeed);
      out[Dir.north] = FakeNodeRef(level.nodes[const KPos(2, 0, -1)]!.theoreticalSpeed);
      expect(level.nodes[const KPos(2, 0, 0)]!.theoreticalSpeed, 16);
      expect(out[Dir.east]!.speed, -16);
      // west is the source direction (negative x). south is positive: same sign as the source? no -> 1 or -1
      expect(out[Dir.south]!.speed.abs(), 16);
      expect(out[Dir.north]!.speed.abs(), 16);
      expect(out[Dir.south]!.speed, -out[Dir.north]!.speed);
    });
  });

  group('clutch and gearshift', () {
    test('an unpowered clutch passes the rotation, a powered one cuts the far side', () {
      final level = FakeLevel();
      level.motor(0, 0, 0, 16, facing: Dir.east);
      level.shaft(1, 0, 0);
      final clutch = level.split('clutch', 2, 0, 0, axis: KAxis.x);
      level.shaft(3, 0, 0);
      level.tickAll(4);
      expect(level.nodes[const KPos(3, 0, 0)]!.theoreticalSpeed, 16);

      // power it: detach, change the state, reattach (what the block does)
      clutch.detachKinetics();
      clutch.state = clutch.state.toggle('powered');
      level.states[clutch.kpos] = clutch.state;
      clutch.handleAdded();
      level.tickAll(2);
      expect(level.nodes[const KPos(3, 0, 0)]!.theoreticalSpeed, 0);
      expect(clutch.theoreticalSpeed, 16);

      // unpower it again
      clutch.detachKinetics();
      clutch.state = clutch.state.toggle('powered');
      level.states[clutch.kpos] = clutch.state;
      clutch.handleAdded();
      level.tickAll(2);
      expect(level.nodes[const KPos(3, 0, 0)]!.theoreticalSpeed, 16);
    });

    test('a powered gearshift reverses the far side', () {
      final level = FakeLevel();
      level.motor(0, 0, 0, 16, facing: Dir.east);
      level.shaft(1, 0, 0);
      final shift = level.split('gearshift', 2, 0, 0, axis: KAxis.x, powered: true);
      level.shaft(3, 0, 0);
      level.tickAll(4);
      expect(shift.theoreticalSpeed, 16);
      expect(level.nodes[const KPos(3, 0, 0)]!.theoreticalSpeed, -16);
    });
  });
}

class FakeNodeRef {
  final double speed;

  FakeNodeRef(this.speed);
}
