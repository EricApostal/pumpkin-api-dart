// `OrientedContraptionEntity` (pure): a contraption that rotates freely around two axes
// (minecart contraptions, couplings). It follows the movement of the cart it rides and turns its
// actors towards the movement direction.
import 'dart:math' as math;

import '../../common/common.dart';
import '../core/contraption.dart';
import '../core/nbt_map.dart';
import '../core/structure_transform.dart';
import '../minecart/capability/minecart_controller.dart' show OrientedCouplingId;
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

  /// The two cart positions of a coupled minecart (`getCoupledCartsIfPresent`). [couplingId] is
  /// the coupling id saved on the entity.
  static (Vec3, Vec3)? Function(
    ContraptionPassengerRef vehicle,
    String couplingId,
  )?
  coupledPositions;

  /// `powerFurnaceCartWithFuelFromStorage(riding)`.
  static void Function(
    Contraption contraption,
    ContraptionPassengerRef vehicle,
  )?
  powerFurnace;

  /// `riding.getData(AllAttachmentTypes.MINECART_CONTROLLER)`: the controller of the cart, when
  /// the cart has one. Its stall state is driven by the contraption instead of the cart motion.
  static MinecartStallSink? Function(ContraptionPassengerRef vehicle)?
  minecartControllerOf;

  /// `MinecartSim2020.getRailVec(railDirection)` of the rail under the cart, projected onto
  /// [motion]: a minecart contraption turns along the curve of its rail.
  static Vec3? Function(ContraptionPassengerRef vehicle, Vec3 motion)?
  projectOnRail;
}

/// The stall part of `MinecartController` the oriented entity drives.
abstract interface class MinecartStallSink {
  /// `MinecartController.isPresent`.
  bool get isPresent;

  /// `MinecartController.setStalledExternally(stall)`.
  void setStalledExternally(bool stall);
}

/// `OrientedContraptionEntity`.
class OrientedContraptionEntity extends AbstractContraptionEntity
    implements OrientedCouplingId {
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

    final cachedMotion = compound.getList('CachedMotion');
    if (cachedMotion.isNotEmpty) {
      motionBeforeStall = readVec(cachedMotion);
      if (motionBeforeStall != vec3Zero)
        targetYaw = prevYaw = yaw =
            yaw + AbstractContraptionEntity.yawFromVector(motionBeforeStall);
      host.setDeltaMovement(vec3Zero);
    }

    couplingId = compound.contains('OnCoupling')
        ? compound.getUuid('OnCoupling')
        : null;
  }

  @override
  void writeAdditional(NbtMap compound, {bool spawnPacket = false}) {
    super.writeAdditional(compound, spawnPacket: spawnPacket);

    // Java writes `CachedMotion` whenever the field is non-null, which is always (it starts at
    // `Vec3.ZERO`).
    compound.putVec('CachedMotion', motionBeforeStall);

    if (initialOrientation.axis.isHorizontal) {
      compound.putString(
        'InitialOrientation',
        initialOrientation.serializedName,
      );
    }
    if (forceAngle) {
      compound.putFloat('ForceYaw', yaw);
      forceAngle = false;
    }
    compound.putBool('Placed', manuallyPlaced);
    compound.putFloat('Yaw', yaw);
    compound.putFloat('Pitch', pitch);
    final coupling = couplingId;
    if (coupling != null) compound.putUuid('OnCoupling', coupling);
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

    // `riding.getData(MINECART_CONTROLLER)`: a cart with a controller takes the stall from the
    // contraption, so the two do not fight over its motion. A cart without one is stopped here.
    final controller = OrientedContraptionHooks.minecartControllerOf?.call(riding);
    if (controller != null && controller.isPresent) {
      controller.setStalledExternally(stalled);
    } else {
      if (stalled) {
        if (!wasStalled) motionBeforeStall = host.vehicleDeltaMovement;
        host.setVehicleDeltaMovement(vec3Zero);
      }
      if (wasStalled && !stalled) {
        host.setVehicleDeltaMovement(motionBeforeStall);
        motionBeforeStall = vec3Zero;
      }
    }

    if (stalled) return;
    if (isOnCoupling) {
      final coupled = OrientedContraptionHooks.coupledPositions?.call(
        riding,
        couplingId ?? '',
      );
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
      final coupled = OrientedContraptionHooks.coupledPositions?.call(
        riding,
        couplingId ?? '',
      );
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
    var motion = movementVector.normalized;

    if (!rotationLock) {
      // A minecart follows the direction of its rail, not its raw motion, so the contraption
      // turns into the curve instead of pointing along the straight line it travelled.
      if (host.vehicleIsMinecart) {
        final projected = OrientedContraptionHooks.projectOnRail?.call(
          riding,
          motion,
        );
        if (projected != null) motion = projected;
      }

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
