// Parity harness for placement orientation: does the plugin choose the same block state as
// Java Create when a player places a block?
//
// Pure logic, no host. Every case is a (clicked face, player look direction, neighbour layout,
// sneaking) tuple, run against a matrix of blocks. The "actual" side is the plugin's own state
// selection: the pure functions of `lib/src/kinetics/placement.dart` for the kinetic blocks, and
// the `placement:` declarations of `manifestBlock(...)` (read from the library sources and
// evaluated exactly like the host does, `crates/pumpkin-data/src/block_registry.rs`) for the
// blocks the host places by itself. The "expected" side is a transcription of the Java rule,
// cited per block.
//
// Java sources (branch `port/26.3`), all under `src/main/java/com/simibubi/create/`:
//   content/kinetics/base/RotatedPillarKineticBlock.java:60-72        shaft, encased cogwheel (super)
//   content/kinetics/simpleRelays/CogWheelBlock.java:143-179          cogwheel, large cogwheel
//   content/kinetics/base/AbstractEncasedShaftBlock.java:36-44        encased shaft
//   content/kinetics/simpleRelays/encased/EncasedCogwheelBlock.java:74-84
//   content/kinetics/base/DirectionalKineticBlock.java:28-58          bearings (and the motor fallback)
//   content/kinetics/base/HorizontalKineticBlock.java:35-53           preferred horizontal facing
//   content/kinetics/base/HorizontalAxisKineticBlock.java:29-35       speed controller (super)
//   content/kinetics/base/DirectionalAxisKineticBlock.java:48-87      gauge (super)
//   content/kinetics/crank/HandCrankBlock.java:83-90                  hand crank
//   content/kinetics/motor/CreativeMotorBlock.java:31-38              creative motor
//   content/kinetics/speedController/SpeedControllerBlock.java:49-57  speed controller
//   content/kinetics/clock/CuckooClockBlock.java:45-50                cuckoo clock
//   content/kinetics/gauge/GaugeBlock.java:60-100                     speedometer, stressometer
//   content/contraptions/bearing/SailBlock.java:67-71                 sail frame, dyed sails
//   foundation/block/WrenchableDirectionalBlock.java:42-44            sail (super)
//   content/contraptions/bearing/BearingBlock.java                    bearings (no placement override)
import 'dart:io';
import 'dart:math' as math;

import 'package:create/src/contraptions/actors/actor_placement.dart';
import 'package:create/src/contraptions/bearing/bearing_placement.dart';
import 'package:create/src/contraptions/bearing/sail.dart';
import 'package:create/src/contraptions/chassis/chassis_placement.dart';
import 'package:create/src/contraptions/gantry/gantry_logic.dart'
    show gantryCarriagePlacementRules;
import 'package:create/src/contraptions/piston/linear_actuator_logic.dart'
    show mechanicalPistonHeadPlacementRules;
import 'package:create/src/conveyance/transport/funnel/funnel_placement.dart';
import 'package:create/src/conveyance/transport/hatch/item_hatch_logic.dart'
    show itemHatchPlacementRules;
import 'package:create/src/kinetics/block_data.dart'
    show
        facingShaftPaths,
        facingShaftTag,
        reverseFacingShaftPaths,
        reverseFacingShaftTag,
        shaftPaths,
        shaftTag;
import 'package:create/src/kinetics/block_defs.dart';
import 'package:create/src/kinetics/geometry.dart';
import 'package:create/src/trains/track/track_placement_rules.dart'
    show trackPlacementRules;
import 'package:create/src/kinetics/node.dart';
import 'package:create/src/kinetics/placement.dart';
import 'package:create/src/manifest/manifest.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

void main() {
  final registry = KineticBlockRegistry()
    ..register('create:shaft', const AxisBlockDef())
    ..register(
      'create:cogwheel',
      const AxisBlockDef(smallCog: true, dedicatedCog: true),
    )
    ..register(
      'create:large_cogwheel',
      const AxisBlockDef(largeCog: true, dedicatedCog: true),
    )
    ..register('create:andesite_encased_shaft', const AxisBlockDef())
    ..register('create:rotation_speed_controller', const AxisBlockDef())
    ..register('create:creative_motor', const FacingBlockDef())
    ..register('create:hand_crank', const FacingBlockDef(shaftAtFront: false))
    ..register(
      'create:mechanical_bearing',
      const FacingBlockDef(shaftAtFront: false),
    );

  group('placement parity', () {
    for (final target in _targets()) {
      test(target.label, () {
        final divergences = <String, int>{};
        var cases = 0;
        for (final face in Dir.values) {
          for (final look in Dir.values) {
            final (yaw, pitch) = _lookAngles[look]!;
            for (final layout in _layouts) {
              for (final sneaking in const [false, true]) {
                final world = layout.build(KPos.zero, face);
                KState stateAt(KPos p) => world[p] ?? KState.air;
                final p = _Placement(
                  face: face,
                  look: look,
                  horizontal: horizontalDirection(yaw),
                  pitch: pitch,
                  sneaking: sneaking,
                  stateAt: stateAt,
                );
                if (target.skip != null && target.skip!(p)) continue;
                cases++;
                final ctx = PlacementContext(
                  pos: KPos.zero,
                  clickedFace: face,
                  nearestLooking: nearestLookingDirection(yaw, pitch),
                  horizontal: horizontalDirection(yaw),
                  sneaking: sneaking,
                  stateAt: stateAt,
                  blocks: registry,
                );
                final actual = target.actual(p, ctx);
                final expected = target.expected(p);
                if (_sameProps(actual, expected)) continue;
                final key = '${layout.name}/${p.face}/${p.look}/${p.sneaking}: ${_fmt(actual)} != Java ${_fmt(expected)}';
                divergences.update(key, (n) => n + 1, ifAbsent: () => 1);
              }
            }
          }
        }
        final total = divergences.values.fold(0, (a, b) => a + b);
        final report =
            '${target.label} disagrees with ${target.java} in $total of $cases placements\n'
            '${divergences.entries.map((e) => '  ${e.key}: ${e.value}x').join('\n')}';

        expect(divergences, isEmpty, reason: report);
      });
    }
  });

  group('placement rules the host cannot express', () {
    // Each test pins one Java branch whose value the host's rule vocabulary cannot produce. The
    // rule list falls back to the nearest expressible value; when the host grows the missing
    // source, the fallback and this test change together.

    test('a chassis placed on another chassis copies its axis', () {
      // `LinearChassisBlock.getStateForPlacement`: `isChassis(clickedState)` wins over the look
      // axis. The host has no source for the clicked block's `axis`, so the clicked face's axis
      // (y for a top face) stands in.
      final p = _Placement(
        face: Dir.up,
        look: Dir.down,
        horizontal: Dir.south,
        pitch: 90,
        sneaking: false,
        stateAt: (pos) => pos == const KPos(0, -1, 0)
            ? const KState('create:linear_chassis', {'axis': 'x'})
            : KState.air,
      );
      expect(_javaChassisAxis(p), KAxis.x);
      expect(_applyHostRules(linearChassisPlacementRules, _HostInput.of(p)), {
        'axis': 'y',
      });
    });

    test('an actor placed on another actor copies its facing', () {
      // `AttachedActorBlock.getStateForPlacement` copies the clicked actor's `FACING`; the host
      // has no source for a clicked block's property, so the look's opposite stands in.
      final p = _Placement(
        face: Dir.north,
        look: Dir.south,
        horizontal: Dir.south,
        pitch: 0,
        sneaking: false,
        stateAt: (pos) => pos == const KPos(0, 0, 1)
            ? const KState('create:mechanical_harvester', {'facing': 'east'})
            : KState.air,
      );
      expect(_javaAttachedActorFacing(p), Dir.east);
      expect(
        _applyHostRules(attachedActorPlacementRules, _HostInput.of(p))['facing'],
        'north',
      );
    });

    test('an item hatch is refused on a top face in Java', () {
      // `ItemHatchBlock.getStateForPlacement` returns `null` for a vertical click, so no hatch
      // appears. A rule cannot refuse a placement; the host places it with the look direction.
      final p = _Placement(
        face: Dir.up,
        look: Dir.down,
        horizontal: Dir.south,
        pitch: 90,
        sneaking: false,
        stateAt: (_) => KState.air,
      );
      expect(_javaItemHatchFacing(p), isNull);
      expect(
        _applyHostRules(itemHatchPlacementRules, _HostInput.of(p))['facing'],
        'south',
      );
    });

    test('a belt funnel clicked on a top face takes the look direction', () {
      // `BeltFunnelBlock.getStateForPlacement`: a vertical click falls back to
      // `getHorizontalDirection()`, which is the look direction; the host rule gives its opposite
      // (the clicked face of a horizontal click), so a vertical click is 180 degrees off.
      final p = _Placement(
        face: Dir.up,
        look: Dir.down,
        horizontal: Dir.south,
        pitch: 90,
        sneaking: false,
        stateAt: (_) => KState.air,
      );
      expect(_javaBeltFunnelFacing(p), Dir.south);
      expect(
        _applyHostRules(beltFunnelPlacementRules, _HostInput.of(p))['facing'],
        'north',
      );
    });
  });

  group('the harness catches the regressions it was built for', () {
    // A sail placed on the floor while looking forward: Java faces the sail against the player's
    // look (`SailBlock.getStateForPlacement`), the clicked face is the floor. The old declaration
    // `clickedFace('facing', opposite: true)` got this wrong; the current one must not.
    test('a floor-placed sail faces the player, not the floor', () {
      final p = _Placement(
        face: Dir.up,
        look: Dir.north,
        horizontal: Dir.north,
        pitch: 0,
        sneaking: false,
        stateAt: (_) => KState.air,
      );
      expect(_javaSailFacing(p), Dir.south);
      expect(_javaDirectionalFacing(p), Dir.south);
      expect(_applyHostRules(sailRules(), _HostInput.of(p)), {
        'facing': 'south',
      });
      expect(
        _applyHostRules(const [
          PlacementRule.clickedFace('facing', opposite: true),
        ], _HostInput.of(p)),
        {'facing': 'down'},
        reason: 'the old clicked-face rule is the regression the harness exists to catch',
      );
    });

    test('a cogwheel on a shaft continues the shaft axis', () {
      final p = _Placement(
        face: Dir.up,
        look: Dir.down,
        horizontal: Dir.south,
        pitch: 90,
        sneaking: false,
        stateAt: (pos) => pos == const KPos(1, 0, 0)
            ? const KState('create:shaft', {'axis': 'x'})
            : KState.air,
      );
      final ctx = PlacementContext(
        pos: KPos.zero,
        clickedFace: p.face,
        nearestLooking: p.look,
        horizontal: p.horizontal,
        sneaking: p.sneaking,
        stateAt: p.stateAt,
        blocks: registry,
      );
      expect(cogwheelAxis(ctx, large: false), KAxis.x);
      expect(_javaCogwheelAxis(p, large: false), KAxis.x);
    });
  });

  group('cogwheel placement', () {
    // `CogWheelBlock.getAxisForPlacement` in the cases that differ from a plain
    // clicked-axis rule: a side face, a neighbouring shaft, a second cog.
    PlacementContext ctxFor(
      Dir face, {
      Map<KPos, KState> neighbours = const {},
      bool sneaking = false,
    }) => PlacementContext(
      pos: KPos.zero,
      clickedFace: face,
      nearestLooking: Dir.south,
      horizontal: Dir.south,
      sneaking: sneaking,
      stateAt: (p) => neighbours[p] ?? KState.air,
      blocks: registry,
    );

    _Placement javaFor(
      Dir face, {
      Map<KPos, KState> neighbours = const {},
      bool sneaking = false,
    }) => _Placement(
      face: face,
      look: Dir.south,
      horizontal: Dir.south,
      pitch: 0,
      sneaking: sneaking,
      stateAt: (p) => neighbours[p] ?? KState.air,
    );

    test('the top face turns the cog on y', () {
      for (final large in const [false, true]) {
        expect(cogwheelAxis(ctxFor(Dir.up), large: large), KAxis.y);
        expect(_javaCogwheelAxis(javaFor(Dir.up), large: large), KAxis.y);
      }
    });

    test('a side face turns the cog on that face axis', () {
      expect(cogwheelAxis(ctxFor(Dir.east), large: false), KAxis.x);
      expect(cogwheelAxis(ctxFor(Dir.north), large: false), KAxis.z);
      expect(_javaCogwheelAxis(javaFor(Dir.east), large: false), KAxis.x);
      expect(_javaCogwheelAxis(javaFor(Dir.north), large: false), KAxis.z);
    });

    test('a cog beside a shaft continues the shaft axis', () {
      // The shaft runs along z to the south; the top face was clicked, so the
      // clicked axis (y) is wrong and only the shaft's `hasShaftTowards` can give
      // the cog the z axis (`RotatedPillarKineticBlock.getPreferredAxis`).
      final neighbours = {const KPos(0, 0, 1): _shaft(Dir.south)};
      expect(
        cogwheelAxis(ctxFor(Dir.up, neighbours: neighbours), large: false),
        KAxis.z,
      );
      expect(
        _javaCogwheelAxis(
          javaFor(Dir.up, neighbours: neighbours),
          large: false,
        ),
        KAxis.z,
      );
    });

    test('a second cog next to a small cog continues its axis', () {
      // The existing cog turns on z; the west face was clicked (x axis), and
      // `CogWheelBlock.getAxisForPlacement` copies the clicked-on cog's axis.
      final neighbours = {const KPos(1, 0, 0): _cog(Dir.south)};
      expect(
        cogwheelAxis(ctxFor(Dir.west, neighbours: neighbours), large: false),
        KAxis.z,
      );
      expect(
        _javaCogwheelAxis(
          javaFor(Dir.west, neighbours: neighbours),
          large: false,
        ),
        KAxis.z,
      );
    });

    test('the placed-on cog is the one the player clicked, from either side', () {
      // Clicking the east face of a z-axis cog east of the new position: the new
      // block is at the cog's east, so the click is on its west face.
      final eastSide = {const KPos(-1, 0, 0): _cog(Dir.south)};
      final clickedEast = ctxFor(Dir.east, neighbours: eastSide);
      expect(clickedEast.placedOnPos, const KPos(-1, 0, 0));
      expect(cogwheelAxis(clickedEast, large: false), KAxis.z);

      // Clicking the west face of a cog west of the new position: same axis.
      final westSide = {const KPos(1, 0, 0): _cog(Dir.south)};
      final clickedWest = ctxFor(Dir.west, neighbours: westSide);
      expect(clickedWest.placedOnPos, const KPos(1, 0, 0));
      expect(cogwheelAxis(clickedWest, large: false), KAxis.z);

      // The canPlace event's `face` is the host's `final_face`, pointing from the
      // placed block toward the clicked one, so the clicked face is its opposite
      // (`placementContextFor`). With that conversion the neighbour is the cog.
      const hostFace = Dir.west;
      final fromEvent = ctxFor(hostFace.opposite, neighbours: eastSide);
      expect(fromEvent.placedOnPos, const KPos(-1, 0, 0));
      expect(cogwheelAxis(fromEvent, large: false), KAxis.z);

      // Reading the event face as the clicked face points the other way and loses
      // the cog's axis: the sign-inversion the fix removes.
      final inverted = ctxFor(hostFace, neighbours: eastSide);
      expect(inverted.placedOnPos, const KPos(1, 0, 0));
      expect(cogwheelAxis(inverted, large: false), isNot(KAxis.z));
    });

    test('sneaking keeps the clicked face axis even next to a shaft', () {
      final neighbours = {const KPos(0, 0, 1): _shaft(Dir.south)};
      expect(
        cogwheelAxis(
          ctxFor(Dir.up, neighbours: neighbours, sneaking: true),
          large: false,
        ),
        KAxis.y,
      );
      expect(
        _javaCogwheelAxis(
          javaFor(Dir.up, neighbours: neighbours, sneaking: true),
          large: false,
        ),
        KAxis.y,
      );
    });

    test('without a click record the clicked face comes from the placed state', () {
      // The host places with `clickedAxis`: the state still carries the clicked
      // axis when no `UseRecord` matched, so the correction must not assume `up`.
      expect(clickedFaceForPlacedState(_cog(Dir.east)), Dir.east);
      expect(clickedFaceForPlacedState(_cog(Dir.south)), Dir.south);
      expect(
        clickedFaceForPlacedState(_facing('create:creative_motor', Dir.north)),
        Dir.north,
      );
      expect(clickedFaceForPlacedState(KState.air), Dir.up);
      expect(
        cogwheelAxis(
          ctxFor(clickedFaceForPlacedState(_cog(Dir.east))),
          large: false,
        ),
        KAxis.x,
      );
    });
  });

  group('assembly operator press', () {
    // `MechanicalPressBlock.getStateForPlacement`: `getPreferredHorizontalFacing`
    // as it is, else `HorizontalKineticBlock`'s
    // `getHorizontalDirection().getOpposite()`. Both the belt placement
    // (`AssemblyOperatorBlockItem`) and a directly placed press use
    // `mechanicalPressFacing`; the host's declared rule is the fallback.
    PlacementContext pressCtx(Map<KPos, KState> neighbours) => PlacementContext(
      pos: KPos.zero,
      clickedFace: Dir.up,
      nearestLooking: Dir.south,
      horizontal: Dir.south,
      sneaking: false,
      stateAt: (p) => neighbours[p] ?? KState.air,
      blocks: registry,
    );

    test('without a shaft the press faces the player', () {
      expect(mechanicalPressFacing(pressCtx(const {})), Dir.north);
    });

    test('a neighbouring shaft turns the press onto it, not away from it', () {
      final neighbours = {const KPos(-1, 0, 0): _shaft(Dir.east)};
      expect(mechanicalPressFacing(pressCtx(neighbours)), Dir.west);
      expect(
        _javaPreferredFacing(
          _Placement(
            face: Dir.up,
            look: Dir.south,
            horizontal: Dir.south,
            pitch: 0,
            sneaking: false,
            stateAt: (p) => neighbours[p] ?? KState.air,
          ),
          Dir.horizontals,
        ),
        Dir.west,
      );
    });

    test('a directly placed press takes the shaft side over the look fallback', () {
      // The host declares `horizontalFacing(opposite: true)` and would face the
      // press north (away from the player); the preferred side is west.
      final neighbours = {const KPos(-1, 0, 0): _shaft(Dir.east)};
      final ctx = pressCtx(neighbours);
      expect(ctx.horizontal.opposite, Dir.north);
      expect(mechanicalPressFacing(ctx), Dir.west);
      // No shaft: the declared rule is already the Java answer.
      expect(
        mechanicalPressFacing(pressCtx(const {})),
        pressCtx(const {}).horizontal.opposite,
      );
    });
  });

  group('declared placement rules', () {
    test('every sail and bearing declares placement rules', () {
      for (final key in [..._bearingKeys, ..._sailKeys]) {
        expect(
          _declaredRules(key),
          isNotEmpty,
          reason: '$key declares no placement rules',
        );
      }
    });

    test('the declarations are the ones the Java rules need', () {
      // `sail.dart` (`SailBlock.getStateForPlacement`): the look direction, turned around.
      expect(_describe(sailPlacement), ['facing/lookingDirection/opposite']);
      // `bearing_placement.dart` (`DirectionalKineticBlock.getStateForPlacement`): a
      // neighbouring shaft wins unless the player sneaks, otherwise the look decides, turned
      // around unless the player sneaks. The clicked face is not used at all.
      expect(_describe(_declaredRules('create:mechanical_bearing')), [
        'facing/neighbourShaft/opposite',
        'facing/lookingDirection/opposite',
        'facing/lookingDirection',
      ]);
    });

    test('the chassis, sticker, gantry, piston head, actors, funnels and hatch declare theirs', () {
      for (final key in [
        ..._linearChassisKeys,
        'create:radial_chassis',
        'create:sticker',
        'create:gantry_carriage',
        'create:mechanical_piston_head',
        ..._attachedActorKeys,
        ..._beltFunnelKeys,
        'create:item_hatch',
      ]) {
        expect(
          _declaredRules(key),
          isNotEmpty,
          reason: '$key declares no placement rules',
        );
      }
    });

    test('the rules are the ones the Java placement needs', () {
      // `StickerBlock.getStateForPlacement`: the look direction, flipped unless sneaking.
      expect(_describe(stickerPlacementRules), [
        'facing/lookingDirection',
        'facing/lookingDirection/opposite',
      ]);
      // `GantryCarriageBlock.getFacingForPlacement`: the clicked face.
      expect(_describe(gantryCarriagePlacementRules), ['facing/clickedFace']);
      // `WrenchableDirectionalBlock` (the piston head): the look direction, never flipped.
      expect(_describe(mechanicalPistonHeadPlacementRules), [
        'facing/lookingDirection',
        'waterlogged/inWater',
      ]);
      // The belt funnel faces the clicked face, which is the look turned around for a side click.
      expect(_describe(beltFunnelPlacementRules), [
        'facing/horizontalFacing/opposite',
        'waterlogged/inWater',
      ]);
      // The item hatch faces away from the clicked face, which is the look direction.
      expect(_describe(itemHatchPlacementRules), [
        'facing/horizontalFacing',
        'waterlogged/inWater',
      ]);
      // The actors face the clicked face, which is the look turned around.
      expect(_describe(attachedActorPlacementRules), [
        'facing/horizontalFacing/opposite',
        'waterlogged/inWater',
      ]);
      // The chassis: the host has neither a clicked-block property source nor a look-axis one,
      // so the clicked face's axis stands in for both branches.
      for (final rules in [
        linearChassisPlacementRules,
        radialChassisPlacementRules,
      ]) {
        expect(_describe(rules), ['axis/clickedAxis']);
      }
    });

    test('the block definitions use the pure rule lists', () {
      // An inline list would drift from the rules the tests check (the bearing test's rule).
      const uses = {
        'lib/src/contraptions/chassis/chassis_blocks.dart': [
          'placement: linearChassisPlacementRules',
          'placement: radialChassisPlacementRules',
          'placement: stickerPlacementRules',
        ],
        'lib/src/contraptions/gantry/gantry_carriage.dart': [
          'placement: gantryCarriagePlacementRules',
        ],
        'lib/src/contraptions/piston/piston_blocks.dart': [
          'placement: mechanicalPistonHeadPlacementRules',
        ],
        'lib/src/contraptions/actors/attached_actor_block.dart': [
          'placement: attachedActorPlacementRules',
        ],
        'lib/src/conveyance/transport/funnel/funnel_blocks.dart': [
          'placement: beltFunnelPlacementRules',
        ],
        'lib/src/logistics/itemhatch/item_hatch_part.dart': [
          'placement: itemHatchPlacementRules',
        ],
      };
      uses.forEach((file, snippets) {
        final source = File(file).readAsStringSync();
        for (final snippet in snippets) {
          expect(source, contains(snippet), reason: '$file must use $snippet');
        }
      });
    });

    test('the track declares the look rule the ordinary placement needs', () {
      // `TrackBlock.getStateForPlacement` is the ordinary placement path in Java
      // (`BlockItem.useOn`), so the host has to place the shape itself. An `onPlaced` write
      // would recurse through the host's `placed` callback.
      expect(_describe(trackPlacementRules), [
        'shape/trackShape',
        'waterlogged/inWater',
      ]);
    });

    test('the track shape follows all four horizontal look directions', () {
      // `TrackBlock.java:139-190`: `(0, 0, 1)` is south, `(1, 0, 0)` east; the look picks the
      // nearest of the two straight axes, so south/north give `zo` and east/west give `xo`.
      final shapes = {
        for (final look in const [Dir.south, Dir.north, Dir.east, Dir.west])
          look: _applyHostRules(
            trackPlacementRules,
            _HostInput.of(
              _Placement(
                face: Dir.up,
                look: look,
                horizontal: look,
                pitch: 0,
                sneaking: false,
                stateAt: (_) => const KState('air'),
              ),
            ),
          )['shape'],
      };
      expect(shapes, {
        Dir.south: 'zo',
        Dir.north: 'zo',
        Dir.east: 'xo',
        Dir.west: 'xo',
      });
    });
  });

  test('every look direction maps to its canonical yaw/pitch', () {
    _lookAngles.forEach((look, angles) {
      expect(nearestLookingDirection(angles.$1, angles.$2), look);
      expect(
        horizontalDirection(angles.$1),
        look.isHorizontal ? look : Dir.south,
      );
    });
  });
}

// -- The matrix ------------------------------------------------------------------------------

/// Yaw/pitch (degrees) that make `Direction.orderedByNearest` pick the key direction first.
const Map<Dir, (double, double)> _lookAngles = {
  Dir.south: (0, 0),
  Dir.west: (90, 0),
  Dir.north: (180, 0),
  Dir.east: (-90, 0),
  Dir.down: (0, 90),
  Dir.up: (0, -90),
};

/// A neighbour layout: what is around the placed block. `face` is the clicked face, so
/// `pos.relative(face.opposite)` is the block that was clicked on.
final class _Layout {
  final String name;
  final Map<KPos, KState> Function(KPos pos, Dir face) build;

  const _Layout(this.name, this.build);
}

KState _shaft(Dir along) => KState('create:shaft', {'axis': along.axis.name});
KState _cog(Dir along) => KState('create:cogwheel', {'axis': along.axis.name});
KState _largeCog(Dir along) =>
    KState('create:large_cogwheel', {'axis': along.axis.name});
KState _facing(String block, Dir facing) =>
    KState(block, {'facing': facing.name});

/// A block whose top is sturdy and whose bottom is sturdy (`minecraft:stone`).
const KState _solid = KState('minecraft:stone');

/// `BlockState.isFaceSturdy(level, pos, face)` for the harness's blocks: only [_solid] is.
bool _sturdy(KState state) => state.block == _solid.block;

Map<KPos, KState> _noNeighbours(KPos pos, Dir face) => const {};

final List<_Layout> _layouts = [
  const _Layout('empty', _noNeighbours),
  _Layout('shaft+x', (pos, _) => {pos.relative(Dir.east): _shaft(Dir.east)}),
  _Layout('shaft+y', (pos, _) => {pos.above(): _shaft(Dir.up)}),
  _Layout('shaft+z', (pos, _) => {pos.relative(Dir.south): _shaft(Dir.south)}),
  _Layout(
    'shafts+x+z',
    (pos, _) => {
      pos.relative(Dir.east): _shaft(Dir.east),
      pos.relative(Dir.south): _shaft(Dir.south),
    },
  ),
  _Layout(
    'cog-at-click',
    (pos, face) => {pos.relative(face.opposite): _cog(Dir.up)},
  ),
  _Layout('large-cog-above-x', (pos, _) => {pos.above(): _largeCog(Dir.east)}),
  _Layout('large-cog-above-z', (pos, _) => {pos.above(): _largeCog(Dir.south)}),
  _Layout(
    'motor-east',
    (pos, _) => {
      pos.relative(Dir.east): _facing('create:creative_motor', Dir.west),
    },
  ),
  _Layout(
    'crank-west',
    (pos, _) => {
      pos.relative(Dir.west): _facing('create:hand_crank', Dir.west),
    },
  ),
  _Layout(
    'bearing-south',
    (pos, _) => {
      pos.relative(Dir.south): _facing('create:mechanical_bearing', Dir.south),
    },
  ),
  _Layout(
    'controller-below-x',
    (pos, _) => {
      pos.below(): const KState('create:rotation_speed_controller', {
        'axis': 'x',
      }),
    },
  ),
  _Layout(
    'controller-below-z',
    (pos, _) => {
      pos.below(): const KState('create:rotation_speed_controller', {
        'axis': 'z',
      }),
    },
  ),
  // For the track's ascending shapes: a solid block on one side, with and without a block above
  // it (`isFaceSturdy(UP)` / `isFaceSturdy(DOWN)` of `TrackBlock.getStateForPlacement`).
  _Layout('solid+x', (pos, _) => {pos.relative(Dir.east): _solid}),
  _Layout('solid+z', (pos, _) => {pos.relative(Dir.south): _solid}),
  _Layout(
    'solid+z-covered',
    (pos, _) => {
      pos.relative(Dir.south): _solid,
      pos.relative(Dir.south).above(): _solid,
    },
  ),
  _Layout(
    'solid-x-z',
    (pos, _) => {
      pos.relative(Dir.west): _solid,
      pos.relative(Dir.south): _solid,
    },
  ),
];

// -- What the plugin does --------------------------------------------------------------------

/// A block under test: the plugin's answer next to the Java rule it has to match.
final class _Target {
  final String label;
  final String java;
  final Map<String, String> Function(_Placement p, PlacementContext ctx) actual;
  final Map<String, String> Function(_Placement p) expected;

  /// Placements whose Java rule the host cannot express (a clicked-block property, a clicked
  /// horizontal face, a refused placement). They are covered by their own focused test.
  final bool Function(_Placement p)? skip;

  const _Target(
    this.label,
    this.java, {
    required this.actual,
    required this.expected,
    this.skip,
  });
}

List<_Target> _targets() => [
  _Target(
    'shaft',
    'RotatedPillarKineticBlock.getStateForPlacement',
    actual: (_, c) => {'axis': rotatedPillarAxis(c).name},
    expected: (p) => {'axis': _javaRotatedPillarAxis(p).name},
  ),
  _Target(
    'cogwheel',
    'CogWheelBlock.getAxisForPlacement (small)',
    actual: (_, c) => {'axis': cogwheelAxis(c, large: false).name},
    expected: (p) => {'axis': _javaCogwheelAxis(p, large: false).name},
  ),
  _Target(
    'large_cogwheel',
    'CogWheelBlock.getAxisForPlacement (large)',
    actual: (_, c) => {'axis': cogwheelAxis(c, large: true).name},
    expected: (p) => {'axis': _javaCogwheelAxis(p, large: true).name},
  ),
  _Target(
    'encased_shaft',
    'AbstractEncasedShaftBlock.getStateForPlacement',
    actual: (_, c) => {'axis': encasedShaftAxis(c).name},
    expected: (p) => {'axis': _javaEncasedShaftAxis(p).name},
  ),
  _Target(
    'encased_cogwheel',
    'EncasedCogwheelBlock.getStateForPlacement',
    actual: (_, c) => {'axis': encasedCogwheelAxis(c).name},
    expected: (p) => {'axis': _javaEncasedCogwheelAxis(p).name},
  ),
  _Target(
    'hand_crank',
    'HandCrankBlock.getStateForPlacement',
    actual: (_, c) => {'facing': handCrankFacing(c).name},
    expected: (p) => {'facing': _javaHandCrankFacing(p).name},
  ),
  _Target(
    'creative_motor',
    'CreativeMotorBlock.getStateForPlacement',
    actual: (_, c) => {'facing': creativeMotorFacing(c).name},
    expected: (p) => {'facing': _javaCreativeMotorFacing(p).name},
  ),
  _Target(
    'rotation_speed_controller',
    'SpeedControllerBlock.getStateForPlacement',
    actual: (_, c) => {'axis': speedControllerAxis(c).name},
    expected: (p) => {'axis': _javaSpeedControllerAxis(p).name},
  ),
  _Target(
    'cuckoo_clock',
    'CuckooClockBlock.getStateForPlacement',
    actual: (_, c) => {'facing': cuckooClockFacing(c).name},
    expected: (p) => {'facing': _javaCuckooClockFacing(p).name},
  ),
  _Target(
    'speedometer',
    'GaugeBlock.getStateForPlacement',
    actual: (_, c) {
      final g = gaugePlacement(c);
      return {'facing': g.facing.name, 'axis_along_first': '${g.alongFirst}'};
    },
    expected: (p) {
      final g = _javaGaugePlacement(p);
      return {'facing': g.facing.name, 'axis_along_first': '${g.alongFirst}'};
    },
  ),
  // The bearings and sails are placed by the host: their state selection is the declared rule
  // list, not a kinetic placement function.
  for (final key in _bearingKeys)
    _Target(
      key,
      'DirectionalKineticBlock.getStateForPlacement (BearingBlock)',
      actual: (p, _) => _applyHostRules(_declaredRules(key), _HostInput.of(p)),
      expected: (p) => {'facing': _javaDirectionalFacing(p).name},
    ),
  for (final key in _sailKeys)
    _Target(
      key,
      'SailBlock.getStateForPlacement + WrenchableDirectionalBlock.getStateForPlacement',
      actual: (p, _) => _applyHostRules(_declaredRules(key), _HostInput.of(p)),
      expected: (p) => {'facing': _javaSailFacing(p).name},
    ),
  // The track is placed by the host too: `TrackBlock.getStateForPlacement` becomes the
  // `PlacementRule.trackShape('shape')` rule of `track_registration.dart`.
  _Target(
    'track',
    'TrackBlock.getStateForPlacement (shape)',
    actual: (p, _) => {
      'shape': _applyHostRules(trackPlacementRules, _HostInput.of(p))['shape']!,
    },
    expected: (p) => {'shape': _javaTrackShape(p)},
  ),
  // The chassis family, the sticker, the gantry carriage, the piston head, the attached actors,
  // the belt funnels and the item hatch are placed by the host too: their state selection is the
  // rule list of the pure module named in `_declaredRules`.
  for (final key in _linearChassisKeys)
    _Target(
      key,
      'LinearChassisBlock.getStateForPlacement + RotatedPillarKineticBlock.getStateForPlacement',
      actual: (p, _) => _hostFacing(_declaredRules(key), p, 'axis'),
      expected: (p) => {'axis': _javaChassisAxis(p).name},
      // The clicked chassis's `axis` has no host source; the clicked face's axis stands in and
      // is the look axis only when the player clicks the face they look at.
      skip: (p) => p.face.axis != p.look.axis,
    ),
  _Target(
    'radial_chassis',
    'RotatedPillarKineticBlock.getStateForPlacement',
    actual: (p, _) => _hostFacing(_declaredRules('create:radial_chassis'), p, 'axis'),
    expected: (p) => {'axis': _javaChassisAxis(p).name},
    skip: (p) => p.face.axis != p.look.axis,
  ),
  _Target(
    'sticker',
    'StickerBlock.getStateForPlacement',
    actual: (p, _) => _hostFacing(_declaredRules('create:sticker'), p, 'facing'),
    expected: (p) => {'facing': _javaStickerFacing(p).name},
  ),
  _Target(
    'gantry_carriage',
    'GantryCarriageBlock.getFacingForPlacement (DirectionalAxisKineticBlock)',
    actual: (p, _) =>
        _hostFacing(_declaredRules('create:gantry_carriage'), p, 'facing'),
    expected: (p) => {'facing': _javaGantryFacing(p).name},
  ),
  _Target(
    'mechanical_piston_head',
    'MechanicalPistonHeadBlock on WrenchableDirectionalBlock.getStateForPlacement',
    actual: (p, _) => _hostFacing(
      _declaredRules('create:mechanical_piston_head'),
      p,
      'facing',
    ),
    expected: (p) => {'facing': _javaPistonHeadFacing(p).name},
  ),
  for (final key in _attachedActorKeys)
    _Target(
      key,
      'AttachedActorBlock.getStateForPlacement',
      actual: (p, _) => _hostFacing(_declaredRules(key), p, 'facing'),
      expected: (p) => {'facing': _javaAttachedActorFacing(p).name},
      // The clicked face (or the clicked actor's `facing`) has no host source; the opposite of
      // the look is the clicked face only for an aligned click.
      skip: (p) => p.face.isHorizontal && p.face != p.horizontal.opposite,
    ),
  for (final key in _beltFunnelKeys)
    _Target(
      key,
      'BeltFunnelBlock.getStateForPlacement',
      actual: (p, _) => _hostFacing(_declaredRules(key), p, 'facing'),
      expected: (p) => {'facing': _javaBeltFunnelFacing(p).name},
      // A horizontal clicked face is not a host source, and a vertical click wants the look
      // direction where the rule gives its opposite.
      skip: (p) => !p.face.isHorizontal || p.face != p.horizontal.opposite,
    ),
  _Target(
    'item_hatch',
    'ItemHatchBlock.getStateForPlacement',
    actual: (p, _) =>
        _hostFacing(_declaredRules('create:item_hatch'), p, 'facing'),
    expected: (p) => {'facing': _javaItemHatchFacing(p)!.name},
    // Java refuses a vertical click; the host cannot, and the clicked face is not a source.
    skip: (p) => !p.face.isHorizontal || p.face != p.horizontal.opposite,
  ),
];

/// The `facing` (or `axis`) the host places with [rules], as the single-property map the matrix
/// compares.
Map<String, String> _hostFacing(
  List<PlacementRule> rules,
  _Placement p,
  String property,
) => {property: _applyHostRules(rules, _HostInput.of(p))[property]!};

/// The two linear chassis (`LinearChassisBlock`).
const List<String> _linearChassisKeys = [
  'create:linear_chassis',
  'create:secondary_linear_chassis',
];

/// The actors of `AttachedActorBlock` (`HarvesterBlock`, `PloughBlock`, `RollerBlock`).
const List<String> _attachedActorKeys = [
  'create:mechanical_harvester',
  'create:mechanical_plough',
  'create:mechanical_roller',
];

/// The two belt funnels (`BeltFunnelBlock`).
const List<String> _beltFunnelKeys = [
  'create:andesite_belt_funnel',
  'create:brass_belt_funnel',
];

/// The sail rule, as the plugin declares it (`sail_block.dart`).
List<PlacementRule> sailRules() => _declaredRules(_sailKeys.first);

// -- The declared placement rules, read from the library --------------------------------

/// The bearings and sails of the manifest (`BearingBlock`, `SailBlock` subclasses).
final List<String> _bearingKeys = [
  for (final m in kBlocks)
    if (m.javaClass.endsWith('BearingBlock')) 'create:${m.key}',
];

/// The sail frame and the sixteen dyed sails (`SailBlock.frame` / `SailBlock.withCanvas`).
final List<String> _sailKeys = [
  sailFrame,
  for (final color in sailColors) dyedSail(color),
];

/// The `placement:` list of `manifestBlock('<blockKey>', ...)`, as declared in the library.
///
/// Sails keep theirs in the pure `sail.dart` (`sailPlacement`), the bearings in the pure
/// `bearing_placement.dart` (`bearingPlacementRules`), and the blocks below in their own pure
/// modules, so all of them are used directly.
List<PlacementRule> _declaredRules(String blockKey) {
  if (_bearingKeys.contains(blockKey)) return bearingPlacementRules;
  if (_sailKeys.contains(blockKey)) return sailPlacement;
  return switch (blockKey) {
    'create:linear_chassis' ||
    'create:secondary_linear_chassis' => linearChassisPlacementRules,
    'create:radial_chassis' => radialChassisPlacementRules,
    'create:sticker' => stickerPlacementRules,
    'create:gantry_carriage' => gantryCarriagePlacementRules,
    'create:mechanical_piston_head' => mechanicalPistonHeadPlacementRules,
    'create:mechanical_harvester' ||
    'create:mechanical_plough' ||
    'create:mechanical_roller' => attachedActorPlacementRules,
    'create:andesite_belt_funnel' ||
    'create:brass_belt_funnel' => beltFunnelPlacementRules,
    'create:item_hatch' => itemHatchPlacementRules,
    _ => throw StateError('no placement rules known for $blockKey'),
  };
}

/// `property/source/opposite` of every rule, for assertions.
List<String> _describe(List<PlacementRule> rules) => [
  for (final r in rules)
    '${r.property}/${r.source.name}${r.opposite ? '/opposite' : ''}',
];

// -- The host's rule evaluation --------------------------------------------------------------

/// What the host knows when it applies the declared [PlacementRule]s
/// (`PlacementContext` in `crates/pumpkin-data/src/block_registry.rs`).
final class _HostInput {
  final Dir face;
  final Dir look;
  final Dir horizontal;
  final double pitch;
  final bool sneaking;

  /// `PlacementContext.yaw`: the yaw of [look], `0` looks south.
  final double yaw;

  /// `PlacementContext.neighbours`: what is next to the placed block.
  final KState Function(KPos pos) stateAt;

  const _HostInput({
    required this.face,
    required this.look,
    required this.horizontal,
    required this.pitch,
    required this.sneaking,
    required this.stateAt,
    this.yaw = 0,
  });

  factory _HostInput.of(_Placement p) => _HostInput(
    face: p.face,
    look: p.look,
    horizontal: p.horizontal,
    pitch: p.pitch,
    sneaking: p.sneaking,
    stateAt: p.stateAt,
    yaw: _lookAngles[p.look]!.$1,
  );
}

/// `ShaftNeighbour` + `PlacementContext::has_shaft_towards`: the neighbour in [direction] is in
/// the rule's tag and its property points into the placed block.
bool _hostShaftTowards(ShaftNeighbour rule, KState neighbour, Dir direction) {
  final tagged = switch (rule.tag) {
    shaftTag => shaftPaths.contains(neighbour.path),
    facingShaftTag => facingShaftPaths.contains(neighbour.path),
    reverseFacingShaftTag => reverseFacingShaftPaths.contains(neighbour.path),
    _ => false,
  };
  if (!tagged) return false;
  final value = switch (rule.property) {
    'axis' => neighbour.axisOf('axis')?.name,
    'facing' => neighbour.dirOf('facing')?.name,
    _ => null,
  };
  if (value == null) return false;
  return switch (rule.kind) {
    ShaftKind.axis => value == direction.axis.name,
    ShaftKind.facing => value == direction.name,
    ShaftKind.facingOpposite => value == direction.opposite.name,
  };
}

/// `PlacementContext::shaft_neighbour_direction`: `DirectionalKineticBlock.getPreferredFacing`,
/// including the give-up when two sides on different axes connect.
Dir? _hostShaftNeighbourDirection(
  List<ShaftNeighbour> rules,
  _HostInput input,
) {
  Dir? preferred;
  for (final direction in Dir.values) {
    final neighbour = input.stateAt(KPos.zero.relative(direction));
    if (!rules.any((rule) => _hostShaftTowards(rule, neighbour, direction))) {
      continue;
    }
    if (preferred != null && preferred.axis != direction.axis) return null;
    preferred = direction;
  }
  return preferred;
}

/// `Block::placement_rules`: the first rule that gives a value for a property wins.
Map<String, String> _applyHostRules(
  List<PlacementRule> rules,
  _HostInput input,
) {
  final out = <String, String>{};
  for (final rule in rules) {
    if (out.containsKey(rule.property)) continue;
    if (rule.whenSneaking != null && rule.whenSneaking != input.sneaking)
      continue;
    final value = _hostValue(rule, input);
    if (value != null) out[rule.property] = value;
  }
  return out;
}

/// `PlacementSource::value` (`crates/pumpkin-data/src/block_registry.rs:271-320`).
String? _hostValue(PlacementRule rule, _HostInput input) {
  final opposite = rule.opposite;
  switch (rule.source) {
    case PlacementSourceKind.horizontalFacing:
      return _pick(input.horizontal, opposite);
    case PlacementSourceKind.lookingDirection:
      return _pick(input.look, opposite);
    case PlacementSourceKind.clickedFace:
      return _pick(input.face, opposite);
    case PlacementSourceKind.clickedFaceDown:
      final d = opposite ? input.face.opposite : input.face;
      return (d == Dir.up ? Dir.down : d).name;
    case PlacementSourceKind.clickedAxis:
      return input.face.axis.name;
    case PlacementSourceKind.horizontalAxis:
      return input.horizontal.axis.name;
    case PlacementSourceKind.clickedHalf:
      // The click height is not part of this matrix; the middle of the face is the default.
      const cursorY = 0.5;
      final bottom =
          input.face != Dir.down && (input.face == Dir.up || cursorY <= 0.5);
      return bottom != opposite ? 'bottom' : 'top';
    case PlacementSourceKind.verticalLook:
      final threshold = rule.pitch ?? 90;
      if (input.pitch <= -threshold) return opposite ? 'down' : 'up';
      if (input.pitch >= threshold) return opposite ? 'up' : 'down';
      return 'horizontal';
    case PlacementSourceKind.inWater:
      // Nothing in the matrix is placed into water.
      return '${false != opposite}';
    case PlacementSourceKind.sneaking:
      return '${input.sneaking != opposite}';
    case PlacementSourceKind.neighbourShaft:
      final direction = _hostShaftNeighbourDirection(rule.shafts, input);
      if (direction == null) return null;
      return _pick(direction, opposite);
    case PlacementSourceKind.trackShape:
      return _hostTrackShape(input);
    case PlacementSourceKind.constant:
      return rule.constantValue;
  }
}

/// `PlacementSource::TrackShape`: Create's `TrackBlock.getStateForPlacement`, the nearest of the
/// eight track axes to the look, ascending when the neighbour on that side has a solid top and no
/// block above it. A yaw of `0` looks south (`+z`).
String _hostTrackShape(_HostInput input) {
  const axes = [
    (0.0, 0.0, 1.0),
    (1.0, 0.0, 0.0),
    (1.0, 0.0, 1.0),
    (-1.0, 0.0, 1.0),
    (0.0, 1.0, -1.0),
    (0.0, 1.0, 1.0),
    (1.0, 1.0, 0.0),
    (-1.0, 1.0, 0.0),
  ];
  const names = ['zo', 'xo', 'pd', 'nd', 'an', 'as', 'ae', 'aw'];
  final radians = input.yaw * math.pi / 180;
  final look = (-math.sin(radians), 0.0, math.cos(radians));
  double distance((double, double, double) a) =>
      math.pow(a.$1 - look.$1, 2).toDouble() +
      math.pow(a.$2 - look.$2, 2).toDouble() +
      math.pow(a.$3 - look.$3, 2).toDouble();

  var best = 0;
  var bestDistance = double.maxFinite;
  for (var i = 0; i < axes.length; i++) {
    final axis = axes[i];
    final length = math.sqrt(
      axis.$1 * axis.$1 + axis.$2 * axis.$2 + axis.$3 * axis.$3,
    );
    final negative = (
      -axis.$1 / length,
      -axis.$2 / length,
      -axis.$3 / length,
    );
    final d = math.min(distance(axis), distance(negative));
    if (d > bestDistance) continue;
    bestDistance = d;
    best = i;
  }
  // Only the two straight shapes have an axis of length one, and only they ascend.
  final Dir? direction = switch (best) {
    0 => Dir.south,
    1 => Dir.east,
    _ => null,
  };
  if (direction == null) return names[best];

  var shape = best;
  for (final negative in const [true, false]) {
    final side = negative ? direction.opposite : direction;
    final beside = input.stateAt(KPos.zero.relative(side));
    final above = input.stateAt(KPos.zero.relative(side).relative(Dir.up));
    // `isFaceSturdy(level, offset, UP)` and `!isFaceSturdy(level, offset.above(), DOWN)`.
    final ascend = _sturdy(beside) && !_sturdy(above);
    if (!ascend) continue;
    shape = switch ((best, negative)) {
      (0, true) => 4,
      (0, false) => 5,
      (_, true) => 7,
      (_, false) => 6,
    };
  }
  return names[shape];
}

String _pick(Dir d, bool opposite) => (opposite ? d.opposite : d).name;

// -- The Java rules, transcribed --------------------------------------------------------------

/// What `BlockPlaceContext` gives the Java rule.
final class _Placement {
  final Dir face;
  final Dir look;
  final Dir horizontal;
  final double pitch;
  final bool sneaking;
  final KState Function(KPos pos) stateAt;

  const _Placement({
    required this.face,
    required this.look,
    required this.horizontal,
    required this.pitch,
    required this.sneaking,
    required this.stateAt,
  });

  KPos get pos => KPos.zero;

  /// `getClickedPos().relative(getClickedFace().getOpposite())`.
  KPos get placedOnPos => pos.relative(face.opposite);
}

/// `IRotate` of the blocks the matrix puts in the world.
bool _javaRotates(KState state) => switch (state.path) {
  'shaft' ||
  'cogwheel' ||
  'large_cogwheel' ||
  'encased_shaft' ||
  'encased_cogwheel' => true,
  'rotation_speed_controller' => true,
  'creative_motor' || 'hand_crank' || 'mechanical_bearing' => true,
  _ => false,
};

/// `IRotate.hasShaftTowards` of the blocks the matrix puts in the world.
bool _javaHasShaftTowards(KState state, Dir face) => switch (state.path) {
  // AbstractShaftBlock / RotatedPillarKineticBlock / HorizontalAxisKineticBlock: along the axis.
  'shaft' ||
  'cogwheel' ||
  'large_cogwheel' ||
  'encased_shaft' ||
  'encased_cogwheel' ||
  'rotation_speed_controller' => face.axis == (state.axisOf('axis') ?? KAxis.y),
  // CreativeMotorBlock: the facing side.
  'creative_motor' => face == (state.dirOf('facing') ?? Dir.north),
  // HandCrankBlock / BearingBlock: the side opposite the facing.
  'hand_crank' ||
  'mechanical_bearing' => face == (state.dirOf('facing') ?? Dir.north).opposite,
  _ => false,
};

/// `ICogWheel.isSmallCog`.
bool _javaIsSmallCog(KState state) => state.path == 'cogwheel';

/// `ICogWheel.isLargeCog`.
bool _javaIsLargeCog(KState state) => state.path == 'large_cogwheel';

/// `IRotate.getRotationAxis` of the blocks the matrix puts in the world.
KAxis _javaRotationAxis(KState state) => switch (state.path) {
  'creative_motor' ||
  'hand_crank' ||
  'mechanical_bearing' => (state.dirOf('facing') ?? Dir.north).axis,
  _ => state.axisOf('axis') ?? KAxis.y,
};

/// `RotatedPillarKineticBlock.getPreferredAxis`.
KAxis? _javaPreferredAxis(_Placement c) {
  KAxis? preferred;
  for (final side in Dir.values) {
    final state = c.stateAt(c.pos.relative(side));
    if (!_javaRotates(state)) continue;
    if (!_javaHasShaftTowards(state, side.opposite)) continue;
    if (preferred != null && preferred != side.axis) return null;
    preferred = side.axis;
  }
  return preferred;
}

/// `DirectionalKineticBlock.getPreferredFacing` / `HorizontalKineticBlock.getPreferredHorizontalFacing`.
Dir? _javaPreferredFacing(_Placement c, List<Dir> sides) {
  Dir? preferred;
  for (final side in sides) {
    final state = c.stateAt(c.pos.relative(side));
    if (!_javaRotates(state)) continue;
    if (!_javaHasShaftTowards(state, side.opposite)) continue;
    if (preferred != null && preferred.axis != side.axis) return null;
    preferred = side;
  }
  return preferred;
}

/// `RotatedPillarKineticBlock.getStateForPlacement`.
KAxis _javaRotatedPillarAxis(_Placement c) {
  final preferred = _javaPreferredAxis(c);
  if (preferred != null && !c.sneaking) return preferred;
  return preferred != null && c.sneaking ? c.face.axis : c.look.axis;
}

/// `AbstractEncasedShaftBlock.getStateForPlacement`.
KAxis _javaEncasedShaftAxis(_Placement c) {
  if (c.sneaking) return _javaRotatedPillarAxis(c);
  return _javaPreferredAxis(c) ?? c.look.axis;
}

/// `DirectionalKineticBlock.getStateForPlacement`.
Dir _javaDirectionalFacing(_Placement c) {
  final preferred = _javaPreferredFacing(c, Dir.values);
  if (preferred == null || c.sneaking)
    return c.sneaking ? c.look : c.look.opposite;
  return preferred.opposite;
}

/// `WrenchableDirectionalBlock.getStateForPlacement` + `SailBlock.getStateForPlacement`.
Dir _javaSailFacing(_Placement c) => c.look.opposite;

/// `GantryCarriageBlock.getFacingForPlacement`, used by
/// `DirectionalAxisKineticBlock.getStateForPlacement`: the clicked face.
Dir _javaGantryFacing(_Placement c) => c.face;

/// `StickerBlock.getStateForPlacement`: the nearest looking direction, flipped unless sneaking.
Dir _javaStickerFacing(_Placement c) => c.sneaking ? c.look : c.look.opposite;

/// `MechanicalPistonHeadBlock.getStateForPlacement` on `WrenchableDirectionalBlock`: the nearest
/// looking direction, never flipped.
Dir _javaPistonHeadFacing(_Placement c) => c.look;

/// `LinearChassisBlock.getStateForPlacement`, falling back to
/// `RotatedPillarKineticBlock.getStateForPlacement` when the player sneaks.
KAxis _javaChassisAxis(_Placement c) {
  if (!c.sneaking) {
    final clicked = c.stateAt(c.placedOnPos);
    if (_javaIsChassis(clicked)) return clicked.axisOf('axis') ?? KAxis.y;
    return c.look.axis;
  }
  return _javaRotatedPillarAxis(c);
}

/// `AbstractChassisBlock` of the manifest.
bool _javaIsChassis(KState state) => switch (state.path) {
  'linear_chassis' || 'secondary_linear_chassis' || 'radial_chassis' => true,
  _ => false,
};

/// `AttachedActorBlock.getStateForPlacement`.
Dir _javaAttachedActorFacing(_Placement c) {
  if (!c.face.isHorizontal) return c.horizontal.opposite;
  final clicked = c.stateAt(c.placedOnPos);
  if (_javaIsAttachedActor(clicked)) {
    return clicked.dirOf('facing') ?? Dir.north;
  }
  return c.face;
}

/// The blocks that extend `AttachedActorBlock`.
bool _javaIsAttachedActor(KState state) => switch (state.path) {
  'mechanical_harvester' || 'mechanical_plough' || 'mechanical_roller' => true,
  _ => false,
};

/// `BeltFunnelBlock.getStateForPlacement`: the clicked face when it is horizontal, else the
/// horizontal look direction.
Dir _javaBeltFunnelFacing(_Placement c) =>
    c.face.isHorizontal ? c.face : c.horizontal;

/// `ItemHatchBlock.getStateForPlacement`: the opposite of the clicked face, or no placement
/// (`null`) for a click on a top or bottom face.
Dir? _javaItemHatchFacing(_Placement c) =>
    c.face.isHorizontal ? c.face.opposite : null;

/// `CogWheelBlock.getAxisForPlacement`.
KAxis _javaCogwheelAxis(_Placement c, {required bool large}) {
  if (c.sneaking) return c.face.axis;

  final below = c.stateAt(c.pos.below());
  if (below.isCreate('rotation_speed_controller') && large) {
    return below.axisOf('axis') == KAxis.x ? KAxis.z : KAxis.x;
  }

  final placedAgainst = c.stateAt(c.placedOnPos);
  if (_javaIsSmallCog(placedAgainst)) return _javaRotationAxis(placedAgainst);

  return _javaPreferredAxis(c) ?? c.face.axis;
}

/// `EncasedCogwheelBlock.getStateForPlacement` (its `super` is `RotatedPillarKineticBlock`).
KAxis _javaEncasedCogwheelAxis(_Placement c) {
  final placedOn = c.stateAt(c.placedOnPos);
  var axis = _javaRotatedPillarAxis(c);
  if (_javaIsSmallCog(placedOn)) axis = _javaRotationAxis(placedOn);
  return axis;
}

/// `HandCrankBlock.getStateForPlacement`.
Dir _javaHandCrankFacing(_Placement c) {
  final preferred = _javaPreferredFacing(c, Dir.values);
  if (preferred == null || c.sneaking) return c.face;
  return preferred.opposite;
}

/// `CreativeMotorBlock.getStateForPlacement`, falling back to `DirectionalKineticBlock`.
Dir _javaCreativeMotorFacing(_Placement c) {
  final preferred = _javaPreferredFacing(c, Dir.values);
  if (c.sneaking || preferred == null) return _javaDirectionalFacing(c);
  return preferred;
}

/// `SpeedControllerBlock.getStateForPlacement`, falling back to `HorizontalAxisKineticBlock`.
KAxis _javaSpeedControllerAxis(_Placement c) {
  final above = c.stateAt(c.pos.above());
  if (_javaIsLargeCog(above)) {
    final axis = above.axisOf('axis');
    if (axis != null && axis.isHorizontal)
      return axis == KAxis.x ? KAxis.z : KAxis.x;
  }
  final preferred = _javaPreferredFacing(c, Dir.horizontals);
  if (preferred != null) return preferred.axis;
  return c.horizontal.clockWise(KAxis.y).axis;
}

/// `CuckooClockBlock.getStateForPlacement`.
Dir _javaCuckooClockFacing(_Placement c) {
  final preferred = _javaPreferredFacing(c, Dir.horizontals);
  return preferred != null ? preferred.opposite : c.horizontal.opposite;
}

/// `DirectionalAxisKineticBlock.prefersConnectionTo`: `shaftAxis == false` always answers `false`.
bool _prefersConnectionTo(_Placement c, Dir facing, {required bool shaftAxis}) {
  if (!shaftAxis) return false;
  final state = c.stateAt(c.pos.relative(facing));
  return _javaRotates(state) && _javaHasShaftTowards(state, facing.opposite);
}

/// `GaugeBlock.getStateForPlacement` on top of `DirectionalAxisKineticBlock.getStateForPlacement`.
({Dir facing, bool alongFirst}) _javaGaugePlacement(_Placement c) {
  // GaugeBlock.getStateForPlacement: a gauge put onto a shaft's end takes its facing from the look.
  final face = c.face;
  final placedOnState = c.stateAt(c.placedOnPos);
  if (_javaRotates(placedOnState) &&
      _javaHasShaftTowards(placedOnState, face)) {
    final lookPositive = c.look.isPositive;
    if (face.axis == KAxis.x) {
      return (facing: lookPositive ? Dir.north : Dir.south, alongFirst: true);
    } else if (face.axis == KAxis.y) {
      return (
        facing: c.horizontal.opposite,
        alongFirst: c.horizontal.axis == KAxis.x,
      );
    } else {
      return (facing: lookPositive ? Dir.west : Dir.east, alongFirst: false);
    }
  }

  // GaugeBlock.getFacingForPlacement: the clicked face.
  final facing = face;
  var alongFirst = false;
  final faceAxis = facing.axis;

  if (faceAxis.isHorizontal) {
    alongFirst = faceAxis == KAxis.z;
    final positivePerpendicular = faceAxis == KAxis.x ? Dir.south : Dir.east;
    final shaftAbove = _prefersConnectionTo(c, Dir.up, shaftAxis: true);
    final shaftBelow = _prefersConnectionTo(c, Dir.down, shaftAxis: true);
    final preferLeft = _prefersConnectionTo(
      c,
      positivePerpendicular,
      shaftAxis: false,
    );
    final preferRight = _prefersConnectionTo(
      c,
      positivePerpendicular.opposite,
      shaftAxis: false,
    );
    if (shaftAbove || shaftBelow || preferLeft || preferRight) {
      alongFirst = faceAxis == KAxis.x;
    }
  }

  if (faceAxis.isVertical) {
    // GaugeBlock.getAxisAlignmentForPlacement.
    alongFirst = c.horizontal.axis != KAxis.x;
    Dir? preferredSide;
    for (final side in Dir.horizontals) {
      if (!_prefersConnectionTo(c, side, shaftAxis: true) &&
          !_prefersConnectionTo(c, side.clockWise(KAxis.y), shaftAxis: false)) {
        continue;
      }
      if (preferredSide != null && preferredSide.axis != side.axis) {
        preferredSide = null;
        break;
      }
      preferredSide = side;
    }
    if (preferredSide != null) alongFirst = preferredSide.axis == KAxis.x;
  }

  return (facing: facing, alongFirst: alongFirst);
}

/// `TrackBlock.getStateForPlacement` (`TrackBlock.java:128-170`): the shape whose axis is nearest
/// to the horizontal look, ascending when the neighbour on that side has a solid top and no solid
/// bottom above it. Ties go to the later shape, as Java's `distance > bestValue` does.
String _javaTrackShape(_Placement c) {
  final (yaw, _) = _lookAngles[c.look]!;
  var look = (c.look.dx.toDouble(), 0.0, c.look.dz.toDouble());
  if (look.$1 == 0 && look.$3 == 0) {
    // `VecHelper.rotate(new Vec3(0, 0, 1), -yRot, Axis.Y)`.
    final radians = -yaw * math.pi / 180;
    look = (-math.sin(radians), 0.0, math.cos(radians));
  }
  final length = math.sqrt(look.$1 * look.$1 + look.$3 * look.$3);
  look = (look.$1 / length, 0.0, look.$3 / length);

  // `TrackShape.values()`, junctions and portals left out, with the first axis of each.
  const shapes = [
    ('none', (0.0, 0.0, 0.0)),
    ('zo', (0.0, 0.0, 1.0)),
    ('xo', (1.0, 0.0, 0.0)),
    ('pd', (1.0, 0.0, 1.0)),
    ('nd', (-1.0, 0.0, 1.0)),
    ('an', (0.0, 1.0, -1.0)),
    ('as', (0.0, 1.0, 1.0)),
    ('ae', (1.0, 1.0, 0.0)),
    ('aw', (-1.0, 1.0, 0.0)),
  ];
  double toLook((double, double, double) axis) =>
      math.pow(axis.$1 - look.$1, 2).toDouble() +
      math.pow(axis.$2 - look.$2, 2).toDouble() +
      math.pow(axis.$3 - look.$3, 2).toDouble();

  var best = 'zo';
  var bestAxis = (0.0, 0.0, 1.0);
  var bestValue = double.maxFinite;
  for (final (name, axis) in shapes) {
    final axisLength = math.sqrt(
      axis.$1 * axis.$1 + axis.$2 * axis.$2 + axis.$3 * axis.$3,
    );
    final normalizedAxis = axisLength < 1.0E-4
        ? (0.0, 0.0, 0.0)
        : (axis.$1 / axisLength, axis.$2 / axisLength, axis.$3 / axisLength);
    final negated = (
      -normalizedAxis.$1,
      -normalizedAxis.$2,
      -normalizedAxis.$3,
    );
    final distance = math.min(toLook(axis), toLook(negated));
    if (distance > bestValue) continue;
    bestValue = distance;
    best = name;
    bestAxis = axis;
  }

  // `if (bestAxis.lengthSqr() == 1)`: only the straight shapes ascend.
  if (bestAxis.$1.abs() + bestAxis.$2.abs() + bestAxis.$3.abs() != 1) return best;
  for (final negative in const [true, false]) {
    final side = negative ? -1 : 1;
    final offset = c.pos.offset(
      (bestAxis.$1 * side).round(),
      (bestAxis.$2 * side).round(),
      (bestAxis.$3 * side).round(),
    );
    if (_sturdy(c.stateAt(offset)) && !_sturdy(c.stateAt(offset.above()))) {
      if (best == 'xo') best = negative ? 'aw' : 'ae';
      if (best == 'zo') best = negative ? 'an' : 'as';
    }
  }
  return best;
}

// -- Comparison ------------------------------------------------------------------------------
bool _sameProps(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

String _fmt(Map<String, String> props) => props.isEmpty
    ? '<nothing>'
    : props.entries.map((e) => '${e.key}=${e.value}').join(',');
