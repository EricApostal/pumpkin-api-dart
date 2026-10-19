// `GantryContraptionEntity`: moves a `GantryContraption` along the gantry shaft it hangs from. The
// shaft itself (`create:gantry_shaft`) belongs to the kinetics module; this asks it through
// [GantryShaftLike].
//
// Java: `content/contraptions/gantry/GantryContraptionEntity`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../kinetics/api.dart' show SequenceContext;
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_runtime.dart';
import '../core/contraption.dart';
import '../core/nbt_map.dart';
import '../core/structure_transform.dart';
import '../entity/contraption_entity.dart';
import 'gantry_contraption.dart';

/// The parts of a `GantryShaftBlockEntity` a gantry needs.
abstract interface class GantryShaftLike {
  BState get shaftState;

  /// `getPinionMovementSpeed()`.
  double get pinionMovementSpeed;

  /// `canAssembleOn()`.
  bool get canAssembleOn;

  SequenceContext? get sequenceContext;

  double get theoreticalSpeed;
}

/// Looks a gantry shaft up in the block entity store.
abstract final class GantryShafts {
  static GantryShaftLike? at(String worldId, Pos pos) {
    final runtime = ActuatorRuntime.maybe;
    if (runtime == null) return null;
    final be = runtime.store.at(
      worldId,
      BlockPos(x: pos.$1, y: pos.$2, z: pos.$3),
    );
    return be is GantryShaftLike ? be as GantryShaftLike : null;
  }
}

class GantryContraptionEntity extends AbstractContraptionEntity {
  Direction movementAxis;
  double sequencedOffsetLimit = -1;
  double axisMotion = 0;
  int _ticks = 0;

  GantryContraptionEntity(super.host, [this.movementAxis = Direction.north]);

  /// `create(level, contraption, movementAxis)`.
  static GantryContraptionEntity create(
    ContraptionEntityHost host,
    Contraption contraption,
    Direction movementAxis,
  ) {
    final entity = GantryContraptionEntity(host, movementAxis);
    entity.setContraption(contraption);
    return entity;
  }

  /// `limitMovement(maxOffset)`.
  void limitMovement(double maxOffset) => sequencedOffsetLimit = maxOffset;

  @override
  Future<void> tickContraption() async {
    final gantry = contraption;
    if (gantry is! GantryContraption) return;
    _ticks++;

    checkPinionShaft();
    await tickActors();

    if (ContraptionCollision.collideBlocks?.call(this) ?? false) {
      unawaited(disassemble());
      return;
    }

    final previousAxisMotion = axisMotion;
    if (!isStalled && _ticks > 2) {
      var movement = host.deltaMovement;
      if (sequencedOffsetLimit >= 0) {
        movement = (
          movement.$1.clamp(-sequencedOffsetLimit, sequencedOffsetLimit),
          movement.$2.clamp(-sequencedOffsetLimit, sequencedOffsetLimit),
          movement.$3.clamp(-sequencedOffsetLimit, sequencedOffsetLimit),
        );
      }
      move(movement);
      if (sequencedOffsetLimit > 0) {
        sequencedOffsetLimit = math.max(
          0,
          sequencedOffsetLimit - movement.length,
        );
      }
    }

    if (axisMotion.sign != previousAxisMotion.sign && previousAxisMotion != 0) {
      contraption?.stopMoving();
    }
    if (axisMotion != previousAxisMotion || _ticks % 3 == 0) _sendUpdate();
  }

  /// `checkPinionShaft`: the shaft must exist, be unpowered and be turning.
  void checkPinionShaft() {
    final gantry = contraption;
    if (gantry is! GantryContraption) return;
    final facing = gantry.getFacing();
    final current = getAnchorVec() + (0.5, 0.5, 0.5);
    final shaftPos = posContaining(current).relative(facing.opposite);
    final shaft = GantryShafts.at(host.level.worldId, shaftPos);
    if (shaft == null || shaft.shaftState.key != 'create:gantry_shaft') {
      host.setDeltaMovement(vec3Zero);
      unawaited(disassemble());
      return;
    }

    final direction = shaft.shaftState.dir('facing') ?? Direction.north;
    var speed = shaft.pinionMovementSpeed;
    if (shaft.shaftState.flag('powered') || speed == 0) {
      host.setDeltaMovement(vec3Zero);
      unawaited(disassemble());
      return;
    }

    if (sequencedOffsetLimit >= 0) {
      speed = speed.clamp(-sequencedOffsetLimit, sequencedOffsetLimit);
    }
    axisMotion = speed;
    host.setDeltaMovement(direction.unitVec3 * speed);
  }

  void _sendUpdate() {
    host.sendPayload('create:gantry_update', {
      'entityID': host.entityId,
      'coord': _axisCoord(),
      'motion': axisMotion,
      'sequenceLimit': sequencedOffsetLimit,
    });
  }

  /// `getAxisCoord()`: the anchor coordinate along the movement axis (the packet's `coord`).
  double _axisCoord() {
    final anchor = getAnchorVec();
    return movementAxis.axis.choose(anchor.$1, anchor.$2, anchor.$3);
  }

  @override
  void writeAdditional(NbtMap compound, {bool spawnPacket = false}) {
    super.writeAdditional(compound, spawnPacket: spawnPacket);
    compound.putString('GantryAxis', movementAxis.name.toUpperCase());
    if (sequencedOffsetLimit >= 0)
      compound.putDouble('SequencedOffsetLimit', sequencedOffsetLimit);
  }

  @override
  void readAdditional(NbtMap compound, {bool spawnData = false}) {
    // `readEnum(compound, "GantryAxis", Direction.class)`: the Java enum name (upper case), with
    // `Direction.values()[0]` ([Direction.down]) as the fallback.
    movementAxis =
        Direction.byName(compound.getString('GantryAxis').toLowerCase()) ??
        Direction.values[0];
    sequencedOffsetLimit = compound.contains('SequencedOffsetLimit')
        ? compound.getDouble('SequencedOffsetLimit')
        : -1;
    super.readAdditional(compound, spawnData: spawnData);
  }

  @override
  StructureTransform makeStructureTransform() => StructureTransform.identity(
    posContaining(getAnchorVec() + (0.5, 0.5, 0.5)),
  );

  @override
  ContraptionRotationState getRotationState() => ContraptionRotationState.none;

  @override
  Vec3 applyRotation(Vec3 localPos, double partialTicks) => localPos;

  @override
  Vec3 reverseRotation(Vec3 localPos, double partialTicks) => localPos;

  @override
  double getStalledAngle() => 0;

  @override
  void handleStallInformation(double x, double y, double z, double angle) {
    host.setPosition((x, y, z));
  }

  @override
  Future<void> disassemble() async {
    sequencedOffsetLimit = -1;
    await super.disassemble();
  }
}
