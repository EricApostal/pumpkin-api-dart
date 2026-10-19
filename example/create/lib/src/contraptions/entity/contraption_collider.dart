// `ContraptionCollider` (pure): entities touching a contraption, and the world collision of
// translating contraptions. The continuous oriented-box collision maths lives in
// `core/collision.dart`; this file applies it to the entities of the host.
import 'dart:math' as math;

import '../../common/common.dart';
import '../core/collision.dart';
import '../core/contraption.dart';
import '../core/movement.dart';
import 'contraption_entity.dart';
import 'translating_contraption.dart';

/// Hooks the trains and actuator modules install.
abstract final class ContraptionColliderHooks {
  /// Whether [entity] is a train carriage (a `CarriageContraptionEntity`).
  static bool Function(AbstractContraptionEntity entity)? isTrainCarriage;

  /// Whether trains cause damage (`trains.trainsCauseDamage`).
  static bool Function()? trainsCauseDamage;

  /// `entity.hurt(CreateDamageSources.runOver(...), damage)`.
  static void Function(ContraptionCollisionEntity entity, double damage)?
  damageRunOver;
}

/// `ContraptionCollider`.
abstract final class ContraptionCollider {
  /// `collideEntities(contraptionEntity)`: pushes the entities around a contraption out of it.
  static void collideEntities(AbstractContraptionEntity contraptionEntity) {
    final contraption = contraptionEntity.contraption;
    if (contraption == null) return;
    if (!contraptionEntity.collisionEnabled) return;

    final host = contraptionEntity.host;
    final bounds = host.boundingBox;
    final contraptionMotion =
        host.position - contraptionEntity.getPrevPositionVec();
    final anchorVec = contraptionEntity.getAnchorVec();

    final rotation = contraptionEntity.getRotationState();
    final rotationMatrix = rotation.asMatrix();

    final denseViableColliders = CollisionList();

    final entities = host.entitiesNear(
      bounds.inflate(2).expandTowards(0, 32, 0),
    );
    for (final entity in entities) {
      if (!entity.isAlive) continue;
      // Server players are handled by the client's own movement packets.
      if (entity.isPlayer) {
        for (final e in entity.selfAndPassengers) {
          e.setAboveGroundTickCountZero();
        }
        continue;
      }
      if (!contraptionEntity.canCollideWith(entity)) continue;

      for (final e in entity.selfAndPassengers) {
        e.setAboveGroundTickCountZero();
      }

      final entityPosition = entity.position;
      var entityBounds = entity.boundingBox;
      var motion = entity.deltaMovement;
      final yawOffset = rotation.yawOffset;
      final position = getWorldToLocalTranslation(
        entity,
        anchorVec,
        rotationMatrix,
        yawOffset,
      );

      motion = motion - contraptionMotion;
      motion = rotationMatrix.transform(motion);

      final localBB = entityBounds.moveBy(position).inflate(1e-7);
      final obb = OrientedBB(localBB);
      obb.rotation = rotationMatrix;

      final collidableBBs = contraption.getSimplifiedEntityColliders();
      if (collidableBBs.size == 0) {
        _getPotentiallyCollidedShapes(
          contraption,
          localBB.expandTowards(motion.$1, motion.$2, motion.$3),
          collidableBBs,
        );
      }

      final result = ContinuousOBBCollider.collideMany(
        collidableBBs,
        denseViableColliders,
        obb,
        motion,
        entity.maxUpStep,
        !rotation.hasVerticalRotation,
      );

      var entityMotion = entity.deltaMovement;
      final entityMotionNoTemporal = entityMotion;
      var collisionNormal = result.normal;
      var collisionLocation = result.location;
      var totalResponse = result.collisionResponse;
      var surfaceCollision = result.surfaceCollision;
      final hardCollision = result.hardCollision;
      final temporalCollision = result.temporalCollision;
      var motionResponse = !temporalCollision
          ? motion
          : motion.normalized * (motion.length * result.temporalResponse);

      motionResponse =
          rotationMatrix.transformTransposed(motionResponse) +
          contraptionMotion;
      totalResponse = rotationMatrix.transformTransposed(totalResponse);
      totalResponse = VecHelper.rotate(totalResponse, yawOffset, Axis.y);
      collisionNormal = rotationMatrix.transformTransposed(collisionNormal);
      collisionNormal = VecHelper.rotate(collisionNormal, yawOffset, Axis.y);
      collisionNormal = collisionNormal.normalized;
      collisionLocation = rotationMatrix.transformTransposed(collisionLocation);
      collisionLocation = VecHelper.rotate(
        collisionLocation,
        yawOffset,
        Axis.y,
      );

      var bounce = 0.0;
      var slide = 0.0;

      if (collisionLocation != vec3Zero) {
        collisionLocation =
            collisionLocation +
            (entity.position + entity.boundingBox.center) * 0.5;
        if (temporalCollision)
          collisionLocation = collisionLocation + (0, motionResponse.$2, 0);

        var pos = posContaining(
          contraptionEntity.toLocalVector(entity.position, 0),
        );
        var info = contraption.getBlocks()[pos];
        if (info != null) {
          if (contraption.levelForColliders?.stateHasTag(
                info.state,
                'minecraft:climbable',
              ) ??
              false) {
            surfaceCollision = true;
            totalResponse = totalResponse + (0, 0.1, 0);
          }
        }

        pos = posContaining(
          contraptionEntity.toLocalVector(collisionLocation, 0),
        );
        info = contraption.getBlocks()[pos];
        if (info != null) {
          final interactor = contraption.getInteractors()[pos];
          if (interactor != null)
            interactor.handleEntityCollision(entity, pos, contraption);
          bounce = _bounceMultiplier(info.state.key);
          slide = math.max(
            0,
            (contraption.levelForColliders?.stateFriction(info.state) ?? 0.6) -
                0.6,
          );
        }
      }

      final hasNormal = collisionNormal != vec3Zero;
      final anyCollision = hardCollision || temporalCollision;

      if (bounce > 0 &&
          hasNormal &&
          anyCollision &&
          _bounceEntity(entity, collisionNormal, contraptionEntity, bounce)) {
        continue;
      }

      if (temporalCollision) {
        final idealVerticalMotion = motionResponse.$2;
        if (idealVerticalMotion != entityMotion.$2) {
          entityMotion = (
            entityMotion.$1,
            idealVerticalMotion,
            entityMotion.$3,
          );
          entity.setDeltaMovement(entityMotion);
        }
      }

      if (hardCollision) {
        final motionX = entityMotion.$1;
        final motionY = entityMotion.$2;
        final motionZ = entityMotion.$3;
        final intersectX = totalResponse.$1;
        final intersectY = totalResponse.$2;
        final intersectZ = totalResponse.$3;

        const horizontalEpsilon = 1 / 128;
        if (motionX != 0 &&
            intersectX.abs() > horizontalEpsilon &&
            motionX > 0 == intersectX < 0) {
          entityMotion = (0.0, entityMotion.$2, entityMotion.$3);
        }
        if (motionY != 0 && intersectY != 0 && motionY > 0 == intersectY < 0) {
          entityMotion = (
            entityMotion.$1,
            contraptionMotion.$2,
            entityMotion.$3,
          );
        }
        if (motionZ != 0 &&
            intersectZ.abs() > horizontalEpsilon &&
            motionZ > 0 == intersectZ < 0) {
          entityMotion = (entityMotion.$1, entityMotion.$2, 0.0);
        }
      }

      if (bounce == 0 &&
          slide > 0 &&
          hasNormal &&
          anyCollision &&
          rotation.hasVerticalRotation) {
        final slideFactor =
            (collisionNormal.$1, 0.0, collisionNormal.$3).length * 1.25;
        final motionIn = (
          entityMotionNoTemporal.$1,
          entityMotionNoTemporal.$2 * 0.9 - 0.01,
          entityMotionNoTemporal.$3,
        );
        final slideNormal = collisionNormal
            .cross(motionIn.cross(collisionNormal))
            .normalized;
        final newMotion =
            (entityMotion.$1 * 0.85, 0.0, entityMotion.$3 * 0.85) +
            slideNormal * ((0.2 + slide) * motionIn.length * slideFactor) +
            (0, -0.1 - collisionNormal.$2 * 0.125, 0);
        entity.setDeltaMovement(newMotion);
        entityMotion = newMotion;
      }

      if (!hardCollision && !surfaceCollision) continue;

      final allowedMovement = totalResponse;
      entity.setPosition(entityPosition + allowedMovement);
      final newPosition = entity.position;

      entityMotion = _handleDamageFromTrain(
        contraptionEntity,
        contraptionMotion,
        entity,
        entityMotion,
      );

      entity.setVelocitySync();

      if (surfaceCollision) {
        contraptionEntity.registerColliding(entity);
        entity.setFallDistance(0);
        final canWalk = bounce != 0 || slide == 0;
        if (canWalk || !rotation.hasVerticalRotation) {
          if (canWalk) entity.setOnGround(true);
        }
        entity.setPosition((newPosition.$1, newPosition.$2, newPosition.$3));
      }

      entity.setDeltaMovement(entityMotion);
    }
  }

  static Vec3 _handleDamageFromTrain(
    AbstractContraptionEntity contraptionEntity,
    Vec3 contraptionMotion,
    ContraptionCollisionEntity entity,
    Vec3 entityMotion,
  ) {
    final isTrain =
        ContraptionColliderHooks.isTrainCarriage?.call(contraptionEntity) ??
        false;
    if (!isTrain) return entityMotion;
    if (!entity.onGround) return entityMotion;
    if (entity.contraptionGrounded) {
      entity.clearContraptionGrounded();
      return entityMotion;
    }
    if (entity.isItemEntity) return entityMotion;
    if (contraptionEntity is OrientedLike &&
        (contraptionEntity as OrientedLike).nonDamageTicks != 0) {
      return entityMotion;
    }
    if (!(ContraptionColliderHooks.trainsCauseDamage?.call() ?? true))
      return entityMotion;

    final diffMotion = contraptionMotion - entity.deltaMovement;
    if (diffMotion.length <= 0.35 || contraptionMotion.length <= 0.35)
      return entityMotion;

    final damage = diffMotion.length;
    ContraptionColliderHooks.damageRunOver?.call(
      entity,
      (damage * 16).toInt().toDouble(),
    );

    return VecHelper.clamp(entityMotion + diffMotion, 3);
  }

  static bool _bounceEntity(
    ContraptionCollisionEntity entity,
    Vec3 normal,
    AbstractContraptionEntity contraption,
    double factor,
  ) {
    if (factor == 0) return false;
    if (entity.isSuppressingBounce) return false;

    final contactPointMotion = contraption.getContactPointMotion(
      entity.position,
    );
    final motion = entity.deltaMovement - contactPointMotion;
    final deltaV = normal * (factor * 2 * motion.dot(normal));
    if (deltaV.dot(deltaV) < 0.1) return false;
    entity.setDeltaMovement(entity.deltaMovement - deltaV);
    return true;
  }

  /// `getPotentiallyCollidedShapes(world, contraption, localBB, out)`.
  static void _getPotentiallyCollidedShapes(
    Contraption contraption,
    Aabb localBB,
    CollisionList out,
  ) {
    final height = localBB.ySize;
    final width = localBB.xSize;
    final horizontalFactor = (height > width && width != 0)
        ? height / width
        : 1.0;
    final verticalFactor = (width > height && height != 0)
        ? width / height
        : 1.0;
    var scanBB = localBB.inflate(0.5);
    scanBB = scanBB.inflate(horizontalFactor, verticalFactor, horizontalFactor);

    final min = (scanBB.minX.floor(), scanBB.minY.floor(), scanBB.minZ.floor());
    final max = (scanBB.maxX.floor(), scanBB.maxY.floor(), scanBB.maxZ.floor());

    final level = contraption.levelForColliders;
    if (level == null) return;
    for (final p in betweenClosed(min, max)) {
      final info = contraption.blocks[p];
      if (info == null || contraption.isHiddenInPortal(p)) continue;
      final boxes = level.stateCollisionBoxes(info.state);
      for (final box in boxes) {
        out.append(
          p.$1 + (box.minX + box.maxX) / 2,
          p.$2 + (box.minY + box.maxY) / 2,
          p.$3 + (box.minZ + box.maxZ) / 2,
          (box.maxX - box.minX) / 2,
          (box.maxY - box.minY) / 2,
          (box.maxZ - box.minZ) / 2,
        );
      }
    }
  }

  /// `getWorldToLocalTranslation(entity, anchorVec, rotationMatrix, yawOffset)`.
  static Vec3 getWorldToLocalTranslation(
    ContraptionCollisionEntity entity,
    Vec3 anchorVec,
    Matrix3d rotationMatrix,
    double yawOffset,
  ) {
    final entityPosition = entity.position;
    final centerY = (0.0, entity.boundingBox.ySize / 2, 0.0);
    var position = entityPosition + centerY;
    position = worldToLocalPos(position, anchorVec, rotationMatrix, yawOffset);
    position = position - centerY;
    return position - entityPosition;
  }

  /// `worldToLocalPos(worldPos, anchorVec, rotation)`.
  static Vec3 worldToLocalPosWithState(
    Vec3 worldPos,
    Vec3 anchorVec,
    ContraptionRotationState rotation,
  ) => worldToLocalPos(
    worldPos,
    anchorVec,
    rotation.asMatrix(),
    rotation.yawOffset,
  );

  /// `worldToLocalPos(worldPos, anchorVec, rotationMatrix, yawOffset)`.
  static Vec3 worldToLocalPos(
    Vec3 worldPos,
    Vec3 anchorVec,
    Matrix3d rotationMatrix,
    double yawOffset,
  ) {
    var localPos = worldPos - anchorVec - VecHelper.centerOfOrigin;
    localPos = VecHelper.rotate(localPos, -yawOffset, Axis.y);
    localPos = rotationMatrix.transform(localPos);
    return localPos + VecHelper.centerOfOrigin;
  }

  // -- Terrain collision of translating contraptions -------------------------------------------

  /// `collideBlocks(contraptionEntity)`: whether the contraption is blocked by the world or by
  /// another contraption.
  static bool collideBlocks(AbstractContraptionEntity contraptionEntity) {
    if (!contraptionEntity.supportsTerrainCollision) return false;
    final contraption = contraptionEntity.contraption;
    if (contraption is! TranslatingContraption) return false;

    final motion = contraptionEntity.host.deltaMovement;
    if (motion == vec3Zero) return false;

    final bounds = contraptionEntity.host.boundingBox;
    final position = contraptionEntity.host.position;
    var gridPos = posContaining(position);

    final movementDirection = approximateNearest(motion);
    if (movementDirection.axisDirection == AxisDirection.positive) {
      gridPos = gridPos.relative(movementDirection);
    }
    if (isCollidingWithWorld(contraption, gridPos, movementDirection))
      return true;

    final otherContraptions = contraptionEntity.host.entitiesNear(
      bounds.inflate(1),
    );
    for (final other in otherContraptions) {
      if (other.entityId == contraptionEntity.entityId) continue;
      final otherEntity = other.contraptionEntity;
      if (otherEntity == null) continue;
      if (!otherEntity.supportsTerrainCollision) continue;
      final otherContraption = otherEntity.contraption;
      if (otherContraption is! TranslatingContraption) continue;
      final otherMotion = otherEntity.host.deltaMovement;
      final otherBounds = otherEntity.host.boundingBox;
      final otherPosition = otherEntity.host.position;

      if (!bounds.moveBy(motion).intersects(otherBounds.moveBy(otherMotion)))
        continue;

      for (var colliderPos in contraption.getOrCreateColliders(
        contraption.levelForColliders!,
        movementDirection,
      )) {
        colliderPos = colliderPos + gridPos - posContaining(otherPosition);
        if (!otherContraption.getBlocks().containsKey(colliderPos)) continue;
        return true;
      }
    }
    return false;
  }

  /// `isCollidingWithWorld(world, contraption, anchor, movementDirection)`.
  static bool isCollidingWithWorld(
    TranslatingContraption contraption,
    Pos anchor,
    Direction movementDirection,
  ) {
    final level = contraption.levelForColliders;
    if (level == null) return false;
    for (final pos in contraption.getOrCreateColliders(
      level,
      movementDirection,
    )) {
      final colliderPos = pos + anchor;
      if (!level.isLoaded(colliderPos)) return true;

      final collidedState = level.stateAt(colliderPos);
      final blockInfo = contraption.getBlocks()[pos];
      final emptyCollider = level.stateCollisionEmpty(collidedState);

      if (collidedState.key == 'minecraft:cocoa') continue;

      if (blockInfo != null) {
        final movementBehaviour = MovementBehaviours.of(blockInfo.state, level);
        if (movementBehaviour != null) {
          if (movementBehaviour.breaksBlocks()) {
            if (!emptyCollider) return true;
            continue;
          }
        }
      }

      if (collidedState.key == 'create:pulley_magnet' &&
          pos == posZero &&
          movementDirection == Direction.up) {
        continue;
      }
      if (!level.stateReplaceable(collidedState) && !emptyCollider) return true;
    }
    return false;
  }

  /// `Direction.getApproximateNearest`.
  static Direction approximateNearest(Vec3 vec) {
    final ax = vec.$1.abs();
    final ay = vec.$2.abs();
    final az = vec.$3.abs();
    if (ax >= ay && ax >= az)
      return vec.$1 > 0 ? Direction.east : Direction.west;
    if (ay >= ax && ay >= az) return vec.$2 > 0 ? Direction.up : Direction.down;
    return vec.$3 > 0 ? Direction.south : Direction.north;
  }

  /// `BlockHelper.getBounceMultiplier`.
  static double _bounceMultiplier(String blockKey) {
    if (blockKey == 'minecraft:slime_block') return 0.8;
    if (blockKey.endsWith('_bed')) return 0.66 * 0.8;
    return 0;
  }
}

/// `OrientedContraptionEntity` parts the collider reads without importing the class.
abstract interface class OrientedLike {
  int get nonDamageTicks;
}
