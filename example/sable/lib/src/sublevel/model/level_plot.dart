// `dev.ryanhcode.sable.sublevel.plot.LevelPlot`: an allocated and reserved space
// in a level belonging to a sub-level, holding its own chunk grid.
//
// The plot yard lives at a distant origin (see `SubLevelContainer.defaultOrigin`)
// so sub-level blocks never collide with real world blocks. A plot is
// `1 << logSize` chunks on a side; chunk coordinates inside the plot are
// *local* (0..side-1) and map to *global* yard coordinates with a shift.
//
// Everything in this file is pure: the chunk objects come from
// `PlotChunkHost`, and the light engine (the one genuinely host-bound piece of
// the Java class) is abstract.
//
// Pure: no host imports.
//
// create's pure helpers (positions, `Aabb`, `BlockBounds`) are not exported from
// its public barrel yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart';
import '../math/bounding_box.dart';
import '../api/block_entity_hooks.dart';
import '../host/sub_level_host.dart';
import 'plot_chunk_holder.dart';
import 'sub_level.dart';
import 'sub_level_container.dart';

/// An allocated & reserved space in a level belonging to a [SubLevel], holding
/// its own chunk grid.
abstract class LevelPlot {
  /// The minimum chunk X and Z coordinates of the plot, in units of
  /// `1 << logSize` chunks.
  ///
  /// For example a plot with `pos = (0, 0)` and a log size of 4 has its chunks
  /// in the range `[0, 16)`.
  final (int, int) plotPos;

  /// The plot grid containing this plot.
  final SubLevelContainer container;

  /// The log_2 of the side length of a plot, in chunks.
  final int logSize;

  /// The chunk storage for this plot, indexed by `z << logSize | x`.
  final List<PlotChunkHolder?> _chunks;

  /// The sub-level using this plot.
  final SubLevel subLevel;

  /// All loaded chunk holders in this plot.
  final List<PlotChunkHolder> loadedChunks = [];

  /// All block entity actors within this plot, by position.
  final Map<Pos, BlockEntitySubLevelActor> blockEntityActors = {};

  /// All block entity reaction wheels within this plot, by position.
  final Map<Pos, BlockEntitySubLevelReactionWheel> blockEntityReactionWheels = {};

  /// If the plot should expand and add new chunks when blocks reach the edge of
  /// existing chunks.
  bool expandPlotIfNecessary = true;

  /// The local, block-aligned, inclusive bounding box of this sub-level.
  BoundingBox3i? localBounds;

  /// The biome for the whole plot (`minecraft:plains`).
  String biome = 'minecraft:plains';

  /// Creates a new plot at the given plot coordinate.
  ///
  /// [x] and [z] are the global plot coordinates, in units of
  /// `1 << logSize` chunks.
  LevelPlot(this.container, int x, int z, this.logSize, this.subLevel)
    : plotPos = (x, z),
      _chunks = List<PlotChunkHolder?>.filled((1 << logSize) * (1 << logSize), null);

  /// Ticks this plot (the Java class runs lighting updates here; the port has
  /// no plot light engine yet).
  void tick() {}

  /// The center block position in the plot.
  Pos getCenterBlock() {
    final centerChunk = getCenterChunk();
    final level = subLevel.level;
    return (
      (centerChunk.$1 << 4) + 8,
      (level.minY + level.maxY) ~/ 2,
      (centerChunk.$2 << 4) + 8,
    );
  }

  /// The lighting engine of this plot, or `null` when it has none.
  ///
  /// Server sub-levels have their own light engine in Java; Pumpkin does not
  /// expose a per-plot light engine to plugins, so this is a HOST GAP in
  /// `ServerLevelPlot`.
  Object? getLightEngine();

  /// Adds a chunk at the given *global* chunk position.
  void newChunk((int, int) pos, PlotChunk chunk, bool initializeLighting) {
    final local = toLocal(pos);
    if (getChunkHolder(local) != null) {
      throw StateError('Chunk already exists at ${pos.$1}, ${pos.$2}');
    }
    final holder = PlotChunkHolder.create(chunk, pos);
    addChunkHolder(local, holder, initializeLighting);
  }

  /// Adds a new, empty chunk at the given global chunk position and initializes
  /// lighting for it.
  ///
  /// HOST GAP: creating a chunk needs the host's chunk factory; see
  /// [PlotChunkHost.createEmptyChunk].
  void newEmptyChunk((int, int) pos) {
    final chunk = container.chunkHost.createEmptyChunk(pos.$1, pos.$2);
    newChunk(pos, chunk, true);
  }

  /// The sub-level using this plot.
  SubLevel getSubLevel() => subLevel;

  /// The chunk host of the level this plot belongs to.
  PlotChunkHost get chunkHost => container.chunkHost;

  /// Whether the point is inside the plot (x/z only).
  bool contains(double x, double z) {
    final logBlockSize = logSize + 4;
    return x >= (plotPos.$1 << logBlockSize) &&
        x < ((plotPos.$1 + 1) << logBlockSize) &&
        z >= (plotPos.$2 << logBlockSize) &&
        z < ((plotPos.$2 + 1) << logBlockSize);
  }

  /// The minimum chunk position of the plot (global).
  (int, int) getChunkMin() => (plotPos.$1 << logSize, plotPos.$2 << logSize);

  /// The maximum chunk position of the plot (global, inclusive).
  (int, int) getChunkMax() => (((plotPos.$1 + 1) << logSize) - 1, ((plotPos.$2 + 1) << logSize) - 1);

  /// Whether the global chunk is within this plot.
  bool containsChunk((int, int) chunk) =>
      (chunk.$1 >> logSize) == plotPos.$1 && (chunk.$2 >> logSize) == plotPos.$2;

  /// The local chunk position inside the plot for a global chunk position.
  (int, int) toLocal((int, int) global) =>
      (global.$1 - (plotPos.$1 << logSize), global.$2 - (plotPos.$2 << logSize));

  /// The global chunk position for a local chunk position inside the plot.
  (int, int) toGlobal((int, int) local) =>
      (local.$1 + (plotPos.$1 << logSize), local.$2 + (plotPos.$2 << logSize));

  /// The index of a local chunk in the plot's chunk array
  /// (`local.z << logSize | local.x`).
  int indexOf((int, int) local) => (local.$2 << logSize) | local.$1;

  /// Whether the local chunk coordinates are inside the plot.
  bool hasLocal((int, int) local) =>
      local.$1 >= 0 && local.$1 < (1 << logSize) && local.$2 >= 0 && local.$2 < (1 << logSize);

  /// The chunk holder at the local position in the plot.
  PlotChunkHolder? getChunkHolder((int, int) local) {
    if (!hasLocal(local)) return null;
    return _chunks[indexOf(local)];
  }

  /// Sets a chunk at the local position in the plot.
  void addChunkHolder((int, int) localChunkPos, PlotChunkHolder holder, bool initializeLighting) {
    if (!hasLocal(localChunkPos)) {
      throw ArgumentError('Chunk ${localChunkPos.$1}, ${localChunkPos.$2} is outside the plot');
    }
    loadedChunks.add(holder);
    _chunks[indexOf(localChunkPos)] = holder;
    updateBoundingBox();
  }

  /// The chunk at the local position in the plot, or `null`.
  PlotChunk? getChunk((int, int) local) => getChunkHolder(local)?.chunk;

  /// The chunk at the global position in the center of the plot.
  (int, int) getCenterChunk() =>
      ((plotPos.$1 << logSize) + (1 << (logSize - 1)), (plotPos.$2 << logSize) + (1 << (logSize - 1)));

  /// Updates and rebuilds the block bounding box of this plot.
  void updateBoundingBox() {
    if (subLevel.level.isClientSide) return;

    final previousBounds = localBounds;
    localBounds = null;

    for (final holder in loadedChunks) {
      final chunkLocalBounds = holder.getBoundingBox();
      if (chunkLocalBounds == null) continue;

      final chunkBounds = chunkLocalBounds.move(holder.pos.$1 << 4, 0, holder.pos.$2 << 4);
      final bounds = localBounds;
      if (bounds == null) {
        localBounds = BoundingBox3i.copy(chunkBounds);
      } else {
        bounds.expandToBox(chunkBounds);
      }
    }

    if (previousBounds != localBounds) {
      subLevel.onPlotBoundsChanged();
    }
  }

  /// The block-aligned, inclusive bounding box of the sub-level, or the empty
  /// box when not set.
  BoundingBox3ic getBoundingBox() => localBounds ?? BoundingBox3i.empty;

  /// Sets the local bounding box.
  void setBoundingBox(BoundingBox3ic bounds) {
    final current = localBounds;
    if (current == null) {
      localBounds = BoundingBox3i.copy(bounds);
    } else {
      current.setFrom(bounds);
    }
  }

  /// Removes all chunks from this plot.
  void onRemove() {
    for (final holder in loadedChunks) {
      onRemoveChunkHolder(holder.chunk);
    }
    loadedChunks.clear();
    localBounds = null;
  }

  /// Releases one chunk of this plot on the host.
  void onRemoveChunkHolder(PlotChunk chunk);

  /// Expands the plot if necessary to include the given block and its
  /// neighbours.
  void expandIfNecessary(Pos blockPos) {
    if (!expandPlotIfNecessary) return;
    for (final direction in Direction.values) {
      // One block of margin to prevent black face lighting at the edges.
      final offset = blockPos.relative(direction, 2);
      final globalChunk = (offset.$1 >> 4, offset.$3 >> 4);
      if (getChunk(toLocal(globalChunk)) == null) {
        newEmptyChunk(globalChunk);
      }
    }
  }

  /// Handles a change in block state at the global block position [pos].
  ///
  /// The actor and reaction wheel are resolved by the subclass (the Java
  /// version asks the level for the block entity, which the port cannot do for
  /// plot chunks; see `api/block_entity_hooks.dart`).
  void onBlockChange(Pos pos, String state) {
    final actor = actorAt(pos);
    if (actor != null) {
      blockEntityActors[pos] = actor;
    } else {
      blockEntityActors.remove(pos);
    }

    final wheel = reactionWheelAt(pos);
    if (wheel != null) {
      blockEntityReactionWheels[pos] = wheel;
      onReactionWheelChanged(pos, wheel, true);
    } else {
      final previous = blockEntityReactionWheels.remove(pos);
      if (previous != null) onReactionWheelChanged(pos, previous, false);
    }
  }

  /// The sub-level actor block entity at [pos], or `null`.
  BlockEntitySubLevelActor? actorAt(Pos pos);

  /// The reaction wheel block entity at [pos], or `null`.
  BlockEntitySubLevelReactionWheel? reactionWheelAt(Pos pos);

  /// Called when a reaction wheel appears ([added] true) or disappears.
  void onReactionWheelChanged(Pos pos, BlockEntitySubLevelReactionWheel wheel, bool added) {}

  /// Gets all active actors in the plot.
  Iterable<BlockEntitySubLevelActor> getBlockEntityActors() => blockEntityActors.values;

  /// The reaction wheels of the plot.
  Iterable<BlockEntitySubLevelReactionWheel> getBlockEntityReactionWheels() =>
      blockEntityReactionWheels.values;

  @override
  String toString() => 'LevelPlot[plot=(${plotPos.$1}, ${plotPos.$2}), logSize=$logSize, '
      'chunks=${loadedChunks.length}, bounds=$localBounds]';
}
