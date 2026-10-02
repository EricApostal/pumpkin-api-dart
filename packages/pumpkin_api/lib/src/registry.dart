/// Hands out numeric ids for Dart closures. The host only knows about ids, it
/// calls them back through the `handle-*` exports of the plugin world.
final class HandlerRegistry<T> {
  final Map<int, T> _handlers = {};
  int _nextId = 0;

  int add(T handler) {
    final id = _nextId++;
    _handlers[id] = handler;
    return id;
  }

  T? operator [](int id) => _handlers[id];

  void remove(int id) => _handlers.remove(id);
}
