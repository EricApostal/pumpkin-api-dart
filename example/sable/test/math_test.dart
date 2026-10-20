// The shared math layer: vectors, quaternions, the affine matrix, poses and
// bounding boxes. These are the types 251 files of the Sable port compile
// against, so their semantics are pinned here.
import 'dart:math' as math;

import 'package:sable/sable.dart';
import 'package:test/test.dart';

Matcher closeToVec(double x, double y, double z) => isA<Vector3d>()
    .having((v) => v.x, 'x', closeTo(x, 1e-9))
    .having((v) => v.y, 'y', closeTo(y, 1e-9))
    .having((v) => v.z, 'z', closeTo(z, 1e-9));

void main() {
  group('Vector3d', () {
    test('set/sub/mul/div/lerp/dot/cross', () {
      final a = Vector3d(1, 2, 3);
      expect(Vector3d.copy(a).add(Vector3d(1, 1, 1)), closeToVec(2, 3, 4));
      expect(a.subInto(Vector3d(1, 1, 1), Vector3d()), closeToVec(0, 1, 2));
      expect(a.mulInto(2, Vector3d()), closeToVec(2, 4, 6));
      expect(a.divVecInto(Vector3d(1, 2, 3), Vector3d()), closeToVec(1, 1, 1));
      expect(a.dot(Vector3d(1, 0, 0)), 1);
      expect(a.cross(Vector3d(1, 0, 0)), closeToVec(0, 3, -2));
      expect(Vector3d(0, 0, 0).lerp(Vector3d(10, 20, 30), 0.5), closeToVec(5, 10, 15));
    });

    test('normalize and length', () {
      final v = Vector3d(3, 4, 0);
      expect(v.length, closeTo(5, 1e-12));
      expect(v.normalizeInto(Vector3d()), closeToVec(0.6, 0.8, 0));
      expect(Vector3d().normalize(), closeToVec(0, 0, 0));
    });
  });

  group('Quaterniond', () {
    test('rotates 90 degrees about y', () {
      final half = math.sqrt(0.5);
      final q = Quaterniond(0, half, 0, half);
      expect(q.transform(Vector3d(1, 0, 0), Vector3d()), closeToVec(0, 0, -1));
      expect(q.transformInverse(Vector3d(0, 0, -1), Vector3d()), closeToVec(1, 0, 0));
    });

    test('angle and difference', () {
      final half = math.sqrt(0.5);
      final q = Quaterniond(0, half, 0, half);
      expect(q.angle(), closeTo(math.pi / 2, 1e-9));
      final identity = Quaterniond();
      expect(identity.difference(q, Quaterniond()).angle(), closeTo(math.pi / 2, 1e-9));
    });

    test('nlerp half way is 45 degrees', () {
      final half = math.sqrt(0.5);
      final q = Quaterniond(0, half, 0, half);
      final dest = Quaterniond();
      Quaterniond().nlerp(q, 0.5, dest);
      final v = dest.transform(Vector3d(1, 0, 0), Vector3d());
      expect(v.z, closeTo(-half, 1e-9));
      expect(v.x, closeTo(half, 1e-9));
    });
  });

  group('Matrix4d', () {
    test('affine inverse round trips a point', () {
      final m = Matrix4d()
          .translate(3, -2, 5)
          .rotate(Quaterniond(0, 0.5, 0.5, 0.7071067811865476))
          .scaleXYZ(2, 3, 4);
      final point = Vector3d(1.5, -0.25, 7);
      final world = m.transformPosition(point);
      final back = m.invertAffine().transformPosition(world);
      expect(back, closeToVec(1.5, -0.25, 7));
    });
  });

  group('Pose3d', () {
    test('transformPosition applies scale, rotation and position', () {
      final half = math.sqrt(0.5);
      final pose = Pose3d.full(
        Vector3d(10, 0, 0),
        Quaterniond(0, half, 0, half),
        Vector3d(1, 0, 0),
        Vector3d(2, 2, 2),
      );

      // local (1, 0, 0) is the rotation point: only the translation applies.
      expect(pose.transformPosition(Vector3d(1, 0, 0)), closeToVec(10, 0, 0));

      // local (2, 0, 0): offset (1,0,0) * scale 2 = (2,0,0), rotated -> (0,0,-2).
      expect(pose.transformPosition(Vector3d(2, 0, 0)), closeToVec(10, 0, -2));
    });

    test('transformPositionInverse is the inverse', () {
      final pose = Pose3d.full(
        Vector3d(-4, 12, 0.5),
        Quaterniond(0.2, 0.3, 0.4, 0.8)..normalize(),
        Vector3d(0.25, -1, 3),
        Vector3d(1.5, 0.5, 2),
      );
      final local = Vector3d(4, -2, 9);
      final global = pose.transformPosition(Vector3d.copy(local));
      final back = pose.transformPositionInverse(global);
      expect(back, closeToVec(local.x, local.y, local.z));
    });

    test('bakeIntoMatrix matches transformPosition', () {
      final pose = Pose3d.full(
        Vector3d(1, 2, 3),
        Quaterniond(0.1, -0.2, 0.3, 0.9)..normalize(),
        Vector3d(0.5, 0.5, 0.5),
        Vector3d(1, 1, 1),
      );
      final matrix = pose.matrix();
      final local = Vector3d(2, -3, 4);
      final a = pose.transformPosition(Vector3d.copy(local));
      final b = matrix.transformPosition(local);
      expect(a, closeToVec(b.x, b.y, b.z));
    });

    test('lerp interpolates position and orientation', () {
      final a = Pose3d.full(
        Vector3d(0, 0, 0),
        Quaterniond(),
        Vector3d(0, 0, 0),
        Vector3d(1, 1, 1),
      );
      final b = Pose3d.full(
        Vector3d(10, 20, 30),
        Quaterniond(),
        Vector3d(2, 2, 2),
        Vector3d(3, 3, 3),
      );
      final dest = Pose3d();
      a.lerp(b, 0.5, dest);
      expect(dest.position(), closeToVec(5, 10, 15));
      expect(dest.rotationPoint(), closeToVec(1, 1, 1));
      expect(dest.scale(), closeToVec(2, 2, 2));
    });

    test('withinTolerance compares position and rotation point', () {
      final a = Pose3d()..position().set(0, 0, 0);
      final b = Pose3d()..position().set(0.5, 0, 0);
      expect(a.withinTolerance(b, 1.0, 0.1), isTrue);
      expect(a.withinTolerance(b, 0.25, 0.1), isFalse);
    });
  });

  group('BoundingBox3d', () {
    test('setValues swaps, setUnchecked does not', () {
      final box = BoundingBox3d.full(2, 3, 4, 1, 1, 1);
      expect(box.minX, 1);
      expect(box.maxX, 2);
      expect(box.minY, 1);
      expect(box.maxY, 3);

      final unchecked = BoundingBox3d.unchecked(2, 3, 4, 1, 1, 1);
      expect(unchecked.minX, 2);
      expect(unchecked.maxX, 1);
    });

    test('transform takes the bounds around the rotated corners', () {
      final half = math.sqrt(0.5);
      final pose = Pose3d.full(
        Vector3d(),
        Quaterniond(0, half, 0, half),
        Vector3d(),
        Vector3d(1, 1, 1),
      );
      final box = BoundingBox3d.full(0, 0, 0, 2, 1, 1);
      final rotated = box.transform(pose);
      // +90 degrees about y maps (x, 0, z) to (z, 0, -x).
      expect(rotated.minX, closeTo(0, 1e-9));
      expect(rotated.maxX, closeTo(1, 1e-9));
      expect(rotated.minZ, closeTo(-2, 1e-9));
      expect(rotated.maxZ, closeTo(0, 1e-9));
      expect(rotated.minY, closeTo(0, 1e-9));
      expect(rotated.maxY, closeTo(1, 1e-9));
    });

    test('expand/intersect/contains/volume', () {
      final box = BoundingBox3d.full(0, 0, 0, 2, 2, 2);
      expect(box.volume(), closeTo(8, 1e-12));
      expect(BoundingBox3d.copy(box).expand(1).minX, -1);
      expect(box.containsValues(2, 2, 2), isTrue);
      expect(box.containsValues(2.5, 0, 0), isFalse);
      expect(box.intersects(BoundingBox3d.full(2, 2, 2, 4, 4, 4)), isTrue);
      expect(box.intersects(BoundingBox3d.full(3, 3, 3, 4, 4, 4)), isFalse);
      expect(box.intersect(BoundingBox3d.full(1, 1, 1, 4, 4, 4)).maxX, 2);
    });

    test('chunkBoundsFrom floors to chunk coordinates', () {
      final box = BoundingBox3d.full(-1, 15, 16, 16, 31, 31);
      final chunks = box.chunkBoundsFrom();
      expect(chunks.minX, -1);
      expect(chunks.maxX, 1);
      expect(chunks.minY, 0);
      expect(chunks.maxY, 1);
      expect(chunks.minZ, 1);
      expect(chunks.maxZ, 1);
    });
  });

  group('BoundingBox3i', () {
    test('is inclusive and reports volume in blocks', () {
      final box = BoundingBox3i.values(0, 0, 0, 1, 1, 1);
      expect(box.volume(), 8);
      expect(box.width(), 2);
      expect(box.containsValues(1, 1, 1), isTrue);
      expect(box.containsValues(2, 0, 0), isFalse);
    });

    test('chunkBoundsFrom uses arithmetic shift', () {
      final box = BoundingBox3i.values(-1, -1, -1, 15, 15, 15);
      final chunks = box.chunkBoundsFrom();
      expect(chunks.minX, -1);
      expect(chunks.maxX, 0);
    });

    test('empty has an inverted range', () {
      expect(BoundingBox3i.empty.minX, greaterThan(BoundingBox3i.empty.maxX));
      expect(BoundingBox3i.empty.volume(), 0);
    });

    test('fromPositions takes the tight box', () {
      final box = BoundingBox3i.fromPositions([(1, 2, 3), (-1, 5, 0), (4, -2, 3)]);
      expect(box, isNotNull);
      expect(box!.minX, -1);
      expect(box.maxX, 4);
      expect(box.minY, -2);
      expect(box.maxY, 5);
      expect(box.minZ, 0);
      expect(box.maxZ, 3);
      expect(BoundingBox3i.fromPositions(const []), isNull);
    });
  });

  group('JOMLConversion', () {
    test('converts record vectors and block positions', () {
      expect(JOMLConversion.toJoml((1.5, -2, 3)), closeToVec(1.5, -2, 3));
      expect(JOMLConversion.toMojang(Vector3d(1, 2, 3)), (1.0, 2.0, 3.0));
      expect(JOMLConversion.toJomlVec3i((1, 2, 3)), isA<Vector3i>());
      expect(JOMLConversion.atCenterOf((0, 0, 0)), closeToVec(0.5, 0.5, 0.5));
    });
  });
}
