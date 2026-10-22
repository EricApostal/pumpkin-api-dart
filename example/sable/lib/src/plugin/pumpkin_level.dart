// The Pumpkin implementation of the sub-level host seams: `SableLevel`, the
// plot chunk host and the file store.
//
// The pure model (`sublevel/model/**`) never imports the host; the plugin hands
// it these adapters. This is the file `host/sub_level_host.dart` points at
// ("the Pumpkin implementation is `host/pumpkin_level.dart`").
//
// Two kinds of chunk exist here:
//
//  * **world chunks**, read from and written to the level through the plugin
//    API (`HostBlockGetter`, `setBlockState`);
//  * **plot chunks**, the yard a sub-level's blocks move into. Pumpkin cannot
//    create a real `LevelChunk` at an arbitrary position, so a plot chunk is
//    held in memory (`MemoryPlotChunk`) and serialized block by block through
//    Sable's own region format. That is the documented `chunk-source` gap in
//    `vanilla/host_gap.dart`, and it is what makes assembly work at all: the
//    plot yard never touches world generation.
//
// Host: this file uses `pumpkin_api`.
//
// create's positions and block states are not exported from its public barrel
// yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter, setBlockState;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../sublevel/api/sub_level_assembly_helper.dart' show AssemblyBlockHost;
import '../sublevel/host/sub_level_host.dart';
import '../sublevel/model/server_sub_level.dart';
import '../sublevel/model/sub_level_container.dart';
import '../sublevel/plot/heat/sub_level_heat_map_manager.dart';
import '../sublevel/system/physics_system.dart';

/// A dimension of the server, as the sub-level model sees it.
///
/// The world handle is kept (`World.keep()`), because every model call happens
/// outside the callback that received it.
final class PumpkinSableLevel implements SableLevel {
  PumpkinSableLevel(this.world);

  /// The kept handle of the level.
  final World world;

  /// The dimension key (`minecraft:overworld`), which is what
  /// `SubLevelContainer` keys its containers by.
  @override
  String get dimensionId => world.getDimension();

  @override
  bool get isClientSide => false;

  @override
  int get minY => world.getMinY();

  /// HOST GAP: the plugin API does not expose `Level.getMaxY`; 26.x worlds are
  /// 384 blocks tall, which is the range the plot chunks and the assembler's
  /// bounds checks use (the same value `simulated`'s level adapter uses).
  @override
  int get maxY => world.getMinY() + 384;

  @override
  int get gameTime => world.getWorldAge();

  /// HOST GAP: the plugin API has no biome lookup by position.
  @override
  String? biomeAt(int x, int y, int z) => null;

  @override
  int get sectionsCount => (maxY - minY) >> 4;
}

/// A plot chunk held in memory.
///
/// The blocks live in a map from `(y - minY) << 8 | z << 4 | x` to the state, so
/// an empty chunk costs one map. Serialization is block by block, which is the
/// port's replacement for a chunk blob (see the `chunk-serialization` gap).
final class MemoryPlotChunk implements PlotChunk {
  MemoryPlotChunk(this.pos, this.minY, this.maxY);

  @override
  final (int, int) pos;

  /// The lowest block y of the level (the first section starts here).
  final int minY;

  /// The first y outside the level.
  final int maxY;

  /// The non-air blocks, by packed local position.
  final Map<int, BState> blocks = {};

  /// The block-entity data of the chunk, by packed local position.
  final Map<int, Map<String, Object?>> blockEntities = {};

  /// The packed key of a local position. [y] is absolute, as the `PlotChunk`
  /// contract says; the level is 384 blocks tall, so 12 bits never collide.
  static int indexOf(int x, int y, int z) => ((y & 0xFFF) << 8) | ((z & 15) << 4) | (x & 15);

  /// The state at a local position (`minecraft:air` when unset).
  BState stateAt(int x, int y, int z) => blocks[indexOf(x, y, z)] ?? BState.air;

  /// Writes a state at a local position (air removes the entry).
  void setState(int x, int y, int z, BState state) {
    final index = indexOf(x, y, z);
    if (state.isAir) {
      blocks.remove(index);
    } else {
      blocks[index] = state;
    }
  }

  @override
  int get sectionsCount => (maxY - minY) >> 4;

  @override
  bool get hasOnlyAir => blocks.isEmpty;

  @override
  bool sectionHasOnlyAir(int index) {
    for (final key in blocks.keys) {
      // The key holds the absolute y; a section index is relative to [minY].
      if ((((key >> 8) & 0xFFF) - minY) >> 4 == index) return false;
    }
    return true;
  }

  @override
  int sectionMinY(int index) => minY + (index << 4);

  @override
  Map<String, Object?>? blockEntityData(int x, int y, int z) => blockEntities[indexOf(x, y, z)];

  @override
  String blockAt(int x, int y, int z) => stateAt(x, y, z).key;

  /// The chunk as the `chunks` map of a plot save.
  Map<String, Object?> save() => {
    'blocks': {
      for (final entry in blocks.entries)
        '${entry.key}': {'key': entry.value.key, if (entry.value.props.isNotEmpty) 'props': entry.value.props},
    },
    if (blockEntities.isNotEmpty) 'block_entities': {...blockEntities},
  };

  /// Rebuilds a chunk from [save].
  void load(Map<String, Object?> tag) {
    blocks.clear();
    final saved = tag['blocks'];
    if (saved is Map) {
      for (final entry in saved.entries) {
        final index = int.tryParse('${entry.key}');
        final value = entry.value;
        if (index == null || value is! Map) continue;
        final key = value['key'];
        if (key is! String || key == 'minecraft:air') continue;
        final props = value['props'];
        blocks[index] = BState(key, {
          if (props is Map) for (final p in props.entries) '${p.key}': '${p.value}',
        });
      }
    }
    blockEntities.clear();
    final savedEntities = tag['block_entities'];
    if (savedEntities is Map) {
      for (final entry in savedEntities.entries) {
        final index = int.tryParse('${entry.key}');
        final value = entry.value;
        if (index == null || value is! Map) continue;
        blockEntities[index] = Map<String, Object?>.from(value);
      }
    }
  }

  @override
  String toString() => 'MemoryPlotChunk[${pos.$1}, ${pos.$2}, blocks=${blocks.length}]';
}

/// A world chunk, as far as a `PlotChunk` cares.
///
/// Only reads are meaningful: a world chunk is never a plot, so the plot save
/// never serializes one.
final class WorldPlotChunk implements PlotChunk {
  WorldPlotChunk(this.pos, this._world, this._level);

  @override
  final (int, int) pos;

  final World _world;
  final PumpkinSableLevel _level;

  @override
  int get sectionsCount => _level.sectionsCount;

  @override
  bool get hasOnlyAir => false;

  /// Unknown without a section read; reported as "not empty" so a caller that
  /// scans a chunk does not skip a world chunk it cannot inspect.
  @override
  bool sectionHasOnlyAir(int index) => false;

  @override
  int sectionMinY(int index) => _level.minY + (index << 4);

  @override
  Map<String, Object?>? blockEntityData(int x, int y, int z) => null;

  @override
  String blockAt(int x, int y, int z) =>
      HostBlockGetter.stateOfId(_world.getBlockStateId(pos: BlockPos(x: x, y: y, z: z))).key;
}

/// The chunk host of one level: world chunks through the plugin API, plot
/// chunks in memory.
///
/// Implements [AssemblyBlockHost] as well, so assembly moves block states with
/// their properties instead of falling back to the key-only adapter (which
/// refuses block-entity moves).
final class PumpkinPlotChunkHost implements PlotChunkHost, AssemblyBlockHost {
  PumpkinPlotChunkHost(this.level);

  @override
  final PumpkinSableLevel level;

  /// The container this host serves, set once the container exists (the two
  /// reference each other: the container needs a chunk host to be built).
  SubLevelContainer? container;

  final Map<int, MemoryPlotChunk> _plotChunks = {};
  late final HostBlockGetter _worldBlocks = HostBlockGetter(level.world);

  static int _key(int x, int z) => (x << 32) | (z & 0xFFFFFFFF);

  /// Whether [x], [z] are inside the plot yard of the level.
  bool _inYard(int x, int z) => container?.inBounds(x, z) ?? false;

  /// The plot chunk at a global chunk position, created when it is missing.
  MemoryPlotChunk _memoryChunk(int x, int z) =>
      _plotChunks[_key(x, z)] ?? (_plotChunks[_key(x, z)] = MemoryPlotChunk((x, z), level.minY, level.maxY));

  /// Forgets every plot chunk (level unload).
  void clear() => _plotChunks.clear();

  @override
  bool isBlockLoaded(int x, int y, int z) {
    if (_inYard(x >> 4, z >> 4)) {
      return _plotChunks.containsKey(_key(x >> 4, z >> 4)) && y >= level.minY && y < level.maxY;
    }
    return level.world.isLoaded(pos: BlockPos(x: x, y: y, z: z));
  }

  @override
  PlotChunk? getLoadedChunk(int x, int z) {
    if (_inYard(x, z)) return _plotChunks[_key(x, z)];
    final chunk = level.world.getChunk(x: x, z: z);
    return chunk == null ? null : WorldPlotChunk((x, z), level.world, level);
  }

  @override
  PlotChunk createEmptyChunk(int x, int z) {
    final chunk = MemoryPlotChunk((x, z), level.minY, level.maxY);
    _plotChunks[_key(x, z)] = chunk;
    return chunk;
  }

  /// HOST GAP: plot chunks live in this map, not in the host's chunk map, so
  /// there is no per-chunk load flag to set. Kept so a plot that unloads a
  /// chunk does not throw.
  @override
  void setChunkLoaded(int x, int z, bool loaded) {}

  /// HOST GAP: `chunk-tickets.wit` has no "keep this position loaded" call for
  /// a plugin-owned position; plot chunks never need one because they are in
  /// memory (see the `chunk-source` gap).
  @override
  void addChunkTicket(int x, int z, String ticketType, int level) {}

  @override
  void removeChunkTicket(int x, int z, String ticketType, int level) {}

  @override
  bool isChunkLoadedEnough(int x, int z) {
    if (_inYard(x, z)) return _plotChunks.containsKey(_key(x, z));
    return level.world.isLoaded(pos: BlockPos(x: x << 4, y: level.minY + 64, z: z << 4));
  }

  @override
  Map<String, Object?> serializeChunk(PlotChunk chunk) =>
      chunk is MemoryPlotChunk ? chunk.save() : const {};

  @override
  PlotChunk deserializeChunk(int x, int z, Map<String, Object?> tag) {
    final chunk = MemoryPlotChunk((x, z), level.minY, level.maxY)..load(tag);
    _plotChunks[_key(x, z)] = chunk;
    return chunk;
  }

  @override
  void setBlock(int x, int y, int z, String block) => setBlockStateAt(x, y, z, BState(block));

  /// HOST GAP: a plot chunk has no ticking section on the host; the sub-level
  /// tick drives everything the port simulates.
  @override
  void startTickingChunk(PlotChunk chunk) {}

  /// HOST GAP: plot chunks hold no host entities (the host has no entity index
  /// for them), so there is nothing to kick.
  @override
  void kickEntitiesIn(PlotChunk chunk) {}

  // -- AssemblyBlockHost ------------------------------------------------------

  @override
  BState blockStateAt(int x, int y, int z) {
    if (_inYard(x >> 4, z >> 4)) {
      final chunk = _plotChunks[_key(x >> 4, z >> 4)];
      if (chunk == null) return BState.air;
      return chunk.stateAt(x & 15, y, z & 15);
    }
    return _worldBlocks.stateAt((x, y, z));
  }

  @override
  void setBlockStateAt(int x, int y, int z, BState state) {
    if (_inYard(x >> 4, z >> 4)) {
      final chunkX = x >> 4;
      final chunkZ = z >> 4;
      final chunk = _memoryChunk(chunkX, chunkZ);
      final old = chunk.stateAt(x & 15, y, z & 15);
      chunk.setState(x & 15, y, z & 15, state);
      _afterPlotBlockChange(x, y, z, old, state);
      return;
    }
    // The world write is a host call; the model is synchronous, so it is
    // issued now and the host applies it before the next read. The old state is
    // read first, because the level-side hook needs the pair.
    final physics = SubLevelPhysicsSystem.of(container);
    final old = physics == null ? null : _worldBlocks.stateAt((x, y, z));
    unawaited(setBlockState(level.world, (x, y, z), state));
    if (old != null) _afterWorldBlockChange(x, y, z, old, state);
  }

  /// What the level does after a block inside a **plot** changed
  /// (`SableCommonEvents.handleBlockChange`).
  ///
  /// The mass delta is what an assembly needs: `MassTracker` is built when the
  /// sub-level is allocated (an empty plot) and learns each moved block here, so
  /// `SubLevelAssemblyHelper.assembleBlocks` finds a real centre of mass instead
  /// of throwing "the sub-level has no solid blocks".
  void _afterPlotBlockChange(int x, int y, int z, BState oldState, BState newState) {
    final plot = container?.getPlot(x >> 4, z >> 4);
    if (plot == null) return;

    final local = plot.toLocal((x >> 4, z >> 4));
    plot.getChunkHolder(local)?.handleBlockChange(x & 15, y, z & 15, oldState.key, newState.key);
    plot.updateBoundingBox();
    plot.expandIfNecessary((x, y, z));
    plot.onBlockChange((x, y, z), newState.key);

    final subLevel = plot.getSubLevel();
    if (subLevel is ServerSubLevel) {
      final position = (x, y, z);
      // Java queues the change for the heat map and the floating-block
      // controller (`SableCommonEvents.java:63-74`). Both exist only once
      // something built them (the heat map needs splitting on, the controller
      // needs the block-property table), so a `null` one is skipped rather than
      // created here.
      if (oldState != newState) {
        subLevel.floatingBlockController?.queueRemoveFloatingBlock(oldState.key, position);
        subLevel.floatingBlockController?.queueAddFloatingBlock(newState.key, position);
      }
      if (oldState.isAir && !newState.isAir) {
        // `ServerSubLevel.heatMapManager` is typed as the `SubLevelHeatMap`
        // interface, which does not declare the two hooks
        // (`SubLevelHeatMapManager` does, and the port only ever builds that).
        final heatMap = subLevel.heatMapManager;
        if (heatMap is SubLevelHeatMapManager) heatMap.onSolidAdded(position);
      }
      if (!oldState.isAir && newState.isAir) {
        final heatMap = subLevel.heatMapManager;
        if (heatMap is SubLevelHeatMapManager) heatMap.onSolidRemoved(position);
      }
    }

    final physics = SubLevelPhysicsSystem.of(container);
    if (physics != null) {
      physics.handleBlockChange(
        x,
        y,
        z,
        oldState.key,
        newState.key,
        subLevelId: subLevel is ServerSubLevel ? subLevel.uniqueIdOrNull : null,
      );
    }
  }

  /// The same hook for a block in the open **world**: there is no plot at the
  /// position, so the mass delta is skipped ([SubLevelPhysicsSystem.handleBlockChange]
  /// resolves no sub-level), but the pipeline still sees the change and the
  /// sub-levels near it are woken — `SableCommonEvents.handleBlockChange` runs
  /// for every chunk block change of the level, not only for plot chunks.
  void _afterWorldBlockChange(int x, int y, int z, BState oldState, BState newState) {
    final physics = SubLevelPhysicsSystem.of(container);
    if (physics == null) return;
    physics.handleBlockChange(x, y, z, oldState.key, newState.key);
  }

  @override
  Map<String, Object?>? blockEntityDataAt(int x, int y, int z) {
    if (_inYard(x >> 4, z >> 4)) {
      return _plotChunks[_key(x >> 4, z >> 4)]?.blockEntityData(x & 15, y, z & 15);
    }
    // HOST GAP: the host exposes block-entity data as raw NBT bytes
    // (`World.getBlockEntityNbt`); the port has no NBT byte codec, so assembly
    // moves the blocks but not a vanilla block entity's contents.
    return null;
  }

  @override
  void setBlockEntityDataAt(int x, int y, int z, Map<String, Object?> data) {
    if (!_inYard(x >> 4, z >> 4)) return;
    final chunkX = x >> 4;
    final chunkZ = z >> 4;
    _memoryChunk(chunkX, chunkZ).blockEntities[MemoryPlotChunk.indexOf(x & 15, y, z & 15)] =
        Map<String, Object?>.from(data);
  }

  @override
  void removeBlockEntityAt(int x, int y, int z) {
    if (!_inYard(x >> 4, z >> 4)) return;
    _plotChunks[_key(x >> 4, z >> 4)]?.blockEntities.remove(
      MemoryPlotChunk.indexOf(x & 15, y, z & 15),
    );
  }

  /// `markAndNotifyBlock`: the host notifies the block's neighbours.
  ///
  /// Java's `Level.markAndNotifyBlock` sends the updates to the neighbours and
  /// the clients. A plot chunk here is in memory, not in the host's chunk map,
  /// so it has neither neighbours nor clients to update; the level-side effects
  /// of the write (`SableCommonEvents.handleBlockChange`) already ran in
  /// [setBlockStateAt], which is the port's `LevelChunk.setBlockState` hook.
  ///
  /// Deliberately not a second [setBlockStateAt]-style hook: `moveBlocks` calls
  /// this for every block after writing it (and again after the whole batch), so
  /// hanging the mass delta off it would count every moved block twice.
  @override
  void notifyBlockChanged(int x, int y, int z, BState oldState, BState newState) {}
}

/// The plugin's data folder, as a `SableFileStore`.
///
/// Paths are relative to the plugin's data folder, so `world/sublevels/r.0.0.slvlr`
/// lands in `<data>/world/sublevels/`, the same layout the Java mod writes under
/// `<world>/sublevels/`.
final class PumpkinFileStore implements SableFileStore {
  PumpkinFileStore(this.folder);

  final DataFolder folder;

  @override
  bool exists(String path) => folder.exists(path);

  @override
  List<int> readBytes(String path) => folder.readAsBytes(path);

  @override
  void writeBytes(String path, List<int> bytes) => folder.writeAsBytes(path, bytes);

  @override
  void delete(String path) => folder.delete(path);

  @override
  void createDirectory(String path) => folder.createDirectory(path);

  @override
  List<String> list(String path) => [
    for (final entry in folder.list(path)) entry.name,
  ];
}
