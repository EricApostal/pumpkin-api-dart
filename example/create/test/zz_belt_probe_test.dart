import 'package:create/src/kinetics/block_defs.dart';
import 'package:create/src/kinetics/geometry.dart';
import 'package:test/test.dart';

import 'kinetics_test_support.dart';

class BeltDef extends KineticBlockDef {
  const BeltDef();
  @override
  KAxis rotationAxis(KState state) {
    if (state['slope'] == 'sideways') return KAxis.y;
    final facing = state.dirOf('facing') ?? Dir.north;
    return facing.clockWise(KAxis.y).axis;
  }

  @override
  bool hasShaftTowards(KState state, Dir face) =>
      face.axis == rotationAxis(state) && (state['part'] ?? 'start') != 'middle';
}

void main() {
  test('probe: belt joins a motor', () {
    final level = FakeLevel();
    level.blocks.register('create:belt', const BeltDef());
    final motor = level.motor(0, 0, 0, 32, facing: Dir.east);
    final belt = level.place(
      KPos(1, 0, 0),
      const KState('create:belt', {
        'facing': 'north',
        'part': 'start',
        'slope': 'horizontal',
      }),
    );
    level.tickAll(3);
    print('motor speed=${motor.speed} belt speed=${belt.speed} net=${belt.network}');
    expect(belt.speed, 32);
  });
}
