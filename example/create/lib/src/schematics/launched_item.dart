// `LaunchedItem` (pure): a block, belt or entity in flight from the schematicannon to its target.
import '../api/block_state.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import 'schematic_stack.dart';
import 'schematic_world.dart';

/// `LaunchedItem.ticksForDistance`.
int launchTicks(Pos start, Pos target) => cannonTicksForDistance(start, target);

/// A thing the cannon shot. [stack] is the icon (the item that paid for it).
sealed class LaunchedItem {
  int totalTicks;
  int ticksRemaining;
  final Pos target;
  final SlotStack stack;

  LaunchedItem(this.target, this.stack, this.totalTicks, this.ticksRemaining);

  /// `update(world)` on the server: counts down; returns true when the item landed and must be
  /// placed (then removed from the flight list).
  bool update() {
    if (ticksRemaining > 0) {
      ticksRemaining--;
      return false;
    }
    return true;
  }

  Map<String, Object?> toTag();

  /// Reads the persisted form (`serializeNBT`).
  static LaunchedItem? fromTag(Map<String, Object?> tag) {
    final target = _pos(tag['Target']);
    if (target == null) return null;
    final stack = SlotStack(
      (tag['StackId'] as String?) ?? 'minecraft:air',
      (tag['StackCount'] as int?) ?? 0,
    );
    final total = (tag['TotalTicks'] as int?) ?? 0;
    final left = (tag['TicksLeft'] as int?) ?? 0;
    if (tag.containsKey('Length')) {
      final state = _state(tag['BlockState']);
      if (state == null) return null;
      final length = tag['Length'] as int;
      final casing = (tag['Casing'] as List<Object?>? ?? const []).cast<int>();
      return LaunchedBelt(target, stack, total, left, state, length, [
        for (var i = 0; i < length; i++) i >= casing.length ? 0 : casing[i].clamp(0, 2),
      ]);
    }
    if (tag.containsKey('BlockState')) {
      final state = _state(tag['BlockState']);
      if (state == null) return null;
      return LaunchedBlock(target, stack, total, left, state, tag['Data'] as List<int>?);
    }
    return null; // entities are not persisted (their data is in the schematic)
  }

  static Pos? _pos(Object? o) => o is List && o.length == 3 ? (o[0] as int, o[1] as int, o[2] as int) : null;

  static BState? _state(Object? o) {
    if (o is! Map) return null;
    final name = o['Name'] as String?;
    if (name == null) return null;
    final props = (o['Properties'] as Map<Object?, Object?>?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {};
    return BState(name, props);
  }

  Map<String, Object?> _base() => {
    'TotalTicks': totalTicks,
    'TicksLeft': ticksRemaining,
    'StackId': stack.item,
    'StackCount': stack.count,
    'Target': [target.$1, target.$2, target.$3],
  };
}

/// `LaunchedItem.ForBlockState`.
final class LaunchedBlock extends LaunchedItem {
  final BState state;

  /// Block entity data (binary NBT) or null.
  final List<int>? data;

  LaunchedBlock(super.target, super.stack, super.totalTicks, super.ticksRemaining, this.state, this.data);

  factory LaunchedBlock.launch(Pos start, Pos target, SlotStack stack, BState state, List<int>? data) {
    final ticks = launchTicks(start, target);
    return LaunchedBlock(target, stack, ticks, ticks, state, data);
  }

  @override
  Map<String, Object?> toTag() => {
    ..._base(),
    'BlockState': {'Name': state.key, 'Properties': state.props},
    if (data != null) 'Data': data,
  };
}

/// `LaunchedItem.ForBelt`: a whole belt, shot from its last segment; [casings] are the casing
/// ordinals (0 none, 1 andesite, 2 brass) per segment.
final class LaunchedBelt extends LaunchedItem {
  final BState state;
  final int length;
  final List<int> casings;

  LaunchedBelt(super.target, super.stack, super.totalTicks, super.ticksRemaining, this.state, this.length, this.casings);

  factory LaunchedBelt.launch(Pos start, Pos target, SlotStack stack, BState state, List<int> casings) {
    final ticks = launchTicks(start, target);
    return LaunchedBelt(target, stack, ticks, ticks, state, casings.length, casings);
  }

  @override
  Map<String, Object?> toTag() => {
    ..._base(),
    'BlockState': {'Name': state.key, 'Properties': state.props},
    'Length': length,
    'Casing': casings,
  };
}

/// `LaunchedItem.ForEntity`.
final class LaunchedEntity extends LaunchedItem {
  final SchematicEntity entity;

  /// The absolute position the entity is spawned at.
  final (double, double, double) position;

  LaunchedEntity(super.target, super.stack, super.totalTicks, super.ticksRemaining, this.entity, this.position);

  factory LaunchedEntity.launch(Pos start, Pos target, SlotStack stack, SchematicEntity entity, (double, double, double) position) {
    final ticks = launchTicks(start, target);
    return LaunchedEntity(target, stack, ticks, ticks, entity, position);
  }

  @override
  Map<String, Object?> toTag() => _base();
}

// ---- belts ---------------------------------------------------------------------------------

/// `BeltBlock.nextSegmentPosition(state, pos, forward)`, null at the ends.
Pos? nextBeltSegment(BState state, Pos pos, bool forward) {
  final direction = Direction.byName(state['facing'] ?? 'north') ?? Direction.north;
  final slope = state['slope'] ?? 'horizontal';
  final part = state['part'] ?? 'none';
  final offset = forward ? 1 : -1;
  if ((part == 'end' && forward) || (part == 'start' && !forward)) return null;
  if (slope == 'vertical') {
    return pos.aboveBy(direction.axisDirection == AxisDirection.positive ? offset : -offset);
  }
  var p = pos.relative(direction, offset);
  if (slope != 'horizontal' && slope != 'sideways') {
    p = p.aboveBy(slope == 'upward' ? offset : -offset);
  }
  return p;
}

/// `SchematicannonBlockEntity.stripBeltIfNotLast`: only the last segment of a belt is shot (as the
/// whole belt); the others become a shaft or nothing.
BState stripBeltIfNotLast(BState belt) {
  final part = belt['part'];
  if (part == 'middle') return BState.air;
  final facing = Direction.byName(belt['facing'] ?? 'north') ?? Direction.north;
  final slope = belt['slope'] ?? 'horizontal';
  final positive = facing.axisDirection == AxisDirection.positive;
  final start = part == 'start';
  final end = part == 'end';
  final isLast = switch (slope) {
    'downward' => start,
    'upward' => end,
    _ => (positive && end) || (!positive && start),
  };
  if (isLast) return belt;
  final axis = slope == 'sideways' ? Axis.y : facing.clockWise.axis;
  return BState('create:shaft', {'axis': axis.serializedName, 'waterlogged': 'false'});
}
