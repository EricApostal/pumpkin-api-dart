// The docking connector's peripheral: the name of the sub-level it is docked
// to.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.peripherals.DockingConnectorPeripheral

import '../../../api/sim_peripheral.dart';

/// What [DockingConnectorPeripheral] reads; the docking connector's block entity
/// implements it.
abstract interface class SimDockingConnectorSource {
  /// `otherConnectorPosition != null`: the connector is paired with another.
  bool get hasOtherConnector;

  /// `Sable.HELPER.getContaining(level, otherConnectorPosition)?.getName()`:
  /// the name of the sub-level holding the other connector, when there is one
  /// and it is named.
  String? get otherConnectorSubLevelName;

  /// The block's `DockingConnectorBlock.FACING`, as a direction name.
  String get facing;
}

/// `DockingConnectorPeripheral`: type `docking_connector`.
final class DockingConnectorPeripheral extends SimBlockPeripheral<SimDockingConnectorSource> {
  DockingConnectorPeripheral(super.blockEntity) {
    // `@LuaFunction public String getConnectedName()` (DockingConnectorPeripheral.java:19-29):
    // the sub-level's name, or `""` when there is no pair or the pair's
    // sub-level has no name.
    method('getConnectedName', (computer, args) {
      if (blockEntity.hasOtherConnector) {
        final name = blockEntity.otherConnectorSubLevelName;
        if (name != null) return [name];
      }
      return const [''];
    });
  }

  @override
  String get type => 'docking_connector';
}
