// The entity surface Sable's sub-level helpers need, as a plain Dart interface.
//
// Sable's Java code talks to `net.minecraft.world.entity.Entity` directly; the
// plugin cannot (players are host entities), so the helpers are written against
// this view and the plugin adapts its entities to it. Nothing Sable-internal
// leaks into it.
//
// Pure: no host imports.
import '../../math/vector.dart';

/// The parts of an entity the sub-level helpers read and write.
abstract interface class SubLevelEntity {
  /// `Entity.position()`.
  Vector3d get position;

  /// `Entity.getEyePosition()`.
  Vector3d get eyePosition;

  /// `Entity.getEyeHeight()`.
  double get eyeHeight;

  /// `Entity.getLookAngle()`.
  Vector3d get lookAngle;

  /// `Entity.getDeltaMovement()`.
  Vector3d get deltaMovement;

  set deltaMovement(Vector3d value);

  /// `Entity.getBbHeight()`.
  double get boundingBoxHeight;

  /// `Entity.getXRot()` / `setXRot`.
  double get xRot;

  set xRot(double value);

  /// `Entity.getYRot()` / `setYRot`.
  double get yRot;

  set yRot(double value);

  /// `Entity.getYHeadRot()` / `setYHeadRot`.
  double get yHeadRot;

  set yHeadRot(double value);

  // The interpolation fields the client uses; `setOldPosNoMovement` writes them.
  double get xOld;

  set xOld(double value);

  double get yOld;

  set yOld(double value);

  double get zOld;

  set zOld(double value);

  double get xo;

  set xo(double value);

  double get yo;

  set yo(double value);

  double get zo;

  set zo(double value);

  /// `Entity.getType()` as a registry key (`minecraft:arrow`).
  String get typeId;

  /// `entity instanceof FallingBlockEntity`.
  bool get isFallingBlock;

  /// `entity instanceof AbstractArrow`.
  bool get isArrow;

  /// `entity instanceof AbstractHurtingProjectile`.
  bool get isHurtingProjectile;

  /// `AbstractHurtingProjectile.accelerationPower`.
  double get accelerationPower;

  /// `Entity.snapTo(position)`.
  void snapTo(Vector3d position);

  /// `Entity.lookAt(FEET, target)`.
  void lookAtFeet(Vector3d target);

  /// `Entity.setPosRaw(position)`, bypassing the collision/plot logic.
  void setPosRaw(Vector3d position);
}
