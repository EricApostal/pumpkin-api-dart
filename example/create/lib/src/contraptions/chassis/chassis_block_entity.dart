// `ChassisBlockEntity`: the range of a linear or radial chassis and the blocks it would take along.
// The range is a scroll value (1..`kinetics.contraptions.maxChassisRange`); the included positions
// are what the contraption assembly asks for.
//
// Java: `content/contraptions/chassis/ChassisBlockEntity`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/value_settings.dart';
import '../../common/common.dart';
import '../../core/block_entity.dart';
import '../../kinetics/behaviours.dart';
import '../core/level.dart';
import '../core/movement_checks.dart';
import 'chassis_logic.dart';
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_runtime.dart';

final class ChassisBlockEntity extends CreateBlockEntity
    implements ValueSettingsHost {
  ChassisBlockEntity(super.worldId, super.pos);

  ScrollValueBehaviour? _range;

  @override
  void onLoad() {
    final max = ActuatorRuntime.instance.settings.maxChassisRange;
    final range = ScrollValueBehaviour().between(1, max);
    range.value = max ~/ 2;
    _range = addBehaviour(range);
    super.onLoad();
  }

  /// The position as a [Pos]; the inherited `pos` is a host `BlockPos` and the `pos` of
  /// `common/pos.dart` shadows it in this library.
  Pos get localPos => (this.pos.x, this.pos.y, this.pos.z);

  /// `getRange`.
  int get range =>
      _range?.value ?? ActuatorRuntime.instance.settings.maxChassisRange ~/ 2;

  /// The state of this chassis, `null` when the block is gone.
  BState? get chassisState {
    final w = world;
    if (w == null || removed) return null;
    return HostBlockGetter.stateOfId(w.getBlockStateId(pos: this.pos));
  }

  bool get isRadial => isRadialChassis(chassisState ?? BState.air);

  /// `getIncludedBlockPositions`: the blocks a contraption would take along when this chassis is
  /// the anchor. Empty without a contraption level (the core installs one).
  List<Pos> getIncludedBlockPositions(Direction? forcedMovement) {
    final state = chassisState;
    final level = ActuatorHosts.levelOf(worldId);
    if (state == null || level == null || !isChassis(state)) return const [];
    return isRadial
        ? _includedRadial(state, level)
        : _includedLinear(state, level, forcedMovement);
  }

  List<Pos> _includedLinear(
    BState state,
    ContraptionLevel level,
    Direction? forcedMovement,
  ) {
    final positions = <Pos>[];
    final axis = state.axisOf('axis') ?? Axis.y;
    var facing = Direction.fromAxisAndDirection(axis, AxisDirection.positive);
    final range = this.range;
    for (final offset in [1, -1]) {
      if (offset == -1) facing = facing.opposite;
      final side = linearGlueableSide(state, facing);
      final sticky = side != null && state.flag(side);
      for (var i = 1; i <= range; i++) {
        final current = localPos.relative(facing, i);
        final currentState = level.stateAt(current);
        if (forcedMovement != facing && !sticky) break;
        if (!BlockMovementChecks.isMovementNecessary(
          currentState,
          level,
          current,
        ))
          break;
        if (BlockMovementChecks.isBrittle(currentState, level)) break;
        positions.add(current);
        if (BlockMovementChecks.isNotSupportive(currentState, facing, level))
          break;
      }
    }
    return positions;
  }

  List<Pos> _includedRadial(BState state, ContraptionLevel level) {
    final positions = <Pos>[];
    final axis = state.axisOf('axis') ?? Axis.y;
    final range = this.range;
    for (final facing in Direction.values) {
      if (facing.axis == axis) continue;
      final side = radialGlueableSide(state, facing);
      if (side == null || !state.flag(side)) continue;
      final start = localPos.relative(facing);
      final frontier = <Pos>[start];
      final visited = <Pos>{};
      while (frontier.isNotEmpty) {
        final search = frontier.removeAt(0);
        final searched = level.stateAt(search);
        if (visited.contains(search)) continue;
        if (!search.closerThan(localPos, range + .5)) continue;
        if (!BlockMovementChecks.isMovementNecessary(searched, level, search))
          continue;
        if (BlockMovementChecks.isBrittle(searched, level)) continue;
        visited.add(search);
        if (search != localPos) positions.add(search);
        for (final offset in Direction.values) {
          if (offset.axis == axis) continue;
          if (search == localPos && offset != facing) continue;
          if (BlockMovementChecks.isNotSupportive(searched, offset, level))
            continue;
          frontier.add(search.relative(offset));
        }
      }
    }
    return positions;
  }

  /// `collectChassisGroup`: every chassis of the connected group (bulk scroll values).
  List<ChassisBlockEntity> collectChassisGroup() {
    final frontier = <Pos>[localPos];
    final collected = <ChassisBlockEntity>[];
    final visited = <Pos>{};
    while (frontier.isNotEmpty) {
      final current = frontier.removeAt(0);
      if (!visited.add(current)) continue;
      final be = store.at(
        worldId,
        BlockPos(x: current.$1, y: current.$2, z: current.$3),
      );
      if (be is ChassisBlockEntity) {
        collected.add(be);
        be.addAttachedChasses(frontier, visited);
      }
    }
    return collected;
  }

  /// `addAttachedChasses`: the neighbours that belong to the same chassis group.
  bool addAttachedChasses(List<Pos> frontier, Set<Pos> visited) {
    final state = chassisState;
    final w = world;
    if (state == null || w == null || !isChassis(state)) return false;
    final axis = state.axisOf('axis') ?? Axis.y;
    if (isRadial) {
      for (final offset in [-1, 1]) {
        final direction = Direction.fromAxisAndDirection(
          axis,
          AxisDirection.positive,
        );
        final current = localPos.relative(direction, offset);
        if (!w.isLoaded(pos: BlockPos(x: current.$1, y: current.$2, z: current.$3))) return false;
        final neighbour = HostBlockGetter.stateOfId(
          w.getBlockStateId(pos: BlockPos(x: current.$1, y: current.$2, z: current.$3)),
        );
        if (!isRadialChassis(neighbour)) continue;
        if (neighbour['axis'] != axis.serializedName) continue;
        if (!visited.contains(current)) frontier.add(current);
      }
      return true;
    }
    for (final offset in Direction.values) {
      final current = localPos.relative(offset);
      if (visited.contains(current)) continue;
      if (!w.isLoaded(pos: BlockPos(x: current.$1, y: current.$2, z: current.$3))) return false;
      final neighbour = HostBlockGetter.stateOfId(
        w.getBlockStateId(pos: BlockPos(x: current.$1, y: current.$2, z: current.$3)),
      );
      if (!isLinearChassis(neighbour)) continue;
      if (!sameChassisKind(state, neighbour)) continue;
      if (neighbour['axis'] != state['axis']) continue;
      frontier.add(current);
    }
    return true;
  }

  @override
  List<ValueSettingsTarget> get valueSettingsTargets => [
    if (_range case final r?) r,
  ];
}
