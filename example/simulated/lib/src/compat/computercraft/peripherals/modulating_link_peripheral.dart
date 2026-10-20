// The modulating linked receiver's peripheral: the distance to the closest
// link.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.peripherals.ModulatingLinkPeripheral

import '../../../api/sim_peripheral.dart';

/// What [ModulatingLinkPeripheral] reads; the modulating linked receiver's
/// block entity implements it.
abstract interface class SimModulatingLinkSource {
  /// `ModulatingLinkedReceiverBlockEntity.getDistanceToClosest()`.
  double get distanceToClosest;
}

/// `ModulatingLinkPeripheral`: type `modulating_link`.
final class ModulatingLinkPeripheral extends SimBlockPeripheral<SimModulatingLinkSource> {
  ModulatingLinkPeripheral(super.blockEntity) {
    // `@LuaFunction public double getClosestDistance()`. (ModulatingLinkPeripheral.java:16-19)
    method('getClosestDistance', (computer, args) => [blockEntity.distanceToClosest]);
  }

  @override
  String get type => 'modulating_link';
}
