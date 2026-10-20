// `dev.ryanhcode.sable.sublevel.plot.HeatDataChunkSection`: the splitting heat
// map of one 16³ section.
//
// One `short` per block: 0 means "not reached", anything else is the BFS
// distance from the flood-fill root. It is not part of the saved chunk; it is
// rebuilt as blocks change.
//
// Pure: no host imports.

/// The heat map of one chunk section.
final class HeatDataChunkSection {
  /// `SIZE`: the number of data points.
  static const int size = 16 * 16 * 16;

  final List<int> _data = List<int>.filled(size, 0);

  /// `getIndex(x, y, z)`.
  static int indexOf(int x, int y, int z) => (y << 8) | (z << 4) | x;

  /// The heat at the section-local position, `0` when unreached.
  int get(int x, int y, int z) => _data[indexOf(x, y, z)];

  /// Sets the heat at the section-local position.
  void set(int x, int y, int z, int value) => _data[indexOf(x, y, z)] = value;

  /// Clears every point.
  void clear() => _data.fillRange(0, size, 0);

  @override
  String toString() => 'HeatDataChunkSection(${_data.where((v) => v != 0).length} reached)';
}
