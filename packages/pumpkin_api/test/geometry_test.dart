import 'dart:math' as math;

import 'package:pumpkin_api/src/geometry.dart';
import 'package:test/test.dart';

void main() {
  test('vector math', () {
    final a = vec3(1, 2, 3), b = vec3(4, 6, 3);
    expect(a + b, (5.0, 8.0, 6.0));
    expect(b - a, (3.0, 4.0, 0.0));
    expect(a * 2, (2.0, 4.0, 6.0));
    expect(b / 2, (2.0, 3.0, 1.5));
    expect(-a, (-1.0, -2.0, -3.0));
    expect(a.distanceTo(b), 5.0);
    expect(a.distanceSquaredTo(b), 25.0);
    expect(vec3(3, 4, 0).normalized.length, closeTo(1, 1e-12));
    expect(vec3Zero.normalized, vec3Zero);
    expect(vec3(1, 0, 0).cross(vec3(0, 1, 0)), (0.0, 0.0, 1.0));
    expect(a.dot(b), 1 * 4 + 2 * 6 + 9);
    expect(a.lerp(b, 0.5), (2.5, 4.0, 3.0));
    expect(vec3(1.7, -0.2, 3.0).blockCoords, (1, -1, 3));
    expect(vec3(1, 0, 0).angleTo(vec3(0, 1, 0)), closeTo(math.pi / 2, 1e-12));
    expect(vec3(1.234, 2, 3).describe(decimals: 1), '1.2, 2.0, 3.0');
    expect(a.clampLength(1).length, closeTo(1, 1e-12));
  });

  test('rotation convention', () {
    void near(Vec3 a, Vec3 b) {
      expect(a.x, closeTo(b.x, 1e-9));
      expect(a.y, closeTo(b.y, 1e-9));
      expect(a.z, closeTo(b.z, 1e-9));
    }

    near(directionFromRotation(0, 0), vec3(0, 0, 1));
    near(directionFromRotation(90, 0), vec3(-1, 0, 0));
    near(directionFromRotation(-90, 0), vec3(1, 0, 0));
    near(directionFromRotation(0, -90), vec3(0, 1, 0));
    near(directionFromRotation(0, 90), vec3(0, -1, 0));
    final (yaw, pitch) = rotationFromDirection(vec3(-1, 0, 0));
    expect(yaw, closeTo(90, 1e-9));
    expect(pitch, closeTo(0, 1e-9));
    final (y2, p2) = vec3(0, 0, 0).rotationTo(vec3(0, 5, 0));
    expect(p2, closeTo(-90, 1e-9));
    expect(y2, closeTo(0, 1e-9));
  });

  test('cuboid', () {
    final c = Cuboid.corners((3, 5, 7), (0, 4, 7));
    expect(c.min, (0, 4, 7));
    expect(c.max, (3, 5, 7));
    expect((c.sizeX, c.sizeY, c.sizeZ), (4, 2, 1));
    expect(c.volume, 8);
    expect(c.center, (2.0, 5.0, 7.5));
    expect(c.contains(vec3(3.9, 5.5, 7.5)), isTrue);
    expect(c.contains(vec3(4.0, 5.5, 7.5)), isFalse);
    expect(c.containsBlockXYZ(0, 4, 7), isTrue);
    expect(c.containsBlockXYZ(0, 6, 7), isFalse);
    expect(c.blockCoords.length, 8);
    expect(c.blockCoords.first, (0, 4, 7));
    expect(c.blockCoords.toSet().length, 8);
    final e = c.expand(1);
    expect(e.volume, 6 * 4 * 3);
    expect(c.intersects(e), isTrue);
    expect(c.intersects(Cuboid.corners((10, 10, 10), (12, 12, 12))), isFalse);
    expect(c.intersection(e), c);
    expect(c.union(Cuboid.corners((10, 4, 7), (10, 4, 7))).max, (10, 5, 7));
    expect(c.translate(1, 1, 1).min, (1, 5, 8));
    expect(c == Cuboid.corners((0, 4, 7), (3, 5, 7)), isTrue);
    expect(Cuboid.around(vec3(0.5, 0.5, 0.5), 1).volume, 27);
  });

  test('location', () {
    const l = Location(world: 'w', x: 1, y: 2, z: 3, yaw: 90);
    expect(l.copyWith(y: 5).y, 5);
    expect(l, const Location(world: 'w', x: 1, y: 2, z: 3, yaw: 90));
    expect(l.hashCode, const Location(world: 'w', x: 1, y: 2, z: 3, yaw: 90).hashCode);
    expect(l.direction.x, closeTo(-1, 1e-9));
    expect(l.distanceTo(l.copyWith(world: 'x')), double.infinity);
    expect(l.add(vec3(1, 1, 1)).position, (2.0, 3.0, 4.0));
    expect(l.describe(), 'w (1.0, 2.0, 3.0) yaw=90.0 pitch=0.0');
    expect(Location.fromVec3('w', vec3(1, 2, 3), yaw: 90), l);
  });
}
