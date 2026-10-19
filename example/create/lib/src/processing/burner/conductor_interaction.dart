// `ConductorBlockInteractionBehavior` and its blaze burner implementation: a player clicking a
// lit blaze burner next to train controls hands the held schedule to the train, resumes a paused
// schedule or takes the schedule back. Ported from
// `api/behaviour/interaction/ConductorBlockInteractionBehavior.java`.
//
// The Dart `MovingInteractionBehaviour` does not tell which hand was used, so the interaction
// always acts on the main hand (Java ignores the off hand).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/trains.dart';
import '../../common/common.dart' hide pos;
import '../../contraptions/core/contraption.dart';
import '../../contraptions/core/movement.dart';
import '../../contraptions/core/structure_info.dart';
import '../../core/nbt.dart' show NetworkNbt;
import '../../trains/manager/create.dart' show Create;
import '../../trains/schedule/schedule_item.dart'
    show ScheduleItem, scheduleItemKey, trainScheduleComponent;
import '../recipe/heat.dart';
import 'blaze_burner_block.dart';

/// `ConductorBlockInteractionBehavior`: the common part of the blocks that act as conductors.
abstract class ConductorBlockInteractionBehaviour
    extends MovingInteractionBehaviour {
  const ConductorBlockInteractionBehaviour();

  /// `isValidConductor(state)`.
  bool isValidConductor(BState state);

  /// `onScheduleUpdate(hasSchedule, state, setState)`: called after a schedule was set or taken.
  void onScheduleUpdate(
    bool hasSchedule,
    BState currentState,
    void Function(BState newState) setState,
  ) {}

  @override
  Future<bool> handlePlayerInteraction(
    InteractingPlayer player,
    Pos localPos,
    Contraption contraption,
  ) async {
    final hostPlayer = player.hostPlayer;
    if (hostPlayer is! Player) return false;

    final handle = contraption.entity;
    if (handle == null) return false;

    final info = contraption.blocks[localPos];
    if (info == null || !isValidConductor(info.state)) return false;

    final carriageEntity = _carriageEntityOf(handle.entityId);
    if (carriageEntity == null) return false;
    final carriage = carriageEntity.getCarriage();
    final train = carriage?.train;
    if (train == null) return false;
    final carriageContraption = carriageEntity.getContraption();
    if (carriageContraption == null) return false;

    final assemblyDirection = carriageContraption.getAssemblyDirection();
    final held = hostPlayer.getItemInHand(hand: Hand.right);

    for (final direction in _directionsInAxis(assemblyDirection.axis)) {
      if (!_inControl(contraption, localPos, direction)) continue;

      final runtime = train.runtime;
      if (runtime.getSchedule() != null) {
        if (runtime.paused && !runtime.completed) {
          runtime.paused = false;
          player.playSound('create:confirm', 1, volume: 1);
          _overlay(hostPlayer, 'create.schedule.continued');
          return true;
        }

        if (held != null && await held.getCount() > 0) {
          player.playSound('create:deny', 1, volume: 1);
          _overlay(hostPlayer, 'create.schedule.remove_with_empty_hand');
          return true;
        }

        player.playSound('minecraft:entity.item.pickup', 1, volume: 1);
        _overlay(
          hostPlayer,
          runtime.isAutoSchedule
              ? 'create.schedule.auto_removed_from_train'
              : 'create.schedule.removed_from_train',
        );
        final returned = runtime.returnSchedule();
        if (returned != null) await _giveSchedule(hostPlayer, returned);
        onScheduleUpdate(
          false,
          info.state,
          (newState) => _setBlockState(contraption, localPos, info, newState),
        );
        return true;
      }

      final isSchedule =
          held != null && await held.getRegistryKey() == scheduleItemKey;
      if (!isSchedule) return true;

      final schedule = ScheduleItem.getSchedule(
        held.customComponent(trainScheduleComponent),
      );
      if (schedule == null) return false;
      if (schedule.entries.isEmpty) {
        player.playSound('create:deny', 1, volume: 1);
        _overlay(hostPlayer, 'create.schedule.no_stops');
        return true;
      }

      onScheduleUpdate(
        true,
        info.state,
        (newState) => _setBlockState(contraption, localPos, info, newState),
      );
      runtime.setSchedule(schedule, false);
      TrainFx.effects.awardAdvancement(player.uuid, 'conductor');
      player.playSound('create:confirm', 1, volume: 1);
      _overlay(hostPlayer, 'create.schedule.applied_to_train');

      final count = await held.getCount();
      if (count <= 1) {
        await hostPlayer.setItemInHand(hand: Hand.right, stack: null);
      } else {
        await held.setCount(count: count - 1);
        await hostPlayer.setItemInHand(hand: Hand.right, stack: held);
      }
      return true;
    }

    _overlay(hostPlayer, 'create.schedule.non_controlling_seat');
    player.playSound('create:deny', 1, volume: 1);
    return true;
  }

  static void _setBlockState(
    Contraption contraption,
    Pos localPos,
    StructureBlockInfo info,
    BState newState,
  ) {
    if (info.state == newState) return;
    contraption.entity?.setBlock(
      localPos,
      StructureBlockInfo(info.pos, newState, info.nbt),
    );
  }

  /// `Iterate.directionsInAxis`.
  static Iterable<Direction> _directionsInAxis(Axis axis) =>
      Direction.values.where((d) => d.axis == axis);

  /// `CarriageContraption.inControl(localPos, direction)`: the block next to the conductor is a
  /// train control facing away from it.
  static bool _inControl(Contraption contraption, Pos localPos, Direction dir) {
    final info = contraption.blocks[localPos.relative(dir)];
    if (info == null) return false;
    if (info.state.key != CarriageContraption.controlsKey) return false;
    return info.state.dir('facing') == dir.opposite;
  }

  /// The carriage entity with [entityId], found through the trains of the railway manager.
  static CarriageContraptionEntity? _carriageEntityOf(int entityId) {
    for (final train in Create.RAILWAYS.trains.values) {
      for (final carriage in train.carriages) {
        CarriageContraptionEntity? found;
        carriage.forEachPresentEntity((entity) {
          if (entity.id == entityId) found = entity;
        });
        if (found != null) return found;
      }
    }
    return null;
  }

  /// `player.setItemInHand(hand, train.runtime.returnSchedule(...))`: a new schedule item.
  static Future<void> _giveSchedule(Player player, CTag tag) async {
    final item = ItemStack.create(registryKey: scheduleItemKey, count: 1);
    item.setCustomComponent(
      trainScheduleComponent,
      NetworkNbt.encode(tag.toNbt()),
    );
    final left = await player.give(item);
    if (left != null) {
      await player.getWorld().dropItem(player.getPosition(), left);
    }
  }

  static void _overlay(Player player, String key) => player.sendSystemMessage(
    text: TextComponent.translate(key: key, with_: const []),
    overlay: true,
  );
}

/// `ConductorBlockInteractionBehavior.BlazeBurner`: any lit blaze burner is a conductor.
final class BlazeBurnerConductorInteraction
    extends ConductorBlockInteractionBehaviour {
  const BlazeBurnerConductorInteraction();

  @override
  bool isValidConductor(BState state) =>
      state.key == BlazeBurnerBlock.key &&
      BlazeBurnerBlock.heatLevelOf(state) != HeatLevel.none;
}
