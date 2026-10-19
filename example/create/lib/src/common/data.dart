// Catnip data classes (pure): Pair, Couple, IntAttached, Iterate, BlockFace, Pointing.
import 'direction.dart';
import 'pos.dart';

/// `net.createmod.catnip.api.data.Pair` (mutable, value equality).
class Pair<F, S> {
  F first;
  S second;

  Pair(this.first, this.second);

  static Pair<F, S> of<F, S>(F first, S second) => Pair<F, S>(first, second);

  F getFirst() => first;
  S getSecond() => second;
  void setFirst(F v) => first = v;
  void setSecond(S v) => second = v;

  Pair<F, S> copy() => Pair<F, S>(first, second);

  Pair<S, F> swap() => Pair<S, F>(second, first);

  @override
  bool operator ==(Object other) => other is Pair<Object?, Object?> && other.first == first && other.second == second;

  @override
  int get hashCode => ((first?.hashCode ?? 0) * 31) ^ (second?.hashCode ?? 0);

  @override
  String toString() => '($first, $second)';
}

/// `Couple<T>`: a pair of the same type, iterable; `get(true)` is the first.
class Couple<T> extends Pair<T, T> {
  Couple(super.first, super.second);

  static Couple<T> create<T>(T first, T second) => Couple<T>(first, second);

  /// `Couple.create(Supplier)`.
  static Couple<T> fromFactory<T>(T Function() factory) => Couple<T>(factory(), factory());

  /// `Couple.createWithContext`.
  static Couple<T> createWithContext<T>(T Function(bool first) factory) => Couple<T>(factory(true), factory(false));

  T get(bool first) => first ? this.first : second;

  void set(bool first, T value) {
    if (first) {
      this.first = value;
    } else {
      second = value;
    }
  }

  @override
  Couple<T> copy() => Couple<T>(first, second);

  Couple<S> map<S>(S Function(T) f) => Couple<S>(f(first), f(second));

  Couple<S?> mapNotNull<S>(S Function(T) f) => Couple<S?>(first != null ? f(first) : null, second != null ? f(second) : null);

  Couple<S> mapWithContext<S>(S Function(T, bool) f) => Couple<S>(f(first, true), f(second, false));

  Couple<S> mapWithParams<S, R>(S Function(T, R) f, Couple<R> values) =>
      Couple<S>(f(first, values.first), f(second, values.second));

  bool both(bool Function(T) test) => test(first) && test(second);

  bool either(bool Function(T) test) => test(first) || test(second);

  void replace(T Function(T) f) {
    first = f(first);
    second = f(second);
  }

  void replaceWithContext(T Function(T, bool) f) {
    first = f(first, true);
    second = f(second, false);
  }

  void replaceWithParams<S>(T Function(T, S) f, Couple<S> values) {
    first = f(first, values.first);
    second = f(second, values.second);
  }

  void forEach(void Function(T) f) {
    f(first);
    f(second);
  }

  void forEachWithContext(void Function(T, bool) f) {
    f(first, true);
    f(second, false);
  }

  void forEachWithParams<S>(void Function(T, S) f, Couple<S> values) {
    f(first, values.first);
    f(second, values.second);
  }

  @override
  Couple<T> swap() => Couple<T>(second, first);

  /// Both values, first then second (for `for (final v in couple.values)`).
  List<T> get values => [first, second];

  List<T> toList() => [first, second];

  @override
  bool operator ==(Object other) => other is Couple<Object?> && other.first == first && other.second == second;

  @override
  int get hashCode => ((first?.hashCode ?? 0) * 31) ^ (second?.hashCode ?? 0);

  @override
  String toString() => '($first, $second)';
}

/// `IntAttached<V>`: a counter with a value.
class IntAttached<V> extends Pair<int, V> {
  IntAttached(super.first, super.second);

  static IntAttached<V> with_<V>(int number, V value) => IntAttached<V>(number, value);
  static IntAttached<V> withZero<V>(V value) => IntAttached<V>(0, value);

  bool get isZero => first == 0;
  bool exceeds(int value) => first > value;
  bool get isOrBelowZero => first <= 0;
  void increment() => first++;
  void decrement() => first--;
  V get value => second;

  /// Sorts descending by the number (`IntAttached.comparator`).
  static int compare(IntAttached<Object?> a, IntAttached<Object?> b) => b.first.compareTo(a.first);
}

/// `Iterate`: constant iteration helpers.
abstract final class Iterate {
  static const List<bool> trueAndFalse = [true, false];
  static const List<bool> falseAndTrue = [false, true];
  static const List<int> zeroAndOne = [0, 1];
  static const List<int> positiveAndNegative = [1, -1];
  static const List<Direction> directions = Direction.values;
  static const List<Direction> horizontalDirections = [Direction.south, Direction.west, Direction.north, Direction.east];
  static const List<Axis> axes = Axis.values;

  static List<Direction> directionsInAxis(Axis axis) => switch (axis) {
    Axis.x => const [Direction.east, Direction.west],
    Axis.y => const [Direction.up, Direction.down],
    Axis.z => const [Direction.south, Direction.north],
  };

  static List<Pos> hereAndBelow(Pos pos) => [pos, pos.below];

  static List<Pos> hereBelowAndAbove(Pos pos) => [pos, pos.below, pos.above];

  static T cycleValue<T>(List<T> list, T current) {
    final i = list.indexOf(current);
    if (i == -1) throw ArgumentError('Current value not found in list');
    return list[(i + 1) % list.length];
  }
}

/// `BlockFace`: a position and the side of it.
class BlockFace extends Pair<Pos, Direction> {
  BlockFace(super.first, super.second);

  Pos get pos => first;
  Direction get face => second;
  Direction get oppositeFace => second.opposite;
  Pos get connectedPos => first.relative(second);
  BlockFace get opposite => BlockFace(connectedPos, oppositeFace);

  bool isEquivalent(BlockFace other) {
    if (this == other) return true;
    return connectedPos == other.pos && pos == other.connectedPos;
  }

  @override
  BlockFace copy() => BlockFace(first, second);
}

/// `Pointing`: which way an item or label points on a face (for the Create "Pointing" widgets).
enum Pointing {
  up(0),
  left(270),
  down(180),
  right(90);

  const Pointing(this.xRotation);

  final int xRotation;

  String get serializedName => name;

  Direction getCombinedDirection(Direction direction) {
    final axis = direction.axis;
    var top = axis == Axis.y ? Direction.south : Direction.up;
    final rotations = direction.axisDirection == AxisDirection.negative ? 4 - index : index;
    for (var i = 0; i < rotations; i++) {
      top = top.clockWiseAround(axis);
    }
    return top;
  }
}
