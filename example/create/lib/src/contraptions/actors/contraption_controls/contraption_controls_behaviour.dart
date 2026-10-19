// `ContraptionControlsMovement` and `ContraptionControlsMovingInteraction`: the actor of the
// contraption controls, and the click that toggles a whole actor type.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../common/common.dart';
import '../../core/contraption.dart';
import '../../core/movement.dart';
import '../../core/nbt_map.dart';
import '../../storage/stacks.dart';
import '../actor_runtime.dart';
import 'contraption_controls_block.dart';

/// `ContraptionControlsMovement`.
final class ContraptionControlsMovement extends MovementBehaviour {
  const ContraptionControlsMovement();

  /// The controls themselves cannot be disabled by other controls.
  @override
  StoredStack? canBeDisabledVia(MovementContext context) => null;

  @override
  void stopMoving(MovementContext context) {
    final filter = getFilter(context);
    final data = context.blockEntityData;
    if (filter == null || data == null) return;
    data.putBool(
      'Disabled',
      context.contraption.isActorTypeDisabled(filter) ||
          context.contraption.isActorTypeDisabled(StoredStack.empty),
    );
  }

  /// `isSameFilter`.
  static bool isSameFilter(StoredStack a, StoredStack b) {
    if (a.isEmpty && b.isEmpty) return true;
    return a.sameItemSameComponents(b);
  }

  /// `getFilter`: the filter saved on the block entity, `null` without block entity data.
  static StoredStack? getFilter(MovementContext context) {
    final data = context.blockEntityData;
    if (data == null) return null;
    final value = data['Filter'];
    if (value == null) return StoredStack.empty;
    return StoredStack.fromNbt(NbtMap.of(value));
  }

  /// `isDisabledInitially`.
  static bool isDisabledInitially(MovementContext context) =>
      context.blockEntityData?.getBool('Disabled') ?? false;
}

/// `ContraptionControlsMovingInteraction`.
final class ContraptionControlsMovingInteraction
    extends MovingInteractionBehaviour {
  const ContraptionControlsMovingInteraction();

  @override
  bool handlePlayerInteraction(
    InteractingPlayer player,
    Pos localPos,
    Contraption contraption,
  ) {
    final actor = _actorAt(contraption, localPos);
    if (actor == null) return true;

    final filter =
        ContraptionControlsMovement.getFilter(actor) ?? StoredStack.empty;
    var disable = true;
    var invert = false;

    final disabledActors = contraption.getDisabledActors();
    for (final present in List.of(disabledActors)) {
      final sameFilter = ContraptionControlsMovement.isSameFilter(
        present,
        filter,
      );
      if (present.isEmpty) {
        disabledActors.remove(present);
        disable = false;
        if (!sameFilter) invert = true;
        continue;
      }
      if (!sameFilter) continue;
      disabledActors.remove(present);
      disable = false;
      break;
    }

    if (invert) {
      for (final actorContext in contraption.getActors()) {
        final behaviour = MovementBehaviours.of(actorContext.state);
        if (behaviour == null) continue;
        final stack = behaviour.canBeDisabledVia(actorContext);
        if (stack == null) continue;
        if (ContraptionControlsMovement.isSameFilter(stack, filter)) continue;
        if (contraption.isActorTypeDisabled(stack)) continue;
        disabledActors.add(stack);
      }
    }

    if (filter.isEmpty) disabledActors.clear();
    if (disable) disabledActors.add(filter);

    contraption.setActorsActive(filter, !disable);
    ContraptionControlsBlockEntity.sendStatus(player, filter, !disable);

    final position = actor.position;
    final world = actors?.worldOf(actor);
    if (world != null && position != null) {
      world.playCustomSound(
        soundName: 'create:controller_click',
        category: SoundCategory.blocks,
        pos: position,
        volume: 1,
        pitch: disable ? 0.8 : 1.5,
      );
    }
    return true;
  }

  /// The actor context of the clicked block.
  static MovementContext? _actorAt(Contraption contraption, Pos localPos) =>
      contraption.getActorAt(localPos);
}
