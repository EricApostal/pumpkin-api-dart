// `SimpleRegistry` (pure): Create's registry type for API extension points, mapping keys to
// values with identity semantics. Java's `SimpleRegistry<K, V>` is keyed by game objects
// (`Block`, `BlockEntityType`, `Item`, ...); this port keys every registry by the object's id
// string (`create:shaft`), which is what the rest of the code already uses.
//
// Direct registrations win over providers. Providers are queried newest first and their values
// are cached until [SimpleRegistry.invalidate] is called (a tag reload does that in Java).
import '../block_state.dart';

/// `SimpleRegistry.Provider<K, V>`: a lazy value source.
final class SimpleRegistryProvider<V> {
  /// `Provider.get(object)`: the value for [key], or `null`.
  final V? Function(String key) lookup;

  /// `Provider.onRegister(invalidate)`: called after the provider joined a registry, so it can
  /// subscribe to whatever invalidates its results (Java: tag reloads).
  final void Function(void Function() invalidate)? onRegister;

  const SimpleRegistryProvider(this.lookup, {this.onRegister});

  /// `Provider.forTag(tag, holderGetter, value)`: the value for every key of [tag].
  ///
  /// [isInTag] answers the tag membership (`Tags.block`, ...); call
  /// [SimpleRegistry.invalidate] after a tag reload.
  factory SimpleRegistryProvider.forTag(
    String tag,
    V value, {
    required bool Function(String key, String tag) isInTag,
  }) => SimpleRegistryProvider<V>((key) => isInTag(key, tag) ? value : null);
}

/// `SimpleRegistry<K, V>`.
class SimpleRegistry<V> {
  final Map<String, V> _direct = {};
  final List<SimpleRegistryProvider<V>> _providers = [];
  final Map<String, V> _cache = {};

  /// `register(object, value)`: throws when [key] already has a direct value.
  void register(String key, V value) {
    if (_direct.containsKey(key)) {
      throw ArgumentError.value(key, 'key', 'already registered');
    }
    _direct[key] = value;
    _cache.remove(key);
  }

  /// `registerProvider(provider)`.
  void registerProvider(SimpleRegistryProvider<V> provider) {
    if (_providers.contains(provider)) {
      throw ArgumentError('The provider is already registered');
    }
    _providers.add(provider);
    provider.onRegister?.call(invalidate);
    _cache.clear();
  }

  /// `invalidate()`: drops the cached provider values.
  void invalidate() => _cache.clear();

  /// `get(object)`: the direct value, else the newest provider that has one.
  V? lookup(String key) {
    if (_direct.containsKey(key)) return _direct[key];
    if (_cache.containsKey(key)) return _cache[key];
    for (var i = _providers.length - 1; i >= 0; i--) {
      final value = _providers[i].lookup(key);
      if (value != null) {
        _cache[key] = value;
        return value;
      }
    }
    return null;
  }

  /// `get(StateHolder)`: the value of a block state.
  V? lookupState(BState state) => lookup(state.key);

  /// The direct registration of [key] (providers are not consulted).
  V? direct(String key) => _direct[key];

  bool contains(String key) => _direct.containsKey(key);

  Iterable<String> get keys => _direct.keys;

  /// Removes every registration and cached value (tests and reloads).
  void clear() {
    _direct.clear();
    _providers.clear();
    _cache.clear();
  }
}

/// `SimpleRegistry.Multi<K, V>`: every provider is queried and its value is added on top of the
/// direct list, like Java.
class MultiSimpleRegistry<V> {
  final Map<String, List<V>> _direct = {};
  final List<SimpleRegistryProvider<V>> _providers = [];

  /// `register(object, values)`: replaces the whole list (throws on a duplicate).
  void register(String key, List<V> values) {
    if (_direct.containsKey(key)) {
      throw ArgumentError.value(key, 'key', 'already registered');
    }
    _direct[key] = List<V>.of(values);
  }

  /// `add(object, value)`.
  void add(String key, V value) =>
      _direct.putIfAbsent(key, () => <V>[]).add(value);

  /// `addProvider(provider)`.
  void addProvider(SimpleRegistryProvider<V> provider) {
    if (_providers.contains(provider)) {
      throw ArgumentError('The provider is already registered');
    }
    _providers.add(provider);
    provider.onRegister?.call(invalidate);
  }

  /// `registerProvider(provider)`: inherited from `SimpleRegistry` in Java.
  void registerProvider(SimpleRegistryProvider<V> provider) =>
      addProvider(provider);

  /// The provider values are never cached, so there is nothing to drop.
  void invalidate() {}

  /// `get(object)`: never `null`; an empty list when nothing is registered.
  List<V> lookup(String key) {
    final result = <V>[...?_direct[key]];
    for (final provider in _providers) {
      final value = provider.lookup(key);
      if (value != null) result.add(value);
    }
    return result;
  }

  /// `get(StateHolder)`.
  List<V> lookupState(BState state) => lookup(state.key);

  Iterable<String> get keys => _direct.keys;

  /// Removes every registration (tests and reloads).
  void clear() {
    _direct.clear();
    _providers.clear();
  }
}

/// `SimpleBuilder.SimpleRegistryAccess<K, V>`: the two associations a builder makes, so the
/// registrate-free port can offer the same `associate` / `associateTag` calls.
final class SimpleRegistryAccess<V> {
  /// `adder.accept(object, value)`.
  final void Function(String key, V value) adder;

  /// `tagAdder.accept(tag, value)`.
  final void Function(String tag, V value) tagAdder;

  const SimpleRegistryAccess._(this.adder, this.tagAdder);

  /// `SimpleRegistryAccess.of(registry, holderGetter)`.
  factory SimpleRegistryAccess.of(
    SimpleRegistry<V> registry, {
    required bool Function(String key, String tag) isInTag,
  }) => SimpleRegistryAccess<V>._(
    registry.register,
    (tag, value) => registry.registerProvider(
      SimpleRegistryProvider<V>.forTag(tag, value, isInTag: isInTag),
    ),
  );

  /// `SimpleRegistryAccess.of(SimpleRegistry.Multi, holderGetter)`.
  factory SimpleRegistryAccess.ofMulti(
    MultiSimpleRegistry<V> registry, {
    required bool Function(String key, String tag) isInTag,
  }) => SimpleRegistryAccess<V>._(
    registry.add,
    (tag, value) => registry.addProvider(
      SimpleRegistryProvider<V>.forTag(tag, value, isInTag: isInTag),
    ),
  );

  /// `associate(object)`.
  void add(String key, V value) => adder(key, value);

  /// `associateTag(tag)`.
  void addTag(String tag, V value) => tagAdder(tag, value);
}
