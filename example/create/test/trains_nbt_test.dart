// NBT parity tests for the trains module. Every layout here mirrors a Java `write`/`read` pair
// (`Train`, `Carriage`, `SignalBoundary`, `GlobalStation`, `TrackObserver`, the schedule types and
// the railway saved data), so a changed key name or value type fails the test.
import 'package:create/src/common/common.dart';
import 'package:create/src/core/nbt.dart' show NbtKind;
import 'package:create/src/redstone/support/text.dart' show Txt;
import 'package:create/src/trains/bogey/abstract_bogey_block.dart';
import 'package:create/src/trains/bogey/standard_bogey_block.dart';
import 'package:create/src/trains/display/flap_display_layout.dart';
import 'package:create/src/trains/display/flap_display_section.dart';
import 'package:create/src/trains/entity/arrival_sound_queue.dart';
import 'package:create/src/trains/entity/carriage.dart';
import 'package:create/src/trains/entity/carriage_bogey.dart';
import 'package:create/src/trains/entity/carriage_contraption.dart';
import 'package:create/src/trains/entity/train.dart';
import 'package:create/src/trains/entity/train_icon_type.dart';
import 'package:create/src/trains/entity/train_migration.dart';
import 'package:create/src/trains/graph/dimension_palette.dart';
import 'package:create/src/trains/graph/edge_point_type.dart';
import 'package:create/src/trains/graph/track_edge.dart';
import 'package:create/src/trains/graph/track_edge_intersection.dart';
import 'package:create/src/trains/graph/track_graph.dart';
import 'package:create/src/trains/graph/track_node.dart';
import 'package:create/src/trains/graph/track_node_location.dart';
import 'package:create/src/trains/manager/railway_saved_data.dart';
import 'package:create/src/trains/observer/filter_item_stack.dart';
import 'package:create/src/trains/observer/track_observer.dart';
import 'package:create/src/trains/schedule/condition/schedule_wait_condition.dart';
import 'package:create/src/trains/schedule/condition/scheduled_delay.dart';
import 'package:create/src/trains/schedule/destination/change_throttle_instruction.dart';
import 'package:create/src/trains/schedule/destination/destination_instruction.dart';
import 'package:create/src/trains/schedule/destination/schedule_instruction.dart';
import 'package:create/src/trains/schedule/schedule.dart';
import 'package:create/src/trains/schedule/schedule_entry.dart';
import 'package:create/src/trains/schedule/schedule_runtime.dart';
import 'package:create/src/trains/signal/edge_group_color.dart';
import 'package:create/src/trains/signal/signal_boundary.dart';
import 'package:create/src/trains/signal/signal_edge_group.dart';
import 'package:create/src/trains/signal/signal_types.dart';
import 'package:create/src/trains/station/global_package_port.dart';
import 'package:create/src/trains/station/global_station.dart';
import 'package:create/src/trains/station/station_marker.dart';
import 'package:create/src/trains/track/bezier_connection.dart';
import 'package:create/src/trains/track/track_block_entity.dart';
import 'package:create/src/trains/track/track_level.dart' show TrackLevel;
import 'package:create/src/trains/track/track_material.dart';
import 'package:create/src/trains/util/ctag.dart';
import 'package:test/test.dart';

const String _trainId = '00000000-0000-4000-8000-000000000001';
const String _stationId = '00000000-0000-4000-8000-000000000002';
const String _signalId = '00000000-0000-4000-8000-000000000003';
const String _observerId = '00000000-0000-4000-8000-000000000004';
const String _groupA = '00000000-0000-4000-8000-000000000005';
const String _groupB = '00000000-0000-4000-8000-000000000006';

/// A standard bogey block for the carriages (registered on first use).
AbstractBogeyBlock _bogeyBlock() =>
    AbstractBogeyBlock.byKey('create:small_bogey') ??
    StandardBogeyBlock.registerStandardBlocks().first;

TrackNode _node(double x, double z, int netId) => TrackNode(
  TrackNodeLocation(x, 0, z).inDimension(overworldId),
  netId,
  (0.0, 1.0, 0.0),
);

TrackEdge _edge(TrackNode a, TrackNode b) =>
    TrackEdge(a, b, null, TrackMaterial.ANDESITE);

/// A two node graph with one straight edge.
({TrackGraph graph, TrackNode a, TrackNode b, TrackEdge edge}) _twoNodeGraph() {
  final graph = TrackGraph('00000000-0000-4000-8000-000000000010');
  final a = _node(0, 0, 1);
  final b = _node(0, 4, 2);
  graph
    ..addNode(a)
    ..addNode(b);
  final edge = _edge(a, b);
  graph.putConnection(a, b, edge);
  return (graph: graph, a: a, b: b, edge: edge);
}

/// A carriage whose four wheel points sit on the graph's edge.
Carriage _carriage(TrackGraph graph, TrackNode a, TrackNode b, TrackEdge edge) {
  final block = _bogeyBlock();
  final carriage = Carriage(
    CarriageBogey(block, false, null),
    CarriageBogey(block, false, null),
    3,
  );
  for (final bogey in [
    carriage.bogeys.getFirst()!,
    carriage.bogeys.getSecond()!,
  ]) {
    bogey.points.getFirst()
      ..node1 = a
      ..node2 = b
      ..edge = edge
      ..position = 1.0;
    bogey.points.getSecond()
      ..node1 = a
      ..node2 = b
      ..edge = edge
      ..position = 2.0;
  }
  return carriage;
}

Schedule _schedule() => Schedule.of(
  [
    ScheduleEntry(_destination('Central'), [
      [ScheduledDelay()..data.putInt('Value', 3)],
    ]),
    ScheduleEntry(ChangeThrottleInstruction()..data.putInt('Value', 50), []),
  ],
  true,
  1,
);

/// A `DestinationInstruction` with the given filter text.
DestinationInstruction _destination(String text) =>
    DestinationInstruction()..data.putString('Text', text);

void main() {
  setUp(() => Schedule.ensureRegistered());

  group('Carriage', () {
    test('round-trips every key of Carriage.write', () {
      final g = _twoNodeGraph();
      final carriage = _carriage(g.graph, g.a, g.b, g.edge)
        ..stalled = true
        ..presentConductors = Couple.create(true, false)
        ..serialisedEntity = CTag()
        ..serialisedEntity.putString('id', 'minecraft:minecart')
        ..serialisedEntity.putInt('count', 1);
      carriage.serialisedPassengers[0] = CTag()
        ..putUuid('PlayerPassenger', _trainId);

      carriage.getDimensional(overworldId)
        ..positionAnchor = (10.0, 20.0, 30.0)
        ..rotationAnchors = Couple.create<Vec3?>(
          (1.0, 0.5, 0.0),
          (2.0, 0.5, 0.0),
        )
        ..cutoff = 0.25
        ..discardTicks = 3
        ..pivot = TrackNodeLocation(1.0, 2.0, 3.0).inDimension(overworldId);

      final dimensions = DimensionPalette();
      final tag = carriage.write(dimensions);

      expect(tag.containsKind('FirstBogey', NbtKind.compound), isTrue);
      expect(tag.getBoolean('Stalled'), isTrue);
      expect(tag.getBoolean('FrontConductor'), isTrue);
      expect(tag.getBoolean('BackConductor'), isFalse);
      expect(tag.getInt('Spacing'), 3);
      expect(tag.getCompound('Entity').getString('id'), 'minecraft:minecart');
      expect(
        tag
            .getCompound('Passengers')
            .getCompound('Seat0')
            .getUuid('PlayerPassenger'),
        _trainId,
      );

      final positioning = tag.getCompoundList('EntityPositioning').single;
      expect(positioning.getInt('Dim'), 0);
      expect(positioning.getFloat('Cutoff'), 0.25);
      expect(positioning.getInt('DiscardTicks'), 3);
      expect(positioning.getCompound('Pivot').getBlockPos('Pos'), (2, 4, 6));
      // `VecHelper.writeNBT`: a list of three doubles.
      expect(positioning.getVec3('PositionAnchor'), (10.0, 20.0, 30.0));
      // `VecHelper.writeNBTCompound`: each anchor is `{V: [x, y, z]}`, not `{X, Y, Z}`.
      final anchors = positioning.getCompoundList('RotationAnchors');
      expect(anchors, hasLength(2));
      expect(anchors[0].contains('V'), isTrue);
      expect(anchors[0].contains('X'), isFalse);
      expect(anchors[0].getVec3('V'), (1.0, 0.5, 0.0));
      expect(anchors[1].getVec3('V'), (2.0, 0.5, 0.0));

      final back = Carriage.read(tag, g.graph, dimensions);
      expect(back.stalled, isTrue);
      expect(back.presentConductors.getFirst(), isTrue);
      expect(back.presentConductors.getSecond(), isFalse);
      expect(back.bogeySpacing, 3);
      expect(back.serialisedEntity.getString('id'), 'minecraft:minecart');
      expect(
        back.serialisedPassengers[0]!.getUuid('PlayerPassenger'),
        _trainId,
      );
      expect(back.bogeys.getSecond(), isNotNull);
      expect(back.bogeys.getFirst()!.points.getFirst().position, 1.0);

      final backDimensional = back.getDimensional(overworldId);
      expect(backDimensional.positionAnchor, (10.0, 20.0, 30.0));
      expect(backDimensional.rotationAnchors.getFirst(), (1.0, 0.5, 0.0));
      expect(backDimensional.rotationAnchors.getSecond(), (2.0, 0.5, 0.0));
      expect(backDimensional.cutoff, 0.25);
      expect(backDimensional.discardTicks, 3);
      expect(backDimensional.pivot!.getLocation(), (1.0, 2.0, 3.0));
    });

    test('a single bogey carriage writes no SecondBogey', () {
      final block = _bogeyBlock();
      final carriage = Carriage(CarriageBogey(block, false, null), null, 0);
      final tag = carriage.write(DimensionPalette());
      expect(tag.contains('SecondBogey'), isFalse);
      final back = Carriage.read(tag, null, DimensionPalette());
      expect(back.bogeys.getSecond(), isNull);
    });
  });

  group('Train', () {
    test('round-trips the train, its carriage, runtime and navigation', () {
      final g = _twoNodeGraph();
      final station = GlobalStation()
        ..setId(_stationId)
        ..setLocation(Couple.create(g.a.location, g.b.location), 1.0)
        ..name = 'Central';
      g.graph.edgePoints.put(EdgePointType.STATION, station);

      final carriage = _carriage(g.graph, g.a, g.b, g.edge);
      final train = Train(
        _trainId,
        '00000000-0000-4000-8000-0000000000aa',
        g.graph,
        [carriage],
        <int>[],
        true,
        3,
        name: Txt.literal('Express'),
        icon: TrainIconType.byId('create:electric'),
      );

      train
        ..speed = 1.5
        ..throttle = 0.75
        ..targetSpeed = 2.0
        ..speedBeforeStall = 1.0
        ..fuelTicks = 42
        ..currentlyBackwards = true
        ..derailed = true
        ..updateSignalBlocks = true
        ..currentStation = _stationId;
      train.occupiedSignalBlocks[_groupA] = _signalId;
      train.occupiedSignalBlocks[_groupB] = null;
      train.reservedSignalBlocks.add(_groupB);
      train.occupiedObservers.add(_observerId);
      train.migratingPoints.add(
        TrainMigration()
          ..locations = Couple.create(
            TrackNodeLocation(0.0, 0.0, 0.0).inDimension(overworldId),
            TrackNodeLocation(0.0, 0.0, 4.0).inDimension(overworldId),
          )
          ..positionOnOldEdge = 1.25
          ..curve = false
          ..fallback = (0.5, 1.0, -2.0),
      );

      train.runtime.setSchedule(_schedule(), false);
      train.runtime
        ..state = State.POST_TRANSIT
        ..paused = true
        ..completed = true
        ..isAutoSchedule = true
        ..currentEntry = 1
        ..conditionProgress = [1]
        ..conditionContext = [CTag()..putInt('Time', 5)]
        ..predictionTicks = [10, 20];

      train.navigation
        ..destination = station
        ..distanceToDestination = 12.5
        ..distanceStartedAt = 30.0
        ..destinationBehindTrain = true
        ..announceArrival = true
        ..currentPath = [Couple.create(g.a, g.b)]
        ..waitingForSignal = Pair.of(_signalId, true)
        ..distanceToSignal = 3.5
        ..ticksWaitingForSignal = 7;

      final dimensions = DimensionPalette();
      final tag = train.write(dimensions);

      expect(tag.getUuid('Id'), _trainId);
      expect(tag.getUuid('Owner'), '00000000-0000-4000-8000-0000000000aa');
      expect(tag.getUuid('Graph'), g.graph.id);
      expect(tag.getCompoundList('Carriages'), hasLength(1));
      expect(tag.getIntArray('CarriageSpacing'), isEmpty);
      expect(tag.getBoolean('DoubleEnded'), isTrue);
      expect(tag.getDouble('Speed'), 1.5);
      expect(tag.getDouble('Throttle'), 0.75);
      expect(tag.getDouble('SpeedBeforeStall'), 1.0);
      expect(tag.getInt('Fuel'), 42);
      expect(tag.getDouble('TargetSpeed'), 2.0);
      expect(tag.getString('IconType'), 'create:electric');
      expect(tag.getInt('MapColorIndex'), 3);
      expect(tag.getString('Name'), '"Express"');
      expect(tag.getUuid('Station'), _stationId);
      expect(tag.getBoolean('Backwards'), isTrue);
      expect(tag.getBoolean('Derailed'), isTrue);
      expect(tag.getBoolean('UpdateSignals'), isTrue);

      final signalBlocks = tag.getCompoundList('SignalBlocks');
      expect(signalBlocks, hasLength(2));
      expect(signalBlocks[0].getUuid('Id'), _groupA);
      expect(signalBlocks[0].getUuid('Boundary'), _signalId);
      expect(signalBlocks[1].getUuid('Boundary'), isNull);
      expect(
        tag.getCompoundList('ReservedSignalBlocks').single.getUuid('Id'),
        _groupB,
      );
      expect(
        tag.getCompoundList('OccupiedObservers').single.getUuid('Id'),
        _observerId,
      );

      final migration = tag.getCompoundList('MigratingPoints').single;
      expect(migration.getBoolean('Curve'), isFalse);
      expect(migration.getVec3('Fallback'), (0.5, 1.0, -2.0));
      expect(migration.getDouble('Position'), 1.25);
      expect(migration.getCompoundList('Nodes'), hasLength(2));

      final runtime = tag.getCompound('Runtime');
      expect(runtime.getInt('CurrentEntry'), 1);
      expect(runtime.getBoolean('AutoSchedule'), isTrue);
      expect(runtime.getBoolean('Paused'), isTrue);
      expect(runtime.getBoolean('Completed'), isTrue);
      expect(runtime.getString('State'), 'POST_TRANSIT');
      expect(runtime.getIntArray('ConditionProgress'), [1]);
      expect(runtime.getIntArray('TransitTimes'), [10, 20]);
      expect(runtime.getCompound('Schedule').getBoolean('Cyclic'), isTrue);
      expect(
        runtime.getCompoundList('ConditionContext').single.getInt('Time'),
        5,
      );

      final navigation = tag.getCompound('Navigation');
      expect(navigation.getUuid('Destination'), _stationId);
      expect(navigation.getDouble('DistanceToDestination'), 12.5);
      expect(navigation.getDouble('DistanceStartedAt'), 30.0);
      expect(navigation.getBoolean('BehindTrain'), isTrue);
      expect(navigation.getBoolean('AnnounceArrival'), isTrue);
      expect(navigation.getCompoundList('Path'), hasLength(1));
      expect(navigation.getUuid('BlockingSignal'), _signalId);
      expect(navigation.getBoolean('BlockingSignalSide'), isTrue);
      expect(navigation.getDouble('DistanceToSignal'), 3.5);
      expect(navigation.getInt('TicksWaitingForSignal'), 7);

      final back = Train.read(tag, {g.graph.id: g.graph}, dimensions);
      expect(back.id, _trainId);
      expect(back.owner, '00000000-0000-4000-8000-0000000000aa');
      expect(back.graph, same(g.graph));
      expect(back.carriages, hasLength(1));
      expect(back.speed, 1.5);
      expect(back.throttle, 0.75);
      expect(back.speedBeforeStall, 1.0);
      expect(back.targetSpeed, 2.0);
      expect(back.fuelTicks, 42);
      expect(back.icon.id, 'create:electric');
      expect(back.name.plain, 'Express');
      expect(back.mapColorIndex, 3);
      expect(back.currentStation, _stationId);
      expect(back.getCurrentStation(), same(station));
      expect(back.currentlyBackwards, isTrue);
      expect(back.derailed, isTrue);
      expect(back.updateSignalBlocks, isTrue);
      expect(back.occupiedSignalBlocks, {_groupA: _signalId, _groupB: null});
      expect(back.reservedSignalBlocks, {_groupB});
      expect(back.occupiedObservers, {_observerId});

      final backMigration = back.migratingPoints.single;
      expect(backMigration.positionOnOldEdge, 1.25);
      expect(backMigration.curve, isFalse);
      expect(backMigration.fallback, (0.5, 1.0, -2.0));
      expect(backMigration.locations.getSecond().dimension, overworldId);

      expect(back.runtime.state, State.POST_TRANSIT);
      expect(back.runtime.paused, isTrue);
      expect(back.runtime.completed, isTrue);
      expect(back.runtime.isAutoSchedule, isTrue);
      expect(back.runtime.currentEntry, 1);
      expect(back.runtime.conditionProgress, [1]);
      expect(back.runtime.conditionContext.single.getInt('Time'), 5);
      expect(back.runtime.predictionTicks, [10, 20]);
      expect(back.runtime.schedule!.entries, hasLength(2));
      expect(back.runtime.schedule!.cyclic, isTrue);

      expect(back.navigation.destination, same(station));
      expect(back.navigation.distanceToDestination, 12.5);
      expect(back.navigation.distanceStartedAt, 30.0);
      expect(back.navigation.destinationBehindTrain, isTrue);
      expect(back.navigation.announceArrival, isTrue);
      expect(back.navigation.currentPath, hasLength(1));
      expect(
        back.navigation.currentPath.single.getFirst().getLocation(),
        g.a.location,
      );
      expect(back.navigation.waitingForSignal!.getFirst(), _signalId);
      expect(back.navigation.waitingForSignal!.getSecond(), isTrue);
      expect(back.navigation.distanceToSignal, 3.5);
      expect(back.navigation.ticksWaitingForSignal, 7);
    });

    test('writes no SpeedBeforeStall when it is null', () {
      final train = Train(_trainId, null, null, [], [], false, 0);
      final tag = train.write(DimensionPalette());
      expect(tag.contains('SpeedBeforeStall'), isFalse);
      expect(tag.contains('Owner'), isFalse);
      expect(tag.contains('Graph'), isFalse);
      expect(tag.contains('Station'), isFalse);
      // The default name is the translatable `create.train.unnamed` component.
      expect(tag.getString('Name'), '{"translate":"create.train.unnamed"}');
    });
  });

  group('edge points', () {
    test('SignalBoundary writes Tiles/Group/Update/Type/State per side', () {
      final boundary = SignalBoundary()
        ..setId(_signalId)
        ..setLocation(
          Couple.create(
            TrackNodeLocation(0.0, 0.0, 0.0).inDimension(overworldId),
            TrackNodeLocation(0.0, 0.0, 4.0).inDimension(overworldId),
          ),
          2.0,
        );
      boundary.blockEntities.getFirst()[(1, 2, 3)] = true;
      boundary.blockEntities.getSecond()[(4, 5, 6)] = false;
      boundary.groups.set(true, _groupA);
      boundary.groups.set(false, _groupB);
      boundary.sidesToUpdate.set(true, true);
      boundary.sidesToUpdate.set(false, false);
      boundary.types.set(true, SignalType.CROSS_SIGNAL);
      boundary.types.set(false, SignalType.ENTRY_SIGNAL);
      boundary.cachedStates.set(true, SignalState.RED);
      boundary.cachedStates.set(false, SignalState.GREEN);

      final dimensions = DimensionPalette();
      final tag = CTag();
      boundary.write(tag, dimensions);

      expect(tag.getUuid('Id'), _signalId);
      expect(tag.getDouble('Position'), 2.0);
      expect(tag.getCompoundList('Edge'), hasLength(2));
      expect(tag.getCompoundList('Tiles1').single.getBlockPos('Pos'), (
        1,
        2,
        3,
      ));
      expect(tag.getCompoundList('Tiles1').single.getBoolean('Power'), isTrue);
      expect(tag.getCompoundList('Tiles2').single.getBoolean('Power'), isFalse);
      expect(tag.getUuid('Group1'), _groupA);
      expect(tag.getUuid('Group2'), _groupB);
      expect(tag.getBoolean('Update1'), isTrue);
      expect(tag.contains('Update2'), isFalse);
      expect(tag.getString('Type1'), 'CROSS_SIGNAL');
      expect(tag.getString('Type2'), 'ENTRY_SIGNAL');
      expect(tag.getString('State1'), 'RED');
      expect(tag.getString('State2'), 'GREEN');
      // `SignalBoundary` extends `TrackEdgePoint`, not `SingleBlockEntityEdgePoint`: it has no
      // `BlockEntityPos`/`BlockEntityDimension`.
      expect(tag.contains('BlockEntityPos'), isFalse);

      final back = SignalBoundary()..read(tag, false, dimensions);
      expect(back.id, _signalId);
      expect(back.position, 2.0);
      expect(back.blockEntities.getFirst()[(1, 2, 3)], isTrue);
      expect(back.blockEntities.getSecond()[(4, 5, 6)], isFalse);
      expect(back.groups.getFirst(), _groupA);
      expect(back.groups.getSecond(), _groupB);
      expect(back.sidesToUpdate.getFirst(), isTrue);
      expect(back.sidesToUpdate.getSecond(), isFalse);
      expect(back.types.getFirst(), SignalType.CROSS_SIGNAL);
      expect(back.types.getSecond(), SignalType.ENTRY_SIGNAL);
      expect(back.cachedStates.getFirst(), SignalState.RED);
      expect(back.cachedStates.getSecond(), SignalState.GREEN);
    });

    test(
      'GlobalStation writes Name/Assembling/Ports with the offline buffer',
      () {
        final station = GlobalStation()
          ..setId(_stationId)
          ..setLocation(
            Couple.create(
              TrackNodeLocation(0.0, 0.0, 0.0).inDimension(overworldId),
              TrackNodeLocation(0.0, 0.0, 4.0).inDimension(overworldId),
            ),
            1.0,
          )
          ..name = 'Central'
          ..assembling = true
          ..blockEntityPos = (7, 8, 9)
          ..blockEntityDimension = 'minecraft:the_nether';
        final port = GlobalPackagePort()
          ..address = 'factory'
          ..primed = true;
        port.offlineBuffer.setStackInSlot(
          2,
          CTag()
            ..putString('id', 'create:cardboard_package_12x12')
            ..putInt('count', 3),
        );
        station.connectedPorts[(7, 8, 9)] = port;

        final dimensions = DimensionPalette();
        final tag = CTag();
        station.write(tag, dimensions);

        expect(tag.getString('Name'), 'Central');
        expect(tag.getBoolean('Assembling'), isTrue);
        expect(tag.getBlockPos('BlockEntityPos'), (7, 8, 9));
        expect(
          tag.getInt('BlockEntityDimension'),
          dimensions.encode('minecraft:the_nether'),
        );
        final ports = tag.getCompoundList('Ports');
        expect(ports, hasLength(1));
        expect(ports.single.getString('Address'), 'factory');
        expect(ports.single.getBoolean('Primed'), isTrue);
        expect(ports.single.getBlockPos('Pos'), (7, 8, 9));
        final buffer = ports.single.getCompound('OfflineBuffer');
        expect(buffer.getInt('Size'), 18);
        final items = buffer.getCompoundList('Items');
        expect(items, hasLength(1));
        expect(items.single.getInt('Slot'), 2);
        expect(items.single.getString('id'), 'create:cardboard_package_12x12');
        expect(items.single.getInt('count'), 3);

        final back = GlobalStation()..read(tag, false, dimensions);
        expect(back.name, 'Central');
        expect(back.assembling, isTrue);
        expect(back.blockEntityPos, (7, 8, 9));
        expect(back.blockEntityDimension, 'minecraft:the_nether');
        final backPort = back.connectedPorts[(7, 8, 9)]!;
        expect(backPort.address, 'factory');
        expect(backPort.primed, isTrue);
        expect(
          backPort.offlineBuffer.getStackInSlot(2)!.getString('id'),
          'create:cardboard_package_12x12',
        );
      },
    );

    test('TrackObserver writes Activated/Filter/TrainId', () {
      final observer = TrackObserver()
        ..setId(_observerId)
        ..setLocation(
          Couple.create(
            TrackNodeLocation(0.0, 0.0, 0.0).inDimension(overworldId),
            TrackNodeLocation(0.0, 0.0, 4.0).inDimension(overworldId),
          ),
          1.0,
        );
      final train = Train(_trainId, null, null, [], [], false, 0);
      observer.keepAlive(train);
      observer.setFilterAndNotify(
        null,
        FilterItemStack.ofItem('minecraft:iron_ingot'),
      );

      final dimensions = DimensionPalette();
      final tag = CTag();
      observer.write(tag, dimensions);

      expect(tag.getInt('Activated'), 8);
      expect(tag.getCompound('Filter').getString('id'), 'minecraft:iron_ingot');
      expect(tag.getUuid('TrainId'), _trainId);
      expect(tag.getUuid('Id'), _observerId);

      final back = TrackObserver()..read(tag, false, dimensions);
      expect(back.isActivated(), isTrue);
      expect(back.getFilter().itemKey(), 'minecraft:iron_ingot');
      expect(back.getCurrentTrain(), _trainId);
    });

    test('TrackEdgeIntersection round-trips', () {
      final intersection = TrackEdgeIntersection()
        ..id = _signalId
        ..groupId = _groupA
        ..location = 1.5
        ..targetLocation = 2.5
        ..target = Couple.create(
          TrackNodeLocation(0.0, 0.0, 0.0).inDimension(overworldId),
          TrackNodeLocation(4.0, 0.0, 0.0).inDimension(overworldId),
        );

      final dimensions = DimensionPalette();
      final tag = intersection.write(dimensions);
      expect(tag.getUuid('Id'), _signalId);
      expect(tag.getUuid('GroupId'), _groupA);
      expect(tag.getDouble('Location'), 1.5);
      expect(tag.getDouble('TargetLocation'), 2.5);
      expect(tag.getCompoundList('TargetEdge'), hasLength(2));

      final back = TrackEdgeIntersection.read(tag, dimensions);
      expect(back.id, _signalId);
      expect(back.groupId, _groupA);
      expect(back.location, 1.5);
      expect(back.targetLocation, 2.5);
      expect(back.target.getSecond().getLocation(), (4.0, 0.0, 0.0));
    });
  });

  group('track graph points', () {
    test('a graph keeps its edge points and the edges referencing them', () {
      final g = _twoNodeGraph();
      final station = GlobalStation()
        ..setId(_stationId)
        ..setLocation(Couple.create(g.a.location, g.b.location), 1.0)
        ..name = 'Central';
      final observer = TrackObserver()
        ..setId(_observerId)
        ..setLocation(Couple.create(g.a.location, g.b.location), 2.0);
      final boundary = SignalBoundary()
        ..setId(_signalId)
        ..setLocation(Couple.create(g.a.location, g.b.location), 3.0);

      g.graph.edgePoints.put(EdgePointType.STATION, station);
      g.graph.edgePoints.put(EdgePointType.OBSERVER, observer);
      g.graph.edgePoints.put(EdgePointType.SIGNAL, boundary);
      // `EdgeData.write` asks each point for its type; `create()` normally sets it.
      station.setType(EdgePointType.STATION);
      observer.setType(EdgePointType.OBSERVER);
      boundary.setType(EdgePointType.SIGNAL);
      g.edge.getEdgeData().points.addAll([station, observer, boundary]);
      g.edge.getEdgeData().setSingleSignalGroup(g.graph, null);

      final dimensions = DimensionPalette();
      final tag = g.graph.write(dimensions);
      final points = tag.getCompound('Points');
      expect(points.getCompoundList('create:station'), hasLength(1));
      expect(points.getCompoundList('create:observer'), hasLength(1));
      expect(points.getCompoundList('create:signal'), hasLength(1));

      final back = TrackGraph.read(tag, dimensions);
      final backStation = back.getPoint(EdgePointType.STATION, _stationId)!;
      expect(backStation.name, 'Central');
      final backObserver = back.getPoint(EdgePointType.OBSERVER, _observerId)!;
      expect(backObserver.id, _observerId);
      final backSignal = back.getPoint(EdgePointType.SIGNAL, _signalId)!;
      expect(backSignal.id, _signalId);

      final backA = back.locateNode(g.a.location)!;
      final backB = back.locateNode(g.b.location)!;
      final edge = back.getConnectionsFrom(backA)[backB]!;
      final edgePoints = edge.getEdgeData().getPoints();
      expect(edgePoints, hasLength(3));
      expect(edgePoints.map((p) => p.id).toSet(), {
        _stationId,
        _observerId,
        _signalId,
      });
      // `SignalGroup` is absent when the edge has signal boundaries.
      expect(edge.getEdgeData().hasSignalBoundaries(), isTrue);
    });
  });

  group('railway saved data', () {
    test('toMap/fromMap round-trips graphs, signal groups and trains', () {
      final g = _twoNodeGraph();
      final station = GlobalStation()
        ..setId(_stationId)
        ..setLocation(Couple.create(g.a.location, g.b.location), 1.0)
        ..name = 'Central';
      g.graph.edgePoints.put(EdgePointType.STATION, station);

      final boundary = SignalBoundary()
        ..setId(_signalId)
        ..setLocation(Couple.create(g.a.location, g.b.location), 2.0);
      boundary.groups.set(true, _groupA);
      boundary.groups.set(false, _groupB);
      boundary.setType(EdgePointType.SIGNAL);
      g.graph.edgePoints.put(EdgePointType.SIGNAL, boundary);
      g.edge.getEdgeData().points.add(boundary);
      g.edge.getEdgeData().setSingleSignalGroup(g.graph, null);

      final groupA = SignalEdgeGroup(_groupA)..color = EdgeGroupColor.GREEN;
      final groupB = SignalEdgeGroup(_groupB)..color = EdgeGroupColor.BLUE;
      groupA.putAdjacent(_groupB);

      final train = Train(
        _trainId,
        null,
        g.graph,
        [_carriage(g.graph, g.a, g.b, g.edge)],
        <int>[],
        false,
        0,
        name: Txt.literal('Express'),
      )..currentStation = _stationId;

      final data = RailwaySavedData()
        ..trackNetworks[g.graph.id] = g.graph
        ..signalEdgeGroups[_groupA] = groupA
        ..signalEdgeGroups[_groupB] = groupB
        ..trains[_trainId] = train;

      expect(groupA.adjacent, contains(_groupB));

      final map = data.toMap();
      // The saved data is a compound with the Java list keys.
      expect(map.containsKey('RailGraphs'), isTrue);
      expect(map.containsKey('SignalBlocks'), isTrue);
      expect(map.containsKey('Trains'), isTrue);
      expect(map.containsKey('DimensionPalette'), isTrue);

      final back = RailwaySavedData.fromMap(map);
      expect(back.trackNetworks.keys, [g.graph.id]);
      expect(back.signalEdgeGroups.keys.toSet(), {_groupA, _groupB});
      expect(back.signalEdgeGroups[_groupA]!.color, EdgeGroupColor.GREEN);
      // `Connected` (intersections) is written, `adjacent` is rebuilt from the signal boundaries.
      expect(back.signalEdgeGroups[_groupA]!.intersecting, isEmpty);
      expect(back.signalEdgeGroups[_groupA]!.adjacent, contains(_groupB));
      expect(back.trains.keys, [_trainId]);

      final backGraph = back.trackNetworks[g.graph.id]!;
      expect(
        backGraph.getPoint(EdgePointType.STATION, _stationId)!.name,
        'Central',
      );
      expect(backGraph.getPoint(EdgePointType.SIGNAL, _signalId), isNotNull);
      // Loading links the two sides of a signal boundary again.
      expect(back.signalEdgeGroups[_groupB]!.adjacent, contains(_groupA));

      final backTrain = back.trains[_trainId]!;
      expect(backTrain.graph, same(backGraph));
      expect(backTrain.name.plain, 'Express');
      expect(backTrain.carriages, hasLength(1));
      expect(backTrain.getCurrentStation()!.name, 'Central');
    });
  });

  group('schedule', () {
    test('every instruction round-trips its Id and Data', () {
      for (final pair in Schedule.INSTRUCTION_TYPES) {
        final instruction = pair.second();
        instruction.data.putString('Text', 'marker');
        instruction.data.putInt('Value', 37);
        final tag = instruction.write();
        expect(tag.getString('Id'), pair.first);
        final back = ScheduleInstruction.fromTag(tag);
        expect(back.getId(), pair.first, reason: pair.first);
        expect(back.getData().getString('Text'), 'marker', reason: pair.first);
        expect(back.getData().getInt('Value'), 37, reason: pair.first);
      }
    });

    test('every condition round-trips its Id and Data', () {
      for (final pair in Schedule.CONDITION_TYPES) {
        final condition = pair.second();
        condition.data.putInt('Time', 7);
        condition.data.putString('Text', 'marker');
        final tag = condition.write();
        expect(tag.getString('Id'), pair.first);
        final back = ScheduleWaitCondition.fromTag(tag);
        expect(back, isNotNull, reason: pair.first);
        expect(back!.getId(), pair.first, reason: pair.first);
        expect(back.getData().getInt('Time'), 7, reason: pair.first);
        expect(back.getData().getString('Text'), 'marker', reason: pair.first);
      }
    });

    test('ScheduleRuntime round-trips CurrentEntry/State/ConditionContext/TransitTimes', () {
      final train = Train(_trainId, null, null, [], [], false, 0);
      final runtime = train.runtime..setSchedule(_schedule(), false);
      runtime
        ..state = State.IN_TRANSIT
        ..paused = false
        ..completed = true
        ..isAutoSchedule = true
        ..currentEntry = 1
        ..conditionProgress = [2]
        ..conditionContext = [CTag()..putInt('StatusVersion', 4)]
        ..predictionTicks = [11, 22];

      final tag = runtime.write();
      expect(tag.getInt('CurrentEntry'), 1);
      expect(tag.getString('State'), 'IN_TRANSIT');
      expect(tag.getBoolean('Paused'), isFalse);
      expect(tag.getBoolean('Completed'), isTrue);
      expect(tag.getBoolean('AutoSchedule'), isTrue);
      expect(tag.getIntArray('ConditionProgress'), [2]);
      expect(tag.getIntArray('TransitTimes'), [11, 22]);
      expect(
        tag.getCompound('Schedule').getCompoundList('Entries'),
        hasLength(2),
      );

      final backTrain = Train(_trainId, null, null, [], [], false, 0);
      backTrain.runtime.read(tag);
      expect(backTrain.runtime.state, State.IN_TRANSIT);
      expect(backTrain.runtime.paused, isFalse);
      expect(backTrain.runtime.completed, isTrue);
      expect(backTrain.runtime.isAutoSchedule, isTrue);
      expect(backTrain.runtime.currentEntry, 1);
      expect(backTrain.runtime.conditionProgress, [2]);
      expect(
        backTrain.runtime.conditionContext.single.getInt('StatusVersion'),
        4,
      );
      expect(backTrain.runtime.predictionTicks, [11, 22]);
      expect(backTrain.runtime.schedule!.entries, hasLength(2));
    });
  });

  group('display, markers and sounds', () {
    test('FlapDisplayLayout/Section round-trip Key, Sections, Width, Cycle and Text', () {
      final layout = FlapDisplayLayout(10);
      layout.getSections().single.setText(Txt.literal('Hello'));

      final tag = layout.write();
      expect(tag.getString('Key'), 'Default');
      final sections = tag.getCompoundList('Sections');
      expect(sections, hasLength(1));
      expect(
        sections.single.getFloat('Width'),
        FlapDisplaySection.MONOSPACE * 10,
      );
      expect(sections.single.getString('Cycle'), 'alphabet');
      expect(sections.single.contains('SingleFlap'), isFalse);
      expect(sections.single.contains('Gap'), isFalse);
      expect(sections.single.getString('Text'), '"Hello"');

      final back = FlapDisplayLayout(10)..read(tag);
      expect(back.isLayout('Default'), isTrue);
      expect(back.getSections(), hasLength(1));
      expect(back.getSections().single.getText()!.plain, 'Hello');
    });

    test('StationMarker round-trips source, target and name', () {
      final marker = StationMarker(
        (1, 2, 3),
        (4, 5, 6),
        Txt.literal('Central'),
      );
      final tag = marker.save();
      expect(tag.getBlockPos('source'), (1, 2, 3));
      expect(tag.getBlockPos('target'), (4, 5, 6));
      expect(tag.getString('name'), '"Central"');

      final back = StationMarker.load(tag);
      expect(back.getSource(), (1, 2, 3));
      expect(back.getTarget(), (4, 5, 6));
      expect(back.getName().plain, 'Central');
      expect(back.getId(), 'create:station-4,5,6');
      expect(back, marker);
    });

    test(
      'ArrivalSoundQueue serializes under SoundQueue with Offset/Sources',
      () {
        final queue = ArrivalSoundQueue()
          ..offset = 4
          ..add(3, (1, 2, 3))
          ..add(5, (4, 5, 6));

        final tag = CTag();
        queue.serialize(tag);
        final soundQueue = tag.getCompound('SoundQueue');
        expect(soundQueue.getInt('Offset'), 4);
        final sources = soundQueue.getCompoundList('Sources');
        expect(sources, hasLength(2));
        expect(sources[0].getInt('Tick'), 3);
        expect(sources[0].getBlockPos('Pos'), (1, 2, 3));

        final back = ArrivalSoundQueue()..deserialize(tag);
        expect(back.offset, 4);
        expect(back.firstTick(), 7);
        expect(back.sources[3], [(1, 2, 3)]);
        expect(back.sources[5], [(4, 5, 6)]);
      },
    );

    test('CarriageContraption writes AssemblyDirection/Controls/Conductors/SoundQueue', () {
      final contraption = CarriageContraption(Direction.north)
        ..forwardControls = true
        ..backwardControls = false
        ..blockConductors = Couple.create(true, false);
      contraption.conductorSeats[(1, 2, 3)] = Couple.create(true, false);
      contraption.soundQueue.add(2, (4, 5, 6));

      final tag = CTag();
      contraption.writeNBT(tag);
      // Java writes `Direction.name()` (`CarriageContraption.java:193`), the *constant* name, and
      // the Java side reads it back with `readEnum` (`CarriageContraption.java:379-386`), which
      // matches a constant name exactly and otherwise falls back to `getEnumConstants()[0]`
      // (`down`) -- the direction a Java client cannot call `getClockWise()` on.
      expect(tag.getString('AssemblyDirection'), 'NORTH');
      expect(tag.getBoolean('FrontControls'), isTrue);
      expect(tag.getBoolean('BackControls'), isFalse);
      expect(tag.getBoolean('FrontBlazeConductor'), isTrue);
      expect(tag.getBoolean('BackBlazeConductor'), isFalse);
      final seats = tag.getCompoundList('ConductorSeats');
      expect(seats, hasLength(1));
      expect(seats.single.getBlockPos('Pos'), (1, 2, 3));
      expect(seats.single.getBoolean('Forward'), isTrue);
      expect(seats.single.getBoolean('Backward'), isFalse);
      expect(
        tag.getCompound('SoundQueue').getCompoundList('Sources'),
        hasLength(1),
      );

      final back = CarriageContraption(Direction.north)..readNBT(tag);
      expect(back.assemblyDirection, Direction.north);
      expect(back.forwardControls, isTrue);
      expect(back.backwardControls, isFalse);
      expect(back.blockConductors.getFirst(), isTrue);
      expect(back.blockConductors.getSecond(), isFalse);
      expect(back.conductorSeats[(1, 2, 3)]!.getFirst(), isTrue);
      expect(back.soundQueue.sources[2], [(4, 5, 6)]);
    });

    test(
      'AssemblyDirection is the Java constant name, which readEnum resolves horizontally',
      () {
        // `CarriageContraption.readEnum` (`CarriageContraption.java:379-386`), exactly: the
        // constant whose `name()` equals the string, else `getEnumConstants()[0]` = `down`. A
        // `down` assembly direction is what makes a Java client throw
        // `IllegalStateException: Unable to get Y-rotated facing of down` in
        // `CarriageContraptionEntity.updateRenderedPortalCutoff`, so the name the port writes has
        // to survive this reader as a horizontal direction.
        Direction javaReadEnum(String name) => Direction.values.firstWhere(
          (d) => d.name.toUpperCase() == name,
          orElse: () => Direction.values.first,
        );

        for (final direction in Direction.values) {
          final tag = CTag();
          CarriageContraption(direction).writeNBT(tag);
          final written = tag.getString('AssemblyDirection');
          expect(
            written,
            direction.name.toUpperCase(),
            reason: 'Java writes `Direction.name()`: ${direction.name}',
          );
          expect(javaReadEnum(written), direction);
          if (direction.isHorizontal) {
            // The client dereferences `getAssemblyDirection().getClockWise()`: it exists only for
            // horizontal directions.
            expect(javaReadEnum(written).clockWise.axis, isNot(Axis.y));
          }
        }

        // A lower case name -- what the pre-fix build wrote, and so what a carriage in an existing
        // world carries -- still reads as the direction it names (`enumFromNbtName` compares case
        // insensitively). Java would fall back to `down` for it, which is exactly the crash.
        final legacy = CarriageContraption(Direction.north)
          ..readNBT(CTag()..putString('AssemblyDirection', 'north'));
        expect(legacy.assemblyDirection, Direction.north);

        // A name that names no constant, and a missing key, read as the first constant, `down`, on
        // both sides (`getEnumConstants()[0]` / `getStringOr(key, "")`).
        final unknown = CarriageContraption(Direction.north)
          ..readNBT(CTag()..putString('AssemblyDirection', 'sideways'));
        expect(unknown.assemblyDirection, Direction.down);
        final missing = CarriageContraption(Direction.north)..readNBT(CTag());
        expect(missing.assemblyDirection, Direction.down);
      },
    );

  });

  group('track block entity', () {
    BezierConnection curve() => BezierConnection(
      Couple.create((0, 0, 0), (0, 0, 4)),
      Couple.create((0.5, 0.0, 0.0), (0.5, 0.0, 4.0)),
      Couple.create((0.0, 0.0, 1.0), (0.0, 0.0, -1.0)),
      Couple.create((0.0, 1.0, 0.0), (0.0, 1.0, 0.0)),
      true,
      false,
      TrackMaterial.ANDESITE,
    );

    test('write/read keep Connections, Smoothing and BoundLocation', () {
      final entity = TrackBlockEntity((0, 0, 0), _FakeEnv());
      final bezier = curve();
      entity.connections[bezier.getKey()] = bezier;
      entity.tilt.smoothingAngle = 12.5;
      entity.boundLocation = Pair<String, Pos>('minecraft:the_nether', (
        1,
        2,
        3,
      ));

      final tag = CTag();
      entity.write(tag, clientPacket: false);
      expect(tag.getCompoundList('Connections'), hasLength(1));
      expect(tag.getDouble('Smoothing'), 12.5);
      expect(tag.getString('BoundDimension'), 'minecraft:the_nether');
      expect(tag.getBlockPos('BoundLocation'), (1, 2, 3));

      final back = TrackBlockEntity((0, 0, 0), _FakeEnv())
        ..read(tag, clientPacket: false);
      expect(back.connections, hasLength(1));
      expect(back.connections.containsKey((0, 0, 4)), isTrue);
      expect(back.isTilted(), isTrue);
      expect(back.tilt.smoothingAngle, 12.5);
      expect(back.boundLocation!.getFirst(), 'minecraft:the_nether');
      expect(back.boundLocation!.getSecond(), (1, 2, 3));
    });

    test('writeSafe writes only the untilted curves', () {
      final entity = TrackBlockEntity((0, 0, 0), _FakeEnv());
      final bezier = curve();
      entity.connections[bezier.getKey()] = bezier;
      entity.tilt.smoothingAngle = 12.5;
      entity.boundLocation = Pair<String, Pos>('minecraft:the_nether', (
        1,
        2,
        3,
      ));

      final tag = CTag();
      entity.writeSafe(tag);
      expect(tag.getCompoundList('Connections'), hasLength(1));
      expect(tag.contains('Smoothing'), isFalse);
      expect(tag.contains('BoundLocation'), isFalse);
      expect(tag.contains('BoundDimension'), isFalse);
    });
  });
}

/// A [TrackBlockEntityEnv] without a world, for the NBT tests.
final class _FakeEnv implements TrackBlockEntityEnv {
  @override
  TrackLevel? get level => null;

  @override
  bool get isRemoved => false;

  @override
  void notifyUpdate() {}

  @override
  void setChanged() {}
}
