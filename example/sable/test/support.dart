// Test doubles for the sub-level model: a level, a chunk host and a chunk that
// keep everything in memory. No host bindings are involved, so this runs on the
// Dart VM.
import 'package:sable/sable.dart';

final class FakeLevel implements SableLevel {
  @override
  final String dimensionId;

  @override
  bool isClientSide = false;

  @override
  int minY = -64;

  @override
  int maxY = 320;

  @override
  int gameTime = 0;

  @override
  int get sectionsCount => (maxY - minY) >> 4;

  /// The biome every position reports, or `null` for none.
  String? biome;

  @override
  String? biomeAt(int x, int y, int z) => biome;

  FakeLevel([this.dimensionId = 'minecraft:overworld']);
}

/// A chunk that stores its blocks in a sparse map.
final class FakeChunk implements PlotChunk {
  @override
  final (int, int) pos;

  final Map<(int, int, int), String> blocks;

  /// Block-entity data by packed local position, so tests can install saved
  /// data the way `MemoryPlotChunk.blockEntities` does for production.
  final Map<int, Map<String, Object?>> blockEntityDataForTest = {};

  FakeChunk(this.pos, [Map<(int, int, int), String>? blocks]) : blocks = blocks ?? {};

  @override
  int sectionsCount = 1;

  @override
  bool get hasOnlyAir => blocks.isEmpty;

  @override
  bool sectionHasOnlyAir(int index) => blocks.isEmpty;

  @override
  int sectionMinY(int index) => 0;

  @override
  String blockAt(int x, int y, int z) => blocks[(x, y, z)] ?? 'minecraft:air';

  @override
  Map<String, Object?>? blockEntityData(int x, int y, int z) =>
      blockEntityDataForTest[indexOfBlock(x, y, z)];

  @override
  final Map<int, PlotScheduledTick> blockTicks = {};

  @override
  int indexOfBlock(int x, int y, int z) => ((y & 0xFFF) << 8) | ((z & 15) << 4) | (x & 15);

  @override
  void scheduleBlockTick(int x, int y, int z, PlotScheduledTick tick) =>
      blockTicks[indexOfBlock(x, y, z)] = tick;
}

class FakeChunkHost implements PlotChunkHost, PlayerLookupHost {
  @override
  final SableLevel level;

  final Map<(int, int), PlotChunk> chunks = {};
  final Set<(int, int)> loaded = {};
  final List<(int, int, String, int)> tickets = [];
  final Map<String, SablePlayer> players = {};

  FakeChunkHost(this.level);

  @override
  bool isBlockLoaded(int x, int y, int z) => true;

  @override
  PlotChunk? getLoadedChunk(int x, int z) => chunks[(x, z)];

  @override
  PlotChunk createEmptyChunk(int x, int z) {
    final chunk = FakeChunk((x, z));
    chunks[(x, z)] = chunk;
    loaded.add((x, z));
    return chunk;
  }

  @override
  void setChunkLoaded(int x, int z, bool isLoaded) {
    if (isLoaded) {
      loaded.add((x, z));
    } else {
      loaded.remove((x, z));
    }
  }

  @override
  void addChunkTicket(int x, int z, String ticketType, int ticketLevel) =>
      tickets.add((x, z, ticketType, ticketLevel));

  @override
  void removeChunkTicket(int x, int z, String ticketType, int ticketLevel) =>
      tickets.removeWhere((t) => t.$1 == x && t.$2 == z && t.$3 == ticketType);

  @override
  bool isChunkLoadedEnough(int x, int z) => true;

  @override
  Map<String, Object?> serializeChunk(PlotChunk chunk) => {
    'pos': [chunk.pos.$1, chunk.pos.$2],
    'blocks': {
      for (final entry in (chunk as FakeChunk).blocks.entries)
        '${entry.key.$1},${entry.key.$2},${entry.key.$3}': entry.value,
    },
    if (chunk.blockEntityDataForTest.isNotEmpty)
      'block_entities': {
        for (final entry in chunk.blockEntityDataForTest.entries) '${entry.key}': {...entry.value},
      },
    if (chunk.blockTicks.isNotEmpty)
      'block_ticks': {
        for (final entry in chunk.blockTicks.entries)
          '${entry.key}': {'delay': entry.value.delay, 'priority': entry.value.priority.index},
      },
  };

  @override
  PlotChunk deserializeChunk(int x, int z, Map<String, Object?> tag) {
    final chunk = FakeChunk((x, z));
    final blocks = tag['blocks'];
    if (blocks is Map) {
      for (final entry in blocks.entries) {
        final parts = (entry.key as String).split(',').map(int.parse).toList();
        chunk.blocks[(parts[0], parts[1], parts[2])] = entry.value as String;
      }
    }
    final entities = tag['block_entities'];
    if (entities is Map) {
      for (final entry in entities.entries) {
        final index = int.tryParse('${entry.key}');
        final value = entry.value;
        if (index == null || value is! Map) continue;
        chunk.blockEntityDataForTest[index] = Map<String, Object?>.from(value);
      }
    }
    final ticks = tag['block_ticks'];
    if (ticks is Map) {
      for (final entry in ticks.entries) {
        final index = int.tryParse('${entry.key}');
        final value = entry.value;
        if (index == null || value is! Map) continue;
        final delay = (value['delay'] as num?)?.toInt();
        final priority = (value['priority'] as num?)?.toInt();
        if (delay == null || delay < 0) continue;
        chunk.blockTicks[index] = PlotScheduledTick(
          delay,
          priority != null && priority >= 0 && priority < PlotTickPriority.values.length
              ? PlotTickPriority.values[priority]
              : PlotTickPriority.normal,
        );
      }
    }
    chunks[(x, z)] = chunk;
    return chunk;
  }

  @override
  void setBlock(int x, int y, int z, String block) {
    final chunk = chunks[(x >> 4, z >> 4)] as FakeChunk?;
    if (block == 'minecraft:air') {
      chunk?.blocks.remove((x & 15, y, z & 15));
    } else {
      chunk?.blocks[(x & 15, y, z & 15)] = block;
    }
  }

  @override
  void startTickingChunk(PlotChunk chunk) {}

  @override
  void kickEntitiesIn(PlotChunk chunk) {}

  @override
  SablePlayer? playerById(String uuid) => players[uuid];
}

final class FakePlayer implements SablePlayer {
  @override
  final String uuid;

  @override
  (double, double, double) position;

  @override
  String dimensionId;

  FakePlayer(this.uuid, [this.position = (0, 0, 0), this.dimensionId = 'minecraft:overworld']);
}

/// A plot with no host-specific behaviour.
final class TestPlot extends LevelPlot {
  TestPlot(super.container, super.x, super.z, super.logSize, super.subLevel);

  @override
  Object? getLightEngine() => null;

  @override
  void onRemoveChunkHolder(PlotChunk chunk) {}

  @override
  BlockEntitySubLevelActor? actorAt((int, int, int) pos) => null;

  @override
  BlockEntitySubLevelReactionWheel? reactionWheelAt((int, int, int) pos) => null;
}

/// A sub-level for tests: counts plot-bound changes.
final class TestSubLevel extends SubLevel {
  int boundsChanges = 0;

  TestSubLevel(super.level, super.plotX, super.plotZ, super.pose);

  @override
  LevelPlot createPlot(SubLevelContainer plotContainer, int plotX, int plotZ, int logPlotSize) =>
      TestPlot(plotContainer, plotX, plotZ, logPlotSize, this);

  @override
  void onPlotBoundsChanged() => boundsChanges++;
}

/// A container of [TestSubLevel]s.
final class TestContainer extends SubLevelContainer {
  int created = 0;

  TestContainer(
    super.level,
    super.chunkHost, [
    super.logSideLength = 3,
    super.logPlotSize = 4,
    super.originX = SubLevelContainer.defaultOrigin,
    super.originZ = SubLevelContainer.defaultOrigin,
  ]);

  @override
  SubLevel createSubLevel(int globalPlotX, int globalPlotZ, Pose3d pose, String uuid) {
    created++;
    final subLevel = TestSubLevel(level, globalPlotX, globalPlotZ, pose);
    subLevel.setUniqueId(uuid);
    return subLevel;
  }
}
