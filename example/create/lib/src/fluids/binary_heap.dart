// A binary heap priority queue (pure), the `ObjectHeapPriorityQueue` the hose pulley uses.
class BinaryHeap<T> {
  final int Function(T a, T b) _compare;
  final List<T> _items = [];

  BinaryHeap(this._compare);

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  int get length => _items.length;

  /// `first()`: the smallest element.
  T get first => _items.first;

  void enqueue(T item) {
    _items.add(item);
    var i = _items.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_compare(_items[i], _items[parent]) >= 0) break;
      _swap(i, parent);
      i = parent;
    }
  }

  /// `dequeue()`: removes and returns the smallest element.
  T dequeue() {
    final top = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      var i = 0;
      final n = _items.length;
      while (true) {
        final l = 2 * i + 1;
        final r = l + 1;
        var smallest = i;
        if (l < n && _compare(_items[l], _items[smallest]) < 0) smallest = l;
        if (r < n && _compare(_items[r], _items[smallest]) < 0) smallest = r;
        if (smallest == i) break;
        _swap(i, smallest);
        i = smallest;
      }
    }
    return top;
  }

  void clear() => _items.clear();

  void _swap(int a, int b) {
    final t = _items[a];
    _items[a] = _items[b];
    _items[b] = t;
  }
}
