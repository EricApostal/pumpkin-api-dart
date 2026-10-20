// The mechanical pump as the kinetic network and the wrench see it.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/fluids/pump_logic.dart';
import 'package:create/src/kinetics/geometry.dart';
import 'package:test/test.dart';

import 'kinetics_test_support.dart';

KState _pump(Dir facing) => KState('create:mechanical_pump', {
  'facing': facing.name,
  'waterlogged': 'false',
});

void main() {
  group('pump kinetic definition', () {
    test('it is a small cog with no shaft faces, rotating on its facing axis', () {
      const def = PumpDef();
      final state = _pump(Dir.west);
      expect(def.isSmallCog, isTrue);
      expect(def.rotationAxis(state), KAxis.x);
      for (final face in Dir.values) {
        expect(def.hasShaftTowards(state, face), isFalse);
      }
    });

    test('a cogwheel beside a powered pump drives it', () {
      final level = FakeLevel();
      level.blocks.register(
        'create:mechanical_pump',
        const PumpDef(),
      );
      final motor = level.motor(0, 0, 0, 16, facing: Dir.east);
      final shaft = level.shaft(1, 0, 0);
      final cog = level.cog(2, 0, 0, axis: KAxis.x);
      final pump = level.place(const KPos(2, 0, 1), _pump(Dir.west));

      level.tickAll(3);

      expect(shaft.theoreticalSpeed, 16);
      expect(cog.theoreticalSpeed, 16);
      expect(pump.theoreticalSpeed.abs(), 16);
      expect(pump.source, cog.kpos);
      expect(pump.network, motor.kpos.packed);
    });

    test('a shaft on the pump axis does not connect (no shaft faces)', () {
      final level = FakeLevel();
      level.blocks.register(
        'create:mechanical_pump',
        const PumpDef(),
      );
      level.motor(0, 0, 0, 16, facing: Dir.east);
      final shaft = level.shaft(1, 0, 0);
      final pump = level.place(const KPos(2, 0, 0), _pump(Dir.west));

      level.tickAll(3);

      expect(shaft.theoreticalSpeed, 16);
      expect(pump.theoreticalSpeed, 0);
      expect(pump.source, isNull);
    });
  });

  group('pump wrench', () {
    test('wrenching flips the facing', () {
      const state = BState('create:mechanical_pump', {
        'facing': 'north',
        'waterlogged': 'false',
      });
      final flipped = pumpWrenchState(state);
      expect(flipped.dir('facing'), Direction.south);
      expect(pumpWrenchState(flipped).dir('facing'), Direction.north);
      // The other properties survive the flip.
      expect(flipped['waterlogged'], 'false');
    });

    test('the flip keeps the facing axis, so the pump stays in its network', () {
      const def = PumpDef();
      const state = BState('create:mechanical_pump', {'facing': 'north'});
      final flipped = pumpWrenchState(state);
      expect(
        def.rotationAxis(KState(flipped.key, flipped.props)),
        def.rotationAxis(KState(state.key, state.props)),
      );
    });
  });
}
