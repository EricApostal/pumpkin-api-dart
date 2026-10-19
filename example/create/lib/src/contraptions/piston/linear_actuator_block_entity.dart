// `LinearActuatorBlockEntity` and `MechanicalPistonBlockEntity`: a kinetic block that moves a
// contraption along one axis by a fraction of a block per tick, with collision, the movement-mode
// scroll value and the sequenced distance limit.
//
// Java: `content/contraptions/piston/{LinearActuatorBlockEntity,MechanicalPistonBlockEntity}`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/value_settings.dart';
import '../../common/common.dart';
import '../../kinetics/api.dart';
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_nbt.dart';
import '../core/structure_info.dart';
import '../entity/contraption_entity.dart';
import '../entity/controlled_contraption_entity.dart';
import '../entity/i_control_contraption.dart';
import 'linear_actuator_logic.dart';
import 'piston_blocks.dart';
import 'piston_contraption.dart';

/// `LinearActuatorBlockEntity`: the common part of the piston and the gantry.
abstract class LinearActuatorBlockEntity extends KineticBlockEntity
    implements IControlContraption, ValueSettingsHost, AssemblyExceptionHolding {
  LinearActuatorBlockEntity(super.worldId, super.pos);

  double offset = 0;
  bool running = false;
  bool assembleNextTick = false;
  bool needsContraption = true;
  AbstractContraptionEntity? movedContraption;
  bool forceMove = true;
  bool waitingForSpeedChange = false;
  AssemblyException? lastException;
  double sequencedOffsetLimit = -1;

  ScrollValueBehaviour? _movementMode;

  /// The position as a [Pos]; the inherited `pos` is a host `BlockPos`.
  Pos get localPos => (this.pos.x, this.pos.y, this.pos.z);

  @override
  Pos getBlockPosition() => localPos;

  @override
  bool get syncSequenceContext => true;

  MovementMode get movementMode => MovementMode.values[(_movementMode?.value ?? 0).clamp(0, 2)];

  @override
  void onLoad() {
    lazyTickRate = 3;
    _movementMode = addBehaviour(
      ScrollValueBehaviour()
        ..between(0, 2)
        ..withCallback((_) => waitingForSpeedChange = false),
    );
    super.onLoad();
  }

  bool get isPassive => false;

  @override
  void tick() {
    super.tick();

    final contraption = movedContraption;
    if (contraption != null && !contraption.isAlive) movedContraption = null;

    if (isPassive) return;

    if (waitingForSpeedChange) {
      if (movedContraption != null) movedContraption!.host.setDeltaMovement(vec3Zero);
      return;
    }

    if (assembleNextTick) {
      assembleNextTick = false;
      if (running) {
        if (speed == 0) {
          tryDisassemble();
        } else {
          sendData();
        }
        return;
      }
      if (speed != 0) {
        unawaited(_assembleCatching());
      }
      sendData();
      return;
    }

    if (!running) return;

    final contraptionPresent = movedContraption != null;
    if (needsContraption && !contraptionPresent) return;

    var movementSpeed = getMovementSpeed();
    var locked = false;
    if (sequencedOffsetLimit > 0) {
      sequencedOffsetLimit = math.max(0, sequencedOffsetLimit - movementSpeed.abs());
      locked = sequencedOffsetLimit == 0;
    }
    final newOffset = offset + movementSpeed;
    if (newOffset.truncate() != offset.truncate()) visitNewPosition();

    if (locked) {
      forceMove = true;
      resetContraptionToOffset();
      sendData();
    }

    if (contraptionPresent) {
      if (moveAndCollideContraption()) {
        movedContraption!.host.setDeltaMovement(vec3Zero);
        offset = getGridOffset(offset).toDouble();
        resetContraptionToOffset();
        collided();
        return;
      }
    }

    if (!contraptionPresent || !movedContraption!.isStalled) offset = newOffset;

    final extensionRange = getExtensionRange();
    if (offset <= 0 || offset >= extensionRange) {
      offset = offset <= 0 ? 0.0 : extensionRange.toDouble();
      moveAndCollideContraption();
      resetContraptionToOffset();
      tryDisassemble();
      if (waitingForSpeedChange) {
        forceMove = true;
        sendData();
      }
      return;
    }
  }

  Future<void> _assembleCatching() async {
    try {
      await assemble();
      lastException = null;
    } on AssemblyException catch (e) {
      lastException = e;
    }
    sendData();
  }

  @override
  void lazyTick() {
    super.lazyTick();
    if (movedContraption != null) sendData();
  }

  int getGridOffset(double offset) => actuatorGridOffset(offset, getExtensionRange());

  double getInterpolatedOffset(double partialTicks) => actuatorInterpolatedOffset(
    offset,
    partialTicks,
    getMovementSpeed(),
    getExtensionRange(),
  );

  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    sequencedOffsetLimit = -1;
    if (isPassive) return;

    assembleNextTick = true;
    waitingForSpeedChange = false;

    final contraption = movedContraption;
    if (contraption != null && previousSpeed.sign != speed.sign && previousSpeed != 0) {
      if (!contraption.isStalled) {
        offset = (offset * 16).round() / 16.0;
        resetContraptionToOffset();
      }
      contraption.contraption?.stopMoving();
    }

    final seq = sequenceContext;
    if (seq != null && seq.instruction == SequencerInstructions.turnDistance) {
      sequencedOffsetLimit = seq.getEffectiveValue(theoreticalSpeed);
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putBool('Running', running);
    tag.putBool('Waiting', waitingForSpeedChange);
    tag.putFloat('Offset', offset);
    if (sequencedOffsetLimit >= 0) tag.putDouble('SequencedOffsetLimit', sequencedOffsetLimit);
    writeAssemblyException(tag, lastException);
    super.write(tag, clientPacket: clientPacket);
    if (clientPacket && forceMove) {
      tag.putBool('ForceMovement', forceMove);
      forceMove = false;
    }
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    final forceMovement = tag.containsKey('ForceMovement');
    running = tag.getBool('Running') ?? false;
    waitingForSpeedChange = tag.getBool('Waiting') ?? false;
    offset = tag.getDouble('Offset') ?? 0;
    sequencedOffsetLimit = tag.containsKey('SequencedOffsetLimit')
        ? (tag.getDouble('SequencedOffsetLimit') ?? 0)
        : -1;
    lastException = readAssemblyException(tag);
    super.read(tag, clientPacket: clientPacket);
    if (!clientPacket) return;
    if (forceMovement) {
      resetContraptionToOffset();
    }
    if (!running) movedContraption = null;
  }

  @override
  AssemblyException? get lastAssemblyException => lastException;

  Future<void> assemble();

  void disassemble();

  int getExtensionRange();

  int getInitialOffset();

  Vec3 toMotionVector(double speed);

  Vec3 toPosition(double offset);

  void visitNewPosition() {}

  void tryDisassemble() {
    if (removed) {
      disassemble();
      return;
    }
    if (actuatorWaitsForSpeedChange(
      neverPlace: movementMode == MovementMode.moveNeverPlace,
      placeReturned: movementMode == MovementMode.movePlaceReturned,
      offset: offset,
      initialOffset: getInitialOffset(),
    )) {
      waitingForSpeedChange = true;
      return;
    }
    disassemble();
  }

  bool moveAndCollideContraption() {
    final contraption = movedContraption;
    if (contraption == null) return false;
    if (contraption.isStalled) {
      contraption.host.setDeltaMovement(vec3Zero);
      return false;
    }
    final motion = getMotionVector();
    contraption.host.setDeltaMovement(motion);
    contraption.move(motion);
    return ContraptionCollision.collideBlocks?.call(contraption) ?? false;
  }

  void collided() {
    offset = getGridOffset(offset - getMovementSpeed()).toDouble();
    resetContraptionToOffset();
    tryDisassemble();
  }

  void resetContraptionToOffset() {
    final contraption = movedContraption;
    if (contraption == null || !contraption.isAlive) return;
    contraption.setPos(toPosition(offset));
    if (speed == 0 || waitingForSpeedChange) contraption.host.setDeltaMovement(vec3Zero);
  }

  double getMovementSpeed() {
    var movementSpeed = clampNum(convertToLinear(speed), -.49, .49);
    if (sequencedOffsetLimit >= 0) {
      movementSpeed = clampNum(movementSpeed, -sequencedOffsetLimit, sequencedOffsetLimit);
    }
    return movementSpeed;
  }

  Vec3 getMotionVector() => toMotionVector(getMovementSpeed());

  @override
  void onStall() {
    forceMove = true;
    sendData();
  }

  void onLengthBroken() {
    offset = 0;
    sendData();
  }

  @override
  bool isValid() => !removed;

  @override
  void attach(ControlledContraptionEntity contraption) {
    movedContraption = contraption;
    running = true;
    sendData();
  }

  @override
  bool isAttachedTo(AbstractContraptionEntity contraption) => movedContraption == contraption;

  @override
  void onRemoved() {
    disassemble();
    super.onRemoved();
  }

  @override
  List<ValueSettingsTarget> get valueSettingsTargets => [
    if (_movementMode case final m?) m,
  ];
}

/// `MechanicalPistonBlockEntity`.
class MechanicalPistonBlockEntity extends LinearActuatorBlockEntity implements PistonBlockEntityLookup {
  MechanicalPistonBlockEntity(super.worldId, super.pos);

  int extensionLength = 0;

  @override
  void startAssembly() => assembleNextTick = true;

  @override
  void clearAssemblyExceptionIfHeadMissing() {
    if (lastException == null) return;
    // `MechanicalPistonBlock.tick`: only clear when the piston still has a pole behind it, on
    // the piston's own axis.
    final direction = blockStateNow.dir('facing') ?? Direction.north;
    final behind = HostBlockGetter(world!).stateAt(localPos.relative(direction.opposite));
    if (!pistonHasPoleBehind(direction, behind)) return;
    lastException = null;
    sendData();
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    extensionLength = tag.getInt('ExtensionLength') ?? 0;
    super.read(tag, clientPacket: clientPacket);
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('ExtensionLength', extensionLength);
    super.write(tag, clientPacket: clientPacket);
  }

  BState get blockStateNow => HostBlockGetter.stateOfId(world!.getBlockStateId(pos: this.pos));

  @override
  Future<void> assemble() async {
    final level = ActuatorHosts.levelOf(worldId);
    final factory = ActuatorHosts.entities;
    if (level == null || factory == null) return;
    final state = blockStateNow;
    if (!isPistonStateKey(state.key)) return;

    final direction = state.dir('facing') ?? Direction.north;
    final contraption = PistonContraption(direction, getMovementSpeed() < 0);
    if (!await contraption.assemble(level, localPos)) return;

    final positive = Direction.fromAxisAndDirection(direction.axis, AxisDirection.positive);
    final movementDirection = (speed > 0) ^ (direction.axis != Axis.z) ? positive : positive.opposite;

    final anchor = contraption.anchor.relative(direction, contraption.initialExtensionProgress);
    if (ContraptionCollision.isCollidingWithWorld?.call(
          level,
          contraption,
          anchor.relative(movementDirection),
          movementDirection,
        ) ??
        false) {
      return;
    }

    extensionLength = contraption.extensionLength;
    final resultingOffset =
        contraption.initialExtensionProgress + getMovementSpeed().sign * .5;
    if (resultingOffset <= 0 || resultingOffset >= extensionLength) return;

    running = true;
    offset = contraption.initialExtensionProgress.toDouble();
    sendData();

    final startPos = posZero.relative(direction, contraption.initialExtensionProgress);
    await contraption.removeBlocksFromWorld(level, startPos);
    final entity = factory.createControlled(worldId, localPos, contraption);
    movedContraption = entity;
    resetContraptionToOffset();
    forceMove = true;
    factory.spawn(worldId, entity);
  }

  @override
  void disassemble() {
    if (!running && movedContraption == null) return;
    final world = this.world;
    if (!removed) {
      final state = blockStateNow;
      if (isPistonStateKey(state.key)) {
        unawaited(world!
            .setBlockState(
              pos: this.pos,
              state: BlockRegistry.resolveState(state.key, {
                    ...state.props,
                    'state': 'extended',
                  }) ??
                  0,
              // Java `3 | 16`: notify neighbours and clients, force the state.
              updateFlags: {
                BlockFlagsFlag.notifyNeighbors,
                BlockFlagsFlag.notifyListeners,
                BlockFlagsFlag.forceState,
              },
            )
            .catchError((Object _) {}));
      }
    } else if (world != null) {
      // `MechanicalPistonBlockEntity.disassemble`: a removed piston still breaks its head and
      // poles (`playerWillDestroy` with a `null` player, so they drop). The state at the
      // position is air already, so the facing comes from the moving contraption.
      final moving = movedContraption?.contraption;
      final direction = moving is PistonContraption
          ? moving.orientation
          : (blockStateNow.dir('facing') ?? Direction.north);
      unawaited(
        destroyPistonExtensions(world, localPos, direction, drop: true),
      );
    }
    final contraption = movedContraption;
    if (contraption != null) {
      resetContraptionToOffset();
      unawaited(contraption.disassemble());
    }
    running = false;
    movedContraption = null;
    sendData();
  }

  @override
  void collided() {
    super.collided();
    if (!running && getMovementSpeed() > 0) assembleNextTick = true;
  }

  @override
  double getMovementSpeed() => pistonMovementSpeed(
    speed: speed,
    facing: blockStateNow.dir('facing') ?? Direction.north,
    offset: offset,
    extensionRange: getExtensionRange(),
    sequencedOffsetLimit: sequencedOffsetLimit,
  );

  @override
  int getExtensionRange() => extensionLength;

  @override
  Vec3 toMotionVector(double speed) => (blockStateNow.dir('facing') ?? Direction.north).unitVec3 * speed;

  @override
  Vec3 toPosition(double offset) {
    final contraption = movedContraption?.contraption;
    final anchor = contraption?.anchor ?? posZero;
    return anchor.toVec3() + (blockStateNow.dir('facing') ?? Direction.north).unitVec3 * offset;
  }

  @override
  int getInitialOffset() {
    final contraption = movedContraption?.contraption;
    return contraption is PistonContraption ? contraption.initialExtensionProgress : 0;
  }
}
