// `Navigation` (pure): the path of a train to its destination station. It drives the train towards
// the destination (braking, curves, signals, cross signal chains), and searches paths with a
// weighted frontier search that penalises other trains, red signals and occupied stations.
import 'dart:math' as math;

import '../../common/data.dart';
import '../../common/direction.dart' show clampNum, toFloat;
import '../../common/vec_helper.dart';
import '../graph/dimension_palette.dart';
import '../graph/discovered_path.dart';
import '../graph/edge_point_type.dart';
import '../graph/track_edge.dart';
import '../graph/track_graph.dart';
import '../graph/track_node.dart';
import '../graph/track_node_location.dart';
import '../manager/create.dart';
import '../signal/signal_boundary.dart';
import '../signal/signal_types.dart';
import '../station/global_station.dart';
import '../track/track_material.dart';
import '../util/ctag.dart';
import 'java_priority_queue.dart';
import 'train.dart';
import 'train_level.dart';
import 'travelling_point.dart';

/// `Navigation.StationTest`.
typedef StationTest = bool Function(
  double distance,
  double cost,
  Map<TrackEdge, Pair<bool, Couple<TrackNode>>> reachedVia,
  Pair<Couple<TrackNode>, TrackEdge> current,
  GlobalStation station,
);

class Navigation {
  final Train train;

  GlobalStation? destination;
  double distanceToDestination = 0;
  double distanceStartedAt = 0;
  bool destinationBehindTrain = false;
  bool announceArrival = false;
  List<Couple<TrackNode>> currentPath = [];

  final TravellingPoint _signalScout = TravellingPoint();
  Pair<String?, bool>? waitingForSignal;
  final Map<String, Pair<SignalBoundary, bool>> _waitingForChainedGroups = {};
  double distanceToSignal = 0;
  int ticksWaitingForSignal = 0;

  Navigation(this.train);

  void tick(TrainLevel level) {
    if (destination == null) return;

    if (!train.runtime.paused) {
      final frontDriver = train.hasForwardConductor();
      final backDriver = train.hasBackwardConductor();
      if (destinationBehindTrain && !backDriver) {
        if (frontDriver) {
          train.status.missingCorrectConductor();
        } else {
          train.status.missingConductor();
        }
        cancelNavigation();
        return;
      }

      if (!destinationBehindTrain && !frontDriver) {
        train.status.missingConductor();
        cancelNavigation();
        return;
      }

      train.status.foundConductor();
    }

    destination!.reserveFor(train);

    final acceleration = train.acceleration();
    final brakingDistance = (train.speed * train.speed) / (2 * acceleration);
    final speedMod = destinationBehindTrain ? -1.0 : 1.0;
    final preDepartureLookAhead = train.getCurrentStation() != null ? 4.5 : 0.0;
    double distanceToNextCurve = -1;

    // Signals
    if (train.graph != null) {
      if (waitingForSignal != null && _currentSignalResolved()) {
        final signalId = waitingForSignal!.getFirst();
        final signal = signalId == null
            ? null
            : train.graph!.getPoint(EdgePointType.SIGNAL, signalId);
        if (signal != null &&
            signal.types.get(waitingForSignal!.getSecond()) ==
                SignalType.CROSS_SIGNAL) {
          _waitingForChainedGroups.clear();
        }
        waitingForSignal = null;
      }

      final leadingPoint = !destinationBehindTrain
          ? train.carriages.first.getLeadingPoint()
          : train.carriages.last.getTrailingPoint();

      if (waitingForSignal == null) {
        distanceToSignal = double.maxFinite;
        ticksWaitingForSignal = 0;
      }

      if (distanceToSignal > 1 / 16.0) {
        var curveDistanceTracker = -1.0;

        _signalScout.node1 = leadingPoint.node1;
        _signalScout.node2 = leadingPoint.node2;
        _signalScout.edge = leadingPoint.edge;
        _signalScout.position = leadingPoint.position;

        final brakingDistanceNoFlicker =
            brakingDistance + 3 - (brakingDistance % 3);
        final scanDistance = clampNum(
          brakingDistanceNoFlicker,
          preDepartureLookAhead,
          distanceToDestination,
        );

        var crossSignalDistanceTracker = -1.0;
        Pair<String?, bool>? trackingCrossSignal;
        _waitingForChainedGroups.clear();

        // Adding 50 to the distance due to unresolved inaccuracies in
        // TravellingPoint::travel
        _signalScout.travel(
          train.graph!,
          (distanceToDestination + 50) * speedMod,
          controlSignalScout(),
          (distance, couple) {
            // > scanDistance and not following down a cross signal
            final crossSignalTracked = trackingCrossSignal != null;
            if (!crossSignalTracked && distance > scanDistance) return true;

            final nodes = couple.getSecond();
            final boundary = couple.getFirst();
            if (identical(boundary, destination) &&
                (boundary as GlobalStation).canApproachFrom(
                  nodes.getSecond(),
                )) {
              return true;
            }
            if (boundary is! SignalBoundary) return false;
            final signal = boundary;

            final entering = signal.getGroup(nodes.getSecond());
            final signalEdgeGroup = entering == null
                ? null
                : Create.RAILWAYS.signalEdgeGroups[entering];
            if (signalEdgeGroup == null) return false;

            final primary = entering == signal.groups.getFirst();
            final crossSignal =
                signal.types.get(primary) == SignalType.CROSS_SIGNAL;
            final occupied =
                !train.manualTick &&
                (signal.isForcedRed(nodes.getSecond()) ||
                    signalEdgeGroup.isOccupiedUnless(train));

            if (!crossSignalTracked) {
              if (crossSignal) {
                // Now entering cross signal path
                trackingCrossSignal = Pair.of(boundary.id, primary);
                crossSignalDistanceTracker = distance;
                _waitingForChainedGroups[entering!] = Pair.of(signal, primary);
              }
              if (occupied) {
                // Section is occupied
                waitingForSignal = Pair.of(boundary.id, primary);
                distanceToSignal = distance;
                if (!crossSignal) return true; // Standard entry signal, do not collect any further segments
              }
              if (!occupied &&
                  !crossSignal &&
                  distance < distanceToSignal + .25 &&
                  distance < brakingDistanceNoFlicker) {
                signalEdgeGroup.reserved =
                    signal; // Reserve group for traversal
              }
              return false;
            }

            _waitingForChainedGroups[entering!] = Pair.of(
              signal,
              primary,
            ); // Add group to chain
            if (occupied) {
              // Section is occupied, but wait at the cross signal that started the chain
              waitingForSignal = trackingCrossSignal;
              distanceToSignal = crossSignalDistanceTracker;
              if (!crossSignal) return true; // Entry signals end a chain
            }
            if (!crossSignal) {
              if (distance < distanceToSignal + .25) {
                // Collect and reset the signal chain because none were blocked
                trackingCrossSignal = null;
                _reserveChain();
                return false;
              } else {
                return true; // End of a blocked signal chain
              }
            }

            return false;
          },
          (distance, edge) {
            final turn = edge.getTurn()!;
            final vDistance =
                (turn.starts.getFirst().$2 - turn.starts.getSecond().$2).abs();

            // ignore turn if its a straight & mild slope
            if (vDistance > 1 / 16.0) {
              if (turn.axes
                          .getFirst()
                          .multiplyBy((1.0, 0.0, 1.0))
                          .distanceTo(
                            turn.axes.getSecond().multiplyBy((1.0, 0.0, 1.0)) *
                                -1,
                          ) <
                      1 / 64.0 &&
                  vDistance / turn.getLength() < toFloat(.225)) {
                return;
              }
            }

            final current = toFloat(curveDistanceTracker);
            if (current == -1 || distance < current)
              curveDistanceTracker = distance;
          },
        );

        if (trackingCrossSignal != null && waitingForSignal == null)
          _reserveChain();

        distanceToNextCurve = toFloat(curveDistanceTracker);
      } else {
        ticksWaitingForSignal++;
      }
    }

    var targetDistance = waitingForSignal != null
        ? distanceToSignal
        : distanceToDestination;

    // always overshoot to ensure the travelling point crosses the target
    targetDistance += 0.25;

    // dont leave until green light
    if (targetDistance > 1 / 32.0 && train.getCurrentStation() != null) {
      if (waitingForSignal != null &&
          distanceToSignal < preDepartureLookAhead) {
        ticksWaitingForSignal++;
        return;
      }
      train.leaveStation();
    }

    train.currentlyBackwards = destinationBehindTrain;

    if (targetDistance < -10) {
      cancelNavigation();
      return;
    }

    if (targetDistance - train.speed.abs() < 1 / 32.0) {
      train.speed = math.max(targetDistance, 1 / 32.0) * speedMod;
      return;
    }

    train.burnFuel();

    var topSpeed = train.maxSpeed();

    if (targetDistance < 10) {
      final maxApproachSpeed = topSpeed * (targetDistance / 10);
      final speedRelativeToStation = train.speed * speedMod;

      if (speedRelativeToStation > maxApproachSpeed) {
        train.speed +=
            (maxApproachSpeed - train.speed.abs()) * toFloat(.5) * speedMod;
        return;
      }
    }

    topSpeed *= train.throttle;
    final turnTopSpeed = math.min(topSpeed, train.maxTurnSpeed());

    var targetSpeed = targetDistance > brakingDistance
        ? topSpeed * speedMod
        : 0.0;

    if (distanceToNextCurve != -1) {
      final slowingDistance =
          brakingDistance - (turnTopSpeed * turnTopSpeed) / (2 * acceleration);
      final targetTurnSpeed = distanceToNextCurve > slowingDistance
          ? topSpeed * speedMod
          : turnTopSpeed * speedMod;
      if (targetTurnSpeed.abs() < targetSpeed.abs())
        targetSpeed = targetTurnSpeed;
    }

    train.targetSpeed = targetSpeed;
    train.approachTargetSpeed(1);
  }

  void _reserveChain() {
    train.reservedSignalBlocks.addAll(_waitingForChainedGroups.keys);
    _waitingForChainedGroups.forEach((groupId, boundary) {
      final signalEdgeGroup = Create.RAILWAYS.signalEdgeGroups[groupId];
      if (signalEdgeGroup != null)
        signalEdgeGroup.reserved = boundary.getFirst();
    });
    _waitingForChainedGroups.clear();
  }

  bool _currentSignalResolved() {
    if (train.manualTick) return true;
    if (distanceToDestination < toFloat(.5)) return true;
    final signalId = waitingForSignal!.getFirst();
    final signal = signalId == null
        ? null
        : train.graph!.getPoint(EdgePointType.SIGNAL, signalId);
    if (signal == null) return true;

    // Cross Signal
    if (signal.types.get(waitingForSignal!.getSecond()) ==
        SignalType.CROSS_SIGNAL) {
      for (final entry in _waitingForChainedGroups.entries) {
        final boundary = entry.value;
        final signalEdgeGroup = Create.RAILWAYS.signalEdgeGroups[entry.key];
        if (signalEdgeGroup == null) {
          // Migration, re-initialize chain
          waitingForSignal!.setFirst(null);
          return true;
        }
        if (boundary.getFirst().isForcedRedPrimary(boundary.getSecond())) {
          train.reservedSignalBlocks.clear();
          return false;
        }
        if (signalEdgeGroup.isOccupiedUnless(train)) return false;
      }
      return true;
    }

    // Entry Signal
    final groupId = signal.groups.get(waitingForSignal!.getSecond());
    if (groupId == null) return true;
    final signalEdgeGroup = Create.RAILWAYS.signalEdgeGroups[groupId];
    if (signalEdgeGroup == null) return true;
    if (!signalEdgeGroup.isOccupiedUnless(train)) return true;
    return false;
  }

  bool isActive() => destination != null;

  ITrackSelector control(TravellingPoint mp) {
    if (destination == null)
      return mp.steer(train.manualSteer, (0.0, 1.0, 0.0));
    return (graph, pair) =>
        _navigateOptions(currentPath, graph, pair.getSecond());
  }

  ITrackSelector controlSignalScout() {
    if (destination == null)
      return _signalScout.steer(train.manualSteer, (0.0, 1.0, 0.0));
    final pathCopy = List<Couple<TrackNode>>.of(currentPath);
    return (graph, pair) => _navigateOptions(pathCopy, graph, pair.getSecond());
  }

  MapEntry<TrackNode, TrackEdge> _navigateOptions(
    List<Couple<TrackNode>> path,
    TrackGraph graph,
    List<MapEntry<TrackNode, TrackEdge>> options,
  ) {
    if (path.isEmpty) return options[0];
    final nodes = path[0];
    final targetEdge = graph.getConnection(nodes);
    for (final entry in options) {
      if (!identical(entry.value, targetEdge)) continue;
      path.removeAt(0);
      return entry;
    }
    return options[0];
  }

  void cancelNavigation() {
    distanceToDestination = 0;
    currentPath.clear();
    if (destination == null) return;
    destination!.cancelReservation(train);
    destination = null;
    train.runtime.transitInterrupted();
    train.reservedSignalBlocks.clear();
  }

  double startNavigation(DiscoveredPath? pathTo) {
    final noneFound = pathTo == null;
    final distance = noneFound ? -1.0 : pathTo.distance.abs();
    final cost = noneFound ? -1.0 : pathTo.cost;

    distanceToDestination = distance;

    if (noneFound) {
      distanceToDestination = distanceStartedAt = 0;
      currentPath = [];
      if (destination != null) cancelNavigation();
      return -1;
    }

    if (distanceToDestination.abs() > 100) announceArrival = true;

    currentPath = pathTo.path;
    destinationBehindTrain = pathTo.distance < 0;
    train.reservedSignalBlocks.clear();
    train.navigation.waitingForSignal = null;

    if (destination == null) distanceStartedAt = distance;

    if (identical(destination, pathTo.destination)) return 0;

    if (!train.runtime.paused) {
      final frontDriver = train.hasForwardConductor();
      final backDriver = train.hasBackwardConductor();
      if (destinationBehindTrain && !backDriver) {
        if (frontDriver) {
          train.status.missingCorrectConductor();
        } else {
          train.status.missingConductor();
        }
        return -1;
      }

      if (!destinationBehindTrain && !frontDriver) {
        if (backDriver) {
          train.status.missingCorrectConductor();
        } else {
          train.status.missingConductor();
        }
        return -1;
      }

      train.status.foundConductor();
    }

    destination = pathTo.destination;
    return cost;
  }

  DiscoveredPath? findPathToStation(
    GlobalStation destination,
    double maxCost,
  ) => findPathTo([destination], maxCost);

  DiscoveredPath? findPathTo(List<GlobalStation> destinations, double maxCost) {
    final graph = train.graph;
    if (graph == null) return null;

    final results = Couple.create<DiscoveredPath?>(null, null);
    for (final forward in Iterate.trueAndFalse) {
      // When updating destinations midtransit, avoid reversing out of path
      if (destination != null && destinationBehindTrain == forward) continue;

      final initialPoint = forward
          ? train.carriages.first.getLeadingPoint()
          : train.carriages.last.getTrailingPoint();
      final initialEdge = forward
          ? initialPoint.edge
          : graph.getConnectionsFrom(initialPoint.node2)[initialPoint.node1];

      search(double.maxFinite, maxCost, forward, destinations, (
        distance,
        cost,
        reachedVia,
        currentEntry,
        globalStation,
      ) {
        for (final candidate in destinations) {
          if (identical(globalStation, candidate)) {
            final edge = currentEntry.getSecond();
            final node1 = currentEntry.getFirst().getFirst();
            final node2 = currentEntry.getFirst().getSecond();

            final path = <Couple<TrackNode>>[];
            var backTrack = reachedVia[edge];
            var toReach = Couple.create(node1, node2);
            TrackEdge? edgeReached = edge;
            while (backTrack != null) {
              if (identical(edgeReached, initialEdge)) break;
              if (backTrack.getFirst()) path.insert(0, toReach);
              toReach = backTrack.getSecond();
              edgeReached = graph.getConnection(toReach);
              backTrack = reachedVia[edgeReached];
            }

            final position = edge.getLength() - candidate.getLocationOn(edge);
            final distanceToDest = distance - position;
            results.set(
              forward,
              DiscoveredPath(
                (forward ? 1 : -1) * distanceToDest,
                cost,
                path,
                candidate,
              ),
            );
            return true;
          }
        }
        return false;
      });
    }

    final front = results.getFirst();
    final back = results.getSecond();

    final frontEmpty = front == null;
    final backEmpty = back == null;
    final canDriveForward = train.hasForwardConductor() || train.runtime.paused;
    final canDriveBackward =
        train.doubleEnded && train.hasBackwardConductor() ||
        train.runtime.paused;

    if (backEmpty || !canDriveBackward) return canDriveForward ? front : null;
    if (frontEmpty || !canDriveForward) return canDriveBackward ? back : null;

    final frontBetter = maxCost == -1
        ? -back.distance > front.distance
        : back.cost > front.cost;
    return frontBetter ? front : back;
  }

  GlobalStation? findNearestApproachable(bool forward) {
    final graph = train.graph;
    if (graph == null) return null;

    GlobalStation? result;
    final acceleration = train.acceleration();
    final minDistance =
        toFloat(.75) * (train.speed * train.speed) / (2 * acceleration);
    final maxDistance = math.max(
      32,
      toFloat(1.5) * (train.speed * train.speed) / (2 * acceleration),
    );

    searchWithin(maxDistance.toDouble(), forward, null, (
      distance,
      cost,
      reachedVia,
      currentEntry,
      globalStation,
    ) {
      if (distance < minDistance) return false;

      final edge = currentEntry.getSecond();
      final position = edge.getLength() - globalStation.getLocationOn(edge);
      if (distance - position < minDistance) return false;
      final presentTrain = globalStation.getPresentTrain();
      if (presentTrain != null && !identical(presentTrain, train)) return false;
      result = globalStation;
      return true;
    });

    return result;
  }

  /// `search(maxDistance, forward, destinations, stationTest)` (no cost limit).
  void searchWithin(
    double maxDistance,
    bool forward,
    List<GlobalStation>? destinations,
    StationTest stationTest,
  ) => search(maxDistance, -1, forward, destinations, stationTest);

  void search(
    double maxDistance,
    double maxCost,
    bool forward,
    List<GlobalStation>? destinations,
    StationTest stationTest,
  ) {
    final graph = train.graph;
    if (graph == null) return;

    // Cache the list of track types that the train can travel on
    final validTypes = <TrackType>{};
    for (var i = 0; i < train.carriages.length; i++) {
      final carriage = train.carriages[i];
      final leading = carriage.leadingBogey();
      if (i == 0) {
        validTypes.addAll(
          leading.type.getValidPathfindingTypes(leading.getStyle()),
        );
      } else {
        validTypes.retainAll(
          leading.type.getValidPathfindingTypes(leading.getStyle()),
        );
      }
      if (carriage.isOnTwoBogeys()) {
        final trailing = carriage.trailingBogey();
        validTypes.retainAll(
          trailing.type.getValidPathfindingTypes(trailing.getStyle()),
        );
      }
    }
    if (validTypes.isEmpty)
      return; // if there are no valid track types, a route can't be found

    final penalties = Map<TrackEdge, int>.identity();
    final costRelevant = maxCost >= 0;
    if (costRelevant) {
      for (final otherTrain in Create.RAILWAYS.trains.values) {
        if (!identical(otherTrain.graph, graph)) continue;
        if (identical(otherTrain, train)) continue;
        final navigationPenalty = otherTrain.getNavigationPenalty();
        otherTrain.getEndpointEdges().forEach((nodes) {
          if (nodes.either((n) => n == null)) return;
          for (final flip in Iterate.trueAndFalse) {
            final e = graph.getConnection(flip ? nodes.swap() : nodes);
            if (e == null) continue;
            final existing = penalties[e] ?? 0;
            penalties[e] = existing + navigationPenalty ~/ 2;
          }
        });
      }
    }

    final startingPoint = forward
        ? train.carriages.first.getLeadingPoint()
        : train.carriages.last.getTrailingPoint();

    final visited = Set<TrackEdge>.identity();
    final reachedVia = Map<TrackEdge, Pair<bool, Couple<TrackNode>>>.identity();
    final frontier = JavaPriorityQueue<_FrontierEntry>(
      (a, b) => a.compareTo(b),
    );

    final initialNode1 = (forward ? startingPoint.node1 : startingPoint.node2)!;
    final initialNode2 = (forward ? startingPoint.node2 : startingPoint.node1)!;
    final initialEdge = graph.getConnectionsFrom(initialNode1)[initialNode2];
    if (initialEdge == null) return;

    final distanceToNode2 = forward
        ? initialEdge.getLength() - startingPoint.position
        : startingPoint.position;

    var signalWeight = clampNum(
      ticksWaitingForSignal * 2,
      Penalties.RED_SIGNAL,
      200,
    );

    // Apply penalties to initial edge
    var initialPenalty = 0;
    if (costRelevant) initialPenalty += penalties[initialEdge] ?? 0;

    final initialSignalData = initialEdge.getEdgeData();
    if (initialSignalData.hasPoints()) {
      for (final point in initialSignalData.getPoints()) {
        if (point.getLocationOn(initialEdge) <
            initialEdge.getLength() - distanceToNode2)
          continue;
        if (costRelevant && distanceToNode2 + initialPenalty > maxCost) return;
        if (!point.canNavigateVia(initialNode2)) return;
        if (point is SignalBoundary) {
          final signal = point;
          if (signal.isForcedRed(initialNode2)) {
            initialPenalty += Penalties.REDSTONE_RED_SIGNAL;
            continue;
          }
          final group = signal.getGroup(initialNode2);
          if (group == null) continue;
          final signalEdgeGroup = Create.RAILWAYS.signalEdgeGroups[group];
          if (signalEdgeGroup == null) continue;
          if (signalEdgeGroup.isOccupiedUnless(signal)) {
            initialPenalty += signalWeight;
            signalWeight ~/= 2;
          }
        }
        if (point is GlobalStation) {
          final station = point;
          final presentTrain = station.getPresentTrain();
          final isOwnStation = identical(presentTrain, train);
          if (presentTrain != null && !isOwnStation)
            initialPenalty += Penalties.STATION_WITH_TRAIN;
          if (station.canApproachFrom(initialNode2) &&
              stationTest(
                distanceToNode2,
                distanceToNode2 + initialPenalty,
                reachedVia,
                Pair.of(Couple.create(initialNode1, initialNode2), initialEdge),
                station,
              )) {
            return;
          }
          if (!isOwnStation) initialPenalty += Penalties.STATION;
        }
      }
    }

    if (costRelevant && distanceToNode2 + initialPenalty > maxCost) return;

    frontier.add(
      _FrontierEntry(
        distanceToNode2,
        initialPenalty,
        0,
        false,
        initialNode1,
        initialNode2,
        initialEdge,
      ),
    );

    while (frontier.isNotEmpty) {
      final entry = frontier.poll()!;
      if (!visited.add(entry.edge)) continue;

      final distance = entry.distance;
      final penalty = entry.penalty;

      if (distance > maxDistance) continue;

      final edge = entry.edge;
      final node1 = entry.node1;
      final node2 = entry.node2;

      if (entry.hasDestination) {
        final signalData = edge.getEdgeData();
        if (signalData.hasPoints()) {
          for (final point in signalData.getPoints()) {
            if (point is GlobalStation) {
              final station = point;
              if (station.canApproachFrom(node2) &&
                  stationTest(
                    distance,
                    penalty.toDouble(),
                    reachedVia,
                    Pair.of(Couple.create(node1, node2), edge),
                    station,
                  )) {
                return;
              }
            }
          }
        }
      }

      final validTargets = <MapEntry<TrackNode, TrackEdge>>[];
      final connectionsFrom = graph.getConnectionsFrom(node2);
      for (final connection in connectionsFrom.entries) {
        final newNode = connection.key;
        if (identical(newNode, node1)) continue;
        if (edge.canTravelTo(connection.value)) validTargets.add(connection);
      }

      if (validTargets.isEmpty) continue;

      search:
      for (final target in validTargets) {
        if (!validTypes.contains(target.value.getTrackMaterial().trackType))
          continue;
        final newNode = target.key;
        final newEdge = target.value;
        var newPenalty = penalty;
        final edgeLength = newEdge.getLength();
        final newDistance = distance + edgeLength;

        if (costRelevant) newPenalty += penalties[newEdge] ?? 0;

        // Apply penalty to next connected edge
        var hasDestination = false;
        final signalData = newEdge.getEdgeData();
        if (signalData.hasPoints()) {
          for (final point in signalData.getPoints()) {
            if (identical(node2, initialNode1) &&
                point.getLocationOn(newEdge) < edgeLength - distanceToNode2)
              continue;
            if (costRelevant && newDistance + newPenalty > maxCost)
              continue search;
            if (!point.canNavigateVia(newNode)) continue search;
            if (point is SignalBoundary) {
              final signal = point;
              if (signal.isForcedRed(newNode)) {
                newPenalty += Penalties.REDSTONE_RED_SIGNAL;
                continue;
              }
              final group = signal.getGroup(newNode);
              if (group == null) continue;
              final signalEdgeGroup = Create.RAILWAYS.signalEdgeGroups[group];
              if (signalEdgeGroup == null) continue;
              if (signalEdgeGroup.isOccupiedUnless(signal)) {
                newPenalty += signalWeight;
                signalWeight ~/= 2;
              }
            }
            if (point is GlobalStation) {
              final station = point;
              final presentTrain = station.getPresentTrain();
              final isOwnStation = identical(presentTrain, train);
              if (presentTrain != null && !isOwnStation)
                newPenalty += Penalties.STATION_WITH_TRAIN;
              if (station.canApproachFrom(newNode) &&
                  stationTest(
                    newDistance,
                    newDistance + newPenalty,
                    reachedVia,
                    Pair.of(Couple.create(node2, newNode), newEdge),
                    station,
                  )) {
                hasDestination = true;
                break;
              }
              if (!isOwnStation) newPenalty += Penalties.STATION;
            }
          }
        }

        if (costRelevant && newDistance + newPenalty > maxCost) continue;

        double remainingDist = 0;
        // Calculate remaining distance estimator for next connected edge
        if (destinations != null && destinations.isNotEmpty) {
          remainingDist = double.maxFinite;
          final newNodePosition = newNode.getLocation().getLocation();
          for (final station in destinations) {
            final destinationNode = station.edgeLocation.getFirst();
            final destinationVec = destinationNode.getLocation();
            var dMin = (newNodePosition.$1 - destinationVec.$1).abs();
            var dMid = (newNodePosition.$2 - destinationVec.$2).abs();
            var dMax = (newNodePosition.$3 - destinationVec.$3).abs();
            // Sort distance vector in ascending order
            double temp;
            if (dMin > dMid) {
              temp = dMid;
              dMid = dMin;
              dMin = temp;
            }
            if (dMin > dMax) {
              temp = dMax;
              dMax = dMin;
              dMin = temp;
            }
            if (dMid > dMax) {
              temp = dMax;
              dMax = dMid;
              dMid = temp;
            }
            // Octile distance from newNode to station node
            var currentRemaining =
                0.317837245195782 * dMin +
                0.414213562373095 * dMid +
                dMax +
                station.position;
            if (node2.getLocation() == destinationNode) {
              currentRemaining -=
                  newEdge.getLength() *
                  2; // Correct the distance estimator for station edge
            }
            remainingDist = math.min(remainingDist, currentRemaining);
          }
        }

        reachedVia.putIfAbsent(
          newEdge,
          () => Pair.of(validTargets.length > 1, Couple.create(node1, node2)),
        );
        frontier.add(
          _FrontierEntry(
            newDistance,
            newPenalty,
            remainingDist,
            hasDestination,
            node2,
            newNode,
            newEdge,
          ),
        );
      }
    }
  }

  CTag write(DimensionPalette dimensions) {
    final tag = CTag();
    if (destination == null) return tag;

    tag.putUuid('Destination', destination!.id);
    tag.putDouble('DistanceToDestination', distanceToDestination);
    tag.putDouble('DistanceStartedAt', distanceStartedAt);
    tag.putBoolean('BehindTrain', destinationBehindTrain);
    tag.putBoolean('AnnounceArrival', announceArrival);
    tag.putCompoundList('Path', [
      for (final c in currentPath)
        CTag()..putCompoundList('Nodes', [
          c.getFirst().getLocation().write(dimensions),
          c.getSecond().getLocation().write(dimensions),
        ]),
    ]);
    if (waitingForSignal == null) return tag;
    if (waitingForSignal!.getFirst() != null)
      tag.putUuid('BlockingSignal', waitingForSignal!.getFirst()!);
    tag.putBoolean('BlockingSignalSide', waitingForSignal!.getSecond());
    tag.putDouble('DistanceToSignal', distanceToSignal);
    tag.putInt('TicksWaitingForSignal', ticksWaitingForSignal);
    return tag;
  }

  void read(CTag tag, TrackGraph? graph, DimensionPalette dimensions) {
    final destinationId = tag.getUuid('Destination');
    destination = graph != null && destinationId != null
        ? graph.getPoint(EdgePointType.STATION, destinationId)
        : null;

    if (destination == null) return;

    distanceToDestination = tag.getDouble('DistanceToDestination');
    distanceStartedAt = tag.getDouble('DistanceStartedAt');
    destinationBehindTrain = tag.getBoolean('BehindTrain');
    announceArrival = tag.getBoolean('AnnounceArrival');
    currentPath.clear();
    for (final c in tag.getCompoundList('Path')) {
      final nodes = c.getCompoundList('Nodes');
      if (nodes.length < 2) continue;
      final first = graph!.locateNode(
        TrackNodeLocation.read(nodes[0], dimensions),
      );
      final second = graph.locateNode(
        TrackNodeLocation.read(nodes[1], dimensions),
      );
      // removeBrokenPathEntries: paths with unknown nodes are dropped
      if (first == null || second == null) continue;
      currentPath.add(Couple.create(first, second));
    }

    final blocking = tag.getUuid('BlockingSignal');
    waitingForSignal = blocking != null
        ? Pair.of(blocking, tag.getBoolean('BlockingSignalSide'))
        : null;
    if (waitingForSignal == null) return;
    distanceToSignal = tag.getDouble('DistanceToSignal');
    ticksWaitingForSignal = tag.getInt('TicksWaitingForSignal');
  }
}

class _FrontierEntry {
  final double distance;
  final int penalty;
  final double remaining;
  final bool hasDestination;
  final TrackNode node1;
  final TrackNode node2;
  final TrackEdge edge;

  _FrontierEntry(
    this.distance,
    this.penalty,
    this.remaining,
    this.hasDestination,
    this.node1,
    this.node2,
    this.edge,
  );

  int compareTo(_FrontierEntry o) {
    final a = distance + penalty + remaining;
    final b = o.distance + o.penalty + o.remaining;
    return a < b ? -1 : (a > b ? 1 : 0);
  }
}
