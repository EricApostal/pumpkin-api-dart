// The host half of the attach driver: reads the world around a computer
// through `SimulatedHost` and hands the answers to the algorithm in
// `simulated_attach.dart`.
//
// Java's `AttachedComputerHandler` plus CC's capability registration make a
// peripheral appear on the side of a computer that touches a block entity.
// Here the block entities live in Simulated's store, so the driver asks
// `SimulatedHost` what is around the computer; `CcWorldComputers` calls it when
// a computer block is placed, loaded or first used, when a neighbour of a
// computer changes (a Simulated block placed next to a running computer), when
// a peripheral block entity loads or unloads, and when the computer goes away.
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
import 'simulated_attach.dart';
import 'simulated_peripherals.dart' show CcSimulatedPeripherals, SimulatedPeripheral;

/// `ComputerCraftPeripherals`'s world half.
abstract final class CcSimulatedDriver {
  /// Attaches the peripherals of the blocks around the computer [computerId] at
  /// [pos] in [worldId], and detaches the ones that are no longer there.
  ///
  /// Returns the number of sides with a peripheral; 0 when the Simulated plugin
  /// is not loaded or the computer is not.
  static int refresh(CcService service, String worldId, (int, int, int) pos, int computerId) {
    CcSimulatedPeripherals.install();
    final host = sim.SimulatedHost.instance;
    if (host == null) return 0;
    return SimulatedAttach.refresh(_HostNeighbours(host), service, worldId, pos, computerId);
  }

  /// Detaches the peripheral of the side of [computerId] that has the block at
  /// [block] next to it: the Simulated block there is gone.
  ///
  /// Returns whether a peripheral of ours was detached.
  static bool detachAt(CcService service, int computerId, (int, int, int) computer, (int, int, int) block) {
    final side = SimulatedAttach.sideTowards(computer, block);
    if (side == null || service.peripheral(computerId, side) is! SimulatedPeripheral) return false;
    SimulatedAttach.detachSide(service, computerId, side);
    return true;
  }

  /// Detaches every peripheral of ours from the sides of [computerId] (the
  /// computer block was broken or its chunk unloaded).
  static void detachAll(CcService service, int computerId) =>
      SimulatedAttach.detachAll(service, computerId);

  /// The side of the computer at [computer] that has the block at [block] next
  /// to it, or null.
  static ComputerSide? sideTowards((int, int, int) computer, (int, int, int) block) =>
      SimulatedAttach.sideTowards(computer, block);
}

/// `SimulatedHost` as the algorithm's view of the world.
final class _HostNeighbours implements PeripheralNeighbours {
  final sim.SimulatedHost _host;

  const _HostNeighbours(this._host);

  @override
  String? typeAt(String worldId, (int, int, int) pos) => _host.blockEntityTypeAt(worldId, pos);

  @override
  Object? entityAt(String worldId, (int, int, int) pos) => _host.blockEntityAt<Object>(worldId, pos);
}