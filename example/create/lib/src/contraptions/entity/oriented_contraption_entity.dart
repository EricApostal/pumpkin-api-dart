// `OrientedContraptionEntity` (pure): a contraption that rotates freely around two axes
// (minecart contraptions, couplings). It follows the movement of the cart it rides and turns its
// actors towards the movement direction.
import 'dart:math' as math;

import '../../common/common.dart';
import '../core/contraption.dart';
import '../core/nbt_map.dart';
import '../core/structure_transform.dart';
import 'contraption_entity.dart';

/// Hooks the mounted (minecart) and bearing modules install for the oriented entity.
abstract final class OrientedContraptionHooks {
  /// `MountedContraption.rotationMode == ROTATION_LOCKED`.
  static bool Function(Contraption contraption)? rotationLock;

  /// `MountedContraption.rotationMode == ROTATE_PAUSED`.
  static bool Function(Contraption contraption)? pauseWhileRotating;

  /// `MountedContraption.addExtraInventories(riding)`.
  static void Function(
    Contraption contraption,
    ContraptionPassengerRef? vehicle,
  )?
  addExtraInventories;

  /// The facing of a stabilized (sub)contraption, `null` for a normal one.
  static Direction? Function(Contraption contraption)? stabilizedFacing;

  /// The two cart positions of a coupled minecart (`getCoupledCartsIfPresent`).
  static (Vec3, Vec3)? Function(ContraptionPassengerRef vehicle)?
  coupledPositions;

  /// `powerFurnaceCartWithFuelFromStorage(riding)`.
  static void Function(
    Contraption contraption,
    ContraptionPassengerRef vehicle,
  )?
  powerFurnace;
}

/// `OrientedContraptionEntity`.
class OrientedContraptionEntity extends AbstractContraptionEntity {
  Vec3 motionBeforeStall = vec3Zero;
  bool forceAngle = false;
  bool _attachedExtraInventories = false;
  bool manuallyPlaced = false;

  double prevYaw = 0;
  double yaw = 0;
  double targetYaw = 0;

  double prevPitch = 0;
  double pitch = 0;

  int nonDamageTicks = 10;

  /// `INITIAL_ORIENTATION` (only horizontal values are meaningful; the default is south).
  Direction initialOrientation = Direction.south;

  String? couplingId;

  OrientedContraptionEntity(super.host);

  /// `create(world, contraption, initialOrientation)`.
  void configure(Contraption contraption, Direction orientation) {
    setContraption(contraption);
    initialOrientation = orientation;
    startAtInitialYaw();
  }

  /// `setInitialOrientation`.
  void setInitialOrientation(Direction direction) =>
      initialOrientation = direction;

  /// `getInitialOrientation`.
  Direction getInitialOrientation() => initialOrientation;

  @override
  double get yawOffset => getInitialYaw();

  /// `getInitialYaw()`.
  double getInitialYaw() => isInitialOrientationPresent
      ? initialOrientation.toYRot
      : Direction.south.toYRot;

  /// `isInitialOrientationPresent`.
  bool get isInitialOrientationPresent => initialOrientation.axis.isHorizontal;

  /// `startAtInitialYaw`.
  void startAtInitialYaw() => startAtYaw(getInitialYaw());

  /// `startAtYaw`.
  void startAtYaw(double newYaw) {
    targetYaw = yaw = prevYaw = newYaw;
    forceAngle = true;
  }

  @override
  ContraptionRotationState getRotationState() {
    final crs = ContraptionRotationState();
    final initialYaw = yawOffset;
    crs.zRotation = pitch;
    crs.yRotation = -yaw + initialYaw;

    if (pitch != 0 && yaw != 0) {
      crs.secondYRotation = -yaw;
      crs.yRotation = initialYaw;
    }
    return crs;
  }

  /// `getViewYRot(partialTicks)`.
  double getViewYRot(double partialTicks) =>
      -(partialTicks == 1.0 ? yaw : _lerpAngle(partialTicks, prevYaw, yaw));

  /// `getViewXRot(partialTicks)`.
  double getViewXRot(double partialTicks) =>
      partialTicks == 1.0 ? pitch : _lerpAngle(partialTicks, prevPitch, pitch);

  @override
  Vec3 applyRotation(Vec3 localPos, double partialTicks) {
    var vec = VecHelper.rotate(localPos, getInitialYaw(), Axis.y);
    vec = VecHelper.rotate(vec, getViewXRot(partialTicks), Axis.z);
    vec = VecHelper.rotate(vec, getViewYRot(partialTicks), Axis.y);
    return vec;
  }

  @override
  Vec3 reverseRotation(Vec3 localPos, double partialTicks) {
    var vec = VecHelper.rotate(localPos, -getViewYRot(partialTicks), Axis.y);
    vec = VecHelper.rotate(vec, -getViewXRot(partialTicks), Axis.z);
    vec = VecHelper.rotate(vec, -getInitialYaw(), Axis.y);
    return vec;
  }

  @override
  void readAdditional(NbtMap compound, {bool spawnData = false}) {
    super.readAdditional(compound, spawnData: spawnData);

    if (compound.contains('InitialOrientation')) {
      initialOrientation =
          Direction.byName(
            compound.getString('InitialOrientation').toLowerCase(),
          ) ??
          Direction.south;
    }
    yaw = compound.getDouble('Yaw');
    pitch = compound.getDouble('Pitch');
    manuallyPlaced = compound.getBool('Placed');

    if (compound.contains('ForceYaw'))
      startAtYaw(compound.getDouble('ForceYaw'));

    final cachedMotion = compound.getVec('CachedMotion');
    if (cachedMotion != vec3Zero) {
      motionBeforeStall = cachedMotion;
      targetYaw = prevYaw = yaw =
          yaw + AbstractContraptionEntity.yawFromVector(motionBeforeStall);
      host.setDeltaMovement(vec3Zero);
    }

    couplingId = compound.contains('OnCoupling')
        ? compound.getString('OnCoupling')
        : null;
  }

  @override
  void writeAdditional(NbtMap compound, {bool spawnPacket = false}) {
    super.writeAdditional(compound, spawnPacket: spawnPacket);

    if (motionBeforeStall != vec3Zero)
      compound.putVec('CachedMotion', motionBeforeStall);

    if (initialOrientation.axis.isHorizontal) {
      compound.putString(
        'InitialOrientation',
        initialOrientation.name.toUpperCase(),
      );
    }
    if (forceAngle) {
      compound.putDouble('ForceYaw', yaw);
      forceAngle = false;
    }
    compound.putBool('Placed', manuallyPlaced);
    compound.putDouble('Yaw', yaw);
    compound.putDouble('Pitch', pitch);
    final coupling = couplingId;
    if (coupling != null) compound.putString('OnCoupling', coupling);
  }

  @override
  Future<void> tickContraption() async {
    if (nonDamageTicks > 0) nonDamageTicks--;

    final riding = host.vehiclePassenger;
    if (riding == null) return;

    final c = contraption;
    if (c == null) return;

    final rotationLock =
        OrientedContraptionHooks.rotationLock?.call(c) ?? false;
    final pauseWhileRotating =
        OrientedContraptionHooks.pauseWhileRotating?.call(c) ?? false;
    final wasStalled = isStalled;

    final isOnCoupling = couplingId != null && host.vehicleIsMinecart;

    if (!_attachedExtraInventories) {
      OrientedContraptionHooks.addExtraInventories?.call(c, riding);
      _attachedExtraInventories = true;
    }

    final rotating = updateOrientation(
      rotationLock,
      wasStalled,
      riding,
      isOnCoupling,
    );
    if (!rotating || !pauseWhileRotating) await tickActors();
    final stalled = isStalled;

    if (stalled) {
      if (!wasStalled) motionBeforeStall = host.vehicleDeltaMovement;
      host.setVehicleDeltaMovement(vec3Zero);
    }
    if (wasStalled && !stalled) {
      host.setVehicleDeltaMovement(motionBeforeStall);
      motionBeforeStall = vec3Zero;
    }

    if (stalled) return;
    if (isOnCoupling) {
      final coupled = OrientedContraptionHooks.coupledPositions?.call(riding);
      if (coupled == null) return;
      return;
    }
    OrientedContraptionHooks.powerFurnace?.call(c, riding);
  }

  /// `updateOrientation`.
  bool updateOrientation(
    bool rotationLock,
    bool wasStalled,
    ContraptionPassengerRef riding,
    bool isOnCoupling,
  ) {
    if (isOnCoupling) {
      final coupled = OrientedContraptionHooks.coupledPositions?.call(riding);
      if (coupled == null) return false;
      final (a, b) = coupled;
      final diffX = a.$1 - b.$1;
      final diffY = a.$2 - b.$2;
      final diffZ = a.$3 - b.$3;

      prevYaw = yaw;
      prevPitch = pitch;
      yaw = math.atan2(diffZ, diffX) * 180 / math.pi;
      pitch =
          math.atan2(diffY, math.sqrt(diffX * diffX + diffZ * diffZ)) *
          180 /
          math.pi;

      if (couplingId == riding.uuid) {
        pitch *= -1;
        yaw += 180;
      }
      return false;
    }

    final c = contraption;
    if (c != null &&
        (c.typeId == 'create:stabilized' ||
            OrientedContraptionHooks.stabilizedFacing?.call(c) != null)) {
      prevYaw = yaw;
      final parent = host.vehiclePassenger?.contraptionEntity;
      if (parent is OrientedContraptionEntity) {
        yaw =
            wrapDegrees(getInitialYaw() - parent.getInitialYaw()) -
            parent.getViewYRot(1);
      }
      return false;
    }

    prevYaw = yaw;
    if (wasStalled) return false;

    var rotating = false;
    var movementVector = host.vehicleDeltaMovement;
    final locationDiff = host.vehiclePosition - host.vehiclePrevPosition;
    if (!host.vehicleIsMinecart) movementVector = locationDiff;
    final motion = movementVector.normalized;

    if (!rotationLock) {
      if (motion.length > 0) {
        targetYaw = AbstractContraptionEntity.yawFromVector(motion);
        if (targetYaw < 0) targetYaw += 360;
        if (yaw < 0) yaw += 360;
      }

      prevYaw = yaw;
      final maxApproachSpeed =
          motion.length * 12 / math.max(1, host.boundingBox.xSize / 6);
      final yawHint = _shortestAngleDiff(
        yaw,
        AbstractContraptionEntity.yawFromVector(locationDiff),
      );
      var approach = _shortestAngleDiff(yaw, targetYaw, yawHint);
      approach = approach.clamp(-maxApproachSpeed, maxApproachSpeed);
      yaw += approach;
      if (_shortestAngleDiff(yaw, targetYaw).abs() < 1) {
        yaw = targetYaw;
      } else {
        rotating = true;
      }
    }
    return rotating;
  }

  @override
  Vec3 getAnchorVec() => super.getAnchorVec() - (0.5, 0, 0.5);

  @override
  Vec3 getPrevAnchorVec() => super.getPrevAnchorVec() - (0.5, 0, 0.5);

  @override
  StructureTransform makeStructureTransform() {
    final offset = posContaining(getAnchorVec() + (0.5, 0.5, 0.5));
    return StructureTransform.angles(offset, 0, -yaw + getInitialYaw(), 0);
  }

  @override
  double getStalledAngle() => yaw;

  @override
  void handleStallInformation(double x, double y, double z, double stallAngle) {
    yaw = stallAngle;
  }

  /// `getCouplingId`.
  String? getCouplingId() => couplingId;

  /// `setCouplingId`.
  void setCouplingId(String? id) => couplingId = id;

  /// `stopRiding`: a contraption that is dropped disassembles itself.
  Future<void> stopRiding() async {
    if (host.isAlive) await disassemble();
  }

  /// `nonDamageTicks` reset of `ContraptionRelocationPacket`.
  void onRelocated() => nonDamageTicks = 10;

  static double _lerpAngle(double t, double a, double b) =>
      a + _shortestAngleDiff(a, b) * t;

  static double _shortestAngleDiff(double a, double b, [double? hint]) {
    final diff = wrapDegrees(b - a);
    if (hint != null && hint.abs() > 90 && diff.abs() < 90) {
      return diff + (diff > 0 ? 360 : -360);
    }
    return diff;
  }
}
