// `dev.ryanhcode.sable.sublevel.plot.ServerLevelPlot`: the server-side plot.
//
// It owns the plot's chunks, the biome of the whole plot, its light engine and
// the contraptions and lift providers inside it, and it saves/loads the chunk
// grid as one NBT compound (`plot_x`, `plot_z`, `log_size`, `biome`,
// `data_version`, `chunks`).
//
// Chunk serialization itself is host work (`PlotChunkHost.serializeChunk`): the
// Pumpkin API has no paletted-container access, so the host stores the chunk
// blob opaquely and the plot only lays out the compound.
//
// Pure: no host imports (chunk access goes through `PlotChunkHost`).
//
// create's `Pos` is not exported from its public barrel yet; imported from
// `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;
import '../api/block/block_entity_sub_level_actor.dart';
import '../api/block/block_entity_sub_level_reaction_wheel.dart';
import '../api/physics.dart';
import '../host/sub_level_host.dart';
import '../network/wire.dart' show SableBufferUtils;
import 'level_plot.dart';
import 'plot_chunk_holder.dart';
import 'server_sub_level.dart';

/// A plot of a server sub-level.
final class ServerLevelPlot extends LevelPlot {
  /// The current save format version (Java `DATA_VERSION`).
  static const int dataVersion = 1;

  /// The plot's light engine, when the host provides one.
  ///
  /// HOST GAP: Pumpkin does not expose a per-plot `LevelLightEngine`, so this is
  /// `null` and every lighting call below is a no-op with a precise gap note.
  Object? lightEngine;

  /// The contraptions inside this plot.
  final Set<KinematicContraption> contraptions = {};

  /// The lift providers inside this plot, by packed block position.
  final Map<int, LiftProviderContext> liftProviders = {};

  ServerLevelPlot(super.container, super.x, super.z, super.logSize, super.subLevel);

  /// Adds a contraption to this plot.
  void addContraption(KinematicContraption contraption) => contraptions.add(contraption);

  /// Removes a contraption from this plot.
  void removeContraption(KinematicContraption contraption) => contraptions.remove(contraption);

  /// The contraptions of this plot.
  Iterable<KinematicContraption> getContraptions() => contraptions;

  /// Ticks this plot: the lighting updates Java runs here, plus the pending
  /// block ticks the chunk serialiser keeps (`LevelPlot.tick` drains them;
  /// this override exists so the comment that used to claim "no plot light
  /// engine yet" names what the tick does do).
  @override
  void tick() => super.tick();

  @override
  Object? getLightEngine() => lightEngine;

  @override
  void onRemoveChunkHolder(PlotChunk chunk) {
    // Java unloads the chunk from the chunk map here (and fires the chunk
    // unload event). The host owns chunk lifetime for plot chunks.
    chunkHost.setChunkLoaded(chunk.pos.$1, chunk.pos.$2, false);
  }

  /// Sets the biome of the whole plot.
  void setBiome(String biome) => this.biome = biome;

  /// Initializes lighting for a freshly loaded chunk.
  ///
  /// HOST GAP: needs a per-plot `LevelLightEngine`. The host guards on
  /// [lightEngine] being present; calling this without one is an error rather
  /// than a silent no-op.
  void initializeLight(PlotChunk chunk) {
    if (lightEngine == null) {
      throw UnimplementedError(
        'HOST GAP: ServerLevelPlot.initializeLight needs a per-plot light engine; '
        'set ServerLevelPlot.lightEngine once the host provides one.',
      );
    }
  }

  /// Corrects the lighting of a chunk after loading.
  ///
  /// HOST GAP: needs a plot light engine (`correctLight`).
  void correctLight(PlotChunk chunk) {
    if (lightEngine == null) {
      throw UnimplementedError(
        'HOST GAP: ServerLevelPlot.correctLight needs a per-plot light engine; '
        'set ServerLevelPlot.lightEngine once the host provides one.',
      );
    }
  }

  /// Queues a lighting update for a chunk.
  ///
  /// HOST GAP: needs a plot light engine (`lightChunk`).
  void lightChunk(PlotChunk chunk) {
    if (lightEngine == null) {
      throw UnimplementedError(
        'HOST GAP: ServerLevelPlot.lightChunk needs a per-plot light engine; '
        'set ServerLevelPlot.lightEngine once the host provides one.',
      );
    }
  }

  @override
  void addChunkHolder((int, int) localChunkPos, PlotChunkHolder holder, bool initializeLighting) {
    super.addChunkHolder(localChunkPos, holder, initializeLighting);
    // Without a host light engine the chunks stay unlit; that is the explicit
    // signal the host could not provide one (see [lightEngine]).
    if (initializeLighting && lightEngine != null) {
      initializeLight(holder.chunk);
      lightChunk(holder.chunk);
    }
  }

  /// Removes every entity inside the plot.
  ///
  /// HOST GAP: the model has no entity index for plot chunks; the host
  /// implementation (`PlotChunkHost.kickEntitiesIn`) does the work.
  void kickAllEntities() {
    for (final holder in loadedChunks) {
      chunkHost.kickEntitiesIn(holder.chunk);
    }
  }

  /// Removes every block of the plot (used when a sub-level is deleted).
  void destroyAllBlocks() {
    for (final holder in loadedChunks) {
      final chunk = holder.chunk;
      for (var i = 0; i < chunk.sectionsCount; i++) {
        if (chunk.sectionHasOnlyAir(i)) continue;
        final minY = chunk.sectionMinY(i);
        for (var x = 0; x < 16; x++) {
          for (var y = 0; y < 16; y++) {
            for (var z = 0; z < 16; z++) {
              if (chunk.blockAt(x, y + minY, z) == 'minecraft:air') continue;
              chunkHost.setBlock(
                (chunk.pos.$1 << 4) + x,
                minY + y,
                (chunk.pos.$2 << 4) + z,
                'minecraft:air',
              );
            }
          }
        }
      }
    }
    updateBoundingBox();
  }

  /// Creates a chunk without lighting it (the load path initializes lighting in
  /// one batch afterwards).
  void newNonLitChunk((int, int) pos) {
    final chunk = chunkHost.createEmptyChunk(pos.$1, pos.$2);
    newChunk(pos, chunk, false);
  }

  /// Serializes the plot to the NBT-shaped map `SubLevelSerializer` stores.
  Map<String, Object?> save() {
    final tag = <String, Object?>{
      'plot_x': plotPos.$1 - container.getOrigin().$1,
      'plot_z': plotPos.$2 - container.getOrigin().$2,
      'log_size': logSize,
      'biome': biome,
      'data_version': dataVersion,
    };

    final chunks = <String, Object?>{};
    for (final holder in loadedChunks) {
      final global = holder.pos;
      final local = toLocal(global);
      // `ServerLevelPlot.java:420`: the key is `ChunkPos.pack(localX, localZ)`
      // as a decimal string, not the port's old `"x,z"`: Java cannot parse that,
      // and the port must read Java's keys.
      chunks['${SableBufferUtils.packChunk(local.$1, local.$2)}'] =
          chunkHost.serializeChunk(holder.chunk);
    }
    tag['chunks'] = chunks;
    return tag;
  }

  /// Deserializes a plot from the map produced by [save].
  ///
  /// Throws [ArgumentError] for a log-size mismatch or an unsupported version,
  /// like the Java method.
  void load(Map<String, Object?> tag) {
    final savedLogSize = (tag['log_size'] as num?)?.toInt() ?? 0;
    if (savedLogSize != logSize) {
      throw ArgumentError('Log size mismatch: plot is $logSize, data is $savedLogSize');
    }

    final version = (tag['data_version'] as num?)?.toInt() ?? 0;
    if (version < 0 || version > dataVersion) {
      throw ArgumentError('Unsupported version: $version');
    }

    final biomeName = tag['biome'];
    if (biomeName is String && biomeName.isNotEmpty) {
      biome = biomeName;
    }

    final chunks = tag['chunks'];
    if (chunks is! Map) return;

    for (final entry in chunks.entries) {
      final key = entry.key as String;
      // `ServerLevelPlot.java:453`: the key is `Long.parseLong`, i.e. a packed
      // `ChunkPos`. A key that is neither packed nor the port's old `"x,z"` is
      // reported rather than skipped: silently dropping it loses the blocks.
      final packed = int.tryParse(key);
      final int localX;
      final int localZ;
      if (packed != null) {
        localX = SableBufferUtils.unpackChunkX(packed);
        localZ = SableBufferUtils.unpackChunkZ(packed);
      } else {
        final parts = key.split(',');
        if (parts.length != 2 || int.tryParse(parts[0]) == null || int.tryParse(parts[1]) == null) {
          onChunkKeyError?.call(key);
          continue;
        }
        localX = int.parse(parts[0]);
        localZ = int.parse(parts[1]);
      }
      final local = (localX, localZ);
      final global = toGlobal(local);
      final chunkTag = entry.value;
      if (chunkTag is! Map) {
        onChunkKeyError?.call(key);
        continue;
      }

      final chunk = chunkHost.deserializeChunk(global.$1, global.$2, Map<String, Object?>.from(chunkTag));
      addChunkHolder(local, PlotChunkHolder.create(chunk, global), false);
      if (lightEngine != null) lightChunk(chunk);
      chunkHost.startTickingChunk(chunk);
    }

    updateBoundingBox();
  }

  @override
  void onBlockChange(Pos pos, String state) {
    super.onBlockChange(pos, state);

    final packed = packBlockPos(pos);
    liftProviders.remove(packed);

    final context = liftProviderAt(pos, state);
    if (context != null) liftProviders[packed] = context;
  }

  /// The lift provider lookup of the compat layer (the Create blocks).
  ///
  /// Dart block states are data, so a block cannot implement
  /// `BlockSubLevelLiftProvider` itself; the compat layer registers a lookup by
  /// block key instead and installs it here.
  static LiftProviderContext? Function(Pos pos, String state)? liftProviderLookup;

  /// Reports a `chunks` key of a loaded plot that is neither a packed `ChunkPos`
  /// (what Java writes) nor the port's legacy `"x,z"`.
  ///
  /// Java's `Long.parseLong` throws and the whole sub-level fails to load; the
  /// port skips the one chunk, but only after reporting it — a skipped chunk is
  /// missing blocks. Installed by the host.
  static void Function(String key)? onChunkKeyError;

  /// The lift provider context of the block at [pos], when the block is a lift
  /// provider.
  LiftProviderContext? liftProviderAt(Pos pos, String state) => liftProviderLookup?.call(pos, state);

  /// The sub-level actor block entity at [pos], or `null`.
  ///
  /// HOST GAP: the host cannot look up a block entity inside a plot chunk; the
  /// plugin's block entity store supplies this once plot chunks are host-owned.
  @override
  BlockEntitySubLevelActor? actorAt(Pos pos) => null;

  /// The reaction wheel block entity at [pos], or `null`.
  ///
  /// HOST GAP: same as [actorAt].
  @override
  BlockEntitySubLevelReactionWheel? reactionWheelAt(Pos pos) => null;

  /// All lift providers of this plot.
  Iterable<LiftProviderContext> getLiftProviders() => liftProviders.values;

  @override
  ServerSubLevel getSubLevel() => super.getSubLevel() as ServerSubLevel;
}

/// `BlockSubLevelLiftProvider.LiftProviderContext`: a lift provider block and
/// the normal of the face it lifts along.
final class LiftProviderContext {
  final Pos pos;
  final String state;

  /// The direction the block lifts along (`Vec3` of the direction's step).
  final (double, double, double) dir;

  const LiftProviderContext(this.pos, this.state, this.dir);

  @override
  String toString() => 'LiftProviderContext[$pos, $state, $dir]';
}

/// Packs a block position the way `BlockPos.asLong` does (x 26 bits, z 26 bits,
/// y 12 bits), matching `create`'s `packPos`.
int packBlockPos(Pos pos) =>
    ((pos.$1 & 0x3FFFFFF) << 38) | ((pos.$3 & 0x3FFFFFF) << 12) | (pos.$2 & 0xFFF);
