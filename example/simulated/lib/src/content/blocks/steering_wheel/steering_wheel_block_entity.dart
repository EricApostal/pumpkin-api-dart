// The block entity of the steering wheel.
//
// It is a kinetic generator: while it turns towards its target angle it reports a
// generated speed, which the network carries to whatever the wheel is attached
// to. The angle machine itself is [SteeringWheelLogic].
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.content.blocks.steering_wheel.SteeringWheelBlockEntity
// create's kinetics are not in its public barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/kinetics/behaviours.dart' show ScrollValueBehaviour;
import 'package:create/src/kinetics/kinetic_block_entity.dart' show GeneratingKineticBlockEntity;
import 'package:pumpkin_api/pumpkin_api.dart';

import 'steering_wheel_logic.dart';

/// `SteeringWheelBlockEntity`.
final class SteeringWheelBlockEntity extends GeneratingKineticBlockEntity {
  /// The block entity type key.
  static const String type = 'simulated:steering_wheel';

  /// The block key.
  static const String block = 'simulated:steering_wheel';

  SteeringWheelBlockEntity(super.worldId, super.pos) {
    angleInput = addBehaviour(ScrollValueBehaviour()..between(1, 360)..value = 180);
  }

  /// The angle limit value box.
  late final ScrollValueBehaviour angleInput;

  /// The angle machine.
  final SteeringWheelLogic logic = SteeringWheelLogic();

  /// The material the wheel is made of (`Blocks.SPRUCE_PLANKS` by default).
  String material = 'minecraft:spruce_planks';

  /// The block's facing, as the shared direction type.
  Direction get facing =>
      Direction.byName(blockState.dirOf('facing')?.name ?? 'north') ?? Direction.north;

  bool get onFloor => blockState.flag('on_floor');

  @override
  double get generatedSpeed {
    logic.angleLimit = angleInput.getValue().toDouble();
    return logic.generatedSpeedForOutput;
  }

  /// `getLogicalSpeed()`.
  double get logicalSpeed {
    logic.angleLimit = angleInput.getValue().toDouble();
    return logic.logicalSpeedForOutput;
  }

  @override
  void tick() {
    super.tick();
    if (removed) return;

    logic.angleLimit = angleInput.getValue().toDouble();
    final finished = logic.tick(facing: facing, onFloor: onFloor);
    if (finished) updateGeneratedRotation();
  }

  /// `updateTargetAngle(absoluteTarget)`: the client asked for a new angle.
  void updateTargetAngle(double absoluteTarget) {
    logic.updateTargetAngle(absoluteTarget, facing: facing, onFloor: onFloor);
    updateGeneratedRotation();
    sendData();
  }

  /// `getAngle()`.
  double get angle => logic.angle;

  /// `startHolding()` / `stopHolding()`.
  void setHeld(bool held) {
    logic.held = held;
    sendData();
  }

  /// `directionConvert(val)`.
  double directionConvert(double value) => logic.directionConvert(value, facing);

  /// `getAnalogOutputSignalFrom(state, dir)`.
  int analogOutput(Direction side) => logic.analogOutput(facing, side);

  /// `isMaterialValid(stack)`: a plank block different from the current one.
  bool isMaterialValid(String itemKey) {
    if (!itemKey.endsWith('_planks') && itemKey != 'minecraft:planks') return false;
    return itemKey != material;
  }

  /// `applyMaterialIfValid(stack)`.
  bool applyMaterialIfValid(String itemKey) {
    if (!isMaterialValid(itemKey)) return false;
    material = itemKey;
    sendData();
    return true;
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) {
      logic.held = tag.getBool('Held') ?? false;
      return;
    }
    logic.read({
      'Angle': tag.getDouble('Angle') ?? 0,
      'TargetAngle': tag.getDouble('TargetAngle') ?? 0,
      if (tag.getDouble('TargetAngleToUpdate') != null) 'TargetAngleToUpdate': tag.getDouble('TargetAngleToUpdate'),
      'InUse': tag.getInt('InUse') ?? 0,
      'SequencedAngleLimit': tag.getDouble('SequencedAngleLimit') ?? 0,
      'GeneratedSpeed': tag.getDouble('GeneratedSpeed') ?? 0,
    });
    final saved = tag.getString('Material');
    if (saved != null) material = saved;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    final data = logic.write();
    tag.putDouble('Angle', data['Angle']! as double);
    tag.putDouble('TargetAngle', data['TargetAngle']! as double);
    final toUpdate = data['TargetAngleToUpdate'];
    if (toUpdate is double) tag.putDouble('TargetAngleToUpdate', toUpdate);
    tag.putInt('InUse', data['InUse']! as int);
    tag.putDouble('SequencedAngleLimit', data['SequencedAngleLimit']! as double);
    tag.putDouble('GeneratedSpeed', data['GeneratedSpeed']! as double);
    if (clientPacket) tag.putBool('Held', logic.held);
    tag.putString('Material', material);
  }

  /// The state of the block, for the block callbacks that need it.
  BState blockStateValue() {
    final w = world;
    if (w == null) return BState(block);
    return HostBlockGetter.stateOfId(w.getBlockStateId(pos: pos));
  }
}
