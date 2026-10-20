// `dev.ryanhcode.sable.api.sublevel.SubLevelContainer`: holds all sub-levels and
// plots in a level.
//
// The plot yard is a square grid of `1 << logSideLength` plots, each
// `1 << logPlotSize` chunks on a side, placed `DEFAULT_ORIGIN` plots out so the
// yard never overlaps generated terrain (10000 plots × 128 chunks ≈ 1.28M
// chunks ≈ 20.5M blocks from the origin).
//
// The container itself is pure bookkeeping: allocation, occupancy, lookup by
// plot coordinate and by UUID, removal and observers. Chunks come from
// `PlotChunkHost` and are created by the concrete container.
//
// Pure: no host imports.
import 'dart:math' as math;

import '../api/sub_level_observer.dart';
import '../host/sub_level_host.dart';
import '../math/bounding_box.dart';
import '../math/pose.dart';
import '../math/vector.dart';
import '../storage/sub_level_removal_reason.dart';
import '../util/bit_grid.dart';
import 'level_plot.dart';
import 'plot_chunk_holder.dart';
import 'sub_level.dart';

/// Holds all sub-levels and plots in a level.
abstract class SubLevelContainer {
  /// The log_2 of the side length of the plot grid, in plots (Java
  /// `DEFAULT_LOG_SIZE_LENGTH`).
  static int defaultLogSizeLength = 7;

  /// The log_2 of the side length of one plot, in chunks (Java
  /// `DEFAULT_LOG_PLOT_SIZE`).
  static int defaultLogPlotSize = 7;

  /// The origin of the plot yard, in plots. The yard sits over 30 million
  /// blocks out, so it is outside any world border or generated terrain.
  static const int defaultOrigin = 10000;

  /// The containers of the loaded levels, by dimension id (the Java static
  /// `getContainer(Level)` reads this off the level through a mixin).
  static final Map<String, SubLevelContainer> _containers = {};

  /// The container of [level], or `null` when the level has none.
  static SubLevelContainer? of(SableLevel level) => _containers[level.dimensionId];

  /// Registers [container] for its level.
  static void register(SubLevelContainer container) {
    _containers[container.level.dimensionId] = container;
  }

  /// Removes the container of [level].
  static void unregister(SableLevel level) => _containers.remove(level.dimensionId);

  /// Forgets every container (server shutdown).
  static void clearAll() => _containers.clear();

  /// The plot grid storage for all loaded sub-levels, indexed by
  /// `z << logSideLength | x`.
  final List<SubLevel?> subLevels;

  /// All loaded sub-levels, in allocation order.
  final List<SubLevel> allSubLevels = [];

  /// All loaded sub-levels, by UUID.
  final Map<String, SubLevel> subLevelsByUUID = {};

  /// The occupancy of the plot grid, including loaded and unloaded plots.
  final BitGrid occupancy;

  /// All observers of the plot grid.
  final List<SubLevelObserver> observers = [];

  /// The level of the plot grid.
  final SableLevel level;

  /// The chunk host of the level (see `host/sub_level_host.dart`).
  final PlotChunkHost chunkHost;

  /// The log_2 of the side length of the plot grid, in plots.
  final int logSideLength;

  /// The log_2 of the amount of chunks in the side of a plot.
  final int logPlotSize;

  /// The X origin of the plot grid, in plot coordinates.
  final int originX;

  /// The Z origin of the plot grid, in plot coordinates.
  final int originZ;

  /// The fraction of velocity a sub-level keeps when it is loaded
  /// (`SableConfig.velocityRetainedOnLoad`).
  double velocityRetainedOnLoad = 0.9;

  /// Creates a sub-level container.
  SubLevelContainer(this.level, this.chunkHost, this.logSideLength, this.logPlotSize, this.originX, this.originZ)
    : subLevels = List<SubLevel?>.filled((1 << logSideLength) * (1 << logSideLength), null),
      occupancy = BitGrid((1 << logSideLength) * (1 << logSideLength));

  /// Called every tick for the plot grid.
  void tick() {
    for (final subLevel in allSubLevels) {
      subLevel.tick();
    }
    processSubLevelRemovals();
    for (final observer in observers) {
      observer.tick(this);
    }
  }

  /// Whether [subLevel] should be removed because its mass tracker became
  /// invalid (the Java check is `ServerSubLevel.getMassTracker().isInvalid()`).
  bool isInvalid(SubLevel subLevel) => false;

  /// Destroys the contents of [subLevel] before it is removed (Java
  /// `destroyAllBlocks`); no-op for levels without a plot implementation.
  void destroyAllBlocks(SubLevel subLevel) {}

  /// Processes and follows through on queued sub-level removals.
  void processSubLevelRemovals() {
    for (final subLevel in allSubLevels.toList()) {
      if (!subLevel.isRemoved() && isInvalid(subLevel)) {
        destroyAllBlocks(subLevel);
        subLevel.markRemoved();
      }

      if (subLevel.isRemoved()) {
        final plotPos = subLevel.getPlot().plotPos;
        removeSubLevel(plotPos.$1 - originX, plotPos.$2 - originZ, SubLevelRemovalReason.removed);
      }
    }
  }

  /// Adds an observer to the plot grid.
  void addObserver(SubLevelObserver observer) => observers.add(observer);

  /// The first empty plot coordinate in the grid, or `null` when full.
  (int, int)? getFirstEmptyPlot() {
    for (var x = 0; x < (1 << logSideLength); x++) {
      for (var z = 0; z < (1 << logSideLength); z++) {
        if (!occupancy.get(getIndex(x, z))) return (x, z);
      }
    }
    return null;
  }

  /// The index of the plot at the given local plot coordinates.
  int getIndex(int x, int z) => x + (z << logSideLength);

  /// The plot at the given local plot coordinates, or `null`.
  LevelPlot? getLocalPlot(int x, int z) {
    if (x < 0 || x >= (1 << logSideLength) || z < 0 || z >= (1 << logSideLength)) {
      return null;
    }
    return subLevels[getIndex(x, z)]?.getPlot();
  }

  /// The sub-level at the given local plot coordinates, or `null`.
  SubLevel? getSubLevel(int x, int z) {
    if (x < 0 || x >= (1 << logSideLength) || z < 0 || z >= (1 << logSideLength)) {
      return null;
    }
    return subLevels[getIndex(x, z)];
  }

  /// Allocates a new sub-level in the first empty plot.
  SubLevel allocateNewSubLevel(Pose3d pose) {
    final firstEmpty = getFirstEmptyPlot();
    if (firstEmpty == null) {
      throw StateError('No empty plots left in the plot grid');
    }
    return allocateSubLevel(newUuid(), firstEmpty.$1, firstEmpty.$2, pose);
  }

  /// Allocates a sub-level at the given local plot coordinates.
  SubLevel allocateSubLevel(String uuid, int x, int z, Pose3d pose) {
    if (getLocalPlot(x, z) != null) {
      throw ArgumentError('Plot already exists at $x, $z');
    }
    if (x < 0 || x >= (1 << logSideLength) || z < 0 || z >= (1 << logSideLength)) {
      throw ArgumentError('Plot coordinates out of bounds: $x, $z');
    }

    final subLevel = createSubLevel(x + originX, z + originZ, pose, uuid);

    final index = getIndex(x, z);
    subLevels[index] = subLevel;
    occupancy.set(index);
    allSubLevels.add(subLevel);
    subLevelsByUUID[subLevel.uniqueId] = subLevel;
    for (final observer in observers) {
      observer.onSubLevelAdded(subLevel);
    }

    onSubLevelAllocated(subLevel);
    return subLevel;
  }

  /// Called after a sub-level was allocated, before it is returned.
  void onSubLevelAllocated(SubLevel subLevel) {}

  /// Creates a new sub-level with the given global plot coordinates and pose.
  SubLevel createSubLevel(int globalPlotX, int globalPlotZ, Pose3d pose, String uuid);

  /// A random UUID string (the Java `UUID.randomUUID().toString()`).
  ///
  /// Overridable so tests are deterministic.
  String newUuid() => randomUuidV4();

  /// Gets a chunk from the plot grid at the given global chunk position.
  PlotChunk? getChunk((int, int) pos) {
    if (!inBoundsChunk(pos)) return null;
    final plot = getPlotAt(pos);
    if (plot == null) return null;
    return plot.getChunk(plot.toLocal(pos));
  }

  /// Gets a chunk holder from the plot grid at the given global chunk position.
  PlotChunkHolder? getChunkHolder((int, int) pos) {
    if (!inBoundsChunk(pos)) return null;
    final plot = getPlotAt(pos);
    if (plot == null) return null;
    return plot.getChunkHolder(plot.toLocal(pos));
  }

  /// Gets the plot at the given global chunk position.
  LevelPlot? getPlot(int chunkX, int chunkZ) {
    final plotX = (chunkX >> logPlotSize) - originX;
    final plotZ = (chunkZ >> logPlotSize) - originZ;
    return getLocalPlot(plotX, plotZ);
  }

  /// Gets the plot at the given global chunk position.
  LevelPlot? getPlotAt((int, int) pos) {
    final plotX = (pos.$1 >> logPlotSize) - originX;
    final plotZ = (pos.$2 >> logPlotSize) - originZ;
    return getLocalPlot(plotX, plotZ);
  }

  /// Whether a global chunk position is within the plot grid.
  bool inBoundsChunk((int, int) pos) => inBounds(pos.$1, pos.$2);

  /// Whether a global block position is within the plot grid.
  bool inBoundsBlock((int, int, int) pos) => inBounds(pos.$1 >> 4, pos.$3 >> 4);

  /// Whether a global position is within the plot grid.
  bool inBoundsPos(Vector3d pos) => inBounds(pos.x.floor() >> 4, pos.z.floor() >> 4);

  /// Whether a global chunk position is within the plot grid.
  bool inBounds(int x, int z) {
    final plotX = (x >> logPlotSize) - originX;
    final plotZ = (z >> logPlotSize) - originZ;
    final sideLength = 1 << logSideLength;
    return plotX >= 0 && plotX < sideLength && plotZ >= 0 && plotZ < sideLength;
  }

  /// Adds a populated chunk in the plot grid at the given global chunk position.
  ///
  /// HOST GAP: the host must be able to hand the model an already-loaded chunk
  /// that belongs to a plot (`newPopulatedChunk` in Java).
  void newPopulatedChunk((int, int) pos, PlotChunk chunk) {
    if (!inBoundsChunk(pos)) return;
    final plotX = (pos.$1 >> logPlotSize) - originX;
    final plotZ = (pos.$2 >> logPlotSize) - originZ;
    final plot = getLocalPlot(plotX, plotZ);
    if (plot == null) {
      throw StateError('Cannot add chunk at ${pos.$1}, ${pos.$2} in nonexistent sub-level plot');
    }
    final local = plot.toLocal(pos);
    if (plot.getChunkHolder(local) != null) {
      throw StateError('Chunk already exists at ${pos.$1}, ${pos.$2}');
    }
    plot.addChunkHolder(local, PlotChunkHolder.create(chunk, pos), false);
  }

  /// The players tracking a plot chunk.
  Iterable<SablePlayer> getPlayersTracking((int, int) chunkPos) {
    final plot = getPlotAt(chunkPos);
    if (plot == null) return const [];
    final lookup = chunkHost;
    if (lookup is! PlayerLookupHost) return const [];
    final players = <SablePlayer>[];
    for (final uuid in trackingPlayerIdsOf(plot.getSubLevel())) {
      final player = lookup.playerById(uuid);
      if (player != null) players.add(player);
    }
    return players;
  }

  /// All plots in the plot grid (the Java return type is
  /// `List<? extends SubLevel>`).
  List<SubLevel> getAllSubLevels() => allSubLevels;

  /// The level of the plot grid.
  SableLevel getLevel() => level;

  /// The log_2 of the side length of a plot.
  int getLogPlotSize() => logPlotSize;

  /// The log_2 of the side length of the plot grid.
  int getLogSideLength() => logSideLength;

  /// The origin of the plot grid, in plot coordinates.
  (int, int) getOrigin() => (originX, originZ);

  /// Removes a sub-level at a local plot coordinate.
  void removeSubLevel(int x, int z, SubLevelRemovalReason reason) {
    final subLevel = getSubLevel(x, z);
    if (subLevel == null) {
      throw StateError('No sub-level at $x, $z');
    }

    for (final observer in observers) {
      observer.onSubLevelRemoved(subLevel, reason);
    }
    subLevel.onRemove();

    final index = getIndex(x, z);
    subLevels[index] = null;
    allSubLevels.remove(subLevel);
    subLevelsByUUID.remove(subLevel.uniqueIdOrNull);

    if (reason == SubLevelRemovalReason.removed) {
      occupancy.clear(index);
    }
  }

  /// The count of loaded sub-levels.
  int getLoadedCount() => allSubLevels.length;

  /// The sub-levels whose global bounding box intersects [bounds].
  Iterable<SubLevel> queryIntersecting(BoundingBox3dc bounds) =>
      allSubLevels.where((subLevel) => subLevel.boundingBox.intersects(bounds));

  /// Removes a sub-level from the plot grid.
  void removeSubLevelAt(SubLevel subLevel, SubLevelRemovalReason reason) {
    final plotPos = subLevel.getPlot().plotPos;
    removeSubLevel(plotPos.$1 - originX, plotPos.$2 - originZ, reason);
  }

  /// Retrieves a sub-level by its UUID.
  SubLevel? getSubLevelById(String uuid) => subLevelsByUUID[uuid];

  /// The occupancy of the plot grid, including loaded and unloaded plots.
  BitGrid getOccupancy() => occupancy;

  /// The tracking player ids of a server sub-level (empty for other kinds).
  Iterable<String> trackingPlayerIdsOf(SubLevel subLevel) =>
      subLevel is ServerSubLevelLike ? (subLevel as ServerSubLevelLike).trackingPlayerIds : const [];

  @override
  String toString() => 'SubLevelContainer[${level.dimensionId}, '
      'grid=${1 << logSideLength}x${1 << logSideLength} plots, '
      'plot=${1 << logPlotSize} chunks, origin=($originX, $originZ), '
      'loaded=${allSubLevels.length}]';
}

/// The server-sub-level surface the container needs without depending on the
/// concrete class (avoids a cycle between the container and `ServerSubLevel`).
abstract interface class ServerSubLevelLike {
  /// The UUIDs of the players tracking this sub-level.
  Iterable<String> get trackingPlayerIds;
}

/// A chunk host that can resolve players by UUID.
abstract interface class PlayerLookupHost {
  SablePlayer? playerById(String uuid);
}

/// A random UUID v4 string, formatted like Java's `UUID.toString()`.
String randomUuidV4([RandomSource? random]) {
  final source = random ?? RandomSource.secure();
  final bytes = List<int>.generate(16, (_) => source.nextByte());
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// A source of random bytes for [randomUuidV4]; tests inject a fixed one.
abstract interface class RandomSource {
  int nextByte();

  /// A source seeded from the clock.
  static RandomSource secure() => _MathRandomSource();
}

final class _MathRandomSource implements RandomSource {
  final math.Random _random = math.Random();

  @override
  int nextByte() => _random.nextInt(256);
}
