// `java.util.PriorityQueue` (pure): the same binary heap (siftUp / siftDown), so that entries with
// equal priority leave the queue in the order Java's queue gives them. Create's path searches
// (`Navigation.search`, `CarriageSyncData.getDistanceTo`) break ties that way.

/// A min-heap ordered by [compare] with the exact algorithm of `java.util.PriorityQueue`.
final class JavaPriorityQueue<E> {
  final int Function(E a, E b) compare;
  final List<E> _queue = <E>[];

  JavaPriorityQueue(this.compare);

  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;
  int get length => _queue.length;

  /// `add` / `offer`.
  bool add(E x) {
    _queue.add(x);
    var k = _queue.length - 1;
    while (k > 0) {
      final parent = (k - 1) >>> 1;
      final e = _queue[parent];
      if (compare(x, e) >= 0) break;
      _queue[k] = e;
      k = parent;
    }
    _queue[k] = x;
    return true;
  }

  /// `peek`: the head, or `null` when empty.
  E? peek() => _queue.isEmpty ? null : _queue[0];

  /// `poll`: removes and returns the head, or `null` when empty.
  E? poll() {
    if (_queue.isEmpty) return null;
    final result = _queue[0];
    final n = _queue.length - 1;
    final x = _queue.removeLast();
    if (n > 0) {
      var k = 0;
      final half = n >>> 1;
      while (k < half) {
        var child = (k << 1) + 1;
        var c = _queue[child];
        final right = child + 1;
        if (right < n && compare(c, _queue[right]) > 0) {
          child = right;
          c = _queue[child];
        }
        if (compare(x, c) <= 0) break;
        _queue[k] = c;
        k = child;
      }
      _queue[k] = x;
    }
    return result;
  }

  void clear() => _queue.clear();
}

/// A mutable box (`MutableObject`, `MutableDouble`, `MutableBoolean` ...) for closures.
final class Mutable<T> {
  T value;

  Mutable(this.value);
}
