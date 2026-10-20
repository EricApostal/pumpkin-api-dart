// `ContraptionCollider` on a sub-level: the entity is collided against the
// contraption in the sub-level's frame.
//
// The Java port redirects eight calls inside `ContraptionCollider.collideEntities`
// so the collider sees the contraption where it really is: its bounding box and
// position projected out of the sub-level, its rotation composed with the
// sub-level's orientation, and the entity's position projected back in. Dart has
// no method redirects, so the same effect is reached by *wrapping* the
// contraption entity: [SubLevelContraptionView] is an
// [AbstractContraptionEntity] whose transform methods apply the sub-level pose,
// and the unchanged [ContraptionCollider] runs on it.
//
// Pure: no host imports.
//
// Java: `...create.contraptions.ContraptionColliderMixin` and
// `...create.contraptions.Matrix3dAccessor`.
//
// create's positions and block states are not exported from its public barrel
// yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/contraptions/core/collision.dart' as cc;
import 'package:create/src/contraptions/core/contraption.dart';
import 'package:create/src/contraptions/core/level.dart' show ContraptionLevel;
import 'package:create/src/core/nbt.dart' show NbtValue;
import 'package:create/src/contraptions/core/structure_transform.dart';
import 'package:create/src/contraptions/entity/contraption_collider.dart';
import 'package:create/src/contraptions/entity/contraption_entity.dart';
import 'package:create/src/contraptions/storage/storage_manager.dart' show StorageSync;
import 'package:pumpkin_api/src/geometry.dart' show Vec3;

import '../../sublevel/math/bounding_box.dart';
import '../../sublevel/math/matrix3.dart';
import '../../sublevel/math/pose.dart';
import '../../sublevel/math/vector.dart';

/// `ContraptionColliderMixin`'s `sable$rotationMatrix`: the contraption's own
/// rotation with the sub-level's orientation applied first.
///
/// Java converts the Create matrix to JOML, calls `rotateLocal(pose.orientation())`
/// and converts back. Both matrices are row-major 3x3 rotations, so the port
/// multiplies in place.
Matrix3d rotationMatrixWithPose(ContraptionRotationState rotationState, Pose3dc pose) {
  final matrix = Matrix3d.copy(_toSable(rotationState.asMatrix()));
  final poseRotation = Matrix3d.identity()..setFromQuaternion(pose.orientation());
  matrix.mulInto(poseRotation, matrix);
  return matrix;
}

/// Converts a Create `Matrix3d` (the collision module's) to the Sable one.
Matrix3d _toSable(cc.Matrix3d matrix) => Matrix3d(
  matrix.m00,
  matrix.m01,
  matrix.m02,
  matrix.m10,
  matrix.m11,
  matrix.m12,
  matrix.m20,
  matrix.m21,
  matrix.m22,
);

/// The `ContraptionRotationState` of [SubLevelContraptionView]: the entity's own
/// rotation with the sub-level's orientation composed on top.
final class SubLevelRotationState extends ContraptionRotationState {
  final ContraptionRotationState _inner;
  final Pose3dc _pose;

  SubLevelRotationState(this._inner, this._pose) {
    xRotation = _inner.xRotation;
    yRotation = _inner.yRotation;
    zRotation = _inner.zRotation;
    secondYRotation = _inner.secondYRotation;
  }

  @override
  cc.Matrix3d asMatrix() {
    final matrix = Matrix3d.copy(_toSable(_inner.asMatrix()));
    final poseRotation = Matrix3d.identity()..setFromQuaternion(_pose.orientation());
    matrix.mulInto(poseRotation, matrix);

    final out = cc.Matrix3d();
    out
      ..m00 = matrix.m00
      ..m01 = matrix.m01
      ..m02 = matrix.m02
      ..m10 = matrix.m10
      ..m11 = matrix.m11
      ..m12 = matrix.m12
      ..m20 = matrix.m20
      ..m21 = matrix.m21
      ..m22 = matrix.m22;
    return out;
  }
}

/// The `ContraptionEntityHost` a [SubLevelContraptionView] exposes: the real
/// host with its bounds, position and entity query projected out of the
/// sub-level.
final class SubLevelContraptionHost implements ContraptionEntityHost {
  final ContraptionEntityHost delegate;
  final Pose3dc pose;

  SubLevelContraptionHost(this.delegate, this.pose);

  @override
  int get entityId => delegate.entityId;

  @override
  String get uuid => delegate.uuid;

  @override
  bool get isAlive => delegate.isAlive;

  @override
  bool get isRemoved => delegate.isRemoved;

  @override
  bool get stalled => delegate.stalled;

  /// `position()` projected out of the sub-level.
  @override
  Vec3 get position => _toVec3(pose.transformPosition(_toVector(delegate.position)));

  @override
  Vec3 get prevPosition => _toVec3(pose.transformPosition(_toVector(delegate.prevPosition)));

  /// The contraption's bounding box, projected out of the sub-level.
  @override
  Aabb get boundingBox {
    final box = BoundingBox3d.fromAabb(delegate.boundingBox).transform(pose);
    return Aabb(box.minX, box.minY, box.minZ, box.maxX, box.maxY, box.maxZ);
  }

  @override
  void setBoundingBox(Aabb box) => delegate.setBoundingBox(box);

  @override
  Vec3 get deltaMovement => delegate.deltaMovement;

  @override
  void setDeltaMovement(Vec3 motion) => delegate.setDeltaMovement(motion);

  @override
  void setPosition(Vec3 position) => delegate.setPosition(position);

  @override
  void teleport(Vec3 position) => delegate.teleport(position);

  @override
  List<ContraptionPassengerRef> get passengers => delegate.passengers;

  @override
  bool hasPassenger(ContraptionPassengerRef passenger) => delegate.hasPassenger(passenger);

  @override
  void addPassenger(ContraptionPassengerRef passenger, {bool force = true}) =>
      delegate.addPassenger(passenger, force: force);

  @override
  void removePassenger(ContraptionPassengerRef passenger) => delegate.removePassenger(passenger);

  @override
  void ejectPassengers() => delegate.ejectPassengers();

  @override
  void setPassengerPosition(ContraptionPassengerRef passenger, Vec3 position) =>
      delegate.setPassengerPosition(passenger, position);

  @override
  void teleportEntity(ContraptionPassengerRef passenger, Vec3 position) =>
      delegate.teleportEntity(passenger, position);

  @override
  Object? get vehicle => delegate.vehicle;

  @override
  ContraptionPassengerRef? get vehiclePassenger => delegate.vehiclePassenger;

  @override
  Vec3 get vehiclePosition => delegate.vehiclePosition;

  @override
  Vec3 get vehiclePrevPosition => delegate.vehiclePrevPosition;

  @override
  Vec3 get vehicleDeltaMovement => delegate.vehicleDeltaMovement;

  @override
  bool get vehicleIsMinecart => delegate.vehicleIsMinecart;

  @override
  void setVehicleDeltaMovement(Vec3 motion) => delegate.setVehicleDeltaMovement(motion);

  @override
  Object? controllerAt(Pos pos) => delegate.controllerAt(pos);

  @override
  void setRotation(double yaw, double pitch) => delegate.setRotation(yaw, pitch);

  @override
  void setOnGround(bool onGround) => delegate.setOnGround(onGround);

  @override
  double get maxUpStep => delegate.maxUpStep;

  @override
  void playSound(String sound, Vec3 at, {double volume = 1, double pitch = 1}) =>
      delegate.playSound(sound, at, volume: volume, pitch: pitch);

  @override
  void sendPayload(String channel, Map<String, Object?> fields) => delegate.sendPayload(channel, fields);

  @override
  void setStalled(bool stalled) => delegate.setStalled(stalled);

  @override
  String? get controllingPlayer => delegate.controllingPlayer;

  @override
  void setControllingPlayer(String? uuid) => delegate.setControllingPlayer(uuid);

  @override
  NbtValue? getPersistentData(String key) => delegate.getPersistentData(key);

  @override
  void setPersistentData(String key, NbtValue? value) => delegate.setPersistentData(key, value);

  @override
  ContraptionLevel get level => delegate.level;

  @override
  ContraptionCollisionEntity? collisionEntityById(int id) => delegate.collisionEntityById(id);

  @override
  void sendBlockChanged(Pos localPos, BState state) => delegate.sendBlockChanged(localPos, state);

  @override
  void sendStorageSync(StorageSync sync) => delegate.sendStorageSync(sync);

  @override
  void sendSeatMapping(Map<String, int> mapping, {int? dismountedId}) =>
      delegate.sendSeatMapping(mapping, dismountedId: dismountedId);

  @override
  void sendStall(double angle) => delegate.sendStall(angle);

  @override
  void sendControlsAbort(String playerUuid) => delegate.sendControlsAbort(playerUuid);

  @override
  void sendDisassembly(StructureTransform transform) => delegate.sendDisassembly(transform);

  /// The entity query the collider makes: the world-space box is projected back
  /// into the plot before the host is asked.
  @override
  List<ContraptionCollisionEntity> entitiesNear(Aabb box) {
    final local = BoundingBox3d.fromAabb(box).transformInverse(pose);
    return delegate.entitiesNear(Aabb(local.minX, local.minY, local.minZ, local.maxX, local.maxY, local.maxZ));
  }

  @override
  ContraptionPassengerRef? passengerFromHost(Object handle) => delegate.passengerFromHost(handle);

  @override
  void remove() => delegate.remove();

  static Vector3d _toVector(Vec3 v) => Vector3d(v.$1, v.$2, v.$3);

  static Vec3 _toVec3(Vector3d v) => (v.x, v.y, v.z);
}

/// A contraption entity seen from outside the sub-level it is in.
///
/// The eight redirects of `ContraptionColliderMixin` are the overrides below;
/// everything else is the wrapped entity's.
final class SubLevelContraptionView extends AbstractContraptionEntity implements OrientedLike {
  final AbstractContraptionEntity delegate;
  final Pose3dc pose;

  /// The sub-level's previous pose, for the contact-point motion.
  final Pose3dc lastPose;

  SubLevelContraptionView(this.delegate, this.pose, this.lastPose)
    : super(SubLevelContraptionHost(delegate.host, pose));

  @override
  Contraption? get contraption => delegate.contraption;

  @override
  bool get collisionEnabled => delegate.collisionEnabled;

  @override
  bool get isElevatorContraption => delegate.isElevatorContraption;

  @override
  bool get supportsTerrainCollision => delegate.supportsTerrainCollision;

  @override
  int get nonDamageTicks => delegate is OrientedLike ? (delegate as OrientedLike).nonDamageTicks : 0;

  /// `position()` projected out of the sub-level.
  @override
  Vec3 get position => _toVec3(pose.transformPosition(_toVector(delegate.position)));

  @override
  Aabb get boundingBox {
    final box = BoundingBox3d.fromAabb(delegate.boundingBox).transform(pose);
    return Aabb(box.minX, box.minY, box.minZ, box.maxX, box.maxY, box.maxZ);
  }

  /// `getAnchorVec()`: the anchor projected out of the sub-level, with the
  /// half-block offset the collider expects (`sable$getAnchorVec`).
  @override
  Vec3 getAnchorVec() {
    final anchor = delegate.getAnchorVec();
    final projected = pose.transformPosition(Vector3d(anchor.$1 + 0.5, anchor.$2 + 0.5, anchor.$3 + 0.5));
    return (projected.x - 0.5, projected.y - 0.5, projected.z - 0.5);
  }

  @override
  Vec3 getPrevAnchorVec() {
    final anchor = delegate.getPrevAnchorVec();
    final projected = pose.transformPosition(Vector3d(anchor.$1 + 0.5, anchor.$2 + 0.5, anchor.$3 + 0.5));
    return (projected.x - 0.5, projected.y - 0.5, projected.z - 0.5);
  }

  @override
  Vec3 getPrevPositionVec() => _toVec3(pose.transformPosition(_toVector(delegate.getPrevPositionVec())));

  @override
  ContraptionRotationState getRotationState() => SubLevelRotationState(delegate.getRotationState(), pose);

  /// `toLocalVector`: the world vector is projected back into the plot first.
  @override
  Vec3 toLocalVector(Vec3 globalVec, double partialTicks, {bool prevAnchor = false}) {
    final local = pose.transformPositionInverse(_toVector(globalVec));
    return delegate.toLocalVector((local.x, local.y, local.z), partialTicks, prevAnchor: prevAnchor);
  }

  /// `getContactPointMotion`: the motion of the contact point on the
  /// contraption, plus the motion of the sub-level itself.
  @override
  Vec3 getContactPointMotion(Vec3 globalContactPoint) {
    final localContactPoint = pose.transformPositionInverse(_toVector(globalContactPoint));
    final motion = pose.transformNormal(
      _toVector(delegate.getContactPointMotion((localContactPoint.x, localContactPoint.y, localContactPoint.z))),
    );
    final subLevelDrift = _toVector(globalContactPoint).sub(lastPose.transformPosition(localContactPoint));
    motion.add(subLevelDrift);
    return (motion.x, motion.y, motion.z);
  }

  @override
  void registerColliding(ContraptionCollisionEntity entity) => delegate.registerColliding(entity);

  @override
  bool canCollideWith(ContraptionCollisionEntity e) => delegate.canCollideWith(e);

  @override
  void setContraption(Contraption? contraption) => delegate.setContraption(contraption);

  @override
  void contraptionInitialize() => delegate.contraptionInitialize();

  @override
  Vec3 applyRotation(Vec3 localPos, double partialTicks) => delegate.applyRotation(localPos, partialTicks);

  @override
  Vec3 reverseRotation(Vec3 localPos, double partialTicks) => delegate.reverseRotation(localPos, partialTicks);

  @override
  Future<void> tickContraption() => delegate.tickContraption();

  @override
  StructureTransform makeStructureTransform() => delegate.makeStructureTransform();

  @override
  double getStalledAngle() => delegate.getStalledAngle();

  @override
  void handleStallInformation(double x, double y, double z, double angle) =>
      delegate.handleStallInformation(x, y, z, angle);

  static Vector3d _toVector(Vec3 v) => Vector3d(v.$1, v.$2, v.$3);

  static Vec3 _toVec3(Vector3d v) => (v.x, v.y, v.z);
}

/// `ContraptionCollider.collideEntities` with the sub-level transforms applied.
///
/// This is the entry point the compat layer calls instead of the plain collider
/// when the contraption is inside a sub-level. Outside a sub-level it delegates
/// straight through, so the two never disagree.
abstract final class SubLevelContraptionCollider {
  /// Collides the entities around [entity].
  ///
  /// [pose] is the sub-level's logical pose and [lastPose] its previous one;
  /// pass `null` for a contraption in the main level.
  static void collideEntities(
    AbstractContraptionEntity entity, {
    Pose3dc? pose,
    Pose3dc? lastPose,
  }) {
    if (pose == null) {
      ContraptionCollider.collideEntities(entity);
      return;
    }

    final view = SubLevelContraptionView(entity, pose, lastPose ?? pose);
    ContraptionCollider.collideEntities(view);
  }
}
