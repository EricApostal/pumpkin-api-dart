// `BogeySizes` (pure): the registry of bogey sizes, sorted by wheel radius.
//
// ignore_for_file: constant_identifier_names, non_constant_identifier_names
//
// Java: `BogeySizes.SMALL` / `LARGE` -> [BogeySizes.small] / [BogeySizes.large];
// `BogeySizes.all()` -> [BogeySizes.all] (a method, like Java).

/// `BogeySizes.BogeySize`: a record of an id and a wheel radius.
final class BogeySize {
  /// `id()`: the resource location (`create:small`).
  final String id;

  /// `wheelRadius()`.
  final double wheelRadius;

  const BogeySize(this.id, this.wheelRadius);

  /// The next size by increasing wheel radius, wrapping around (`nextBySize`).
  BogeySize nextBySize() {
    final values = BogeySizes.allSortedIncreasing();
    final ordinal = values.indexOf(this);
    return values[(ordinal + 1) % values.length];
  }

  @override
  bool operator ==(Object other) => other is BogeySize && other.id == id && other.wheelRadius == wheelRadius;

  @override
  int get hashCode => Object.hash(id, wheelRadius);

  @override
  String toString() => 'BogeySize[id=$id, wheelRadius=$wheelRadius]';
}

/// The size registry. `small` and `large` are registered at load, like the static initialiser of Java.
abstract final class BogeySizes {
  static final Map<String, BogeySize> _sizes = {};
  static final List<BogeySize> _increasing = [];
  static final List<BogeySize> _decreasing = [];

  /// `SMALL = new BogeySize(create:small, 6.5f / 16f)` (also [small]).
  static final BogeySize SMALL = _register(BogeySize('create:small', 6.5 / 16));
  static BogeySize get small => SMALL;

  /// `LARGE = new BogeySize(create:large, 12.5f / 16f)` (also [large]).
  static final BogeySize LARGE = _register(BogeySize('create:large', 12.5 / 16));
  static BogeySize get large => LARGE;

  static BogeySize _register(BogeySize size) {
    register(size);
    return size;
  }

  /// `register(size)`; throws when the id is taken.
  static void register(BogeySize size) {
    final id = size.id;
    if (_sizes.containsKey(id)) throw ArgumentError('Bogey size $id is already registered');
    _sizes[id] = size;
    _increasing.add(size);
    _decreasing.add(size);
    _increasing.sort((a, b) => a.wheelRadius.compareTo(b.wheelRadius));
    _decreasing.sort((a, b) => b.wheelRadius.compareTo(a.wheelRadius));
  }

  /// `all()`: the sizes by id.
  static Map<String, BogeySize> all() {
    init();
    return Map.unmodifiable(_sizes);
  }

  /// `allSortedIncreasing()`.
  static List<BogeySize> allSortedIncreasing() {
    init();
    return List.unmodifiable(_increasing);
  }

  /// `allSortedDecreasing()`.
  static List<BogeySize> allSortedDecreasing() {
    init();
    return List.unmodifiable(_decreasing);
  }

  /// `init()`: forces the static registration.
  static void init() {
    SMALL;
    LARGE;
  }
}
