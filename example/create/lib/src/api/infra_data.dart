// Plain data of the infrastructure hooks (pure, see infra.dart).
import '../common/common.dart';

/// A train for `/create trains` and `/create train` (`Train`).
final class TrainSummary {
  final String id;
  final String name;
  final int carriageCount;
  final bool derailed;

  /// The id of the track graph the train is on, `null` when it is on none.
  final String? graphId;
  final String? ownerName;

  /// `train.getCurrentStation().name`, when the train is waiting at one.
  final String? currentStationName;

  /// `navigation.destination.name` and `navigation.distanceToDestination`.
  final String? destinationName;
  final double distanceToDestination;

  /// `runtime.getSchedule() != null`.
  final bool hasSchedule;
  final int scheduleEntry;

  /// `runtime.state.name()`.
  final String scheduleState;
  final bool schedulePaused;

  /// `train.getPresentDimensions()` with `getPositionInDimension`.
  final List<({String dimension, Pos position})> presence;

  const TrainSummary({
    required this.id,
    required this.name,
    required this.carriageCount,
    this.derailed = false,
    this.graphId,
    this.ownerName,
    this.currentStationName,
    this.destinationName,
    this.distanceToDestination = 0,
    this.hasSchedule = false,
    this.scheduleEntry = 0,
    this.scheduleState = '',
    this.schedulePaused = false,
    this.presence = const [],
  });
}

/// A track graph for `/create trains` (`TrackGraph`).
final class TrackGraphSummary {
  final String id;
  final int nodeCount;
  final int signalCount;
  final int stationCount;

  const TrackGraphSummary(this.id, this.nodeCount, {this.signalCount = 0, this.stationCount = 0});
}

/// The report of `DumpRailwaysCommand.fillReport`.
final class RailwaySummary {
  final int graphCount;
  final int signalGroupCount;
  final int trainCount;

  /// The five graphs nearest to the command source.
  final List<TrackGraphSummary> nearestGraphs;

  /// The five trains nearest to the command source.
  final List<TrainSummary> nearestTrains;

  const RailwaySummary({
    required this.graphCount,
    required this.signalGroupCount,
    required this.trainCount,
    this.nearestGraphs = const [],
    this.nearestTrains = const [],
  });
}

/// What `/create coupling remove` found.
enum CouplingRemoval { noCouplings, notCoupled, removed }

/// `IDisplayAssemblyExceptions` / `AssemblyException`, for `/create highlight`.
final class AssemblyExceptionInfo {
  /// Where the assembly failed, `null` when the exception has no position.
  final Pos? position;
  final String message;

  const AssemblyExceptionInfo(this.message, [this.position]);
}

