// Directions, axes, positions and block states of the kinetic logic (pure: no
// host imports, so the propagation algorithms run in plain `dart test`).
import '../core/pos.dart';

/// `Direction.KAxis`.
enum KAxis {
  x,
  y,
  z;

  bool get isVertical => this == KAxis.y;
  bool get isHorizontal => this != KAxis.y;

  /// `KAxis.choose(x, y, z)`: the component of this axis.
  int choose(int x, int y, int z) => switch (this) {
    KAxis.x => x,
    KAxis.y => y,
    KAxis.z => z,
  };

  /// `choose` for doubles.
  double chooseD(double x, double y, double z) => switch (this) {
    KAxis.x => x,
    KAxis.y => y,
    KAxis.z => z,
  };

  /// The direction along this axis with the given sign.
  Dir get positive => switch (this) {
    KAxis.x => Dir.east,
    KAxis.y => Dir.up,
    KAxis.z => Dir.south,
  };

  Dir get negative => positive.opposite;

  static KAxis? fromName(String? name) => switch (name) {
    'x' => KAxis.x,
    'y' => KAxis.y,
    'z' => KAxis.z,
    _ => null,
  };
}

/// `Direction` in Minecraft's enum order (down, up, north, south, west, east).
enum Dir {
  down(0, -1, 0),
  up(0, 1, 0),
  north(0, 0, -1),
  south(0, 0, 1),
  west(-1, 0, 0),
  east(1, 0, 0);

  final int dx;
  final int dy;
  final int dz;

  const Dir(this.dx, this.dy, this.dz);

  KAxis get axis => dx != 0 ? KAxis.x : (dy != 0 ? KAxis.y : KAxis.z);

  /// `+1` or `-1`.
  int get step => dx + dy + dz;
  bool get isPositive => step > 0;
  bool get isHorizontal => dy == 0;
  bool get isVertical => dy != 0;

  Dir get opposite => switch (this) {
    Dir.down => Dir.up,
    Dir.up => Dir.down,
    Dir.north => Dir.south,
    Dir.south => Dir.north,
    Dir.west => Dir.east,
    Dir.east => Dir.west,
  };

  /// `Direction.getClockWise(axis)`: rotates around [around] seen from its positive end.
  Dir clockWise(KAxis around) => switch (around) {
    KAxis.x => (this != Dir.west && this != Dir.east) ? _clockWiseX : this,
    KAxis.y => (this != Dir.up && this != Dir.down) ? _clockWiseY : this,
    KAxis.z => (this != Dir.north && this != Dir.south) ? _clockWiseZ : this,
  };

  /// `Direction.getCounterClockWise(axis)`.
  Dir counterClockWise(KAxis around) => switch (around) {
    KAxis.x => (this != Dir.west && this != Dir.east) ? _ccwX : this,
    KAxis.y => (this != Dir.up && this != Dir.down) ? _ccwY : this,
    KAxis.z => (this != Dir.north && this != Dir.south) ? _ccwZ : this,
  };

  Dir get _clockWiseY => switch (this) {
    Dir.north => Dir.east,
    Dir.east => Dir.south,
    Dir.south => Dir.west,
    _ => Dir.north,
  };
  Dir get _ccwY => switch (this) {
    Dir.north => Dir.west,
    Dir.west => Dir.south,
    Dir.south => Dir.east,
    _ => Dir.north,
  };
  Dir get _clockWiseX => switch (this) {
    Dir.up => Dir.north,
    Dir.north => Dir.down,
    Dir.down => Dir.south,
    _ => Dir.up,
  };
  Dir get _ccwX => switch (this) {
    Dir.up => Dir.south,
    Dir.south => Dir.down,
    Dir.down => Dir.north,
    _ => Dir.up,
  };
  Dir get _clockWiseZ => switch (this) {
    Dir.up => Dir.east,
    Dir.east => Dir.down,
    Dir.down => Dir.west,
    _ => Dir.up,
  };
  Dir get _ccwZ => switch (this) {
    Dir.up => Dir.west,
    Dir.west => Dir.down,
    Dir.down => Dir.east,
    _ => Dir.up,
  };

  /// The direction along [axis] with sign [positive].
  static Dir along(KAxis axis, {required bool positive}) => positive ? axis.positive : axis.negative;

  /// `Direction.getApproximateNearest(x, y, z)`: the direction with the largest
  /// dot product, ties go to the first in enum order.
  static Dir approximateNearest(num x, num y, num z) {
    var best = Dir.north;
    var bestDot = -double.maxFinite;
    for (final d in Dir.values) {
      final dot = x * d.dx + y * d.dy + z * d.dz;
      if (dot > bestDot) {
        bestDot = dot.toDouble();
        best = d;
      }
    }
    return best;
  }

  static Dir? fromName(String? name) {
    for (final d in Dir.values) {
      if (d.name == name) return d;
    }
    return null;
  }

  /// `Iterate.horizontalDirections` (catnip): south, west, north, east.
  static const List<Dir> horizontals = [Dir.south, Dir.west, Dir.north, Dir.east];

  /// `Iterate.directionsInAxis`.
  static List<Dir> inAxis(KAxis axis) => switch (axis) {
    KAxis.x => const [Dir.east, Dir.west],
    KAxis.y => const [Dir.up, Dir.down],
    KAxis.z => const [Dir.south, Dir.north],
  };
}

/// An immutable block position.
final class KPos {
  final int x;
  final int y;
  final int z;

  const KPos(this.x, this.y, this.z);

  static const KPos zero = KPos(0, 0, 0);

  KPos operator +(KPos o) => KPos(x + o.x, y + o.y, z + o.z);
  KPos operator -(KPos o) => KPos(x - o.x, y - o.y, z - o.z);

  KPos offset(int dx, int dy, int dz) => KPos(x + dx, y + dy, z + dz);
  KPos relative(Dir d, [int n = 1]) => KPos(x + d.dx * n, y + d.dy * n, z + d.dz * n);
  KPos above([int n = 1]) => relative(Dir.up, n);
  KPos below([int n = 1]) => relative(Dir.down, n);

  /// `BlockPos.distManhattan(BlockPos.ZERO)`.
  int get manhattan => x.abs() + y.abs() + z.abs();

  /// `distSqr(BlockPos.ZERO)`.
  int get lengthSqr => x * x + y * y + z * z;

  int choose(KAxis axis) => axis.choose(x, y, z);

  /// `BlockPos.asLong`.
  int get packed => packPos(x, y, z);

  static KPos unpack(int packed) {
    final (x, y, z) = unpackPos(packed);
    return KPos(x, y, z);
  }

  @override
  bool operator ==(Object other) => other is KPos && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '($x, $y, $z)';
}

/// A block state as the kinetic logic sees it: the block key (`create:shaft`)
/// and the property values. Immutable; equal states compare equal.
final class KState {
  final String block;
  final Map<String, String> props;

  const KState(this.block, [this.props = const {}]);

  /// The key without the namespace (`shaft`).
  String get path {
    final i = block.indexOf(':');
    return i < 0 ? block : block.substring(i + 1);
  }

  /// Whether the block is `create:<path>`.
  bool isCreate(String path) => block == 'create:$path';

  bool has(String name) => props.containsKey(name);
  String? operator [](String name) => props[name];

  bool flag(String name) => props[name] == 'true';

  int intValue(String name, [int fallback = 0]) => int.tryParse(props[name] ?? '') ?? fallback;

  KAxis? axisOf(String name) => KAxis.fromName(props[name]);
  Dir? dirOf(String name) => Dir.fromName(props[name]);

  KState set(String name, String value) => KState(block, {...props, name: value});
  KState setAll(Map<String, String> values) => KState(block, {...props, ...values});
  KState setFlag(String name, bool value) => set(name, value ? 'true' : 'false');

  /// `BlockState.cycle` for a boolean property.
  KState toggle(String name) => setFlag(name, !flag(name));

  KState withBlock(String newBlock) => KState(newBlock, props);

  /// Whether the block is air (the placeholder for unloaded or empty positions).
  bool get isAir => block == 'minecraft:air' || block == 'minecraft:cave_air' || block == 'minecraft:void_air';

  static const KState air = KState('minecraft:air');

  @override
  bool operator ==(Object other) {
    if (other is! KState || other.block != block || other.props.length != props.length) return false;
    for (final e in props.entries) {
      if (other.props[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(block, Object.hashAllUnordered(props.entries.map((e) => Object.hash(e.key, e.value))));

  @override
  String toString() => props.isEmpty ? block : '$block[${props.entries.map((e) => '${e.key}=${e.value}').join(',')}]';
}
