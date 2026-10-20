// `dev.ryanhcode.sable.api.entity.EntitySubLevelUtil`: entity operations around
// sub-levels (old position, kicking out of a plot).
//
// Pure: no host imports.
import 'dart:math' as math;

import '../../model/sub_level.dart';
import '../../math/vector.dart';
import '../sub_level_helper.dart';
import 'sub_level_entity.dart';

/// Utility for operations regarding entities and sub-levels.
abstract final class EntitySubLevelUtil {
  /// The entity types kept inside a sub-level instead of being kicked out
  /// (`SableTags.RETAIN_IN_SUB_LEVEL`); the plugin fills this in from its tag
  /// registry.
  static final Set<String> retainInSubLevel = {};

  /// Resolves the sub-level an entity is standing on
  /// (`Sable.HELPER.getTrackingSubLevel`); `null` when the host has no such
  /// tracking.
  static SubLevel? Function(SubLevelEntity entity)? trackingSubLevelLookup;

  /// Sets the old position of [entity] for no apparent movement, taking the
  /// tracking sub-level into account.
  static void setOldPosNoMovement(SubLevelEntity entity) {
    final trackingSubLevel = trackingSubLevelLookup?.call(entity);

    if (trackingSubLevel != null) {
      final entityPos = entity.position;
      final oldPos = trackingSubLevel.lastPose.transformPosition(
        trackingSubLevel.logicalPose.transformPositionInverse(entityPos),
      );
      entity
        ..xOld = oldPos.x
        ..xo = oldPos.x
        ..yOld = oldPos.y
        ..yo = oldPos.y
        ..zOld = oldPos.z
        ..zo = oldPos.z;
    } else {
      entity
        ..xOld = entity.position.x
        ..xo = entity.position.x
        ..yOld = entity.position.y
        ..yo = entity.position.y
        ..zOld = entity.position.z
        ..zo = entity.position.z;
    }
  }

  /// Kicks [entity] out of [subLevel], including velocity and position.
  static void kickEntity(SubLevel subLevel, SubLevelEntity entity) {
    final subLevelGainedVelo = Vector3d();
    if (entity.isHurtingProjectile && entity.accelerationPower == 0) {
      // The Java code calls this and discards the result; kept as-is so the
      // port does not silently change the projectile kick.
      SubLevelHelper.getVelocity(subLevel.getLevel(), entity.position, subLevelGainedVelo);
    }

    // convert from m/s to m/t
    subLevelGainedVelo.mul(1.0 / 20.0);

    final pos = entity.position;
    var anchor = Vector3d();
    if (entity.isFallingBlock) {
      anchor = Vector3d(0.0, entity.boundingBoxHeight / 2.0, 0.0);
    }

    entity.snapTo(
      subLevel.logicalPose
          .transformPosition(Vector3d.copy(pos).add(anchor))
          .sub(anchor),
    );
    entity.deltaMovement = subLevel.logicalPose
        .transformNormal(entity.deltaMovement)
        .add(subLevelGainedVelo);
    entity.lookAtFeet(
      subLevel.logicalPose.transformNormal(entity.lookAngle).add(entity.position),
    );

    // Arrows use an incorrect Y and X rotation
    if (entity.isArrow) {
      final deltaMovement = entity.deltaMovement;
      final horizontal = math.sqrt(
        deltaMovement.x * deltaMovement.x + deltaMovement.z * deltaMovement.z,
      );
      entity.yRot = math.atan2(deltaMovement.x, deltaMovement.z) * 180.0 / math.pi;
      entity.xRot = math.atan2(deltaMovement.y, horizontal) * 180.0 / math.pi;
    }
  }

  /// Whether [entity] should be kicked out of a sub-level.
  static bool shouldKick(SubLevelEntity entity) => !retainInSubLevel.contains(entity.typeId);

  /// A custom orientation for [entity], if any (`null` for none).
  static Quaterniond? getCustomEntityOrientation(SubLevelEntity entity, double partialTicks) =>
      null;

  /// Whether [entity] has a custom orientation.
  static bool hasCustomEntityOrientation(SubLevelEntity entity) => false;
}
