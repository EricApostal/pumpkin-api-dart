// The navigation table's peripheral: the angle to the navigation target, in
// degrees and in radians.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.peripherals.NavTablePeripheral

import '../../../api/sim_peripheral.dart';

/// What [NavTablePeripheral] reads; the navigation table's block entity
/// implements it.
abstract interface class SimNavTableSource {
  /// `NavTableBlockEntity.getRelativeAngle()`, in degrees.
  double get relativeAngle;
}

/// `NavTablePeripheral`: type `navigation_table`.
final class NavTablePeripheral extends SimBlockPeripheral<SimNavTableSource> {
  NavTablePeripheral(super.blockEntity) {
    // `@LuaFunction public Float getRelativeAngle()`. (NavTablePeripheral.java:17-20)
    method('getRelativeAngle', (computer, args) => [blockEntity.relativeAngle]);
    // `@LuaFunction public double getRelativeAngleRad()` (NavTablePeripheral.java:22-25):
    // `Math.toRadians(getRelativeAngle())`.
    method('getRelativeAngleRad', (computer, args) => [simRadians(blockEntity.relativeAngle)]);
  }

  @override
  String get type => 'navigation_table';
}
