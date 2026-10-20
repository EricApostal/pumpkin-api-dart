// `dev.ryanhcode.sable.util.BoundedBitVolume3i`: a bounded 3D bit set with one
// bit per block in the bounds.
//
// Used by water occlusion regions. The index layout matches Java:
// `(localX * zSpan * ySpan) + (localZ * ySpan) + localY`, so a saved volume
// reads back the same.
//
// Pure: no host imports.
import 'dart:typed_data';

/// A bounded 3D bit set.
final class BoundedBitVolume3i {
  final int minX, minY, minZ;
  final int maxX, maxY, maxZ;
  final Uint32List _bits;

  BoundedBitVolume3i(this.minX, this.minY, this.minZ, this.maxX, this.maxY, this.maxZ)
    : _bits = Uint32List((_volume(minX, minY, minZ, maxX, maxY, maxZ) + 31) >> 5) {
    if (maxX < minX || maxY < minY || maxZ < minZ) {
      throw ArgumentError('Invalid bounding box construction');
    }
  }

  static int _volume(int minX, int minY, int minZ, int maxX, int maxY, int maxZ) =>
      (maxX - minX + 1) * (maxY - minY + 1) * (maxZ - minZ + 1);

  /// `fromBlocks`: the tight volume around [blocks], with every block set.
  /// Returns `null` for an empty iterable.
  static BoundedBitVolume3i? fromBlocks(Iterable<(int, int, int)> blocks) {
    final list = blocks.toList();
    if (list.isEmpty) return null;

    var minX = list.first.$1, minY = list.first.$2, minZ = list.first.$3;
    var maxX = minX, maxY = minY, maxZ = minZ;
    for (final block in list.skip(1)) {
      if (block.$1 < minX) minX = block.$1;
      if (block.$2 < minY) minY = block.$2;
      if (block.$3 < minZ) minZ = block.$3;
      if (block.$1 > maxX) maxX = block.$1;
      if (block.$2 > maxY) maxY = block.$2;
      if (block.$3 > maxZ) maxZ = block.$3;
    }

    final set = BoundedBitVolume3i(minX, minY, minZ, maxX, maxY, maxZ);
    for (final block in list) {
      set.setOccupied(block.$1, block.$2, block.$3, true);
    }
    return set;
  }

  /// Sets the occupied status of a global cell.
  void setOccupied(int x, int y, int z, bool occupied) {
    if (!isInBounds(x, y, z)) {
      throw ArgumentError('Cannot set out of bounds!');
    }
    final index = getIndex(x, y, z);
    if (occupied) {
      _bits[index >> 5] |= 1 << (index & 31);
    } else {
      _bits[index >> 5] &= ~(1 << (index & 31)) & 0xFFFFFFFF;
    }
  }

  /// The occupied status of a cell; `false` when out of bounds.
  bool getOccupied(int x, int y, int z) {
    if (!isInBounds(x, y, z)) return false;
    final index = getIndex(x, y, z);
    return (_bits[index >> 5] & (1 << (index & 31))) != 0;
  }

  /// The index of a global coordinate, or `-1` when out of bounds.
  int getIndex(int x, int y, int z) {
    if (!isInBounds(x, y, z)) return -1;
    final localX = x - minX;
    final localY = y - minY;
    final localZ = z - minZ;
    return (localX * zSpan * ySpan) + (localZ * ySpan) + localY;
  }

  int volume() => xSpan * ySpan * zSpan;

  int get xSpan => maxX - minX + 1;
  int get ySpan => maxY - minY + 1;
  int get zSpan => maxZ - minZ + 1;

  bool isInBounds(int x, int y, int z) =>
      x >= minX && x <= maxX && y >= minY && y <= maxY && z >= minZ && z <= maxZ;

  (int, int, int) getMinBlockPos() => (minX, minY, minZ);

  (int, int, int) getMaxBlockPos() => (maxX, maxY, maxZ);

  /// The raw words (the Java `BitSet`'s internal storage order differs; this is
  /// for the port's own persistence).
  Uint32List get words => _bits;

  @override
  String toString() => 'BoundedBitVolume3i[($minX, $minY, $minZ) -> '
      '($maxX, $maxY, $maxZ), volume=$volume()]';
}
