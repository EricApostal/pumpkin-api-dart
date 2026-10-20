// The torsion spring's peripheral: the limit of the spring, its angle, and
// whether it is running.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.peripherals.TorsionSpringPeripheral

import '../../../api/sim_peripheral.dart';

/// What [TorsionSpringPeripheral] reads and writes; `TorsionSpringBlockEntity`
/// implements it over its `angleInput` value box.
abstract interface class SimTorsionSpringSource {
  /// `TorsionSpringBlockEntity.isSpringStatic()`.
  bool get isSpringStatic;

  /// `angleInput.getValue()`: the limit, in degrees.
  int get angleLimit;

  /// `angleInput.setValue(limit)`.
  void setAngleLimit(int limit);

  /// `TorsionSpringBlockEntity.getAngle()`.
  double get angle;
}

/// `TorsionSpringPeripheral`: type `torsion_spring`.
final class TorsionSpringPeripheral extends SimBlockPeripheral<SimTorsionSpringSource> {
  TorsionSpringPeripheral(super.blockEntity) {
    // `@LuaFunction public void setLimit(final int limit)` (TorsionSpringPeripheral.java:16-21):
    // only while the spring is static; a running spring ignores the call.
    method('setLimit', (computer, args) {
      final limit = simIntArg(args, 0, 'setLimit');
      if (blockEntity.isSpringStatic) blockEntity.setAngleLimit(limit);
      return const [];
    });
    // `@LuaFunction public float getAngle()`. (TorsionSpringPeripheral.java:23-26)
    method('getAngle', (computer, args) => [blockEntity.angle]);
    // `@LuaFunction public double getAngleRad()` (TorsionSpringPeripheral.java:28-31):
    // `Math.toRadians(getAngle())`.
    method('getAngleRad', (computer, args) => [simRadians(blockEntity.angle)]);
    // `@LuaFunction public int getLimit()`. (TorsionSpringPeripheral.java:33-36)
    method('getLimit', (computer, args) => [blockEntity.angleLimit.toDouble()]);
    // `@LuaFunction public boolean isRunning()`: `!isSpringStatic()`. (TorsionSpringPeripheral.java:38-41)
    method('isRunning', (computer, args) => [!blockEntity.isSpringStatic]);
  }

  @override
  String get type => 'torsion_spring';
}
