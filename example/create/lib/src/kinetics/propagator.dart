// `RotationPropagator`: how speed spreads through connected kinetic blocks, who
// wins when sources meet, and what breaks (pure). A direct port of Create's
// `RotationPropagator`; block states come from the [KineticLevel].
import 'dart:math' as math;

import 'block_defs.dart';
import 'geometry.dart';
import 'node.dart';

abstract final class RotationPropagator {
  static const int maxFlickerScore = 128;

  /// The change in rotation between two attached kinetic entities: 1 for an
  /// axis connection, -1 for a 1:1 gear connection, 0 when they are not connected.
  static double getRotationSpeedModifier(KineticNode from, KineticNode to) {
    final level = from.level;
    final stateFrom = from.blockState;
    final stateTo = to.blockState;

    final definitionFrom = level.blocks.defFor(stateFrom);
    final definitionTo = level.blocks.defFor(stateTo);
    if (definitionFrom == null || definitionTo == null) return 0;

    final diff = to.kpos - from.kpos;
    final direction = Dir.approximateNearest(diff.x, diff.y, diff.z);

    var alignedAxes = true;
    for (final axis in KAxis.values) {
      if (axis != direction.axis) {
        if (diff.choose(axis) != 0) alignedAxes = false;
      }
    }

    final connectedByAxis =
        alignedAxes &&
        definitionFrom.hasShaftTowards(stateFrom, direction) &&
        definitionTo.hasShaftTowards(stateTo, direction.opposite);

    final connectedByGears = definitionFrom.isSmallCog && definitionTo.isSmallCog;

    final custom = from.propagateRotationTo(to, stateFrom, stateTo, diff, connectedByAxis, connectedByGears);
    if (custom != 0) return custom;

    // KAxis <-> KAxis
    if (connectedByAxis) {
      var axisModifier = _getAxisModifier(to, direction.opposite);
      if (axisModifier != 0) axisModifier = 1 / axisModifier;
      return _getAxisModifier(from, direction) * axisModifier;
    }

    // Attached encased belts
    if (level.blocks.isChainDrive(stateFrom) && level.blocks.isChainDrive(stateTo)) {
      final connected = areChainBlocksConnected(stateFrom, stateTo, direction);
      return connected ? chainRotationSpeedModifier(from, to) : 0;
    }

    // Large gear <-> large gear
    if (_isLargeToLargeGear(level, stateFrom, stateTo, diff)) {
      final sourceAxis = stateFrom.axisOf('axis')!;
      final targetAxis = stateTo.axisOf('axis')!;
      final sourceAxisDiff = diff.choose(sourceAxis);
      final targetAxisDiff = diff.choose(targetAxis);
      return (sourceAxisDiff > 0) ^ (targetAxisDiff > 0) ? -1 : 1;
    }

    // Gear <-> large gear
    if (definitionFrom.isLargeCog && definitionTo.isSmallCog) {
      if (_isLargeToSmallCog(stateFrom, stateTo, definitionTo, diff)) return -2;
    }
    if (definitionTo.isLargeCog && definitionFrom.isSmallCog) {
      if (_isLargeToSmallCog(stateTo, stateFrom, definitionFrom, diff)) return -.5;
    }

    // Gear <-> gear
    if (connectedByGears) {
      if (diff.manhattan != 1) return 0;
      if (definitionTo.isLargeCog) return 0;
      if (direction.axis == definitionFrom.rotationAxis(stateFrom)) return 0;
      if (definitionFrom.rotationAxis(stateFrom) == definitionTo.rotationAxis(stateTo)) return -1;
    }

    return 0;
  }

  /// `ChainDriveBlock.areBlocksConnected`.
  static bool areChainBlocksConnected(KState state, KState other, Dir facing) {
    final part = state['part'];
    final connectionAxis = chainConnectionAxis(state);
    final otherConnectionAxis = chainConnectionAxis(other);

    if (otherConnectionAxis != connectionAxis) return false;
    if (facing.axis != connectionAxis) return false;
    if (facing.isPositive && (part == 'middle' || part == 'start')) return true;
    if (!facing.isPositive && (part == 'middle' || part == 'end')) return true;
    return false;
  }

  /// `ChainDriveBlock.getConnectionAxis`.
  static KAxis chainConnectionAxis(KState state) {
    final axis = state.axisOf('axis') ?? KAxis.y;
    final connectionAlongFirst = state.flag('axis_along_first');
    return connectionAlongFirst ? (axis == KAxis.x ? KAxis.y : KAxis.x) : (axis == KAxis.z ? KAxis.y : KAxis.z);
  }

  /// `ChainDriveBlock.getRotationSpeedModifier`.
  static double chainRotationSpeedModifier(KineticNode from, KineticNode to) {
    var fromMod = 1.0;
    var toMod = 1.0;
    if (from case final ChainModifierNode f) fromMod = f.chainModifier;
    if (to case final ChainModifierNode t) toMod = t.chainModifier;
    return fromMod / toMod;
  }

  static double _getConveyedSpeed(KineticNode from, KineticNode to) {
    final stateFrom = from.blockState;
    final stateTo = to.blockState;
    final level = from.level;

    // Rotation speed controller <-> large gear
    if (_isLargeCogToSpeedController(level, stateFrom, stateTo, to.kpos - from.kpos)) {
      return speedControllerConveyedSpeed(from, to, true);
    }
    if (_isLargeCogToSpeedController(level, stateTo, stateFrom, from.kpos - to.kpos)) {
      return speedControllerConveyedSpeed(to, from, false);
    }

    final rotationSpeedModifier = getRotationSpeedModifier(from, to);
    return from.theoreticalSpeed * rotationSpeedModifier;
  }

  /// `SpeedControllerBlockEntity.getConveyedSpeed`.
  static double speedControllerConveyedSpeed(KineticNode cogWheel, KineticNode controller, bool targetingController) {
    if (controller is! SpeedControllerNode) return 0;

    final speed = controller.theoreticalSpeed;
    final wheelSpeed = cogWheel.theoreticalSpeed;
    final desiredOutputSpeed = speedControllerDesiredOutput(cogWheel, controller, targetingController);

    final compareSpeed = targetingController ? speed : wheelSpeed;
    if (desiredOutputSpeed >= 0 && compareSpeed >= 0) return math.max(desiredOutputSpeed, compareSpeed);
    if (desiredOutputSpeed < 0 && compareSpeed < 0) return math.min(desiredOutputSpeed, compareSpeed);
    return desiredOutputSpeed;
  }

  /// `SpeedControllerBlockEntity.getDesiredOutputSpeed`.
  static double speedControllerDesiredOutput(KineticNode cogWheel, KineticNode controller, bool targetingController) {
    final targetSpeed = (controller as SpeedControllerNode).targetSpeedValue.toDouble();
    final speed = controller.theoreticalSpeed;
    final wheelSpeed = cogWheel.theoreticalSpeed;

    if (targetSpeed == 0) return 0;
    if (targetingController && wheelSpeed == 0) return 0;
    if (!controller.hasSource) {
      if (targetingController) return targetSpeed;
      return 0;
    }

    final wheelPowersController = controller.source == cogWheel.kpos;

    if (wheelPowersController) {
      if (targetingController) return targetSpeed;
      return wheelSpeed;
    }

    if (targetingController) return speed;
    return targetSpeed;
  }

  static bool _isLargeToLargeGear(KineticLevel level, KState from, KState to, KPos diff) {
    if (!level.blocks.isLargeCog(from) || !level.blocks.isLargeCog(to)) return false;
    final fromAxis = from.axisOf('axis');
    final toAxis = to.axisOf('axis');
    if (fromAxis == null || toAxis == null || fromAxis == toAxis) return false;
    for (final axis in KAxis.values) {
      final axisDiff = diff.choose(axis);
      if (axis == fromAxis || axis == toAxis) {
        if (axisDiff == 0) return false;
      } else if (axisDiff != 0) {
        return false;
      }
    }
    return true;
  }

  static double _getAxisModifier(KineticNode be, Dir direction) {
    if (!(be.hasSource || be.isSource)) return 1;
    return be.shaftHalvesModifier(direction);
  }

  static bool _isLargeToSmallCog(KState from, KState to, KineticBlockDef defTo, KPos diff) {
    final axisFrom = from.axisOf('axis');
    if (axisFrom == null) return false;
    if (axisFrom != defTo.rotationAxis(to)) return false;
    if (diff.choose(axisFrom) != 0) return false;
    for (final axis in KAxis.values) {
      if (axis == axisFrom) continue;
      if (diff.choose(axis).abs() != 1) return false;
    }
    return true;
  }

  static bool _isLargeCogToSpeedController(KineticLevel level, KState from, KState to, KPos diff) {
    if (!level.blocks.isLargeCog(from) || !to.isCreate('rotation_speed_controller')) return false;
    if (diff != const KPos(0, -1, 0)) return false;
    final axis = from.axisOf('axis');
    if (axis == null || axis.isVertical) return false;
    if (to.axisOf('axis') == axis) return false;
    return true;
  }

  /// Inserts the added position into the kinetic network.
  static void handleAdded(KineticLevel level, KPos pos, KineticNode addedTE) {
    if (!level.isLoaded(pos)) return;
    _propagateNewSource(addedTE);
  }

  /// Searches for sourceless networks attached to [currentTE] and updates them.
  static void _propagateNewSource(KineticNode currentTE) {
    final pos = currentTE.kpos;
    final level = currentTE.level;
    final maxSpeed = level.settings.maxRotationSpeed;

    for (final neighbourTE in _getConnectedNeighbours(currentTE)) {
      final speedOfCurrent = currentTE.theoreticalSpeed;
      final speedOfNeighbour = neighbourTE.theoreticalSpeed;
      final newSpeed = _getConveyedSpeed(currentTE, neighbourTE);
      final oppositeSpeed = _getConveyedSpeed(neighbourTE, currentTE);

      if (newSpeed == 0 && oppositeSpeed == 0) continue;

      final incompatible = newSpeed.sign != speedOfNeighbour.sign && (newSpeed != 0 && speedOfNeighbour != 0);

      final tooFast = newSpeed.abs() > maxSpeed || oppositeSpeed.abs() > maxSpeed;
      // Check for both the new speed and the opposite speed, just in case

      final speedChangedTooOften = currentTE.flickerScore > maxFlickerScore;
      if (tooFast || speedChangedTooOften) {
        level.destroyBlock(pos);
        return;
      }

      // Opposite directions
      if (incompatible) {
        level.destroyBlock(pos);
        return;

        // Same direction: overpower the slower speed
      } else {
        // Neighbour faster, overpower the incoming tree
        if (oppositeSpeed.abs() > speedOfCurrent.abs()) {
          final prevSpeed = currentTE.speed;
          currentTE.setSource(neighbourTE.kpos);
          currentTE.setSpeed(_getConveyedSpeed(neighbourTE, currentTE));
          currentTE.onSpeedChanged(prevSpeed);
          currentTE.sendData();

          _propagateNewSource(currentTE);
          return;
        }

        // Current faster, overpower the neighbours' tree
        if (newSpeed.abs() >= speedOfNeighbour.abs()) {
          // Do not overpower you own network -> cycle
          if (!currentTE.hasNetwork || currentTE.network == neighbourTE.network) {
            final epsilon = speedOfNeighbour.abs() / 256 / 256;
            if (newSpeed.abs() > speedOfNeighbour.abs() + epsilon) level.destroyBlock(pos);
            continue;
          }

          if (currentTE.hasSource && currentTE.source == neighbourTE.kpos) currentTE.removeSource();

          final prevSpeed = neighbourTE.speed;
          neighbourTE.setSource(currentTE.kpos);
          neighbourTE.setSpeed(_getConveyedSpeed(currentTE, neighbourTE));
          neighbourTE.onSpeedChanged(prevSpeed);
          neighbourTE.sendData();
          _propagateNewSource(neighbourTE);
          continue;
        }
      }

      if ((neighbourTE.theoreticalSpeed - newSpeed).abs() <= 1e-4) continue;

      final prevSpeed = neighbourTE.speed;
      neighbourTE.setSpeed(newSpeed);
      neighbourTE.setSource(currentTE.kpos);
      neighbourTE.onSpeedChanged(prevSpeed);
      neighbourTE.sendData();
      _propagateNewSource(neighbourTE);
    }
  }

  /// Removes the given entity from the network.
  static void handleRemoved(KineticLevel level, KPos pos, KineticNode? removedBE) {
    if (removedBE == null) return;
    if (removedBE.theoreticalSpeed == 0) return;

    for (final neighbourPos in _getPotentialNeighbourLocations(removedBE)) {
      final neighbourState = level.stateAt(neighbourPos);
      if (level.blocks.defFor(neighbourState) == null) continue;
      final neighbourBE = level.nodeAt(neighbourPos);
      if (neighbourBE == null) continue;

      if (!neighbourBE.hasSource || neighbourBE.source != pos) continue;

      _propagateMissingSource(neighbourBE);
    }
  }

  /// Clears the entire subnetwork depending on [updateTE] and finds a new source.
  static void _propagateMissingSource(KineticNode updateTE) {
    final level = updateTE.level;

    final potentialNewSources = <KineticNode>[];
    final frontier = <KPos>[updateTE.kpos];
    final missingSource = updateTE.hasSource ? updateTE.source : null;

    while (frontier.isNotEmpty) {
      final pos = frontier.removeAt(0);
      final currentBE = level.nodeAt(pos);
      if (currentBE == null) continue;

      currentBE.removeSource();
      currentBE.sendData();

      for (final neighbourBE in _getConnectedNeighbours(currentBE)) {
        if (neighbourBE.kpos == missingSource) continue;
        if (!neighbourBE.hasSource) continue;

        if (neighbourBE.source != pos) {
          potentialNewSources.add(neighbourBE);
          continue;
        }

        if (neighbourBE.isSource) potentialNewSources.add(neighbourBE);

        frontier.add(neighbourBE.kpos);
      }
    }

    for (final newSource in potentialNewSources) {
      if (newSource.hasSource || newSource.isSource) {
        _propagateNewSource(newSource);
        return;
      }
    }
  }

  static KineticNode? _findConnectedNeighbour(KineticNode currentTE, KPos neighbourPos) {
    final level = currentTE.level;
    final neighbourState = level.stateAt(neighbourPos);
    if (level.blocks.defFor(neighbourState) == null) return null;
    final neighbourKBE = level.nodeAt(neighbourPos);
    if (neighbourKBE == null) return null;
    if (level.blocks.defFor(neighbourKBE.blockState) == null) return null;
    if (!isConnected(currentTE, neighbourKBE) && !isConnected(neighbourKBE, currentTE)) return null;
    return neighbourKBE;
  }

  static bool isConnected(KineticNode from, KineticNode to) {
    final stateFrom = from.blockState;
    final stateTo = to.blockState;
    return _isLargeCogToSpeedController(from.level, stateFrom, stateTo, to.kpos - from.kpos) ||
        getRotationSpeedModifier(from, to) != 0 ||
        from.isCustomConnection(to, stateFrom, stateTo);
  }

  static List<KineticNode> _getConnectedNeighbours(KineticNode be) {
    final neighbours = <KineticNode>[];
    for (final neighbourPos in _getPotentialNeighbourLocations(be)) {
      final neighbourBE = _findConnectedNeighbour(be, neighbourPos);
      if (neighbourBE == null) continue;
      neighbours.add(neighbourBE);
    }
    return neighbours;
  }

  static List<KPos> _getPotentialNeighbourLocations(KineticNode be) {
    final neighbours = <KPos>[];
    final blockPos = be.kpos;
    final level = be.level;

    if (!level.isLoaded(blockPos)) return neighbours;

    for (final facing in Dir.values) {
      final relative = blockPos.relative(facing);
      if (level.isLoaded(relative)) neighbours.add(relative);
    }

    final blockState = be.blockState;
    final block = level.blocks.defFor(blockState);
    if (block == null) return neighbours;
    return be.addPropagationLocations(block, blockState, neighbours);
  }
}
