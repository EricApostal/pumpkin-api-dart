// The directional linked receiver's peripheral: the angle to the closest link,
// in degrees and in radians.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.peripherals.DirectionalLinkPeripheral

import '../../../api/sim_peripheral.dart';

/// What [DirectionalLinkPeripheral] reads; the directional linked receiver's
/// block entity implements it.
abstract interface class SimDirectionalLinkSource {
  /// `DirectionalLinkedReceiverBlockEntity.getAngleToClosestLink()`, in radians.
  double get angleToClosestLink;
}

/// `DirectionalLinkPeripheral`: type `directional_link`.
final class DirectionalLinkPeripheral extends SimBlockPeripheral<SimDirectionalLinkSource> {
  DirectionalLinkPeripheral(super.blockEntity) {
    // `@LuaFunction public double getClosestAngle()` (DirectionalLinkPeripheral.java:16-19):
    // `Math.toDegrees(getAngleToClosestLink())`.
    method('getClosestAngle', (computer, args) => [simDegrees(blockEntity.angleToClosestLink)]);
    // `@LuaFunction public double getClosestAngleRad()`. (DirectionalLinkPeripheral.java:21-24)
    method('getClosestAngleRad', (computer, args) => [blockEntity.angleToClosestLink]);
  }

  @override
  String get type => 'directional_link';
}
