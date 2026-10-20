// Block states as plain data and a read-only view of the blocks around a position
// (pure). Algorithms that depend on the neighbours (connected pillars, glass panes,
// girders, stairs, ...) are written against [BlockGetter] so they run on the plain Dart VM in
// tests; `api/blocks.dart` provides the host implementation.
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;

import '../common/direction.dart';
import '../common/pos.dart';

/// A block state: the block key (`minecraft:stone`, `create:metal_girder`) and the
/// property values as strings (`{'axis': 'y', 'waterlogged': 'false'}`).
final class BState {
  final String key;
  final Map<String, String> props;

  const BState(this.key, [this.props = const {}]);

  /// `Blocks.AIR.defaultBlockState()`.
  static const BState air = BState('minecraft:air');

  bool get isAir => key == 'minecraft:air' || key == 'minecraft:cave_air' || key == 'minecraft:void_air';

  /// `BlockState.is(Block)`.
  bool isBlock(String blockKey) => key == blockKey;

  /// `BlockState.hasProperty`.
  bool has(String property) => props.containsKey(property);

  /// `getValue` as a string; `null` when the block lacks the property.
  String? operator [](String property) => props[property];

  /// A boolean property (`false` when missing).
  bool flag(String property) => props[property] == 'true';

  /// An integer property (0 when missing).
  int intValue(String property) => int.tryParse(props[property] ?? '') ?? 0;

  /// `setValue`: a copy with [property] set (unchanged when the block does not have it, so
  /// `with` is safe on blocks of any kind).
  BState setValue(String property, String value) {
    if (!props.containsKey(property) || props[property] == value) return this;
    return BState(key, {...props, property: value});
  }

  BState setFlag(String property, bool value) => setValue(property, value ? 'true' : 'false');

  BState setInt(String property, int value) => setValue(property, '$value');

  /// `setValue` for a direction-valued property.
  BState setDir(String property, Direction d) => setValue(property, d.serializedName);

  /// A copy with all of [values] set.
  BState setAll(Map<String, String> values) {
    var s = this;
    for (final e in values.entries) {
      s = s.setValue(e.key, e.value);
    }
    return s;
  }

  /// The direction stored under [property] (`facing`), or `null`.
  Direction? dir(String property) {
    final v = props[property];
    return v == null ? null : Direction.byName(v);
  }

  /// The axis stored under [property] (`axis`), or `null`.
  Axis? axisOf(String property) {
    final v = props[property];
    return v == null ? null : Axis.byName(v);
  }

  /// `BlockState.cycle` of a boolean property.
  BState cycleFlag(String property) => setFlag(property, !flag(property));

  /// `withPropertiesOf`: the block [blockKey] with the values this state has for the
  /// properties both have (the caller checks they exist on the target by passing [targetProps]).
  BState copyPropsTo(String blockKey, Iterable<String> targetProps) =>
      BState(blockKey, {for (final p in targetProps) if (props.containsKey(p)) p: props[p]!});

  @override
  bool operator ==(Object other) {
    if (other is! BState || other.key != key || other.props.length != props.length) return false;
    for (final e in props.entries) {
      if (other.props[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(key, Object.hashAllUnordered(props.entries.map((e) => Object.hash(e.key, e.value))));

  @override
  String toString() => props.isEmpty ? key : '$key[${props.entries.map((e) => '${e.key}=${e.value}').join(',')}]';
}

/// A read-only view of the world's blocks (`BlockGetter` / `LevelReader`).
abstract class BlockGetter {
  /// The state at [p]; [BState.air] for unloaded chunks.
  BState stateAt(Pos p);

  /// `Level.isLoaded`.
  bool isLoaded(Pos p);

  /// `BlockState.isFaceSturdy(level, pos, face)`: the face of the block at [p] that looks
  /// toward [face] is solid enough to attach things to.
  bool isFaceSturdy(Pos p, Direction face);

  /// The collision shape of the block at [p] in block units (`blockState.getCollisionShape`).
  List<BlockBox> collisionBoxes(Pos p);

  /// `blockState.getCollisionShape(level, pos).isEmpty()`.
  bool collisionShapeEmpty(Pos p) => collisionBoxes(p).isEmpty;

  /// `blockState.getBlockSupportShape(level, pos).isEmpty()`.
  bool supportShapeEmpty(Pos p);

  /// `BlockState.canBeReplaced()`.
  bool canBeReplaced(Pos p);

  /// `BlockState.isCollisionShapeFullBlock`.
  bool isCollisionShapeFullBlock(Pos p) {
    final boxes = collisionBoxes(p);
    return boxes.length == 1 &&
        boxes.first.minX <= 0 &&
        boxes.first.minY <= 0 &&
        boxes.first.minZ <= 0 &&
        boxes.first.maxX >= 1 &&
        boxes.first.maxY >= 1 &&
        boxes.first.maxZ >= 1;
  }

  /// `BlockState.is(TagKey)` for the block at [p].
  bool hasTag(Pos p, String tag);

  /// Whether [p] holds water (a water block or a waterlogged block).
  bool isWater(Pos p);
}

/// A [BlockGetter] over a map, for tests and for simulating changes. Blocks absent from the
/// map are air. A face is sturdy when [fullBlocks] contains the block's key (or [sturdy] says so).
final class MapBlockGetter extends BlockGetter {
  final Map<Pos, BState> blocks;

  /// Keys of blocks that are full cubes (sturdy on every side, with a full collision shape).
  final Set<String> fullBlocks;

  /// Tags by block key: `{'minecraft:walls': {'minecraft:cobblestone_wall'}}`.
  final Map<String, Set<String>> tags;

  /// Extra sturdiness rule (called before the [fullBlocks] check).
  final bool? Function(BState state, Direction face)? sturdy;

  /// Positions that hold water. Vanilla water is registered `.replaceable()`, so a placement
  /// helper may place into it (`BlockState.canBeReplaced()`).
  final Set<Pos> water;

  /// Collision boxes by block key; blocks in [fullBlocks] are a unit cube, others empty.
  final Map<String, List<BlockBox>> shapes;

  MapBlockGetter({
    Map<Pos, BState>? blocks,
    this.fullBlocks = const {'minecraft:stone', 'minecraft:cobblestone', 'minecraft:dirt', 'minecraft:granite'},
    this.tags = const {},
    this.sturdy,
    this.water = const {},
    this.shapes = const {},
  }) : blocks = blocks ?? {};

  void set(Pos p, BState s) => blocks[p] = s;

  @override
  BState stateAt(Pos p) => blocks[p] ?? BState.air;

  @override
  bool isLoaded(Pos p) => true;

  @override
  bool isFaceSturdy(Pos p, Direction face) {
    final s = stateAt(p);
    final custom = sturdy?.call(s, face);
    if (custom != null) return custom;
    return fullBlocks.contains(s.key);
  }

  @override
  List<BlockBox> collisionBoxes(Pos p) {
    final s = stateAt(p);
    if (s.isAir) return const [];
    return shapes[s.key] ?? (fullBlocks.contains(s.key) ? const [BlockBox.unit] : const []);
  }

  @override
  bool supportShapeEmpty(Pos p) => collisionBoxes(p).isEmpty;

  @override
  bool canBeReplaced(Pos p) => stateAt(p).isAir || water.contains(p);

  @override
  bool hasTag(Pos p, String tag) => tags[tag]?.contains(stateAt(p).key) ?? false;

  @override
  bool isWater(Pos p) => water.contains(p);
}
