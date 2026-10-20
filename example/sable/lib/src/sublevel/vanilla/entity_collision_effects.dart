// Standing on a sub-level: the two checks vanilla does before it lets an entity
// move, and what happens when a moving entity runs into a ship.
//
// The host clips entity motion against the boxes the plugin publishes
// (`entity-collision`), so the *sweep* is not here. What is here is the part
// the host cannot know about: whether the block under an entity is a ship
// block, and how much of the ship's velocity the entity inherits.
//
// Java: dev.ryanhcode.sable.mixinhelper.CanFallAtleastHelper
// Java: dev.ryanhcode.sable.mixin.entity.entity_sublevel_collision.PlayerMixin
// Java: dev.ryanhcode.sable.mixin.entity.entity_sublevel_collision.LivingEntityMixin
// Java: dev.ryanhcode.sable.mixin.player_standup.PlayerMixin
//
// Pure: no host imports.
import 'dart:math' as math;

import '../api/math/level_reused_vectors.dart';
import '../api/math/oriented_bounding_box.dart';
import '../entity/sub_level_entity_collision.dart';
import '../math/bounding_box.dart';
import '../math/pose.dart';
import '../math/vector.dart';
import '../model/sub_level.dart';

/// The collision boxes of one block of a sub-level, in plot coordinates.
typedef SubLevelBlockShapes = Iterable<BoundingBox3dc> Function(
  SubLevel subLevel,
  (int, int, int) plotBlock,
);

/// Queries that answer "is there a ship block here?".
abstract final class SubLevelStanding {
  /// `canFallAtleastWithSubLevels`: the first separating axis found between the
  /// entity's box and a ship block below it, or `null` when there is nothing
  /// there.
  ///
  /// Vanilla uses this for "would I walk off the edge", "can I stand up" and
  /// "can I fall at least N blocks": a non-null result means there *is* a block,
  /// i.e. the movement is blocked.
  ///
  /// The entity's box is compared against every sub-level it overlaps, using the
  /// sub-level's *last* pose (the pose vanilla used for the tick), and the
  /// entity's own box is rotated to the ship's nearest grid orientation so a
  /// player on a tilted deck is tested as an axis-aligned box on that deck.
  static Vector3d? canFallAtLeast({
    required BoundingBox3dc entityBox,
    required Iterable<SubLevel> subLevels,
    required SubLevelBlockShapes shapesAt,
    LevelReusedVectors? sink,
  }) {
    final scratch = sink ?? LevelReusedVectors();
    final considerationBounds = BoundingBox3d.copy(entityBox).expand(1.05);

    final entityOrientation = Quaterniond();
    final entityBounds = OrientedBoundingBox3d(scratch);
    final cube = OrientedBoundingBox3d(scratch);

    for (final subLevel in subLevels) {
      final pose = subLevel.lastPose;
      if (!subLevel.boundingBox.intersects(considerationBounds)) continue;

      final localBounds = BoundingBox3d.copy(entityBox)
        ..expand3(-0.05, 0.0, -0.05)
        ..transformInverse(pose);
      localBounds.minY -= 1.0;

      final minX = localBounds.minX.floor();
      final minY = (localBounds.minY - 1.0).floor();
      final minZ = localBounds.minZ.floor();
      final maxX = localBounds.maxX.floor();
      final maxY = localBounds.maxY.floor();
      final maxZ = localBounds.maxZ.floor();

      entityOrientation
        ..identity()
        ..rotateY(SubLevelEntityCollision.getHitBoxYaw(pose));
      entityBounds.set(
        Vector3d(
          (entityBox.minX + entityBox.maxX) / 2.0,
          (entityBox.minY + entityBox.maxY) / 2.0,
          (entityBox.minZ + entityBox.maxZ) / 2.0,
        ),
        Vector3d(
          (entityBox.maxX - entityBox.minX) - 0.1,
          entityBox.maxY - entityBox.minY,
          (entityBox.maxZ - entityBox.minZ) - 0.1,
        ),
        entityOrientation,
      );

      cube.setOrientation(pose.orientation());

      for (var y = minY; y <= maxY; y++) {
        for (var x = minX; x <= maxX; x++) {
          for (var z = minZ; z <= maxZ; z++) {
            for (final box in shapesAt(subLevel, (x, y, z))) {
              final centre = box.center();
              final position = Vector3d(
                x + centre.x,
                y + centre.y,
                z + centre.z,
              );
              pose.transformPosition(position, position);
              final size = box.size();
              cube
                ..setPosition(position)
                ..setDimensions(size);

              final result = OrientedBoundingBox3d.satInto(
                entityBounds,
                cube,
                Vector3d(),
              );
              if (result.lengthSquared > 0.0) return result;
            }
          }
        }
      }
    }

    return null;
  }

  /// `PlayerMixin#sable$maybeBackOffFromEdge`: before a player walks, vanilla
  /// pulls the movement back so the player does not step off a ledge. On a ship
  /// the "ledge" is a ship block, so the movement is reduced in the ship's yaw
  /// frame.
  ///
  /// [pose] is the tracking sub-level's last pose. [wouldSlideOff] is
  /// [wouldSlideOff] below, bound to the player's box and the sub-levels.
  ///
  /// Returns the movement to use, or `null` when vanilla's own result stands.
  static Vector3d? backOffFromEdge({
    required Vector3d movement,
    required Pose3dc pose,
    required bool flying,
    required bool stayingOnGroundSurface,
    required bool aboveGround,
    required bool Function(double localX, double localZ, Quaterniond frame)
    wouldSlideOff,
    double step = 0.05,
  }) {
    if (flying) return null;
    if (movement.y > 0.0) return null;
    if (!stayingOnGroundSurface || !aboveGround) return null;

    final forward = pose.orientation().transform(
      Vector3d(0.0, 0.0, 1.0),
      Vector3d(),
    );
    final yaw = math.atan2(forward.x, forward.z);
    final frame = Quaterniond()..rotateY(yaw);

    final local = frame.transformInverse(
      Vector3d(movement.x, 0.0, movement.z),
      Vector3d(),
    );
    var xMovement = local.x;
    var zMovement = local.z;

    final signedStep = xMovement.sign * step;
    final zStep = zMovement.sign * step;

    while (xMovement != 0.0 && wouldSlideOff(xMovement, 0.0, frame)) {
      if (xMovement.abs() <= step) {
        xMovement = 0.0;
        break;
      }
      xMovement -= signedStep;
    }

    while (zMovement != 0.0 && wouldSlideOff(0.0, zMovement, frame)) {
      if (zMovement.abs() <= step) {
        zMovement = 0.0;
        break;
      }
      zMovement -= zStep;
    }

    while (xMovement != 0.0 &&
        zMovement != 0.0 &&
        wouldSlideOff(xMovement, zMovement, frame)) {
      if (xMovement.abs() <= step) {
        xMovement = 0.0;
      } else {
        xMovement -= signedStep;
      }

      if (zMovement.abs() <= step) {
        zMovement = 0.0;
      } else {
        zMovement -= zStep;
      }
    }

    final global = frame.transform(
      Vector3d(xMovement, 0.0, zMovement),
      Vector3d(),
    );
    return Vector3d(global.x, movement.y, global.z);
  }

  /// `PlayerMixin#sable$wouldSlideOff`: whether the box, moved by the local
  /// movement, has no ship block under it.
  ///
  /// [bounds] is the entity's world bounding box, [fallDistance] the entity's
  /// maximum step height.
  static bool wouldSlideOff({
    required BoundingBox3dc bounds,
    required double localX,
    required double localZ,
    required double fallDistance,
    required Quaterniond frame,
    required Iterable<SubLevel> subLevels,
    required SubLevelBlockShapes shapesAt,
    LevelReusedVectors? sink,
  }) {
    final movement = frame.transform(Vector3d(localX, 0.0, localZ), Vector3d());
    final x = movement.x;
    final z = movement.z;

    final boundsToCheck = BoundingBox3d.full(
      bounds.minX + x,
      bounds.minY - fallDistance - 1.0e-5,
      bounds.minZ + z,
      bounds.maxX + x,
      bounds.minY,
      bounds.maxZ + z,
    );

    return canFallAtLeast(
          entityBox: boundsToCheck,
          subLevels: subLevels,
          shapesAt: shapesAt,
          sink: sink,
        ) ==
        null;
  }
}

/// What a collision with a ship did to a living entity.
final class CollisionImpact {
  /// The velocity added when the block is bouncy, or `null`.
  final Vector3d? bounce;

  /// The damage dealt when it is not, or `null`.
  final double? damage;

  /// The fall sound to play, or `null`.
  final bool playFallSound;

  const CollisionImpact({this.bounce, this.damage, this.playFallSound = false});

  static const CollisionImpact none = CollisionImpact();
}

/// Inherited velocity and collision damage.
abstract final class CollisionEffects {
  /// The drag the Java code applies to the inherited velocity once the entity is
  /// no longer on the ship (`LivingEntityMixin#sable$applyDrag`).
  ///
  /// Mutates and returns [inherited].
  static Vector3d drag(
    Vector3d inherited, {
    required bool verticalCollision,
    required bool onGround,
    required bool horizontalCollision,
    required bool flying,
    required bool touchingWater,
  }) {
    if (verticalCollision || onGround) {
      inherited.mulVec(Vector3d(0.7, 0.0, 0.7));
    }

    if (horizontalCollision) {
      inherited.mulVec(Vector3d(0.8, 0.6, 0.8));
    }

    if (flying) inherited.mul(0.9);
    if (touchingWater) inherited.mul(0.9);

    inherited.mul(0.99);

    if (inherited.y.abs() < 0.01) inherited.y = 0.0;
    return inherited;
  }

  /// Zeroes a velocity below the threshold the Java code uses (`1e-7` squared).
  static Vector3d clampInherited(Vector3d inherited) {
    if (inherited.lengthSquared <= 1.0e-7) inherited.zero();
    return inherited;
  }

  /// `LivingEntityMixin#sable$computeCollisionEffects`: a fast-moving entity
  /// hitting the side of a ship bounces off a bouncy block or takes
  /// `flyIntoWall` damage.
  ///
  /// [entityVelocity] is the entity's delta movement plus its inherited
  /// velocity; [pointVelocity] is the ship's velocity at the contact point, in
  /// m/tick; [direction] is the contact normal, pointing away from the ship.
  static CollisionImpact evaluate({
    required Vector3d entityVelocity,
    required Vector3d pointVelocity,
    required Vector3d direction,
    required bool bouncy,
    required bool trackingShip,
    double threshold = 3.0 / 20.0,
  }) {
    final relative = Vector3d(
      entityVelocity.x - pointVelocity.x,
      entityVelocity.y - pointVelocity.y,
      entityVelocity.z - pointVelocity.z,
    ).negate();

    final magnitude = direction.dot(relative);
    if (magnitude <= threshold) return CollisionImpact.none;

    if (bouncy) {
      final bounce = Vector3d(
        direction.x * -magnitude,
        direction.y * -magnitude,
        direction.z * -magnitude,
      );
      final length = bounce.length;
      final push = Vector3d(
        direction.x * length * 0.65,
        direction.y * length * 0.65,
        direction.z * length * 0.65,
      );
      if (!trackingShip) push.add(pointVelocity);
      return CollisionImpact(bounce: push, playFallSound: true);
    }

    final damage = magnitude * 12.0 - 8.0;
    if (damage <= 0.0) return CollisionImpact.none;
    return CollisionImpact(damage: damage, playFallSound: true);
  }
}
