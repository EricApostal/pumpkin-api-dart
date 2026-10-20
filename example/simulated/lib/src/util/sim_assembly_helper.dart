// `dev.simulated_team.simulated.util.SimAssemblyHelper`: the two operations that
// move blocks between the world and a sub-level.
//
// `assembleFromSingleBlock` searches the structure with [SimAssemblyContraption]
// and hands the blocks to Sable's `SubLevelAssemblyHelper.assembleBlocks`;
// `disassembleSubLevel` walks a sub-level's plot, moves its blocks back through
// an [AssemblyTransform] and drops the entities of the plot into the world.
//
// Java reads and writes a `ServerLevel` directly. The port goes through
// [SimAssemblyWorld] for the structure search, Sable's block host for the block
// moves and [SimAssemblyEntities] for the entities, so the whole thing runs on
// the VM in tests.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.util.SimAssemblyHelper
import 'dart:math' as math;

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:pumpkin_api/pumpkin_api_core.dart' show Vec3;
import 'package:sable/sable.dart';

import 'assembly/sim_assembly_contraption.dart';
import 'assembly/sim_assembly_exception.dart';

/// An entity the assembly moves or replaces.
final class SimAssemblyEntityRef {
  /// The host entity id.
  final int id;

  /// The entity's box, in world coordinates.
  final Aabb box;

  /// `Entity.position()`.
  final Vec3 position;

  /// `Entity.getYRot()`.
  final double yRot;

  /// Whether the entity is a glue box of either kind.
  final SimAssemblyEntityKind kind;

  const SimAssemblyEntityRef(
    this.id,
    this.box,
    this.position, {
    this.yRot = 0,
    this.kind = SimAssemblyEntityKind.other,
  });
}

/// What the disassembly needs from the entities of the plot.
abstract interface class SimAssemblyEntities {
  /// Every entity whose box intersects [area], in world coordinates.
  List<SimAssemblyEntityRef> entitiesIn(Aabb area);

  /// `entity.remove(KILLED)`.
  void remove(SimAssemblyEntityRef entity);

  /// `entity.setPos`, and the y rotation the structure transform implies.
  void move(SimAssemblyEntityRef entity, Vec3 position, double yRot);

  /// `level.addFreshEntity(new SuperGlueEntity(level, box))`.
  void spawnSuperGlue(Aabb box);

  /// `level.addFreshEntity(new HoneyGlueEntity(level, box))`, then
  /// `setBoundsAndSync`.
  void spawnHoneyGlue(Aabb box);
}

/// A host that has no entities (tests, a level without them).
final class NoSimAssemblyEntities implements SimAssemblyEntities {
  const NoSimAssemblyEntities();

  @override
  List<SimAssemblyEntityRef> entitiesIn(Aabb area) => const [];

  @override
  void remove(SimAssemblyEntityRef entity) {}

  @override
  void move(SimAssemblyEntityRef entity, Vec3 position, double yRot) {}

  @override
  void spawnSuperGlue(Aabb box) {}

  @override
  void spawnHoneyGlue(Aabb box) {}
}

/// The result of an assembly: the new sub-level and the offset from the anchor
/// block to the plot centre.
final class SimAssemblyResult {
  final SubLevel subLevel;
  final Pos offset;

  const SimAssemblyResult(this.subLevel, this.offset);
}

/// The assembly operations of the physics assembler and the swivel bearing.
abstract final class SimAssemblyHelper {
  /// `rotationFrom90DegRots(rots)`: the quarter turn for a number of 90° turns
  /// (any integer, including negative ones).
  static Rotation rotationFrom90DegRots(int rots) => switch (rots % 4 < 0 ? rots % 4 + 4 : rots % 4) {
    0 => Rotation.none,
    1 => Rotation.counterclockwise90,
    2 => Rotation.clockwise180,
    _ => Rotation.clockwise90,
  };

  /// `assembleFromSingleBlock(level, selfPos, toAssemble, includeStart, includeEncasingGlue)`.
  ///
  /// Returns `null` when there is nothing to assemble.
  static SimAssemblyResult? assembleFromSingleBlock(
    SimAssemblyWorld world,
    SableLevel level,
    Pos selfPos,
    Pos toAssemble, {
    bool includeStart = true,
    bool includeEncasingGlue = true,
  }) {
    if (world.stateAt(toAssemble).isAir) return null;

    final contraption = SimAssemblyContraption(
      includeStart ? null : selfPos,
      ignoreEnclosingGlue: !includeEncasingGlue,
    );
    contraption.searchMovedStructure(world, toAssemble);

    final blocks = contraption.blocks;
    if (blocks.isEmpty) return null;

    final bounds = BoundingBox3i.fromPositions(blocks)!;
    final anchor = blocks.first;

    final subLevel = SubLevelAssemblyHelper.assembleBlocks(level, anchor, blocks, bounds);
    final offset = _offsetOf(subLevel.getPlot().getCenterBlock(), anchor);

    // The glue boxes follow the blocks into their new place.
    for (final glue in contraption.glues) {
      world.superGlueMoved(glue, offset);
    }
    for (final glue in contraption.honeyGlues) {
      world.honeyGlueMoved(glue, offset);
    }

    return SimAssemblyResult(subLevel, offset);
  }

  /// `disassembleSubLevel(level, toDisassemble, subLevelAnchor, goal, rotation, playSound)`.
  ///
  /// Moves every block of [toDisassemble]'s plot back into [level] at [goal],
  /// rotated by [rotation], and moves the entities of the plot with them.
  static void disassembleSubLevel(
    SimAssemblyWorld world,
    SableLevel level,
    SubLevel toDisassemble,
    Pos subLevelAnchor,
    Pos goal,
    Rotation rotation, {
    SimAssemblyEntities entities = const NoSimAssemblyEntities(),
    bool playSound = true,
  }) {
    if (playSound) world.playDisassemblySound(subLevelAnchor);

    final plot = toDisassemble.getPlot();
    final plotBounds = BoundingBox3i.copy(plot.getBoundingBox());

    final transform = AssemblyTransform(
      subLevelAnchor,
      goal,
      rotation == Rotation.none ? 0 : 4 - rotation.quarterTurns,
      rotation,
      level,
    );

    final host = SubLevelAssemblyHelper.blockHostOf(level);
    final blocks = <Pos>[];
    for (final chunk in plot.getLoadedChunks()) {
      final localBounds = chunk.getBoundingBox();
      if (localBounds == null) continue;

      final minBlockX = chunk.getPos().$1 << 4;
      final minBlockZ = chunk.getPos().$2 << 4;
      for (var x = localBounds.minX; x <= localBounds.maxX; x++) {
        for (var y = localBounds.minY; y <= localBounds.maxY; y++) {
          for (var z = localBounds.minZ; z <= localBounds.maxZ; z++) {
            final pos = (x + minBlockX, y, z + minBlockZ);
            if (!host.blockStateAt(pos.$1, pos.$2, pos.$3).isAir) blocks.add(pos);
          }
        }
      }
    }

    _moveEntities(entities, transform, plot);

    if (blocks.isNotEmpty) {
      (plot as ServerLevelPlot).kickAllEntities();
      SubLevelAssemblyHelper.moveBlocks(level, transform, blocks);
    }

    SubLevelAssemblyHelper.moveTrackingPoints(level, plotBounds, null, transform);
  }

  static void _moveEntities(
    SimAssemblyEntities entities,
    AssemblyTransform transform,
    LevelPlot plot,
  ) {
    final bounds = plot.getBoundingBox();
    final area = Aabb(
      bounds.minX.toDouble(),
      bounds.minY.toDouble(),
      bounds.minZ.toDouble(),
      bounds.maxX + 1.0,
      bounds.maxY + 1.0,
      bounds.maxZ + 1.0,
    );

    for (final entity in entities.entitiesIn(area)) {
      final box = entity.box;
      final newBox = Aabb.between(
        _apply(transform, (box.minX, box.minY, box.minZ)),
        _apply(transform, (box.maxX, box.maxY, box.maxZ)),
      );

      switch (entity.kind) {
        case SimAssemblyEntityKind.superGlue:
          entities.remove(entity);
          entities.spawnSuperGlue(newBox);
        case SimAssemblyEntityKind.honeyGlue:
          entities.remove(entity);
          entities.spawnHoneyGlue(newBox);
        case SimAssemblyEntityKind.other:
          entities.move(
            entity,
            _apply(transform, entity.position),
            entity.yRot + transform.rotationDegrees,
          );
      }
    }
  }

  /// `disassembleAndAddCreateContraptions`: the heat map's split listener uses
  /// this to break Create contraptions apart when a sub-level splits.
  ///
  /// HOST GAP: Create's contraption entities are driven by the create package's
  /// compat layer; the plugin passes the hook to
  /// [registerSplitListener].
  static void registerSplitListener(
    void Function(SimAssemblyWorld world, BoundingBox3ic bounds, Set<Pos> blocks) listener,
  ) {
    _splitListeners.add(listener);
  }

  /// Removes every split listener (tests).
  static void clearSplitListeners() => _splitListeners.clear();

  static final List<void Function(SimAssemblyWorld, BoundingBox3ic, Set<Pos>)> _splitListeners = [];

  /// `addSplitBlocks`: tells the listeners that [blocks] of [bounds] split off.
  static void notifySplit(SimAssemblyWorld world, BoundingBox3ic bounds, Set<Pos> blocks) {
    for (final listener in _splitListeners) {
      listener(world, bounds, blocks);
    }
  }

  static Vec3 _apply(AssemblyTransform transform, Vec3 v) {
    final out = transform.applyVector(Vector3d(v.$1, v.$2, v.$3));
    return (out.x, out.y, out.z);
  }

  /// `subLevel.getPlot().getCenterBlock().subtract(anchor)`.
  static Pos _offsetOf(Pos center, Pos anchor) => (center.$1 - anchor.$1, center.$2 - anchor.$2, center.$3 - anchor.$3);
}

/// Which kind of entity the disassembly is looking at.
enum SimAssemblyEntityKind { superGlue, honeyGlue, other }

/// The rotation of an [AssemblyTransform] in radians.
extension AssemblyTransformRotation on AssemblyTransform {
  /// The rotation applied to entity y rotations, in radians.
  double get rotationDegrees => angle * math.pi / 2.0;
}
