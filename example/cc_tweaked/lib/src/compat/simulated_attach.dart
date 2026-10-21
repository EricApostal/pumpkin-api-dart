// The pure half of the attach driver: which block sits next to which side of a
// computer, and how a Simulated peripheral is put on a side and taken off
// again.
//
// The world and the computer are behind two small interfaces
// ([PeripheralNeighbours], [ExternalPeripheralTarget]), so the whole algorithm
// runs without a host and the tests drive it directly. The host half, which
// reads the world through `SimulatedHost` and talks to `CcService`, is
// `simulated_driver.dart`.
//
// Java: dev.simulated_team.simulated.compat.computercraft.AttachedComputerHandler
//       (the attach side) and NeoForgeSimPeripheralService (the capability
//       registration, which is what makes a block next to a computer a
//       peripheral of it).

import '../machine/peripheral.dart';
import '../machine/side.dart';
import 'simulated_peripherals.dart';

/// What the driver needs of the world around a computer.
abstract interface class PeripheralNeighbours {
  /// The block entity type at [pos] of world [worldId] (`BlockEntity.typeKey`),
  /// or null when the block there has no entity.
  String? typeAt(String worldId, (int, int, int) pos);

  /// The block entity at [pos] of world [worldId], or null.
  Object? entityAt(String worldId, (int, int, int) pos);
}

/// What the driver needs of a computer's peripherals: the sides of one
/// computer, and how a peripheral is put on one and taken off again
/// (`CcService` implements this).
abstract interface class ExternalPeripheralTarget {
  /// Whether computer [id] is loaded here.
  bool hasComputer(int id);

  /// The peripheral attached to [side] of computer [id], if any.
  Peripheral? peripheral(int id, ComputerSide side);

  /// Attaches [peripheral] to [side] of computer [id].
  void attachExternal(int id, ComputerSide side, Peripheral peripheral);

  /// Removes the peripheral of [side] of computer [id].
  void detachExternal(int id, ComputerSide side);
}

abstract final class SimulatedAttach {
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

  /// The side of the computer at [computer] that has the block at [block] next
  /// to it, or null when the two are not next to each other.
  static ComputerSide? sideTowards((int, int, int) computer, (int, int, int) block) {
    for (final MapEntry(key: side, value: (offset, _)) in neighbours.entries) {
      if (computer.$1 + offset.$1 == block.$1 &&
          computer.$2 + offset.$2 == block.$2 &&
          computer.$3 + offset.$3 == block.$3) {
        return side;
      }
    }
    return null;
  }

  /// The position of the block on [side] of the computer at [computer].
  static (int, int, int) neighbourOf((int, int, int) computer, ComputerSide side) {
    final offset = neighbours[side]!.$1;
    return (computer.$1 + offset.$1, computer.$2 + offset.$2, computer.$3 + offset.$3);
  }

  /// Attaches the peripherals of the blocks around the computer [computerId] at
  /// [pos] in [worldId], and detaches the ones that are no longer there.
  ///
  /// This is what makes a peripheral appear on a computer's side when a block
  /// is placed next to it. Returns the number of sides with a peripheral.
  static int refresh(
    PeripheralNeighbours world,
    ExternalPeripheralTarget target,
    String worldId,
    (int, int, int) pos,
    int computerId,
  ) {
    if (!target.hasComputer(computerId)) return 0;

    var attached = 0;
    for (final MapEntry(key: side, value: (offset, direction)) in neighbours.entries) {
      final neighbour = (pos.$1 + offset.$1, pos.$2 + offset.$2, pos.$3 + offset.$3);
      final typeKey = world.typeAt(worldId, neighbour);
      final entity = typeKey == null ? null : world.entityAt(worldId, neighbour);
      final peripheral = entity == null
          ? null
          : CcSimulatedPeripherals.peripheralFor(entity, typeKey!, direction: direction);

      if (peripheral == null) {
        // Only a peripheral of ours is removed: the side may hold a monitor or
        // a modem, which the computer's own record owns.
        detachSide(target, computerId, side);
        continue;
      }
      target.attachExternal(computerId, side, peripheral);
      attached++;
    }
    return attached;
  }

  /// Detaches the peripheral of [side] of [computerId] when it is one of ours
  /// (a monitor or a modem the computer's record owns is left alone).
  static void detachSide(ExternalPeripheralTarget target, int computerId, ComputerSide side) {
    if (target.peripheral(computerId, side) is SimulatedPeripheral) {
      target.detachExternal(computerId, side);
    }
  }

  /// Detaches every peripheral of ours from the sides of [computerId] (the
  /// computer block was broken or its chunk unloaded).
  static void detachAll(ExternalPeripheralTarget target, int computerId) {
    for (final side in ComputerSide.values) {
      detachSide(target, computerId, side);
    }
  }
}