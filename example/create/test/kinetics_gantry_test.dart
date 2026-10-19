import 'package:create/src/kinetics/block_defs.dart';
import 'package:create/src/kinetics/gantry/gantry_shaft_logic.dart';
import 'package:create/src/kinetics/geometry.dart';
import 'package:create/src/kinetics/node.dart';
import 'package:create/src/kinetics/placement_helpers.dart';
import 'package:test/test.dart';

KState shaft(String facing, String part, {bool powered = false}) => KState(
  'create:gantry_shaft',
  {'facing': facing, 'part': part, 'powered': '$powered'},
);

void main() {
  group('updateShape', () {
    test('a direction off the facing axis leaves the part alone', () {
      final s = shaft('north', 'single');
      expect(gantryShaftUpdatePart(s, Dir.up, shaft('north', 'single')), s);
    });

    test('a shaft placed towards the facing end starts the line', () {
      expect(
        gantryShaftUpdatePart(
          shaft('north', 'single'),
          Dir.north,
          shaft('north', 'single'),
        )['part'],
        'start',
      );
    });

    test('a shaft placed towards the opposite end ends the line', () {
      expect(
        gantryShaftUpdatePart(
          shaft('north', 'single'),
          Dir.south,
          shaft('north', 'single'),
        )['part'],
        'end',
      );
    });

    test('connecting at both ends turns a shaft into the middle', () {
      expect(
        gantryShaftUpdatePart(
          shaft('north', 'start'),
          Dir.south,
          shaft('north', 'single'),
        )['part'],
        'middle',
      );
      expect(
        gantryShaftUpdatePart(
          shaft('north', 'end'),
          Dir.north,
          shaft('north', 'single'),
        )['part'],
        'middle',
      );
    });

    test('a lost connection turns the middle back into an end', () {
      expect(
        gantryShaftUpdatePart(
          shaft('north', 'middle'),
          Dir.north,
          const KState('minecraft:air'),
        )['part'],
        'end',
      );
      expect(
        gantryShaftUpdatePart(
          shaft('north', 'middle'),
          Dir.south,
          const KState('minecraft:air'),
        )['part'],
        'start',
      );
    });

    test(
      'a lost connection at the outer end turns it back into a single shaft',
      () {
        expect(
          gantryShaftUpdatePart(
            shaft('north', 'start'),
            Dir.north,
            const KState('minecraft:air'),
          )['part'],
          'single',
        );
        expect(
          gantryShaftUpdatePart(
            shaft('north', 'end'),
            Dir.south,
            const KState('minecraft:air'),
          )['part'],
          'single',
        );
      },
    );

    test('a shaft facing the other way does not connect', () {
      expect(
        gantryShaftUpdatePart(
          shaft('north', 'single'),
          Dir.north,
          shaft('south', 'single'),
        )['part'],
        'single',
      );
    });
  });

  group('pinion', () {
    test(
      'movement speed is the linear speed, clamped to half a block per tick',
      () {
        expect(gantryShaftPinionSpeed(shaft('north', 'middle'), 0), 0);
        expect(gantryShaftPinionSpeed(shaft('north', 'middle'), 512), -0.49);
        expect(gantryShaftPinionSpeed(shaft('north', 'middle'), -512), 0.49);
        expect(
          gantryShaftPinionSpeed(shaft('north', 'middle'), 51.2),
          closeTo(-0.1, 1e-9),
        );
        expect(gantryShaftPinionSpeed(const KState('create:shaft'), 512), 0);
      },
    );

    test(
      'a carriage assembles only when the pinion pulls away from the middle',
      () {
        expect(gantryShaftCanAssemble(shaft('north', 'single'), 256), isFalse);
        expect(gantryShaftCanAssemble(shaft('north', 'middle'), 256), isTrue);
        expect(gantryShaftCanAssemble(shaft('north', 'start'), 256), isFalse);
        expect(gantryShaftCanAssemble(shaft('north', 'start'), -256), isTrue);
        expect(gantryShaftCanAssemble(shaft('north', 'end'), 256), isTrue);
        expect(gantryShaftCanAssemble(shaft('north', 'end'), -256), isFalse);
        expect(
          gantryShaftCanAssemble(shaft('north', 'middle', powered: true), 256),
          isFalse,
        );
      },
    );
  });

  group('redstone', () {
    KState Function(KPos) world(Map<KPos, KState> states) =>
        (p) => states[p] ?? const KState('minecraft:air');
    bool loaded(KPos p) => true;

    test('a direct signal powers the shaft', () {
      expect(
        gantryShaftShouldBePowered(
          shaft('north', 'middle'),
          KPos.zero,
          true,
          loaded,
          world({}),
        ),
        isTrue,
      );
    });

    test('a powered shaft of the same facing on the axis powers the shaft', () {
      final states = {
        const KPos(0, 0, -1): shaft('north', 'middle', powered: true),
      };
      expect(
        gantryShaftShouldBePowered(
          shaft('north', 'middle'),
          KPos.zero,
          false,
          loaded,
          world(states),
        ),
        isTrue,
      );
    });

    test('a powered shaft facing the other way does not', () {
      final states = {
        const KPos(0, 0, -1): shaft('south', 'middle', powered: true),
      };
      expect(
        gantryShaftShouldBePowered(
          shaft('north', 'middle'),
          KPos.zero,
          false,
          loaded,
          world(states),
        ),
        isFalse,
      );
    });

    test('an unloaded neighbour is skipped', () {
      final states = {
        const KPos(0, 0, -1): shaft('north', 'middle', powered: true),
      };
      expect(
        gantryShaftShouldBePowered(
          shaft('north', 'middle'),
          KPos.zero,
          false,
          (_) => false,
          world(states),
        ),
        isFalse,
      );
    });
  });

  group('pole placement', () {
    HelperWorld helper(
      Map<KPos, KState> states, {
      Set<KPos> replaceable = const {},
    }) => HelperWorld(
      (p) => states[p] ?? const KState('minecraft:air'),
      (p) => replaceable.contains(p) || !states.containsKey(p),
      KineticBlockRegistry(),
    );

    test('a gantry shaft extends the line and copies facing and powered', () {
      final state = shaft('east', 'start', powered: true);
      final w = helper({KPos.zero: state});
      final offset = gantryShaftPoleOffset(w, KPos.zero, state, (
        0.9,
        0.5,
        0.5,
      ));
      expect(offset.success, isTrue);
      expect(offset.pos, const KPos(1, 0, 0));
      final placed = offset.transform(KState('create:gantry_shaft', const {}));
      expect(placed['facing'], 'east');
      expect(placed['powered'], 'true');
    });

    test('an existing line is skipped', () {
      final state = shaft('east', 'start');
      final w = helper({
        KPos.zero: state,
        const KPos(1, 0, 0): shaft('east', 'middle'),
        const KPos(2, 0, 0): shaft('east', 'end'),
      });
      final offset = gantryShaftPoleOffset(w, KPos.zero, state, (
        0.9,
        0.5,
        0.5,
      ));
      expect(offset.success, isTrue);
      expect(offset.pos, const KPos(3, 0, 0));
    });

    test('a blocked next position fails', () {
      final state = shaft('east', 'start');
      final w = helper({
        KPos.zero: state,
        const KPos(1, 0, 0): const KState('minecraft:stone'),
        const KPos(-1, 0, 0): const KState('minecraft:stone'),
      });
      expect(
        gantryShaftPoleOffset(w, KPos.zero, state, (0.9, 0.5, 0.5)).success,
        isFalse,
      );
    });

    test('the config range stops the line', () {
      final state = shaft('east', 'start');
      bool inLine(KPos p) => p.x > 0 && p.x <= 2;
      final w = HelperWorld(
        (p) => p == KPos.zero
            ? state
            : (inLine(p)
                  ? shaft('east', 'middle')
                  : (p == const KPos(-1, 0, 0)
                        ? const KState('minecraft:stone')
                        : const KState('minecraft:air'))),
        (p) => !inLine(p) && p != const KPos(-1, 0, 0),
        KineticBlockRegistry(),
        placementAssistRange: 2,
      );
      expect(
        gantryShaftPoleOffset(w, KPos.zero, state, (0.9, 0.5, 0.5)).success,
        isFalse,
      );
    });
  });

  group('definition', () {
    test('rotates on the facing axis and has a shaft on that axis', () {
      const def = GantryShaftDef();
      final state = shaft('up', 'middle');
      expect(def.rotationAxis(state), KAxis.y);
      expect(def.hasShaftTowards(state, Dir.up), isTrue);
      expect(def.hasShaftTowards(state, Dir.down), isTrue);
      expect(def.hasShaftTowards(state, Dir.north), isFalse);
    });

    test('the powered state is part of the kinetic state', () {
      const def = GantryShaftDef();
      expect(
        def.areStatesKineticallyEquivalent(
          shaft('north', 'single'),
          shaft('north', 'middle'),
        ),
        isTrue,
      );
      expect(
        def.areStatesKineticallyEquivalent(
          shaft('north', 'single'),
          shaft('north', 'single', powered: true),
        ),
        isFalse,
      );
    });
  });
}
