// Doors (pure): the vanilla `DoorBlock` rules and Create's `SlidingDoorBlock` on top of them
// (an extra `visible` property that hides the block while the animation plays), plus the timing
// of `SlidingDoorBlockEntity`.
import '../api/block_state.dart';
import '../api/lerped_float.dart';
import '../common/direction.dart';
import '../common/pos.dart';

const List<String> slidingDoorKeys = [
  'create:andesite_door',
  'create:brass_door',
  'create:copper_door',
  'create:train_door',
  'create:framed_glass_door',
];

/// The doors that fold instead of sliding (`SlidingDoorBlock.isFoldingDoor`): the glass door.
const Set<String> foldingDoorKeys = {'create:framed_glass_door'};

/// `BlockSetType` sounds by door key: (open sound, close sound) as sound event keys. The three
/// Create set types all use the iron door sounds.
const String doorOpenSound = 'minecraft:block.iron_door.open';
const String doorCloseSound = 'minecraft:block.iron_door.close';
const String trapdoorOpenSound = 'minecraft:block.iron_trapdoor.open';
const String trapdoorCloseSound = 'minecraft:block.iron_trapdoor.close';

/// `DoorBlock.getHinge`: the hinge side (`left` or `right`) of a door placed at [pos] by a player
/// looking along [placeDirection], clicking at [clickLocation] (absolute coordinates).
String doorHinge(BlockGetter level, Pos pos, Direction placeDirection, (double, double, double) clickLocation, String doorKey) {
  final abovePos = pos.above;
  final leftDirection = placeDirection.counterClockWise;
  final leftPos = pos.relative(leftDirection);
  final leftAbovePos = abovePos.relative(leftDirection);
  final rightDirection = placeDirection.clockWise;
  final rightPos = pos.relative(rightDirection);
  final rightAbovePos = abovePos.relative(rightDirection);
  final solidBlockBalance =
      (level.isCollisionShapeFullBlock(leftPos) ? -1 : 0) +
      (level.isCollisionShapeFullBlock(leftAbovePos) ? -1 : 0) +
      (level.isCollisionShapeFullBlock(rightPos) ? 1 : 0) +
      (level.isCollisionShapeFullBlock(rightAbovePos) ? 1 : 0);
  bool isLowerDoor(Pos p) {
    final s = level.stateAt(p);
    return _isDoorKey(s) && s['half'] == 'lower';
  }

  final doorLeft = isLowerDoor(leftPos);
  final doorRight = isLowerDoor(rightPos);
  if ((!doorLeft || doorRight) && solidBlockBalance <= 0) {
    if ((!doorRight || doorLeft) && solidBlockBalance >= 0) {
      final stepX = placeDirection.stepX;
      final stepZ = placeDirection.stepZ;
      final clickX = clickLocation.$1 - pos.$1;
      final clickZ = clickLocation.$3 - pos.$3;
      return (stepX >= 0 || !(clickZ < 0.5)) &&
              (stepX <= 0 || !(clickZ > 0.5)) &&
              (stepZ >= 0 || !(clickX > 0.5)) &&
              (stepZ <= 0 || !(clickX < 0.5))
          ? 'left'
          : 'right';
    }
    return 'left';
  }
  return 'right';
}

bool _isDoorKey(BState s) => s.has('hinge') && s.has('half') && (s['half'] == 'lower' || s['half'] == 'upper') && s.has('open');

/// `DoorBlock.canSurvive`.
bool doorCanSurvive(BlockGetter level, Pos pos, BState state) {
  final below = pos.below;
  return state['half'] == 'lower'
      ? level.isFaceSturdy(below, Direction.up)
      : level.stateAt(below).key == state.key;
}

/// `DoorBlock.getStateForPlacement` for the lower half of a door (the caller checked that there is
/// room above): `null` if the door cannot be placed.
BState? doorStateForPlacement({
  required BlockGetter level,
  required Pos pos,
  required BState defaultState,
  required Direction horizontalDirection,
  required (double, double, double) clickLocation,
  required bool powered,
  required int maxY,
  bool sliding = false,
}) {
  if (pos.$2 >= maxY || !level.canBeReplaced(pos.above)) return null;
  var s = defaultState
      .setValue('facing', horizontalDirection.serializedName)
      .setValue('hinge', doorHinge(level, pos, horizontalDirection, clickLocation, defaultState.key))
      .setFlag('powered', powered)
      .setFlag('open', powered)
      .setValue('half', 'lower');
  if (sliding && s.flag('open')) s = s.setFlag('open', false).setFlag('powered', false);
  return s;
}

/// `DoorBlock.updateShape` / `SlidingDoorBlock.updateShape` for a door of this block: the new
/// state, or [BState.air] when the half has to go.
BState doorUpdateShape(
  BlockGetter level,
  Pos pos,
  BState state,
  Direction direction,
  BState neighbour, {
  required bool sliding,
}) {
  final half = state['half'];
  final towardsOther = direction.axis == Axis.y && (half == 'lower') == (direction == Direction.up);
  if (!towardsOther) {
    return half == 'lower' && direction == Direction.down && !doorCanSurvive(level, pos, state) ? BState.air : state;
  }
  if (sliding) {
    return neighbour.key == state.key && neighbour['half'] != half ? neighbour.setValue('half', half!) : BState.air;
  }
  return _isDoorKey(neighbour) && neighbour['half'] != half ? neighbour.setValue('half', half!) : BState.air;
}

/// `SlidingDoorBlock.isDoubleDoor`.
bool isDoubleDoor(BState state, String hinge, Direction facing, BState otherDoor) =>
    otherDoor.key == state.key &&
    otherDoor['hinge'] != hinge &&
    otherDoor.dir('facing') == facing &&
    otherDoor.flag('open') != state.flag('open') &&
    otherDoor['half'] == state['half'];

/// The position of the other door of a double door (`hinge == LEFT ? facing.getClockWise() : facing.getCounterClockWise()`).
Pos otherDoorPos(Pos pos, String hinge, Direction facing) =>
    pos.relative(hinge == 'left' ? facing.clockWise : facing.counterClockWise);

/// `SlidingDoorBlock.isDoorPowered`. [hasNeighborSignal] is `Level.hasNeighborSignal`.
bool isDoorPowered(BlockGetter level, Pos pos, BState state, bool Function(Pos) hasNeighborSignal) {
  final lower = state['half'] == 'lower';
  final hinge = state['hinge']!;
  final facing = state.dir('facing')!;
  final otherPos = otherDoorPos(pos, hinge, facing);
  final otherDoor = level.stateAt(otherPos);
  final vertical = lower ? Direction.up : Direction.down;
  if (isDoubleDoor(state.cycleFlag('open'), hinge, facing, otherDoor) &&
      (hasNeighborSignal(otherPos) || hasNeighborSignal(otherPos.relative(vertical)))) {
    return true;
  }
  return hasNeighborSignal(pos) || hasNeighborSignal(pos.relative(vertical));
}

/// One block change of a door action.
typedef DoorChange = (Pos, BState);

/// What a door action did: the block changes and whether a sound should play.
final class DoorAction {
  final List<DoorChange> changes;

  /// Position and direction of the sound (`true`: opening); `null` for no sound.
  final (Pos, bool)? sound;

  const DoorAction(this.changes, this.sound);
}

/// `SlidingDoorBlock.useWithoutItem`: the right click on a sliding door. Returns the changes of
/// this half and of the other door of a double door. The changes are applied in order, so the
/// recursion sees the first door already toggled like the Java code does.
DoorAction slidingDoorUse(BlockGetter level, Pos pos, BState state) {
  final changes = <DoorChange>[];
  final applied = <Pos, BState>{};
  BState read(Pos p) => applied[p] ?? level.stateAt(p);
  (Pos, bool)? sound;
  void toggle(Pos p, BState s) {
    s = s.cycleFlag('open');
    final isOpen = s.flag('open');
    if (isOpen) s = s.setFlag('visible', false);
    changes.add((p, s));
    applied[p] = s;
    final hinge = s['hinge']!;
    final facing = s.dir('facing')!;
    final otherPos = otherDoorPos(p, hinge, facing);
    final otherDoor = read(otherPos);
    if (isDoubleDoor(s, hinge, facing, otherDoor)) {
      toggle(otherPos, otherDoor);
    } else if (isOpen) {
      sound = (p, true);
    }
  }

  toggle(pos, state);
  return DoorAction(changes, sound);
}

/// `SlidingDoorBlock.setOpen(entity, level, state, pos, open)`.
DoorAction slidingDoorSetOpen(BlockGetter level, Pos pos, BState state, bool open) {
  final changes = <DoorChange>[];
  final applied = <Pos, BState>{};
  BState read(Pos p) => applied[p] ?? level.stateAt(p);
  void set(Pos p, BState s) {
    if (s.flag('open') == open) return;
    var changed = s.setFlag('open', open);
    if (open) changed = changed.setFlag('visible', false);
    changes.add((p, changed));
    applied[p] = changed;
    final hinge = changed['hinge']!;
    final facing = changed.dir('facing')!;
    final otherPos = otherDoorPos(p, hinge, facing);
    final otherDoor = read(otherPos);
    if (isDoubleDoor(changed, hinge, facing, otherDoor)) set(otherPos, otherDoor);
  }

  set(pos, state);
  return DoorAction(changes, changes.isEmpty ? null : (pos, open));
}

/// `SlidingDoorBlock.neighborChanged`: reacts to redstone. [sourceIsSameBlock] is
/// `defaultBlockState().is(pBlock)`; [deferUpdate] is the block entity flag.
DoorAction slidingDoorNeighborChanged(
  BlockGetter level,
  Pos pos,
  BState state, {
  required bool sourceIsSameBlock,
  required bool deferUpdate,
  required bool Function(Pos) hasNeighborSignal,
}) {
  final isPowered = isDoorPowered(level, pos, state, hasNeighborSignal);
  if (sourceIsSameBlock) return const DoorAction([], null);
  if (isPowered == state.flag('powered')) return const DoorAction([], null);
  if (deferUpdate) return const DoorAction([], null);
  var changed = state.setFlag('powered', isPowered).setFlag('open', isPowered);
  if (isPowered) changed = changed.setFlag('visible', false);
  final changes = <DoorChange>[];
  (Pos, bool)? sound;
  if (isPowered != state.flag('open')) {
    sound = (pos, isPowered);
    final hinge = changed['hinge']!;
    final facing = changed.dir('facing')!;
    final otherPos = otherDoorPos(pos, hinge, facing);
    var otherDoor = level.stateAt(otherPos);
    if (isDoubleDoor(changed, hinge, facing, otherDoor)) {
      otherDoor = otherDoor.setFlag('powered', isPowered).setFlag('open', isPowered);
      if (isPowered) otherDoor = otherDoor.setFlag('visible', false);
      changes.add((otherPos, otherDoor));
    }
  }
  changes.add((pos, changed));
  return DoorAction(changes, sound);
}

/// The timing of `SlidingDoorBlockEntity`.
final class SlidingDoorAnimation {
  final LerpedFloat animation;
  bool deferUpdate = false;
  int bridgeTicks = 0;
  int _settledClosedInvisible = 0;

  SlidingDoorAnimation({required bool open}) : animation = LerpedFloat.linear()..startWithValue(open ? 1 : 0);

  /// One server tick (`SlidingDoorBlockEntity.tick`, server side): chases the open state and tells
  /// whether the block model is to be shown again (`showBlockModel`).
  ///
  /// A door that was saved while closing (closed, hidden and with a settled animation from the start)
  /// would stay hidden forever in Java; after a short wait it is shown here as well.
  bool tick({required bool open, required bool visible}) {
    final wasSettled = animation.settled();
    animation.chase(open ? 1 : 0, .15, Chasers.linear);
    animation.tickChaser();
    if (!open && !wasSettled && animation.settled() && !visible) return true;
    if (!open && !visible && animation.settled()) {
      if (++_settledClosedInvisible >= 5) {
        _settledClosedInvisible = 0;
        return true;
      }
    } else {
      _settledClosedInvisible = 0;
    }
    return false;
  }
}
