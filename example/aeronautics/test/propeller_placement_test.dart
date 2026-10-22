// The placement of the propeller family: the host rules the blocks register, and the Java
// `getStateForPlacement` they have to reproduce.
//
// Pure: no host bindings, so `dart test` runs it on the VM.
//
// Java (`create-aeronautics-bundled` 26.3-1.3.2):
//   content/blocks/propeller/small/BasePropellerBlock.java:44-62
//     `getStateForPlacement`: `getPreferredFacing`, else `getClickedFace().getOpposite()`,
//     then `sneaking ? preferred : preferred.getOpposite()`
//   content/blocks/propeller/small/smart_propeller/SmartPropellerBlock.java:57-70
//     `HorizontalAxisKineticBlock.getStateForPlacement` then a swap of `HORIZONTAL_AXIS`, and
//     `CEILING = getClickedFace() == DOWN`
// The `java=` column of `~/pumpkin-harness/orient/java-reference.txt` is what a real NeoForge
// server set for each of these geometries.
import 'package:aeronautics/src/propeller/placement.dart';
import 'package:create/src/kinetics/geometry.dart' show Dir, KAxis, KPos, KState;
import 'package:create/src/kinetics/node.dart' show KineticBlockRegistry;
import 'package:create/src/kinetics/placement.dart'
    show PlacementContext, horizontalDirection, nearestLookingDirection;
import 'package:pumpkin_api/pumpkin_api_core.dart'
    show PlacementSourceKind, ShaftKind;
import 'package:test/test.dart';

/// A placement context with nothing around the placed block.
PlacementContext contextAt(
  KPos pos, {
  required Dir clickedFace,
  double yaw = 0,
  double pitch = 0,
  bool sneaking = false,
}) => PlacementContext(
  pos: pos,
  clickedFace: clickedFace,
  nearestLooking: nearestLookingDirection(yaw, pitch),
  horizontal: horizontalDirection(yaw),
  sneaking: sneaking,
  stateAt: (_) => const KState('minecraft:air'),
  blocks: KineticBlockRegistry(),
);

void main() {
  const pos = KPos(5, 100, 5);

  group('the small propellers', () {
    test('register `BasePropellerBlock.getStateForPlacement` as four rules', () {
      expect(propellerPlacementRules, hasLength(4));
      final [shaft, shaftSneaking, click, clickSneaking] =
          propellerPlacementRules;

      // `preferred.getOpposite()`, only when a shaft decided and the player does not sneak.
      expect(shaft.property, 'facing');
      expect(shaft.source, PlacementSourceKind.neighbourShaft);
      expect(shaft.opposite, isTrue);
      expect(shaft.whenSneaking, isFalse);
      expect(shaft.shafts, isNotEmpty);
      for (final neighbour in shaft.shafts) {
        expect(
          neighbour.kind,
          anyOf(ShaftKind.axis, ShaftKind.facing, ShaftKind.facingOpposite),
        );
      }

      // `preferred`, when a shaft decided and the player sneaks.
      expect(shaftSneaking.source, PlacementSourceKind.neighbourShaft);
      expect(shaftSneaking.opposite, isFalse);
      expect(shaftSneaking.whenSneaking, isTrue);

      // No shaft: `getClickedFace().getOpposite()` and then the sneaking term, which cancels
      // the opposite — so the clicked face itself.
      expect(click.source, PlacementSourceKind.clickedFace);
      expect(click.opposite, isFalse);
      expect(click.whenSneaking, isFalse);

      expect(clickSneaking.source, PlacementSourceKind.clickedFace);
      expect(clickSneaking.opposite, isTrue);
      expect(clickSneaking.whenSneaking, isTrue);
    });

    test('the rules give what `getStateForPlacement` gives', () {
      bool noShaft(KPos _, Dir __) => false;
      for (final clickedFace in Dir.values) {
        for (final sneaking in [false, true]) {
          expect(
            propellerFacingFromRules(
              pos,
              clickedFace: clickedFace,
              sneaking: sneaking,
              shaftTowards: noShaft,
            ),
            propellerFacingForPlacement(
              clickedFace: clickedFace,
              sneaking: sneaking,
              hasPlayer: true,
              preferred: null,
            ),
            reason: 'clicked $clickedFace, sneaking $sneaking',
          );
        }
      }

      // One shaft on each side, and a shaft pair on the same axis (which still decides).
      for (final side in Dir.values) {
        bool oneShaft(KPos _, Dir face) => face == side;
        for (final sneaking in [false, true]) {
          for (final clickedFace in Dir.values) {
            expect(
              propellerFacingFromRules(
                pos,
                clickedFace: clickedFace,
                sneaking: sneaking,
                shaftTowards: oneShaft,
              ),
              propellerFacingForPlacement(
                clickedFace: clickedFace,
                sneaking: sneaking,
                hasPlayer: true,
                preferred: side,
              ),
              reason: 'shaft towards $side, clicked $clickedFace, sneaking $sneaking',
            );
          }
        }
      }

      // Two shafts on different axes: `getPreferredFacing` gives up, the click decides.
      bool crossed(KPos _, Dir face) => face == Dir.north || face == Dir.east;
      for (final sneaking in [false, true]) {
        expect(
          propellerFacingFromRules(
            pos,
            clickedFace: Dir.up,
            sneaking: sneaking,
            shaftTowards: crossed,
          ),
          propellerFacingForPlacement(
            clickedFace: Dir.up,
            sneaking: sneaking,
            hasPlayer: true,
            preferred: null,
          ),
        );
      }
    });

    test('the measured geometries match the Java reference', () {
      // g0..g3 clicked the top face of the block below, looking level: `facing=up` for every
      // yaw. The look at yaw 180 is north, so a look-based fallback would have given `south` —
      // the value Pumpkin used to set.
      for (final yaw in [0.0, 90.0, 180.0, 270.0]) {
        final ctx = contextAt(pos, clickedFace: Dir.up, yaw: yaw);
        expect(
          propellerFacingFromRules(
            ctx.pos,
            clickedFace: ctx.clickedFace,
            sneaking: false,
            shaftTowards: (_, __) => false,
          ),
          Dir.up,
          reason: 'g0-g3 at yaw $yaw',
        );
      }
      expect(
        nearestLookingDirection(180, 0),
        Dir.north,
        reason: 'the look-based fallback is what produced facing=south here',
      );

      // g4 clicked a south face; g5 the top face looking straight down; g6 a ceiling underside.
      expect(
        propellerFacingFromRules(
          pos,
          clickedFace: Dir.south,
          sneaking: false,
          shaftTowards: (_, __) => false,
        ),
        Dir.south,
        reason: 'g4',
      );
      expect(
        propellerFacingFromRules(
          pos,
          clickedFace: Dir.up,
          sneaking: false,
          shaftTowards: (_, __) => false,
        ),
        Dir.up,
        reason: 'g5',
      );
      expect(
        propellerFacingFromRules(
          pos,
          clickedFace: Dir.down,
          sneaking: false,
          shaftTowards: (_, __) => false,
        ),
        Dir.down,
        reason: 'g6',
      );
    });
  });

  group('the smart propeller', () {
    test('the hinge axis is the swapped horizontal axis of the look', () {
      // java-reference: yaw 0 -> axis=z, 90 -> x, 180 -> z, 270 -> x.
      for (final (yaw, axis) in [
        (0.0, KAxis.z),
        (90.0, KAxis.x),
        (180.0, KAxis.z),
        (270.0, KAxis.x),
      ]) {
        final ctx = contextAt(pos, clickedFace: Dir.up, yaw: yaw);
        expect(
          smartPropellerHorizontalAxis(ctx),
          axis,
          reason: 'yaw $yaw',
        );
      }
    });

    test('`ceiling` is a click on the underside, everything else keeps the defaults', () {
      const placed = KState('aeronautics:smart_propeller', {
        'horizontal_axis': 'x',
        'reversed': 'true',
        'ceiling': 'false',
      });
      final top = smartPropellerPlacement(
        contextAt(pos, clickedFace: Dir.up),
        placed,
      );
      expect(top['horizontal_axis'], 'z');
      expect(top.flag('ceiling'), isFalse);
      expect(top.flag('reversed'), isFalse, reason: 'the default state is not reversed');

      final underside = smartPropellerPlacement(
        contextAt(pos, clickedFace: Dir.down, yaw: 90),
        placed,
      );
      expect(underside['horizontal_axis'], 'x');
      expect(underside.flag('ceiling'), isTrue);
    });
  });
}
