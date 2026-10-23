// The block entity of the torsion spring.
//
// The pass-through shaft of the block and the output that actually turns share
// one block. Java gives the output its own `GeneratingKineticBlockEntity`; the
// port keeps one kinetic node per position and reports the output's generated
// speed from this entity, so the network sees the same thing.
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.content.blocks.torsion_spring.TorsionSpringBlockEntity
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/host_bridge.dart';
import 'package:create/src/kinetics/behaviours.dart' show ScrollValueBehaviour;
import 'package:create/src/kinetics/kinetic_block_entity.dart' show GeneratingKineticBlockEntity;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../compat/computercraft/peripherals/torsion_spring_peripheral.dart';
import '../../advancements/sim_advancements.dart';
import 'torsion_spring_logic.dart';

/// `TorsionSpringBlockEntity`.
final class TorsionSpringBlockEntity extends GeneratingKineticBlockEntity implements SimTorsionSpringSource {
  /// The block entity type key.
  static const String type = 'simulated:torsion_spring';

  /// The block key.
  static const String block = 'simulated:torsion_spring';

  TorsionSpringBlockEntity(super.worldId, super.pos) {
    angleInput = addBehaviour(ScrollValueBehaviour()..between(1, 360)..value = 90);
  }

  /// The angle limit value box.
  late final ScrollValueBehaviour angleInput;

  /// The output state machine.
  final TorsionSpringOutputLogic output = TorsionSpringOutputLogic();

  /// The angle limit from a sequenced context (negative: none).
  double sequencedAngleLimit = -1;

  @override
  double get generatedSpeed => output.generatedSpeed;

  /// `getAngle()`.
  @override
  double get angle => output.angle;

  /// `angleInput.getValue()`: the limit, in degrees.
  @override
  int get angleLimit => angleInput.value;

  /// `angleInput.setValue(limit)`.
  @override
  void setAngleLimit(int limit) => angleInput.value = limit;

  /// `setAngle(angle)`.
  void setAngle(double angle) => output.angle = angle;

  /// `isSpringStatic()`.
  @override
  bool get isSpringStatic => output.isStatic;

  /// `interpolatedSpring(pt)`.
  double interpolatedSpring(double partialTick) => output.interpolated(partialTick);

  /// `onSignalChanged()`: the block's redstone state changed.
  void onSignalChanged() {
    final w = world;
    if (w == null) return;
    final state = HostBlockGetter.stateOfId(w.getBlockStateId(pos: pos));
    output.tick(
      parentSpeed: speed,
      angleLimit: angleInput.getValue().toDouble(),
      powered: state.flag('powered'),
      speed: speed,
    );
    consumeRewindAward(w);
  }

  /// Awards `REWIND_TIME` when the last `output.tick` wound a stopped output back
  /// to zero (`TorsionSpringBlockEntity.tick`, `TorsionSpringBlockEntity.java:252`):
  /// at the parent's position — here, this entity's own. The flag is consumed
  /// here because the pure half has no world.
  void consumeRewindAward(World awardWorld) {
    if (!output.rewoundToZero) return;
    output.rewoundToZero = false;
    SimAdvancements.awardNearby(awardWorld, pos.toPos(), 'rewind_time');
  }

  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    sequencedAngleLimit = -1;
    output.updateParentSpeed(previousSpeed, speed);
  }

  @override
  void tick() {
    super.tick();
    if (removed) return;

    final w = world;
    final state = w == null ? BState(block) : HostBlockGetter.stateOfId(w.getBlockStateId(pos: pos));

    final stopped = output.tick(
      parentSpeed: speed,
      angleLimit: angleInput.getValue().toDouble(),
      powered: state.flag('powered'),
      speed: speed,
    );
    if (output.rewoundToZero) {
      final World? awardWorld = w;
      if (awardWorld != null) consumeRewindAward(awardWorld);
    }
    if (stopped) updateGeneratedRotation();
  }

  /// The comparator output read from [side].
  int analogOutput(String side) => torsionSpringAnalogOutput(
    angle: output.angle,
    angleLimit: angleInput.getValue().toDouble(),
    facingName: blockState.dirOf('facing')?.name ?? 'north',
    sideName: side,
  );

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    output.read({
      'OldAngle': tag.getDouble('OldAngle') ?? 0,
      'Angle': tag.getDouble('Angle') ?? 0,
      'TargetAngle': tag.getDouble('TargetAngle') ?? 0,
      'LastSpringSpeed': tag.getDouble('LastSpringSpeed') ?? 0,
      'CurrentState': tag.getInt('CurrentState') ?? 0,
      'RotationProgressTicks': tag.getInt('RotationProgressTicks') ?? 0,
      'RotationDurationTicks': tag.getInt('RotationDurationTicks') ?? 0,
      'GeneratedSpeed': tag.getDouble('GeneratedSpeed') ?? 0,
      'QueuedSpeed': tag.getDouble('QueuedSpeed') ?? 0,
      if (tag.getDouble('SequencedAngleLimit') != null)
        'SequencedAngleLimit': tag.getDouble('SequencedAngleLimit'),
    });
    sequencedAngleLimit = tag.getDouble('SequencedAngleLimit') ?? -1;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    final data = output.write();
    tag.putDouble('OldAngle', data['OldAngle']! as double);
    tag.putDouble('Angle', data['Angle']! as double);
    tag.putDouble('TargetAngle', data['TargetAngle']! as double);
    tag.putDouble('LastSpringSpeed', data['LastSpringSpeed']! as double);
    tag.putInt('CurrentState', data['CurrentState']! as int);
    tag.putInt('RotationProgressTicks', data['RotationProgressTicks']! as int);
    tag.putInt('RotationDurationTicks', data['RotationDurationTicks']! as int);
    tag.putDouble('GeneratedSpeed', data['GeneratedSpeed']! as double);
    tag.putDouble('QueuedSpeed', data['QueuedSpeed']! as double);
    final limit = data['SequencedAngleLimit'];
    if (limit is double) tag.putDouble('SequencedAngleLimit', limit);
  }
}
