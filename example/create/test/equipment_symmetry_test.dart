import 'package:create/src/equipment/model/block_state_ops.dart';
import 'package:create/src/equipment/model/dir.dart';
import 'package:create/src/equipment/symmetry/mirror.dart';
import 'package:test/test.dart';

void main() {
  const stairs = BState('minecraft:oak_stairs', {'facing': 'north', 'half': 'bottom', 'shape': 'straight'});

  group('directions', () {
    test('clockwise about axes', () {
      expect(Dir.north.clockWise, Dir.east);
      expect(Dir.up.clockWiseAbout(Ax.x), Dir.north);
      expect(Dir.up.clockWiseAbout(Ax.z), Dir.east);
      expect(Dir.east.clockWiseAbout(Ax.x), Dir.east);
      expect(Dir.north.clockWiseAbout(Ax.y), Dir.east);
      expect(Dir.fromYRot(0), Dir.south);
      expect(Dir.fromYRot(180), Dir.north);
    });
  });

  group('block state ops', () {
    test('rotate facing and sides', () {
      expect(BlockStateOps.rotate(stairs, Rot.clockwise90)['facing'], 'east');
      expect(BlockStateOps.rotate(stairs, Rot.counterclockwise90)['facing'], 'west');
      const fence = BState('minecraft:oak_fence', {'north': 'true', 'east': 'false', 'south': 'false', 'west': 'false'});
      final r = BlockStateOps.rotate(fence, Rot.clockwise90);
      expect(r['east'], 'true');
      expect(r['north'], 'false');
    });

    test('mirror', () {
      expect(BlockStateOps.mirror(stairs, Mir.leftRight)['facing'], 'south');
      expect(BlockStateOps.mirror(stairs, Mir.frontBack)['facing'], 'north');
      const corner = BState('minecraft:oak_stairs', {'facing': 'north', 'half': 'bottom', 'shape': 'inner_left'});
      expect(BlockStateOps.mirror(corner, Mir.leftRight)['shape'], 'inner_right');
      const sign = BState('minecraft:oak_sign', {'rotation': '2'});
      expect(BlockStateOps.mirror(sign, Mir.leftRight)['rotation'], '14');
      expect(BlockStateOps.mirror(sign, Mir.frontBack)['rotation'], '6');
    });

    test('flipY', () {
      expect(BlockStateOps.flipY(const BState('s', {'half': 'bottom'}))['half'], 'top');
      expect(BlockStateOps.flipY(const BState('d', {'facing': 'down'}))['facing'], 'up');
      expect(BlockStateOps.flipY(const BState('d', {'facing': 'north'}))['facing'], 'north');
    });
  });

  group('plane mirror', () {
    test('XY mirrors along z', () {
      final m = PlaneMirror((10.0, 64.0, 10.0))..setOrientation(PlaneMirror.xy);
      final r = m.processOne((12, 64, 13), stairs);
      expect(r.keys.single, (12, 64, 7));
      expect(r.values.single['facing'], 'south');
    });

    test('YZ mirrors along x', () {
      final m = PlaneMirror((10.0, 64.0, 10.0))..setOrientation(PlaneMirror.yz);
      final r = m.processOne((12, 64, 13), stairs);
      expect(r.keys.single, (8, 64, 13));
    });

    test('integer truncation of the difference (negative side)', () {
      final m = PlaneMirror((10.5, 64.0, 10.5))..setOrientation(PlaneMirror.yz);
      // diff x = 9 - 10.5 = -1.5 -> (int) = -1 -> 9 + 2 = 11
      expect(m.processOne((9, 64, 0), stairs).keys.single, (11, 64, 0));
    });
  });

  group('cross and triple', () {
    test('cross plane Y orientation gives three copies', () {
      final m = CrossPlaneMirror((0.0, 0.0, 0.0));
      final r = m.processOne((2, 5, 3), stairs);
      expect(r.keys.toSet(), {(-2, 5, 3), (2, 5, -3), (-2, 5, -3)});
    });

    test('cross plane diagonal', () {
      final m = CrossPlaneMirror((0.0, 0.0, 0.0))..setOrientation(CrossPlaneMirror.d);
      final r = m.processOne((2, 5, 3), stairs);
      // flipD1: (x - dx - dz, z - dz - dx) = (2-2-3, 3-3-2) = (-3, -2)
      // flipD2: (x - dx + dz, z - dz + dx) = (2-2+3, 3-3+2) = (3, 2)
      expect(r.keys.toSet(), {(-3, 5, -2), (3, 5, 2), (-2, 5, -3)});
    });

    test('triple plane gives seven copies', () {
      final m = TriplePlaneMirror((0.0, 0.0, 0.0));
      final r = m.processOne((2, 5, 3), stairs);
      expect(r.length, 7);
    });

    test('process adds to the map', () {
      final m = PlaneMirror((0.0, 0.0, 0.0))..setOrientation(PlaneMirror.yz);
      final blocks = {(1, 0, 0): stairs};
      m.process(blocks);
      expect(blocks.keys.toSet(), {(1, 0, 0), (-1, 0, 0)});
    });

    test('rotate wraps', () {
      final m = PlaneMirror((0.0, 0.0, 0.0));
      m.rotate(false);
      expect(m.orientationIndex, 1);
      m.rotate(true);
      expect(m.orientationIndex, 0);
    });
  });

  group('wand placement + json', () {
    test('orientation from facing and yaw', () {
      expect(SymmetryWandPlacement.planeOrientationFor(Dir.north), PlaneMirror.xy);
      expect(SymmetryWandPlacement.planeOrientationFor(Dir.east), PlaneMirror.yz);
      expect(SymmetryWandPlacement.crossOrientationFor(0), CrossPlaneMirror.y);
      expect(SymmetryWandPlacement.crossOrientationFor(45), CrossPlaneMirror.d);
      expect(SymmetryWandPlacement.crossOrientationFor(100), CrossPlaneMirror.y);
    });

    test('json round trip', () {
      final m = CrossPlaneMirror((1.0, 2.0, 3.0))
        ..setOrientation(CrossPlaneMirror.d)
        ..enable = false;
      final back = SymmetryMirrorWire.fromJson(m.toJson());
      expect(back, m);
    });
  });
}
