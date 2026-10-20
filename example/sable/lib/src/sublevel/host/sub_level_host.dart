// What the sub-level model needs from a host, as plain Dart interfaces.
//
// Sable's Java code is written against `net.minecraft.server.level.ServerLevel`
// and NeoForge/Fabric events; the loader abstraction (`platform/Sable*Platform`)
// is collapsed here into these interfaces. The pure model (containers, plots,
// storage bookkeeping) only ever talks to this file, so it runs on the VM in
// tests; `host/pumpkin_level.dart` is the implementation over Pumpkin, and every
// capability Pumpkin does not expose yet is a `HOST GAP` there.
//
// Pure: no host imports.
import '../math/bounding_box.dart';
import '../math/pose.dart';

/// A dimension of the server, as the sub-level model sees it.
abstract interface class SableLevel {
  /// `Level.dimension().identifier().toString()`.
  String get dimensionId;

  /// `Level.isClientSide`.
  bool get isClientSide;

  /// `Level.getMinY()`.
  int get minY;

  /// `Level.getMaxY()`.
  int get maxY;

  /// `Level.getGameTime()`.
  int get gameTime;

  /// `Level.getSectionsCount()`.
  int get sectionsCount => (maxY - minY) >> 4;
}

/// One chunk of the plot yard, as far as the plot cares.
///
/// The real object owns block states, block entities, light and ticks; the
/// sub-level model only needs to know it exists and whether it is empty.
abstract interface class PlotChunk {
  /// The chunk position, in global chunk coordinates.
  (int, int) get pos;

  /// `LevelChunk.getSectionsCount()`.
  int get sectionsCount;

  /// `LevelChunkSection.hasOnlyAir()` for every section.
  bool get hasOnlyAir;

  /// `LevelChunk.getBlockEntityNbtForSaving`-style data for one block, or `null`.
  Map<String, Object?>? blockEntityData(int x, int y, int z);

  /// The block key (`minecraft:stone`) at the local position.
  String blockAt(int x, int y, int z);
}

/// The chunk-level operations of the plot yard: loading chunks at the yard's
/// distant origin, keeping them loaded, and reporting whether they are.
///
/// This is the part of `ServerLevel`/`ChunkMap` the sub-level model uses. The
/// Pumpkin implementation is `host/pumpkin_level.dart`.
abstract interface class PlotChunkHost {
  /// The level this host serves.
  SableLevel get level;

  /// `level.isLoaded(BlockPos)`.
  bool isBlockLoaded(int x, int y, int z);

  /// `level.getChunk(x, z)`, or `null` when it is not loaded.
  PlotChunk? getLoadedChunk(int x, int z);

  /// Creates an empty chunk at the global chunk position and marks it loaded,
  /// as `LevelPlot.newEmptyChunk` does.
  ///
  /// HOST GAP: Pumpkin has no API to create a `LevelChunk` at an arbitrary
  /// position outside the generated world; see `host/pumpkin_level.dart`.
  PlotChunk createEmptyChunk(int x, int z);

  /// Marks the chunk loaded/unloaded for the plot yard's bookkeeping.
  void setChunkLoaded(int x, int z, bool loaded);

  /// Requests a chunk to be kept loaded (`TicketType` in the Java code).
  void addChunkTicket(int x, int z, String ticketType, int level);

  /// Removes a ticket added with [addChunkTicket].
  void removeChunkTicket(int x, int z, String ticketType, int level);

  /// Whether the chunk is loaded "enough" for physics (Java
  /// `PhysicsChunkTicketManager.isChunkLoadedEnough`).
  bool isChunkLoadedEnough(int x, int z);
}

/// A player of the server, as far as tracking needs them.
abstract interface class SablePlayer {
  /// `Player.getUUID().toString()`.
  String get uuid;

  /// `Player.position()`.
  (double, double, double) get position;

  /// `Player.level().dimension()`.
  String get dimensionId;
}

/// Where sub-level data is persisted. Sable writes its own region files under
/// `<world>/sublevels`; the port uses the plugin's `DataFolder` instead, which
/// is a sandboxed folder (see `storage/sub_level_storage.dart`).
abstract interface class SableFileStore {
  bool exists(String path);
  List<int> readBytes(String path);
  void writeBytes(String path, List<int> bytes);
  void delete(String path);
  void createDirectory(String path);
  List<String> list(String path);
}

/// The per-level state the model needs that is not chunk or file access:
/// saved data, players and the sub-level lookup used by water occlusion and
/// tracking points.
abstract interface class SubLevelHost {
  PlotChunkHost get chunks;

  /// Every player of the server.
  Iterable<SablePlayer> get players;

  /// `level.getPlayerByUUID`.
  SablePlayer? playerById(String uuid);

  /// The sub-level containing the given world position, if any
  /// (`Sable.HELPER.getContaining`).
  SubLevelLookup get subLevels;

  /// The pose the sub-level has in the physics pipeline (used while saving:
  /// the serialized pose is recentred on the centre of mass).
  Pose3dc poseForSaving(String subLevelId);

  /// The centre of mass of the sub-level's own blocks.
  (double, double, double) centerOfMass(String subLevelId);

  /// The sub-level's linear and angular velocity, if it has a physics body.
  (double, double, double, double, double, double)? velocity(String subLevelId);

  /// `SavedDataStorage.computeIfAbsent`: the raw saved data of [name], or `null`.
  Map<String, Object?>? readSavedData(String name);

  /// Marks the saved data [name] dirty (it is written at the end of the tick).
  void markSavedDataDirty(String name);

  /// Writes the saved data [name] now.
  void writeSavedData(String name, Map<String, Object?> data);
}

/// Resolves the sub-level containing a world position.
abstract interface class SubLevelLookup {
  /// The sub-level whose pose contains [position] in [dimensionId], or `null`.
  Object? containing(String dimensionId, (double, double, double) position);

  /// The sub-level tracking [player] (`Sable.HELPER.getTrackingSubLevel`).
  Object? trackingSubLevel(SablePlayer player);
}

/// A bounding box in the level, for the physics query surface.
typedef BoundsQuery = BoundingBox3dc;
