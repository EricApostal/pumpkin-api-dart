// `TrackVoxelShapes` and the `AllShapes.TRACK_*` shapes (pure): the selection and collision
// shapes of the track block per `shape` state, as unions of boxes in block units. The tracks'
// shapes reach 14 pixels over the block's edges, like in Java.
//
// A [VShape] is a list of pixel boxes (16 per block) with the few `Shapes` operations the track
// shapes use: union, `ONLY_FIRST` subtraction and `optimize` (merging of cells into few boxes).
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../common/common.dart';
import 'track_shape.dart';

/// A box in pixels.
typedef PBox = (double, double, double, double, double, double);

/// `Block.box(x0, y0, z0, x1, y1, z1)`.
PBox pbox(double x0, double y0, double z0, double x1, double y1, double z1) => (x0, y0, z0, x1, y1, z1);

/// A `VoxelShape` as a union of pixel boxes.
final class VShape {
  final List<PBox> boxes;

  const VShape(this.boxes);

  static const VShape empty = VShape([]);

  /// `Shapes.or(this, others)`.
  VShape or(VShape other) => VShape([...boxes, ...other.boxes]);

  /// `Shapes.join(this, cut, BooleanOp.ONLY_FIRST)`.
  VShape minus(VShape cut) {
    var result = boxes;
    for (final c in cut.boxes) {
      final next = <PBox>[];
      for (final b in result) {
        next.addAll(_subtract(b, c));
      }
      result = next;
    }
    return VShape(result);
  }

  static List<PBox> _subtract(PBox a, PBox c) {
    final x0 = a.$1 > c.$1 ? a.$1 : c.$1, x1 = a.$4 < c.$4 ? a.$4 : c.$4;
    final y0 = a.$2 > c.$2 ? a.$2 : c.$2, y1 = a.$5 < c.$5 ? a.$5 : c.$5;
    final z0 = a.$3 > c.$3 ? a.$3 : c.$3, z1 = a.$6 < c.$6 ? a.$6 : c.$6;
    if (x0 >= x1 || y0 >= y1 || z0 >= z1) return [a];
    final out = <PBox>[];
    if (a.$1 < x0) out.add((a.$1, a.$2, a.$3, x0, a.$5, a.$6));
    if (x1 < a.$4) out.add((x1, a.$2, a.$3, a.$4, a.$5, a.$6));
    if (a.$2 < y0) out.add((x0, a.$2, a.$3, x1, y0, a.$6));
    if (y1 < a.$5) out.add((x0, y1, a.$3, x1, a.$5, a.$6));
    if (a.$3 < z0) out.add((x0, y0, a.$3, x1, y1, z0));
    if (z1 < a.$6) out.add((x0, y0, z1, x1, y1, a.$6));
    return out;
  }

  /// `optimize()`: merges the boxes into as few as a greedy decomposition of the occupied cells
  /// gives.
  VShape optimize() {
    if (boxes.length < 2) return this;
    final xs = <double>{}, ys = <double>{}, zs = <double>{};
    for (final b in boxes) {
      xs..add(b.$1)..add(b.$4);
      ys..add(b.$2)..add(b.$5);
      zs..add(b.$3)..add(b.$6);
    }
    final xl = xs.toList()..sort(), yl = ys.toList()..sort(), zl = zs.toList()..sort();
    final nx = xl.length - 1, ny = yl.length - 1, nz = zl.length - 1;
    final cells = List<bool>.filled(nx * ny * nz, false);
    int idx(int x, int y, int z) => (y * nz + z) * nx + x;
    int index(List<double> l, double v) => l.indexOf(v);
    for (final b in boxes) {
      for (var y = index(yl, b.$2); y < index(yl, b.$5); y++) {
        for (var z = index(zl, b.$3); z < index(zl, b.$6); z++) {
          for (var x = index(xl, b.$1); x < index(xl, b.$4); x++) {
            cells[idx(x, y, z)] = true;
          }
        }
      }
    }
    final out = <PBox>[];
    for (var y = 0; y < ny; y++) {
      for (var z = 0; z < nz; z++) {
        for (var x = 0; x < nx; x++) {
          if (!cells[idx(x, y, z)]) continue;
          var ex = x;
          while (ex + 1 < nx && cells[idx(ex + 1, y, z)]) {
            ex++;
          }
          var ez = z;
          bool rowFull(int zz) {
            for (var xx = x; xx <= ex; xx++) {
              if (!cells[idx(xx, y, zz)]) return false;
            }
            return true;
          }

          while (ez + 1 < nz && rowFull(ez + 1)) {
            ez++;
          }
          var ey = y;
          bool layerFull(int yy) {
            for (var zz = z; zz <= ez; zz++) {
              for (var xx = x; xx <= ex; xx++) {
                if (!cells[idx(xx, yy, zz)]) return false;
              }
            }
            return true;
          }

          while (ey + 1 < ny && layerFull(ey + 1)) {
            ey++;
          }
          for (var yy = y; yy <= ey; yy++) {
            for (var zz = z; zz <= ez; zz++) {
              for (var xx = x; xx <= ex; xx++) {
                cells[idx(xx, yy, zz)] = false;
              }
            }
          }
          out.add((xl[x], yl[y], zl[z], xl[ex + 1], yl[ey + 1], zl[ez + 1]));
        }
      }
    }
    return VShape(out);
  }

  /// The boxes in block units.
  List<BlockBox> toBlockBoxes() => [
    for (final b in boxes) BlockBox(b.$1 / 16, b.$2 / 16, b.$3 / 16, b.$4 / 16, b.$5 / 16, b.$6 / 16),
  ];

  /// `VoxelShaper` rotation: the shape, defined facing [from], turned to face [to] about the block
  /// centre (clockwise quarter turns from `from` to `to`, seen from above).
  VShape rotated(Direction from, Direction to) {
    var turns = 0;
    var d = from;
    while (d != to && turns < 4) {
      d = d.clockWise;
      turns++;
    }
    if (turns == 0) return this;
    PBox turn(PBox b) {
      var p0 = (b.$1 - 8, b.$3 - 8), p1 = (b.$4 - 8, b.$6 - 8);
      for (var i = 0; i < turns; i++) {
        p0 = (-p0.$2, p0.$1);
        p1 = (-p1.$2, p1.$1);
      }
      final xa = p0.$1 + 8, xb = p1.$1 + 8, za = p0.$2 + 8, zb = p1.$2 + 8;
      return (xa < xb ? xa : xb, b.$2, za < zb ? za : zb, xa < xb ? xb : xa, b.$5, za < zb ? zb : za);
    }

    return VShape([for (final b in boxes) turn(b)]);
  }
}

/// `TrackVoxelShapes`.
abstract final class TrackVoxelShapes {
  static VShape orthogonal() => VShape([pbox(-14, 0, 0, 16 + 14, 4, 16)]);

  static VShape longOrthogonalX() => VShape([pbox(-3.3, 0, -14, 19.3, 4, 16 + 14)]);

  static VShape longOrthogonalZ() => VShape([pbox(-14, 0, -3.3, 16 + 14, 4, 19.3)]);

  static VShape longOrthogonalZOffset() => VShape([pbox(-14, 0, 0, 16 + 14, 4, 24)]);

  static VShape ascending() {
    final shapes = <PBox>[pbox(-14, 0, 0, 16 + 14, 4, 4)];
    for (var i = 0; i < 6; i++) {
      final off = (i + 1) * 2.0;
      shapes.add(pbox(-14, off, off, 16 + 14, 4 + off, 4 + off));
    }
    return VShape(shapes);
  }

  static VShape diagonal() {
    var shape = VShape([pbox(0, 0, 0, 16, 4, 16)]);
    final shapes = <PBox>[];
    for (var i = 0; i < 6; i++) {
      final off = (i + 1) * 2.0;
      shapes.add(pbox(off, 0, off, 16 + off, 4, 16 + off));
      shapes.add(pbox(-off, 0, -off, 16 - off, 4, 16 - off));
    }
    shape = shape.or(VShape(shapes));

    var off = 10 * 2.0;
    shape = shape.minus(VShape([pbox(off, 0, off, 16 + off, 4, 16 + off)]));
    shape = shape.minus(VShape([pbox(-off, 0, -off, 16 - off, 4, 16 - off)]));

    off = 4 * 2.0;
    shape = shape.or(VShape([pbox(off, 0, off, 16 + off, 4, 16 + off)]));
    shape = shape.or(VShape([pbox(-off, 0, -off, 16 - off, 4, 16 - off)]));
    return shape.optimize();
  }
}

/// `AllShapes.TRACK_*`.
abstract final class TrackShapes {
  /// `TRACK_ORTHO = shape(orthogonal()).forHorizontal(NORTH)`.
  static VShape trackOrtho(Direction d) => TrackVoxelShapes.orthogonal().rotated(Direction.north, d);

  /// `TRACK_ASC = shape(ascending()).forHorizontal(SOUTH)`.
  static VShape trackAsc(Direction d) => TrackVoxelShapes.ascending().rotated(Direction.south, d);

  /// `TRACK_DIAG = shape(diagonal()).forHorizontal(SOUTH)`.
  static VShape trackDiag(Direction d) => TrackVoxelShapes.diagonal().rotated(Direction.south, d);

  /// `TRACK_ORTHO_LONG = shape(longOrthogonalZOffset()).forHorizontal(SOUTH)`.
  static VShape trackOrthoLong(Direction d) => TrackVoxelShapes.longOrthogonalZOffset().rotated(Direction.south, d);

  /// `TRACK_CROSS`.
  static VShape get trackCross => trackOrtho(Direction.south).or(trackOrtho(Direction.east));

  /// `TRACK_CROSS_DIAG`.
  static VShape get trackCrossDiag => trackDiag(Direction.south).or(trackDiag(Direction.east));

  /// `TRACK_CROSS_ORTHO_DIAG = shape(DIAG.SOUTH).add(ORTHO.EAST).forHorizontal(SOUTH)`.
  static VShape trackCrossOrthoDiag(Direction d) =>
      trackDiag(Direction.south).or(trackOrtho(Direction.east)).rotated(Direction.south, d);

  /// `TRACK_CROSS_DIAG_ORTHO = shape(DIAG.SOUTH).add(ORTHO.SOUTH).forHorizontal(SOUTH)`.
  static VShape trackCrossDiagOrtho(Direction d) =>
      trackDiag(Direction.south).or(trackOrtho(Direction.south)).rotated(Direction.south, d);

  /// `TRACK_COLLISION`.
  static final VShape trackCollision = VShape([pbox(0, 0, 0, 16, 2, 16)]);

  /// `TRACK_FALLBACK`.
  static final VShape trackFallback = VShape([pbox(0, 0, 0, 16, 4, 16)]);

  /// `TrackBlock.getFullShape(state)`.
  static VShape fullShape(TrackShape shape) {
    switch (shape) {
      case TrackShape.ae:
        return trackAsc(Direction.east);
      case TrackShape.aw:
        return trackAsc(Direction.west);
      case TrackShape.an:
        return trackAsc(Direction.north);
      case TrackShape.as_:
        return trackAsc(Direction.south);
      case TrackShape.crD:
        return trackCrossDiag;
      case TrackShape.crNdx:
        return trackCrossOrthoDiag(Direction.south);
      case TrackShape.crNdz:
        return trackCrossDiagOrtho(Direction.south);
      case TrackShape.crO:
        return trackCross;
      case TrackShape.crPdx:
        return trackCrossDiagOrtho(Direction.east);
      case TrackShape.crPdz:
        return trackCrossOrthoDiag(Direction.east);
      case TrackShape.nd:
        return trackDiag(Direction.south);
      case TrackShape.pd:
        return trackDiag(Direction.east);
      case TrackShape.xo:
        return trackOrtho(Direction.east);
      case TrackShape.zo:
        return trackOrtho(Direction.south);
      case TrackShape.te:
        return trackOrthoLong(Direction.east);
      case TrackShape.tw:
        return trackOrthoLong(Direction.west);
      case TrackShape.ts:
        return trackOrthoLong(Direction.south);
      case TrackShape.tn:
        return trackOrthoLong(Direction.north);
      case TrackShape.none:
        return trackFallback;
    }
  }

  /// `TrackBlock.getCollisionShape(state)`.
  static VShape collisionShape(TrackShape shape) {
    switch (shape) {
      case TrackShape.ae:
      case TrackShape.aw:
      case TrackShape.an:
      case TrackShape.as_:
        return VShape.empty;
      default:
        return trackCollision;
    }
  }
}
