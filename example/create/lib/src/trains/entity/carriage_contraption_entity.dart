// `CarriageContraptionEntity` (pure logic): the entity that shows one carriage of a train. The
// entity itself (position in the world, passengers, the contraption's blocks and actors) lives in
// the host and is reached through [CarriageEntityHost]; this class is the train logic Java puts
// in the subclass: binding to the carriage, the synced data, arrival sounds, conductors, manual
// control from the train controls and the relocation of the position from the carriage anchors.
//
// The host calls [tick] and [tickContraption] each tick, [startControlling] / [control] for the
// player on the controls, and [writeAdditional] / [readAdditional] when the entity is saved.
import 'dart:math' as math;

import '../../common/data.dart';
import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../../redstone/support/text.dart' show Txt;
import '../manager/create.dart';
import '../station/global_station.dart';
import '../util/ctag.dart';
import 'carriage.dart';
import 'carriage_contraption.dart';
import 'carriage_entity_host.dart';
import 'carriage_sync_data.dart';
import 'contraption_data.dart';
import 'train_level.dart';
import 'travelling_point.dart';

class CarriageContraptionEntity {
  /// `getType().updateInterval()` of `create:carriage_contraption`.
  static const int updateInterval = 3;

  final CarriageEntityHost host;
  final TrainLevel level;

  String? trainId;
  int carriageIndex = 0;

  Carriage? _carriage;
  CarriageContraption? contraption;

  bool validForRender = false;
  bool movingBackwards = false;

  bool leftTickingChunks = false;
  bool firstPositionUpdate = true;

  bool _arrivalSoundPlaying = false;
  bool _arrivalSoundReversed = false;
  int _arrivalSoundTicks = -0x80000000;

  Vec3? _serverPrevPos;

  /// The synced `CARRIAGE_DATA` and `SCHEDULED` entries.
  final CarriageSyncData carriageData = CarriageSyncData();
  bool scheduled = false;

  int nonDamageTicks = 0;

  Vec3 position;
  double xo = 0, yo = 0, zo = 0;
  double yaw = 0, pitch = 0, prevYaw = 0, prevPitch = 0;

  CarriageContraptionEntity(
    this.host,
    this.level,
    this.position, {
    this.contraption,
  }) {
    xo = position.$1;
    yo = position.$2;
    zo = position.$3;
  }

  String get dimension => level.dimension;

  int get id => host.entityId;

  bool get isAlive => host.isAlive;

  int get tickCount => host.tickCount;

  CarriageContraption? getContraption() => contraption;

  Carriage? getCarriage() => _carriage;

  List<CarriagePassenger> getPassengers() => host.getPassengers();

  Iterable<CarriagePassenger> getIndirectPassengers() =>
      host.getIndirectPassengers();

  String? getControllingPlayer() => host.getControllingPlayer();

  void addSittingPassenger(CarriagePassenger passenger, int seat) =>
      host.addSittingPassenger(passenger, seat);

  void alignPassenger(CarriagePassenger passenger) =>
      host.alignPassenger(passenger);

  bool isStalled() => host.isStalled();

  void discard() => host.discard();

  void disassemble() => host.disassemble();

  /// `entity.setPos(pos)`: also moves the host entity (with the current rotation).
  void setPos(Vec3 pos) {
    position = pos;
    host.moveTo(position, yaw, pitch);
  }

  /// Pushes the position and rotation to the host entity.
  void moveToHost() => host.moveTo(position, yaw, pitch);

  /// `saveAsPassenger(entity)`: the saved form of the entity.
  CTag? saveAsPassenger() => host.saveAsPassenger();

  void syncCarriage() {
    final carriage = _carriage;
    if (carriage == null) return;
    carriageData.update(this, carriage);
  }

  CarriageSyncData getCarriageData() => carriageData;

  bool hasSchedule() => scheduled;

  void setServerSidePrevPosition() {
    _serverPrevPos = position;
  }

  /// `getPrevPositionVec()` on the server.
  Vec3 getPrevPositionVec() => _serverPrevPos ?? (xo, yo, zo);

  bool isLocalCoordWithin(Pos localPos, int min, int max) {
    final cc = contraption;
    if (cc == null) return false;
    final facing = cc.getAssemblyDirection();
    final axis = facing.clockWise.axis;
    final coord =
        axis.choose(localPos.$3, localPos.$2, localPos.$1) *
        -facing.axisDirection.step;
    return coord >= min && coord <= max;
  }

  /// `tick()` after the host's own entity tick: conductors that sit in the contraption look
  /// where they are seated.
  void tick() {
    final cc = contraption;
    if (cc == null) return;
    for (final entity in getPassengers()) {
      if (entity.isPlayer) continue;
      final seatOf = cc.data.getSeatOf(entity.uuid);
      if (seatOf == null) continue;
      if (cc.conductorSeats[seatOf] == null) continue;
      alignPassenger(entity);
    }
  }

  /// `setBlock(localPos, info)`: a block of the carriage changed; all entities of the carriage
  /// get it.
  void setBlock(Pos localPos, ContraptionBlockInfo newInfo) {
    final carriage = _carriage;
    if (carriage == null) return;
    carriage.forEachPresentEntity((cce) {
      cce.contraption?.data.getBlocks()[localPos] = newInfo;
      cce.host.blockChanged(localPos, newInfo);
    });
  }

  /// `tickContraption()` (the server side).
  void tickContraption() {
    if (nonDamageTicks > 0) nonDamageTicks--;
    final cc = contraption;
    if (cc == null) return;

    final carriage = _carriage;
    if (carriage == null) {
      discard();
      return;
    }

    final train = carriage.train!;
    if (!Create.RAILWAYS.trains.containsKey(train.id)) {
      discard();
      return;
    }

    host.tickActors();
    final isStalled = this.isStalled();
    carriage.stalled = isStalled;

    scheduled = train.runtime.getSchedule() != null;
    host.setScheduled(scheduled);

    final shouldCarriageSyncThisTick = train.shouldCarriageSyncThisTick(
      level.gameTime,
      updateInterval,
    );
    if (shouldCarriageSyncThisTick && carriageData.isDirty()) {
      host.setCarriageData(carriageData);
      carriageData.setDirty(false);
    }

    final navigation = train.navigation;
    if (navigation.announceArrival &&
        navigation.distanceToDestination.abs() < 60 &&
        carriageIndex == (train.speed < 0 ? train.carriages.length - 1 : 0)) {
      navigation.announceArrival = false;
      _arrivalSoundPlaying = true;
      _arrivalSoundReversed = train.speed < 0;
      _arrivalSoundTicks = -0x80000000;
    }

    if (_arrivalSoundPlaying) _tickArrivalSound(cc);

    host.setTrackGraph(train.graph?.id);

    host.resonate();
  }

  void _tickArrivalSound(CarriageContraption cc) {
    final carriages = _carriage!.train!.carriages;

    if (_arrivalSoundTicks == -0x80000000) {
      final carriageCount = carriages.length;
      int? tick;

      for (var index = 0; index < carriageCount; index++) {
        final i = _arrivalSoundReversed ? carriageCount - 1 - index : index;
        final carriage = carriages[i];
        final entity = carriage.getDimensional(dimension).entity;
        final otherCC = entity?.contraption;
        if (entity == null || otherCC == null) break;
        tick = _arrivalSoundReversed
            ? otherCC.soundQueue.lastTick()
            : otherCC.soundQueue.firstTick();
        if (tick != null) break;
      }

      if (tick == null) {
        _arrivalSoundPlaying = false;
        return;
      }

      _arrivalSoundTicks = tick;
    }

    if (tickCount % 2 == 0) return;

    var keepTicking = false;
    for (final c in carriages) {
      final entity = c.getDimensional(dimension).entity;
      final otherCC = entity?.contraption;
      if (entity == null || otherCC == null) continue;
      keepTicking |= otherCC.soundQueue.tick(
        entity,
        _arrivalSoundTicks,
        _arrivalSoundReversed,
      );
    }

    if (!keepTicking) {
      _arrivalSoundPlaying = false;
      return;
    }

    _arrivalSoundTicks += _arrivalSoundReversed ? -1 : 1;
  }

  /// `bindCarriage()`: finds the carriage of the train by [trainId] and [carriageIndex]; used
  /// after loading the entity.
  void bindCarriage() {
    if (_carriage != null) return;
    final train = Create.RAILWAYS.trains[trainId];
    if (train == null || train.carriages.length <= carriageIndex) return;
    final carriage = train.carriages[carriageIndex];
    _carriage = carriage;
    final dimensional = carriage.getDimensional(dimension);
    dimensional.entity = this;
    dimensional.pivot = null;
    carriage.updateContraptionAnchors();
    dimensional.updateRenderedCutoff();
  }

  /// `writeAdditional`: the train binding.
  void writeAdditional(CTag compound, bool spawnPacket) {
    if (trainId != null) compound.putUuid('TrainId', trainId!);
    compound.putInt('CarriageIndex', carriageIndex);
  }

  /// `readAdditional`.
  void readAdditional(CTag compound, bool spawnPacket) {
    trainId = compound.getUuid('TrainId');
    carriageIndex = compound.getInt('CarriageIndex');
    if (spawnPacket) {
      xo = position.$1;
      yo = position.$2;
      zo = position.$3;
    }
  }

  Txt getContraptionName() =>
      _carriage?.train?.name ?? Txt.translate('create.train');

  Txt getDisplayName() => _carriage == null
      ? Txt.translate('create.train')
      : _carriage!.train!.name;

  /// `checkConductors()`: which sides have a conductor (blaze burner or a seated conductor).
  Couple<bool> checkConductors() {
    final sides = Couple.create(false, false);
    final cc = contraption;
    if (cc == null) return sides;

    sides.setFirst(cc.blockConductors.getFirst());
    sides.setSecond(cc.blockConductors.getSecond());

    for (final entity in getPassengers()) {
      if (entity.isPlayer) continue;
      final seatOf = cc.data.getSeatOf(entity.uuid);
      if (seatOf == null) continue;
      final validSides = cc.conductorSeats[seatOf];
      if (validSides == null) continue;
      sides.setFirst(sides.getFirst() || validSides.getFirst());
      sides.setSecond(sides.getSecond() || validSides.getSecond());
    }

    return sides;
  }

  bool startControlling(Pos controlsLocalPos, CarriagePassenger? player) {
    if (player == null || player.isSpectator) return false;
    final carriage = _carriage;
    if (carriage == null) return false;
    if (carriage.train!.derailed) return false;

    final train = carriage.train!;
    if (train.runtime.getSchedule() != null && !train.runtime.paused)
      train.status.manualControls();
    train.navigation.cancelNavigation();
    train.runtime.paused = true;
    train.navigation.waitingForSignal = null;
    return true;
  }

  double _navDistanceTotal = 0;
  int _hudPacketCooldown = 0;
  bool _stationMessage = false;

  /// `control(controlsLocalPos, heldControls, player)`: the held keys are 0 forward, 1 back,
  /// 2 left, 3 right, 4 jump (navigate to the station ahead), 5 sprint.
  bool control(
    Pos controlsLocalPos,
    Iterable<int> heldControlsIn,
    CarriagePassenger player,
  ) {
    final carriage = _carriage;
    if (carriage == null) return false;
    final train = carriage.train!;
    if (train.derailed) return false;
    if (player.isSpectator) return false;
    if (!host.canInteractWithBlock(
      player.uuid,
      VecHelper.getCenterOf(controlsLocalPos),
      8,
    ))
      return false;
    final heldControls = heldControlsIn.toList();
    if (heldControls.contains(5)) return false;

    final info = contraption?.data.getBlocks()[controlsLocalPos];
    final initialOrientation = host.getInitialOrientation().counterClockWise;
    var inverted = false;
    if (info != null && info.state.has('facing')) {
      inverted = info.state.dir('facing') != initialOrientation;
    }

    if (_hudPacketCooldown-- <= 0 && player.isPlayer) {
      TrainFx.effects.sendTrainHud(player.uuid, train);
      _hudPacketCooldown = 5;
    }

    var targetSpeed = 0;
    if (heldControls.contains(0)) targetSpeed++;
    if (heldControls.contains(1)) targetSpeed--;

    var targetSteer = 0;
    if (heldControls.contains(2)) targetSteer++;
    if (heldControls.contains(3)) targetSteer--;

    if (inverted) {
      targetSpeed *= -1;
      targetSteer *= -1;
    }

    if (targetSpeed != 0) train.burnFuel();

    final slow = inverted ^ (targetSpeed < 0);
    final spaceDown = heldControls.contains(4);
    final currentStation = train.getCurrentStation();
    if (currentStation != null && spaceDown) {
      _sendPrompt(
        player,
        Txt.translate('create.train.arrived_at', [
          Txt.literal(currentStation.name).withColor(0x704630),
        ]).toJson(),
        false,
      );
      return true;
    }

    if (train.speedBeforeStall != null &&
        targetSpeed != 0 &&
        _signum(train.speedBeforeStall!) != _signum(targetSpeed.toDouble())) {
      train.cancelStall();
    }

    if (currentStation != null && targetSpeed != 0) {
      _stationMessage = false;
      _sendPrompt(
        player,
        Txt.translate('create.train.departing_from', [
          Txt.literal(currentStation.name).withColor(0x704630),
        ]).toJson(),
        false,
      );
    }

    if (currentStation == null) {
      final nav = train.navigation;
      if (nav.destination != null) {
        if (!spaceDown) nav.cancelNavigation();
        if (spaceDown) {
          final f = nav.distanceToDestination / _navDistanceTotal;
          final progress = (clampNum(1 - ((1 - f) * (1 - f)), 0.0, 1.0) * 30)
              .toInt();
          final arrived = progress == 0;
          final whiteComponent = Txt.literal('|' * progress);
          final greenComponent = Txt.literal('|' * (30 - progress));

          const fromColor = 0x00FFC244;
          const toColor = 0x00529915;

          final mixedColor = mixColors(
            toColor,
            fromColor,
            toFloat(progress / 30.0),
          );
          final targetColor = arrived ? toColor : 0x00544D45;

          final component = greenComponent
              .withColor(mixedColor)
              .append(whiteComponent.withColor(targetColor));
          _sendPrompt(player, component.toJson(), true);
          train.manualTick = true;
          return true;
        }
      }

      final directedSpeed = targetSpeed != 0
          ? targetSpeed.toDouble()
          : train.speed;
      final lookAhead = nav.findNearestApproachable(
        !train.doubleEnded ||
            (directedSpeed != 0 ? directedSpeed > 0 : !inverted),
      );

      if (lookAhead != null) {
        if (spaceDown) {
          train.manualTick = true;
          nav.startNavigation(nav.findPathToStation(lookAhead, -1));
          train.manualTick = false;
          _navDistanceTotal = nav.distanceToDestination;
          return true;
        }
        _displayApproachStationMessage(player, lookAhead);
      } else {
        _cleanUpApproachStationMessage(player);
      }
    }

    train.manualSteer = targetSteer < 0
        ? SteerDirection.right
        : (targetSteer > 0 ? SteerDirection.left : SteerDirection.none);

    var topSpeed =
        train.maxSpeed() *
        toFloat(TrainSettings.current.manualTrainSpeedModifier);
    final cappedTopSpeed = topSpeed * train.throttle;

    final leadingEdge = carriage.getLeadingPoint().edge;
    final trailingEdge = carriage.getTrailingPoint().edge;
    if (leadingEdge != null && leadingEdge.isTurn() ||
        trailingEdge != null && trailingEdge.isTurn()) {
      topSpeed = train.maxTurnSpeed();
    }

    if (slow) topSpeed /= 4;
    train.targetSpeed = math.min(topSpeed, cappedTopSpeed) * targetSpeed;

    final counteringAcceleration =
        (_signum(targetSpeed.toDouble()) - _signum(train.speed)).abs() >
        toFloat(1.5);

    if (slow && !counteringAcceleration) train.backwardsDriver = player.uuid;

    train.manualTick = true;
    train.approachTargetSpeed(counteringAcceleration ? 2 : 1);
    return true;
  }

  static double _signum(double v) => v > 0 ? 1.0 : (v < 0 ? -1.0 : 0.0);

  /// `Color.mixColors(color1, color2, w)` for opaque colors: the per channel mix, [w] 0 is
  /// [color1].
  static int mixColors(int color1, int color2, double w) {
    int mix(int shift) {
      final a = (color1 >> shift) & 0xff;
      final b = (color2 >> shift) & 0xff;
      return (a + (b - a) * w).toInt() & 0xff;
    }

    return (mix(16) << 16) | (mix(8) << 8) | mix(0);
  }

  void _sendPrompt(CarriagePassenger player, Object textJson, bool shadow) {
    if (player.isPlayer)
      TrainFx.effects.sendPrompt(player.uuid, textJson, shadow);
  }

  void _displayApproachStationMessage(
    CarriagePassenger player,
    GlobalStation station,
  ) {
    _sendPrompt(player, {
      'translate': 'create.contraption.controls.approach_station',
      'with': [
        {'keybind': 'key.jump'},
        station.name,
      ],
    }, false);
    _stationMessage = true;
  }

  void _cleanUpApproachStationMessage(CarriagePassenger player) {
    if (!_stationMessage) return;
    TrainFx.effects.sendOverlayMessage(player.uuid, Txt.empty());
    _stationMessage = false;
  }

  void setCarriage(Carriage carriage) {
    _carriage = carriage;
    trainId = carriage.train!.id;
    carriageIndex = carriage.train!.carriages.indexOf(carriage);
    contraption?.swapStorageAfterAssembly(this);
    host.setTrackGraph(carriage.train!.graph?.id);

    final dimensional = carriage.getDimensional(dimension);
    dimensional.pivot = null;
    carriage.updateContraptionAnchors();
    dimensional.updateRenderedCutoff();
  }
}
