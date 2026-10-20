// `ChainConveyorRoutingTable` (pure): the port routes a chain conveyor advertises to its
// neighbours. Ported from `ChainConveyorRoutingTable.java`.
import '../../common/pos.dart';
import '../items/item_data.dart';

/// `ChainConveyorRoutingTable.RoutingTableEntry`.
final class RoutingTableEntry {
  final String port;
  final int distance;
  final Pos nextConnection;
  int timeout;
  final bool endOfRoute;

  RoutingTableEntry(
    this.port,
    this.distance,
    this.nextConnection,
    this.timeout,
    this.endOfRoute,
  );

  /// `invalid()`.
  bool get invalid => timeout <= 0;

  /// `copyForNeighbour(connection)`.
  RoutingTableEntry copyForNeighbour(Pos connection) => RoutingTableEntry(
    port,
    distance + 1,
    -connection,
    ChainConveyorRoutingTable.entryTimeout,
    false,
  );
}

/// `ChainConveyorRoutingTable`.
class ChainConveyorRoutingTable {
  /// `ENTRY_TIMEOUT`.
  static const int entryTimeout = 100;

  /// `PORT_ENTRY_TIMEOUT`.
  static const int portEntryTimeout = 20;

  final List<RoutingTableEntry> entriesByDistance = [];
  int lastUpdate = 0;
  bool changed = false;

  /// `tick()`.
  void tick() {
    for (final e in entriesByDistance) {
      e.timeout--;
    }
    final before = entriesByDistance.length;
    entriesByDistance.removeWhere((e) => e.invalid);
    if (entriesByDistance.length != before) changed = true;
    lastUpdate++;
  }

  /// `shouldAdvertise()`.
  bool shouldAdvertise() => changed || lastUpdate > entryTimeout - 20;

  /// `receivePortInfo(filter, connection)`.
  void receivePortInfo(String filter, Pos connection) => insert(
    RoutingTableEntry(
      filter,
      filter == '*' ? 1000 : 0,
      connection,
      portEntryTimeout,
      true,
    ),
  );

  /// `PackagePortTarget.ChainConveyorFrogportTarget.deregister`: forgets the routes that end at
  /// the port with [filter], so a removed frogport does not keep receiving packages.
  void purgePortRoutes(String filter) {
    entriesByDistance.removeWhere((e) => e.endOfRoute && e.port == filter);
    changed = true;
  }

  /// `getExitFor(box)`: the connection to take for a package, `(0, 0, 0)` when there is no route.
  Pos getExitFor(ItemValue box) {
    for (final entry in entriesByDistance) {
      if (matchPackage(box, entry.port)) return entry.nextConnection;
    }
    return posZero;
  }

  /// `advertiseTo(connection, otherTable)`.
  void advertiseTo(Pos connection, ChainConveyorRoutingTable otherTable) {
    final backConnection = -connection;
    for (final entry in entriesByDistance) {
      if (entry.endOfRoute || connection != entry.nextConnection) {
        otherTable.insert(entry.copyForNeighbour(connection));
      }
    }
    otherTable.entriesByDistance.removeWhere(
      (e) =>
          e.timeout < entryTimeout &&
          !e.endOfRoute &&
          backConnection == e.nextConnection,
    );
  }

  /// `insert(entry)`.
  void insert(RoutingTableEntry entry) {
    var targetIndex = 0;
    for (var i = 0; i < entriesByDistance.length; i++) {
      final other = entriesByDistance[i];
      // Still not found at this distance: either a new port or a shorter route to a known one.
      if (other.distance > entry.distance) break;
      if (other.port == entry.port) {
        if (other.distance == entry.distance &&
            other.nextConnection == entry.nextConnection) {
          // Same route: keep the entry and refresh its life time.
          other.timeout = entryTimeout;
        }
        // A different (longer or differently routed) path: let the old entry decay.
        return;
      }
      targetIndex = i + 1;
    }
    entriesByDistance.insert(targetIndex, entry);
    changed = true;
  }
}
