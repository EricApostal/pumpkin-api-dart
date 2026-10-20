// The velocity sensor's peripheral.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.peripherals.VelocitySensorPeripheral

import '../../../api/sim_peripheral.dart';

/// What [VelocitySensorPeripheral] reads; the velocity sensor's block entity
/// implements it.
abstract interface class SimVelocitySensorSource {
  /// `VelocitySensorBlockEntity.getAdjustedVelocity()`.
  double get adjustedVelocity;
}

/// `VelocitySensorPeripheral`: type `velocity_sensor`.
final class VelocitySensorPeripheral extends SimBlockPeripheral<SimVelocitySensorSource> {
  VelocitySensorPeripheral(super.blockEntity) {
    // `@LuaFunction public float getVelocity()`. (VelocitySensorPeripheral.java:17-20)
    method('getVelocity', (computer, args) => [blockEntity.adjustedVelocity]);
  }

  @override
  String get type => 'velocity_sensor';
}
