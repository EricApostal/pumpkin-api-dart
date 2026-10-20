// One horizontal slice of a balloon, stored as 8x8 bit masks.
//
// Java: `content/blocks/hot_air/balloon/graph/BalloonLayerData`.
//
// A layer keeps two masks per 8x8 chunk of its Y plane: the blocks that are
// part of the balloon's air volume, and the ones that are solid (non-air) but
// not airtight, which take up volume. Iterating a layer yields the hot-air
// blocks of the plane.
//
// Pure: no host imports.
import 'package:create/src/common/pos.dart' show Pos;

/// `BalloonLayerData`.
final class BalloonLayerData {
  /// Shift of the 8x8 chunk grid.
  static const int layerChunkShift = 3;

  /// Mask of the 8x8 chunk grid.
  static const int layerChunkMask = 7;

  /// `blockToChunkCoord`.
  static int blockToChunkCoord(int x) => x >> layerChunkShift;

  /// `getBlockIndex`: the bit of [x], [z] inside its 8x8 chunk.
  static int getBlockIndex(int x, int z) =>
      ((x & layerChunkMask) << layerChunkShift) + (z & layerChunkMask);

  /// The Y level of this slice.
  final int yLevel;

  /// Packed (chunkX, chunkZ) -> the 64-bit mask of hot-air blocks.
  final Map<(int, int), int> chunks = {};

  /// Packed (chunkX, chunkZ) -> the 64-bit mask of solid blocks.
  final Map<(int, int), int> solidChunks = {};

  /// All connections going into this layer.
  final Set<BalloonLayerData> inwardConnections = {};

  /// All connections going out of this layer.
  final Set<BalloonLayerData> outwardConnections = {};

  /// The number of hot-air blocks.
  int hotAirCount = 0;

  /// The number of solid (non-air) blocks inside the volume.
  int solidCount = 0;

  /// Whether the chunk bounds below were set at least once.
  bool boundsInitialized = false;

  int minChunkX = 0;
  int minChunkZ = 0;
  int maxChunkX = 0;
  int maxChunkZ = 0;

  /// `State`: whether the builder still has to look below this layer.
  BalloonLayerDataState state = BalloonLayerDataState.needsDownPass;

  BalloonLayerData(this.yLevel);

  /// The mask of hot-air blocks of the chunk containing [x], [z].
  int hotAirChunkAtBlock(int x, int z) => chunks[(x >> layerChunkShift, z >> layerChunkShift)] ?? 0;

  /// The mask of solid blocks of the chunk containing [x], [z].
  int solidsChunkAtBlock(int x, int z) => solidChunks[(x >> layerChunkShift, z >> layerChunkShift)] ?? 0;

  /// Marks [x], [z] as a hot-air block and grows the chunk bounds.
  void addHotAirBlock(int x, int z) {
    final chunkX = x >> layerChunkShift;
    final chunkZ = z >> layerChunkShift;
    final key = (chunkX, chunkZ);
    final previous = chunks[key] ?? 0;

    if (previous == 0) {
      if (!boundsInitialized) {
        minChunkX = chunkX;
        minChunkZ = chunkZ;
        maxChunkX = chunkX;
        maxChunkZ = chunkZ;
        boundsInitialized = true;
      } else {
        if (chunkX < minChunkX) minChunkX = chunkX;
        if (chunkZ < minChunkZ) minChunkZ = chunkZ;
        if (chunkX > maxChunkX) maxChunkX = chunkX;
        if (chunkZ > maxChunkZ) maxChunkZ = chunkZ;
      }
    }

    chunks[key] = previous | (1 << getBlockIndex(x, z));
  }

  /// Marks [x], [z] as solid.
  void addSolidBlock(int x, int z) {
    final key = (x >> layerChunkShift, z >> layerChunkShift);
    solidChunks[key] = (solidChunks[key] ?? 0) | (1 << getBlockIndex(x, z));
  }

  /// Clears [x], [z] from the hot-air mask.
  void removeHotAirBlock(int x, int z) {
    final key = (x >> layerChunkShift, z >> layerChunkShift);
    final previous = chunks[key] ?? 0;
    if (previous == 0) return;
    chunks[key] = previous & ~(1 << getBlockIndex(x, z));
  }

  /// Clears [x], [z] from the solid mask.
  void removeSolidBlock(int x, int z) {
    final key = (x >> layerChunkShift, z >> layerChunkShift);
    final previous = solidChunks[key] ?? 0;
    if (previous == 0) return;
    solidChunks[key] = previous & ~(1 << getBlockIndex(x, z));
  }

  /// Whether two layers of adjacent Y planes share at least one hot-air
  /// block's (x, z) column, so the balloon connects through them.
  bool overlaps(BalloonLayerData other) {
    if (!boundsInitialized || !other.boundsInitialized) return false;

    final fromX = minChunkX > other.minChunkX ? minChunkX : other.minChunkX;
    final fromZ = minChunkZ > other.minChunkZ ? minChunkZ : other.minChunkZ;
    final toX = maxChunkX < other.maxChunkX ? maxChunkX : other.maxChunkX;
    final toZ = maxChunkZ < other.maxChunkZ ? maxChunkZ : other.maxChunkZ;

    if (fromX > toX || fromZ > toZ) return false;

    for (var chunkX = fromX; chunkX <= toX; chunkX++) {
      for (var chunkZ = fromZ; chunkZ <= toZ; chunkZ++) {
        final key = (chunkX, chunkZ);
        final mine = chunks[key] ?? 0;
        final theirs = other.chunks[key] ?? 0;
        if (mine & theirs != 0) return true;
      }
    }

    return false;
  }

  /// Whether [x], [z] is a hot-air block of this layer.
  bool getHotAirBlock(int x, int z) {
    final chunk = hotAirChunkAtBlock(x, z);
    if (chunk == 0) return false;
    return ((chunk >> getBlockIndex(x, z)) & 1) != 0;
  }

  /// Whether [x], [z] is a solid block inside the volume.
  bool getSolidBlock(int x, int z) {
    final chunk = solidsChunkAtBlock(x, z);
    if (chunk == 0) return false;
    return ((chunk >> getBlockIndex(x, z)) & 1) != 0;
  }

  /// Every hot-air block of this layer.
  Iterable<Pos> get blocks => _iterate(ignoreSolids: false);

  /// Every hot-air block that is not solid.
  Iterable<Pos> get nonSolidBlocks => _iterate(ignoreSolids: true);

  Iterable<Pos> _iterate({required bool ignoreSolids}) sync* {
    for (final entry in chunks.entries) {
      final (chunkX, chunkZ) = entry.key;
      var bits = entry.value;
      if (bits == 0) continue;
      final solids = ignoreSolids ? (solidChunks[entry.key] ?? 0) : 0;
      bits &= ~solids;
      while (bits != 0) {
        final index = _lowestBit(bits);
        bits &= bits - 1;
        yield (
          (chunkX << layerChunkShift) + (index >> layerChunkShift),
          yLevel,
          (chunkZ << layerChunkShift) + (index & layerChunkMask),
        );
      }
    }
  }

  static int _lowestBit(int value) {
    var index = 0;
    var v = value;
    while ((v & 1) == 0) {
      v >>= 1;
      index++;
    }
    return index;
  }

  /// The chunk keys of the hot-air blocks (for the bounds of a balloon).
  Iterable<(int, int)> get chunkKeys => chunks.keys;

  @override
  String toString() => 'BalloonLayerData(y: $yLevel, hotAir: $hotAirCount, solid: $solidCount)';
}

/// `BalloonLayerData.State`.
enum BalloonLayerDataState { needsDownPass, complete }
