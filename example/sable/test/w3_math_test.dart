// W3: the API math — the oriented bounding box SAT/sweep routines, the reused
// vector sink and the quaternion helpers the physics code relies on. Pure, so it
// runs on the VM.
import 'dart:math' as math;

import 'package:sable/sable.dart';
import 'package:test/test.dart';

void main() {
  group('Vector2d', () {
    test('set and setFrom', () {
      final a = Vector2d(1, 2)..setFrom(Vector2d(3, 4));
      expect(a.x, 3);
      expect(a.y, 4);
    });
  });

  group('Quaterniond helpers', () {
    test('fromAxisAngle rotates a vector around the axis', () {
      final q = Quaterniond()..fromAxisAngle(Vector3d(0, 1, 0), math.pi / 2);
      final rotated = q.transform(Vector3d(1, 0, 0), Vector3d());
      expect(rotated.x, closeTo(0, 1e-9));
      expect(rotated.z, closeTo(-1, 1e-9));
    });

    test('fromAxisAngleDeg matches the radian form', () {
      final degrees = Quaterniond()..fromAxisAngleDeg(Vector3d(0, 1, 0), 90);
      final radians = Quaterniond()..fromAxisAngle(Vector3d(0, 1, 0), math.pi / 2);
      expect(degrees.x, closeTo(radians.x, 1e-12));
      expect(degrees.w, closeTo(radians.w, 1e-12));
    });

    test('a zero axis is the identity', () {
      final q = Quaterniond()..fromAxisAngle(Vector3d(0, 0, 0), 1.0);
      expect(q, Quaterniond());
    });

    test('rotateY post-multiplies', () {
      final a = Quaterniond()..rotateY(math.pi / 2);
      final b = Quaterniond().mul(Quaterniond(0, math.sin(math.pi / 4), 0, math.cos(math.pi / 4)));
      expect(a.x, closeTo(b.x, 1e-12));
      expect(a.y, closeTo(b.y, 1e-12));
      expect(a.z, closeTo(b.z, 1e-12));
      expect(a.w, closeTo(b.w, 1e-12));
    });

    test('premul applies the rotation on the global side', () {
      final local = Quaterniond()..rotateX(0.3);
      final global = Quaterniond()..rotateY(0.5);
      final combined = Quaterniond.copy(local)..premul(global);
      final expected = Quaterniond.copy(global).mul(local);
      expect(combined.x, closeTo(expected.x, 1e-12));
      expect(combined.y, closeTo(expected.y, 1e-12));
      expect(combined.z, closeTo(expected.z, 1e-12));
      expect(combined.w, closeTo(expected.w, 1e-12));
    });
  });

  group('LevelReusedVectors', () {
    test('has eight vertex slots and fifteen axes', () {
      final sink = LevelReusedVectors();
      expect(sink.a, hasLength(8));
      expect(sink.b, hasLength(8));
      expect(sink.checks, hasLength(15));
      expect(sink.scaffoldingTop, hasLength(1));
    });
  });

  group('OrientedBoundingBox3d', () {
    late LevelReusedVectors sink;

    setUp(() => sink = LevelReusedVectors());

    OrientedBoundingBox3d box(Vector3d position, Vector3d dimensions) =>
        OrientedBoundingBox3d.withValues(
          position,
          dimensions,
          Quaterniond(),
          sink,
        );

    test('vertices are the eight corners', () {
      final b = box(Vector3d(0, 0, 0), Vector3d(2, 2, 2));
      final vertices = b.vertices(sink.a);
      expect(vertices, hasLength(8));
      // The Java code names its half-extents `tempmin`/`tempmax` the other way
      // round; slot 0 is `+dimensions/2` and slot 7 is `-dimensions/2`.
      expect(vertices[0].x, closeTo(1, 1e-9));
      expect(vertices[0].y, closeTo(1, 1e-9));
      expect(vertices[7].x, closeTo(-1, 1e-9));
      expect(vertices[7].y, closeTo(-1, 1e-9));
    });

    test('two overlapping boxes produce a translation vector', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(2, 2, 2));
      final b = box(Vector3d(0.5, 0, 0), Vector3d(2, 2, 2));

      final mtv = OrientedBoundingBox3d.sat(a, b);
      expect(mtv.length, closeTo(1.5, 1e-6));
      expect(mtv.x, closeTo(-1.5, 1e-6));
    });

    test('two separated boxes produce a zero vector', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(10, 0, 0), Vector3d(1, 1, 1));
      expect(OrientedBoundingBox3d.sat(a, b).length, closeTo(0, 1e-9));
    });

    test('a rotated box still overlaps its centre neighbour', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(2, 2, 2));
      final b = OrientedBoundingBox3d.withValues(
        Vector3d(0.2, 0, 0),
        Vector3d(2, 2, 2),
        Quaterniond()..fromAxisAngleDeg(Vector3d(0, 1, 0), 45),
        sink,
      );
      expect(OrientedBoundingBox3d.sat(a, b).length, greaterThan(0));
    });

    test('a sweep that hits reports an entry time in [0, 1]', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));
      final result = OrientedBoundingBox3d.sweep(a, b, Vector3d(10, 0, 0), SweepResult());

      expect(result.hit, isTrue);
      expect(result.entryT, closeTo(0.4, 1e-6));
      expect(result.exitT, closeTo(0.6, 1e-6));
      expect(result.normal.x, closeTo(-1, 1e-6));
    });

    test('a sweep that misses reports no hit', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));
      final result = OrientedBoundingBox3d.sweep(a, b, Vector3d(0, 10, 0), SweepResult());
      expect(result.hit, isFalse);
    });

    test('a sweep that stops short reports no hit', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(1, 1, 1));
      final b = box(Vector3d(5, 0, 0), Vector3d(1, 1, 1));
      final result = OrientedBoundingBox3d.sweep(a, b, Vector3d(2, 0, 0), SweepResult());
      expect(result.hit, isFalse);
    });

    test('checkSeparation projects every vertex', () {
      final a = box(Vector3d(0, 0, 0), Vector3d(2, 2, 2));
      final vertices = a.vertices(sink.a);
      final projection = OrientedBoundingBox3d.checkSeparation(
        vertices,
        Vector3d(1, 0, 0),
        Vector2d(),
      );
      expect(projection.x, closeTo(-1, 1e-9));
      expect(projection.y, closeTo(1, 1e-9));
    });

    test('genChecks produces six face axes and nine cross axes', () {
      final checks = LevelReusedVectors().checks;
      OrientedBoundingBox3d.genChecks(
        Vector3d(1, 0, 0),
        Vector3d(0, 1, 0),
        Vector3d(0, 0, 1),
        Vector3d(1, 0, 0),
        Vector3d(0, 1, 0),
        Vector3d(0, 0, 1),
        checks,
      );
      // Parallel boxes: every cross axis collapses to zero.
      expect(checks[0].x, 1);
      expect(checks[6].length, closeTo(0, 1e-12));
      expect(checks[14].length, closeTo(0, 1e-12));
    });
  });
}
