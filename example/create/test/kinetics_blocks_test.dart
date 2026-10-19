import 'package:create/src/kinetics/block_data.dart';
import 'package:create/src/kinetics/block_defs.dart';
import 'package:create/src/kinetics/chain_drive.dart';
import 'package:create/src/kinetics/geometry.dart';
import 'package:create/src/kinetics/node.dart';
import 'package:create/src/kinetics/placement.dart';
import 'package:create/src/kinetics/placement_helpers.dart';
import 'package:create/src/kinetics/transform.dart';
import 'package:create/src/kinetics/wrench.dart';
import 'package:test/test.dart';

void main() {
  helperTests();
  transformTests();
  group('block definitions', () {
    test('every kinetic block passes the host validation', () {
      for (final path in kineticBlockPaths) {
        final def = kineticBlockData(path).toDefinition();
        final problems = def.validate();
        expect(problems, isEmpty, reason: '$path: $problems');
      }
    });

    test('every block is in the manifest and has the right state count', () {
      for (final path in kineticBlockPaths) {
        final m = manifestBlockOf(path);
        final layout = kineticBlockData(path).toDefinition().layout;
        expect(layout.stateCount, m.stateCount, reason: path);
      }
    });

    test('shape rules only use properties and values of their block', () {
      for (final path in kineticBlockPaths) {
        final d = kineticBlockData(path);
        for (final rule in d.shapeRules) {
          for (final e in rule.when.entries) {
            final p = d.properties.firstWhere((p) => p.name == e.key, orElse: () => throw StateError('$path: no ${e.key}'));
            expect(p.valueIndex(e.value), isNotNull, reason: '$path ${e.key}=${e.value}');
          }
        }
        expect(d.shapeRules.length, lessThanOrEqualTo(64), reason: path);
      }
    });
  });

  group('placement', () {
    KState Function(KPos) world(Map<KPos, KState> m) => (p) => m[p] ?? KState.air;
    final blocks = KineticBlockRegistry()
      ..register('create:shaft', const AxisBlockDef())
      ..register('create:cogwheel', const AxisBlockDef(smallCog: true, dedicatedCog: true))
      ..register('create:large_cogwheel', const AxisBlockDef(largeCog: true, dedicatedCog: true));

    PlacementContext ctx(Map<KPos, KState> m, {Dir face = Dir.up, Dir look = Dir.down, bool sneaking = false, KPos pos = const KPos(0, 0, 0)}) =>
        PlacementContext(
          pos: pos,
          clickedFace: face,
          nearestLooking: look,
          horizontal: Dir.north,
          sneaking: sneaking,
          stateAt: world(m),
          blocks: blocks,
        );

    test('a shaft aligns with the shaft it touches', () {
      final m = {const KPos(1, 0, 0): const KState('create:shaft', {'axis': 'x'})};
      expect(rotatedPillarAxis(ctx(m)), KAxis.x);
      expect(rotatedPillarAxis(ctx(m, sneaking: true, face: Dir.up)), KAxis.y);
      expect(rotatedPillarAxis(ctx({}, look: Dir.east)), KAxis.x);
    });

    test('shafts with different axes around leave the choice to the player', () {
      final m = {
        const KPos(1, 0, 0): const KState('create:shaft', {'axis': 'x'}),
        const KPos(0, 1, 0): const KState('create:shaft', {'axis': 'y'}),
      };
      expect(preferredAxis(ctx(m)), isNull);
    });

    test('a directional block faces away from the shaft it connects to', () {
      final m = {const KPos(0, 0, 1): const KState('create:shaft', {'axis': 'z'})};
      expect(preferredFacing(ctx(m)), Dir.south);
      expect(directionalFacing(ctx(m)), Dir.north);
      expect(directionalFacing(ctx({}, look: Dir.east)), Dir.west);
      expect(directionalFacing(ctx({}, look: Dir.east, sneaking: true)), Dir.east);
    });

    test('cogwheel positions: no two cogs of the same size touch with a different axis', () {
      final m = {const KPos(1, 0, 0): const KState('create:cogwheel', {'axis': 'y'})};
      // a small cog at the origin with axis x touches the cog at +x? the neighbour is on the x axis: allowed
      expect(isValidCogwheelPosition(false, world(m), blocks, KPos.zero, KAxis.x), isTrue);
      // axis y at the origin: the neighbour (axis y) is beside it and has the same axis: allowed
      expect(isValidCogwheelPosition(false, world(m), blocks, KPos.zero, KAxis.y), isTrue);
      // axis z: the neighbour at +x has axis y which differs from the direction axis: a large cog may not
      expect(isValidCogwheelPosition(true, world(m), blocks, KPos.zero, KAxis.z), isFalse);
      expect(isValidCogwheelPosition(false, world(m), blocks, KPos.zero, KAxis.z), isTrue);
    });

    test('looking directions', () {
      expect(nearestLookingDirection(0, 0), Dir.south); // yaw 0 faces south
      expect(nearestLookingDirection(90, 0), Dir.west);
      expect(nearestLookingDirection(180, 0), Dir.north);
      expect(nearestLookingDirection(-90, 0), Dir.east);
      expect(nearestLookingDirection(0, 80), Dir.down);
      expect(nearestLookingDirection(0, -80), Dir.up);
      expect(horizontalDirection(0), Dir.south);
      expect(horizontalDirection(90), Dir.west);
      expect(horizontalDirection(180), Dir.north);
      expect(horizontalDirection(270), Dir.east);
    });
  });

  group('chain drives', () {
    final blocks = KineticBlockRegistry()..chainDriveBlocks.add('create:encased_chain_drive');
    const chain = KState('create:encased_chain_drive', {'axis': 'y', 'part': 'none', 'axis_along_first': 'true'});

    test('two chain drives next to each other connect', () {
      // the second is placed east of the first
      final first = chainDriveUpdateShape(chain, Dir.east, chain, blocks);
      expect(first['part'], 'start');
      final second = chainDriveUpdateShape(chain, Dir.west, chain, blocks);
      expect(second['part'], 'end');
    });

    test('removing the neighbour disconnects', () {
      const connected = KState('create:encased_chain_drive', {'axis': 'y', 'part': 'start', 'axis_along_first': 'true'});
      final back = chainDriveUpdateShape(connected, Dir.east, KState.air, blocks);
      expect(back['part'], 'none');
    });

    test('a middle piece loses one side', () {
      const middle = KState('create:encased_chain_drive', {'axis': 'y', 'part': 'middle', 'axis_along_first': 'true'});
      expect(chainDriveUpdateShape(middle, Dir.east, KState.air, blocks)['part'], 'end');
      expect(chainDriveUpdateShape(middle, Dir.west, KState.air, blocks)['part'], 'start');
    });
  });

  group('wrench rotation', () {
    final blocks = KineticBlockRegistry();
    test('axis blocks rotate around the clicked face', () {
      const shaft = KState('create:shaft', {'axis': 'x', 'waterlogged': 'false'});
      expect(wrenchRotate(shaft, Dir.up, blocks: blocks)['axis'], 'z');
      expect(wrenchRotate(shaft, Dir.north, blocks: blocks)['axis'], 'y');
    });

    test('directional blocks turn their facing', () {
      const motor = KState('create:creative_motor', {'facing': 'north'});
      expect(wrenchRotate(motor, Dir.up, blocks: blocks)['facing'], 'east');
      expect(wrenchRotate(motor, Dir.east, blocks: blocks)['facing'], 'down');
    });

    test('encased cogwheels swap their shaft stubs', () {
      const cog = KState('create:andesite_encased_cogwheel', {'axis': 'y', 'top_shaft': 'true', 'bottom_shaft': 'false'});
      // about X (clicked on east): the y axis goes to z and the stubs swap
      final r = wrenchRotate(cog, Dir.east, blocks: blocks);
      expect(r['axis'], 'z');
      expect(r['top_shaft'], 'false');
      expect(r['bottom_shaft'], 'true');
      // about Z: the y axis goes to x and nothing swaps
      final r2 = wrenchRotate(cog, Dir.south, blocks: blocks);
      expect(r2['axis'], 'x');
      expect(r2['top_shaft'], 'true');
    });

    test('horizontal axis blocks only turn when clicked on the top or bottom', () {
      const controller = KState('create:rotation_speed_controller', {'axis': 'x'});
      expect(wrenchRotate(controller, Dir.up, traits: const RotationTraits(horizontalAxisOnly: true), blocks: blocks)['axis'], 'z');
      expect(wrenchRotate(controller, Dir.north, traits: const RotationTraits(horizontalAxisOnly: true), blocks: blocks), controller);
    });
  });
}

void helperTests() {
  group('placement helpers', () {
    final blocks = KineticBlockRegistry()
      ..register('create:shaft', const AxisBlockDef())
      ..register('create:cogwheel', const AxisBlockDef(smallCog: true, dedicatedCog: true))
      ..register('create:large_cogwheel', const AxisBlockDef(largeCog: true, dedicatedCog: true))
      ..register('create:andesite_encased_cogwheel', const EncasedCogDef(large: false));

    HelperWorld world(Map<KPos, KState> m) => HelperWorld((p) => m[p] ?? KState.air, (p) => !m.containsKey(p), blocks);

    test('a shaft line is extended at the end, behind the shafts already there', () {
      final m = {
        const KPos(0, 0, 0): const KState('create:shaft', {'axis': 'x'}),
        const KPos(1, 0, 0): const KState('create:shaft', {'axis': 'x'}),
      };
      final o = shaftPoleOffset(world(m), const KPos(0, 0, 0), m[const KPos(0, 0, 0)]!, (0.95, 0.5, 0.5));
      expect(o.success, isTrue);
      expect(o.pos, const KPos(2, 0, 0));
      expect(o.transform(const KState('create:shaft', {'axis': 'y'}))['axis'], 'x');
      // from the other side
      final o2 = shaftPoleOffset(world(m), const KPos(0, 0, 0), m[const KPos(0, 0, 0)]!, (0.05, 0.5, 0.5));
      expect(o2.pos, const KPos(-1, 0, 0));
    });

    test('the pole range limits the line', () {
      final m = {for (var x = 0; x < 5; x++) KPos(x, 0, 0): const KState('create:shaft', {'axis': 'x'})};
      final w = HelperWorld((p) => m[p] ?? KState.air, (p) => !m.containsKey(p), blocks, placementAssistRange: 3);
      final o = shaftPoleOffset(w, const KPos(0, 0, 0), m[const KPos(0, 0, 0)]!, (0.95, 0.5, 0.5));
      // 4 poles on the east side are over the range of 3: the other end is used
      expect(o.success, isTrue);
      expect(o.pos, const KPos(-1, 0, 0));
    });

    test('a small cog next to a small cog is placed diagonally', () {
      final m = {const KPos(0, 0, 0): const KState('create:cogwheel', {'axis': 'y'})};
      final o = smallCogOffset(world(m), const KPos(0, 0, 0), m[const KPos(0, 0, 0)]!, (0.95, 0.5, 0.6));
      // the click is not on the shaft: the side neighbour in the clicked direction
      expect(o.success, isTrue);
      expect(o.pos, const KPos(1, 0, 0));
      expect(o.transform(const KState('create:cogwheel', {'axis': 'x'}))['axis'], 'y');
    });

    test('clicking the shaft in the middle of a cog does not use the helper', () {
      final m = {const KPos(0, 0, 0): const KState('create:cogwheel', {'axis': 'y'})};
      final o = smallCogOffset(world(m), const KPos(0, 0, 0), m[const KPos(0, 0, 0)]!, (0.5, 1.0, 0.5));
      expect(o.success, isFalse);
    });

    test('a small cog beside a large cog goes on the diagonal', () {
      final m = {const KPos(0, 0, 0): const KState('create:large_cogwheel', {'axis': 'y'})};
      final o = smallCogOffset(world(m), const KPos(0, 0, 0), m[const KPos(0, 0, 0)]!, (0.95, 0.5, 0.6));
      expect(o.success, isTrue);
      expect(o.pos, const KPos(1, 0, 1));
    });

    test('a cog on an encased cogwheel uses the integrated helper', () {
      final m = {
        const KPos(0, 0, 0): const KState('create:andesite_encased_cogwheel', {'axis': 'y', 'top_shaft': 'false', 'bottom_shaft': 'false'}),
      };
      final o = cogwheelItemOffset(world(m), const KPos(0, 0, 0), m[const KPos(0, 0, 0)]!, Dir.east, (1.0, 0.5, 0.5), large: false);
      expect(o.success, isTrue);
      expect(o.transform(const KState('create:cogwheel', {'axis': 'x'}))['axis'], 'y');
    });

    test('the speed controller takes a large cog on top', () {
      final m = {const KPos(0, 0, 0): const KState('create:rotation_speed_controller', {'axis': 'x'})};
      final o = speedControllerCogOffset(world(m), const KPos(0, 0, 0), m[const KPos(0, 0, 0)]!);
      expect(o.success, isTrue);
      expect(o.pos, const KPos(0, 1, 0));
      expect(o.transform(const KState('create:large_cogwheel', {'axis': 'y'}))['axis'], 'z');
    });
  });
}

void transformTests() {
  group('state transforms', () {
    final blocks = KineticBlockRegistry()..chainDriveBlocks.add('create:encased_chain_drive');

    test('encased cogwheels swap their shafts on a half turn and mirror', () {
      const cog = KState('create:andesite_encased_cogwheel', {'axis': 'x', 'top_shaft': 'true', 'bottom_shaft': 'false'});
      final half = rotateKineticState(cog, 2, blocks)!;
      expect(half['top_shaft'], 'false');
      expect(half['bottom_shaft'], 'true');
      final quarter = rotateKineticState(cog, 1, blocks)!;
      expect(quarter['axis'], 'z');
      expect(quarter['top_shaft'], 'true'); // axis x, clockwise: Java swaps only for a counterclockwise turn
    });

    test('a chain drive keeps its connection through four quarter turns', () {
      const chain = KState('create:encased_chain_drive', {'axis': 'y', 'part': 'start', 'axis_along_first': 'true'});
      var s = chain;
      for (var i = 0; i < 4; i++) {
        s = rotateKineticState(s, 1, blocks)!;
      }
      expect(s, chain);
      // a half turn reverses the direction of the connection
      final half = rotateKineticState(chain, 2, blocks)!;
      expect(half['part'], 'end');
    });

    test('mirroring reverses a chain drive along the mirrored axis', () {
      const chain = KState('create:encased_chain_drive', {'axis': 'y', 'part': 'start', 'axis_along_first': 'true'});
      // axis y, along first: connection axis x
      expect(mirrorKineticState(chain, frontBack: true, leftRight: false)!['part'], 'end');
      expect(mirrorKineticState(chain, frontBack: false, leftRight: true)!['part'], 'start');
    });

    test('gauges cycle axis_along_first on odd turns', () {
      const gauge = KState('create:speedometer', {'facing': 'north', 'axis_along_first': 'true'});
      final r = rotateKineticState(gauge, 1, blocks)!;
      expect(r['axis_along_first'], 'false');
      expect(r['facing'], 'east');
    });
  });
}
