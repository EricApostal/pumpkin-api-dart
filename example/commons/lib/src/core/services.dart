/// How modules find each other: a module [provide]s a service object and other
/// modules [require] it by type. Services are created in `Module.onLoad`, so
/// a module that needs one lists the providing module in `dependsOn`.
final class Services {
  final Map<Type, Object> _services = {};

  void provide<T extends Object>(T service) {
    if (_services.containsKey(T)) {
      throw StateError('A service of type $T is already provided.');
    }
    _services[T] = service;
  }

  T require<T extends Object>() =>
      find<T>() ??
      (throw StateError(
        'No service of type $T. Does the module list its provider in '
        'dependsOn?',
      ));

  T? find<T extends Object>() => _services[T] as T?;
}
