// `ElevatorPulleyBlockEntity`: the pulley of an elevator. It turns the column's target floor into a
// rope offset and stops with the contraption at the floor's contact.
//
// Java: `content/contraptions/elevator/ElevatorPulleyBlockEntity`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter;
import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../../kinetics/api.dart';
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_runtime.dart';
import '../entity/controlled_contraption_entity.dart';
import '../pulley/pulley_block_entity.dart';
import 'elevator_column.dart';
import 'elevator_contact_block_entity.dart';
import 'elevator_contraption.dart';

class ElevatorPulleyBlockEntity extends PulleyBlockEntity {
  ElevatorPulleyBlockEntity(super.worldId, super.pos);

  double _prevSpeed = 0;
  bool arrived = true;
  int clientOffsetTarget = 0;
  bool _initialOffsetReceived = false;

  BState get _state =>
      HostBlockGetter.stateOfId(world!.getBlockStateId(pos: this.pos));

  ElevatorContraption? get _elevator {
    final contraption = movedContraption?.contraption;
    return contraption is ElevatorContraption ? contraption : null;
  }

  /// `getTargetOffset`: the rope length that puts the contraption at the target floor.
  int getTargetOffset() {
    final elevator = _elevator;
    if (elevator == null) return offset.truncate();
    final target = elevator.getCurrentTargetY();
    if (target == null) return offset.truncate();
    return this.pos.y - target + elevator.contactYOffset - 1;
  }

  @override
  void attach(ControlledContraptionEntity contraption) {
    super.attach(contraption);
    if (offset >= 0) resetContraptionToOffset();
    final elevator = _elevator;
    if (elevator == null) return;
    final coords = elevator.getGlobalColumn();
    if (coords != null)
      ElevatorColumn.getOrCreate(worldId, coords).setActive(true);
  }

  @override
  void tick() {
    final wasArrived = arrived;
    super.tick();

    final elevator = _elevator;
    if (elevator == null) return;

    waitingForSpeedChange = false;
    elevator.arrived = wasArrived;

    if (!arrived) return;

    final entity = movedContraption;
    if (entity == null) return;
    final y = entity.position.$2;
    var targetLevel = (0.5 + y).floor() + elevator.contactYOffset;

    final currentTarget = elevator.getCurrentTargetY();
    if (currentTarget != null) targetLevel = currentTarget;

    if (!wasArrived) {
      _triggerContact(elevator, targetLevel - elevator.contactYOffset);
      // `AllSoundEvents.CONTRAPTION_DISASSEMBLE.play(level, null, worldPosition.below(offset))`.
      world?.playCustomSound(
        soundName: 'create:contraption_disassemble',
        category: SoundCategory.blocks,
        pos: (localPos.$1 + .5, localPos.$2 - offset, localPos.$3 + .5),
        volume: 0.75,
        pitch: 0.8,
      );
    }

    var diff = (targetLevel - y - elevator.contactYOffset).toDouble();
    if (diff.abs() > 1 / 128) diff *= 0.25;
    entity.setPos(entity.position + (0, diff, 0));
  }

  @override
  void lazyTick() {
    super.lazyTick();
    if (!arrived) return;
    final entity = movedContraption;
    if (entity == null || !entity.isAlive) return;
    final elevator = _elevator;
    if (elevator == null) return;
    if (getTargetOffset() != offset.truncate()) return;

    final targetLevel = (0.5 + entity.position.$2).floor();
    _triggerContact(elevator, targetLevel);
  }

  /// `triggerContact`: the contact at the reached floor pulses its redstone output.
  void _triggerContact(ElevatorContraption elevator, int targetLevel) {
    final coords = elevator.getGlobalColumn();
    if (coords == null) return;
    final column = ElevatorColumn.get(worldId, coords);
    if (column == null) return;

    final contactPos = column.contactAt(targetLevel + elevator.contactYOffset);
    final world = this.world;
    if (world == null) return;
    if (!world.isLoaded(pos: contactPos.toBlockPos())) return;
    final state = HostBlockGetter(world).stateAt(contactPos);
    if (state.key != 'create:elevator_contact') return;
    if (state.flag('powering')) return;

    final be = ActuatorRuntime.instance.store.at(
      worldId,
      BlockPos(x: contactPos.$1, y: contactPos.$2, z: contactPos.$3),
    );
    if (be is ElevatorContactBlockEntity) {
      be.activateBlock = true;
      be.markDirty();
    }
    world.scheduleBlockTick(
      pos: BlockPos(x: contactPos.$1, y: contactPos.$2, z: contactPos.$3),
      delayTicks: 1,
      priority: TickPriority.normal,
    );
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    if (clientPacket) tag.putInt('ClientTarget', clientOffsetTarget);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (!clientPacket) return;
    clientOffsetTarget = tag.getInt('ClientTarget') ?? 0;
    if (_initialOffsetReceived) return;
    offset = tag.getDouble('Offset') ?? 0;
    _initialOffsetReceived = true;
    resetContraptionToOffset();
  }

  @override
  double getMovementSpeed() {
    final currentTarget = getTargetOffset();
    if (currentTarget != clientOffsetTarget) {
      clientOffsetTarget = currentTarget;
      sendData();
    }

    final diff = (currentTarget - offset).toDouble();
    var movementSpeed = clampNum(convertToLinear(speed * 2), -1.99, 1.99);
    final rpmLimit = movementSpeed.abs();

    final configAcc = 0.0075 + (0.0175 - 0.0075) * movementSpeed.abs();
    final deceleration = math.sqrt(2 * diff.abs() * configAcc);

    var result = diff;
    result = result.clamp(-rpmLimit, rpmLimit);
    result = result.clamp(_prevSpeed - configAcc, _prevSpeed + configAcc);
    result = result.clamp(-deceleration, deceleration);

    arrived = diff.abs() < 0.5;
    // `if (speed > 1/1024) setChanged()`: the block is saved while the elevator moves.
    if (result > 1 / 1024) markDirty();
    _prevSpeed = result;
    return result;
  }

  @override
  bool get shouldCreateRopes => false;

  @override
  void disassemble() {
    final elevator = _elevator;
    if (elevator != null) {
      final coords = elevator.getGlobalColumn();
      if (coords != null) ElevatorColumn.get(worldId, coords)?.setActive(false);
    }
    super.disassemble();
    offset = -1;
    sendData();
  }

  /// `clicked`: the empty-hand click toggles the elevator.
  void clicked() {
    if (isPassive) {
      final parentPos = mirrorParent;
      if (parentPos != null) {
        final parent = ActuatorRuntime.instance.store.at(
          worldId,
          BlockPos(x: parentPos.$1, y: parentPos.$2, z: parentPos.$3),
        );
        if (parent is ElevatorPulleyBlockEntity) {
          parent.clicked();
          return;
        }
      }
    }

    if (running) {
      disassemble();
    } else {
      assembleNextTick = true;
    }
  }

  @override
  bool moveAndCollideContraption() {
    if (arrived) return false;
    super.moveAndCollideContraption();
    return false;
  }

  @override
  Future<void> assemble() async {
    final level = ActuatorHosts.levelOf(worldId);
    final factory = ActuatorHosts.entities;
    final world = this.world;
    if (level == null || factory == null || world == null) return;
    if (_state.key != 'create:elevator_pulley') return;
    if (speed == 0) return;

    final maxLength = level.settings.maxRopeLength;
    var i = 1;
    while (i <= maxLength) {
      final ropePos = localPos.belowBy(i);
      final state = level.stateAt(ropePos);
      if (!level.stateCollisionEmpty(state) && !level.stateReplaceable(state))
        break;
      ++i;
    }

    offset = (i - 1).toDouble();
    forceMove = true;

    if (mirrorParent == null) {
      needsContraption = false;
      final anchor = localPos.belowBy((offset + 1).floor());
      offset = offset.floorToDouble();
      final contraption = ElevatorContraption(offset.toInt());

      final offsetOnSuccess = offset;
      offset = 0;

      final canAssemble = await contraption.assemble(level, anchor);
      if (!canAssemble && speed > 0) return;

      if (contraption.blocks.isNotEmpty) {
        offset = offsetOnSuccess;
        await contraption.removeBlocksFromWorld(level, posZero);
        final entity = factory.createControlled(worldId, localPos, contraption);
        movedContraption = entity;
        entity.setPos(anchor.toVec3());
        contraption.maxContactY = this.pos.y + contraption.contactYOffset - 1;
        contraption.minContactY = contraption.maxContactY - maxLength;
        factory.spawn(worldId, entity);
        forceMove = true;
        needsContraption = true;

        for (var collider in contraption.getOrCreateColliders(
          level,
          Direction.up,
        )) {
          if (collider.$2 != 0) continue;
          final global = collider + anchor;
          final be = ActuatorRuntime.instance.store.at(
            worldId,
            BlockPos(x: global.$1, y: this.pos.y, z: global.$3),
          );
          if (be is ElevatorPulleyBlockEntity) be.startMirroringOther(localPos);
        }

        final coords = contraption.getGlobalColumn();
        if (coords != null) {
          final column = ElevatorColumn.getOrCreate(worldId, coords);
          final target = (this.pos.y + contraption.contactYOffset - 1 - offset)
              .toInt();
          column.target(target);
          unawaited(column.gatherAll());
          column.setActive(true);
          column.markDirty();

          contraption.broadcastFloorData(level, column.contactAt(target));
          clientOffsetTarget = column.getTargetedYLevel();
          arrived = true;
        }
      }
    }

    running = true;
    sendData();
  }

  @override
  void onSpeedChanged(double previousSpeed) => markDirty();
}
