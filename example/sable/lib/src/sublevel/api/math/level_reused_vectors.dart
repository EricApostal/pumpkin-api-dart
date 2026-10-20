// `dev.ryanhcode.sable.api.math.LevelReusedVectors`: mutable scratch vectors for
// the OBB SAT calculations, reused to avoid allocating per collision.
//
// Pure: no host imports.
//
// create's positions are not exported from its public barrel yet, so they are
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;

import '../../math/bounding_box.dart';
import '../../math/pose.dart';
import '../../math/vector.dart';

/// The mutability optimization vectors of one level's collision pass.
final class LevelReusedVectors {
  /// `Shapes.create(new AABB(0, 15/16, 0, 1, 1, 1))`, the scaffolding top shape.
  final List<BlockBox> scaffoldingTop = const [
    BlockBox(0.0, 15.0 / 16.0, 0.0, 1.0, 1.0, 1.0),
  ];

  final Vector3d tempVert6 = Vector3d();
  final Vector3d tempVert5 = Vector3d();
  final Vector3d tempVert4 = Vector3d();
  final Vector3d tempVert3 = Vector3d();
  final Vector3d tempVert2 = Vector3d();
  final Vector3d tempVert1 = Vector3d();

  final Vector3d zero = Vector3d();
  final Vector2d proj1 = Vector2d();
  final Vector2d proj2 = Vector2d();
  final Vector3d oppo = Vector3d();
  final Vector3d obbARight = Vector3d();
  final Vector3d obbAForward = Vector3d();
  final Vector3d obbAUp = Vector3d();
  final Vector3d obbBRight = Vector3d();
  final Vector3d obbBForward = Vector3d();
  final Vector3d obbBUp = Vector3d();
  final Vector3d checker = Vector3d();

  /// `BlockPos.MutableBlockPos`; Dart records are immutable, so these are
  /// reassigned instead of mutated.
  Pos minPos = (0, 0, 0);
  Pos maxPos = (0, 0, 0);
  Pos maxBlockPos = (0, 0, 0);
  Pos offsetPos = (0, 0, 0);

  final BoundingBox3d fullContextBounds = BoundingBox3d();
  final BoundingBox3d rotatedContextBounds = BoundingBox3d();
  final BoundingBox3d considerationBounds = BoundingBox3d();
  final BoundingBox3d localBounds = BoundingBox3d();
  final BoundingBox3d localBounds2 = BoundingBox3d();
  final Vector3d collisionMotion = Vector3d();
  final Vector3d velocityMotion = Vector3d();
  final Vector3d entityBoundsCenter = Vector3d();
  final Vector3d stepHeightEntityBoundsCenter = Vector3d();
  final Vector3d lastStepTestMTV = Vector3d();
  final Vector3d entityPosition = Vector3d();
  final Vector3d posMinusCenter = Vector3d();
  final Vector3d trackingPosition = Vector3d();
  final Pose3d lastPose = Pose3d();
  final Pose3d lastSubLevelPose = Pose3d();
  final Pose3d subLevelPose = Pose3d();
  final Matrix4d bakedMatrix = Matrix4d();
  final Vector3d mtv = Vector3d();
  final Vector3d normalizedMtv = Vector3d();
  final Vector3d localMtv = Vector3d();
  final Vector3d existingDeltaMovement = Vector3d();
  final Vector3d maxMTV = Vector3d();
  final BoundingBox3d maxAABB = BoundingBox3d();
  final Vector3d center = Vector3d();
  final BoundingBox3d offsetAABB = BoundingBox3d();
  final BoundingBox3d compressedMinAABB = BoundingBox3d();
  final BoundingBox3d compressedOffsetAABB = BoundingBox3d();
  final BoundingBox3d intersection = BoundingBox3d();

  final Quaterniond entityBoxOrientation = Quaterniond();
  final Quaterniond entityCustomOrientation = Quaterniond();
  final Vector3d tempEyePosition = Vector3d();
  final Vector3d anchorRelativePosition = Vector3d();

  final List<Vector3d> a = List.generate(8, (_) => Vector3d());
  final List<Vector3d> b = List.generate(8, (_) => Vector3d());
  final List<Vector3d> checks = List.generate(15, (_) => Vector3d());

  final Vector3d tempmin = Vector3d();
  final Vector3d tempmax = Vector3d();
  final Vector3d entityUpDirection = Vector3d();
  final Vector3d entityDownDirection = Vector3d();

  final Vector3d hitNormal = Vector3d();
  final Vector3d overlapNormal = Vector3d();
  final Vector3d exitNormal = Vector3d();
  final Vector3d relativePos = Vector3d();
}
