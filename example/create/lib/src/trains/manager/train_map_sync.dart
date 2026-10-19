// `TrainMapSync` (server side of `create:train_map_request`): the train positions and states the
// Xaero / JourneyMap / FTB Chunks integrations show. A requesting player gets a full sync at once
// and then a light packet every 5 ticks and a full one every 10, until the request expires after
// 20 ticks without a refresh.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart';
import '../../common/vec_helper.dart';
import '../../core/module.dart';
import '../entity/train.dart';
import '../graph/edge_point_type.dart';
import '../manager/create.dart';
import '../signal/signal_types.dart';

/// `TrainMapSync.TrainState`.
enum TrainState {
  running,
  runningManually,
  derailed,
  scheduleInterrupted,
  conductorMissing,
  navigationFailed,
}

/// `TrainMapSync.SignalState`.
enum SignalState { notWaiting, waitingForRedstone, blockSignal, chainSignal }

/// Installs the request handler and the periodic sync.
void installTrainMapSync(CreateContext ctx) {
  final bus = ctx.services.find<PayloadBus>();
  bus?.onServerbound('create:train_map_request', (player, fields) {
    TrainMapSync.requestReceived(bus, player);
  });
  ctx.listen(
    Events.serverTickStart,
    (server, e) => TrainMapSync.serverTick(bus),
  );
}

/// Clears the requesting players (plugin unload).
void unloadTrainMapSync() => TrainMapSync.clear();

abstract final class TrainMapSync {
  /// `lightPacketInterval`.
  static const int lightPacketInterval = 5;

  /// `fullPacketInterval`.
  static const int fullPacketInterval = 10;

  /// Ticks since the last sync.
  static int ticks = 0;

  /// Requesting player uuids with the ticks until the request expires.
  static final Map<String, int> _requesting = {};

  /// `requestReceived(sender)`: sends a full sync immediately for a new requester.
  static void requestReceived(PayloadBus? bus, Player player) {
    final id = player.getId().asString;
    final sendImmediately = !_requesting.containsKey(id);
    _requesting[id] = 20;
    if (sendImmediately) send(bus, false);
  }

  /// `serverTick`: the periodic light / full sync.
  static void serverTick(PayloadBus? bus) {
    ticks++;
    if (_requesting.isEmpty) return;
    for (final id in _requesting.keys.toList()) {
      final left = (_requesting[id] ?? 1) - 1;
      if (left <= 0) {
        _requesting.remove(id);
      } else {
        _requesting[id] = left;
      }
    }
    if (_requesting.isEmpty) return;
    if (ticks % fullPacketInterval == 0) {
      send(bus, false);
    } else if (ticks % lightPacketInterval == 0) {
      send(bus, true);
    }
  }

  /// `send(server, light)`: one packet per requesting player.
  static void send(PayloadBus? bus, bool light) {
    if (bus == null || _requesting.isEmpty) return;
    final entries = <Map<String, Object?>>[
      for (final train in Create.RAILWAYS.trains.values)
        {'first': train.id, 'second': _createEntry(bus, train)},
    ];
    for (final player in bus.roster.players) {
      if (!_requesting.containsKey(player.getId().asString)) continue;
      bus.sendClientbound('create:train_map_sync', player, {
        'light': light,
        'entries': entries,
      });
    }
  }

  static void clear() {
    ticks = 0;
    _requesting.clear();
  }

  /// `createEntry(server, train)`.
  static Map<String, Object?> _createEntry(PayloadBus bus, Train train) {
    final stopped = train.speed.abs() < 0.05;
    final carriages = train.carriages;
    final positions = List<double>.filled(carriages.length * 6, 0);
    final dimensions = <String?>[];

    for (var i = 0; i < carriages.length; i++) {
      final carriage = carriages[i];
      Vec3? leadingPos;
      Vec3? trailingPos;

      if (train.graph == null) {
        // The train is derailed: the anchors of the dimensional carriage.
        final pair = carriage.anyAvailableDimensionalCarriage();
        if (pair == null || carriage.presentInMultipleDimensions()) {
          dimensions.add(null);
          continue;
        }
        leadingPos = pair.getSecond().rotationAnchors.getFirst();
        trailingPos = pair.getSecond().rotationAnchors.getSecond();
        if (leadingPos == null || trailingPos == null) {
          dimensions.add(null);
          continue;
        }
        dimensions.add(pair.getFirst());
      } else {
        // The train is on track: the wheel points.
        final leading = carriage.getLeadingPoint();
        final trailing = carriage.getTrailingPoint();
        if (leading.edge == null || trailing.edge == null) {
          dimensions.add(null);
          continue;
        }

        final leadingDim =
            leading.node1 == null || leading.edge!.isInterDimensional()
            ? null
            : leading.node1!.getLocation().dimension;
        final trailingDim =
            trailing.node1 == null || trailing.edge!.isInterDimensional()
            ? null
            : trailing.node1!.getLocation().dimension;
        dimensions.add(
          leadingDim == null || leadingDim != trailingDim ? null : leadingDim,
        );

        leadingPos = leading.getPosition(train.graph);
        trailingPos = trailing.getPosition(train.graph);
      }

      positions[i * 6] = leadingPos.$1;
      positions[i * 6 + 1] = leadingPos.$2;
      positions[i * 6 + 2] = leadingPos.$3;
      positions[i * 6 + 3] = trailingPos.$1;
      positions[i * 6 + 4] = trailingPos.$2;
      positions[i * 6 + 5] = trailingPos.$3;
    }

    var state = TrainState.running;
    var signalState = SignalState.notWaiting;
    var fueled = false;
    var targetStationDistance = 0;
    var targetStationName = '';
    String? waitingForTrain;

    final ownerName = _ownerName(bus, train.owner);

    if (train.derailed) {
      state = TrainState.derailed;
      return _entry(
        positions: positions,
        dimensions: dimensions,
        state: state,
        signalState: signalState,
        fueled: fueled,
        backwards: train.currentlyBackwards,
        targetStationDistance: targetStationDistance,
        ownerName: ownerName,
        targetStationName: targetStationName,
        waitingForTrain: waitingForTrain,
      );
    }

    final runtime = train.runtime;
    if (runtime.getSchedule() != null && stopped) {
      if (runtime.paused) {
        state = TrainState.scheduleInterrupted;
      } else if (train.status.conductor) {
        state = TrainState.conductorMissing;
      } else if (train.status.navigation) {
        state = TrainState.navigationFailed;
      }
    }

    if ((runtime.getSchedule() == null || runtime.paused) && train.speed != 0) {
      state = TrainState.runningManually;
    }

    final currentStation = train.getCurrentStation();
    if (currentStation != null) {
      targetStationName = currentStation.name;
      targetStationDistance = 0;
    } else if (train.navigation.destination != null && !runtime.paused) {
      targetStationName = train.navigation.destination!.name;
      final distance = train.navigation.distanceToDestination.floor();
      targetStationDistance = distance < 0 ? 0 : distance;
    }

    if (stopped && train.navigation.waitingForSignal != null) {
      final signalId = train.navigation.waitingForSignal!.getFirst();
      final side = train.navigation.waitingForSignal!.getSecond();
      final graph = train.graph;
      if (signalId != null && graph != null) {
        final signal = graph.getPoint(EdgePointType.SIGNAL, signalId);
        if (signal != null) {
          final chainSignal = signal.types.get(side) == SignalType.CROSS_SIGNAL;
          signalState = chainSignal
              ? SignalState.chainSignal
              : SignalState.blockSignal;
          if (signal.isForcedRedPrimary(side)) {
            signalState = SignalState.waitingForRedstone;
          } else {
            final group =
                Create.RAILWAYS.signalEdgeGroups[signal.groups.get(side)];
            if (group != null) {
              for (final other in group.trains) {
                if (identical(other, train)) continue;
                waitingForTrain = other.id;
                break;
              }
            }
          }
        }
      }
    }

    if (train.fuelTicks > 0 && !stopped) fueled = true;

    return _entry(
      positions: positions,
      dimensions: dimensions,
      state: state,
      signalState: signalState,
      fueled: fueled,
      backwards: train.currentlyBackwards,
      targetStationDistance: targetStationDistance,
      ownerName: ownerName,
      targetStationName: targetStationName,
      waitingForTrain: waitingForTrain,
    );
  }

  static String _ownerName(PayloadBus bus, String? owner) {
    if (owner == null) return '';
    for (final player in bus.roster.players) {
      if (player.getId().asString == owner) return player.getName();
    }
    return '';
  }

  static Map<String, Object?> _entry({
    required List<double> positions,
    required List<String?> dimensions,
    required TrainState state,
    required SignalState signalState,
    required bool fueled,
    required bool backwards,
    required int targetStationDistance,
    required String ownerName,
    required String targetStationName,
    required String? waitingForTrain,
  }) => {
    'positions': positions,
    'dimensions': dimensions,
    'state': state.index,
    'signalState': signalState.index,
    'fueled': fueled,
    'backwards': backwards,
    'targetStationDistance': targetStationDistance,
    'ownerName': ownerName,
    'targetStationName': targetStationName,
    'waitingForTrain': waitingForTrain,
  };
}
