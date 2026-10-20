// `dev.ryanhcode.sable.physics.floating_block.FloatingBlockData`: the
// accumulated statistics of one cluster of floating blocks.
//
// A cluster is all the blocks on a sub-level that share one
// [FloatingBlockMaterial]. For those blocks the class tracks
//
// * [weightedPosition] — Σ scaleᵢ·posᵢ,
// * [totalScale] — Σ scaleᵢ,
// * [outerProduct] — the second moment Σ scaleᵢ·posᵢ·posᵢᵀ, which the friction
//   model turns into the cluster's inertia,
// * [blockCount] and the latest pressure scale.
//
// Pure: no host imports.
import '../math/matrix3.dart';
import '../math/vector.dart';
import '../model/sub_level.dart';

/// One cluster's block statistics.
final class FloatingBlockData {
  /// Σ scaleᵢ·posᵢ, in the sub-level's local space.
  final Matrix3d outerProduct = Matrix3d.zero();

  /// Σ scaleᵢ·posᵢ.
  final Vector3d weightedPosition = Vector3d();

  /// Σ scaleᵢ.
  double totalScale = 0.0;

  /// The number of blocks in the cluster.
  int blockCount = 0;

  /// The pressure scale of the last `computePressureScale`.
  double latestPressureScale = 1.0;

  final Matrix3d _tempMassMatrix = Matrix3d();
  final Vector3d _tempPosOffset = Vector3d();

  /// `addFloatingBlock(pos, scale)`.
  void addFloatingBlock(Vector3d pos, double scale) {
    addData(pos, scale);
    blockCount++;
  }

  /// `removeFloatingBlock(pos, scale)`.
  void removeFloatingBlock(Vector3d pos, double scale) {
    blockCount--;
    addData(pos, -scale);
  }

  void addData(Vector3d pos, double scale) {
    weightedPosition.fma(scale, pos);
    totalScale += scale;

    _tempPosOffset.setFrom(pos).fma(-1 / totalScale, weightedPosition);
    if (blockCount > 0) {
      Matrix3d.fmaOuterProduct(
        _tempPosOffset,
        _tempPosOffset,
        scale * totalScale / (totalScale - scale),
        outerProduct,
      );
    }

    outerProduct.add(_tempMassMatrix.makeIdentity().scale(scale / 6.0));
  }

  /// `translateOrigin(nudge)`.
  void translateOrigin(Vector3d nudge) => weightedPosition.fma(totalScale, nudge);

  /// `getPressureScale()`.
  double getPressureScale() => latestPressureScale;

  /// `computePressureScale(subLevel)`: samples the air pressure at the
  /// cluster's centre.
  void computePressureScale(SubLevel subLevel, double Function(Vector3d worldPosition) pressureAt) {
    final position = Vector3d();
    subLevel.logicalPose.orientation().transform(weightedPosition, position);
    subLevel.logicalPose.position().fma(1 / totalScale, position);
    latestPressureScale = pressureAt(position);
  }

  /// The centre of the cluster, in the sub-level's local space.
  Vector3d centerOfCluster([Vector3d? dest]) =>
      (dest ?? Vector3d()).setFrom(weightedPosition).div(totalScale);

  /// The outer product divided by the total scale, i.e. the cluster's average
  /// position matrix.
  Matrix3d averagePositionMatrix([Matrix3d? dest]) =>
      outerProduct.scaleInto(1 / totalScale, dest ?? Matrix3d());

  @override
  String toString() =>
      'FloatingBlockData[blocks=$blockCount, scale=$totalScale, '
      'pos=$weightedPosition, pressure=$latestPressureScale]';
}
