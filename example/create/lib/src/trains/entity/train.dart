// `Train` (pure): a train of carriages travelling on a track graph. It owns the speed model
// (acceleration, passive slowdown, stalls), the signal reservation (occupied / reserved signal
// groups, observers), collisions with other trains, derailing, the manual and scheduled
// navigation, coupling stress and the persistence of all of it. `tick` is called once per server
// tick by the railway manager (`GlobalRailwayManager`), `earlyTick` before it.
import 'dart:collection';
import 'dart:math' as math;

import '../../content/advancement_ids.dart';
import '../../common/data.dart';
import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../../redstone/support/text.dart' show Txt;
import '../graph/dimension_palette.dart';
import '../graph/discovered_path.dart';
import '../graph/edge_point_type.dart';
import '../graph/track_edge.dart';
import '../graph/track_graph.dart';
import '../graph/track_graph_location.dart';
import '../graph/track_node.dart';
import '../manager/create.dart';
import '../observer/track_observer.dart';
import '../schedule/schedule_runtime.dart' show ScheduleRuntime, State;
import '../signal/signal_boundary.dart';
import '../signal/signal_edge_group.dart';
import '../signal/signal_types.dart';
import '../signal/track_edge_point.dart';
import '../station/global_station.dart';
import '../util/ctag.dart';
import 'carriage.dart';
import 'carriage_contraption.dart';
import 'navigation.dart';
import 'train_icon_type.dart';
import 'train_level.dart';
import 'train_migration.dart';
import 'train_name.dart';
import 'train_status.dart';
import 'travelling_point.dart';

class Train {
  double speed = 0;
  double targetSpeed = 0;
  double? speedBeforeStall;
  int carriageWaitingForChunks = -1;

  double throttle = 1;
  bool honk = false;

  String id;
  String? owner;
  TrackGraph? graph;
  late Navigation navigation;
  late ScheduleRuntime runtime;
  TrainIconType icon;
  int mapColorIndex;
  Txt name;
  late TrainStatus status;

  bool invalid = false;

  SteerDirection manualSteer = SteerDirection.none;
  bool manualTick = false;

  String? currentStation;
  bool currentlyBackwards = false;

  bool doubleEnded;
  List<Carriage> carriages;
  List<int> carriageSpacing;

  bool updateSignalBlocks = false;
  Map<String, String?> occupiedSignalBlocks = {};
  Set<String> reservedSignalBlocks = {};

  Set<String> occupiedObservers = {};
  Map<String, Pair<int, bool>> cachedObserverFiltering = {};

  List<TrainMigration> migratingPoints = [];
  int migrationCooldown = 0;
  bool derailed = false;

  int fuelTicks = 0;
  int honkTicks = 0;

  bool? lowHonk;
  int honkPitch = 0;

  double accumulatedSteamRelease = 0;

  late int tickOffset;
  int ticksSinceLastMailTransfer = 0;
  late List<double> stress;

  // advancements
  String? backwardsDriver;

  /// `new Train(id, owner, graph, carriages, carriageSpacing, doubleEnded, name, icon, mapColorIndex)`;
  /// without [name] and [icon] the train is "unnamed" with the default icon.
  Train(
    this.id,
    this.owner,
    this.graph,
    this.carriages,
    this.carriageSpacing,
    this.doubleEnded,
    this.mapColorIndex, {
    Txt? name,
    TrainIconType? icon,
  }) : name = name ?? Txt.translate('create.train.unnamed'),
       icon = icon ?? TrainIconType.getDefault() {
    stress = List<double>.filled(carriageSpacing.length, 0);
    status = TrainStatus(this);

    for (final c in carriages) {
      c.setTrain(this);
    }

    navigation = Navigation(this);
    runtime = ScheduleRuntime(this);
    manualSteer = SteerDirection.none;
    tickOffset = Create.RANDOM.nextInt(100);
  }

  void earlyTick(TrainLevel level) {
    status.tick(level);
    if (graph == null && migratingPoints.isNotEmpty) reattachToTracks(level);
    if (graph == null) {
      _addToSignalGroups(occupiedSignalBlocks.keys, true);
      return;
    }

    if (updateSignalBlocks) {
      updateSignalBlocks = false;
      collectInitiallyOccupiedSignalBlocks();
    }

    _addToSignalGroups(occupiedSignalBlocks.keys, true);
    _addToSignalGroups(reservedSignalBlocks, false);

    if (occupiedObservers.isEmpty) return;

    _tickOccupiedObservers(level);
  }

  void _tickOccupiedObservers(TrainLevel level) {
    var storageVersion = 0;
    for (final carriage in carriages) {
      storageVersion += carriage.storage.getVersion();
    }

    for (final uuid in occupiedObservers.toList()) {
      final observer = graph!.getPoint(EdgePointType.OBSERVER, uuid);
      if (observer == null) continue;

      final filter = observer.getFilter();
      if (filter.isEmpty()) {
        observer.keepAlive(this);
        continue;
      }

      final cachedMatch = cachedObserverFiltering.putIfAbsent(uuid, () => Pair.of(-1, false));
      var shouldActivate = cachedMatch.getSecond();

      if (cachedMatch.getFirst() == storageVersion) {
        if (shouldActivate) observer.keepAlive(this);
        continue;
      }

      shouldActivate = false;
      for (final carriage in carriages) {
        if (shouldActivate) break;

        for (final item in carriage.storage.getAllItems()) {
          if (shouldActivate) break;
          if (item.isEmpty) continue;
          shouldActivate |= filter.testItem(item.id);
        }

        for (final fluid in carriage.storage.getFluids()) {
          if (shouldActivate) break;
          if (fluid.isEmpty) continue;
          shouldActivate |= filter.testFluid(fluid.id);
        }
      }

      cachedObserverFiltering[uuid] = Pair.of(storageVersion, shouldActivate);

      if (shouldActivate) observer.keepAlive(this);
    }
  }

  /// `addToSignalGroups(groups)`: also drops the ids that no longer name a group.
  void _addToSignalGroups(Iterable<String> groups, bool occupied) {
    final groupMap = Create.RAILWAYS.signalEdgeGroups;
    final gone = <String>[];
    for (final id in groups) {
      final signalEdgeGroup = groupMap[id];
      if (signalEdgeGroup == null) {
        gone.add(id);
      } else {
        signalEdgeGroup.trains.add(this);
      }
    }
    if (gone.isEmpty) return;
    if (occupied) {
      gone.forEach(occupiedSignalBlocks.remove);
    } else {
      gone.forEach(reservedSignalBlocks.remove);
    }
  }

  void tick(TrainLevel level) {
    Create.RAILWAYS.markTracksDirty();

    if (graph == null) {
      for (final c in carriages) {
        c.manageEntities(level);
      }
      _updateConductors();
      return;
    }

    final currentStation = getCurrentStation();
    if (currentStation != null) {
      ticksSinceLastMailTransfer++;
      if (ticksSinceLastMailTransfer > 20) {
        currentStation.runMailTransfer();
        ticksSinceLastMailTransfer = 0;
      }
    }

    _updateConductors();
    runtime.tick(level);
    navigation.tick(level);

    _tickPassiveSlowdown();
    if (derailed) _tickDerailedSlowdown();

    var distance = speed;
    Carriage? previousCarriage;
    final carriageCount = carriages.length;
    var stalled = false;
    double maxStress = 0;

    if (carriageWaitingForChunks != -1) distance = 0;

    for (var i = 0; i < carriageCount; i++) {
      final carriage = carriages[i];
      if (previousCarriage != null) {
        final target = carriageSpacing[i - 1];
        double actual = target.toDouble();

        final leadingPoint = carriage.getLeadingPoint();
        final trailingPoint = previousCarriage.getTrailingPoint();

        var entries = 0;
        double total = 0;

        if (leadingPoint.node1 != null && trailingPoint.node1 != null) {
          final d1 = leadingPoint.node1!.getLocation().dimension;
          final d2 = trailingPoint.node1!.getLocation().dimension;
          for (final b in Iterate.trueAndFalse) {
            final d = b ? d1 : d2;
            if (!b && d1 == d2) continue;
            if (d1 != d2) continue;

            final dimensional = carriage.getDimensionalIfPresent(d);
            final dimensional2 = previousCarriage.getDimensionalIfPresent(d);
            if (dimensional == null || dimensional2 == null) continue;

            final leadingAnchor = dimensional.leadingAnchor();
            final trailingAnchor = dimensional2.trailingAnchor();
            if (leadingAnchor == null || trailingAnchor == null) continue;

            var distanceTo = leadingAnchor.distanceSquaredTo(trailingAnchor);
            if (carriage.leadingBogey().isUpsideDown() != previousCarriage.trailingBogey().isUpsideDown()) {
              distanceTo = math.sqrt(distanceTo - 4);
            } else {
              distanceTo = math.sqrt(distanceTo);
            }
            total += distanceTo;
            entries++;
          }
        }

        if (entries > 0) actual = total / entries;

        stress[i - 1] = target - actual;
        maxStress = math.max(maxStress, (target - actual).abs());
      }

      previousCarriage = carriage;

      if (carriage.stalled) {
        speedBeforeStall ??= speed;
        distance = 0;
        speed = 0;
        stalled = true;
      }
    }

    if (!stalled && speedBeforeStall != null) {
      speed = clampNum(speedBeforeStall!, -1.0, 1.0);
      speedBeforeStall = null;
    }

    // positive stress: carriages should move apart
    // negative stress: carriages should move closer

    final approachingStation = navigation.distanceToDestination < 5;
    final leadingModifier = approachingStation ? 0.75 : 0.5;
    final trailingModifier = approachingStation ? 0.0 : 0.125;

    var blocked = false;
    final iterateFromBack = speed < 0;

    for (var index = 0; index < carriageCount; index++) {
      final i = iterateFromBack ? carriageCount - 1 - index : index;
      final leadingStress = i == 0 ? 0.0 : stress[i - 1] * -(iterateFromBack ? trailingModifier : leadingModifier);
      final trailingStress = i == stress.length ? 0.0 : stress[i] * (iterateFromBack ? leadingModifier : trailingModifier);

      final carriage = carriages[i];

      final toFollowForward = i == 0 ? null : carriages[i - 1].getTrailingPoint();

      final toFollowBackward = i == carriageCount - 1 ? null : carriages[i + 1].getLeadingPoint();

      final totalStress = derailed ? 0.0 : leadingStress + trailingStress;

      final first = i == 0;
      final last = i == carriageCount - 1;
      final carriageType = first
          ? (last ? Carriage.BOTH : Carriage.FIRST)
          : (last ? Carriage.LAST : Carriage.MIDDLE);
      final actualDistance = carriage.travel(
        level,
        graph!,
        distance + totalStress,
        toFollowForward,
        toFollowBackward,
        carriageType,
      );
      blocked |= carriage.blocked || carriage.isOnIncompatibleTrack();

      final onTwoBogeys = carriage.isOnTwoBogeys();
      maxStress = math.max(maxStress, onTwoBogeys ? carriage.bogeySpacing - carriage.getAnchorDiff() : 0);
      maxStress = math.max(maxStress, carriage.leadingBogey().getStress());
      if (onTwoBogeys) maxStress = math.max(maxStress, carriage.trailingBogey().getStress());

      if (index == 0) {
        distance = actualDistance;
        _collideWithOtherTrains(level, carriage);
        backwardsDriver = null;
        if (graph == null) return;
      }
    }

    if (blocked) {
      speed = 0;
      navigation.cancelNavigation();
      runtime.tick(level);
      status.endOfTrack();
    } else if (maxStress > 4) {
      speed = 0;
      navigation.cancelNavigation();
      runtime.tick(level);
      derailed = true;
      status.highStress();
    } else if (speed != 0) {
      status.trackOK();
    }

    _updateNavigationTarget(level, distance);
  }

  IEdgePointListener frontSignalListener() {
    return (distance, couple) {
      final point = couple.getFirst();
      if (point is GlobalStation) {
        final station = point;
        if (!station.canApproachFrom(couple.getSecond().getSecond()) || !identical(navigation.destination, station)) {
          return false;
        }
        speed = 0;
        navigation.distanceToDestination = 0;
        navigation.currentPath.clear();
        arriveAt(navigation.destination!);
        navigation.destination = null;
        return true;
      }

      if (point is TrackObserver) {
        occupiedObservers.add(point.getId());
        return false;
      }

      if (point is! SignalBoundary) return false;
      final signal = point;
      if (navigation.waitingForSignal != null && navigation.waitingForSignal!.getFirst() == signal.getId()) {
        speed = 0;
        navigation.distanceToSignal = 0;
        return true;
      }

      final groupId = signal.getGroup(couple.getSecond().getSecond());
      final signalEdgeGroup = groupId == null ? null : Create.RAILWAYS.signalEdgeGroups[groupId];
      if (signalEdgeGroup == null) return false;

      if ((runtime.getSchedule() == null || runtime.paused) && signalEdgeGroup.isOccupiedUnless(this)) {
        for (final c in carriages) {
          c.forEachPresentEntity((cce) {
            final uuid = cce.getControllingPlayer();
            if (uuid != null) TrainFx.effects.awardAdvancement(uuid, AllAdvancements.redSignal);
          });
        }
      }

      signalEdgeGroup.reserved = signal;
      _occupy(groupId!, signal.id);
      return false;
    };
  }

  void cancelStall() {
    speedBeforeStall = null;
    for (final c in carriages) {
      c.stalled = false;
      c.forEachPresentEntity((cce) => cce.getContraption()?.data.cancelActorStalls());
    }
  }

  bool _occupy(String groupId, String? boundaryId) {
    reservedSignalBlocks.remove(groupId);
    if (boundaryId != null && occupiedSignalBlocks.containsKey(groupId)) {
      if (boundaryId == occupiedSignalBlocks[groupId]) return false;
    }
    final had = occupiedSignalBlocks.containsKey(groupId) && occupiedSignalBlocks[groupId] != null;
    occupiedSignalBlocks[groupId] = boundaryId;
    return !had;
  }

  IEdgePointListener backSignalListener() {
    return (distance, couple) {
      final point = couple.getFirst();
      if (point is TrackObserver) {
        occupiedObservers.remove(point.getId());
        cachedObserverFiltering.remove(point.getId());
        return false;
      }
      if (point is! SignalBoundary) return false;
      final groupId = point.getGroup(couple.getSecond().getFirst());
      occupiedSignalBlocks.remove(groupId);
      return false;
    };
  }

  void _updateNavigationTarget(TrainLevel level, double distance) {
    if (navigation.destination == null) return;

    final blockingSignal = navigation.waitingForSignal;
    var fullRefresh = navigation.distanceToDestination > 100 && navigation.distanceToDestination % 100 > 20;
    var signalRefresh = blockingSignal != null && navigation.distanceToSignal % 50 > 5;
    var partialRefresh = navigation.distanceToDestination < 100 && navigation.distanceToDestination % 50 > 5;

    final toSubstract = navigation.destinationBehindTrain ? -distance : distance;
    final navigatingManually = runtime.paused;

    navigation.distanceToDestination -= toSubstract;
    if (blockingSignal != null) {
      navigation.distanceToSignal -= toSubstract;
      signalRefresh &= navigation.distanceToSignal % 50 < 5;
    }

    fullRefresh &= navigation.distanceToDestination % 100 <= 20;
    partialRefresh &= navigation.distanceToDestination % 50 <= 5;

    if (blockingSignal != null && navigation.ticksWaitingForSignal % 100 == 50) {
      final blockingId = blockingSignal.getFirst();
      final signal = blockingId == null ? null : graph!.getPoint(EdgePointType.SIGNAL, blockingId);
      fullRefresh |= signal != null && signal.types.get(blockingSignal.getSecond()) == SignalType.CROSS_SIGNAL;
    }

    if (signalRefresh) navigation.waitingForSignal = null;
    if (!fullRefresh && !partialRefresh) return;
    if (reservedSignalBlocks.isNotEmpty) return;

    if (!navigatingManually && fullRefresh) {
      final preferredPath = runtime.startCurrentInstruction(level);
      if (preferredPath != null) {
        navigation.startNavigation(preferredPath);
      }
    }
  }

  void _tickDerailedSlowdown() {
    speed = toFloat(speed / 3.0);
    if (mthEqual(speed, 0)) speed = 0;
  }

  void _tickPassiveSlowdown() {
    if (!manualTick && navigation.destination == null && speed != 0) {
      final acceleration = this.acceleration();
      if (speed > 0) {
        speed = math.max(speed - acceleration, 0);
      } else {
        speed = math.min(speed + acceleration, 0);
      }
    }
    manualTick = false;
  }

  void _updateConductors() {
    for (final carriage in carriages) {
      carriage.updateConductors();
    }
  }

  bool hasForwardConductor() {
    for (final carriage in carriages) {
      if (carriage.presentConductors.getFirst()) return true;
    }
    return false;
  }

  bool hasBackwardConductor() {
    for (final carriage in carriages) {
      if (carriage.presentConductors.getSecond()) return true;
    }
    return false;
  }

  void _collideWithOtherTrains(TrainLevel level, Carriage carriage) {
    if (derailed) return;

    final trailingPoint = carriage.getTrailingPoint();
    final leadingPoint = carriage.getLeadingPoint();

    if (leadingPoint.node1 == null ||
        trailingPoint.node1 == null ||
        leadingPoint.edge == null ||
        trailingPoint.edge == null) {
      return;
    }
    final dimension = leadingPoint.node1!.getLocation().dimension;
    if (dimension != trailingPoint.node1!.getLocation().dimension) return;

    final start = (speed < 0 ? trailingPoint : leadingPoint).getPosition(graph);
    final end = (speed < 0 ? leadingPoint : trailingPoint).getPosition(graph);

    final collision = findCollidingTrain(level, start, end, dimension);
    if (collision == null) return;

    final train = collision.getFirst();

    final combinedSpeed = speed.abs() + train.speed.abs();
    if (combinedSpeed > toFloat(.2)) {
      final v = collision.getSecond();
      level.explode(v.$1, v.$2, v.$3, toFloat(math.min(3 * combinedSpeed, 5)));
    }

    crash();
    train.crash();
  }

  Pair<Train, Vec3>? findCollidingTrain(TrainLevel level, Vec3 start, Vec3 end, String dimension) {
    final diff = end - start;
    final maxDistanceSqr = math.pow(TrainSettings.current.maxAssemblyLength, 2.0).toDouble();

    trains:
    for (final train in Create.RAILWAYS.trains.values.toList()) {
      if (identical(train, this)) continue;
      if (train.graph != null && !identical(train.graph, graph)) continue;

      Vec3? lastPoint;

      for (final otherCarriage in train.carriages) {
        for (final betweenBits in Iterate.trueAndFalse) {
          if (betweenBits && lastPoint == null) continue;

          final otherLeading = otherCarriage.getLeadingPoint();
          final otherTrailing = otherCarriage.getTrailingPoint();
          if (otherLeading.edge == null || otherTrailing.edge == null) continue;
          final otherDimension = otherLeading.node1!.getLocation().dimension;
          if (otherDimension != otherTrailing.node1!.getLocation().dimension) continue;
          if (otherDimension != dimension) continue;

          var start2 = otherLeading.getPosition(train.graph);
          var end2 = otherTrailing.getPosition(train.graph);

          if (math.min(start2.distanceSquaredTo(start), end2.distanceSquaredTo(start)) > maxDistanceSqr) {
            continue trains;
          }

          if (betweenBits) {
            end2 = start2;
            start2 = lastPoint!;
          }

          lastPoint = end2;

          if ((end.$2 < end2.$2 - 3 || end2.$2 < end.$2 - 3) && (start.$2 < start2.$2 - 3 || start2.$2 < start.$2 - 3)) {
            continue;
          }

          final diff2 = end2 - start2;
          final normedDiff = diff.normalized;
          final normedDiff2 = diff2.normalized;
          var intersect = VecHelper.intersect(start, start2, normedDiff, normedDiff2, Axis.y);

          if (intersect == null) {
            final intersectSphere = VecHelper.intersectSphere(start2, normedDiff2, start, toFloat(.125));
            if (intersectSphere == null) continue;
            if (!mthEqual(normedDiff2.dot((intersectSphere - start2).normalized), 1)) continue;
            intersect = [
              intersectSphere.distanceTo(start) - .125,
              intersectSphere.distanceTo(start2) - .125,
            ];
          }

          if (intersect[0] > diff.length) continue;
          if (intersect[1] > diff2.length) continue;
          if (intersect[0] < 0) continue;
          if (intersect[1] < 0) continue;

          return Pair.of(train, start + normedDiff * intersect[0]);
        }
      }
    }
    return null;
  }

  void crash() {
    navigation.cancelNavigation();
    if (derailed) return;
    speed = -clampNum(speed, -.5, .5);
    derailed = true;
    graph = null;
    status.crash();

    for (final carriage in carriages) {
      carriage.forEachPresentEntity((e) {
        for (final entity in e.getIndirectPassengers()) {
          if (!entity.isPlayer) continue;
          final controllingPlayer = e.getControllingPlayer();
          if (controllingPlayer != null && controllingPlayer == entity.uuid) continue;
          TrainFx.effects.awardAdvancement(entity.uuid, AllAdvancements.trainCrash);
        }
      });
    }

    if (backwardsDriver != null) {
      TrainFx.effects.awardAdvancement(backwardsDriver!, AllAdvancements.trainCrashBackwards);
    }
  }

  bool disassemble(Direction assemblyDirection, Pos pos) {
    if (!canDisassemble()) return false;

    var offset = 1;
    final backwards = currentlyBackwards;
    String? dimension;

    for (var i = 0; i < carriages.length; i++) {
      final carriage = carriages[backwards ? carriages.length - i - 1 : i];
      final entity = carriage.anyAvailableEntity();
      if (entity == null) return false;
      dimension = entity.dimension;

      entity.getContraption()?.returnStorageForDisassembly(carriage.storage);
      final target = pos
          .relative(assemblyDirection, backwards ? offset + carriage.bogeySpacing : offset)
          .belowBy(carriage.leadingBogey().isUpsideDown() ? 2 : 0);
      entity.setPos(target.toVec3());
      entity.disassemble();

      for (final bogey in carriage.bogeys.toList()) {
        if (bogey == null) continue;
        final bogeyPosition = bogey.getAnchorPosition();
        if (bogeyPosition == null) continue;
        TrainFx.effects.setBogeyData(dimension, posContaining(bogeyPosition), bogey.bogeyData);
      }

      offset += carriage.bogeySpacing;

      if (i < carriageSpacing.length) {
        offset += carriageSpacing[backwards ? carriageSpacing.length - i - 1 : i];
      }
    }

    final currentStation = getCurrentStation();
    if (currentStation != null) {
      currentStation.cancelReservation(this);
      final blockEntityPos = currentStation.getBlockEntityPos();
      if (blockEntityPos != null && dimension != null) {
        TrainFx.effects.noteDisassembledTrain(dimension, blockEntityPos, name.copy(), mapColorIndex);
      }
    }

    Create.RAILWAYS.removeTrain(id);
    TrainFx.effects.sendRemoveTrain(id);
    return true;
  }

  bool canDisassemble() {
    for (final carriage in carriages) {
      if (carriage.presentInMultipleDimensions()) return false;
      final entity = carriage.anyAvailableEntity();
      if (entity == null) return false;
      if (!mthEqual(entity.pitch, 0)) return false;
      if (!mthEqual(((entity.yaw % 90) + 360) % 90, 0)) return false;
    }
    return true;
  }

  bool isTravellingOn(TrackNode node) {
    var affected = false;
    forEachTravellingPoint((tp) {
      if (identical(tp.node1, node) || identical(tp.node2, node)) affected = true;
    });
    return affected;
  }

  void detachFromTracks() {
    migratingPoints.clear();
    navigation.cancelNavigation();
    forEachTravellingPoint((tp) => migratingPoints.add(TrainMigration.fromPoint(tp)));
    graph = null;
  }

  void forEachTravellingPoint(void Function(TravellingPoint) callback) {
    for (final c in carriages) {
      c.leadingBogey().points.forEach(callback);
      if (c.isOnTwoBogeys()) c.trailingBogey().points.forEach(callback);
    }
  }

  void forEachTravellingPointBackwards(void Function(TravellingPoint, double) callback) {
    double lastWheelOffset = 0;
    for (var i = 0; i < carriages.length; i++) {
      final index = carriages.length - i - 1;
      final carriage = carriages[index];
      final trailingBogey = carriage.trailingBogey();
      final trailSpacing = trailingBogey.type.getWheelPointSpacing();

      // trailing point
      callback(trailingBogey.trailing(), i == 0 ? 0 : carriageSpacing[index] - lastWheelOffset - trailSpacing / 2);

      // inside 1st bogey
      callback(trailingBogey.leading(), trailSpacing);

      lastWheelOffset = trailSpacing / 2;

      if (!carriage.isOnTwoBogeys()) continue;

      final leadingBogey = carriage.leadingBogey();
      final leadSpacing = carriage.leadingBogey().type.getWheelPointSpacing();

      // between bogeys
      callback(leadingBogey.trailing(), carriage.bogeySpacing - lastWheelOffset - leadSpacing / 2);

      // inside 2nd bogey
      callback(trailingBogey.leading(), leadSpacing);

      lastWheelOffset = leadSpacing / 2;
    }
  }

  void reattachToTracks(TrainLevel level) {
    if (migrationCooldown > 0) {
      migrationCooldown--;
      return;
    }

    final entrySet = Create.RAILWAYS.trackNetworks.entries.toList();
    final successfulMigrations = <String, List<TrackGraphLocation>>{};
    for (final md in migratingPoints) {
      for (final entry in entrySet.toList()) {
        final gl = md.tryMigratingTo(entry.value);
        if (gl == null) {
          entrySet.remove(entry);
          continue;
        }
        successfulMigrations.putIfAbsent(entry.key, () => []).add(gl);
      }
    }

    if (entrySet.isEmpty) {
      migrationCooldown = 40;
      status.failedMigration();
      derailed = true;
      return;
    }

    for (final entry in entrySet) {
      graph = entry.value;
      final locations = successfulMigrations[entry.key]!;
      forEachTravellingPoint((tp) => tp.migrateTo(locations));
      migratingPoints.clear();
      if (derailed) status.successfulMigration();
      derailed = false;
      if (runtime.getSchedule() != null && runtime.state == State.IN_TRANSIT) runtime.state = State.PRE_TRANSIT;
      final currentStation = getCurrentStation();
      if (currentStation != null) currentStation.reserveFor(this);
      updateSignalBlocks = true;
      migrationCooldown = 0;
      return;
    }
  }

  int getTotalLength() {
    var length = 0;
    for (var i = 0; i < carriages.length; i++) {
      final carriage = carriages[i];
      if (i == 0) length += carriage.leadingBogey().type.getWheelPointSpacing() ~/ 2;
      if (i == carriages.length - 1) length += carriage.trailingBogey().type.getWheelPointSpacing() ~/ 2;

      length += carriage.bogeySpacing;
      if (i < carriageSpacing.length) length += carriageSpacing[i];
    }
    return length;
  }

  void leaveStation() {
    final currentStation = getCurrentStation();
    if (currentStation != null) currentStation.trainDeparted(this);
    this.currentStation = null;
  }

  void arriveAt(GlobalStation station) {
    setCurrentStation(station);
    reservedSignalBlocks.clear();
    runtime.destinationReached();
    station.runMailTransfer();
    ticksSinceLastMailTransfer = 0;
  }

  void setCurrentStation(GlobalStation station) {
    currentStation = station.id;
  }

  GlobalStation? getCurrentStation() {
    if (currentStation == null) return null;
    if (graph == null) return null;
    return graph!.getPoint(EdgePointType.STATION, currentStation!);
  }

  /// `getOwner(level)`: the uuid of the owner when that player is online, else `null`.
  String? getOwner(TrainLevel level) {
    final uuid = owner;
    if (uuid == null) return null;
    return TrainFx.effects.isPlayerOnline(uuid) ? uuid : null;
  }

  void approachTargetSpeed(double accelerationMod) {
    final actualTarget = targetSpeed;
    if (mthEqual(actualTarget, speed)) return;
    if (manualTick) leaveStation();
    final acceleration = this.acceleration();
    if (speed < actualTarget) {
      speed = math.min(speed + acceleration * accelerationMod, actualTarget);
    } else if (speed > actualTarget) {
      speed = math.max(speed - acceleration * accelerationMod, actualTarget);
    }
  }

  void collectInitiallyOccupiedSignalBlocks() {
    final trailingPoint = carriages.last.getTrailingPoint();
    final node1 = trailingPoint.node1;
    final node2 = trailingPoint.node2;
    final edge = trailingPoint.edge;

    if (edge == null) return;

    final position = trailingPoint.position;
    final signalData = edge.getEdgeData();

    occupiedSignalBlocks.clear();
    reservedSignalBlocks.clear();
    occupiedObservers.clear();
    cachedObserverFiltering.clear();

    final signalScout = TravellingPoint.at(node1, node2, edge, position, false);
    final allGroups = Create.RAILWAYS.signalEdgeGroups;
    String? prevGroup;

    if (signalData.hasSignalBoundaries()) {
      final nextBoundary = signalData.next(EdgePointType.SIGNAL, position);
      if (nextBoundary == null) {
        double d = 0;
        SignalBoundary? prev;
        var current = signalData.next(EdgePointType.SIGNAL, 0);
        while (current != null) {
          prev = current;
          d = current.getLocationOn(edge);
          current = signalData.next(EdgePointType.SIGNAL, d);
        }
        if (prev != null) {
          final group = prev.getGroup(node2!);
          if (group != null && allGroups.containsKey(group)) {
            _occupy(group, null);
            prevGroup = group;
          }
        }
      } else {
        final group = nextBoundary.getGroup(node1!);
        if (group != null && allGroups.containsKey(group)) {
          _occupy(group, null);
          prevGroup = group;
        }
      }
    } else {
      final groupId = signalData.getEffectiveEdgeGroupId(graph!);
      if (groupId != null && allGroups.containsKey(groupId)) {
        _occupy(groupId, null);
        prevGroup = groupId;
      }
    }

    forEachTravellingPointBackwards((tp, d) {
      signalScout.travel(graph!, d, signalScout.follow(tp), (distance, couple) {
        final point = couple.getFirst();
        if (point is TrackObserver) {
          occupiedObservers.add(point.getId());
          return false;
        }
        if (point is! SignalBoundary) return false;
        couple.getSecond().map<String?>(point.getGroup).forEach((id) {
          if (id == null) return;
          if (!allGroups.containsKey(id)) return;
          if (id == prevGroup) return;
          _occupy(id, null);
          prevGroup = id;
        });
        return false;
      }, signalScout.ignoreTurns());
    });
  }

  bool shouldCarriageSyncThisTick(int gameTicks, int updateInterval) => (gameTicks + tickOffset) % updateInterval == 0;

  Couple<Couple<TrackNode?>> getEndpointEdges() {
    final pts = Couple.create(carriages.first.getLeadingPoint(), carriages.last.getTrailingPoint());
    return pts.map((tp) => Couple.create<TrackNode?>(tp.node1, tp.node2));
  }

  int getNavigationPenalty() {
    if (manualTick) return Penalties.MANUAL_TRAIN;
    if (runtime.getSchedule() == null || runtime.paused) return Penalties.IDLE_TRAIN;
    if (navigation.waitingForSignal != null && navigation.ticksWaitingForSignal > 0) {
      return Penalties.WAITING_TRAIN + math.min(navigation.ticksWaitingForSignal ~/ 20, 1000);
    }
    if (navigation.destination != null && navigation.distanceToDestination < 50 || navigation.distanceToSignal < 20) {
      return Penalties.ARRIVING_TRAIN;
    }
    return Penalties.ANY_TRAIN;
  }

  void burnFuel() {
    if (fuelTicks > 0) {
      fuelTicks--;
      return;
    }

    final iterateFromBack = speed < 0;
    final carriageCount = carriages.length;

    for (var index = 0; index < carriageCount; index++) {
      final i = iterateFromBack ? carriageCount - 1 - index : index;
      final carriage = carriages[i];
      final burnTime = carriage.storage.extractFuel();
      if (burnTime <= 0) continue;
      fuelTicks += burnTime;
      return;
    }
  }

  double maxSpeed() {
    final t = TrainSettings.current;
    return toFloat(toFloat(fuelTicks > 0 ? t.poweredTrainTopSpeed : t.trainTopSpeed) / 20);
  }

  double maxTurnSpeed() {
    final t = TrainSettings.current;
    return toFloat(toFloat(fuelTicks > 0 ? t.poweredTrainTurningTopSpeed : t.trainTurningTopSpeed) / 20);
  }

  double acceleration() {
    final t = TrainSettings.current;
    return toFloat(toFloat(fuelTicks > 0 ? t.poweredTrainAcceleration : t.trainAcceleration) / 400);
  }

  CTag write(DimensionPalette dimensions) {
    final tag = CTag();
    tag.putUuid('Id', id);
    if (owner != null) tag.putUuid('Owner', owner!);
    if (graph != null) tag.putUuid('Graph', graph!.id);
    tag.putCompoundList('Carriages', [for (final c in carriages) c.write(dimensions)]);
    tag.putIntArray('CarriageSpacing', carriageSpacing);
    tag.putBoolean('DoubleEnded', doubleEnded);
    tag.putDouble('Speed', speed);
    tag.putDouble('Throttle', throttle);
    if (speedBeforeStall != null) tag.putDouble('SpeedBeforeStall', speedBeforeStall!);
    tag.putInt('Fuel', fuelTicks);
    tag.putDouble('TargetSpeed', targetSpeed);
    tag.putString('IconType', icon.id);
    tag.putInt('MapColorIndex', mapColorIndex);
    tag.putString('Name', componentToJson(name));
    if (currentStation != null) tag.putUuid('Station', currentStation!);
    tag.putBoolean('Backwards', currentlyBackwards);
    tag.putBoolean('Derailed', derailed);
    tag.putBoolean('UpdateSignals', updateSignalBlocks);
    tag.putCompoundList('SignalBlocks', [
      for (final e in occupiedSignalBlocks.entries)
        CTag()
          ..putUuid('Id', e.key)
          ..also((c) {
            if (e.value != null) c.putUuid('Boundary', e.value!);
          }),
    ]);
    tag.putCompoundList('ReservedSignalBlocks', [for (final uid in reservedSignalBlocks) CTag()..putUuid('Id', uid)]);
    tag.putCompoundList('OccupiedObservers', [for (final uid in occupiedObservers) CTag()..putUuid('Id', uid)]);
    tag.putCompoundList('MigratingPoints', [for (final tm in migratingPoints) tm.write(dimensions)]);

    tag.putCompound('Runtime', runtime.write());
    tag.putCompound('Navigation', navigation.write(dimensions));

    return tag;
  }

  static Train read(CTag tag, Map<String, TrackGraph> trackNetworks, DimensionPalette dimensions) {
    final id = tag.getUuid('Id')!;
    final owner = tag.getUuid('Owner');
    final graphId = tag.getUuid('Graph');
    final graph = graphId == null ? null : trackNetworks[graphId];
    final carriages = <Carriage>[];
    for (final c in tag.getCompoundList('Carriages')) {
      carriages.add(Carriage.read(c, graph, dimensions));
    }
    final carriageSpacing = <int>[...tag.getIntArray('CarriageSpacing')];
    final doubleEnded = tag.getBoolean('DoubleEnded');
    final mapColorIndex = tag.getInt('MapColorIndex');

    final train = Train(id, owner, graph, carriages, carriageSpacing, doubleEnded, mapColorIndex);

    train.speed = tag.getDouble('Speed');
    train.throttle = tag.getDouble('Throttle');
    if (tag.contains('SpeedBeforeStall')) train.speedBeforeStall = tag.getDouble('SpeedBeforeStall');
    train.targetSpeed = tag.getDouble('TargetSpeed');
    train.icon = TrainIconType.byId(tag.getString('IconType'));
    train.name = componentFromJson(tag.getString('Name'));
    train.currentStation = tag.getUuid('Station');
    train.currentlyBackwards = tag.getBoolean('Backwards');
    train.derailed = tag.getBoolean('Derailed');
    train.updateSignalBlocks = tag.getBoolean('UpdateSignals');
    train.fuelTicks = tag.getInt('Fuel');

    for (final c in tag.getCompoundList('SignalBlocks')) {
      final key = c.getUuid('Id');
      if (key != null) train.occupiedSignalBlocks[key] = c.getUuid('Boundary');
    }
    for (final c in tag.getCompoundList('ReservedSignalBlocks')) {
      final key = c.getUuid('Id');
      if (key != null) train.reservedSignalBlocks.add(key);
    }
    for (final c in tag.getCompoundList('OccupiedObservers')) {
      final key = c.getUuid('Id');
      if (key != null) train.occupiedObservers.add(key);
    }
    for (final c in tag.getCompoundList('MigratingPoints')) {
      train.migratingPoints.add(TrainMigration.read(c, dimensions));
    }

    train.runtime.read(tag.getCompound('Runtime'));
    train.navigation.read(tag.getCompound('Navigation'), graph, dimensions);

    train.getCurrentStation()?.reserveFor(train);

    return train;
  }

  int countPlayerPassengers() {
    var count = 0;
    for (final carriage in carriages) {
      carriage.forEachPresentEntity((e) {
        for (final p in e.getIndirectPassengers()) {
          if (p.isPlayer) count++;
        }
      });
    }
    return count;
  }

  void determineHonk(TrainLevel level) {
    if (lowHonk != null) return;
    for (final carriage in carriages) {
      final dimensional = carriage.getDimensionalIfPresent(level.dimension);
      if (dimensional == null) return;
      final entity = dimensional.entity;
      final cc = entity?.getContraption();
      if (entity == null || cc == null) break;
      final first = cc.soundQueue.getFirstWhistle(entity);
      if (first != null) {
        lowHonk = first.getFirst();
        honkPitch = first.getSecond();
      }
    }
  }

  double distanceToLocationSqr(TrainLevel level, Vec3 location) {
    var distance = 3.4028234663852886e+38;
    for (final carriage in carriages) {
      final dce = carriage.getDimensionalIfPresent(level.dimension);
      if (dce == null || dce.positionAnchor == null) continue;
      distance = math.min(distance, toFloat(dce.positionAnchor!.distanceSquaredTo(location)));
    }
    return distance;
  }

  List<String> getPresentDimensions() {
    final out = <String>[];
    for (final carriage in carriages) {
      for (final d in carriage.getPresentDimensions()) {
        if (!out.contains(d)) out.add(d);
      }
    }
    return out;
  }

  Pos? getPositionInDimension(String dimension) {
    for (final carriage in carriages) {
      final p = carriage.getPositionInDimension(dimension);
      if (p != null) return p;
    }
    return null;
  }
}

/// `Train.Penalties`.
class Penalties {
  static const int STATION = 50, STATION_WITH_TRAIN = 300;
  static const int MANUAL_TRAIN = 200,
      IDLE_TRAIN = 700,
      ARRIVING_TRAIN = 50,
      WAITING_TRAIN = 50,
      ANY_TRAIN = 25,
      RED_SIGNAL = 25,
      REDSTONE_RED_SIGNAL = 400;
}

extension _Also<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}
