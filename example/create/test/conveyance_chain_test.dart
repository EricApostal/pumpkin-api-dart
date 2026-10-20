import 'package:create/src/common/direction.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/contraptions/core/nbt_map.dart';
import 'package:create/src/contraptions/core/structure_transform.dart';
import 'package:create/src/core/nbt.dart';
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

    test('a connection added at runtime gets its stats', () {
      final stats = <Pos, ConnectionStats>{};
      putConnectionStats(stats, (0, 0, 0), (0, 0, 5), 32);
      expect(stats.keys, [(0, 0, 5)]);
      expect(stats[(0, 0, 5)]!.chainLength, greaterThan(0));

      // A second connection is added without dropping the first one.
      putConnectionStats(stats, (0, 0, 0), (5, 0, 0), 32);
      expect(stats.keys, unorderedEquals([(0, 0, 5), (5, 0, 0)]));
    });

    test('connection stats follow the current speed, not a cached direction', () {
      final forward = <Pos, ConnectionStats>{};
      putConnectionStats(forward, (0, 0, 0), (0, 0, 5), 32);
      expect(forward[(0, 0, 5)]!.tangentAngle, closeTo(325, 1e-6));

      final backward = <Pos, ConnectionStats>{};
      putConnectionStats(backward, (0, 0, 0), (0, 0, 5), -32);
      expect(backward[(0, 0, 5)]!.tangentAngle, closeTo(35, 1e-6));
    });

    test('a contraption transform moves the connections and the package targets', () {
      final transform = StructureTransform(
        (1, 0, 2),
        Axis.y,
        BlockRotation.clockwise90,
        BlockMirror.none,
      );
      final nbt = NbtMap()
        ..putList('Connections', [
          NbtValue.intArray([0, 0, 5]),
        ])
        ..putList('TravellingPackages', [
          (NbtMap()
                ..putBlockPos('Target', (0, 0, 5))
                ..putList('Packages', []))
              .toValue(),
        ]);

      transformChainConveyorNbt(nbt, transform);

      final expected = transform.applyPosWithoutOffset((0, 0, 5));
      final connection = nbt.getList('Connections').single;
      expect(connection.kind, NbtKind.intArray);
      expect(connection.value, [expected.$1, expected.$2, expected.$3]);
      final entry = NbtMap.of(nbt.getList('TravellingPackages').single);
      expect(entry.getBlockPos('Target'), expected);
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

    test('a removed port forgets its routes', () {
      final table = ChainConveyorRoutingTable();
      table.receivePortInfo('A', (0, 0, 1));
      table.receivePortInfo('B', (0, 0, -1));
      table.changed = false;

      table.purgePortRoutes('A');
      expect(table.entriesByDistance.map((e) => e.port), ['B']);
      expect(table.changed, isTrue);
    });

    test('a route towards a port survives the port of that name being removed', () {
      final table = ChainConveyorRoutingTable();
      table.receivePortInfo('A', (0, 0, 1));

      // The neighbour knows a route towards A; it is not a port on the neighbour itself.
      final neighbour = ChainConveyorRoutingTable();
      table.advertiseTo((0, 0, -1), neighbour);
      expect(neighbour.entriesByDistance.single.endOfRoute, isFalse);

      neighbour.purgePortRoutes('A');
      expect(neighbour.entriesByDistance, hasLength(1));
    });
  });
}
