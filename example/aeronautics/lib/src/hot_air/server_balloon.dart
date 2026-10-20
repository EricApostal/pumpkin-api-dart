// The server side of a balloon: the gas amounts, and the lift and torque they
// produce on the sub-level they belong to.
//
// Java: `content/blocks/hot_air/balloon/ServerBalloon`.
//
// The lift is computed from the *centre of the air volume* and its spread: the
// average position gives the torque arm, the outer-product matrix gives how the
// pressure gradient across the volume turns into a torque. Both are maintained
// incrementally as blocks join or leave the volume, and rebuilt from scratch
// when the graph is.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:sable/sable.dart'
    show
        AssemblyTransform,
        DimensionPhysicsData,
        ForceGroup,
        Matrix3d,
        ServerSubLevel,
        SubLevelHelper,
        Vector3d;

import 'balloon.dart';
import 'balloon_map.dart';
import 'lifting_gas.dart';

/// `ServerBalloon`.
final class ServerBalloon extends Balloon {
  /// The gas amounts, by gas.
  final Map<LiftingGasType, LiftingGasData> gasAmounts = {};

  // Physics scratch: the Java class keeps these as instance fields so the
  // physics tick allocates nothing.
  final Matrix3d _outerProduct = Matrix3d.zero();
  final Matrix3d _translatedOuterProduct = Matrix3d.zero();
  final Vector3d _averagePosition = Vector3d();
  final Vector3d _translatedAveragePosition = Vector3d();

  /// The origin the average position and the matrices are relative to.
  final Vector3d _physicsOrigin;

  final Vector3d _localAveragePosition = Vector3d();
  final Vector3d _worldCenter = Vector3d();
  final Vector3d _gradient = Vector3d();
  final Vector3d _force = Vector3d();
  final Vector3d _torque = Vector3d();
  final Vector3d _positionTemp = Vector3d();

  double _totalLift = 0;
  double _totalFilledVolume = 0;
  double _totalTargetVolume = 0;
  double _totalVolumeChange = 0;
  bool _leaking = false;

  ServerBalloon(
    super.world,
    super.controllerPos,
    super.graph,
    super.heaters,
  ) : _physicsOrigin = Vector3d(
        controllerPos.$1.toDouble(),
        controllerPos.$2.toDouble(),
        controllerPos.$3.toDouble(),
      ) {
    onRebuilt();
  }

  // -- Gas -----------------------------------------------------------------------

  /// The total lift in kilopixel-grams.
  double get totalLift => _totalLift;

  /// The filled volume, in cubic metres.
  double get totalFilledVolume => _totalFilledVolume;

  /// The volume the heaters want to fill.
  double get totalTargetVolume => _totalTargetVolume;

  /// The change of the filled volume in the last tick.
  double get totalVolumeChange => _totalVolumeChange;

  /// The centre of the air volume, in the world's coordinates.
  Vector3d get center => Vector3d.copy(_averagePosition).add(_physicsOrigin);

  /// The gas amounts, as the save data holds them.
  List<LiftingGasHolder> get liftingGasHolders => [
    for (final entry in gasAmounts.entries) LiftingGasHolder(entry.key, entry.value),
  ];

  /// Loads the gas amounts of a balloon that was unloaded at this position.
  void loadFrom(SavedBalloon unloaded) {
    for (final holder in unloaded.gasData) {
      gasAmounts[holder.type] = holder.data.copy();
    }
  }

  @override
  void tick() {
    super.tick();
    updateGasAmounts();
  }

  @override
  void checkHeaters() {
    super.checkHeaters();

    for (final data in gasAmounts.values) {
      data.target = 0;
    }

    if (_leaking) return;

    for (final heater in heaters) {
      final type = heater.liftingGasType;
      final data = gasAmounts.putIfAbsent(type, LiftingGasData.new);
      data.target += heater.gasOutput;
    }
  }

  /// Moves every gas towards its target and recomputes the lift.
  void updateGasAmounts() {
    final capacity = this.capacity;

    // The balloon may be over capacity for a moment (half of it destroyed), so
    // the lift does not jump.
    _totalTargetVolume = 0;
    for (final data in gasAmounts.values) {
      _totalTargetVolume += data.target;
    }

    final scale = _totalTargetVolume <= 0 ? 1.0 : math.min(capacity / _totalTargetVolume, 1);

    for (final entry in gasAmounts.entries) {
      final type = entry.key;
      final data = entry.value;
      final difference = data.target * scale - data.amount;

      if (difference > 0) {
        data.nudge = difference / type.fillingTime;
      } else if (difference < 0) {
        data.nudge = difference / type.emptyingTime;
      } else {
        data.nudge = 0;
      }

      // Close to the target the fill rate speeds up, so the last few blocks do
      // not take forever.
      if (type.responsivenessAdjustmentFactor > 0 && type.responsivenessAdjustmentRange > 0) {
        final x = capacity == 0 ? 0.0 : difference / (capacity * type.responsivenessAdjustmentRange);
        data.nudge *= 1 + type.responsivenessAdjustmentFactor / (1 + 3 * x * x);
      }
    }

    _totalLift = 0;
    _totalFilledVolume = 0;
    _totalVolumeChange = 0;

    for (final entry in gasAmounts.entries) {
      final data = entry.value;
      data.amount += data.nudge;
      _totalLift += data.amount * entry.key.liftStrength;
      _totalFilledVolume += data.amount;
      _totalVolumeChange += data.nudge;
    }

    _totalTargetVolume = math.min(_totalTargetVolume, capacity.toDouble());
  }

  // -- Physics -------------------------------------------------------------------

  /// Applies the lift and torque of the gas to the sub-level for one physics
  /// tick.
  void applyForces(double timeStep) {
    final capacity = this.capacity;
    if (capacity <= 0) return;

    final subLevel = SubLevelHelper.getContaining(world.level, controllerPos);
    if (subLevel is! ServerSubLevel) return;
    if (_totalFilledVolume == 0) return;

    _translateMatrices();

    final level = subLevel.getLevel();
    final pose = subLevel.logicalPose;

    _translatedAveragePosition.setFrom(_averagePosition).add(_physicsOrigin);

    _localAveragePosition.setFrom(_translatedAveragePosition).sub(pose.rotationPoint());
    _worldCenter.setFrom(_localAveragePosition);
    pose.orientation().transform(_worldCenter, _worldCenter).add(pose.position());

    final gravity = DimensionPhysicsData.getGravity(level, Vector3d.copy(_worldCenter));
    pose.orientation().transformInverse(gravity, gravity);
    final pressure = BalloonMap.airPressureAtVector(world, _worldCenter);
    if (pressure < 1e-5 || gravity.lengthSquared == 0) return;

    // The gradient of the pressure, in the sub-level's own space.
    const diff = 0.1;
    final pressureX = BalloonMap.airPressureAtVector(world, Vector3d(_worldCenter.x + diff, _worldCenter.y, _worldCenter.z)) - pressure;
    final pressureY = BalloonMap.airPressureAtVector(world, Vector3d(_worldCenter.x, _worldCenter.y + diff, _worldCenter.z)) - pressure;
    final pressureZ = BalloonMap.airPressureAtVector(world, Vector3d(_worldCenter.x, _worldCenter.y, _worldCenter.z + diff)) - pressure;
    _gradient.set(pressureX, pressureY, pressureZ).div(diff);
    pose.orientation().transformInverse(_gradient, _gradient);

    // Force and torque, in momentum units.
    _force.setFrom(gravity).mul(-_totalLift);
    _torque.setFrom(_localAveragePosition).mul(pressure);
    _torque.fma(1.0 / capacity, _translatedOuterProduct.transform(_gradient, Vector3d()));
    _torque.cross(_force);
    _force.mul(pressure);

    _force.mul(timeStep);
    _torque.mul(timeStep);

    // The queued force groups carry a force total but no torque, so the impulse
    // goes straight to the body; the group only keeps the point force for the
    // heat map and the debug view.
    final handle = subLevel.physicsBody;
    if (handle != null) {
      handle.applyLinearAndAngularImpulse(Vector3d.copy(_force), Vector3d.copy(_torque), true);
    }

    if (subLevel.isTrackingIndividualQueuedForces()) {
      final group = subLevel.getOrCreateQueuedForceGroup(ForceGroup.balloonLift);
      final point = Vector3d.copy(_translatedAveragePosition)
        ..fma(1 / (pressure * capacity), _gradient);
      group.recordPointForce(point, Vector3d.copy(_force));
    }
  }

  /// `translateMatrices`: moves the outer-product matrix to the centre of mass.
  void _translateMatrices() {
    _translatedOuterProduct.setFrom(_outerProduct);
    Matrix3d.fmaOuterProduct(_averagePosition, _averagePosition, -capacity.toDouble(), _translatedOuterProduct);
  }

  // -- Maintenance ---------------------------------------------------------------

  @override
  void onRebuilt() {
    _outerProduct.set(0, 0, 0, 0, 0, 0, 0, 0, 0);
    _averagePosition.zero();

    for (final layer in layerGraph.layers) {
      for (final pos in layer.nonSolidBlocks) {
        _positionTemp
          ..set(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5)
          ..sub(_physicsOrigin);
        _averagePosition.add(_positionTemp);
      }
    }

    final capacity = this.capacity;
    if (capacity > 0) _averagePosition.div(capacity.toDouble());

    for (final layer in layerGraph.layers) {
      for (final pos in layer.nonSolidBlocks) {
        _positionTemp
          ..set(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5)
          ..sub(_physicsOrigin);
        Matrix3d.fmaOuterProduct(_positionTemp, _positionTemp, 1, _outerProduct);
      }
    }

    _leaking = false;
  }

  @override
  void onHotAirAdded(Pos pos) {
    _positionTemp
      ..set(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5)
      ..sub(_physicsOrigin);

    final capacity = this.capacity;
    _averagePosition
      ..mul((capacity - 1).toDouble())
      ..add(_positionTemp)
      ..div(capacity.toDouble());
    Matrix3d.fmaOuterProduct(_positionTemp, _positionTemp, 1, _outerProduct);
  }

  @override
  void onHotAirRemoved(Pos pos) {
    _positionTemp
      ..set(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5)
      ..sub(_physicsOrigin);

    final capacity = this.capacity;
    _averagePosition
      ..mul((capacity + 1).toDouble())
      ..sub(_positionTemp)
      ..div(capacity.toDouble());
    Matrix3d.fmaOuterProduct(_positionTemp, _positionTemp, -1, _outerProduct);
  }

  @override
  void onHotAirRemovedAll(List<Pos> positions) {
    for (final pos in positions) {
      _positionTemp
        ..set(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5)
        ..sub(_physicsOrigin);

      _averagePosition
        ..mul(capacity.toDouble())
        ..sub(_positionTemp)
        ..div((capacity - 1).toDouble());
      Matrix3d.fmaOuterProduct(_positionTemp, _positionTemp, -1, _outerProduct);

      capacity--;
    }
  }

  @override
  void setLeaking() => _leaking = true;

  @override
  void setAssembling(AssemblyTransform transform) {
    super.setAssembling(transform);
    _physicsOrigin.set(controllerPos.$1.toDouble(), controllerPos.$2.toDouble(), controllerPos.$3.toDouble());
  }

  /// A gust is only worth spawning when the removed block was in the gas: below
  /// the fill line the escaping gas does not reach it.
  @override
  bool shouldSpawnGust(Pos pos) {
    final capacity = this.capacity;
    if (capacity <= 0) return false;
    final percentHeight = (pos.$2 + 0.5 - bounds.minY) / height;
    final fill = (_totalFilledVolume / capacity).clamp(0.0, 1.0);
    return percentHeight > 1.0 - fill;
  }

  /// Spawns a gust, taking a share of every gas first: a gust only forms when
  /// every gas had its share.
  @override
  void spawnGust(int x, int y, int z, Direction direction) {
    var contributingGases = 0;
    for (final holder in liftingGasHolders) {
      if (holder.data.amount > 0) contributingGases++;
    }
    if (contributingGases == 0) return;

    var canSpawnGust = true;
    final nudge = 1.0 / contributingGases;
    for (final holder in liftingGasHolders) {
      if (holder.data.amount < nudge) {
        canSpawnGust = false;
        holder.data.amount = 0;
      } else {
        holder.data.amount -= nudge;
      }
    }

    if (canSpawnGust) super.spawnGust(x, y, z, direction);
  }

  @override
  bool get isValid => _totalTargetVolume > 0.05 || _totalFilledVolume > 0.05;

  /// Whether the volume opened to the outside and the balloon is losing gas.
  bool get isLeaking => _leaking;

  @override
  void merge(Balloon other) {
    super.merge(other);
    if (other is ServerBalloon) {
      for (final entry in other.gasAmounts.entries) {
        final existing = gasAmounts.putIfAbsent(entry.key, () => LiftingGasData());
        existing.amount += entry.value.amount;
        existing.target += entry.value.target;
        existing.nudge += entry.value.nudge;
      }
    }
  }

  @override
  String toString() =>
      'ServerBalloon(controller: $controllerPos, capacity: $capacity, filled: ${_totalFilledVolume.toStringAsFixed(2)}, lift: ${_totalLift.toStringAsFixed(2)})';
}
