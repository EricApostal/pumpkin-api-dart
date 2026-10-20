// `dev.ryanhcode.sable.api.block.BlockSubLevelLiftProvider`: blocks that produce
// lift and drag (sails, balloons, ...).
//
// The contribution is a direct port of the Java default method, including the
// shared scratch vectors and the (deliberately) negative impulse signs.
//
// Pure: no host imports.
//
// create's positions are not exported from its public barrel yet, so they are
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;

import '../../model/server_sub_level.dart';
import '../../math/pose.dart';
import '../../math/vector.dart';
import '../../physics/dimension_physics.dart';

/// A lift provider: a block that produces lift and drag inside a sub-level.
abstract interface class BlockSubLevelLiftProvider {
  /// `Direction.values()`, in the Java order.
  static const List<Direction> directions = Direction.values;

  // Memory optimization: the Java interface keeps these as static scratch
  // vectors shared by every provider on the physics thread.
  static final Vector3d liftForce = Vector3d();
  static final Vector3d liftPos = Vector3d();
  static final Vector3d liftNormal = Vector3d();
  static final Vector3d liftVelo = Vector3d();
  static final Vector3d drag = Vector3d();
  static final Vector3d temp = Vector3d();

  /// Resets the scratch vectors.
  static void resetVectors() {
    liftVelo.zero();
    liftPos.zero();
    liftForce.zero();
    liftNormal.zero();
    drag.zero();
  }

  /// Groups the lift providers into 6-connected clusters.
  static List<LiftProviderGroup> groupLiftProviders(
    Iterable<LiftProviderContext> liftProviders,
  ) {
    final groups = <LiftProviderGroup>[];
    final positions = <Pos>{for (final provider in liftProviders) provider.pos};

    while (positions.isNotEmpty) {
      final groupBlocks = <Pos>{};
      final toVisit = <Pos>[positions.first];

      while (toVisit.isNotEmpty) {
        final pos = toVisit.removeLast();
        if (groupBlocks.contains(pos)) continue;

        groupBlocks.add(pos);
        positions.remove(pos);

        for (final direction in directions) {
          final offset = (pos.$1 + direction.stepX, pos.$2 + direction.stepY, pos.$3 + direction.stepZ);
          if (positions.contains(offset)) toVisit.add(offset);
        }
      }

      groups.add(LiftProviderGroup(groupBlocks));
    }

    return groups;
  }

  /// The normal of this lift provider.
  Direction sable$getNormal(BState state);

  /// The default of [sable$getParallelDragScalar].
  static const double defaultParallelDragScalar = 0.75;

  /// The default of [sable$getDirectionlessDragScalar].
  static const double defaultDirectionlessDragScalar = 0.06888202261;

  /// The default of [sable$getLiftScalar].
  static const double defaultLiftScalar = 0.475;

  /// How effective this provider is at producing drag parallel to the normal.
  double sable$getParallelDragScalar() => defaultParallelDragScalar;

  /// How effective this provider is at producing directionless drag.
  ///
  /// Should be at least `(-k1 + sqrt(k1^2 + k2^2)) / 2` to prevent exponential
  /// velocity gain, where `k1` is the parallel drag and `k2` the lift scalar.
  double sable$getDirectionlessDragScalar() => defaultDirectionlessDragScalar;

  /// How effective this provider is at producing lift.
  double sable$getLiftScalar() => defaultLiftScalar;

  /// Called once per **physics** tick while on [subLevel].
  ///
  /// The default contribution is [contributeLiftAndDrag]; implementers that
  /// override it can still call that helper.
  void sable$contributeLiftAndDrag(
    LiftProviderContext ctx,
    ServerSubLevel subLevel,
    Pose3d? localPose,
    double timeStep,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
    Vector3d linearImpulse,
    Vector3d angularImpulse, [
    LiftProviderGroup? group,
  ]) => contributeLiftAndDrag(
    this,
    ctx,
    subLevel,
    localPose,
    timeStep,
    linearVelocity,
    angularVelocity,
    linearImpulse,
    angularImpulse,
    group,
  );

  /// Called once per **physics** tick while on [subLevel].
  static void contributeLiftAndDrag(
    BlockSubLevelLiftProvider provider,
    LiftProviderContext ctx,
    ServerSubLevel subLevel,
    Pose3d? localPose,
    double timeStep,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
    Vector3d linearImpulse,
    Vector3d angularImpulse, [
    LiftProviderGroup? group,
  ]) {
    resetVectors();
    liftNormal.set(ctx.dir.x, ctx.dir.y, ctx.dir.z);
    liftPos.set(ctx.pos.$1 + 0.5, ctx.pos.$2 + 0.5, ctx.pos.$3 + 0.5);

    if (localPose != null) {
      localPose.transformNormal(liftNormal);
      localPose.transformPosition(liftPos);
    }

    final pose = subLevel.logicalPose;
    final pressure = DimensionPhysicsData.getAirPressure(
      subLevel.getLevel(),
      pose.transformPosition(Vector3d.copy(liftPos), temp),
    );

    // TEMP = transformed position relative to the sub-level origin
    pose.transformPosition(Vector3d.copy(liftPos), temp).sub(pose.position());
    liftVelo.setFrom(linearVelocity).add(angularVelocity.cross(temp));
    pose.transformNormalInverse(liftVelo);

    liftForce.zero();

    final parallelDragScalar = provider.sable$getParallelDragScalar();
    if (parallelDragScalar > 0) {
      final dragStrength = liftNormal.dot(liftVelo) * parallelDragScalar * pressure * timeStep;
      final parallelDrag = liftNormal.mulInto(dragStrength, Vector3d());
      liftForce.add(parallelDrag);

      if (group != null) {
        group.totalDrag.sub(parallelDrag);
        group.dragCenter.fma(dragStrength.abs(), liftPos);
        group.totalDragStrength += dragStrength.abs();
      }
    }

    final directionlessDragScalar = provider.sable$getDirectionlessDragScalar();
    if (directionlessDragScalar > 0) {
      final dragStrength = directionlessDragScalar * pressure * timeStep;
      final directionlessDrag = liftVelo.mulInto(dragStrength, Vector3d());
      liftForce.add(directionlessDrag);

      if (group != null) {
        group.totalDrag.sub(directionlessDrag);
        group.dragCenter.fma(directionlessDrag.length, liftPos);
        group.totalDragStrength += directionlessDrag.length;
      }
    }

    final liftScalar = provider.sable$getLiftScalar();
    if (liftScalar > 0) {
      final liftStrength =
          liftVelo.subInto(drag, temp).length * liftScalar * pressure * timeStep;
      final lift = liftNormal.mulInto(liftStrength, Vector3d());
      liftForce.add(lift);

      if (group != null) {
        group.totalLift.sub(lift);
        group.liftCenter.fma(liftStrength.abs(), liftPos);
        group.totalLiftStrength += liftStrength;
      }
    }

    // Why is this all negative of what it should be?
    linearImpulse.sub(liftForce);
    liftPos.subInto(subLevel.getMassTracker().getCenterOfMass(), temp);
    angularImpulse.sub(temp.cross(liftForce));
    resetVectors();
  }
}

/// `LiftProviderContext`: the in-world context of one lift provider.
final class LiftProviderContext {
  final Pos pos;
  final BState state;
  final Vector3d dir;

  const LiftProviderContext(this.pos, this.state, this.dir);
}

/// `LiftProviderGroup`: the summed lift/drag of one cluster of providers.
final class LiftProviderGroup {
  final Set<Pos> _positions;
  final Vector3d _totalLift = Vector3d();
  final Vector3d _liftCenter = Vector3d();
  final Vector3d _totalDrag = Vector3d();
  final Vector3d _dragCenter = Vector3d();
  double totalLiftStrength = 0.0;
  double totalDragStrength = 0.0;

  LiftProviderGroup(this._positions);

  /// The blocks of this group.
  Set<Pos> get positions => _positions;

  /// The summed lift.
  Vector3d get totalLift => _totalLift;

  /// The lift-weighted centre.
  Vector3d get liftCenter => _liftCenter;

  /// The summed drag.
  Vector3d get totalDrag => _totalDrag;

  /// The drag-weighted centre.
  Vector3d get dragCenter => _dragCenter;
}
