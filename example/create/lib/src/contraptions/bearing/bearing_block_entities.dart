// The block entities of the bearing family: `MechanicalBearingBlockEntity` (a generating bearing
// that rotates a contraption), `WindmillBearingBlockEntity` (a generating bearing whose speed comes
// from its sails) and `ClockworkBearingBlockEntity` (two arms that follow the time of day).
//
// Java: `content/contraptions/bearing/{MechanicalBearingBlockEntity,WindmillBearingBlockEntity,
// ClockworkBearingBlockEntity,IBearingBlockEntity}`.
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
import '../blocks/actuator_runtime.dart';
import '../core/level.dart';
import '../core/structure_info.dart';
import '../entity/contraption_entity.dart';
import '../entity/controlled_contraption_entity.dart';
import '../entity/i_control_contraption.dart';
import 'bearing_blocks.dart';
import 'bearing_contraptions.dart';

/// `IBearingBlockEntity`: a bearing tells the client its angle and whether its top is wooden.
abstract interface class IBearingBlockEntity {
  /// `getInterpolatedAngle(partialTicks)`.
  double getInterpolatedAngle(double partialTicks);

  /// `isWoodenTop()`.
  bool get isWoodenTop;

  /// `setAngle(forcedAngle)`.
  void setAngle(double forcedAngle);
}

/// `MechanicalBearingBlockEntity`.
class MechanicalBearingBlockEntity extends GeneratingKineticBlockEntity
    implements
        IControlContraption,
        IBearingBlockEntity,
        ValueSettingsHost,
        RunningActuator,
        AssemblyExceptionHolding {
  MechanicalBearingBlockEntity(super.worldId, super.pos) {
    // `addBehaviours` adds the movement mode at construction, before `read` restores `ScrollValue`
    // (`WindmillBearingBlockEntity.addBehaviours` removes it again; both behaviours would write the
    // same key otherwise). Adding it in `onLoad` is too late: `BlockEntityStore.install` calls
    // `read` before `onLoad`.
    if (!isWindmill) {
      _movementMode = addBehaviour(ScrollValueBehaviour().between(0, 2));
    }
  }

  ControlledContraptionEntity? movedContraption;
  double angle = 0;
  bool running = false;
  bool assembleNextTick = false;
  AssemblyException? lastException;
  double sequencedAngleLimit = -1;

  ScrollValueBehaviour? _movementMode;

  @override
  bool get isWoodenTop => false;

  @override
  bool get syncSequenceContext => true;

  /// `movementMode.get()` as a [RotationMode].
  RotationMode get movementMode =>
      RotationMode.values[(_movementMode?.value ?? 0).clamp(0, 2)];

  @override
  void onLoad() {
    lazyTickRate = 3;
    super.onLoad();
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putBool('Running', running);
    tag.putFloat('Angle', angle);
    if (sequencedAngleLimit >= 0)
      tag.putDouble('SequencedAngleLimit', sequencedAngleLimit);
    writeAssemblyException(tag, lastException);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    if (wasMoved) {
      super.read(tag, clientPacket: clientPacket);
      return;
    }
    running = tag.getBool('Running') ?? false;
    angle = tag.getDouble('Angle') ?? 0;
    sequencedAngleLimit = tag.containsKey('SequencedAngleLimit')
        ? (tag.getDouble('SequencedAngleLimit') ?? 0)
        : -1;
    lastException = readAssemblyException(tag);
    super.read(tag, clientPacket: clientPacket);
  }

  @override
  double getInterpolatedAngle(double partialTicks) {
    final contraption = movedContraption;
    if (contraption == null || contraption.isStalled || !running)
      partialTicks = 0;
    var angularSpeed = getAngularSpeed();
    if (sequencedAngleLimit >= 0) {
      angularSpeed = angularSpeed.clamp(
        -sequencedAngleLimit,
        sequencedAngleLimit,
      );
    }
    return angle + angularSpeed * partialTicks;
  }

  @override
  void onSpeedChanged(double prevSpeed) {
    super.onSpeedChanged(prevSpeed);
    assembleNextTick = true;
    sequencedAngleLimit = -1;

    final contraption = movedContraption;
    if (contraption != null && prevSpeed.sign != speed.sign && prevSpeed != 0) {
      if (!contraption.isStalled) {
        angle = angle.roundToDouble();
        applyRotation();
      }
      contraption.contraption?.stopMoving();
    }

    final seq = sequenceContext;
    if (!isWindmill &&
        seq != null &&
        seq.instruction == SequencerInstructions.turnAngle) {
      sequencedAngleLimit = seq.getEffectiveValue(theoreticalSpeed);
    }
  }

  /// `getAngularSpeed`: degrees per tick.
  double getAngularSpeed() {
    var angular = convertToAngular(isWindmill ? generatedSpeed : speed);
    if (speed == 0) angular = 0;
    return angular;
  }

  @override
  AssemblyException? get lastAssemblyException => lastException;

  bool get isWindmill => false;

  /// The position as a [Pos]; the inherited `pos` is a host `BlockPos` and the `pos` of
  /// `common/pos.dart` shadows it in this library.
  Pos get localPos => (this.pos.x, this.pos.y, this.pos.z);

  @override
  Pos getBlockPosition() => localPos;

  /// `assemble`.
  Future<void> assemble() async {
    final level = ActuatorHosts.levelOf(worldId);
    final factory = ActuatorHosts.entities;
    if (level == null || factory == null) return;
    final state = HostBlockGetter.stateOfId(
      world!.getBlockStateId(pos: this.pos),
    );
    if (!bearingBlocks.contains(state.key)) return;

    final direction = state.dir('facing') ?? Direction.north;
    final contraption = BearingContraption(isWindmill, direction);
    try {
      if (!await contraption.assemble(level, localPos)) return;
      lastException = null;
    } on AssemblyException catch (e) {
      lastException = e;
      sendData();
      return;
    }

    await contraption.removeBlocksFromWorld(level, posZero);
    final entity = factory.createControlled(worldId, localPos, contraption);
    final anchor = localPos.relative(direction);
    entity.setPos(anchor.toVec3());
    entity.setRotationAxis(direction.axis);
    factory.spawn(worldId, entity);
    movedContraption = entity;

    // `AllSoundEvents.CONTRAPTION_ASSEMBLE.playOnServer(level, worldPosition)`.
    world?.playCustomSound(
      soundName: 'create:contraption_assemble',
      category: SoundCategory.blocks,
      pos: localPos.center,
      volume: 1,
      pitch: 1,
    );

    running = true;
    angle = 0;
    sendData();
    updateGeneratedRotation();
  }

  /// `disassemble`.
  void disassemble() {
    final contraption = movedContraption;
    if (!running && contraption == null) return;
    angle = 0;
    sequencedAngleLimit = -1;
    if (isWindmill) applyRotation();
    if (contraption != null) {
      // `AllSoundEvents.CONTRAPTION_DISASSEMBLE.playOnServer(level, worldPosition)`.
      world?.playCustomSound(
        soundName: 'create:contraption_disassemble',
        category: SoundCategory.blocks,
        pos: localPos.center,
        volume: 1,
        pitch: 1,
      );
      unawaited(contraption.disassemble());
    }
    movedContraption = null;
    running = false;
    updateGeneratedRotation();
    assembleNextTick = false;
    sendData();
  }

  @override
  void tick() {
    super.tick();

    if (assembleNextTick) {
      assembleNextTick = false;
      if (running) {
        final canDisassemble =
            movementMode == RotationMode.rotatePlace ||
            (isNearInitialAngle() &&
                movementMode == RotationMode.rotatePlaceReturned);
        final contraption = movedContraption;
        if (speed == 0 &&
            (canDisassemble ||
                contraption == null ||
                contraption.contraption?.blocks.isEmpty == true)) {
          contraption?.contraption?.stopMoving();
          disassemble();
          return;
        }
      } else {
        if (speed == 0 && !isWindmill) return;
        unawaited(assemble());
      }
    }

    if (!running) return;

    final contraption = movedContraption;
    if (!(contraption != null && contraption.isStalled)) {
      var angularSpeed = getAngularSpeed();
      if (sequencedAngleLimit >= 0) {
        angularSpeed = angularSpeed.clamp(
          -sequencedAngleLimit,
          sequencedAngleLimit,
        );
        sequencedAngleLimit = math.max(
          0,
          sequencedAngleLimit - angularSpeed.abs(),
        );
      }
      angle = (angle + angularSpeed) % 360;
    }

    applyRotation();
  }

  bool isNearInitialAngle() => angle.abs() < 22.5 || angle.abs() > 360 - 22.5;

  @override
  void lazyTick() {
    super.lazyTick();
    if (movedContraption != null) sendData();
  }

  void applyRotation() {
    final contraption = movedContraption;
    if (contraption == null) return;
    contraption.setAngle(angle);
    final state = HostBlockGetter.stateOfId(
      world!.getBlockStateId(pos: this.pos),
    );
    final facing = state.dir('facing');
    if (facing != null) contraption.setRotationAxis(facing.axis);
  }

  @override
  void attach(ControlledContraptionEntity contraption) {
    if (contraption.contraption is! BearingContraption) return;
    final state = HostBlockGetter.stateOfId(
      world!.getBlockStateId(pos: this.pos),
    );
    final facing = state.dir('facing');
    if (facing == null) return;
    movedContraption = contraption;
    markDirty();
    final anchor = localPos.relative(facing);
    contraption.setPos(anchor.toVec3());
    running = true;
    sendData();
  }

  @override
  void onStall() => sendData();

  @override
  bool isValid() => !removed;

  @override
  bool isAttachedTo(AbstractContraptionEntity contraption) =>
      movedContraption == contraption;

  /// `isRunning()` (`RunningActuator`): whether the bearing is moving its contraption.
  @override
  bool get isRunning => running;

  @override
  void setAngle(double forcedAngle) => angle = forcedAngle;

  ControlledContraptionEntity? getMovedContraption() => movedContraption;

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

/// `WindmillBearingBlockEntity`.
class WindmillBearingBlockEntity extends MechanicalBearingBlockEntity {
  WindmillBearingBlockEntity(super.worldId, super.pos) {
    // `addBehaviours`: added at construction so `read` restores the saved `ScrollValue`.
    _movementDirection = addBehaviour(
      ScrollValueBehaviour()
          .between(0, 1)
          .withCallback((_) => _onDirectionChanged()),
    );
  }

  double lastGeneratedSpeed = 0;
  bool queuedReassembly = false;
  ScrollValueBehaviour? _movementDirection;

  @override
  bool get isWoodenTop => true;

  @override
  bool get isWindmill => true;

  /// `onDirectionChanged`: a running windmill reverses at once.
  void _onDirectionChanged() {
    if (!running) return;
    updateGeneratedRotation();
  }

  /// The windmill has the rotation direction instead of the movement mode.
  @override
  List<ValueSettingsTarget> get valueSettingsTargets => [
    if (_movementDirection case final m?) m,
  ];

  @override
  void updateGeneratedRotation() {
    super.updateGeneratedRotation();
    lastGeneratedSpeed = generatedSpeed;
    queuedReassembly = false;
  }

  @override
  void onSpeedChanged(double prevSpeed) {
    final cancelAssembly = assembleNextTick;
    super.onSpeedChanged(prevSpeed);
    assembleNextTick = cancelAssembly;
  }

  @override
  void tick() {
    super.tick();
    if (!queuedReassembly) return;
    queuedReassembly = false;
    if (!running) assembleNextTick = true;
  }

  /// `disassembleForMovement`: the windmill bearing lets go while the structure moves.
  void disassembleForMovement() {
    if (!running) return;
    disassemble();
    queuedReassembly = true;
  }

  @override
  double get generatedSpeed {
    if (!running) return 0;
    final contraption = movedContraption?.contraption;
    if (contraption == null) return lastGeneratedSpeed;
    final sails = contraption is BearingContraption
        ? contraption.getSailBlocks()
        : 0;
    final perRpm = ActuatorRuntime.instance.settings.windmillSailsPerRPM;
    return (sails ~/ perRpm).clamp(1, 16) * angleSpeedDirection;
  }

  double get angleSpeedDirection =>
      (_movementDirection?.value ?? 0) == 0 ? 1 : -1;

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putFloat('LastGenerated', lastGeneratedSpeed);
    tag.putBool('QueueAssembly', queuedReassembly);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    if (!wasMoved) lastGeneratedSpeed = tag.getDouble('LastGenerated') ?? 0;
    queuedReassembly = tag.getBool('QueueAssembly') ?? false;
    super.read(tag, clientPacket: clientPacket);
  }
}

/// `ClockworkBearingBlockEntity`: two arms that follow the time of day.
class ClockworkBearingBlockEntity extends KineticBlockEntity
    implements
        IControlContraption,
        IBearingBlockEntity,
        ValueSettingsHost,
        RunningActuator,
        AssemblyExceptionHolding {
  ClockworkBearingBlockEntity(super.worldId, super.pos) {
    // `addBehaviours`: added at construction so `read` restores the saved `ScrollValue`.
    _operationMode = addBehaviour(ScrollValueBehaviour().between(0, 2));
  }

  ControlledContraptionEntity? hourHand;
  ControlledContraptionEntity? minuteHand;
  double hourAngle = 0;
  double minuteAngle = 0;
  bool running = false;
  bool assembleNextTick = false;
  AssemblyException? lastException;

  ScrollValueBehaviour? _operationMode;

  @override
  bool get isWoodenTop => false;

  /// The position as a [Pos]; the inherited `pos` is a host `BlockPos` and the `pos` of
  /// `common/pos.dart` shadows it in this library.
  Pos get localPos => (this.pos.x, this.pos.y, this.pos.z);

  @override
  Pos getBlockPosition() => localPos;

  /// `ClockHands` as the scroll value: 0 hour first, 1 minute first, 2 hour first (24h).
  int get clockHands => (_operationMode?.value ?? 0).clamp(0, 2);

  @override
  void onLoad() {
    lazyTickRate = 3;
    super.onLoad();
  }

  @override
  void tick() {
    super.tick();

    if (assembleNextTick) {
      assembleNextTick = false;
      if (running) {
        if (speed == 0) {
          hourHand?.contraption?.stopMoving();
          minuteHand?.contraption?.stopMoving();
          disassemble();
        }
        return;
      }
      unawaited(assemble());
      return;
    }

    if (!running) return;

    final hour = hourHand;
    if (!(hour != null && hour.isStalled)) {
      hourAngle = (hourAngle + getHourArmSpeed()) % 360;
    }
    final minute = minuteHand;
    if (!(minute != null && minute.isStalled)) {
      minuteAngle = (minuteAngle + getMinuteArmSpeed()) % 360;
    }
    applyRotations();
  }

  void applyRotations() {
    final state = HostBlockGetter.stateOfId(
      world!.getBlockStateId(pos: this.pos),
    );
    final axis = state.dir('facing')?.axis ?? Axis.x;
    final hour = hourHand;
    if (hour != null) {
      hour.setAngle(hourAngle);
      hour.setRotationAxis(axis);
    }
    final minute = minuteHand;
    if (minute != null) {
      minute.setAngle(minuteAngle);
      minute.setRotationAxis(axis);
    }
  }

  @override
  void lazyTick() {
    super.lazyTick();
    if (hourHand != null) sendData();
  }

  double getHourArmSpeed() {
    var armSpeed = getAngularSpeed() / 2;
    if (armSpeed != 0) {
      final mode = clockHands;
      final target = mode == 1 ? getMinuteTarget() : getHourTarget(mode == 2);
      final diff = shortestAngleDiff(hourAngle, target);
      armSpeed = diff < 0
          ? math.max(armSpeed, diff)
          : math.min(-armSpeed, diff);
    }
    return armSpeed;
  }

  double getMinuteArmSpeed() {
    var armSpeed = getAngularSpeed();
    if (armSpeed != 0) {
      final target = clockHands == 1 ? getHourTarget(false) : getMinuteTarget();
      final diff = shortestAngleDiff(minuteAngle, target);
      armSpeed = diff < 0
          ? math.max(armSpeed, diff)
          : math.min(-armSpeed, diff);
    }
    return armSpeed;
  }

  double getHourTarget(bool cycle24) {
    final dayTime = _dayTime();
    final hours = (dayTime ~/ 1000 + 6) % 24;
    final offset = _armDirectionStep;
    return (offset *
        -360 /
        (cycle24 ? 24 : 12) *
        (hours % (cycle24 ? 24 : 12)));
  }

  double getMinuteTarget() {
    final dayTime = _dayTime();
    final minutes = (dayTime % 1000) * 60 ~/ 1000;
    final offset = _armDirectionStep;
    return (offset * -360 / 60 * minutes);
  }

  /// `level.getOverworldClockTime()` as the day time in ticks.
  int _dayTime() {
    final w = world;
    if (w == null) return 0;
    return w.getWorldAge() % 24000;
  }

  /// `getBlockState().getValue(FACING).getAxisDirection().getStep()`.
  int get _armDirectionStep {
    final state = HostBlockGetter.stateOfId(
      world!.getBlockStateId(pos: this.pos),
    );
    return state.dir('facing')?.axisDirection.step ?? 1;
  }

  double getAngularSpeed() => -(speed.abs() * 3 / 10);

  /// `assemble`: both arms, each as its own contraption entity.
  Future<void> assemble() async {
    final level = ActuatorHosts.levelOf(worldId);
    final factory = ActuatorHosts.entities;
    if (level == null || factory == null) return;
    final state = HostBlockGetter.stateOfId(
      world!.getBlockStateId(pos: this.pos),
    );
    if (state.key != clockworkBearing) return;
    final direction = state.dir('facing') ?? Direction.north;

    final (hour, minute) = (() {
      try {
        final result = ClockworkContraption.assembleClockworkAt(
          level,
          localPos,
          direction,
        );
        lastException = null;
        return result ?? (null, null);
      } on AssemblyException catch (e) {
        lastException = e;
        sendData();
        return (null, null);
      }
    })();
    if (hour == null || hour.blocks.isEmpty) return;

    var anchor = localPos.relative(direction);
    await hour.removeBlocksFromWorld(level, posZero);
    final hourEntity = factory.createControlled(worldId, localPos, hour);
    hourEntity.setPos(anchor.toVec3());
    hourEntity.setRotationAxis(direction.axis);
    factory.spawn(worldId, hourEntity);
    hourHand = hourEntity;

    if (minute != null) {
      anchor = localPos.relative(direction, minute.offset + 1);
      await minute.removeBlocksFromWorld(level, posZero);
      final minuteEntity = factory.createControlled(worldId, localPos, minute);
      minuteEntity.setPos(anchor.toVec3());
      minuteEntity.setRotationAxis(direction.axis);
      factory.spawn(worldId, minuteEntity);
      minuteHand = minuteEntity;
    }

    running = true;
    hourAngle = 0;
    minuteAngle = 0;
    sendData();
  }

  /// `disassemble`.
  void disassemble() {
    if (!running && hourHand == null && minuteHand == null) return;
    hourAngle = 0;
    minuteAngle = 0;
    applyRotations();
    if (hourHand case final h?) unawaited(h.disassemble());
    if (minuteHand case final m?) unawaited(m.disassemble());
    hourHand = null;
    minuteHand = null;
    running = false;
    sendData();
  }

  @override
  void attach(ControlledContraptionEntity contraption) {
    final cc = contraption.contraption;
    if (cc is! ClockworkContraption) return;
    markDirty();
    final state = HostBlockGetter.stateOfId(
      world!.getBlockStateId(pos: this.pos),
    );
    final facing = state.dir('facing') ?? Direction.north;
    final anchor = localPos.relative(facing, cc.offset + 1);
    if (cc.handType == HandType.hour) {
      hourHand = contraption;
      contraption.setPos(anchor.toVec3());
    } else {
      minuteHand = contraption;
      contraption.setPos(anchor.toVec3());
    }
    running = true;
    sendData();
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putBool('Running', running);
    tag.putFloat('HourAngle', hourAngle);
    tag.putFloat('MinuteAngle', minuteAngle);
    writeAssemblyException(tag, lastException);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    running = tag.getBool('Running') ?? false;
    hourAngle = tag.getDouble('HourAngle') ?? 0;
    minuteAngle = tag.getDouble('MinuteAngle') ?? 0;
    lastException = readAssemblyException(tag);
    super.read(tag, clientPacket: clientPacket);
  }

  @override
  void onSpeedChanged(double prevSpeed) {
    super.onSpeedChanged(prevSpeed);
    assembleNextTick = true;
  }

  @override
  bool isValid() => !removed;

  @override
  double getInterpolatedAngle(double partialTicks) =>
      hourAngle + getHourArmSpeed() * partialTicks;

  @override
  void onStall() => sendData();

  @override
  void onRemoved() {
    disassemble();
    super.onRemoved();
  }

  @override
  bool isAttachedTo(AbstractContraptionEntity contraption) {
    final cc = contraption.contraption;
    if (cc is! ClockworkContraption) return false;
    return cc.handType == HandType.hour
        ? hourHand == contraption
        : minuteHand == contraption;
  }

  /// `isRunning()` (`RunningActuator`): whether the bearing is moving its contraption.
  @override
  bool get isRunning => running;

  @override
  void setAngle(double forcedAngle) => hourAngle = forcedAngle;

  @override
  AssemblyException? get lastAssemblyException => lastException;

  @override
  List<ValueSettingsTarget> get valueSettingsTargets => [
    if (_operationMode case final m?) m,
  ];
}

/// `AngleHelper.getShortestAngleDiff`.
double shortestAngleDiff(double from, double to) {
  var diff = (to - from) % 360;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return diff;
}

/// A block entity that remembers the last assembly exception (`IDisplayAssemblyExceptions`).

/// The `ContraptionLevel` of a world, or `null` when the host adapter is not installed.
ContraptionLevel? levelOf(String worldId) => ActuatorHosts.levelOf(worldId);

/// The state of a block entity's block, as a [BState].
BState stateOf(String worldId, Pos pos) {
  final w = ActuatorRuntime.instance.worlds.byId(worldId);
  if (w == null) return BState.air;
  return HostBlockGetter.stateOfId(
    w.getBlockStateId(
      pos: BlockPos(x: pos.$1, y: pos.$2, z: pos.$3),
    ),
  );
}

/// A structure block info at [pos] with [state] and no block entity data.
StructureBlockInfo infoAt(Pos pos, BState state) =>
    StructureBlockInfo(pos, state);
