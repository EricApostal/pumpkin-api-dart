// The name plate's peripheral: reads and writes the name of the plate, which is
// the name of the sub-level it is attached to when it may edit it.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.compat.computercraft.peripherals.NamePlatePeripheral

import '../../../api/sim_peripheral.dart';

/// What [NamePlatePeripheral] reads and writes; the name plate's block entity
/// implements it.
abstract interface class SimNamePlateSource {
  /// `NameplateBlockEntity.getName()`: the connected sub-level's name when the
  /// plate may edit it, else the plate's own name, else `""`.
  String get name;

  /// `NameplateBlockEntity.setName(newName, true, null)`: updates the connected
  /// name plates and the sub-level's name, without a player to credit.
  void setName(String newName);
}

/// `NamePlatePeripheral`: type `name_plate`.
final class NamePlatePeripheral extends SimBlockPeripheral<SimNamePlateSource> {
  NamePlatePeripheral(super.blockEntity) {
    // `@LuaFunction public void setName(final String newName)`. (NamePlatePeripheral.java:16-19)
    method('setName', (computer, args) {
      blockEntity.setName(simStringArg(args, 0, 'setName'));
      return const [];
    });
    // `@LuaFunction public String getName()`. (NamePlatePeripheral.java:21-24)
    method('getName', (computer, args) => [blockEntity.name]);
  }

  @override
  String get type => 'name_plate';
}
