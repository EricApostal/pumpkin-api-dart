// Deterministic registries (pure): the id of an entry is its position, so the
// order has to be the order the code registered in, or a canonical order given
// from outside, never the iteration order of a hash map.

/// Thrown when a key is registered twice.
final class DuplicateRegistrationException implements Exception {
  final String registry;
  final String key;

  const DuplicateRegistrationException(this.registry, this.key);

  @override
  String toString() => 'DuplicateRegistrationException: `$key` is registered twice in `$registry`';
}

/// What a canonical order did to a registry, see [OrderedRegistry.entries].
final class OrderReport {
  /// Keys of the canonical order that nobody registered.
  final List<String> missing;

  /// Registered keys that are not in the canonical order (they follow the
  /// listed ones, in registration order).
  final List<String> extra;

  const OrderReport(this.missing, this.extra);

  bool get isClean => missing.isEmpty && extra.isEmpty;
}

/// Entries by key, kept in registration order, optionally reordered by a
/// canonical list of keys.
final class OrderedRegistry<T> {
  /// Name used in messages, for example `items`.
  final String name;

  final List<String> _keys = [];
  final Map<String, T> _values = {};
  List<String>? _canonical;

  OrderedRegistry(this.name);

  /// Number of entries.
  int get length => _keys.length;

  bool contains(String key) => _values.containsKey(key);

  /// The entry registered as [key], or `null`.
  T? operator [](String key) => _values[key];

  /// Adds an entry. Throws a [DuplicateRegistrationException] if [key] is taken.
  void add(String key, T value) {
    if (_values.containsKey(key)) throw DuplicateRegistrationException(name, key);
    _keys.add(key);
    _values[key] = value;
  }

  /// Like [add] for a key that may be registered by several modules, keeping
  /// the first value (used for lists that merge, such as tags).
  T putIfAbsent(String key, T Function() create) {
    final existing = _values[key];
    if (existing != null) return existing;
    final value = create();
    add(key, value);
    return value;
  }

  /// Installs a canonical order: [keys] come first, in this order, whatever
  /// the registration order was. Duplicates in [keys] are ignored.
  void useOrder(List<String> keys) {
    _canonical = keys.toSet().toList();
  }

  /// The keys in id order: canonical keys that are registered first, then the
  /// others in registration order.
  List<String> get keys {
    final canonical = _canonical;
    if (canonical == null) return List.unmodifiable(_keys);
    final listed = canonical.toSet();
    return List.unmodifiable([
      for (final key in canonical)
        if (_values.containsKey(key)) key,
      for (final key in _keys)
        if (!listed.contains(key)) key,
    ]);
  }

  /// The entries in id order (see [keys]).
  List<MapEntry<String, T>> get entries => [for (final key in keys) MapEntry(key, _values[key] as T)];

  /// The position of [key] in id order, or -1.
  int indexOf(String key) => keys.indexOf(key);

  /// How the canonical order and the registrations differ (clean without one).
  OrderReport get report {
    final canonical = _canonical;
    if (canonical == null) return const OrderReport([], []);
    final listed = canonical.toSet();
    return OrderReport(
      [
        for (final key in canonical)
          if (!_values.containsKey(key)) key,
      ],
      [
        for (final key in _keys)
          if (!listed.contains(key)) key,
      ],
    );
  }
}
