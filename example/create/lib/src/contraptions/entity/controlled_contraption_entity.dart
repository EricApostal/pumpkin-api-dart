// `ControlledContraptionEntity` (pure): a contraption bound to a controller block entity (bearings,
// pistons, pulleys, elevators). It rotates around one axis and translates; the controller tells it
// where it is and how far it turned.
import 'dart:math' as math;

import '../../common/common.dart';
import '../../conveyance/nbt_names.dart'
    show enumByNameIgnoreCase, enumNbtName;
import '../core/contraption.dart';
import '../core/movement.dart';
import '../core/nbt_map.dart';
import '../core/structure_info.dart';
import '../core/structure_transform.dart';
import 'contraption_entity.dart';
import 'i_control_contraption.dart';

/// `ControlledContraptionEntity`.
class ControlledContraptionEntity extends AbstractContraptionEntity {
  Pos? controllerPos;
  Axis? rotationAxis;

  double prevAngle = 0;
  double angle = 0;
  double angleDelta = 0;

  ControlledContraptionEntity(super.host);

  /// `setContraption`: a bearing also knows its rotation axis.
  @override
  void setContraption(Contraption? contraption) {
    super.setContraption(contraption);
    if (contraption is BearingContraptionLike) {
      rotationAxis = (contraption as BearingContraptionLike).facing.axis;
    }
  }

  /// `getContactPointMotion`: a translating contraption moves its contact points with the entity.
  @override
  Vec3 getContactPointMotion(Vec3 globalContactPoint) {
    if (contraption is TranslatingContraptionLike) return host.deltaMovement;
    return super.getContactPointMotion(globalContactPoint);
  }

  @override
  void readAdditional(NbtMap compound, {bool spawnData = false}) {
    super.readAdditional(compound, spawnData: spawnData);
    if (compound.contains('ControllerRelative')) {
      controllerPos =
          compound.getBlockPos('ControllerRelative') +
          posContaining(host.position);
    }
    if (compound.contains('Axis')) {
      rotationAxis = enumByNameIgnoreCase(
        compound.getString('Axis'),
        Axis.values,
      );
    }
    angle = compound.getDouble('Angle');
  }

  @override
  void writeAdditional(NbtMap compound, {bool spawnPacket = false}) {
    super.writeAdditional(compound, spawnPacket: spawnPacket);
    final c = controllerPos;
    if (c != null)
      compound.putBlockPos(
        'ControllerRelative',
        c - posContaining(host.position),
      );
    final axis = rotationAxis;
    // Create writes `rotationAxis.name()`: the enum constant, i.e. `X`/`Y`/`Z`.
    // `readEnum` matches it exactly (an unknown name falls back to `Axis.X`); the port
    // also accepts the lower-case spelling of an older save.
    if (axis != null)
      compound.putString('Axis', enumNbtName(axis.serializedName));
    compound.putFloat('Angle', angle);
  }

  @override
  ContraptionRotationState getRotationState() {
    final crs = ContraptionRotationState();
    if (rotationAxis == Axis.x) crs.xRotation = angle;
    if (rotationAxis == Axis.y) crs.yRotation = angle;
    if (rotationAxis == Axis.z) crs.zRotation = angle;
    return crs;
  }

  @override
  Vec3 applyRotation(Vec3 localPos, double partialTicks) => VecHelper.rotate(
    localPos,
    getAngle(partialTicks),
    rotationAxis ?? Axis.y,
  );

  @override
  Vec3 reverseRotation(Vec3 localPos, double partialTicks) => VecHelper.rotate(
    localPos,
    -getAngle(partialTicks),
    rotationAxis ?? Axis.y,
  );

  /// `setAngle`.
  void setAngle(double newAngle) {
    angle = newAngle;
    for (final passenger in host.passengers) {
      positionRider(passenger);
    }
  }

  /// `getAngle(partialTicks)`.
  double getAngle(double partialTicks) => angle;

  /// `setRotationAxis`.
  void setRotationAxis(Axis axis) => rotationAxis = axis;

  /// `getRotationAxis`.
  Axis? get getRotationAxis => rotationAxis;

  @override
  Future<void> tickContraption() async {
    angleDelta = angle - prevAngle;
    prevAngle = angle;
    await tickActors();

    final pos = controllerPos;
    if (pos == null) return;
    if (!host.level.isLoaded(pos)) return;
    final controller = getController();
    if (controller == null) {
      host.remove();
      return;
    }
    if (!controller.isAttachedTo(this)) {
      controller.attach(this);
    }
  }

  /// `getController()`.
  IControlContraption? getController() {
    final pos = controllerPos;
    if (pos == null || !host.level.isLoaded(pos)) return null;
    final be = host.controllerAt(pos);
    return be is IControlContraption ? be : null;
  }

  @override
  bool shouldActorTrigger(
    MovementContext context,
    StructureBlockInfo blockInfo,
    MovementBehaviour actor,
    Vec3 actorPosition,
    Pos gridPosition,
  ) {
    if (super.shouldActorTrigger(
      context,
      blockInfo,
      actor,
      actorPosition,
      gridPosition,
    ))
      return true;

    final bearing = contraption;
    if (bearing is! BearingContraptionLike) return false;
    final facing = (bearing as BearingContraptionLike).facing;
    final activeAreaOffset = actor.getActiveAreaOffset(context);
    final plane = VecHelper.axisAlignedPlaneOf(facing);
    final offsetProduct = (
      activeAreaOffset.$1 * plane.$1,
      activeAreaOffset.$2 * plane.$2,
      activeAreaOffset.$3 * plane.$3,
    );
    if (offsetProduct != vec3Zero) return false;
    if (!VecHelper.onSameAxis(blockInfo.pos, posZero, facing.axis))
      return false;

    context.motion = facing.unitVec3 * (angleDelta / 360.0);
    context.relativeMotion = context.motion;
    final timer = context.data.getInt('StationaryTimer');
    if (timer > 0) {
      context.data.putInt('StationaryTimer', timer - 1);
      return false;
    }
    context.data.putInt('StationaryTimer', 20);
    return true;
  }

  @override
  StructureTransform makeStructureTransform() {
    final offset = posContaining(getAnchorVec() + (0.5, 0.5, 0.5));
    final xRot = rotationAxis == Axis.x ? angle : 0.0;
    final yRot = rotationAxis == Axis.y ? angle : 0.0;
    final zRot = rotationAxis == Axis.z ? angle : 0.0;
    return StructureTransform.angles(offset, xRot, yRot, zRot);
  }

  @override
  void onContraptionStalled() {
    getController()?.onStall();
    super.onContraptionStalled();
  }

  @override
  double getStalledAngle() => angle;

  @override
  void handleStallInformation(double x, double y, double z, double stallAngle) {
    host.setPosition((x, y, z));
    angle = stallAngle;
    prevAngle = stallAngle;
  }

  /// `teleportTo` does nothing: a controlled contraption is placed by its controller.
  void teleportTo(double x, double y, double z) {}
}

/// A bearing contraption (`BearingContraption`), as the controlled entity needs it.
abstract interface class BearingContraptionLike {
  Direction get facing;
}

/// `Math.sqrt` helper for angles that are stored in degrees.
double degreesOf(double radians) => radians * 180 / math.pi;
