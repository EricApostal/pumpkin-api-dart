// Placement of blocks against a bearing, and what a right click on a bearing does.
//
// Pure: no host bindings. The rules themselves live in
// `lib/src/contraptions/bearing/bearing_placement.dart` and are read back from the source so the
// registered bearings cannot drift from them.
//
// Java sources (branch `port/26.3`, `src/main/java/com/simibubi/create/`):
//   content/kinetics/base/DirectionalKineticBlock.java:49-58   `getStateForPlacement`, `FACING`
//   content/contraptions/bearing/BearingBlock.java:22-25       `hasShaftTowards` (opposite `FACING`)
//   content/contraptions/bearing/MechanicalBearingBlock.java:19-37
//   content/contraptions/bearing/WindmillBearingBlock.java:23-41
//   content/contraptions/bearing/ClockworkBearingBlock.java:24-42  `useItemOn`
import 'dart:io';

import 'package:create/src/common/direction.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/contraptions/bearing/bearing_placement.dart';
import 'package:create/src/kinetics/block_data.dart';
import 'package:create/src/kinetics/block_defs.dart';
import 'package:create/src/kinetics/geometry.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart'
    show PlacementSourceKind, ShaftKind;
import 'package:test/test.dart';

void main() {
  group('bearing end-face placement', () {
    test('a click on any face places next to the bearing, never inside it', () {
      const bearing = (4, 64, -3);
      for (final face in Direction.values) {
        final placed = bearingPlacementPos(bearing, face);
        expect(
          placed,
          bearing.relative(face),
          reason: 'a bearing is not replaceable, so the block goes on the clicked face',
        );
        expect(placed, isNot(bearing));
      }
    });

    test('the shaft is on the back, the end faces the other way', () {
      // `BearingBlock.hasShaftTowards(face)`: `face == FACING.getOpposite()`. The shaft leaves
      // through the back of the bearing, so the end the contraption sits on is the `facing`
      // side. Clicking that end is what the user could not do.
      for (final facing in Direction.values) {
        final end = facing.opposite;
        expect(bearingHasShaftTowards(facing, end), isTrue);
        expect(bearingHasShaftTowards(facing, facing), isFalse);
        // Clicking the end face places the held block on that side.
        expect(bearingPlacementPos((0, 0, 0), end), (0, 0, 0).relative(end));
      }
    });

    test('the registered rules are `getStateForPlacement` in order', () {
      expect(bearingPlacementRules, hasLength(3));
      final [shaft, look, sneaking] = bearingPlacementRules;
      // `preferred.getOpposite()` when there is a shaft and the player does not sneak.
      expect(shaft.source, PlacementSourceKind.neighbourShaft);
      expect(shaft.property, 'facing');
      expect(shaft.opposite, isTrue);
      expect(shaft.whenSneaking, isFalse);
      expect(shaft.shafts, bearingShaftNeighbours);
      expect(shaft.shafts.map((s) => s.tag), [
        shaftTag,
        facingShaftTag,
        reverseFacingShaftTag,
      ]);
      expect(shaft.shafts.first.property, 'axis');
      expect(shaft.shafts.first.kind, ShaftKind.axis);
      // No shaft, not sneaking: `nearest.getOpposite()`, the bearing faces the player.
      expect(look.source, PlacementSourceKind.lookingDirection);
      expect(look.opposite, isTrue);
      expect(look.whenSneaking, isFalse);
      // Sneaking: `nearest`, whatever the neighbours are.
      expect(sneaking.source, PlacementSourceKind.lookingDirection);
      expect(sneaking.opposite, isFalse);
      expect(sneaking.whenSneaking, isTrue);
    });

    test(
      'a neighbouring shaft decides the facing, the look is the fallback',
      () {
        const pos = (0, 0, 0);
        // A shaft to the east, its shaft end pointing west into the bearing.
        final preferred = bearingPreferredFacing(
          pos,
          (neighbour, side) => side == Direction.east,
        );
        expect(preferred, Direction.east);
        expect(
          bearingFacingForPlacement(
            nearestLooking: Direction.north,
            sneaking: false,
            hasPlayer: true,
            preferred: preferred,
          ),
          Direction.west,
          reason: 'preferred.getOpposite()',
        );
        // Two shafts on different axes: Java gives up and uses the look.
        expect(
          bearingPreferredFacing(
            pos,
            (neighbour, side) => side == Direction.east || side == Direction.up,
          ),
          isNull,
        );
        // Two shafts on one axis: the axis decides, Java keeps the last side in
        // `Iterate.directions` (down, up, north, south, west, east).
        expect(
          bearingPreferredFacing(
            pos,
            (neighbour, side) =>
                side == Direction.east || side == Direction.west,
          ),
          Direction.east,
        );
        // No shaft: the look decides, turned around; sneaking keeps it.
        expect(
          bearingFacingForPlacement(
            nearestLooking: Direction.north,
            sneaking: false,
            hasPlayer: true,
          ),
          Direction.south,
        );
        expect(
          bearingFacingForPlacement(
            nearestLooking: Direction.north,
            sneaking: true,
            hasPlayer: true,
          ),
          Direction.north,
        );
      },
    );

    test('the rules give the Java facing for every look and every shaft', () {
      const pos = (0, 0, 0);
      // The four horizontal and the two vertical look directions.
      for (final look in Direction.values) {
        for (final sneaking in [false, true]) {
          for (final shaftSide in [null, ...Direction.values]) {
            bool shaftTowards(Pos neighbour, Direction side) =>
                side == shaftSide;
            final preferred = bearingPreferredFacing(pos, shaftTowards);
            final expected = bearingFacingForPlacement(
              nearestLooking: look,
              sneaking: sneaking,
              hasPlayer: true,
              preferred: preferred,
            );
            expect(
              bearingFacingFromRules(
                pos,
                nearestLooking: look,
                sneaking: sneaking,
                shaftTowards: shaftTowards,
              ),
              expected,
              reason: 'look $look, sneaking $sneaking, shaft $shaftSide',
            );
          }
        }
      }
    });

    test('the rules cover the three branches of `getStateForPlacement`', () {
      const pos = (0, 0, 0);
      for (final look in Direction.values) {
        // No shaft, not sneaking: opposite of the look.
        expect(
          bearingFacingFromRules(
            pos,
            nearestLooking: look,
            sneaking: false,
            shaftTowards: (_, _) => false,
          ),
          look.opposite,
          reason: 'no shaft, not sneaking: $look',
        );
        // No shaft, sneaking: the look.
        expect(
          bearingFacingFromRules(
            pos,
            nearestLooking: look,
            sneaking: true,
            shaftTowards: (_, _) => false,
          ),
          look,
          reason: 'no shaft, sneaking: $look',
        );
        // A shaft: opposite of the shaft side, and sneaking wins over it.
        for (final side in Direction.values) {
          expect(
            bearingFacingFromRules(
              pos,
              nearestLooking: look,
              sneaking: false,
              shaftTowards: (_, shaft) => shaft == side,
            ),
            side.opposite,
            reason: 'shaft $side, look $look',
          );
          expect(
            bearingFacingFromRules(
              pos,
              nearestLooking: look,
              sneaking: true,
              shaftTowards: (_, shaft) => shaft == side,
            ),
            look,
            reason: 'sneaking keeps the look, shaft $side, look $look',
          );
        }
      }
    });

    test('the shaft tag holds exactly the axis-shaft blocks', () {
      // `IRotate.hasShaftTowards(face) == (face.getAxis() == AXIS)` for these, which is what
      // `ShaftKind.axis` reads. The encased cogwheels are left out: they also need their
      // `top_shaft`/`bottom_shaft` value, so `axis` alone would over-report. The bearings are
      // `ShaftKind.facing` (their shaft leaves through the side opposite `facing`) and join
      // `facingShaftTag` instead.
      expect(shaftTag, 'create:shafts');
      expect(shaftPaths, {
        'shaft',
        'powered_shaft',
        'cogwheel',
        'large_cogwheel',
        'andesite_encased_shaft',
        'brass_encased_shaft',
        'rotation_speed_controller',
      });
      for (final path in shaftPaths) {
        expect(
          kineticBlockData(path).tags,
          contains(shaftTag),
          reason: '$path must join the tag the bearing rule reads',
        );
      }
      expect(
        kineticBlockData('andesite_encased_cogwheel').tags,
        isNot(contains(shaftTag)),
      );
      // The block definition the plugin registers agrees with `ShaftKind.axis`.
      const shaftDef = AxisBlockDef();
      for (final axis in KAxis.values) {
        final state = KState('create:shaft', {'axis': axis.name});
        for (final face in Dir.values) {
          expect(
            shaftDef.hasShaftTowards(state, face),
            face.axis == axis,
            reason: '$state, $face',
          );
        }
      }
    });

    test('the nearest looking direction comes from the look angles', () {
      expect(nearestLookingFromLook(0, 0), Direction.south);
      expect(nearestLookingFromLook(180, 0), Direction.north);
      expect(nearestLookingFromLook(-90, 0), Direction.east);
      expect(nearestLookingFromLook(90, 0), Direction.west);
      expect(nearestLookingFromLook(0, 90), Direction.down);
      expect(nearestLookingFromLook(0, -90), Direction.up);
    });

    test('a replaceable clicked block is replaced instead', () {
      // Air, water and replaceable blocks: the host places into the clicked position
      // (`place_block` in `crates/pumpkin-core/src/block/registry.rs`).
      expect(bearingPlacementPos((1, 2, 3), Direction.up, replaceable: true), (
        1,
        2,
        3,
      ));
    });

    test('every bearing registers the shared placement rules', () {
      final source = File('lib/src/contraptions/bearing/bearing_blocks.dart')
          .readAsStringSync();
      final blocks = RegExp(
        r"manifestBlock\(\s*'(mechanical_bearing|windmill_bearing|clockwork_bearing)'",
      ).allMatches(source).length;
      expect(blocks, 3, reason: 'the three bearings');
      final usesShared = RegExp(r'placement:\s*bearingPlacementRules')
          .allMatches(source)
          .length;
      expect(
        usesShared,
        3,
        reason: 'an inline rule list would drift from bearingPlacementRules',
      );
      expect(
        source.contains("PlacementRule.clickedFace('facing')"),
        isFalse,
        reason: 'the rules must come from bearing_placement.dart',
      );
    });
  });

  group('right click on a bearing', () {
    test('a held block is not consumed: the click is left to the item', () {
      // `MechanicalBearingBlock.useItemOn`: a non-empty stack returns TRY_WITH_EMPTY_HAND, which
      // lets the held block be placed. Returning SUCCESS here is what swallowed the placement.
      expect(
        bearingUse(mayBuild: true, sneaking: false, holdingItem: true),
        BearingUse.tryEmptyHand,
      );
    });

    test('an empty hand assembles or disassembles', () {
      expect(
        bearingUse(mayBuild: true, sneaking: false, holdingItem: false),
        BearingUse.assemble,
      );
    });

    test('sneaking and mayBuild=false fail like Java', () {
      expect(
        bearingUse(mayBuild: true, sneaking: true, holdingItem: false),
        BearingUse.fail,
      );
      expect(
        bearingUse(mayBuild: true, sneaking: true, holdingItem: true),
        BearingUse.fail,
      );
      expect(
        bearingUse(mayBuild: false, sneaking: false, holdingItem: false),
        BearingUse.fail,
      );
      expect(
        bearingUse(mayBuild: false, sneaking: false, holdingItem: true),
        BearingUse.fail,
      );
    });

    test('the handler in bearing_blocks.dart asks the pure decision', () {
      final source = File('lib/src/contraptions/bearing/bearing_blocks.dart')
          .readAsStringSync();
      expect(source.contains('bearingUse('), isTrue);
      expect(
        source.contains('BlockUseResult.tryEmptyHand'),
        isTrue,
        reason: 'a held stack must fall through to item use',
      );
    });
  });
}
