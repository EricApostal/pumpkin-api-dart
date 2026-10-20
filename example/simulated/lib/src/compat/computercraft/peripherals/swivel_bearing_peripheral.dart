// The swivel bearing's peripheral: the angle it is turning to.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.peripherals.SwivelBearingPeripheral

import '../../../api/sim_peripheral.dart';

/// What [SwivelBearingPeripheral] reads; `SwivelBearingBlockEntity` implements
/// it (`getTargetAngleDegrees()`).
abstract interface class SimSwivelBearingSource {
  /// `SwivelBearingBlockEntity.getTargetAngleDegrees()`.
  double get targetAngleDegrees;
}

/// `SwivelBearingPeripheral`: type `swivel_bearing`.
final class SwivelBearingPeripheral extends SimBlockPeripheral<SimSwivelBearingSource> {
  SwivelBearingPeripheral(super.blockEntity) {
    // `@LuaFunction public double getTargetAngle()`. (SwivelBearingPeripheral.java:17-20)
    method('getTargetAngle', (computer, args) => [blockEntity.targetAngleDegrees]);
    // `@LuaFunction public double getTargetAngleRad()` (SwivelBearingPeripheral.java:22-25):
    // `Math.toRadians(getTargetAngleDegrees())`.
    method('getTargetAngleRad', (computer, args) => [simRadians(blockEntity.targetAngleDegrees)]);
  }

  @override
  String get type => 'swivel_bearing';
}
