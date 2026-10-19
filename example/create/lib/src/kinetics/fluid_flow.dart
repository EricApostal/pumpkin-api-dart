// Fluid flow vectors and the water wheel's flow score (pure). The host reports
// fluid states but not the flow direction, so `FlowingFluid.getFlow` is computed
// here from the heights of the neighbouring fluids, like vanilla does.
import 'dart:math' as math;

import 'geometry.dart';

/// A fluid at a position.
final class FluidInfo {
  /// The still fluid key (`minecraft:water`), `null` for no fluid.
  final String? fluid;

  /// The amount: 8 for a source and falling fluid, 1 for the thinnest flow.
  final int level;
  final bool isSource;
  final bool isFalling;

  const FluidInfo(this.fluid, this.level, {this.isSource = false, this.isFalling = false});

  static const FluidInfo empty = FluidInfo(null, 0);

  bool get isEmpty => fluid == null;

  /// `FluidState.getOwnHeight()`.
  double get ownHeight => level / 9.0;
}

/// A 3D vector (just what the flow maths needs).
final class Vec {
  final double x;
  final double y;
  final double z;

  const Vec(this.x, this.y, this.z);

  static const Vec zero = Vec(0, 0, 0);

  Vec operator +(Vec o) => Vec(x + o.x, y + o.y, z + o.z);
  Vec multiply(Vec o) => Vec(x * o.x, y * o.y, z * o.z);
  Vec scale(double f) => Vec(x * f, y * f, z * f);
  double dot(Vec o) => x * o.x + y * o.y + z * o.z;
  double get lengthSqr => x * x + y * y + z * z;

  /// `Vec3.normalize()`: zero below 1e-5.
  Vec normalize() {
    final d = math.sqrt(lengthSqr);
    return d < 1.0E-5 ? Vec.zero : Vec(x / d, y / d, z / d);
  }

  /// `VecHelper.rotate(vec, 90, axis)`.
  Vec rotate90(KAxis axis) => switch (axis) {
    KAxis.x => Vec(x, -z, y),
    KAxis.y => Vec(z, y, -x),
    KAxis.z => Vec(-y, x, z),
  };

  @override
  String toString() => 'Vec($x, $y, $z)';
}

/// The world as the flow maths sees it.
abstract interface class FluidWorldView {
  FluidInfo fluidAt(int x, int y, int z);

  /// `BlockState.blocksMotion()`.
  bool blocksMotion(int x, int y, int z);

  /// `BlockState.isFaceSturdy(level, pos, direction)`.
  bool isFaceSturdy(int x, int y, int z, Dir face);

  /// The block key at the position (for bubble columns, ice).
  String blockAt(int x, int y, int z);

  /// The `drag` property of a bubble column.
  bool bubbleColumnDragDown(int x, int y, int z);
}

abstract final class FluidFlow {
  /// `FlowingFluid.getFlow(level, pos, state)` for the fluid at ([x],[y],[z]).
  static Vec flowVector(FluidWorldView w, int x, int y, int z) {
    final state = w.fluidAt(x, y, z);
    if (state.isEmpty) return Vec.zero;

    bool affectsFlow(FluidInfo other) => other.isEmpty || other.fluid == state.fluid;

    var flowX = 0.0;
    var flowZ = 0.0;
    for (final dir in Dir.values.where((d) => d.isHorizontal)) {
      final nx = x + dir.dx;
      final nz = z + dir.dz;
      final neighbour = w.fluidAt(nx, y, nz);
      if (!affectsFlow(neighbour)) continue;
      var neighbourHeight = neighbour.ownHeight;
      var f = 0.0;
      if (neighbourHeight == 0) {
        if (!w.blocksMotion(nx, y, nz)) {
          final below = w.fluidAt(nx, y - 1, nz);
          if (affectsFlow(below)) {
            neighbourHeight = below.ownHeight;
            if (neighbourHeight > 0) f = state.ownHeight - (neighbourHeight - 0.8888889);
          }
        }
      } else if (neighbourHeight > 0) {
        f = state.ownHeight - neighbourHeight;
      }
      if (f != 0) {
        flowX += dir.dx * f;
        flowZ += dir.dz * f;
      }
    }

    var flow = Vec(flowX, 0, flowZ);
    if (state.isFalling) {
      for (final dir in Dir.values.where((d) => d.isHorizontal)) {
        final nx = x + dir.dx;
        final nz = z + dir.dz;
        if (_isSolidFace(w, state, nx, y, nz, dir) || _isSolidFace(w, state, nx, y + 1, nz, dir)) {
          flow = flow.normalize() + const Vec(0, -6, 0);
          break;
        }
      }
    }
    return flow.normalize();
  }

  static bool _isSolidFace(FluidWorldView w, FluidInfo self, int x, int y, int z, Dir direction) {
    final fluid = w.fluidAt(x, y, z);
    if (!fluid.isEmpty && fluid.fluid == self.fluid) return false;
    if (direction == Dir.up) return true;
    final block = w.blockAt(x, y, z);
    if (block == 'minecraft:ice' || block == 'minecraft:frosted_ice') return false; // IceBlock
    return w.isFaceSturdy(x, y, z, direction);
  }

  /// `WaterWheelBlockEntity.getFlowVectorAtPosition`: bubble columns push up or down.
  static Vec flowAtPosition(FluidWorldView w, int x, int y, int z) {
    if (w.blockAt(x, y, z) == 'minecraft:bubble_column') {
      return Vec(0, w.bubbleColumnDragDown(x, y, z) ? -1 : 1, 0);
    }
    return flowVector(w, x, y, z);
  }
}

/// The offsets a water wheel looks at (`SMALL_OFFSETS` / `LARGE_OFFSETS`).
abstract final class WaterWheelOffsets {
  static final Map<KAxis, List<KPos>> small = {for (final a in KAxis.values) a: _small(a)};
  static final Map<KAxis, List<KPos>> large = {for (final a in KAxis.values) a: _large(a)};

  static List<KPos> _small(KAxis axis) => [
    for (final d in Dir.values)
      if (d.axis != axis) KPos.zero.relative(d),
  ];

  static List<KPos> _large(KAxis axis) {
    final offsets = <KPos>{};
    for (final d in Dir.values) {
      if (d.axis == axis) continue;
      final central = KPos.zero.relative(d, 2);
      offsets.add(central);
      for (final d2 in Dir.values) {
        if (d2.axis == axis) continue;
        if (d2.axis == d.axis) continue;
        offsets.add(central.relative(d2));
      }
    }
    return offsets.toList();
  }
}

/// `WaterWheelBlockEntity.determineAndApplyFlowScore` without the side effects:
/// the flow score of a wheel of [axis] at ([x],[y],[z]) and whether it touches lava.
({int score, bool lava}) waterWheelFlowScore(
  FluidWorldView w,
  int x,
  int y,
  int z,
  KAxis axis,
  int size, {
  bool Function(String fluid)? isLava,
}) {
  final unit = axis.positive;
  final plane = Vec(1 - unit.dx.toDouble(), 1 - unit.dy.toDouble(), 1 - unit.dz.toDouble());
  final offsets = size == 1 ? WaterWheelOffsets.small[axis]! : WaterWheelOffsets.large[axis]!;

  var score = 0;
  var lava = false;
  for (final o in offsets) {
    final tx = x + o.x;
    final ty = y + o.y;
    final tz = z + o.z;
    var flowAtPos = FluidFlow.flowAtPosition(w, tx, ty, tz).multiply(plane);
    final f = w.fluidAt(tx, ty, tz).fluid;
    if (f != null && (isLava?.call(f) ?? f == 'minecraft:lava')) lava = true;

    if (flowAtPos.lengthSqr == 0) continue;

    flowAtPos = flowAtPos.normalize();
    final normal = Vec(o.x.toDouble(), o.y.toDouble(), o.z.toDouble()).normalize();

    final positiveMotion = normal.rotate90(axis);
    final dot = flowAtPos.dot(positiveMotion);
    if (dot.abs() > .5) score += dot.sign.toInt();
  }
  return (score: score, lava: lava);
}
