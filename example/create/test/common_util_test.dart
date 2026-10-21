import 'package:create/src/common/common.dart';
import 'package:test/test.dart';

void main() {
  test('direction rotation and opposites', () {
    expect(Direction.north.clockWise, Direction.east);
    expect(Direction.north.counterClockWise, Direction.west);
    expect(Direction.up.clockWiseAround(Axis.x), Direction.north);
    expect(Direction.up.clockWiseAround(Axis.z), Direction.east);
    expect(Direction.east.clockWiseAround(Axis.x), Direction.east);
    for (final d in Direction.values) {
      expect(d.opposite.opposite, d);
      expect(d.clockWiseAround(d.axis), d);
      expect(d.clockWiseAround(Axis.x).counterClockWiseAround(Axis.x), d);
    }
    expect(Direction.fromYRot(0), Direction.south);
    expect(Direction.fromYRot(90), Direction.west);
    expect(Direction.fromYRot(180), Direction.north);
    expect(Direction.fromYRot(-90), Direction.east);
    expect(Direction.nearest(0, -3, 1), Direction.down);
    expect(Direction.north.toYRot, 180);
  });

  test('Direction.nearest is getApproximateNearest, starting at Float.MIN_VALUE', () {
    // `Direction.getApproximateNearest` (`Direction.java:315-328`) starts from `NORTH` with
    // `highestDot = Float.MIN_VALUE` -- the smallest *positive* float -- and only replaces it on a
    // strictly greater dot product. So a vector that scores zero or less everywhere (a track shape
    // with no axis normalizes to the zero vector) keeps `north`, where a negative starting bound
    // would return the first constant, `down`, a vertical direction no carriage can have.
    expect(Direction.nearest(0, 0, 0), Direction.north);
    expect(Direction.nearest(-1, 0, 0), Direction.west);
    expect(Direction.nearest(0, 0, -1), Direction.north);
    expect(Direction.nearest(0, 1, 0), Direction.up);
    expect(Direction.nearest(0, -1, 0), Direction.down);
    expect(Direction.nearest(0.7, 0.1, 0.1), Direction.east);
    expect(Direction.nearest(0.1, 0.1, 0.7), Direction.south);
    // Equal dot products keep the earlier constant of `VALUES` (`down, up, north, south, west,
    // east`), as `>` does in Java: south is scanned before east.
    expect(Direction.nearest(0.7, 0, 0.7), Direction.south);
    // A horizontal axis is never vertical, whatever its sign: what the station's
    // `getAssemblyDirection` hands the carriage.
    for (final axis in [Axis.x, Axis.z]) {
      for (final direction in axis.directions) {
        expect(Direction.nearest(direction.stepX * 1.0, 0, direction.stepZ * 1.0).axis, axis);
      }
    }
  });

  test('rotation and mirror', () {
    expect(BlockRotation.clockwise90.getRotated(BlockRotation.clockwise90), BlockRotation.clockwise180);
    expect(BlockRotation.clockwise90.rotate(Direction.north), Direction.east);
    expect(BlockMirror.leftRight.mirrorDirection(Direction.north), Direction.south);
    expect(BlockMirror.frontBack.mirrorDirection(Direction.north), Direction.north);
  });

  test('transformPos matches StructureTemplate', () {
    expect(transformPos((2, 5, 1), BlockMirror.none, BlockRotation.clockwise90, posZero), (-1, 5, 2));
    expect(transformPos((2, 5, 1), BlockMirror.none, BlockRotation.counterclockwise90, posZero), (1, 5, -2));
    expect(transformPos((2, 5, 1), BlockMirror.none, BlockRotation.clockwise180, posZero), (-2, 5, -1));
    expect(transformPos((2, 5, 1), BlockMirror.leftRight, BlockRotation.none, posZero), (2, 5, -1));
    expect(transformPos((2, 5, 1), BlockMirror.none, BlockRotation.none, posZero), (2, 5, 1));
    // BlockPos.rotate agrees with transform around the origin.
    for (final r in BlockRotation.values) {
      expect((3, 1, -4).rotate(r), transformPos((3, 1, -4), BlockMirror.none, r, posZero));
    }
  });

  test('VecHelper.rotate', () {
    final v = VecHelper.rotate((1.0, 0.0, 0.0), 90, Axis.y);
    expect(v.$1, closeTo(0, 1e-6));
    expect(v.$3, closeTo(-1, 1e-6));
    expect(VecHelper.rotate((1.0, 2.0, 3.0), 0, Axis.x), (1.0, 2.0, 3.0));
    expect(VecHelper.getCenterOf(posZero), VecHelper.centerOfOrigin);
    expect(VecHelper.isVecPointingTowards((0.0, 1.0, 0.0), Direction.up), true);
  });

  test('angles', () {
    expect(AngleHelper.horizontalAngle(Direction.east), -270);
    expect(AngleHelper.verticalAngle(Direction.up), -90);
    expect(AngleHelper.getShortestAngleDiff(350, 10), closeTo(20, 1e-4));
  });

  test('couple and pair', () {
    final c = Couple.create(1, 2);
    expect(c.get(true), 1);
    expect(c.swap().get(true), 2);
    expect(c.map((e) => e * 2), Couple.create(2, 4));
    expect(c.values, [1, 2]);
    expect(Pair.of(1, 'a'), Pair.of(1, 'a'));
    expect(Iterate.directionsInAxis(Axis.y), [Direction.up, Direction.down]);
    expect(Iterate.cycleValue([1, 2, 3], 3), 1);
  });

  test('boxes and pos', () {
    final b = BlockBounds.fromCorners((3, 3, 3), (0, 1, 2));
    expect(b.size, (4, 3, 2));
    expect(b.isInside((1, 2, 3)), true);
    expect(b.positions().length, 24);
    expect((1, 2, 3).relative(Direction.west, 2), (-1, 2, 3));
    expect(posFromLong((-5, 70, 12).asLong), (-5, 70, 12));
    expect(StringHelper.snakeCaseToCamelCase('crushing_wheel'), 'CrushingWheel');
    expect(StringHelper.camelCaseToSnakeCase('CrushingWheel'), 'crushing_wheel');
    expect(DyeHelper.getDyeColors('red').first, 0xB13937);
  });
}
