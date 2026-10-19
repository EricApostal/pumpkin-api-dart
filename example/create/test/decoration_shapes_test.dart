import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;
import 'package:test/test.dart';

import 'package:create/src/common/direction.dart';
import 'package:create/src/decoration/shapes.dart';

bool near(double a, double b) => (a - b).abs() < 1e-9;

void expectBox(BlockBox b, List<double> v) {
  final actual = [b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ];
  for (var i = 0; i < 6; i++) {
    expect(near(actual[i], v[i] / 16), isTrue, reason: 'component $i of $actual is not ${v[i]}/16');
  }
}

void main() {
  group('VoxelShaper', () {
    test('forDirectional rotates a slab to every face', () {
      expectBox(casing3px.get(Direction.up).single, [0, 0, 0, 16, 3, 16]);
      expectBox(casing3px.get(Direction.down).single, [0, 13, 0, 16, 16, 16]);
      // A panel facing north sits on the south side of the block (Create's rotation convention).
      expectBox(casing3px.get(Direction.north).single, [0, 0, 13, 16, 16, 16]);
      expectBox(casing3px.get(Direction.south).single, [0, 0, 0, 16, 16, 3]);
      expectBox(casing3px.get(Direction.east).single, [0, 0, 0, 3, 16, 16]);
      expectBox(casing3px.get(Direction.west).single, [13, 0, 0, 16, 16, 16]);
    });

    test('forHorizontal keeps the base shape for its own direction', () {
      expectBox(stepBottom.get(Direction.south).single, [0, 0, 8, 16, 8, 16]);
      expectBox(stepBottom.get(Direction.north).single, [0, 0, 0, 16, 8, 8]);
      // A shape built for south sits on the side of the direction it is rotated to.
      expectBox(stepBottom.get(Direction.east).single, [8, 0, 0, 16, 8, 16]);
      expectBox(stepBottom.get(Direction.west).single, [0, 0, 0, 8, 8, 16]);
      expectBox(stepTop.get(Direction.north).single, [0, 8, 0, 16, 16, 8]);
    });

    test('forAxis and forHorizontalAxis', () {
      expectBox(eightVoxelPole.getAxis(Axis.y).single, [4, 0, 4, 12, 16, 12]);
      expectBox(eightVoxelPole.getAxis(Axis.x).single, [0, 4, 4, 16, 12, 12]);
      expectBox(eightVoxelPole.getAxis(Axis.z).single, [4, 4, 0, 12, 12, 16]);
      expectBox(girderBeam.getAxis(Axis.z).single, [4, 2, 0, 12, 14, 16]);
      expectBox(girderBeam.getAxis(Axis.x).single, [0, 2, 4, 16, 14, 12]);
    });

    test('girder cross has a pole and both beams', () {
      expect(girderCross.length, 3);
      expectBox(girderCross.first, [3, 0, 3, 13, 16, 13]);
    });

    test('the beam shaft along x is the pole along x plus the beam along z', () {
      final s = girderBeamShaft.getAxis(Axis.x);
      expect(s.length, 2);
      expectBox(s[0], [4, 2, 0, 12, 14, 16]); // beam along z
      expectBox(s[1], [0, 5, 5, 16, 11, 11]); // pole along x
    });
  });

  group('vanilla tables', () {
    test('door, ladder and trapdoor tables equal Shapes.rotateHorizontal(boxZ(16, 13, 16))', () {
      final shaper = rotateHorizontalFromNorth(boxZ16(16, 0, 16, 13, 16));
      for (final f in Direction.planeHorizontal) {
        expect(ladderShapes[f]!.single, isA<BlockBox>());
        final a = ladderShapes[f]!.single;
        final b = shaper.get(f).single;
        expect([a.minX, a.minY, a.minZ, a.maxX, a.maxY, a.maxZ].map((v) => (v * 16).round()).toList(),
            [b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ].map((v) => (v * 16).round()).toList(),
            reason: '$f');
      }
    });

    test('doorShape follows the open hinge rule', () {
      // Facing north, closed: z 13..16. Open with the left hinge turns clockwise (east -> x 0..3).
      expectBox(doorShape(Direction.north, false, false).single, [0, 0, 13, 16, 16, 16]);
      expectBox(doorShape(Direction.north, true, false).single, [0, 0, 0, 3, 16, 16]);
      expectBox(doorShape(Direction.north, true, true).single, [13, 0, 0, 16, 16, 16]);
    });

    test('stairs: a straight stair faces its high side, corners use the outer table', () {
      final straight = stairShape('bottom', 'straight', Direction.north);
      // Bottom slab plus the north half of the upper layer.
      final upper = straight.where((b) => b.minY >= 0.5).toList();
      expect(upper.length, 2);
      for (final b in upper) {
        expect(b.maxZ <= 0.5 + 1e-9, isTrue);
      }
      final outer = stairShape('bottom', 'outer_left', Direction.north);
      expect(outer.where((b) => b.minY >= 0.5).single.maxX, closeTo(0.5, 1e-9));
      final topStair = stairShape('top', 'straight', Direction.north);
      expect(topStair.any((b) => b.minY < 0.5 && b.maxY <= 0.5 + 1e-9 && b.minZ < 0.01), isTrue);
    });

    test('slab shapes', () {
      expectBox(slabShape('bottom').single, [0, 0, 0, 16, 8, 16]);
      expectBox(slabShape('top').single, [0, 8, 0, 16, 16, 16]);
      expect(slabShape('double').single.maxY, 1);
    });

    test('walls and panes', () {
      expect(wallShape(true, {Direction.north: 'low'}).length, 2);
      expect(wallShape(false, const {}).isEmpty, isTrue);
      final north = wallShape(false, {Direction.north: 'tall'}).single;
      expectBox(north, [5, 0, 0, 11, 16, 11]);
      final collision = wallShape(true, {Direction.east: 'low'}, collision: true);
      expect(collision.first.maxY, 1.5);
      expectBox(crossShape({Direction.south: true}).last, [7, 0, 8, 9, 16, 16]);
    });

    test('trapdoors', () {
      expectBox(trapdoorShape(Direction.north, 'bottom', false).single, [0, 0, 0, 16, 3, 16]);
      expectBox(trapdoorShape(Direction.north, 'top', false).single, [0, 13, 0, 16, 16, 16]);
      expectBox(trapdoorShape(Direction.north, 'top', true).single, [0, 0, 13, 16, 16, 16]);
    });
  });

  group('create shapes', () {
    test('sliding door shapes', () {
      expectBox(slidingDoorShape(Direction.south, true, false).single, [-13, 0, 0, 3, 16, 3]);
      expectBox(slidingDoorShape(Direction.north, false, true).single, [-3, 0, 7, 3, 16, 16]);
    });

    test('whistle shapes', () {
      expect(whistleFloor['medium']!.length, 3);
      expect(whistleWall['small']!.get(Direction.south).length, 3);
      expectBox(whistleExtender('double', 'large').single, [2, 0, 2, 14, 18, 14]);
    });

    test('placard and scaffolding', () {
      expectBox(placard.get(Direction.up).single, [2, 0, 2, 14, 3, 14]);
      expectBox(placard.get(Direction.down).single, [2, 13, 2, 14, 16, 14]);
      expect(scaffoldFull.length, 5);
    });
  });
}
