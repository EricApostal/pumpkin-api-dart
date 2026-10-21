// `BoreheadBearingLogic`: the numbers of the borehead bearing: the rotation
// speed and its slowdown, the rock cutter positions on the contraption, the
// mining cursor and the stall timer.
//
// The Sable handles, the kinetic network and the contraption entity live in the
// block entity; everything that decides *where* and *how fast* is here.
//
// Pure: no host imports.
//
// Java: `content/blocks/borehead_bearing/BoreheadBearingBlockEntity.java`
//       (673 lines)
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/common/common.dart' show Pos, Vec3, vec3Zero;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:simulated/simulated.dart' show BearingSlowdownController, ContraptionSymmetry;

import '../../../config/offroad_config.dart';

/// The result of one `updateSpeed` (`BoreheadBearingBlockEntity.java:280`).
enum BoreheadSpeedStep {
  /// The rotation speed was updated.
  running,

  /// The slowdown finished: the bearing must disassemble.
  disassemble,
}

/// The state machine of one borehead bearing.
final class BoreheadBearingLogic {
  /// `IMMUT_ZERO` (`BoreheadBearingBlockEntity.java:61`).
  static const Vec3 immutZero = vec3Zero;

  /// `r`, the radius the search box is inflated by
  /// (`BoreheadBearingBlockEntity.java:195`).
  static const double searchBoxRadius = 1;

  /// `getBreakingSpeed`'s multipliers (`BoreheadBearingBlockEntity.java:226-232`).
  static const int superEffectiveMultiplier = 100;
  static const int effectiveMultiplier = 10;
  static const int defaultMultiplier = 5;

  /// `startDisassemblySlowdown`'s base (`BoreheadBearingBlockEntity.java:515`).
  static const double slowdownBaseTicks = 1;

  /// `getRockCuttingAmount(10)` in the slow-down start and `getRockCuttingAmount(12)`
  /// in the disassembly (`BoreheadBearingBlockEntity.java:299,513`).
  static const int minimumRockCuttersForSpeed = 10;
  static const int minimumRockCuttersForSlowdown = 12;

  /// The slowdown controller (`BoreheadBearingBlockEntity.java:68`).
  final BearingSlowdownController slowdown = BearingSlowdownController();

  /// `centerMiningPositions`: the origin of every rock cutter on the contraption
  /// (`BoreheadBearingBlockEntity.java:72`).
  final List<Vec3> centerMiningPositions = [];

  /// `visitedPositions`: the blocks this bearing is cutting right now
  /// (`BoreheadBearingBlockEntity.java:73`).
  final Set<Pos> visitedPositions = {};

  /// `nextAvailableIndex` (`BoreheadBearingBlockEntity.java:77`).
  int nextAvailableIndex = 0;

  /// `rotationSpeed` (`BoreheadBearingBlockEntity.java:80`).
  double rotationSpeed = 0;

  /// `disassemblySlowdown` (`BoreheadBearingBlockEntity.java:79`).
  bool disassemblySlowdown = false;

  /// `initialized`: the contraption was scanned for rock cutters
  /// (`BoreheadBearingBlockEntity.java:92`).
  bool initialized = false;

  /// `stalled` (`BoreheadBearingBlockEntity.java:93`).
  bool stalled = false;

  /// `stalledRecoveryTimer` (`BoreheadBearingBlockEntity.java:97`).
  int stalledRecoveryTimer = 0;

  /// `clientRockCutters`: how many cutters the client was told about
  /// (`BoreheadBearingBlockEntity.java:88`).
  int clientRockCutters = 0;

  /// `insideMainTick` (`BoreheadBearingBlockEntity.java:98`).
  bool insideMainTick = false;

  BoreheadBearingLogic();

  /// `isSlowingDown()` (`BoreheadBearingBlockEntity.java:534`).
  bool get isSlowingDown => disassemblySlowdown;

  /// `isStalled()` (`BoreheadBearingBlockEntity.java:644`).
  bool get isStalled => stalled || stalledRecoveryTimer > 0;

  /// `getRockCuttingAmount(0)`.
  int get rockCuttingAmount => centerMiningPositions.length;

  /// `getRockCuttingAmount(minimumRockcuttingWheelAmount)`
  /// (`BoreheadBearingBlockEntity.java:320`).
  int rockCuttingAmountAtLeast(int minimum) =>
      math.max(rockCuttingAmount, minimum);

  /// `isActive()` (`BoreheadBearingBlockEntity.java:256`): only a running,
  /// non-slowing, non-stalled bearing cuts.
  bool isActive({required double speed, required bool removed}) =>
      initialized && speed != 0 && !isSlowingDown && !removed && !isStalled;

  // -- Speed (`BoreheadBearingBlockEntity.java:280-360`) ------------------------

  /// `updateSpeed()` (`BoreheadBearingBlockEntity.java:280`).
  ///
  /// [angularSpeed] is `super.getAngularSpeed()` (the kinetic speed in degrees
  /// per tick) and [speed] `getSpeed()`. [isVirtual] is a ponder.
  BoreheadSpeedStep updateSpeed({
    required bool isVirtual,
    required bool isClientSide,
    required double angularSpeed,
    required double speed,
  }) {
    if (isSlowingDown) {
      if (slowdown.stepGoal() && !isClientSide) {
        return BoreheadSpeedStep.disassemble;
      }

      rotationSpeed = slowdown.speed(0);
      return BoreheadSpeedStep.running;
    }

    final divisor = OffroadConfig.server.blocks.boreheadBearingRotationDivisor;
    var targetSpeed = isVirtual ? angularSpeed / 4 : angularSpeed / divisor;

    final currentRockCutters = rockCuttingAmountAtLeast(minimumRockCuttersForSpeed);
    var fullMass = (currentRockCutters * 5).toDouble();

    if (isStalled) {
      targetSpeed /= 4;
      fullMass = currentRockCutters.toDouble();
    } else if (speed == 0) {
      targetSpeed = 0;
      fullMass = currentRockCutters.toDouble();
    }

    // While slowing down and without rotation there is no point lerping after
    // a while.
    if (rotationSpeed.abs() <= 0.05 && speed == 0) {
      rotationSpeed = 0;
      return BoreheadSpeedStep.running;
    }

    rotationSpeed = _lerp(1 / fullMass, rotationSpeed, targetSpeed);
    return BoreheadSpeedStep.running;
  }

  /// `this.angle = this.slowdownController.getAngle(0)` of `updateSpeed`
  /// (`BoreheadBearingBlockEntity.java:290`).
  double get slowdownAngle => slowdown.angle(0);

  /// `getAngularSpeed()` (`BoreheadBearingBlockEntity.java:346`): the slowdown
  /// speed while the disassembly slows the bearing down (`clientAngleDiff` is
  /// client-only and passed in).
  double angularSpeed({required bool insideMainTick, required double clientAngleDiff}) {
    if (insideMainTick && disassemblySlowdown) {
      return slowdown.speed(1) + clientAngleDiff / 3;
    }
    return rotationSpeed;
  }

  /// `getInterpolatedAngle(partialTicks)` (`BoreheadBearingBlockEntity.java:332`).
  double interpolatedAngle({
    required double partialTicks,
    required bool isVirtual,
    required double angle,
  }) {
    if (!isVirtual && isSlowingDown) return slowdown.angle(partialTicks);
    if (isVirtual) return _lerp(partialTicks, angle, angle + rotationSpeed);
    return angle + rotationSpeed * partialTicks;
  }

  // -- Stalling (`BoreheadBearingBlockEntity.java:362-367,648`) ----------------

  /// `startUnstalling()` (`BoreheadBearingBlockEntity.java:362`).
  void startUnstalling() {
    if (stalled) {
      stalled = false;
      stalledRecoveryTimer = OffroadConfig.server.blocks.boreheadBearingStallRecoveryTicks;
    }
  }

  /// `setStalled(stalled)` (`BoreheadBearingBlockEntity.java:648`).
  void setStalled(bool value) => stalled = value;

  /// The stall timer's tick (`BoreheadBearingBlockEntity.java:166-173`):
  /// returns whether the countdown reached zero this tick, which is when the
  /// client is told.
  bool tickStallTimer() {
    final before = stalledRecoveryTimer;
    if (stalledRecoveryTimer > 0) stalledRecoveryTimer--;
    return stalledRecoveryTimer == 0 && before != stalledRecoveryTimer;
  }

  /// `itemCallback(stack)`'s decision (`BoreheadBearingBlockEntity.java:261`):
  /// whether a full inventory stalls the bearing.
  static bool shouldStall({required int inserted, required bool stallingEnabled}) =>
      inserted == 0 && stallingEnabled;

  // -- The contraption's rock cutters ------------------------------------------

  /// `initializeContraption`'s scan (`BoreheadBearingBlockEntity.java:465-479`):
  /// one empty entry per rock cutting wheel block on the contraption, which the
  /// actors then fill in through [updatePosition].
  void initializeFromBlocks(int rockCuttingWheelBlocks) {
    resetCenterMiningInfo();
    for (var i = 0; i < rockCuttingWheelBlocks; i++) {
      centerMiningPositions.add(vec3Zero);
    }
    initialized = true;
  }

  /// `resetCenterMiningInfo()` (`BoreheadBearingBlockEntity.java:504`).
  void resetCenterMiningInfo() {
    centerMiningPositions.clear();
    nextAvailableIndex = 0;
    visitedPositions.clear();
  }

  /// `requestNewIndexAndIncrement(context)`
  /// (`BoreheadBearingBlockEntity.java:538`): the next free index, or `-1` when
  /// the block is not a rock cutter or the contraption has no room left.
  int requestNewIndex({required bool isRockCuttingWheel}) {
    if (isRockCuttingWheel && nextAvailableIndex < centerMiningPositions.length) {
      return nextAvailableIndex++;
    }
    return -1;
  }

  /// `updatePosition(index, originPosition)`
  /// (`BoreheadBearingBlockEntity.java:549`).
  void updatePosition(int index, Vec3 originPosition) {
    if (index < centerMiningPositions.length) {
      centerMiningPositions[index] = originPosition;
    }
  }

  /// `updateMiningBlocks` (`BoreheadBearingBlockEntity.java:162`): the blocks
  /// inside the search box of every rock cutter, in the Java loop order
  /// (x, then z, then y).
  ///
  /// The caller asks [MultiMiningLevelLike] whether a candidate may be cut and
  /// adds it to the manager; this only decides which positions are candidates.
  Iterable<Pos> candidatesFor(Vec3 origin) sync* {
    final searchRadius = OffroadConfig.server.blocks.boreheadBearingSearchRadius;
    final doubled = searchRadius * 2;
    final minX = _intFloor(origin.$1 - doubled);
    final maxX = _intFloor(origin.$1 + doubled);
    final minY = _intFloor(origin.$2 - doubled);
    final maxY = _intFloor(origin.$2 + doubled);
    final minZ = _intFloor(origin.$3 - doubled);
    final maxZ = _intFloor(origin.$3 + doubled);

    for (var x = minX; x <= maxX; x++) {
      for (var z = minZ; z <= maxZ; z++) {
        for (var y = minY; y <= maxY; y++) {
          if (!inSearchBox(origin, x, y, z, searchRadius)) continue;
          yield (x, y, z);
        }
      }
    }
  }

  /// The box SDF test of the search (`BoreheadBearingBlockEntity.java:196-202`).
  ///
  /// ```
  /// localPoint = |(x+.5, y+.5, z+.5) - pos| - searchRadius + 1
  /// boxSDF     = max(localPoint, 0).length() + min(max(localPoint.x, max(localPoint.y, localPoint.z)), 0)
  /// candidate  = boxSDF - 1 <= 0
  /// ```
  static bool inSearchBox(Vec3 origin, int x, int y, int z, double searchRadius) {
    final px = (x + 0.5 - origin.$1).abs() - searchRadius + searchBoxRadius;
    final py = (y + 0.5 - origin.$2).abs() - searchRadius + searchBoxRadius;
    final pz = (z + 0.5 - origin.$3).abs() - searchRadius + searchBoxRadius;

    final outside = math.sqrt(
      math.max(px, 0) * math.max(px, 0) +
          math.max(py, 0) * math.max(py, 0) +
          math.max(pz, 0) * math.max(pz, 0),
    );
    final inside = math.min(math.max(px, math.max(py, pz)), 0);
    return outside + inside - searchBoxRadius <= 0;
  }

  /// `getBreakingSpeed(level, pos, state)`
  /// (`BoreheadBearingBlockEntity.java:222`): 0 when inactive, otherwise the
  /// rotation speed scaled by the block's tag and divided by how much is being
  /// cut.
  double breakingSpeed({
    required bool active,
    required bool superEffective,
    required bool effective,
    required double maxRotationSpeed,
    required double speed,
  }) {
    if (!active) return 0;

    final multiplier = superEffective
        ? superEffectiveMultiplier
        : (effective ? effectiveMultiplier : defaultMultiplier);

    var baseMiningSpeed = ((rotationSpeed * multiplier).abs() / 100).clamp(0.01, 16.0);

    final blockAmount = visitedPositions.length / 50.0;
    if (blockAmount != 0) {
      final inversePercentage = (speed.abs() / maxRotationSpeed).abs();
      baseMiningSpeed /= math.max(blockAmount * inversePercentage, 1);
    }

    return baseMiningSpeed;
  }

  /// `getLocation()` (`BoreheadBearingBlockEntity.java:250`).
  static Pos? locationOf({required bool active, required Pos pos}) => active ? pos : null;

  // -- Disassembly (`BoreheadBearingBlockEntity.java:511`) ----------------------

  /// `startDisassemblySlowdown()` (`BoreheadBearingBlockEntity.java:511`):
  /// starts the slowdown curve; the timer grows with the square of the cutter
  /// count.
  void startDisassemblySlowdown({
    required double interpolatedAngle,
    required double rotationSpeed,
    required Direction facing,
    required Map<Pos, String> contraptionBlocks,
  }) {
    if (isSlowingDown) return;
    final rockCuttingAmount = rockCuttingAmountAtLeast(minimumRockCuttersForSlowdown);

    slowdown.generate(
      maxTime:
          slowdownBaseTicks + BearingSlowdownController.timerScale * (rockCuttingAmount * rockCuttingAmount),
      initialAngle: interpolatedAngle,
      initialVelocity: rotationSpeed,
      symmetry: BearingSlowdownController.symmetryOf(contraptionBlocks, facing),
    );
    disassemblySlowdown = true;
  }

  /// The symmetry the controller uses, for the tests.
  ContraptionSymmetry symmetryOf(Map<Pos, String> blocks, Direction facing) =>
      BearingSlowdownController.symmetryOf(blocks, facing);

  // -- Saved data (`BoreheadBearingBlockEntity.java:555-630`) -------------------

  /// `write(compound, registries, clientPacket)`
  /// (`BoreheadBearingBlockEntity.java:556`).
  Map<String, Object?> write({required bool clientPacket}) => {
    'RotationSpeed': rotationSpeed,
    if (clientPacket) 'BlockBreakingAmount': visitedPositions.length,
    'DisassemblySlowdown': disassemblySlowdown,
    if (disassemblySlowdown) ...slowdown.write(),
    'ContraptionInitialized': initialized,
    'Stalled': stalled,
    'StalledRecoveryTimer': stalledRecoveryTimer,
    if (initialized) ...{
      if (clientPacket)
        'ClientRockCutterAmount': centerMiningPositions.length
      else
        'OriginPositionSize': centerMiningPositions.length,
      if (!clientPacket) 'OriginPositions': _originPositions(),
      if (!clientPacket) 'NextAvailableIndex': nextAvailableIndex,
    },
  };

  List<Map<String, Object?>> _originPositions() => [
    for (var i = 0; i < centerMiningPositions.length; i++)
      {
        'x': centerMiningPositions[i].$1,
        'y': centerMiningPositions[i].$2,
        'z': centerMiningPositions[i].$3,
        'indexPosition': i,
      },
  ];

  /// `read(compound, registries, clientPacket)`
  /// (`BoreheadBearingBlockEntity.java:595`).
  void read(Map<String, Object?> compound, {required bool clientPacket}) {
    rotationSpeed = _float(compound['RotationSpeed']);

    disassemblySlowdown = _bool(compound['DisassemblySlowdown']);
    if (disassemblySlowdown) slowdown.read(compound);

    initialized = _bool(compound['ContraptionInitialized']);
    setStalled(_bool(compound['Stalled']));
    stalledRecoveryTimer = _int(compound['StalledRecoveryTimer']);
    if (!initialized) return;

    if (clientPacket) {
      clientRockCutters = _int(compound['ClientRockCutterAmount']);
      return;
    }

    final size = _int(compound['OriginPositionSize']);
    for (var i = 0; i < size; i++) {
      centerMiningPositions.add(vec3Zero);
    }

    final positions = compound['OriginPositions'];
    if (positions is List) {
      for (final entry in positions) {
        if (entry is! Map) continue;
        final index = _int(entry['indexPosition']);
        if (index < 0 || index >= centerMiningPositions.length) continue;
        centerMiningPositions[index] = (
          _float(entry['x']),
          _float(entry['y']),
          _float(entry['z']),
        );
      }
    }

    nextAvailableIndex = _int(compound['NextAvailableIndex']);
  }

  /// `handleAxisModification(direction)` (`BoreheadBearingBlockEntity.java:637`).
  static double handleAxisModification(Direction direction) =>
      direction.axisDirection.step.toDouble();

  static double _lerp(double delta, double start, double end) => start + delta * (end - start);
  static int _intFloor(double v) => v.floor();
  static int _int(Object? v) => v is num ? v.toInt() : 0;
  static double _float(Object? v) => v is num ? v.toDouble() : 0;
  static bool _bool(Object? v) => v is bool ? v : false;
}