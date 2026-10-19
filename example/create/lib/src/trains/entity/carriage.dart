// `Carriage` (pure): one carriage of a train. It has one or two bogeys (the wheel points moving
// on the track graph), the cargo, and per dimension the entity that shows it
// ([DimensionalCarriageEntity]); a carriage crossing a portal is present in two dimensions.
import 'dart:math' as math;

import '../../common/data.dart';
import '../../common/direction.dart' show toFloat, clampNum;
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../../content/advancement_ids.dart';
import '../graph/dimension_palette.dart';
import '../graph/track_graph.dart';
import '../graph/track_node_location.dart';
import '../util/ctag.dart';
import 'carriage_bogey.dart';
import 'carriage_contraption.dart';
import 'carriage_contraption_entity.dart';
import 'carriage_entity_handler.dart';
import 'carriage_entity_host.dart';
import 'carriage_storage.dart';
import 'train.dart';
import 'train_level.dart';
import 'travelling_point.dart';

class Carriage {
  static int netIdGenerator = 0;

  static const int FIRST = 0, MIDDLE = 1, LAST = 2, BOTH = 3;

  Train? train;
  int id;
  bool blocked = false;
  bool stalled = false;
  Couple<bool> presentConductors;

  int bogeySpacing;
  Couple<CarriageBogey?> bogeys;

  CarriageStorage? _storage;

  /// `storage` (`TrainCargoManager`). While the cargo lives in the contraption (between
  /// `setContraption` and `swapStorageAfterAssembly`) there is none: see [hasStorage].
  CarriageStorage get storage => _storage ??= (storageFactory?.call() ?? EmptyCarriageStorage());

  set storage(CarriageStorage? value) => _storage = value;

  bool get hasStorage => _storage != null;

  CTag serialisedEntity;
  final Map<int, CTag> serialisedPassengers = {};

  final Map<String, DimensionalCarriageEntity> _entities = {};

  /// `storage` of a fresh carriage (`new TrainCargoManager()`), provided by the contraptions side.
  static CarriageStorage Function()? storageFactory;

  Carriage(CarriageBogey bogey1, CarriageBogey? bogey2, this.bogeySpacing)
    : bogeys = Couple.create<CarriageBogey?>(bogey1, bogey2),
      id = ++netIdGenerator,
      serialisedEntity = CTag(),
      presentConductors = Couple.create(false, false) {
    _storage = storageFactory?.call() ?? EmptyCarriageStorage();
    portalScout = TravellingPoint();
    bogey1.setLeading();
    bogey1.carriage = this;
    if (bogey2 != null) bogey2.carriage = this;
  }

  late final TravellingPoint portalScout;

  bool isOnIncompatibleTrack() =>
      leadingBogey().type.isOnIncompatibleTrack(this, true) || trailingBogey().type.isOnIncompatibleTrack(this, false);

  void setTrain(Train train) {
    this.train = train;
  }

  bool presentInMultipleDimensions() => _entities.length > 1;

  List<String> getPresentDimensions() => _entities.keys.toSet().toList();

  /// `getPositionInDimension(dimension)`: the block the carriage entity is at in [dimension].
  Pos? getPositionInDimension(String dimension) {
    final dce = _entities[dimension];
    final anchor = dce?.positionAnchor;
    return anchor == null ? null : posContaining(anchor);
  }

  void setContraption(TrainLevel level, CarriageContraption contraption) {
    _storage = null;
    final entity = CarriageEntities.factory!.create(level, contraption);
    entity.setCarriage(this);
    contraption.data.startMoving(level);
    contraption.data.onEntityInitialize(level, entity);
    updateContraptionAnchors();

    final dimensional = getDimensional(level.dimension);
    dimensional.alignEntity(entity);
    dimensional.removeAndSaveEntity(entity, true);
  }

  /// `getDimensional(level)` / `getDimensional(dimension)`.
  DimensionalCarriageEntity getDimensional(String dimension) =>
      _entities.putIfAbsent(dimension, () => DimensionalCarriageEntity(this));

  DimensionalCarriageEntity? getDimensionalIfPresent(String dimension) => _entities[dimension];

  /// The dimensional entities (`entities.values()`).
  Iterable<DimensionalCarriageEntity> get dimensionalEntities => _entities.values;

  double travel(
    TrainLevel level,
    TrackGraph graph,
    double distance,
    TravellingPoint? toFollowForward,
    TravellingPoint? toFollowBackward,
    int type,
  ) {
    final train = this.train!;
    ITrackSelector Function(TravellingPoint) forwardControl = toFollowForward == null
        ? train.navigation.control
        : (mp) => mp.follow(toFollowForward);
    ITrackSelector Function(TravellingPoint) backwardControl = toFollowBackward == null
        ? train.navigation.control
        : (mp) => mp.follow(toFollowBackward);

    final onTwoBogeys = isOnTwoBogeys();
    final stress = train.derailed ? 0.0 : (onTwoBogeys ? bogeySpacing - getAnchorDiff() : 0.0);
    blocked = false;

    var distanceMoved = distance;
    final iterateFromBack = distance < 0;

    for (final firstBogey in Iterate.trueAndFalse) {
      if (!firstBogey && !onTwoBogeys) continue;

      final actuallyFirstBogey = !onTwoBogeys || (firstBogey ^ iterateFromBack);
      final bogey = bogeys.get(actuallyFirstBogey)!;
      final bogeyCorrection = stress * (actuallyFirstBogey ? 0.5 : -0.5);
      final bogeyStress = bogey.getStress();

      for (final firstWheel in Iterate.trueAndFalse) {
        final actuallyFirstWheel = firstWheel ^ iterateFromBack;
        final point = bogey.points.get(actuallyFirstWheel);
        final prevPoint = !actuallyFirstWheel
            ? bogey.points.getFirst()
            : (!actuallyFirstBogey && onTwoBogeys ? bogeys.getFirst()!.points.getSecond() : null);
        final nextPoint = actuallyFirstWheel
            ? bogey.points.getSecond()
            : (actuallyFirstBogey && onTwoBogeys ? bogeys.getSecond()!.points.getFirst() : null);

        final correction = bogeyStress * (actuallyFirstWheel ? 0.5 : -0.5);
        var toMove = distanceMoved;

        final frontTrackSelector = prevPoint == null ? forwardControl(point) : point.follow(prevPoint);
        final backTrackSelector = nextPoint == null ? backwardControl(point) : point.follow(nextPoint);

        final atFront = (type == FIRST || type == BOTH) && actuallyFirstWheel && actuallyFirstBogey;
        final atBack = (type == LAST || type == BOTH) && !actuallyFirstWheel && (!actuallyFirstBogey || !onTwoBogeys);

        final frontListener = train.frontSignalListener();
        final backListener = train.backSignalListener();
        final passiveListener = point.ignoreEdgePoints();

        toMove += correction + bogeyCorrection;

        final trackSelector = toMove > 0 ? frontTrackSelector : backTrackSelector;
        final signalListener = toMove > 0
            ? (atFront ? frontListener : (atBack ? backListener : passiveListener))
            : (atFront ? backListener : (atBack ? frontListener : passiveListener));

        final moved = point.travel(graph, toMove, trackSelector, signalListener, point.ignoreTurns(), (c) {
          for (final dce in _entities.values) {
            if (dce.pivot != null && c.either((tnl) => tnl.equalsIgnoreDim(dce.pivot!))) return false;
          }
          if (_entities.length > 1) {
            train.status.doublePortal();
            return true;
          }
          return false;
        });

        blocked |= point.blocked;

        distanceMoved = moved;
      }
    }

    updateContraptionAnchors();
    manageEntities(level);
    return distanceMoved;
  }

  double getAnchorDiff() {
    var diff = 0.0;
    var entries = 0;

    final leadingPoint = getLeadingPoint();
    final trailingPoint = getTrailingPoint();
    if (leadingPoint.node1 != null && trailingPoint.node1 != null) {
      if (leadingPoint.node1!.getLocation().dimension != trailingPoint.node1!.getLocation().dimension) {
        return bogeySpacing.toDouble();
      }
    }

    for (final dce in _entities.values) {
      final leading = dce.leadingAnchor();
      final trailing = dce.trailingAnchor();
      if (leading != null && trailing != null) {
        entries++;
        diff += leading.distanceTo(trailing);
      }
    }

    if (entries == 0) return bogeySpacing.toDouble();
    return diff / entries;
  }

  void updateConductors() {
    if (anyAvailableEntity() == null || _entities.length > 1 || serialisedPassengers.isNotEmpty) return;
    presentConductors.replace((_) => false);
    for (final dimensionalCarriageEntity in _entities.values) {
      final entity = dimensionalCarriageEntity.entity;
      if (entity != null && entity.isAlive) {
        presentConductors.replaceWithParams((current, checked) => current || checked, entity.checkConductors());
      }
    }
  }

  final Set<String> _currentlyTraversedDimensions = {};

  void manageEntities(TrainLevel level) {
    _currentlyTraversedDimensions.clear();

    bogeys.forEach((cb) {
      if (cb == null) return;
      cb.points.forEach((tp) {
        if (tp.node1 == null) return;
        _currentlyTraversedDimensions.add(tp.node1!.getLocation().dimension);
      });
    });

    for (final key in _entities.keys.toList()) {
      final dimensionalCarriageEntity = _entities[key]!;
      var discard = _currentlyTraversedDimensions.isNotEmpty && !_currentlyTraversedDimensions.contains(key);

      final currentLevel = level.levelOf(key);
      if (currentLevel == null) continue;

      var entity = dimensionalCarriageEntity.entity;

      if (entity == null) {
        if (discard) {
          _entities.remove(key);
        } else if (dimensionalCarriageEntity.positionAnchor != null &&
            currentLevel.isActiveChunk(posContaining(dimensionalCarriageEntity.positionAnchor!))) {
          dimensionalCarriageEntity.createEntity(currentLevel, anyAvailableEntity() == null);
        }
      } else {
        if (discard) {
          discard = dimensionalCarriageEntity.discardTicks > 3;
          dimensionalCarriageEntity.discardTicks++;
        } else {
          dimensionalCarriageEntity.discardTicks = 0;
        }

        CarriageEntityHandler.validateCarriageEntity(entity);
        if (!entity.isAlive || entity.leftTickingChunks || discard) {
          dimensionalCarriageEntity.removeAndSaveEntity(entity, discard);
          if (discard) _entities.remove(key);
          continue;
        }
      }

      entity = dimensionalCarriageEntity.entity;
      if (entity != null && dimensionalCarriageEntity.positionAnchor != null) {
        dimensionalCarriageEntity.alignEntity(entity);
        entity.syncCarriage();
      }
    }
  }

  void updateContraptionAnchors() {
    final leadingBogey = this.leadingBogey();
    if (leadingBogey.points.either((t) => t.edge == null)) return;
    final trailingBogey = this.trailingBogey();
    if (trailingBogey.points.either((t) => t.edge == null)) return;

    final train = this.train!;
    final leadingBogeyDim = leadingBogey.getDimension();
    final trailingBogeyDim = trailingBogey.getDimension();
    final leadingWheelSpacing = leadingBogey.type.getWheelPointSpacing();
    final trailingWheelSpacing = trailingBogey.type.getWheelPointSpacing();

    final leadingUpsideDown = leadingBogey.isUpsideDown();
    final trailingUpsideDown = trailingBogey.isUpsideDown();

    for (final leading in Iterate.trueAndFalse) {
      final point = leading ? getLeadingPoint() : getTrailingPoint();
      final otherPoint = !leading ? getLeadingPoint() : getTrailingPoint();
      final dimension = point.node1!.getLocation().dimension;
      final otherDimension = otherPoint.node1!.getLocation().dimension;

      if (dimension == otherDimension && leading) {
        getDimensional(dimension).discardPivot();
        continue;
      }

      final dce = getDimensional(dimension);

      dce.positionAnchor = dimension == leadingBogeyDim
          ? leadingBogey.getAnchorPosition()
          : _pivoted(
              dce,
              dimension,
              point,
              leading ? leadingWheelSpacing / 2 : bogeySpacing + trailingWheelSpacing / 2,
              leadingUpsideDown,
              trailingUpsideDown,
            );

      final backAnchorFlip = trailingBogey.isUpsideDown() ^ leadingBogey.isUpsideDown();

      if (isOnTwoBogeys()) {
        dce.rotationAnchors.setFirst(
          dimension == leadingBogeyDim
              ? leadingBogey.getAnchorPosition()
              : _pivoted(
                  dce,
                  dimension,
                  point,
                  leading ? leadingWheelSpacing / 2 : bogeySpacing + trailingWheelSpacing / 2,
                  leadingUpsideDown,
                  trailingUpsideDown,
                ),
        );
        dce.rotationAnchors.setSecond(
          dimension == trailingBogeyDim
              ? trailingBogey.getAnchorPosition(backAnchorFlip)
              : _pivoted(
                  dce,
                  dimension,
                  point,
                  leading ? leadingWheelSpacing / 2 + bogeySpacing : trailingWheelSpacing / 2,
                  leadingUpsideDown,
                  trailingUpsideDown,
                ),
        );
      } else {
        if (dimension == otherDimension) {
          dce.rotationAnchors = Couple.create<Vec3?>(
            leadingBogey.points.getFirst().getPosition(train.graph),
            leadingBogey.points.getSecond().getPosition(train.graph),
          );
        } else {
          dce.rotationAnchors.setFirst(
            identical(leadingBogey.points.getFirst(), point)
                ? point.getPosition(train.graph)
                : _pivoted(dce, dimension, point, leadingWheelSpacing, leadingUpsideDown, trailingUpsideDown),
          );
          dce.rotationAnchors.setSecond(
            identical(leadingBogey.points.getSecond(), point)
                ? point.getPosition(train.graph)
                : _pivoted(dce, dimension, point, leadingWheelSpacing, leadingUpsideDown, trailingUpsideDown),
          );
        }
      }

      final prevmin = dce.minAllowedLocalCoord();
      final prevmax = dce.maxAllowedLocalCoord();

      dce.updateCutoff(leading);

      if (prevmin != dce.minAllowedLocalCoord() || prevmax != dce.maxAllowedLocalCoord()) {
        dce.updateRenderedCutoff();
        dce.updatePassengerLoadout();
      }
    }
  }

  Vec3? _pivoted(
    DimensionalCarriageEntity dce,
    String dimension,
    TravellingPoint start,
    double offset,
    bool leadingUpsideDown,
    bool trailingUpsideDown,
  ) {
    final train = this.train!;
    if (train.graph == null) return dce.pivot?.getLocation();
    final pivot = dce.findPivot(dimension, identical(start, getLeadingPoint()));
    if (pivot == null) return null;
    final flipped = !identical(start, getLeadingPoint()) && (leadingUpsideDown != trailingUpsideDown);
    final startVec = start.getPosition(train.graph, flipped);
    final portalVec = pivot.getLocation() + (0.0, leadingUpsideDown ? -1.0 : 1.0, 0.0);
    return VecHelper.lerp(toFloat(offset / startVec.distanceTo(portalVec)), startVec, portalVec);
  }

  void alignEntity(TrainLevel level) {
    final dimensionalCarriageEntity = _entities[level.dimension];
    if (dimensionalCarriageEntity != null) {
      final entity = dimensionalCarriageEntity.entity;
      if (entity != null) dimensionalCarriageEntity.alignEntity(entity);
    }
  }

  TravellingPoint getLeadingPoint() => leadingBogey().leading();

  TravellingPoint getTrailingPoint() => trailingBogey().trailing();

  CarriageBogey leadingBogey() => bogeys.getFirst()!;

  CarriageBogey trailingBogey() => isOnTwoBogeys() ? bogeys.getSecond()! : leadingBogey();

  bool isOnTwoBogeys() => bogeys.getSecond() != null;

  CarriageContraptionEntity? anyAvailableEntity() {
    for (final dimensionalCarriageEntity in _entities.values) {
      final entity = dimensionalCarriageEntity.entity;
      if (entity != null) return entity;
    }
    return null;
  }

  Pair<String, DimensionalCarriageEntity>? anyAvailableDimensionalCarriage() {
    for (final entry in _entities.entries) {
      if (entry.value.entity != null) return Pair.of(entry.key, entry.value);
    }
    return null;
  }

  void forEachPresentEntity(void Function(CarriageContraptionEntity) callback) {
    for (final dimensionalCarriageEntity in _entities.values.toList()) {
      final entity = dimensionalCarriageEntity.entity;
      if (entity != null) callback(entity);
    }
  }

  CTag write(DimensionPalette dimensions) {
    final tag = CTag();
    tag.putCompound('FirstBogey', bogeys.getFirst()!.write(dimensions));
    if (isOnTwoBogeys()) tag.putCompound('SecondBogey', bogeys.getSecond()!.write(dimensions));
    tag.putInt('Spacing', bogeySpacing);
    tag.putBoolean('FrontConductor', presentConductors.getFirst());
    tag.putBoolean('BackConductor', presentConductors.getSecond());
    tag.putBoolean('Stalled', stalled);

    final passengerMap = <int, CTag>{};

    for (final dimensionalCarriageEntity in _entities.values) {
      final entity = dimensionalCarriageEntity.entity;
      if (entity == null) continue;
      _serialize(entity);
      final contraption = entity.getContraption();
      if (contraption == null) continue;
      final mapping = contraption.data.getSeatMapping();
      for (final passenger in entity.getPassengers()) {
        if (mapping.containsKey(passenger.uuid)) {
          final data = passenger.saveAsPassenger();
          if (data != null) passengerMap[mapping[passenger.uuid]!] = data;
        }
      }
    }

    tag.putCompound('Entity', serialisedEntity.copy());

    final passengerTag = CTag();
    passengerMap.addAll(serialisedPassengers);
    passengerMap.forEach((seat, nbt) => passengerTag.putCompound('Seat$seat', nbt.copy()));
    tag.putCompound('Passengers', passengerTag);

    tag.putCompoundList('EntityPositioning', [
      for (final e in _entities.entries)
        e.value.write()..putInt('Dim', dimensions.encode(e.key)),
    ]);

    return tag;
  }

  void _serialize(CarriageContraptionEntity entity) {
    final data = entity.saveAsPassenger();
    serialisedEntity = data ?? CTag();
    serialisedEntity.remove('Passengers');
    serialisedEntity.getCompound('Contraption').remove('Passengers');
  }

  static Carriage read(CTag tag, TrackGraph? graph, DimensionPalette dimensions) {
    final bogey1 = CarriageBogey.read(tag.getCompound('FirstBogey'), graph, dimensions);
    final bogey2 = tag.contains('SecondBogey') ? CarriageBogey.read(tag.getCompound('SecondBogey'), graph, dimensions) : null;

    final carriage = Carriage(bogey1, bogey2, tag.getInt('Spacing'));

    carriage.stalled = tag.getBoolean('Stalled');
    carriage.presentConductors = Couple.create(tag.getBoolean('FrontConductor'), tag.getBoolean('BackConductor'));
    carriage.serialisedEntity = tag.getCompound('Entity').copy();

    for (final c in tag.getCompoundList('EntityPositioning')) {
      carriage.getDimensional(dimensions.decode(c.getInt('Dim'))).read(c);
    }

    final passengersTag = tag.getCompound('Passengers');
    for (final key in passengersTag.keys.toList()) {
      carriage.serialisedPassengers[int.parse(key.substring(4))] = passengersTag.getCompound(key);
    }

    return carriage;
  }
}

/// `Carriage.DimensionalCarriageEntity`: the carriage in one dimension - its anchors, the portal
/// pivot and the entity (when loaded).
class DimensionalCarriageEntity {
  final Carriage carriage;

  Vec3? positionAnchor;
  Couple<Vec3?> rotationAnchors = Couple.create<Vec3?>(null, null);
  CarriageContraptionEntity? entity;

  TrackNodeLocation? pivot;
  int discardTicks = 0;

  // 0 == whole, 0..1 = fading out, -1..0 = fading in
  double cutoff = 0;

  // client
  bool pointsInitialised = false;

  DimensionalCarriageEntity(this.carriage);

  Train get _train => carriage.train!;

  void discardPivot() {
    final prevmin = minAllowedLocalCoord();
    final prevmax = maxAllowedLocalCoord();

    cutoff = 0;
    pivot = null;

    if ((carriage.serialisedPassengers.isNotEmpty && entity != null) ||
        prevmin != minAllowedLocalCoord() ||
        prevmax != maxAllowedLocalCoord()) {
      updatePassengerLoadout();
      updateRenderedCutoff();
    }
  }

  void updateCutoff(bool leadingIsCurrent) {
    var leadingAnchor = rotationAnchors.getFirst();
    var trailingAnchor = rotationAnchors.getSecond();

    if (leadingAnchor == null || trailingAnchor == null) return;
    if (pivot == null) {
      cutoff = 0;
      return;
    }

    final pivotLoc = pivot!.getLocation() + (0.0, 1.0, 0.0);

    final leadingSpacing = carriage.leadingBogey().type.getWheelPointSpacing() / 2;
    final trailingSpacing = carriage.trailingBogey().type.getWheelPointSpacing() / 2;
    final anchorSpacing = leadingSpacing + carriage.bogeySpacing + trailingSpacing;

    if (carriage.isOnTwoBogeys()) {
      final diff = (trailingAnchor - leadingAnchor).normalized;
      trailingAnchor = trailingAnchor + diff * trailingSpacing;
      leadingAnchor = leadingAnchor + diff * -leadingSpacing;
    }

    var leadingDiff = leadingAnchor.distanceTo(pivotLoc);
    var trailingDiff = trailingAnchor.distanceTo(pivotLoc);

    leadingDiff /= anchorSpacing;
    trailingDiff /= anchorSpacing;

    if (leadingIsCurrent && leadingDiff > trailingDiff && leadingDiff > 1) {
      cutoff = 0;
    } else if (leadingIsCurrent && leadingDiff < trailingDiff && trailingDiff > 1) {
      cutoff = 1;
    } else if (!leadingIsCurrent && leadingDiff > trailingDiff && leadingDiff > 1) {
      cutoff = -1;
    } else if (!leadingIsCurrent && leadingDiff < trailingDiff && trailingDiff > 1) {
      cutoff = 0;
    } else {
      cutoff = toFloat(clampNum(1 - (leadingIsCurrent ? leadingDiff : trailingDiff), 0.0, 1.0) * (leadingIsCurrent ? 1 : -1));
    }
  }

  TrackNodeLocation? findPivot(String dimension, bool leading) {
    if (pivot != null) return pivot;

    final start = leading ? carriage.getLeadingPoint() : carriage.getTrailingPoint();
    final end = !leading ? carriage.getLeadingPoint() : carriage.getTrailingPoint();

    final portalScout = carriage.portalScout;
    portalScout.node1 = start.node1;
    portalScout.node2 = start.node2;
    portalScout.edge = start.edge;
    portalScout.position = start.position;

    final trackSelector = portalScout.follow(end);
    final distance = carriage.bogeySpacing + 10;
    final direction = leading ? -1 : 1;

    portalScout.travel(
      _train.graph!,
      (direction * distance).toDouble(),
      trackSelector,
      portalScout.ignoreEdgePoints(),
      portalScout.ignoreTurns(),
      (nodes) {
        for (final b in Iterate.trueAndFalse) {
          if (nodes.get(b).dimension == dimension) pivot = nodes.get(b);
        }
        return true;
      },
    );

    return pivot;
  }

  CTag write() {
    final tag = CTag();
    tag.putFloat('Cutoff', cutoff);
    tag.putInt('DiscardTicks', discardTicks);
    if (carriage.hasStorage) carriage.storage.write(tag, false);
    if (pivot != null) tag.putCompound('Pivot', pivot!.write(null));
    if (positionAnchor != null) tag.putVec3('PositionAnchor', positionAnchor!);
    if (rotationAnchors.both((v) => v != null)) {
      tag.putCompoundList('RotationAnchors', [
        for (final v in rotationAnchors.toList())
          CTag()
            ..putDouble('X', v!.$1)
            ..putDouble('Y', v.$2)
            ..putDouble('Z', v.$3),
      ]);
    }
    return tag;
  }

  void read(CTag tag) {
    cutoff = tag.getFloat('Cutoff');
    discardTicks = tag.getInt('DiscardTicks');
    if (carriage.hasStorage) carriage.storage.read(tag, false);
    if (tag.contains('Pivot')) pivot = TrackNodeLocation.read(tag.getCompound('Pivot'), null);
    if (positionAnchor != null) return;
    if (tag.contains('PositionAnchor')) positionAnchor = tag.getVec3('PositionAnchor');
    if (tag.contains('RotationAnchors')) {
      final list = tag.getCompoundList('RotationAnchors');
      Vec3 readV(CTag c) => (c.getDouble('X'), c.getDouble('Y'), c.getDouble('Z'));
      rotationAnchors = Couple.create<Vec3?>(
        list.isNotEmpty ? readV(list[0]) : null,
        list.length > 1 ? readV(list[1]) : null,
      );
    }
  }

  Vec3? leadingAnchor() => carriage.isOnTwoBogeys() ? rotationAnchors.getFirst() : positionAnchor;

  Vec3? trailingAnchor() => carriage.isOnTwoBogeys() ? rotationAnchors.getSecond() : positionAnchor;

  static const int _intMin = -0x80000000;
  static const int _intMax = 0x7fffffff;

  int minAllowedLocalCoord() {
    if (cutoff <= 0) return _intMin;
    if (cutoff >= 1) return _intMax;
    final bogeySpacing = carriage.bogeySpacing;
    return (-bogeySpacing + -1 + (2 + bogeySpacing) * cutoff).floor();
  }

  int maxAllowedLocalCoord() {
    if (cutoff >= 0) return _intMax;
    if (cutoff <= -1) return _intMin;
    final bogeySpacing = carriage.bogeySpacing;
    return (-bogeySpacing + -1 + (2 + bogeySpacing) * (cutoff + 1)).ceil();
  }

  void updatePassengerLoadout() {
    final cce = entity;
    if (cce == null) return;

    final loadedPassengers = <int>{};
    final min = minAllowedLocalCoord();
    final max = maxAllowedLocalCoord();
    final contraption = cce.getContraption();
    if (contraption == null) return;

    for (final entry in carriage.serialisedPassengers.entries.toList()) {
      final seatId = entry.key;
      final seats = contraption.data.getSeats();
      if (seatId >= seats.length) continue;

      final localPos = seats[seatId];
      if (!cce.isLocalCoordWithin(localPos, min, max)) continue;

      final tag = entry.value;
      CarriagePassenger? passenger;

      if (tag.contains('PlayerPassenger')) {
        final uuid = tag.getUuid('PlayerPassenger');
        passenger = uuid == null ? null : cce.host.findPlayer(uuid);
      } else {
        passenger = cce.host.loadPassenger(tag, positionAnchor ?? cce.position);
      }

      if (passenger != null) {
        if (passenger.dimension != cce.dimension && passenger.isPlayer) continue;
        cce.addSittingPassenger(passenger, seatId);
      }

      loadedPassengers.add(seatId);
    }

    loadedPassengers.forEach(carriage.serialisedPassengers.remove);

    final mapping = contraption.data.getSeatMapping();
    for (final passenger in cce.getPassengers()) {
      final localPos = contraption.data.getSeatOf(passenger.uuid);
      if (localPos == null) continue;
      if (cce.isLocalCoordWithin(localPos, min, max)) continue;
      if (!mapping.containsKey(passenger.uuid)) continue;

      final seat = mapping[passenger.uuid]!;
      if (passenger.isPlayer) {
        _dismountPlayer(passenger, seat, true);
        continue;
      }

      final passengerData = passenger.saveAsPassenger();
      if (passengerData != null) carriage.serialisedPassengers[seat] = passengerData;
      passenger.discard();
    }
  }

  void _dismountPlayer(CarriagePassenger sp, int seat, bool capture) {
    if (!capture) {
      sp.stopRiding();
      return;
    }

    final tag = CTag();
    tag.putUuid('PlayerPassenger', sp.uuid);
    carriage.serialisedPassengers[seat] = tag;
    sp.stopRiding();

    for (final other in carriage._entities.entries) {
      final otherDce = other.value;
      if (identical(otherDce, this)) continue;
      if (sp.dimension == other.key) continue;
      final loc = otherDce.pivot == null ? otherDce.positionAnchor : otherDce.pivot!.getLocation();
      if (loc == null) continue;
      sp.teleportThroughPortal(other.key, loc);
      TrainFx.effects.awardAdvancement(sp.uuid, AllAdvancements.trainPortal);
    }
  }

  void updateRenderedCutoff() {
    final cce = entity;
    if (cce == null) return;
    final cc = cce.getContraption();
    if (cc == null) return;
    cc.portalCutoffMin = minAllowedLocalCoord();
    cc.portalCutoffMax = maxAllowedLocalCoord();
  }

  void createEntity(TrainLevel level, bool loadPassengers) {
    if (positionAnchor != null) carriage.serialisedEntity.putVec3('Pos', positionAnchor!);
    final created = CarriageEntities.factory?.spawnFromSaved(level, carriage.serialisedEntity, positionAnchor);

    if (created == null) {
      _train.invalid = true;
      return;
    }

    if (positionAnchor != null) created.setPos(positionAnchor!);
    entity = created;

    created.setCarriage(carriage);
    created.syncCarriage();

    updatePassengerLoadout();
  }

  void removeAndSaveEntity(CarriageContraptionEntity entity, bool portal) {
    final contraption = entity.getContraption();
    if (contraption != null) {
      final mapping = contraption.data.getSeatMapping();
      for (final passenger in entity.getPassengers()) {
        if (!mapping.containsKey(passenger.uuid)) continue;

        final seat = mapping[passenger.uuid]!;

        if (passenger.isPlayer) {
          _dismountPlayer(passenger, seat, portal);
          continue;
        }

        final passengerData = passenger.saveAsPassenger();
        if (passengerData != null) carriage.serialisedPassengers[seat] = passengerData;
      }
    }

    for (final passenger in entity.getPassengers()) {
      if (!passenger.isPlayer) passenger.discard();
    }

    carriage._serialize(entity);
    entity.discard();
    this.entity = null;
  }

  void alignEntity(CarriageContraptionEntity entity) {
    final positionVec = rotationAnchors.getFirst();
    final coupledVec = rotationAnchors.getSecond();
    if (positionVec == null || coupledVec == null) return;

    final diffX = positionVec.$1 - coupledVec.$1;
    final diffY = positionVec.$2 - coupledVec.$2;
    final diffZ = positionVec.$3 - coupledVec.$3;

    entity.prevYaw = entity.yaw;
    entity.prevPitch = entity.pitch;

    final anchor = positionAnchor!;
    final lookahead = anchor + (anchor - entity.position).normalized * 16;

    for (final e in entity.getPassengers()) {
      if (!e.isPlayer) continue;
      if (e.position.distanceSquaredTo(entity.position) > 32 * 32) continue;
      if (entity.level.isActiveChunk(posContaining(lookahead))) break;
      _train.carriageWaitingForChunks = carriage.id;
      return;
    }

    if (_train.carriageWaitingForChunks == carriage.id) _train.carriageWaitingForChunks = -1;

    entity.setServerSidePrevPosition();

    entity.setPos(anchor);
    entity.yaw = toFloat(math.atan2(diffZ, diffX) * 180 / math.pi) + 180;
    entity.pitch = toFloat(math.atan2(diffY, math.sqrt(diffX * diffX + diffZ * diffZ)) * 180 / math.pi) * -1;
    entity.moveToHost();

    if (!entity.firstPositionUpdate) return;

    entity.xo = entity.position.$1;
    entity.yo = entity.position.$2;
    entity.zo = entity.position.$3;
    entity.prevYaw = entity.yaw;
    entity.prevPitch = entity.pitch;
  }
}
