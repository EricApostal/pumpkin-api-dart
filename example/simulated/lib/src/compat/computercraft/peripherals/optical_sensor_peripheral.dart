// The optical sensor's peripheral: whether the laser hits something, how far
// away it is, what block it is, and the range of the laser.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.peripherals.OpticalSensorPeripheral

import '../../../api/sim_peripheral.dart';

/// What [OpticalSensorPeripheral] reads; the optical sensor's block entity
/// implements it.
abstract interface class SimOpticalSensorSource {
  /// `OpticalSensorBlockEntity.hasHit()`.
  bool get hasHit;

  /// `OpticalSensorBlockEntity.getHitBlockDistance()`.
  double get hitBlockDistance;

  /// The registry key of `getHitBlock()`, as
  /// `BuiltInRegistries.BLOCK.getKey(block).toString()` gives it (air when the
  /// laser hit nothing).
  String get hitBlockKey;

  /// `OpticalSensorBlockEntity.getRange()`.
  double get range;

  /// `OpticalSensorBlockEntity.setRange(blocks)`: the block entity clamps the
  /// value to the configured maximum.
  void setRange(int blocks);
}

/// `OpticalSensorPeripheral`: type `optical_sensor`.
final class OpticalSensorPeripheral extends SimBlockPeripheral<SimOpticalSensorSource> {
  OpticalSensorPeripheral(super.blockEntity) {
    // `@LuaFunction public boolean hasHit()`. (OpticalSensorPeripheral.java:18-21)
    method('hasHit', (computer, args) => [blockEntity.hasHit]);
    // `@LuaFunction public float getDistance()`. (OpticalSensorPeripheral.java:23-26)
    method('getDistance', (computer, args) => [blockEntity.hitBlockDistance]);
    // `@LuaFunction public String getBlock()`. (OpticalSensorPeripheral.java:28-31)
    method('getBlock', (computer, args) => [blockEntity.hitBlockKey]);
    // `@LuaFunction public float getRange()`. (OpticalSensorPeripheral.java:33-36)
    method('getRange', (computer, args) => [blockEntity.range]);
    // `@LuaFunction(mainThread = true) public final void setRange(final int blocks)`. (OpticalSensorPeripheral.java:38-41)
    method('setRange', (computer, args) {
      blockEntity.setRange(simIntArg(args, 0, 'setRange'));
      return const [];
    });
  }

  @override
  String get type => 'optical_sensor';
}
