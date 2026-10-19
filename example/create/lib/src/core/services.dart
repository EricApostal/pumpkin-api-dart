// A tiny service locator (pure): how modules offer APIs to each other without
// importing each other's internals.

/// Thrown by [CreateServices.require] when nobody provided the service.
final class MissingServiceException implements Exception {
  final Type type;

  const MissingServiceException(this.type);

  @override
  String toString() => 'MissingServiceException: no module provided $type '
      '(is its module enabled and listed before the user in modules.dart?)';
}

/// Services by type. A module `provide`s in `onLoad`, others `require` or
/// `find` them (in `onLoad` of a later module, or `onServerLoaded`).
final class CreateServices {
  final Map<Type, Object> _services = {};

  /// Offers [service] as a `T`. Throws a [StateError] if `T` is taken.
  void provide<T extends Object>(T service) {
    if (_services.containsKey(T)) throw StateError('$T is already provided');
    _services[T] = service;
  }

  /// The service of type `T`; throws [MissingServiceException] if there is none.
  T require<T extends Object>() => find<T>() ?? (throw MissingServiceException(T));

  /// The service of type `T`, or `null`.
  T? find<T extends Object>() => _services[T] as T?;
}
