// `dev.ryanhcode.sable.api.physics.callback.BlockSubLevelCollisionCallback`:
// the per-block-state hook the physics pipeline calls for every contact.
//
// Pure: no host imports.
//
// create's positions are not exported from its public barrel yet, so they are
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;

import '../../../math/vector.dart';

/// The result of a collision callback.
final class CollisionResult {
  /// The tangent motion the block imparts, in m/s.
  final Vector3d tangentMotion;

  /// Whether the collision should be ignored (the block broke).
  final bool removeCollision;

  CollisionResult(this.tangentMotion, this.removeCollision);

  /// `CollisionResult.NONE`.
  static final CollisionResult none = CollisionResult(Vector3d(), false);
}

/// A collision callback attached to a block state.
abstract interface class BlockSubLevelCollisionCallback {
  /// Called from the pipeline for every contact.
  ///
  /// Returns `[x, y, z, remove ? 1.0 : 0.0]`, the shape the Java code hands
  /// back over JNI.
  List<double> onCollision(
    int x,
    int y,
    int z,
    int otherX,
    int otherY,
    int otherZ,
    double x1,
    double y1,
    double z1,
    double impactVelocity,
    bool hasOtherBlock,
  ) {
    final result = sable$onCollision(
      (x, y, z),
      hasOtherBlock ? (otherX, otherY, otherZ) : null,
      Vector3d(x1, y1, z1),
      impactVelocity,
    );
    final motion = result.tangentMotion;
    return [motion.x, motion.y, motion.z, result.removeCollision ? 1.0 : 0.0];
  }

  /// Called when a collision occurs between two blocks.
  ///
  /// [hitBlockPos] is the block this callback is on; [otherHitBlockPos] is the
  /// other block when the other body is a sub-level; [impactPosition] is in the
  /// plot of the hit sub-level (or in global coordinates when a sub-level does
  /// not contain the block); [impactVelocity] is the velocity along the normal.
  CollisionResult sable$onCollision(
    Pos hitBlockPos,
    Pos? otherHitBlockPos,
    Vector3d impactPosition,
    double impactVelocity,
  );
}
