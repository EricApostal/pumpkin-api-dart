// A fixed-size bit grid with Java `BitSet`'s long-array layout.
//
// The plot occupancy (`SubLevelContainer.occupancy`) is a `BitSet` in Java and is
// saved as `BitSet.toLongArray()`. This class keeps the same wire layout so an
// existing Sable world's occupancy data reads unchanged: word `i` holds bits
// `64i .. 64i+63`, bit `n` is `(words[n >> 6] >> (n & 63)) & 1`.
//
// Pure: no host imports.
import 'dart:typed_data';

/// A fixed-size bit grid.
final class BitGrid {
  final int length;
  final Uint32List _words;

  BitGrid(this.length) : _words = Uint32List((length + 31) >> 5);

  /// `BitSet.valueOf(long[])` restricted to [length] bits.
  BitGrid.fromLongArray(Iterable<int> longs, this.length) : _words = Uint32List((length + 31) >> 5) {
    var index = 0;
    for (final word in longs) {
      if (index >= _words.length) break;
      _words[index++] = word & 0xFFFFFFFF;
      if (index < _words.length) _words[index++] = (word >> 32) & 0xFFFFFFFF;
    }
  }

  /// `BitSet.toLongArray()`.
  List<int> toLongArray() {
    var highest = -1;
    for (var i = _words.length - 1; i >= 0; i--) {
      if (_words[i] != 0) {
        highest = i;
        break;
      }
    }
    if (highest < 0) return <int>[];
    final words = (highest >> 1) + 1;
    final out = List<int>.filled(words, 0);
    for (var w = 0; w < words; w++) {
      final low = _words[w * 2];
      final high = w * 2 + 1 < _words.length ? _words[w * 2 + 1] : 0;
      out[w] = (high << 32) | low;
    }
    return out;
  }

  bool get(int index) {
    if (index < 0 || index >= length) return false;
    return (_words[index >> 5] & (1 << (index & 31))) != 0;
  }

  void set(int index, [bool value = true]) {
    if (index < 0 || index >= length) {
      throw RangeError.range(index, 0, length - 1, 'index');
    }
    if (value) {
      _words[index >> 5] |= 1 << (index & 31);
    } else {
      _words[index >> 5] &= ~(1 << (index & 31)) & 0xFFFFFFFF;
    }
  }

  void clear(int index) => set(index, false);

  void clearAll() => _words.fillRange(0, _words.length, 0);

  /// `BitSet.nextClearBit(fromIndex)`, clamped to [length].
  int nextClearBit(int fromIndex) {
    for (var i = fromIndex < 0 ? 0 : fromIndex; i < length; i++) {
      if (!get(i)) return i;
    }
    return length;
  }

  /// The number of set bits.
  int cardinality() {
    var count = 0;
    for (var i = 0; i < length; i++) {
      if (get(i)) count++;
    }
    return count;
  }

  /// Replaces the content with the bits of [other].
  void copyFrom(BitGrid other) {
    clearAll();
    final limit = other.length < length ? other.length : length;
    for (var i = 0; i < limit; i++) {
      if (other.get(i)) set(i);
    }
  }
}
