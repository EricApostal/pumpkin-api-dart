// Swept SAT edge cases for `OrientedBoundingBox3d.sweep`.
//
// The routine is a swept separating-axis test over the 15 candidate axes. It
// reports the entry and exit fractions of the sweep, the entry normal (the
// direction to push A out of B) and the exit normal. The cases below pin the
// boundaries the entity-collision code depends on: a sweep that starts inside,
// a zero-length sweep, a grazing touch, and a sweep fast enough to tunnel
// through an axis-aligned test.
//
// Transcribed from `OrientedBoundingBox3d.sweep` on `port/26.3`.
import 'package:sable/sable.dart';
import 'package:test/test.dart';

void main() {
  late LevelReusedVectors sink;

  setUp(() => sink = LevelReusedVectors());

  OrientedBoundingBox3d box(Vector3d position, Vector3d dimensions, [double yawDegrees = 0]) {
    final orientation = Quaterniond();
    if (yawDegrees != 0) orientation.fromAxisAngleDeg(Vector3d(0, 1, 0), yawDegrees);
    return OrientedBoundingBox3d.withValues(position, dimensions, orientation, sink);
  }

  SweepResult sweep(OrientedBoundingBox3d a, OrientedBoundingBox3d b, Vector3d delta) =>
      OrientedBoundingBox3d.sweep(a, b, delta, SweepResult());

  group('entry and exit', () {
    test('a straight sweep reports the entry and exit fractions', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));

      final result = sweep(a, b, Vector3d(10, 0, 0));
      expect(result.hit, isTrue);
      // Contact at x = 4, separation at x = 6.
      expect(result.entryT, closeTo(0.4, 1e-9));
      expect(result.exitT, closeTo(0.6, 1e-9));
    });

    test('the entry normal points from the target back to the mover', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));

      final result = sweep(a, b, Vector3d(10, 0, 0));
      expect(result.normal.x, closeTo(-1, 1e-9));
      expect(result.normal.y, closeTo(0, 1e-9));
      expect(result.normal.z, closeTo(0, 1e-9));
    });

    test('the exit normal points the way the mover is travelling', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));

      final result = sweep(a, b, Vector3d(10, 0, 0));
      expect(result.exitNormal.x, closeTo(1, 1e-9));
    });

    test('a sweep that stops before contact does not hit', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));

      expect(sweep(a, b, Vector3d(3.9, 0, 0)).hit, isFalse);
    });

    test('a sweep away from the target does not hit', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));

      expect(sweep(a, b, Vector3d(-10, 0, 0)).hit, isFalse);
    });

    test('a sweep that ends past the target still hits', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));

      // The entry is inside the sweep even though the end point is past B.
      expect(sweep(a, b, Vector3d(20, 0, 0)).hit, isTrue);
    });

    test('a sweep that passes beside the target does not hit', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));

      expect(sweep(a, b, Vector3d(10, 0, 0)..add(Vector3d(0, 0, 5))).hit, isFalse);
    });
  });

  group('starting overlapped', () {
    test('a sweep that starts inside reports an entry of zero', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(2, 2, 2));
      final b = box(Vector3d(0.5, 0, 0), Vector3d(2, 2, 2));

      final result = sweep(a, b, Vector3d(10, 0, 0));
      expect(result.hit, isTrue);
      expect(result.entryT, 0.0);
      expect(result.exitT, greaterThan(0.0));
    });

    test('a zero-length sweep inside the target hits with no exit', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(2, 2, 2));
      final b = box(Vector3d(0.5, 0, 0), Vector3d(2, 2, 2));

      final result = sweep(a, b, Vector3d(0, 0, 0));
      expect(result.hit, isTrue);
      expect(result.entryT, 0.0);
      expect(result.exitT, double.infinity);
    });

    test('a zero-length sweep apart from the target does not hit', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));

      expect(sweep(a, b, Vector3d(0, 0, 0)).hit, isFalse);
    });
  });

  group('boundaries', () {
    test('a sweep that ends exactly at contact hits at the end', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));

      // Contact is at x = 4: moving 4 blocks arrives exactly at the face.
      final result = sweep(a, b, Vector3d(4, 0, 0));
      expect(result.hit, isTrue);
      expect(result.entryT, closeTo(1.0, 1e-9));
    });

    test('a sweep that starts exactly at contact hits at zero', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(1, 0, 0), Vector3d(1, 1, 1));

      final result = sweep(a, b, Vector3d(10, 0, 0));
      expect(result.hit, isTrue);
      expect(result.entryT, 0.0);
    });

    test('a fast sweep does not tunnel through the target', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));

      // 1000 blocks in one tick still reports the hit.
      final result = sweep(a, b, Vector3d(1000, 0, 0));
      expect(result.hit, isTrue);
      expect(result.entryT, closeTo(0.004, 1e-9));
    });
  });

  group('orientation', () {
    test('a rotated target is hit later than an axis-aligned one', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final aligned = box(Vector3d(5, 0, 0), Vector3d(2, 2, 2));
      final rotated = box(Vector3d(5, 0, 0), Vector3d(2, 2, 2), 45);

      final alignedHit = sweep(a, aligned, Vector3d(10, 0, 0));
      final rotatedHit = sweep(a, rotated, Vector3d(10, 0, 0));

      expect(alignedHit.hit, isTrue);
      expect(rotatedHit.hit, isTrue);
      // The 45 degree box reaches further along x (its half-diagonal is
      // sqrt(2) rather than 1), so contact happens earlier.
      expect(rotatedHit.entryT, lessThan(alignedHit.entryT));
    });

    test('a rotated mover is swept with its orientation', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(4, 1, 1), 90);
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));

      // After a 90 degree yaw the mover is 1 wide and 4 deep, so it has to
      // travel further before it touches.
      final result = sweep(a, b, Vector3d(10, 0, 0));
      expect(result.hit, isTrue);
      expect(result.entryT, closeTo(0.4, 1e-9));
    });
  });

  group('sat', () {
    test('touching boxes have zero penetration and no translation', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(1, 0, 0), Vector3d(1, 1, 1));

      expect(OrientedBoundingBox3d.sat(a, b).length, closeTo(0, 1e-9));
    });

    test('the translation vector pushes the first box out of the second', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(0.5, 0, 0), Vector3d(1, 1, 1));

      final mtv = OrientedBoundingBox3d.sat(a, b);
      expect(mtv.x, closeTo(-0.5, 1e-9));
      expect(mtv.y, closeTo(0, 1e-9));
      expect(mtv.z, closeTo(0, 1e-9));
    });

    test('a separated box reports no translation even when close', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(1.001, 0, 0), Vector3d(1, 1, 1));

      expect(OrientedBoundingBox3d.sat(a, b).length, closeTo(0, 1e-9));
    });
  });
}
