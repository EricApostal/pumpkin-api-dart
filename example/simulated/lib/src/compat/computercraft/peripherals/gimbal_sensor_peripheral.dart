// The gimbal sensor's peripheral: the two angles of the sensor, in degrees and
// in radians.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.peripherals.GimbalSensorPeripheral

import '../../../api/sim_peripheral.dart';

/// What [GimbalSensorPeripheral] reads; the gimbal sensor's block entity
/// implements it.
abstract interface class SimGimbalSensorSource {
  /// `GimbalSensorBlockEntity.getXAngle()`, in radians.
  double get xAngle;

  /// `GimbalSensorBlockEntity.getZAngle()`, in radians.
  double get zAngle;
}

/// `GimbalSensorPeripheral`: type `gimbal_sensor`.
final class GimbalSensorPeripheral extends SimBlockPeripheral<SimGimbalSensorSource> {
  GimbalSensorPeripheral(super.blockEntity) {
    // `@LuaFunction public List<Double> getAngles()`: `{x, z}` in degrees. (GimbalSensorPeripheral.java:19-22)
    method('getAngles', (computer, args) => [
      [simDegrees(blockEntity.xAngle), simDegrees(blockEntity.zAngle)],
    ]);
    // `@LuaFunction public List<Double> getAnglesRad()`: `{x, z}` in radians. (GimbalSensorPeripheral.java:24-27)
    method('getAnglesRad', (computer, args) => [
      [blockEntity.xAngle, blockEntity.zAngle],
    ]);
  }

  @override
  String get type => 'gimbal_sensor';
}
