// The cross-*component* kinetic network, without a host: one component's motor
// drives a node of another, and a node of another drives this one's shaft.
//
// What is proved here is the half of the wire-up that can be proved headlessly:
// the owner's propagation reaches a node that lives in another wasm instance
// (`ForeignKineticNode`), and the verdict it computes comes back as the data the
// other component applies. The live half (two real plugin components over the
// host's IPC) is `~/pumpkin-harness/kin-cross.sh`; the measurement that showed the
// failure was `data get block` printing `{Network: {Size: 3}, Speed: 16f}` for
// `create:mechanical_bearing` and nothing for `aeronautics:propeller_bearing`.
//
// See `docs/kinetics-across-plugins.md` for the ownership decision.
import 'package:create/src/kinetics/foreign.dart';
import 'package:create/src/kinetics/geometry.dart';
import 'package:create/src/kinetics/block_defs.dart';
import 'package:create/src/kinetics/node.dart' show KineticNode;
import 'package:create/src/kinetics/settings.dart';
import 'package:create/src/kinetics/wire_def.dart';
import 'package:test/test.dart';

import 'kinetics_test_support.dart';

/// A level that can hold nodes of *two* components: its own block entities plus
/// the ones another component announced (`ForeignKineticNodes`).
final class TwoComponentLevel extends FakeLevel {
  late final ForeignKineticNodes foreign = ForeignKineticNodes(this);

  @override
  KineticNode? nodeAt(KPos pos) => super.nodeAt(pos) ?? foreign.at(pos);

  @override
  bool get hosted => false;

  /// Puts a block of another component in the world and announces its node,
  /// which is what the other component's `create.kinetics` update does.
  ForeignKineticNode announce(
    String plugin,
    String block,
    KPos pos,
    Map<String, String> props, {
    double generatedSpeed = 0,
    double addedStress = 0,
    double addedCapacity = 0,
  }) {
    states[pos] = KState(block, props);
    return foreign.announce(
      plugin,
      pos,
      ForeignNodeValues(
        generatedSpeed: generatedSpeed,
        addedStress: addedStress,
        addedCapacity: addedCapacity,
      ),
    );
  }
}

void main() {
  group('a foreign node joins the network of the component that owns it', () {
    test("a Create motor drives a foreign bearing's node", () {
      final level = TwoComponentLevel();
      level.stress.register('aeronautics:propeller_bearing', impact: 2);
      level.blocks.registerForeign(
        'aeronautics:propeller_bearing',
        WireKineticDef.facingBack(),
        'aeronautics',
      );

      final motor = level.motor(0, 0, 0, 16, facing: Dir.up);
      final shaft = level.shaft(0, 1, 0, axis: KAxis.y);
      // `BearingBlock.hasShaftTowards = face == FACING.getOpposite()`: the
      // bearing sits above the shaft, so its shaft has to be on its *down* face,
      // i.e. `facing=up`.
      final bearing = level.announce(
        'aeronautics',
        'aeronautics:propeller_bearing',
        const KPos(0, 2, 0),
        const {'facing': 'up'},
        addedStress: 2,
      );

      level.tickAll(3);

      expect(bearing.theoreticalSpeed, 16, reason: 'the shaft drives the bearing');
      expect(bearing.speed, 16);
      expect(bearing.network, motor.kpos.packed);
      expect(bearing.source, shaft.kpos);
      // The bearing is a member of the *one* network, with the stress the
      // component that owns the network computed.
      final network = level.networks[motor.kpos.packed]!;
      expect(network.members.containsKey(bearing), isTrue);
      expect(network.sources.containsKey(motor), isTrue);
      expect(bearing.capacity, network.currentCapacity);
      expect(bearing.stress, network.currentStress);

      // And the verdict goes back to the component that owns the block entity.
      final pushed = level.foreign.takePending('aeronautics');
      expect(pushed, hasLength(1));
      expect(pushed.single['pos'], [0, 2, 0]);
      expect(pushed.single['speed'], 16);
      expect(pushed.single['network'], motor.kpos.packed);
      expect((pushed.single['source'] as List).cast<int>(), [0, 1, 0]);
      expect(pushed.single['networkSize'], network.size);
    });

    test('a foreign generator drives a Create shaft', () {
      final level = TwoComponentLevel();
      level.blocks.registerForeign(
        'simulated:steering_wheel',
        WireKineticDef.verticalByFlag(flag: 'on_floor', upWhenSet: false),
        'simulated',
      );
      final shaft = level.shaft(0, 1, 0, axis: KAxis.y);
      // `SteeringWheelBlockEntity`: 16 RPM, 16 su/rpm of capacity.
      final wheel = level.announce(
        'simulated',
        'simulated:steering_wheel',
        const KPos(0, 0, 0),
        const {'on_floor': 'false'},
        generatedSpeed: 16,
        addedCapacity: 16,
      );

      level.tickAll(3);

      expect(wheel.theoreticalSpeed, 16, reason: 'the wheel is the source');
      expect(shaft.theoreticalSpeed, 16, reason: 'the shaft is driven by it');
      expect(shaft.source, wheel.kpos);
      expect(shaft.network, wheel.kpos.packed);
      expect(
        level.networks[wheel.kpos.packed]!.sources.containsKey(wheel),
        isTrue,
        reason: 'a generator of another component carries the network',
      );
      final pushed = level.foreign.takePending('simulated');
      expect(pushed.single['speed'], 16);
      expect(pushed.single['overStressed'], isFalse);
    });

    test('a foreign block without a registered rule never connects', () {
      final level = TwoComponentLevel();
      level.motor(0, 0, 0, 16, facing: Dir.up);
      level.shaft(0, 1, 0, axis: KAxis.y);
      // The component never registered a rule for its block: the propagation must
      // not guess one (`defFor` is null), so no edge exists and no speed moves.
      final block = level.announce(
        'aeronautics',
        'aeronautics:propeller_bearing',
        const KPos(0, 2, 0),
        const {'facing': 'up'},
      );

      level.tickAll(3);

      expect(block.theoreticalSpeed, 0);
      expect(block.hasNetwork, isFalse);
    });

    test('a foreign node that is removed leaves the network', () {
      final level = TwoComponentLevel();
      level.stress.register('simulated:swivel_bearing', impact: 4);
      level.blocks.registerForeign(
        'simulated:swivel_bearing',
        WireKineticDef.facingBackUnlessFlag(flag: 'assembled'),
        'simulated',
      );
      level.motor(0, 0, 0, 16, facing: Dir.up);
      final shaft = level.shaft(0, 1, 0, axis: KAxis.y);
      final bearing = level.announce(
        'simulated',
        'simulated:swivel_bearing',
        const KPos(0, 2, 0),
        const {'facing': 'up', 'assembled': 'false'},
        addedStress: 4,
      );
      level.tickAll(3);
      final network = level.networks[shaft.kpos.packed == 0 ? 1 : 0];
      expect(bearing.theoreticalSpeed, 16);

      level.foreign.detach(bearing.kpos);
      level.tickAll(2);

      expect(level.foreign.existing(bearing.kpos), isNull);
      expect(level.foreign.count, 0);
      expect(shaft.theoreticalSpeed, 16, reason: 'the rest of the line keeps turning');
      expect(network?.members.containsKey(bearing), isFalse);
    });
  });

  group('the rule of a block crosses as data (one description, both sides)', () {
    // The addons' defs *are* wire defs, so the owner rebuilds exactly the rule the
    // component registered locally. These cases pin the wire vocabulary against
    // the Create def classes the rules were written from, so a change to one side
    // without the other fails here first.
    const states = <KState>[
      KState('b', {'facing': 'up', 'axis': 'y', 'on_floor': 'false'}),
      KState('b', {'facing': 'down', 'axis': 'y', 'on_floor': 'true'}),
      KState('b', {'facing': 'north', 'axis': 'x', 'on_floor': 'false'}),
      KState('b', {'facing': 'east', 'axis': 'z', 'on_floor': 'true'}),
    ];

    void agree(KineticBlockDef expected, WireKineticDef actual, {String? why}) {
      for (final state in states) {
        expect(
          actual.rotationAxis(state),
          expected.rotationAxis(state),
          reason: 'rotationAxis for $state${why == null ? '' : ' ($why)'}',
        );
        for (final face in Dir.values) {
          expect(
            actual.hasShaftTowards(state, face),
            expected.hasShaftTowards(state, face),
            reason: 'hasShaftTowards($face) for $state${why == null ? '' : ' ($why)'}',
          );
        }
      }
    }

    test('facingBack is FacingBlockDef(shaftAtFront: false)', () {
      agree(const FacingBlockDef(shaftAtFront: false), WireKineticDef.facingBack());
    });

    test('facingFront is FacingBlockDef(shaftAtFront: true)', () {
      agree(const FacingBlockDef(), WireKineticDef.facingFront());
    });

    test('axis is AxisBlockDef()', () {
      agree(const AxisBlockDef(), WireKineticDef.axis());
    });

    test('verticalByFlag is VerticalShaftDef', () {
      agree(
        const VerticalShaftDef(property: 'on_floor', shaftUpWhenSet: false),
        WireKineticDef.verticalByFlag(flag: 'on_floor', upWhenSet: false),
      );
      agree(
        const VerticalShaftDef(property: 'on_floor', shaftUpWhenSet: true),
        WireKineticDef.verticalByFlag(flag: 'on_floor', upWhenSet: true),
      );
    });

    test('perpendicularToFacing is DirectionalAxisBlockDef', () {
      agree(const DirectionalAxisBlockDef(), WireKineticDef.perpendicularToFacing());
    });

    test('facingBackUnlessFlag is SwivelBearingBlock.hasShaftTowards', () {
      // `SwivelBearingBlock.java:90-94`: the shaft runs along the whole facing
      // axis while ASSEMBLED is false, and out of the back once it is set.
      final def = WireKineticDef.facingBackUnlessFlag(flag: 'assembled');
      for (final facing in Dir.values) {
        for (final assembled in [false, true]) {
          final state = KState('simulated:swivel_bearing', {
            'facing': facing.name,
            'assembled': '$assembled',
          });
          expect(def.rotationAxis(state), facing.axis);
          for (final face in Dir.values) {
            final expected = assembled
                ? face == facing.opposite
                : face.axis == facing.axis;
            expect(
              def.hasShaftTowards(state, face),
              expected,
              reason: 'facing=$facing assembled=$assembled face=$face',
            );
          }
        }
      }
    });

    test('a wire def survives the JSON round trip', () {
      final defs = <WireKineticDef>[
        WireKineticDef.axis(),
        WireKineticDef.facingBack(),
        WireKineticDef.facingFront(),
        WireKineticDef.facingAxis(),
        WireKineticDef.verticalByFlag(flag: 'ceiling', upWhenSet: true),
        WireKineticDef.facingBackUnlessFlag(flag: 'assembled'),
        WireKineticDef.perpendicularToFacing(
          alongFirstProperty: 'axis_along_first_coordinate',
        ),
      ];
      for (final def in defs) {
        final rebuilt = WireKineticDef.fromJson(def.toJson());
        expect(rebuilt, isNotNull, reason: '$def');
        for (final state in states) {
          expect(rebuilt!.rotationAxis(state), def.rotationAxis(state));
          for (final face in Dir.values) {
            expect(rebuilt.hasShaftTowards(state, face), def.hasShaftTowards(state, face));
          }
        }
      }
      // A rule this version does not know is refused rather than approximated.
      expect(WireKineticDef.fromJson(const {'axis': {'kind': 'nope'}, 'shaft': {'kind': 'alongAxis'}}), isNull);
      expect(WireKineticDef.fromJson(const {}), isNull);
      expect(WireKineticDef.fromJson('not a rule'), isNull);
    });

    test('kinetic equivalence follows the flags of the block', () {
      final chain = WireKineticDef.axis(kineticFlags: const {'powered'});
      const a = KState('b', {'axis': 'x', 'powered': 'false'});
      const b = KState('b', {'axis': 'x', 'powered': 'true'});
      const c = KState('b', {'axis': 'z', 'powered': 'false'});
      expect(chain.areStatesKineticallyEquivalent(a, b), isFalse);
      expect(chain.areStatesKineticallyEquivalent(a, c), isFalse);
      expect(chain.areStatesKineticallyEquivalent(a, a), isTrue);
      final plain = WireKineticDef.axis();
      expect(plain.areStatesKineticallyEquivalent(a, b), isTrue);
    });
  });
}