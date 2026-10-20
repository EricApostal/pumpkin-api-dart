// The altitude sensor's peripheral: the height of the world and the air
// pressure at the sensor.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.peripherals.AltitudeSensorPeripheral

import '../../../api/sim_peripheral.dart';

/// What [AltitudeSensorPeripheral] reads; the altitude sensor's block entity
/// implements it.
abstract interface class SimAltitudeSensorSource {
  /// `AltitudeSensorBlockEntity.getWorldHeight()`.
  double get worldHeight;

  /// `AltitudeSensorBlockEntity.getAirPressure()`.
  double get airPressure;
}

/// `AltitudeSensorPeripheral`: type `altitude_sensor`.
final class AltitudeSensorPeripheral extends SimBlockPeripheral<SimAltitudeSensorSource> {
  AltitudeSensorPeripheral(super.blockEntity) {
    // `@LuaFunction public float getHeight()`. (AltitudeSensorPeripheral.java:17-20)
    method('getHeight', (computer, args) => [blockEntity.worldHeight]);
    // `@LuaFunction public double getAirPressure()`. (AltitudeSensorPeripheral.java:22-25)
    method('getAirPressure', (computer, args) => [blockEntity.airPressure]);
  }

  @override
  String get type => 'altitude_sensor';
}
