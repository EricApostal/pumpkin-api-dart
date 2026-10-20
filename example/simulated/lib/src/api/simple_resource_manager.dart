// `dev.simulated_team.simulated.api.SimpleResourceManager`: a datapack resource
// manager (navigation targets, block property tooltips, ...) keyed by id.
//
// The Java class extends Veil's `CodecReloadListener`; a Pumpkin plugin has no
// reload listener registry, so the manager is plain data: [apply] takes the
// decoded entries and the plugin calls it when it reads the datapack.
//
// Pure: no host imports.

/// A manager of decoded datapack resources.
///
/// Java: `SimpleResourceManager<T>`
final class SimpleResourceManager<T> {
  /// The resource path (`simulated:navigation_target`).
  final String path;

  /// Whether [sortedEntries] keeps the entries sorted.
  final bool canSort;

  /// The comparator of [sortedEntries] when [canSort] is set.
  final Comparator<T>? comparator;

  final Map<String, T> _entries = {};
  final Map<T, String> _toId = {};
  final List<T> _sortedValues = [];

  SimpleResourceManager(this.path, {this.canSort = false, this.comparator});

  /// `create(codec, path)` with `sorted()`: a manager whose [sortedEntries] are
  /// ordered.
  factory SimpleResourceManager.sorted(
    String path, {
    Comparator<T>? comparator,
  }) => SimpleResourceManager<T>(path, canSort: true, comparator: comparator);

  /// The entry with [id], or `null`.
  T? get(String id) => _entries[id];

  /// The id of [value], or `null`.
  String? idOf(T value) => _toId[value];

  /// Every `(id, value)` pair.
  Map<String, T> get entries => Map.unmodifiable(_entries);

  /// Every value.
  Iterable<T> get values => _entries.values;

  /// The values, sorted when the manager was created sorted.
  List<T> get sortedEntries => List.unmodifiable(_sortedValues);

  /// Replaces the content (`apply` of the reload listener).
  void apply(Map<String, T> entries) {
    _entries
      ..clear()
      ..addAll(entries);
    _toId
      ..clear()
      ..addAll({for (final e in entries.entries) e.value: e.key});

    if (!canSort) return;
    _sortedValues
      ..clear()
      ..addAll(entries.values.toList()..sort(comparator));
  }

  /// Removes every entry (tests, reload).
  void clear() {
    _entries.clear();
    _toId.clear();
    _sortedValues.clear();
  }
}

/// The reload-listener registry the Java class keeps statically.
///
/// Java: `SimpleResourceManager.Registry`
abstract interface class SimpleResourceManagerRegistry {
  /// Registers [manager] under its [SimpleResourceManager.path].
  void registerListener(String path, Object manager);
}

/// A registry that keeps the managers in a map (tests, and the plugin before it
/// hands them to the host).
final class InMemoryResourceManagerRegistry implements SimpleResourceManagerRegistry {
  final Map<String, Object> managers = {};

  @override
  void registerListener(String path, Object manager) => managers[path] = manager;
}
