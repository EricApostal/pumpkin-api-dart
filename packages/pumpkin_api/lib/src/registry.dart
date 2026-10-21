/// Hands out numeric ids for Dart closures. The host only knows about ids, it
/// calls them back through the `handle-*` exports of the plugin world.
final class HandlerRegistry<T> {
  final Map<int, T> _handlers = {};
  int _nextId = 0;

  int add(T handler) {
    final id = reserve();
    _handlers[id] = handler;
    return id;
  }

  /// Hands out an id without storing a handler.
  ///
  /// An event group (`EventApi.listenGroup`) is dispatched by one host handler of its own
  /// rather than one per member, so the group needs an id the registry never looks up.
  int reserve() => _nextId++;

  T? operator [](int id) => _handlers[id];

  void remove(int id) => _handlers.remove(id);
}
