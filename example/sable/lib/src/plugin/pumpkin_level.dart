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
import 'package:create/src/api/blocks.dart' show HostBlockGetter, setBlockState, stateIdOf;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_api/src/host_result.dart' show unwrapHostAsync;

import '../sublevel/api/sub_level_assembly_helper.dart' show AssemblyBlockHost, BatchingBlockHost, BulkBlockHost;
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

  /// The pending scheduled block ticks, by packed local position.
  ///
  /// A plot chunk is never in the host's chunk map, so the host's tick
  /// scheduler cannot see its blocks — `World.scheduleBlockTick` does nothing
  /// for a yard position. Ticks of plot blocks live here instead: [delay]
  /// counts down once per container tick, and `LevelPlot.tick` fires the due
  /// ones back into the block behaviours. The tick survives the chunk's
  /// save/load (`block_ticks` in [save]).
  @override
  final Map<int, PlotScheduledTick> blockTicks = {};

  @override
  int indexOfBlock(int x, int y, int z) => indexOf(x, y, z);

  @override
  void scheduleBlockTick(int x, int y, int z, PlotScheduledTick tick) =>
      blockTicks[indexOf(x, y, z)] = tick;

  /// Removes the scheduled ticks of an emptied block, like the host's tick
  /// scheduler drops the ticks of a replaced block.
  void clearTicksAt(int x, int y, int z) {
    blockTicks.remove(indexOf(x, y, z));
  }

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
    // The keys are stringified like `blocks`/`block_ticks` above: the plot loader reads them with
    // `entry.key as String` (`sublevel/model/server_level_plot.dart:214`), so an int key here made
    // every save that carries a block entity fail to decode ("Type 'int' is not a subtype of type
    // 'String' in type cast") while a stone-only region round-tripped cleanly.
    if (blockEntities.isNotEmpty)
      'block_entities': {
        for (final entry in blockEntities.entries) '${entry.key}': entry.value,
      },
    if (blockTicks.isNotEmpty)
      'block_ticks': {
        for (final entry in blockTicks.entries)
          '${entry.key}': {'delay': entry.value.delay, 'priority': entry.value.priority.index},
      },
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
    blockTicks.clear();
    final savedTicks = tag['block_ticks'];
    if (savedTicks is Map) {
      for (final entry in savedTicks.entries) {
        final index = int.tryParse('${entry.key}');
        final value = entry.value;
        if (index == null || value is! Map) continue;
        final delay = (value['delay'] as num?)?.toInt();
        final priority = (value['priority'] as num?)?.toInt();
        if (delay == null || delay < 0) continue;
        blockTicks[index] = PlotScheduledTick(
          delay,
          priority != null && priority >= 0 && priority < PlotTickPriority.values.length
              ? PlotTickPriority.values[priority]
              : PlotTickPriority.normal,
        );
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

  /// A world chunk is never a plot: the host's scheduler owns its ticks
  /// (`World.scheduleBlockTick`), so there is nothing to keep here.
  @override
  Map<int, PlotScheduledTick> get blockTicks => const {};

  @override
  int indexOfBlock(int x, int y, int z) => ((y & 0xFFF) << 8) | ((z & 15) << 4) | (x & 15);

  @override
  void scheduleBlockTick(int x, int y, int z, PlotScheduledTick tick) {
    // A world chunk is never a plot: the host's scheduler owns its ticks, so
    // the schedule is a no-op (the default `PlotChunk.scheduleBlockTick` would
    // write into the const map above and throw).
  }
}

/// The chunk host of one level: world chunks through the plugin API, plot
/// chunks in memory.
///
/// Implements [AssemblyBlockHost] as well, so assembly moves block states with
/// their properties instead of falling back to the key-only adapter (which
/// refuses block-entity moves).
final class PumpkinPlotChunkHost implements PlotChunkHost, AssemblyBlockHost, BatchingBlockHost, BulkBlockHost {
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
  void clear() {
    _plotChunks.clear();
    clearMirrors();
  }

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
  /// there is no per-chunk load flag to set. The unload half is where the world
  /// copy of a plot chunk is dropped: the plot gave the chunk up, so the yard
  /// chunk it was mirrored into is released with it (Java unloads the plot's
  /// `LevelChunk` from the chunk map here).
  @override
  void setChunkLoaded(int x, int z, bool loaded) {
    if (loaded) return;
    final key = _key(x, z);
    _mirrorIndex.remove(key);
    if (!_mirrorRequests.remove(key)) return;
    final release = onYardChunkRelease;
    if (release == null) return;
    unawaited(
      release(level.dimensionId, x, z).catchError((Object error) {
        diagTicketError('mirror ($x, $z): releasing the load request failed: $error');
      }),
    );
  }

  /// The tickets this host holds, by `(chunkX, chunkZ, type)`.
  final Map<(int, int, String), Future<int?>> _chunkTickets = {};

  /// Force-loads a **world** chunk for the level (`PhysicsChunkTicketManager
  /// .inhabitChunk` -> `level.getChunk(x, z, FULL, true)`).
  ///
  /// Only world chunks: a plot-yard position has no host chunk to load (the plot
  /// blocks live in [MemoryPlotChunk]), and asking the host for a chunk 20M
  /// blocks out just makes worldgen write terrain into the yard — the
  /// `chunk-source` gap. The yard's own "kept loaded" state is the entry in
  /// [_plotChunks].
  ///
  /// The host call is asynchronous, so the ticket handle is stored as a future;
  /// [removeChunkTicket] releases it once it exists.
  @override
  void addChunkTicket(int x, int z, String ticketType, int level) {
    if (_inYard(x, z)) return;
    final key = (x, z, ticketType);
    if (_chunkTickets.containsKey(key)) return;
    _chunkTickets[key] = chunkTickets.forceLoadChunk(worldRef: this.level.world, x: x, z: z).then(
      (result) => switch (result) {
        OkResult(value: final handle) => handle,
        ErrorResult(value: final error) => () {
          diagTicketError('force-load ($x, $z) failed: $error');
          _chunkTickets.remove(key);
          return null;
        }(),
      },
      onError: (Object error) {
        diagTicketError('force-load ($x, $z) threw: $error');
        _chunkTickets.remove(key);
        return null;
      },
    );
  }

  @override
  void removeChunkTicket(int x, int z, String ticketType, int level) {
    final ticket = _chunkTickets.remove((x, z, ticketType));
    if (ticket == null) return;
    unawaited(ticket.then((handle) {
      if (handle != null) chunkTickets.releaseChunkTicket(ticket: handle);
    }));
  }

  /// Releases every ticket this host holds (level unload).
  void releaseChunkTickets() {
    for (final key in _chunkTickets.keys.toList()) {
      removeChunkTicket(key.$1, key.$2, key.$3, 0);
    }
  }

  /// Asks the server to keep a yard chunk loaded, **without waiting for it**.
  ///
  /// The plugin's own `force-load-chunk` cannot be used for the yard: it waits
  /// for the chunk to be *generated* and only answers when its 60 s
  /// `LOAD_TIMEOUT` expires (`chunk_tickets.rs:63`), and that wait happens
  /// inside the host call, so the server's tick loop loses the whole minute and
  /// a watching client's 30 s keep-alive dies — measured twice, once with the
  /// call awaited and once without (not awaiting does not help: the guest's tick
  /// cannot return while the host's subtask is pending). The server's own
  /// `forceload` **marks** the same chunk and returns at once (measured: no
  /// stall), and the chunk system then generates it in the background.
  ///
  /// Set by the plugin, which owns the server handle.
  static Future<void> Function(String dimension, int chunkX, int chunkZ)? onYardChunkKeep;

  /// Releases the request made with [onYardChunkKeep].
  static Future<void> Function(String dimension, int chunkX, int chunkZ)? onYardChunkRelease;

  /// Where a failed ticket is reported; set by the plugin's logger.
  static void Function(String message)? onTicketError;

  static void diagTicketError(String message) => onTicketError?.call(message);

  /// Where the timing of one mirror phase is reported (a stopwatch per phase:
  /// `ticket`, `wipe`, `place`). The bridge costs host time in the tick that
  /// first sends a plot chunk, and a number is the only way to tell which phase
  /// pays for it.
  static void Function(String message)? onMirrorEvent;

  static void diagMirror(String message) => onMirrorEvent?.call(message);

  /// The world positions the last mirror of each plot chunk wrote, so the next
  /// mirror can clear the positions the plot no longer holds. Without it the
  /// world copy keeps the ghost of every block that moved away — and a
  /// full-column diff per mirror would cost a host call per position.
  final Map<int, Set<int>> _mirrorIndex = {};

  /// The plot chunks whose world copy this host has asked the server to keep
  /// loaded ([ensurePlotChunkWanted]).
  final Set<int> _mirrorRequests = {};

  /// Mirrors the plot chunk at [chunkX], [chunkZ] into the level's world chunk,
  /// so the host's chunk packet carries the sub-level's blocks.
  ///
  /// Java serves the plot's own `LevelChunk` to the chunk sender
  /// (`SubLevelPlayerChunkSender.createChunkPacket`): the client stores the
  /// chunk it receives under exactly these chunk coordinates, and its plot
  /// intercept (`ClientChunkCacheMixin.replaceWithPacketData`) reroutes every
  /// yard-coordinate chunk into the plot of the sub-level it is tracking. The
  /// host's `send-chunk-at` can only serialize the chunk that is *loaded in the
  /// world* at that position, so without this mirror the client would render
  /// terrain (or air) as the inside of the ship.
  ///
  /// **The load is not awaited.** The host's `force-load-chunk` waits for the
  /// chunk to be generated, and at the yard that does not happen: measured on
  /// this host, a force-load of the plot chunk (1280064, 1280064) answers after
  /// the host's 60 s `LOAD_TIMEOUT` (`chunk_tickets.rs:63`), and the *await*
  /// wedges the server's tick loop for the whole 60 s, which kills a watching
  /// client's 30 s keep-alive. So the ticket is requested and left pending
  /// ([ensurePlotChunkWanted]), and the caller only mirrors when the world
  /// already has the chunk ([isPlotChunkLoaded]) — the send then happens on a
  /// later tick, when the host has the chunk, instead of stalling the sync.
  /// Writing the plot's blocks is 0 ms (measured: 27 blocks), so the chunk's
  /// *existence* is the whole cost of making a sub-level visible.
  ///
  /// **No wipe.** A chunk the host *generates* at the yard is terrain, so the
  /// world copy below the ship holds stone the plot never had. That terrain is
  /// not rendered: the client's sub-level renderer meshes only the plot's
  /// bounding box (`VanillaChunkedSubLevelRenderData.resize` builds its render
  /// sections from `getPlot().getBoundingBox()`), and the bounds sent to the
  /// client are the ship's own block bounds. Wiping the column was tried and is
  /// not needed to *see* the sub-level; the real fix for a yard that is empty on
  /// the host is a plugin-owned chunk (`host_gap.dart`'s `chunk-source`).
  ///
  /// Returns whether the plot's blocks were written (the world had the chunk).
  Future<bool> mirrorPlotChunk(int chunkX, int chunkZ) async {
    if (!_inYard(chunkX, chunkZ)) {
      diagMirror('mirror ($chunkX, $chunkZ): not in the plot yard; nothing to mirror');
      return false;
    }
    final chunk = _plotChunks[_key(chunkX, chunkZ)];
    if (chunk == null) {
      diagMirror('mirror ($chunkX, $chunkZ): the plot has no chunk at this position');
      return false;
    }
    if (!isPlotChunkLoaded(chunkX, chunkZ)) return false;

    final key = _key(chunkX, chunkZ);
    final total = Stopwatch()..start();
    final baseX = chunkX << 4;
    final baseZ = chunkZ << 4;
    final previous = _mirrorIndex[key];
    final fresh = <int>{};
    final changes = <BlockPlacementChange>[];
    for (final entry in chunk.blocks.entries) {
      final y = (entry.key >> 8) & 0xFFF;
      if (y < level.minY || y >= level.maxY) continue;
      final x = baseX + (entry.key & 15);
      final z = baseZ + ((entry.key >> 4) & 15);
      fresh.add((y << 8) | ((z & 15) << 4) | (x & 15));
      final stateId = stateIdOf(entry.value);
      if (stateId == null) continue; // Unknown to the block table: unmirrorable.
      changes.add(BlockPlacementChange(BlockPos(x: x, y: y, z: z), stateId));
    }
    _mirrorIndex[key] = fresh;

    final placeWatch = Stopwatch()..start();
    if (changes.isNotEmpty) {
      await unwrapHostAsync(
        level.world.setBlocks(changes: [for (final c in changes) c.toWire()], updateFlags: {}),
        'mirroring plot chunk ($chunkX, $chunkZ)',
      );
    }
    if (previous != null) {
      final stalePositions = <BlockPos>[
        for (final packed in previous.difference(fresh))
          BlockPos(
            x: baseX + (packed & 15),
            y: (packed >> 8) & 0xFFF,
            z: baseZ + ((packed >> 4) & 15),
          ),
      ];
      if (stalePositions.isNotEmpty) {
        await level.world.removeBlocks(positions: stalePositions, updateFlags: {});
      }
    }
    diagMirror(
      'mirror ($chunkX, $chunkZ): ${chunk.blocks.length} blocks written in '
      '${placeWatch.elapsedMilliseconds}ms (total ${total.elapsedMilliseconds}ms)',
    );
    return true;
  }

  /// Asks the host to keep the plot chunk's world copy loaded, without waiting
  /// for it; `true` when the world already has it.
  ///
  /// The ticket lives here, next to the chunk it keeps loaded, so
  /// `addChunkTicket`'s yard guard — which skips plot positions — does not drop
  /// it, and the world's own view handling (which never reaches the far yard)
  /// never unloads it from under the mirror.
  bool ensurePlotChunkWanted(int chunkX, int chunkZ) {
    if (!_inYard(chunkX, chunkZ)) return false;
    final key = _key(chunkX, chunkZ);
    if (_mirrorRequests.add(key)) {
      final keep = onYardChunkKeep;
      if (keep == null) {
        // No server handle wired (a unit test, or a host without the surface):
        // the chunk can only be mirrored if something else loaded it.
        diagTicketError('mirror ($chunkX, $chunkZ): no yard-chunk load hook is installed');
      } else {
        diagMirror('mirror ($chunkX, $chunkZ): asking the server to keep the yard chunk loaded');
        unawaited(
          keep(level.dimensionId, chunkX, chunkZ).catchError((Object error) {
            // Keep the request: the next tick retries, and the count in the log
            // is what says the ask is not getting through.
            diagTicketError('mirror ($chunkX, $chunkZ): the load request failed: $error');
          }),
        );
      }
    }
    return isPlotChunkLoaded(chunkX, chunkZ);
  }

  /// Whether the world has the chunk that backs the plot chunk at [chunkX],
  /// [chunkZ] (the condition `chunk-streaming.send-chunk-at` needs).
  bool isPlotChunkLoaded(int chunkX, int chunkZ) => level.world.isLoaded(
    pos: BlockPos(x: chunkX << 4, y: (level.minY + level.maxY) ~/ 2, z: chunkZ << 4),
  );

  /// Forgets the world copy of a plot chunk (level unload).
  void clearMirrors() {
    _mirrorIndex.clear();
    final release = onYardChunkRelease;
    for (final key in _mirrorRequests.toList()) {
      if (release == null) break;
      final x = (key >> 32) & 0xFFFFFFFF;
      final z = key & 0xFFFFFFFF;
      unawaited(release(level.dimensionId, x, z).catchError((Object error) {}));
    }
    _mirrorRequests.clear();
  }

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

  /// Caches world-block reads for one batch of queries.
  ///
  /// The structure search re-reads the same positions constantly (18 neighbours
  /// per visited block) and every read is a host call here; `HostBlockGetter`
  /// already caches within a batch. Plot reads are in memory and need nothing.
  @override
  void beginBatch() => _worldBlocks.beginBatch();

  @override
  void endBatch() => _worldBlocks.endBatch();

  /// One host call for many reads (`World.readBlockStates`): world positions
  /// go in one `get-block-states` call, plot-yard positions (in memory) are
  /// decoded alongside. A plot position with no chunk is air, like a world
  /// position in an unloaded chunk.
  @override
  List<BState> readBlockStates(List<(int, int, int)> positions) {
    if (positions.isEmpty) return const [];
    final states = List<BState>.filled(positions.length, BState.air);
    final worldPositions = <BlockPos>[];
    final worldIndexes = <int>[];
    for (var i = 0; i < positions.length; i++) {
      final (x, y, z) = positions[i];
      if (_inYard(x >> 4, z >> 4)) {
        final chunk = _plotChunks[_key(x >> 4, z >> 4)];
        states[i] = chunk == null ? BState.air : chunk.stateAt(x & 15, y, z & 15);
      } else {
        worldIndexes.add(i);
        worldPositions.add(BlockPos(x: x, y: y, z: z));
      }
    }
    if (worldPositions.isNotEmpty) {
      final ids = level.world.readBlockStates(worldPositions);
      for (var j = 0; j < worldIndexes.length; j++) {
        states[worldIndexes[j]] = HostBlockGetter.stateOfId(ids[j]);
      }
    }
    return states;
  }

  @override
  Map<String, Object?>? blockEntityDataAt(int x, int y, int z) {
    if (_inYard(x >> 4, z >> 4)) {
      return _plotChunks[_key(x >> 4, z >> 4)]?.blockEntityData(x & 15, y, z & 15);
    }
    // A vanilla block entity's saved data as a tree (`World.getBlockEntityData`),
    // decoded to the map the assembly carries. The old HOST GAP was the missing
    // binary NBT codec; the host now serves the tree form, so a moved block
    // carries its saved data. This read path is the *proven* half: assembly
    // reaches it for a real chest (live run) and the map it returns round-trips
    // the plot store. Note the write half below is weaker — see there.
    final save = level.world.vanillaBlockEntityAt(BlockPos(x: x, y: y, z: z));
    return save?.toMap();
  }

  @override
  void setBlockEntityDataAt(int x, int y, int z, Map<String, Object?> data) {
    if (_inYard(x >> 4, z >> 4)) {
      final chunkX = x >> 4;
      final chunkZ = z >> 4;
      _memoryChunk(chunkX, chunkZ).blockEntities[MemoryPlotChunk.indexOf(x & 15, y, z & 15)] =
          Map<String, Object?>.from(data);
      return;
    }
    // The inverse for a destination outside the yard: restore the host-side
    // entity from the carried map.
    //
    // This stores the tag in the chunk's `pending_block_entities` (the form the
    // chunk save and the chunk packet use) and, only when a live entity was
    // there, drops it for a lazy rebuild — `World::apply_block_entity_nbt` does
    // not materialise an entity that was absent. The write itself is sound: the
    // host's item writer and reader agree (`id` + lowercase `count`), so data
    // that came from the host round-trips. What is NOT proven is a chest's
    // `Items` surviving a full assemble → save → reload live (no player in the
    // rig opens a container); and *legacy* item NBT (`Count`, pre-1.20.5) is
    // silently dropped by the reader rather than upgraded. See
    // `docs/host-gaps.md`.
    level.world.setVanillaBlockEntity(BlockPos(x: x, y: y, z: z), NbtCompound.fromMap(data));
  }

  @override
  void removeBlockEntityAt(int x, int y, int z) {
    if (_inYard(x >> 4, z >> 4)) {
      _plotChunks[_key(x >> 4, z >> 4)]?.blockEntities.remove(
        MemoryPlotChunk.indexOf(x & 15, y, z & 15),
      );
      return;
    }
    // The host-side clear (`World.clearVanillaBlockEntity`): removes the entity
    // a move leaves behind, which setting data cannot express.
    level.world.clearVanillaBlockEntity(BlockPos(x: x, y: y, z: z));
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
