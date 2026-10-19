import 'package:create/src/conveyance/chain/chain_conveyor_logic.dart';
import 'package:create/src/conveyance/chain/chain_conveyor_routing.dart';
import 'package:create/src/conveyance/items/item_data.dart';
import 'package:test/test.dart';

void main() {
  group('chain conveyor geometry', () {
    test('wrapAngle keeps the angle in [0, 360)', () {
      expect(wrapAngle(370), 10);
      expect(wrapAngle(-10), 350);
      expect(wrapAngle(360), 0);
      expect(wrapAngle(725), 5);
    });

    test('the chain cost is one iron chain per 2.5 blocks, at least one', () {
      expect(getChainCost((0, 0, 0)), 1);
      expect(getChainCost((2, 0, 0)), 1);
      expect(getChainCost((10, 0, 0)), 4);
      expect(getChainCost((0, 0, 5)), 2);
    });

    test('connection validation rejects same, close, vertical, steep and far targets', () {
      expect(
        validateConnectionGeometry((0, 0, 0), (0, 0, 0), maxLength: 32),
        isNotNull,
      );
      expect(
        validateConnectionGeometry((0, 0, 0), (2, 0, 0), maxLength: 32),
        'chain_conveyor.too_close',
      );
      expect(
        validateConnectionGeometry((0, 0, 0), (0, 10, 0), maxLength: 32),
        'chain_conveyor.cannot_connect_vertically',
      );
      expect(
        validateConnectionGeometry((0, 0, 0), (3, 10, 0), maxLength: 32),
        'chain_conveyor.too_steep',
      );
      expect(
        validateConnectionGeometry((0, 0, 0), (100, 0, 0), maxLength: 32),
        'chain_conveyor.too_far',
      );
      expect(
        validateConnectionGeometry((0, 0, 0), (5, 0, 0), maxLength: 32),
        isNull,
      );
      expect(
        validateConnectionGeometry((0, 0, 0), (3, 1, 0), maxLength: 32),
        isNull,
      );
    });

    test('connection stats leave the conveyor at the tangent angle', () {
      final stats = calculateConnectionStats(
        (0, 0, 0),
        (0, 0, 5),
        reversed: false,
      );
      expect(stats.tangentAngle, closeTo(325, 1e-6));
      expect(stats.chainLength, greaterThan(0));
      expect(stats.start, isNot(stats.end));

      final reversedStats = calculateConnectionStats(
        (0, 0, 0),
        (0, 0, 5),
        reversed: true,
      );
      expect(reversedStats.tangentAngle, closeTo(35, 1e-6));
    });

    test('packages on the loop sit on the circle around the conveyor', () {
      final position = chainPackagePosition((0, 0, 0), 0, null, const {});
      expect(position.$2, closeTo(6 / 16, 1e-9));
      expect(position.$1, closeTo(0.5, 1e-9));
    });
  });

  group('chain conveyor routing table', () {
    test('a wildcard port is reachable and the entry decays', () {
      final table = ChainConveyorRoutingTable();
      table.receivePortInfo('*', (0, 0, 1));
      expect(table.getExitFor(const ItemValue('minecraft:stone', 1)), (
        0,
        0,
        1,
      ));
      expect(table.shouldAdvertise(), isTrue);

      for (var i = 0; i < ChainConveyorRoutingTable.portEntryTimeout; i++) {
        table.tick();
      }
      expect(table.entriesByDistance, isEmpty);
    });

    test('advertising copies the route to the neighbour', () {
      final table = ChainConveyorRoutingTable();
      table.receivePortInfo('*', (0, 0, 1));
      final other = ChainConveyorRoutingTable();
      table.advertiseTo((0, 0, -1), other);

      expect(other.entriesByDistance, hasLength(1));
      final entry = other.entriesByDistance.single;
      expect(entry.port, '*');
      expect(entry.nextConnection, (0, 0, 1));
      expect(entry.timeout, ChainConveyorRoutingTable.entryTimeout);
    });

    test('the same route refreshes instead of duplicating', () {
      final table = ChainConveyorRoutingTable();
      table.receivePortInfo('A', (0, 0, 1));
      table.tick();
      table.receivePortInfo('A', (0, 0, 1));
      expect(table.entriesByDistance, hasLength(1));
      expect(
        table.entriesByDistance.single.timeout,
        ChainConveyorRoutingTable.entryTimeout,
      );
    });
  });
}
