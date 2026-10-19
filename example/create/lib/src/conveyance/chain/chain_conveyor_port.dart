// The package port side of a chain conveyor: the frogports a chain hands packages to. The
// logistics module (which owns `PackageFrogport`) provides the implementations, either by
// implementing [ChainConveyorPort] on its block entity or by registering a port with
// [ChainConveyorPortRegistry] (provided by this module).
import '../../common/pos.dart';
import '../items/item_data.dart';

/// A package port reachable from a chain (`PackagePortTarget.ChainConveyorFrogportTarget`'s
/// block entity side).
abstract interface class ChainConveyorPort {
  /// `PackagePortBlockEntity.isAnimationInProgress()`.
  bool get isAnimationInProgress;

  /// `isBackedUp()`.
  bool get isBackedUp;

  /// `startAnimation(box, simulate)`: takes the package out of the chain.
  void startAnimation(ItemValue package);

  /// `sendAnticipate()`: tells the port a package is about to arrive.
  void sendAnticipate();
}

/// The ports of every world by position, for ports whose block entity does not implement
/// [ChainConveyorPort] directly. Provided as a service by `belts_registration.dart`.
final class ChainConveyorPortRegistry {
  final Map<String, Map<int, ChainConveyorPort>> _byWorld = {};

  /// Registers the port at [pos] of [worldId].
  void register(String worldId, Pos pos, ChainConveyorPort port) =>
      _byWorld.putIfAbsent(worldId, () => {})[pos.asLong] = port;

  /// Removes the port at [pos] of [worldId].
  void unregister(String worldId, Pos pos) =>
      _byWorld[worldId]?.remove(pos.asLong);

  /// The port at [pos], or `null`.
  ChainConveyorPort? at(String worldId, Pos pos) =>
      _byWorld[worldId]?[pos.asLong];
}
