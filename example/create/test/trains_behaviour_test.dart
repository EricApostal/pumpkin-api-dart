// End-to-end behaviour of a scheduled train on a plain Dart graph: the schedule runtime starts
// the instruction, the navigation finds a path and drives the train, the arrival is detected at
// the station edge point and the conditions of the entry are worked through. These mirror the
// Java `ScheduleRuntime` / `Train` / `Navigation` tick chain without a server.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/redstone/link/link_network.dart' show RedstoneLinkNetworkHandler;
import 'package:create/src/trains/bogey/abstract_bogey_block.dart';
import 'package:create/src/trains/bogey/standard_bogey_block.dart';
import 'package:create/src/trains/entity/carriage.dart';
import 'package:create/src/trains/entity/carriage_bogey.dart';
import 'package:create/src/trains/entity/carriage_storage.dart';
import 'package:create/src/trains/entity/train.dart';
import 'package:create/src/trains/entity/train_level.dart';
import 'package:create/src/trains/graph/dimension_palette.dart';
import 'package:create/src/trains/graph/edge_point_type.dart';
import 'package:create/src/trains/graph/track_edge.dart';
import 'package:create/src/trains/graph/track_graph.dart';
import 'package:create/src/trains/graph/track_node.dart';
import 'package:create/src/trains/graph/track_node_location.dart';
import 'package:create/src/trains/manager/create.dart';
import 'package:create/src/trains/schedule/condition/scheduled_delay.dart';
import 'package:create/src/trains/schedule/condition/timed_wait_condition.dart';
import 'package:create/src/trains/schedule/destination/change_throttle_instruction.dart';
import 'package:create/src/trains/schedule/destination/destination_instruction.dart';
import 'package:create/src/trains/schedule/schedule.dart';
import 'package:create/src/trains/schedule/schedule_entry.dart';
import 'package:create/src/trains/schedule/condition/schedule_wait_condition.dart';
import 'package:create/src/trains/schedule/destination/schedule_instruction.dart';
import 'package:create/src/trains/schedule/schedule_level.dart';
import 'package:create/src/trains/schedule/schedule_runtime.dart';
import 'package:create/src/trains/station/global_package_port.dart';
import 'package:create/src/trains/station/global_station.dart';
import 'package:create/src/trains/track/track_material.dart';
import 'package:create/src/trains/util/ctag.dart';
import 'package:test/test.dart';

/// A [TrainLevel] whose chunks are not entity ticking: the carriage entities are not spawned (no
/// contraptions module in a unit test), while the graph side of the train runs for real.
final class SimLevel implements TrainLevel {
  @override
  String get dimension => overworldId;

  @override
  int gameTime = 0;

  @override
  late final BlockGetter blocks = MapBlockGetter();

  @override
  TrainLevel? levelOf(String dimension) => dimension == this.dimension ? this : null;

  @override
  bool isActiveChunk(Pos pos) => false;

  @override
  void explode(double x, double y, double z, double radius) {}

  // -- ScheduleLevel ---------------------------------------------------------------------------

  @override
  int overworldClockTime = 0;

  @override
  bool hasServer = true;

  @override
  ScheduleFilters filters = const PlainScheduleFilters();

  @override
  RedstoneLinkNetworkHandler? redstoneLinks;

  @override
  SchedulePortInventories get ports => const _NoPorts();

  @override
  bool hasDimension(String dimension) => dimension == this.dimension;

  @override
  bool isLoaded(String dimension, Pos pos) => true;

  @override
  bool hasNeighborSignal(String dimension, Pos pos) => false;

  @override
  bool isPositionEntityTicking(String dimension, Pos pos) => false;
}

final class _NoPorts implements SchedulePortInventories {
  const _NoPorts();

  @override
  List<String>? packageAddresses(String dimension, Pos pos, GlobalPackagePort port) => const [];
}

/// A straight line from (0,0,0) to (0,0,[length]) with one straight edge.
({TrackGraph graph, TrackNode a, TrackNode b, TrackEdge edge}) line(double length) {
  final graph = TrackGraph('00000000-0000-4000-8000-0000000000f1');
  final a = TrackNode(TrackNodeLocation(0, 0, 0).inDimension(overworldId), 1, (0.0, 1.0, 0.0));
  final b = TrackNode(TrackNodeLocation(0, 0, length).inDimension(overworldId), 2, (0.0, 1.0, 0.0));
  graph
    ..addNode(a)
    ..addNode(b);
  final edge = TrackEdge(a, b, null, TrackMaterial.ANDESITE);
  final reverse = TrackEdge(b, a, null, TrackMaterial.ANDESITE);
  graph
    ..putConnection(a, b, edge)
    ..putConnection(b, a, reverse);
  return (graph: graph, a: a, b: b, edge: edge);
}

/// A two bogey carriage whose wheels sit at [positions] on the edge: the first bogey is the
/// leading one (`Carriage` calls `bogey1.setLeading()`), so `[leadFront, leadRear, trailFront,
/// trailRear]` with each pair `getWheelPointSpacing()` (2) apart and the bogey centres
/// `bogeySpacing` apart, all increasing along the travel direction.
Carriage carriageOn(
  TrackGraph graph,
  TrackNode a,
  TrackNode b,
  TrackEdge edge,
  List<double> positions,
) {
  final block =
      AbstractBogeyBlock.byKey('create:small_bogey') ?? StandardBogeyBlock.registerStandardBlocks().first;
  final carriage = Carriage(
    CarriageBogey(block, false, null),
    CarriageBogey(block, false, null),
    3,
  );
  for (var i = 0; i < 2; i++) {
    final bogey = carriage.bogeys.get(i == 0)!;
    bogey.points.getFirst()
      ..node1 = a
      ..node2 = b
      ..edge = edge
      ..position = positions[i * 2];
    bogey.points.getSecond()
      ..node1 = a
      ..node2 = b
      ..edge = edge
      ..position = positions[i * 2 + 1];
  }
  carriage.storage = EmptyCarriageStorage();
  carriage.presentConductors = Couple.create(true, true);
  return carriage;
}

Train trainOn(TrackGraph graph, Carriage carriage) => Train(
  '00000000-0000-4000-8000-0000000000f2',
  null,
  graph,
  [carriage],
  <int>[],
  true,
  0,
);

GlobalStation stationAt(TrackGraph graph, TrackNode a, TrackNode b, String name, double position) {
  final station = GlobalStation()
    ..setId('00000000-0000-4000-8000-0000000000f3')
    ..setLocation(Couple.create(a.location, b.location), position)
    ..name = name;
  station.setType(EdgePointType.STATION);
  graph.addPoint(EdgePointType.STATION, station);
  return station;
}

ScheduleEntry entry(
  ScheduleInstruction instruction, [
  List<List<ScheduleWaitCondition>> conditions = const [],
]) => ScheduleEntry(instruction, conditions);

void main() {
  setUp(() {
    Schedule.ensureRegistered();
    Create.RAILWAYS.cleanUp();
  });

  group('scheduled train', () {
    test('navigates to the destination, arrives and works through the entry', () {
      final g = line(20);
      final station = stationAt(g.graph, g.a, g.b, 'Central', 19.0);
      final train = trainOn(g.graph, carriageOn(g.graph, g.a, g.b, g.edge, [5, 3, 2, 0]));
      final level = SimLevel();

      train.runtime.setSchedule(
        Schedule.of(
          [
            entry(
              DestinationInstruction()..data.putString('Text', 'Central'),
              [
                [ScheduledDelay()..data.putInt('Value', 1)..data.putInt('TimeUnit', TimeUnit.SECONDS.index)],
              ],
            ),
            entry(ChangeThrottleInstruction()..data.putInt('Value', 50)),
          ],
          false,
          0,
        ),
        false,
      );

      // The runtime starts the instruction: it finds the path and hands it to the navigation.
      train.runtime.tick(level);
      expect(train.navigation.destination, same(station));
      expect(train.runtime.state, State.IN_TRANSIT);
      expect(train.navigation.distanceToDestination, greaterThan(0));

      // Drive until the station is reached (the front signal listener arrives at the edge point).
      var ticks = 0;
      while (train.runtime.state != State.POST_TRANSIT) {
        train.tick(level);
        ticks++;
        expect(ticks, lessThan(2000), reason: 'the train never reached the station');
      }
      expect(train.getCurrentStation(), same(station));
      expect(train.speed, 0);
      expect(train.navigation.destination, isNull);
      expect(train.runtime.conditionProgress, [0]);

      // The delay condition is worked through, then the entry after it runs.
      ticks = 0;
      while (train.runtime.state == State.POST_TRANSIT) {
        train.tick(level);
        ticks++;
        expect(ticks, lessThan(200));
      }
      expect(train.runtime.state, State.PRE_TRANSIT);
      expect(train.runtime.currentEntry, 1);

      // A non cyclic schedule pauses and completes at the end: the throttle entry runs on the
      // next tick (its `start` advances `currentEntry` itself, as in Java), and the tick after
      // that `checkEndOfScheduleReached` wraps the entry and pauses the runtime.
      ticks = 0;
      while (!train.runtime.completed) {
        train.tick(level);
        ticks++;
        expect(ticks, lessThan(10));
      }
      expect(train.runtime.currentEntry, 0);
      expect(train.runtime.paused, isTrue);
      expect(train.runtime.completed, isTrue);
    });

    test('a train without a conductor does not start the instruction', () {
      final g = line(20);
      final station = stationAt(g.graph, g.a, g.b, 'Central', 19.0);
      final carriage = carriageOn(g.graph, g.a, g.b, g.edge, [5, 3, 2, 0])
        ..presentConductors = Couple.create(false, false);
      final train = trainOn(g.graph, carriage);
      final level = SimLevel();

      train.runtime.setSchedule(
        Schedule.of(
          [entry(DestinationInstruction()..data.putString('Text', 'Central'))],
          true,
          0,
        ),
        false,
      );

      for (var i = 0; i < 100; i++) {
        train.tick(level);
      }
      expect(train.navigation.destination, isNull);
      expect(train.runtime.state, State.PRE_TRANSIT);
      expect(train.runtime.paused, isFalse);
      expect(station.getPresentTrain(), isNull);
    });

    test('an interrupted transit returns the entry to PRE_TRANSIT', () {
      final g = line(20);
      stationAt(g.graph, g.a, g.b, 'Central', 19.0);
      final train = trainOn(g.graph, carriageOn(g.graph, g.a, g.b, g.edge, [5, 3, 2, 0]));
      final level = SimLevel();

      train.runtime.setSchedule(
        Schedule.of(
          [entry(DestinationInstruction()..data.putString('Text', 'Central'))],
          true,
          0,
        ),
        false,
      );
      train.runtime.tick(level);
      expect(train.runtime.state, State.IN_TRANSIT);

      train.navigation.cancelNavigation();
      expect(train.runtime.state, State.PRE_TRANSIT);
      expect(train.navigation.destination, isNull);
    });
  });

  group('runtime persistence', () {
    test('the schedule state of a train survives a round trip', () {
      final g = line(20);
      stationAt(g.graph, g.a, g.b, 'Central', 19.0);
      final train = trainOn(g.graph, carriageOn(g.graph, g.a, g.b, g.edge, [5, 3, 2, 0]));
      train.runtime.setSchedule(
        Schedule.of(
          [
            entry(DestinationInstruction()..data.putString('Text', 'Central'), [
              [ScheduledDelay()..data.putInt('Value', 3)],
            ]),
            entry(ChangeThrottleInstruction()..data.putInt('Value', 50)),
          ],
          true,
          0,
        ),
        false,
      );
      train.runtime
        ..currentEntry = 1
        ..state = State.POST_TRANSIT
        ..conditionProgress = [1]
        ..conditionContext = [CTag()..putInt('Time', 12)]
        ..predictionTicks = [100, -1]
        ..currentTitle = 'Line 2';

      final tag = train.write(DimensionPalette());
      final back = Train.read(tag, {g.graph.id: g.graph}, DimensionPalette());

      expect(back.runtime.getSchedule(), isNotNull);
      expect(back.runtime.getSchedule()!.cyclic, isTrue);
      expect(back.runtime.currentEntry, 1);
      expect(back.runtime.state, State.POST_TRANSIT);
      expect(back.runtime.conditionProgress, [1]);
      expect(back.runtime.conditionContext.single.getInt('Time'), 12);
      expect(back.runtime.predictionTicks, [100, -1]);
      // `currentTitle` is not written by Java either: a rename instruction re-sets it on the next
      // pass through the schedule.
      expect(back.runtime.currentTitle, '');
    });
  });
}
