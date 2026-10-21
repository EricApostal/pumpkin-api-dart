// `AbstractChassisBlock`, `LinearChassisBlock` and `RadialChassisBlock` as data: which side of a
// chassis carries glue, how a rotation/mirror/contraption transform moves those sticky sides, and
// the placement rule that keeps the axis of a placed-on chassis.
//
// Java: `content/contraptions/chassis/{AbstractChassisBlock,LinearChassisBlock,RadialChassisBlock}`.
import 'dart:collection';

import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockStateLayout;

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../schematics/state_transform.dart' as vanilla;
import '../core/level.dart';
import '../core/movement_checks.dart';
import '../core/structure_transform.dart';

const String linearChassis = 'create:linear_chassis';
const String secondaryLinearChassis = 'create:secondary_linear_chassis';
const String radialChassis = 'create:radial_chassis';

/// `AllBlocks.RADIAL_CHASSIS`.
bool isRadialChassis(BState s) => s.key == radialChassis;

/// `LinearChassisBlock.isChassis` (either linear chassis).
bool isLinearChassis(BState s) =>
    s.key == linearChassis || s.key == secondaryLinearChassis;

bool isChassis(BState s) => isLinearChassis(s) || isRadialChassis(s);

/// `LinearChassisBlock.sameKind`.
bool sameChassisKind(BState a, BState b) => a.key == b.key;

/// The sticky property of the linear chassis on [face], `null` when that face is an end.
String? linearGlueableSide(BState state, Direction face) {
  final axis = state.axisOf('axis');
  if (axis == null || face.axis != axis) return null;
  return face.axisDirection == AxisDirection.positive
      ? 'sticky_top'
      : 'sticky_bottom';
}

/// The sticky property of the radial chassis on [face], `null` for the two ends of its axis.
String? radialGlueableSide(BState state, Direction face) {
  final axis = state.axisOf('axis') ?? Axis.y;
  if (axis == Axis.x) {
    return switch (face) {
      Direction.north => 'sticky_west',
      Direction.south => 'sticky_east',
      Direction.up => 'sticky_north',
      Direction.down => 'sticky_south',
      _ => null,
    };
  }
  if (axis == Axis.y) {
    return switch (face) {
      Direction.north => 'sticky_north',
      Direction.south => 'sticky_south',
      Direction.east => 'sticky_east',
      Direction.west => 'sticky_west',
      _ => null,
    };
  }
  return switch (face) {
    Direction.up => 'sticky_north',
    Direction.down => 'sticky_south',
    Direction.east => 'sticky_east',
    Direction.west => 'sticky_west',
    _ => null,
  };
}

/// `AbstractChassisBlock.getGlueableSide`.
String? chassisGlueableSide(BState state, Direction face) =>
    isRadialChassis(state)
    ? radialGlueableSide(state, face)
    : linearGlueableSide(state, face);

/// `AbstractChassisBlock.rotate`: the sticky sides follow the rotation.
BState rotateChassis(BState state, BlockRotation rotation) {
  if (rotation == BlockRotation.none) return state;
  var rotated = vanilla.rotateState(state, rotation);
  for (final face in Direction.values) {
    final prop = chassisGlueableSide(rotated, face);
    if (prop != null) rotated = rotated.setValue(prop, 'false');
  }
  for (final face in Direction.values) {
    final prop = chassisGlueableSide(state, face);
    if (prop == null || !state.flag(prop)) continue;
    final moved = chassisGlueableSide(rotated, rotation.rotate(face));
    if (moved != null) rotated = rotated.setValue(moved, 'true');
  }
  return rotated;
}

/// `AbstractChassisBlock.mirror`.
BState mirrorChassis(BState state, BlockMirror mirror) {
  if (mirror == BlockMirror.none) return state;
  var mirrored = state;
  for (final face in Direction.values) {
    final prop = chassisGlueableSide(mirrored, face);
    if (prop != null) mirrored = mirrored.setValue(prop, 'false');
  }
  for (final face in Direction.values) {
    final prop = chassisGlueableSide(state, face);
    if (prop == null || !state.flag(prop)) continue;
    final moved = chassisGlueableSide(mirrored, mirror.mirrorDirection(face));
    if (moved != null) mirrored = mirrored.setValue(moved, 'true');
  }
  return mirrored;
}

/// `AbstractChassisBlock.transform`: a Y rotation is a plain rotation, anything else rotates the
/// axis first and then moves the sticky sides with `rotateFacing`.
BState transformChassis(BState state, StructureTransform transform) {
  final s = mirrorChassis(state, transform.mirror);
  if (transform.rotationAxis == Axis.y)
    return rotateChassis(s, transform.rotation);
  return _transformInner(s, transform);
}

BState _transformInner(BState state, StructureTransform transform) {
  if (transform.rotation == BlockRotation.none) return state;
  final axis = state.axisOf('axis');
  if (axis == null) return state;
  var rotated = state.setValue(
    'axis',
    transform.rotateAxis(axis).serializedName,
  );
  for (final face in Direction.values) {
    final prop = chassisGlueableSide(rotated, face);
    if (prop != null) rotated = rotated.setValue(prop, 'false');
  }
  for (final face in Direction.values) {
    final prop = chassisGlueableSide(state, face);
    if (prop == null || !state.flag(prop)) continue;
    final moved = chassisGlueableSide(rotated, transform.rotateFacing(face));
    if (moved != null) rotated = rotated.setValue(moved, 'true');
  }
  return rotated;
}

/// `LinearChassisBlock.glueAllowedOnSide`: the neighbouring block is not the same chassis on the
/// same axis.
bool linearGlueAllowedOnSide(BState state, BState other) =>
    !sameChassisKind(other, state) || state['axis'] != other['axis'];

/// `LinearChassisBlock.updateShape`: a neighbouring chassis of the same kind and axis clears the
/// glue of the shared side.
BState linearChassisUpdateShape(BState state, Direction side, BState other) {
  final prop = linearGlueableSide(state, side);
  if (prop == null ||
      !sameChassisKind(state, other) ||
      state['axis'] != other['axis'])
    return state;
  return state.setValue(prop, 'false');
}

/// `LinearChassisBlock.updateShape` answered for the `update-shape` hook: the index of the new
/// state in [layout] (the layout of the chassis block), or `null` when the neighbouring chassis
/// leaves the state unchanged.
///
/// The hook answers with a state index *of the block*, not a global state id (see [stateIndexIn]).
int? linearChassisShapeAnswer(
  BlockStateLayout layout,
  BState state,
  Direction side,
  BState other,
) {
  final next = linearChassisUpdateShape(state, side, other);
  if (next == state) return null;
  return stateIndexIn(layout, next);
}

/// `AbstractChassisBlock.useItemOn` / `useWithoutItem`: the new state after a glue click, or `null`
/// when the click is not a glue toggle. A slime ball on a sticky side glues every allowed side.
///
/// [glueAllowedOnSide] is asked for each face (linear chassis: not the same chassis on that side).
BState? chassisGlueClick(
  BState state,
  Direction clickedFace,
  bool isGlueItem,
  bool sneaking,
  bool emptyHand,
  bool Function(Direction face) glueAllowedOnSide,
) {
  final affected = chassisGlueableSide(state, clickedFace);
  if (affected == null) return null;
  if (isGlueItem && state.flag(affected)) {
    var s = state;
    for (final face in Direction.values) {
      final prop = chassisGlueableSide(s, face);
      if (prop != null && !s.flag(prop) && glueAllowedOnSide(face))
        s = s.setValue(prop, 'true');
    }
    return s;
  }
  if (!isGlueItem && !(emptyHand && sneaking)) return null;
  if (state.flag(affected) == isGlueItem) return null;
  if (!glueAllowedOnSide(clickedFace)) return null;
  return state.setValue(affected, isGlueItem ? 'true' : 'false');
}

// -- The blocks a contraption takes along ---------------------------------------------------------

/// `ChassisBlockEntity.getIncludedBlockPositions`: the blocks a contraption anchored at [anchor]
/// would take along. Pure so assembly, the block entity and the tests share it.
List<Pos> includedChassisPositions(
  ContraptionLevel level,
  Pos anchor,
  BState state,
  int range,
  Direction? forcedMovement,
) => isRadialChassis(state)
    ? _includedRadial(level, anchor, state, range)
    : _includedLinear(level, anchor, state, range, forcedMovement);

List<Pos> _includedLinear(
  ContraptionLevel level,
  Pos anchor,
  BState state,
  int range,
  Direction? forcedMovement,
) {
  final positions = <Pos>[];
  final axis = state.axisOf('axis') ?? Axis.y;
  var facing = Direction.fromAxisAndDirection(axis, AxisDirection.positive);
  for (final offset in [1, -1]) {
    if (offset == -1) facing = facing.opposite;
    final side = linearGlueableSide(state, facing);
    final sticky = side != null && state.flag(side);
    for (var i = 1; i <= range; i++) {
      final current = anchor.relative(facing, i);
      final currentState = level.stateAt(current);
      if (forcedMovement != facing && !sticky) break;
      if (!BlockMovementChecks.isMovementNecessary(
        currentState,
        level,
        current,
      )) {
        break;
      }
      if (BlockMovementChecks.isBrittle(currentState, level)) break;
      positions.add(current);
      if (BlockMovementChecks.isNotSupportive(currentState, facing, level)) {
        break;
      }
    }
  }
  return positions;
}

List<Pos> _includedRadial(
  ContraptionLevel level,
  Pos anchor,
  BState state,
  int range,
) {
  final positions = <Pos>[];
  final axis = state.axisOf('axis') ?? Axis.y;
  for (final facing in Direction.values) {
    if (facing.axis == axis) continue;
    final side = radialGlueableSide(state, facing);
    if (side == null || !state.flag(side)) continue;
    final start = anchor.relative(facing);
    final frontier = <Pos>[start];
    final visited = <Pos>{};
    while (frontier.isNotEmpty) {
      final search = frontier.removeAt(0);
      final searched = level.stateAt(search);
      if (visited.contains(search)) continue;
      if (!search.closerThan(anchor, range + .5)) continue;
      if (!BlockMovementChecks.isMovementNecessary(searched, level, search)) {
        continue;
      }
      if (BlockMovementChecks.isBrittle(searched, level)) continue;
      visited.add(search);
      if (search != anchor) positions.add(search);
      for (final offset in Direction.values) {
        if (offset.axis == axis) continue;
        if (search == anchor && offset != facing) continue;
        if (BlockMovementChecks.isNotSupportive(searched, offset, level)) {
          continue;
        }
        frontier.add(search.relative(offset));
      }
    }
  }
  return positions;
}

/// `ChassisBlockEntity.addAttachedChasses`: adds the neighbours that belong to the chassis group
/// of [anchor] to [frontier]. Pure so assembly, the block entity and the tests share it.
bool addAttachedChassesTo(
  ContraptionLevel level,
  Pos anchor,
  BState state,
  Queue<Pos> frontier,
  Set<Pos> visited,
) {
  if (!isChassis(state)) return false;
  final axis = state.axisOf('axis') ?? Axis.y;
  if (isRadialChassis(state)) {
    // A chain of radial chassis along the axis.
    for (final offset in [-1, 1]) {
      final direction = Direction.fromAxisAndDirection(
        axis,
        AxisDirection.positive,
      );
      final current = anchor.relative(direction, offset);
      if (!level.isLoaded(current)) return false;
      final neighbour = level.stateAt(current);
      if (!isRadialChassis(neighbour)) continue;
      if (neighbour['axis'] != axis.serializedName) continue;
      if (!visited.contains(current)) frontier.add(current);
    }
    return true;
  }
  // The group of connected linear chassis.
  for (final offset in Direction.values) {
    final current = anchor.relative(offset);
    if (visited.contains(current)) continue;
    if (!level.isLoaded(current)) return false;
    final neighbour = level.stateAt(current);
    if (!isLinearChassis(neighbour)) continue;
    if (!sameChassisKind(state, neighbour)) continue;
    if (neighbour['axis'] != state['axis']) continue;
    frontier.add(current);
  }
  return true;
}
