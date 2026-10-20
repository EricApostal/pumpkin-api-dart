// `dev.simulated_team.simulated.util.assembly.SimAssemblyContraption`: the
// structure search the physics assembler, the swivel bearing and the heat map
// split use to collect the blocks that move into a sub-level.
//
// The Java class extends nothing but re-implements Create's contraption search,
// because it needs glue of its own (`HoneyGlueEntity`) and the block movement
// checks of Simulated. The port keeps that shape: the search walks the world
// through [SimAssemblyWorld], so it runs on the VM in tests, and the block rules
// are asked of the world (the plugin's adapter forwards to Create's
// `BlockMovementChecks`).
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.util.assembly.SimAssemblyContraption
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'dart:collection';

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart';
import 'package:create/src/contraptions/core/level.dart' show PushReaction;

import '../../config/sim_config_service.dart';
import 'sim_assembly_exception.dart';

/// A super glue box in the world.
final class SimGlueBox {
  /// The host entity id.
  final int id;

  /// The box, in world coordinates.
  final Aabb box;

  const SimGlueBox(this.id, this.box);

  /// `SuperGlueEntity.contains(pos)`: the block centre is inside the box.
  bool contains(Pos pos) => box.contains(pos.center);

  @override
  bool operator ==(Object other) => other is SimGlueBox && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A honey glue volume in the world.
final class HoneyGlueVolume {
  /// The host entity id.
  final int id;

  /// The box, in world coordinates.
  final Aabb box;

  const HoneyGlueVolume(this.id, this.box);

  /// `HoneyGlueEntity.contains(pos)`: the block centre is inside the box.
  bool contains(Pos pos) => box.contains(pos.center);

  @override
  bool operator ==(Object other) => other is HoneyGlueVolume && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// What the assembly search reads from the world.
///
/// The Java code reads a `Level` and asks Create's `BlockMovementChecks`; the
/// port asks the adapter, which forwards to the same checks.
abstract interface class SimAssemblyWorld {
  /// The block state at [pos].
  BState stateAt(Pos pos);

  /// `Level.isLoaded`.
  bool isLoaded(Pos pos);

  /// `Level.isOutsideBuildHeight`.
  bool isOutsideBuildHeight(Pos pos);

  /// `BlockMovementChecks.isMovementAllowed`.
  bool movementAllowed(BState state, Pos pos);

  /// `BlockMovementChecks.isBrittle`.
  bool isBrittle(BState state);

  /// `BlockMovementChecks.isBlockAttachedTowards`.
  bool isBlockAttachedTowards(BState state, Pos pos, Direction direction);

  /// `BlockMovementChecks.isNotSupportive`.
  bool isNotSupportive(BState state, Direction direction);

  /// `BlockState.getPistonPushReaction`.
  PushReaction pushReaction(BState state);

  /// `SimAssemblyService.canStickTo`.
  bool canStickTo(BState a, BState b);

  /// `SimBlockMovementChecks.addAdditionalBlocks`: the extra positions a block
  /// drags along (belt segments, pulleys).
  List<Pos> additionalBlocks(BState state, Pos pos) => const [];

  /// `ChainConveyorBlockEntity.notifyConnectedToValidate`.
  void notifyChainConveyor(Pos pos) {}

  /// The super glue boxes whose box intersects [area].
  List<SimGlueBox> superGluesIn(Aabb area);

  /// The honey glue volumes whose box intersects [area].
  List<HoneyGlueVolume> honeyGluesIn(Aabb area);

  /// Whether [state] is a swivel bearing (the search treats its plate as glued).
  bool isSwivelBearing(BState state);

  /// Moves a super glue box by [offset] after its blocks were assembled.
  void superGlueMoved(SimGlueBox glue, Pos offset);

  /// Moves a honey glue volume by [offset] after its blocks were assembled.
  void honeyGlueMoved(HoneyGlueVolume glue, Pos offset);

  /// Plays the "contraption stops" sound at [pos].
  void playDisassemblySound(Pos pos);
}

/// The 18 neighbours of a block that a contraption connects through: the six
/// faces and the twelve edges, but never the eight corners.
const List<(int, int, int)> assemblyOffsets = [
  (1, 0, 0),
  (-1, 0, 0),
  (0, 1, 0),
  (0, -1, 0),
  (0, 0, 1),
  (0, 0, -1),
  (1, 1, 0),
  (-1, -1, 0),
  (1, -1, 0),
  (-1, 1, 0),
  (1, 0, 1),
  (-1, 0, -1),
  (1, 0, -1),
  (-1, 0, 1),
  (0, 1, 1),
  (0, -1, -1),
  (0, -1, 1),
  (0, 1, -1),
];

/// `SuperGlueEntity.span(start, end)`: the box from the lower corner of [start]
/// to the upper corner of [end].
Aabb glueSpan(Pos start, Pos end) =>
    Aabb.between(start.toVec3(), end.toVec3()).expandTowards(1, 1, 1);

/// The structure search of Simulated's assemblers.
final class SimAssemblyContraption {
  /// The block that is never captured (the assembler itself), or `null`.
  final Pos? anchor;

  /// Whether a honey glue that encloses [anchor] is ignored.
  final bool ignoreEnclosingGlue;

  final Set<Pos> _blocks = {};
  final Set<SimGlueBox> _glueCache = {};
  final Set<HoneyGlueVolume> _honeyGlueCache = {};

  SimAssemblyContraption(this.anchor, {this.ignoreEnclosingGlue = false});

  /// The captured blocks.
  Set<Pos> get blocks => Set.unmodifiable(_blocks);

  /// The super glue boxes the search used.
  Set<SimGlueBox> get glues => Set.unmodifiable(_glueCache);

  /// The honey glue volumes the search used.
  Set<HoneyGlueVolume> get honeyGlues => Set.unmodifiable(_honeyGlueCache);

  /// `searchMovedStructure(level, pos)`.
  ///
  /// Throws [SimAssemblyException] for an unloaded chunk, an unmovable block or
  /// a structure over the configured block limit.
  void searchMovedStructure(SimAssemblyWorld world, Pos pos) {
    cacheInitialHoneyGlue(world, anchor, pos, ignoreEnclosingGlue);

    final frontier = ListQueue<Pos>();
    final visited = <Pos>{};

    if (!world.isBrittle(world.stateAt(pos))) frontier.add(pos);

    final maxBlocksMoved = SimConfigService.instance.server.assembly.maxBlocksMoved;
    for (var limit = maxBlocksMoved; limit > 0; limit--) {
      if (frontier.isEmpty) return;
      _moveBlock(world, frontier, visited);
    }
    // The frontier still had blocks after the whole budget: the structure is
    // larger than the config allows.
    throw SimAssemblyException.structureTooLarge(maxBlocksMoved);
  }

  /// `addInitialHoneyGlue`: caches the honey glue that holds [pos] (and, when
  /// given, [anchor]) before the search starts.
  void cacheInitialHoneyGlue(SimAssemblyWorld world, Pos? anchor, Pos pos, bool ignoreEnclosingGlue) {
    final range = SimConfigService.instance.server.assembly.honeyGlueRange;
    final area = glueSpan(pos, pos).inflate(range.toDouble());

    for (final glue in world.honeyGluesIn(area)) {
      if (anchor != null) {
        if (ignoreEnclosingGlue && glue.contains(anchor)) continue;
        if (!glue.contains(pos) && !glue.contains(anchor)) continue;
      } else {
        if (!glue.contains(pos)) continue;
      }
      _honeyGlueCache.add(glue);
    }
  }

  /// `checkAndCacheGlue`: whether [pos] and its neighbour in [offsetDir] are
  /// held together by super glue or honey glue.
  bool checkAndCacheGlue(SimAssemblyWorld world, Pos pos, (int, int, int) offsetDir) {
    final targetPos = (pos.$1 + offsetDir.$1, pos.$2 + offsetDir.$2, pos.$3 + offsetDir.$3);

    var inHoneyGlue = false;
    var containedByAnyHoneyGlue = false;
    for (final glue in _honeyGlueCache) {
      final firstContained = glue.contains(pos);
      final targetContained = glue.contains(targetPos);
      containedByAnyHoneyGlue |= firstContained;
      containedByAnyHoneyGlue |= targetContained;
      if (firstContained && targetContained) inHoneyGlue = true;
    }

    if (containedByAnyHoneyGlue) {
      final range = SimConfigService.instance.server.assembly.honeyGlueRange;
      for (final glue in world.honeyGluesIn(glueSpan(pos, targetPos).inflate(range.toDouble()))) {
        if (anchor != null && ignoreEnclosingGlue && glue.contains(anchor!)) continue;
        if (!glue.contains(pos) || !glue.contains(targetPos)) continue;
        _honeyGlueCache.add(glue);
        inHoneyGlue = true;
      }
    }

    for (final glue in _glueCache) {
      if (glue.contains(pos) && glue.contains(targetPos)) return true;
    }

    for (final glue in world.superGluesIn(glueSpan(pos, targetPos).inflate(16))) {
      if (!glue.contains(pos) || !glue.contains(targetPos)) continue;
      _glueCache.add(glue);
      return true;
    }

    return inHoneyGlue;
  }

  void _moveBlock(SimAssemblyWorld world, ListQueue<Pos> frontier, Set<Pos> visited) {
    final pos = frontier.removeFirst();
    visited.add(pos);

    if (world.isOutsideBuildHeight(pos)) return;
    if (!world.isLoaded(pos)) throw SimAssemblyException.unloadedChunk(pos);
    if (anchor != null && pos == anchor) return;

    final state = world.stateAt(pos);
    if (state.isAir) return;

    if (!world.movementAllowed(state, pos)) {
      throw SimAssemblyException.unmovableBlock(pos, state.key);
    }

    // A swivel bearing drags its plate: the plate may sit in a different glue
    // group, so the search adds it explicitly.
    if (world.isSwivelBearing(state)) {
      final facing = state.dir('facing') ?? Direction.north;
      final attachPos = (pos.$1 + facing.stepX, pos.$2 + facing.stepY, pos.$3 + facing.stepZ);
      cacheInitialHoneyGlue(world, pos, attachPos, true);
      frontier.add(attachPos);
    }

    world.notifyChainConveyor(pos);

    // Both halves of a double chest move together.
    if (state.has('type') && state.has('facing') && state['type'] != 'single') {
      final facing = state.dir('facing') ?? Direction.north;
      final side = state['type'] == 'left' ? facing.clockWise : facing.counterClockWise;
      final attached = (pos.$1 + side.stepX, pos.$2 + side.stepY, pos.$3 + side.stepZ);
      if (!visited.contains(attached)) frontier.add(attached);
    }

    // Cart assemblers attach to the block below them.
    final posDown = pos.below;
    if (!visited.contains(posDown) && world.stateAt(posDown).key == 'create:cart_assembler') {
      frontier.add(posDown);
    }

    // Blocks that drag extra positions along (belts, pulleys).
    for (final extra in world.additionalBlocks(state, pos)) {
      if (!visited.contains(extra)) frontier.add(extra);
    }

    for (final offset in assemblyOffsets) {
      final offsetPos = (pos.$1 + offset.$1, pos.$2 + offset.$2, pos.$3 + offset.$3);
      if (anchor != null && offsetPos == anchor) continue;

      final blockState = world.stateAt(offsetPos);
      if (!world.movementAllowed(blockState, offsetPos)) continue;

      final wasVisited = visited.contains(offsetPos);
      final faceHasGlue = checkAndCacheGlue(world, pos, offset);

      final absTotal = offset.$1.abs() + offset.$2.abs() + offset.$3.abs();
      final direction = absTotal == 1 ? _nearestDirection(offset) : null;

      var blockAttachedTowardsFace = direction != null &&
          world.isBlockAttachedTowards(blockState, offsetPos, direction.opposite);

      final brittle = world.isBrittle(blockState);
      var canStick = !brittle && world.canStickTo(state, blockState) && world.canStickTo(blockState, state);

      if (canStick) {
        if (world.pushReaction(state) == PushReaction.pushOnly ||
            world.pushReaction(blockState) == PushReaction.pushOnly) {
          canStick = false;
        }

        if (direction != null) {
          if (world.isNotSupportive(state, direction)) canStick = false;
          if (world.isNotSupportive(blockState, direction.opposite)) canStick = false;
        }
      }

      if (!wasVisited && (canStick || blockAttachedTowardsFace || faceHasGlue)) {
        frontier.add(offsetPos);
      }
    }

    _blocks.add(pos);
    final maxBlocksMoved = SimConfigService.instance.server.assembly.maxBlocksMoved;
    if (_blocks.length > maxBlocksMoved) {
      throw SimAssemblyException.structureTooLarge(maxBlocksMoved);
    }
  }

  static Direction _nearestDirection((int, int, int) offset) {
    for (final direction in Direction.values) {
      if (direction.stepX == offset.$1 &&
          direction.stepY == offset.$2 &&
          direction.stepZ == offset.$3) {
        return direction;
      }
    }
    return Direction.north;
  }
}
