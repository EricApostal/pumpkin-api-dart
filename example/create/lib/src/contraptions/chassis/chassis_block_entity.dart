// `ChassisBlockEntity`: the range of a linear or radial chassis and the blocks it would take along.
// The range is a scroll value (1..`kinetics.contraptions.maxChassisRange`); the included positions
// are what the contraption assembly asks for.
//
// Java: `content/contraptions/chassis/ChassisBlockEntity`.
import 'dart:collection';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/value_settings.dart';
import '../../common/common.dart';
import '../../core/block_entity.dart';
import '../../kinetics/behaviours.dart';
import 'chassis_logic.dart';
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_runtime.dart';

final class ChassisBlockEntity extends CreateBlockEntity
    implements ValueSettingsHost {
  ChassisBlockEntity(super.worldId, super.pos) {
    // `addBehaviours`: added at construction so `read` restores the saved `ScrollValue`.
    final max = ActuatorRuntime.instance.settings.maxChassisRange;
    final range = ScrollValueBehaviour().between(1, max);
    range.value = max ~/ 2;
    _range = addBehaviour(range);
  }

  ScrollValueBehaviour? _range;

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
    return includedChassisPositions(
      level,
      localPos,
      state,
      range,
      forcedMovement,
    );
  }

  /// `collectChassisGroup`: every chassis of the connected group (bulk scroll values).
  List<ChassisBlockEntity> collectChassisGroup() {
    final frontier = Queue<Pos>()..add(localPos);
    final collected = <ChassisBlockEntity>[];
    final visited = <Pos>{};
    while (frontier.isNotEmpty) {
      final current = frontier.removeFirst();
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
  bool addAttachedChasses(Queue<Pos> frontier, Set<Pos> visited) {
    final state = chassisState;
    final level = ActuatorHosts.levelOf(worldId);
    if (state == null || level == null) return false;
    return addAttachedChassesTo(level, localPos, state, frontier, visited);
  }

  @override
  List<ValueSettingsTarget> get valueSettingsTargets => [?_range];
}

