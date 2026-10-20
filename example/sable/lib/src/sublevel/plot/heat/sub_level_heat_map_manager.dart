// `dev.ryanhcode.sable.sublevel.plot.heat.SubLevelHeatMapManager`: finds the
// pieces a sub-level breaks into and splits them off.
//
// The manager keeps a breadth-first "heat" value on every solid block (its
// distance from a root). Two states alternate:
//
// * `filling` — the flood fill spreads from every root through solid blocks;
//   blocks it cannot reach keep a heat value but no split index, so they belong
//   to a different piece,
// * `clearing` — the fill is torn down again while the pieces are labelled, and
//   when two different labels meet they are merged.
//
// When the clear finishes with more than one label, `split` hands each labelled
// group to `SubLevelAssemblyHelper.assembleBlocks`, so each piece becomes its
// own sub-level. The two degenerate cases are handled explicitly: a single group
// that is the whole sub-level is not a split, and when the groups cover the
// whole sub-level one group is kept to avoid destroying the original.
//
// `SableConfig.subLevelSplittingHeatmapSteps` steps run per tick.
//
// Pure: no host imports.
import '../../api/physics.dart';
import '../../api/sub_level_assembly_helper.dart';
import '../../config/sable_config.dart';
import '../../host/sub_level_host.dart';
import '../../math/bounding_box.dart';
import '../../model/plot_chunk_holder.dart';
import '../../model/server_sub_level.dart';
import '../../model/sub_level_container.dart';
import '../../storage/sub_level_removal_reason.dart';
import 'heat_data_chunk_section.dart';

/// `HeatMapPropagationState`.
enum HeatMapPropagationState { clearing, filling, idle }

/// `SubLevelHeatMapManager.SplitListener`: other projects (Simulated) add their
/// own blocks when a sub-level splits.
typedef SplitListener = void Function(
  SableLevel level,
  BoundingBox3ic assemblyBounds,
  List<(int, int, int)> blocks,
);

/// Manages the heatmap and flood fill for sub-level splitting.
final class SubLevelHeatMapManager implements SubLevelHeatMap {
  /// Every registered split listener.
  static final List<SplitListener> listeners = [];

  /// `addSplitListener`.
  static void addSplitListener(SplitListener listener) => listeners.add(listener);

  /// Forgets every listener (tests, shutdown).
  static void clearSplitListeners() => listeners.clear();

  /// All directions checked for solid blocks in 3D (diagonals included).
  static const List<(int, int, int)> directionOffsets = [
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

  final ServerSubLevel subLevel;

  /// The config the step count comes from.
  final SableConfig config;

  /// Block position (packed) to partial sub-level index.
  final Map<int, int> subLevelSplits = {};

  final List<(int, int, int)> floodfill = [];
  final List<(int, int, int)> removed = [];
  final List<(int, int, int)> newStarts = [];
  final List<int> splitIndexMap = [];

  HeatMapPropagationState state = HeatMapPropagationState.filling;

  /// Set on the first placed block.
  bool initialized = false;

  /// Set on the first completed flood fill.
  bool splitComplete = false;

  int solidCount = 0;

  SubLevelHeatMapManager(this.subLevel, {required this.config});

  /// Whether [blockPos] is solid: the plot's own block, not the world's.
  ///
  /// Java asks `level.getBlockState(blockPos)`, which works because the plot
  /// chunks *are* level chunks; here the plot is asked through its chunk host.
  bool isSolidAt((int, int, int) blockPos) {
    final plot = subLevel.getPlot();
    final local = plot.toLocal((blockPos.$1 >> 4, blockPos.$3 >> 4));
    final chunk = plot.getChunk(local);
    if (chunk == null) return false;
    return chunk.blockAt(blockPos.$1 & 15, blockPos.$2, blockPos.$3 & 15) != 'minecraft:air';
  }

  /// `tick()`: runs `sub_level_splitting_heatmap_steps` steps.
  @override
  void tick() {
    final steps = config.subLevelSplittingHeatmapSteps;
    for (var i = 0; i < steps; i++) {
      if (step()) break;
    }
  }

  /// One step of the fill/clear state machine; `true` when there is nothing
  /// left to do.
  bool step() {
    if (state == HeatMapPropagationState.filling) {
      if (floodfill.isNotEmpty) {
        final p = floodfill.removeAt(0);
        if (heatMapContains(p)) {
          final currentHeat = heatMapGet(p);
          for (final dir in directionOffsets) {
            final p2 = _offset(p, dir);
            final solid = isSolidAt(p2);
            final contains = heatMapContains(p2);

            if (solid && !contains) {
              heatMapSet(p2, currentHeat + 1);
              subLevelSplits.remove(_pack(p2));
              floodfill.add(p2);
            }
          }
        }
      }
      if (floodfill.isEmpty) {
        splitComplete = true;
        state = HeatMapPropagationState.clearing;

        if (subLevelSplits.isNotEmpty) split();
      }
    }

    if (state == HeatMapPropagationState.clearing) {
      if (floodfill.isNotEmpty) {
        final p = floodfill.removeAt(0);
        if (heatMapContains(p)) {
          final currentHeat = heatMapGet(p);
          final currentIndex = splitIndexMap[subLevelSplits[_pack(p)]!];
          for (final dir in directionOffsets) {
            final p2 = _offset(p, dir);
            if (isSolidAt(p2)) {
              final otherSplit = subLevelSplits[_pack(p2)];
              if (otherSplit != null) {
                final otherIndex = splitIndexMap[otherSplit];
                if (currentIndex != otherIndex) {
                  // Two flood fills collided; sacrifice the other index mapping.
                  splitIndexMap[otherSplit] = currentIndex;
                }
              }
              if (heatMapContains(p2)) {
                if (heatMapGet(p2) > currentHeat) {
                  floodfill.add(p2);
                  subLevelSplits[_pack(p2)] = currentIndex;
                } else {
                  newStarts.add(p2);
                }
              }
            }
          }
          heatMapRemove(p);
        }
      } else if (removed.isNotEmpty) {
        for (final p in removed) {
          if (heatMapContains(p)) {
            final currentHeat = heatMapGet(p);
            for (final dir in directionOffsets) {
              final p2 = _offset(p, dir);
              if (isSolidAt(p2) && heatMapContains(p2) && heatMapGet(p2) > currentHeat) {
                var canRemove = true;
                for (final dir2 in directionOffsets) {
                  if ((-dir.$1, -dir.$2, -dir.$3) == dir2) continue;
                  final p3 = _offset(p2, dir2);
                  if (isSolidAt(p3) && heatMapContains(p3) && heatMapGet(p3) < heatMapGet(p2)) {
                    canRemove = false;
                  }
                }
                if (canRemove) {
                  // Start a new flood fill from this source, with a fresh index.
                  floodfill.add(p2);
                  final newIndex = splitIndexMap.length;
                  subLevelSplits[_pack(p2)] = newIndex;
                  splitIndexMap.add(newIndex);
                }
              }
            }
          }
          heatMapRemove(p);
        }
        removed.clear();
      } else if (newStarts.isNotEmpty) {
        floodfill.addAll(newStarts);
        newStarts.clear();
        state = HeatMapPropagationState.filling;
      } else if (subLevelSplits.isNotEmpty) {
        splitComplete = true;
        split();
      } else {
        splitComplete = true;
        return true;
      }
    }
    return false;
  }

  void split() {
    final newSubLevelBlocks = <int, List<(int, int, int)>>{};
    for (final entry in subLevelSplits.entries) {
      final splitIndex = splitIndexMap[entry.value];
      newSubLevelBlocks.putIfAbsent(splitIndex, () => []).add(_unpack(entry.key));
    }

    final splittingWholeSubLevel =
        newSubLevelBlocks.length == 1 && solidCount == newSubLevelBlocks.values.first.length;

    // Only one split, and it is the whole sub-level: clear the splits instead of
    // splitting, but rebuild the heatmap because the root is gone.
    if (splittingWholeSubLevel) {
      rebuildHeatmapFrom(newSubLevelBlocks.values.first);
      newSubLevelBlocks.clear();
    }

    // If the groups cover the whole sub-level, splitting would delete the
    // original; keep the largest group instead.
    var totalSplitBlocks = 0;
    for (final blocks in newSubLevelBlocks.values) {
      totalSplitBlocks += blocks.length;
    }

    if (!splittingWholeSubLevel && totalSplitBlocks != 0 && totalSplitBlocks == solidCount) {
      final largest = newSubLevelBlocks.entries.reduce((a, b) => a.value.length >= b.value.length ? a : b);
      rebuildHeatmapFrom(largest.value);
      newSubLevelBlocks.remove(largest.key);
    }

    subLevelSplits.clear();
    splitIndexMap
      ..clear()
      ..add(0);

    final level = subLevel.getLevel();

    for (final blocks in newSubLevelBlocks.values) {
      final bounds = BoundingBox3i.fromPositions(blocks)?.expand(1, 1, 1);
      if (bounds == null) continue;

      for (final listener in listeners) {
        listener(level, bounds, blocks);
      }

      final newSubLevel = SubLevelAssemblyHelper.assembleBlocks(level, blocks.first, blocks, bounds);

      // Protect against split sub-levels with zero mass.
      final tracker = newSubLevel.massTracker;
      final centerOfMass = tracker?.getCenterOfMass();
      final mass = tracker == null ? 0.0 : 1.0 / tracker.getInverseMass();
      if (centerOfMass == null || mass <= 0.0) {
        newSubLevel.getPlot().destroyAllBlocks();

        final container = SubLevelContainer.of(level);
        container?.removeSubLevelAt(newSubLevel, SubLevelRemovalReason.removed);
      }
    }
  }

  void rebuildHeatmapFrom(List<(int, int, int)> blocks) {
    state = HeatMapPropagationState.filling;
    initialized = false;
    splitComplete = false;
    solidCount = 0;

    newStarts.clear();
    floodfill.clear();
    removed.clear();

    for (final block in blocks) {
      heatMapRemove(block);
    }
    for (final block in blocks) {
      onSolidAdded(block);
    }
  }

  /// Called whenever a block at [blockPos] becomes solid.
  void onSolidAdded((int, int, int) blockPos) {
    solidCount++;

    if (!initialized) {
      initialized = true;
      heatMapSet(blockPos, 1);
      floodfill.add(blockPos);
      splitIndexMap.add(0); // Index zero is reserved for in-air placements.
      return;
    }

    var minimumAdjacentHeat = 0x7FFFFFFF;
    if (removed.remove(blockPos)) return;

    for (final direction in directionOffsets) {
      final neighbor = _offset(blockPos, direction);
      if (heatMapContains(neighbor)) {
        final heat = heatMapGet(neighbor);
        if (heat < minimumAdjacentHeat) minimumAdjacentHeat = heat;
      }
    }

    if (minimumAdjacentHeat == 0x7FFFFFFF) {
      // A block placed in thin air: assume it is a split section.
      if (!splitComplete) subLevelSplits[_pack(blockPos)] = 0;
    } else {
      heatMapSet(blockPos, minimumAdjacentHeat + 1);
      if (state == HeatMapPropagationState.filling) {
        floodfill.add(blockPos);
      } else {
        newStarts.add(blockPos);
      }
    }
  }

  /// Called whenever a block at [blockPos] becomes non-solid.
  void onSolidRemoved((int, int, int) blockPos) {
    solidCount--;
    removed.add(blockPos);
  }

  void heatMapRemove((int, int, int) blockPos) => heatMapSet(blockPos, 0);

  bool heatMapContains((int, int, int) neighbor) => heatMapGet(neighbor) != 0;

  int heatMapGet((int, int, int) blockPos) {
    final plot = subLevel.getPlot();
    final local = plot.toLocal((blockPos.$1 >> 4, blockPos.$3 >> 4));
    final holder = plot.getChunkHolder(local);
    if (holder == null) return 0;

    final section = holder.getHeatSection(blockPos.$2 >> 4);
    if (section == null) return 0;

    return section.get(blockPos.$1 & 15, blockPos.$2 & 15, blockPos.$3 & 15);
  }

  void heatMapSet((int, int, int) blockPos, int value) {
    final plot = subLevel.getPlot();
    final local = plot.toLocal((blockPos.$1 >> 4, blockPos.$3 >> 4));
    final holder = plot.getChunkHolder(local);
    if (holder == null) return;

    var section = holder.getHeatSection(blockPos.$2 >> 4);
    if (section == null) {
      section = HeatDataChunkSection();
      holder.setHeatSection(blockPos.$2 >> 4, section);
    }

    section.set(blockPos.$1 & 15, blockPos.$2 & 15, blockPos.$3 & 15, value);
  }

  /// `BlockPos.asLong`: x in the top 26 bits, z in the next 26, y in the low 12.
  static int _pack((int, int, int) pos) =>
      ((pos.$1 & 0x3FFFFFF) << 38) | ((pos.$3 & 0x3FFFFFF) << 12) | (pos.$2 & 0xFFF);

  static (int, int, int) _unpack(int packed) =>
      (packed >> 38, (packed << 52) >> 52, (packed << 26) >> 38);

  static (int, int, int) _offset((int, int, int) pos, (int, int, int) dir) =>
      (pos.$1 + dir.$1, pos.$2 + dir.$2, pos.$3 + dir.$3);

  /// The chunk holder at [local], or `null`.
  PlotChunkHolder? holderAt((int, int) local) => subLevel.getPlot().getChunkHolder(local);

  /// Whether the manager has finished its first fill (`split_complete`).
  bool get isSplitComplete => splitComplete;

  @override
  String toString() =>
      'SubLevelHeatMapManager[${subLevel.uniqueId}, state=${state.name}, '
      'solid=$solidCount, splits=${subLevelSplits.length}]';
}
