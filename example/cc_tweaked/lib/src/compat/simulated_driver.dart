// The attach/detach driver of Simulated's peripherals.
//
// Java's `AttachedComputerHandler` plus CC's capability registration make a
// peripheral appear on the side of a computer that touches a block entity.
// Here the block entities live in Simulated's store, so the driver asks
// `SimulatedHost` what is around the computer and attaches what it finds;
// `CcWorldComputers` calls it when a computer block is placed, loaded or first
// used, and when it goes away.
//
// Java: dev.simulated_team.simulated.compat.computercraft.AttachedComputerHandler
//       (the attach side) and NeoForgeSimPeripheralService (the capability
//       registration).
//
// `simulated` does not export these from its barrel yet (the barrel also
// carries the content, which a VM test cannot load).
// ignore_for_file: implementation_imports
import 'package:simulated/src/host/simulated_host.dart' as sim;

import '../machine/side.dart';
import '../plugin/service.dart';
import 'simulated_peripherals.dart';

/// `ComputerCraftPeripherals`'s world half.
abstract final class CcSimulatedDriver {
  /// Attaches the peripherals of the blocks around the computer [computerId] at
  /// [pos] in [worldId], and detaches the ones that are no longer there.
  ///
  /// This is what makes a peripheral appear on a computer's side when a block
  /// is placed next to it. Returns the number of sides with a peripheral.
  static int refresh(CcService service, String worldId, (int, int, int) pos, int computerId) {
    CcSimulatedPeripherals.install();
    final host = sim.SimulatedHost.instance;
    if (host == null || service.computer(computerId) == null) return 0;

    var attached = 0;
    for (final MapEntry(key: side, value: (offset, direction)) in neighbours.entries) {
      final neighbour = (pos.$1 + offset.$1, pos.$2 + offset.$2, pos.$3 + offset.$3);
      final typeKey = host.blockEntityTypeAt(worldId, neighbour);
      final entity = typeKey == null ? null : host.blockEntityAt<Object>(worldId, neighbour);
      final peripheral = entity == null
          ? null
          : CcSimulatedPeripherals.peripheralFor(entity, typeKey!, direction: direction);

      if (peripheral == null) {
        // Only a peripheral of ours is removed: the side may hold a monitor or
        // a modem, which the computer's own record owns.
        if (service.peripheral(computerId, side) is SimulatedPeripheral) {
          service.detachExternal(computerId, side);
        }
        continue;
      }
      service.attachExternal(computerId, side, peripheral);
      attached++;
    }
    return attached;
  }

  /// Detaches every peripheral of ours from the sides of [computerId] (the
  /// computer block was broken or its chunk unloaded).
  static void detachAll(CcService service, int computerId) {
    for (final side in ComputerSide.values) {
      if (service.peripheral(computerId, side) is SimulatedPeripheral) {
        service.detachExternal(computerId, side);
      }
    }
  }

  /// The six sides of a computer, the block next to it, and the direction from
  /// that block towards the computer (the `direction` CC's capability getter
  /// receives).
  ///
  /// The port has no computer facing: the CC plugin's computers are records
  /// with six sides and no block state, so this is the mapping of a computer
  /// that faces north (`front` = north, `right` = east, and so on).
  static const Map<ComputerSide, ((int, int, int), String)> neighbours = {
    ComputerSide.bottom: ((0, -1, 0), 'up'),
    ComputerSide.top: ((0, 1, 0), 'down'),
    ComputerSide.back: ((0, 0, 1), 'north'),
    ComputerSide.front: ((0, 0, -1), 'south'),
    ComputerSide.right: ((1, 0, 0), 'west'),
    ComputerSide.left: ((-1, 0, 0), 'east'),
  };
}
