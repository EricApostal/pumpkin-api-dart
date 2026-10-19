// The geometry of `BlueprintEntity` (a hanging entity of size 1 to 3 blocks that can also hang
// on floors and ceilings): bounding box, rotation, support positions, and which recipe section
// a hit point belongs to. Pure; vectors are `(double, double, double)`.
import 'dart:math' as math;

import '../model/dir.dart';
import '../model/vec.dart';

/// An axis aligned box.
typedef Aabb = (double, double, double, double, double, double);

final class BlueprintGeometry {
  /// `direction`: the face the blueprint looks at (the wall is behind it).
  final Dir direction;

  /// `verticalOrientation`: for floors and ceilings, which way is "up" on the blueprint.
  final Dir verticalOrientation;

  /// 1 to 3.
  final int size;

  /// The block position of the entity (`getPos()`; in front of the wall).
  final P3 blockPos;

  const BlueprintGeometry({
    required this.direction,
    required this.verticalOrientation,
    required this.size,
    required this.blockPos,
  });

  /// The entity position (`setPosRaw`): the centre of the plane on the wall.
  V3 get entityPosition => (
    blockPos.$1 + .5 - direction.dx * 0.46875,
    blockPos.$2 + .5 - direction.dy * 0.46875,
    blockPos.$3 + .5 - direction.dz * 0.46875,
  );

  /// `updateFacingWithBoundingBox`: the yaw and pitch of the entity.
  (double yaw, double pitch) get rotation {
    if (direction.isHorizontal) {
      return (_get2dData(direction) * 90.0, 0);
    }
    final pitch = -90.0 * direction.step;
    final yaw = verticalOrientation.axis.isHorizontal ? 180 + _toYRot(verticalOrientation) : 0.0;
    return (yaw, pitch);
  }

  static int _get2dData(Dir d) => switch (d) {
    Dir.south => 0,
    Dir.west => 1,
    Dir.north => 2,
    Dir.east => 3,
    _ => 0,
  };

  static double _toYRot(Dir d) => switch (d) {
    Dir.south => 0,
    Dir.west => 90,
    Dir.north => 180,
    Dir.east => 270,
    _ => 0,
  };

  /// `calculateBoundingBox`.
  Aabb get boundingBox {
    var (cx, cy, cz) = entityPosition;
    final axis = direction.axis;
    if (size == 2) {
      final side = axis.isHorizontal ? direction.counterClockWise : verticalOrientation.clockWise;
      final up = axis.isHorizontal ? Dir.up : (direction == Dir.up ? verticalOrientation : verticalOrientation.opposite);
      cx += side.dx * 0.5 + up.dx * 0.5;
      cy += side.dy * 0.5 + up.dy * 0.5;
      cz += side.dz * 0.5 + up.dz * 0.5;
    }
    var d4 = (16 * size).toDouble(), d5 = (16 * size).toDouble(), d6 = (16 * size).toDouble();
    switch (direction.axis) {
      case Ax.x:
        d4 = 1;
      case Ax.y:
        d5 = 1;
      case Ax.z:
        d6 = 1;
    }
    d4 /= 32;
    d5 /= 32;
    d6 /= 32;
    return (cx - d4, cy - d5, cz - d6, cx + d4, cy + d5, cz + d6);
  }

  /// The block positions behind the blueprint that must hold it (`survives()`), with the face
  /// of each that has to be sturdy (`direction`).
  List<P3> get supportPositions {
    final i = math.max(1, size);
    final j = math.max(1, size);
    final behind = blockPos.rel(direction.opposite);
    final up = direction.axis.isHorizontal ? Dir.up : (direction == Dir.up ? verticalOrientation : verticalOrientation.opposite);
    final across = direction.axis.isVertical ? verticalOrientation.clockWise : direction.counterClockWise;
    final out = <P3>[];
    for (var k = 0; k < i; k++) {
      for (var l = 0; l < j; l++) {
        final i1 = (i - 1) ~/ -2;
        final j1 = (j - 1) ~/ -2;
        out.add(behind.rel(across, k + i1).rel(up, l + j1));
      }
    }
    return out;
  }

  /// The block positions the box overlaps (to test for collisions).
  List<P3> get coveredBlocks {
    final (x0, y0, z0, x1, y1, z1) = boundingBox;
    final out = <P3>[];
    for (var x = x0.floor(); x <= (x1 - 1e-7).floor(); x++) {
      for (var y = y0.floor(); y <= (y1 - 1e-7).floor(); y++) {
        for (var z = z0.floor(); z <= (z1 - 1e-7).floor(); z++) {
          out.add((x, y, z));
        }
      }
    }
    return out;
  }

  /// `getSectionAt(vec)`: the section index (0 for a 1x1 blueprint) of a hit point given
  /// relative to the entity position.
  int sectionAt(V3 vec, {required double yRot, required double xRot}) {
    if (size <= 1) return 0;
    var v = rotateVec(vec, yRot, Ax.y);
    v = rotateVec(v, -xRot, Ax.x);
    v = (v.$1 + 0.5, v.$2 + 0.5, v.$3);
    if (size == 3) v = (v.$1 + 1, v.$2 + 1, v.$3);
    final x = v.$1.floor().clamp(0, size - 1);
    final y = v.$2.floor().clamp(0, size - 1);
    return x + y * size;
  }

  /// Placement tries sizes 3, 2, 1 and takes the first that fits.
  static const sizesToTry = [3, 2, 1];
}

/// `BlueprintItem.useOn`: the blueprint entity's facing for a click on [face] by a player
/// looking in [horizontalDirection].
({Dir direction, Dir vertical}) blueprintPlacementFor(Dir face, Dir horizontalDirection) =>
    (direction: face, vertical: face.axis.isHorizontal ? Dir.down : horizontalDirection);
