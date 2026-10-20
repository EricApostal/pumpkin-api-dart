// `ContraptionControlsMovement` and `ContraptionControlsMovingInteraction`: the actor of the
// contraption controls, and the click that toggles a whole actor type.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/payloads.dart' show ItemComponentPatch, ItemStackData;
import '../../../common/common.dart';
import '../../../core/nbt.dart';
import '../../core/contraption.dart';
import '../../core/movement.dart';
import '../../core/nbt_map.dart';
import '../../elevator/elevator_contraption.dart';
import '../../storage/stacks.dart';
import '../actor_runtime.dart';
import 'contraption_controls_block.dart';

/// `ContraptionControlsMovement`.
final class ContraptionControlsMovement extends MovementBehaviour {
  const ContraptionControlsMovement();

  /// The controls themselves cannot be disabled by other controls.
  @override
  StoredStack? canBeDisabledVia(MovementContext context) => null;

  /// `startMoving`: an elevator controls block never keeps a filter.
  @override
  void startMoving(MovementContext context) {
    if (context.contraption is ElevatorContraption)
      context.blockEntityData?.remove('Filter');
  }

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

    // `elevatorInteraction`: the elevator selects its floor through `ElevatorTargetFloorPacket`;
    // the server click only plays the feedback sounds.
    if (contraption is ElevatorContraption) {
      final position = actor.position;
      final world = actors?.worldOf(actor);
      if (world != null && position != null) {
        world.playCustomSound(
          soundName: 'create:controller_click',
          category: SoundCategory.blocks,
          pos: position,
          volume: 1,
          pitch: 1.5,
        );
        world.playCustomSound(
          soundName: 'create:contraption_assemble',
          category: SoundCategory.blocks,
          pos: position,
          volume: .75,
          pitch: .8,
        );
      }
      return true;
    }

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
        _sendToggle(contraption, stack, true);
      }
    }

    if (filter.isEmpty) disabledActors.clear();
    if (disable) disabledActors.add(filter);

    contraption.setActorsActive(filter, !disable);
    ContraptionControlsBlockEntity.sendStatus(player, filter, !disable);
    _sendToggle(contraption, filter, disable);

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

  /// `ContraptionDisableActorPacket` to the clients tracking the contraption.
  static void _sendToggle(
    Contraption contraption,
    StoredStack filter,
    bool disable,
  ) {
    final entity = contraption.entity;
    if (entity == null) return;
    final ids = actors?.itemIds;
    var stack = ItemStackData.empty;
    if (filter.isNotEmpty && ids != null) {
      // `ItemStack.OPTIONAL_STREAM_CODEC` of `filter.getStack()`: the item, its count and
      // the components that differ from the item's defaults.
      final id = ids.idOf(filter.item);
      // An item the id table does not know cannot be sent; the empty filter means "all".
      if (id != null) stack = ItemStackData(id, filter.count, filterComponentPatch(filter));
    }
    entity.sendPayload('create:contraption_actor_toggle', {
      'entityId': entity.entityId,
      'filter': stack,
      'enable': !disable,
    });
  }

  /// The actor context of the clicked block.
  static MovementContext? _actorAt(Contraption contraption, Pos localPos) =>
      contraption.getActorAt(localPos);
}

/// The component patch of the saved [filter] (`DataComponentPatch.STREAM_CODEC`): the saved
/// components, each encoded with the component's own network codec. A component the codec
/// table cannot encode is left out (the receiver then sees the item's default).
ItemComponentPatch filterComponentPatch(StoredStack filter) {
  final comps = filter.components;
  if (comps == null || comps.isEmpty) return ItemComponentPatch.empty;
  final added = <(int, Uint8List)>[];
  for (final key in comps.keys) {
    final id = VanillaIds.dataComponentTypes.idOf(key);
    if (id == null) continue;
    try {
      added.add((id, DataComponentCodec.encode(key, _componentJson(comps[key]!))));
    } on Object {
      // No encoder for this component: the receiver keeps the item's default value.
    }
  }
  return added.isEmpty ? ItemComponentPatch.empty : ItemComponentPatch(added: added);
}

/// An NBT value as the JSON shape `DataComponentCodec` reads (the text component codecs take
/// exactly the tag's own shape).
Object? _componentJson(NbtValue v) => switch (v.kind) {
  NbtKind.compound => <String, Object?>{
    for (final e in NbtMap.of(v).map.entries) e.key: _componentJson(e.value),
  },
  NbtKind.list => [for (final e in v.value as List<NbtValue>) _componentJson(e)],
  NbtKind.string => v.value as String,
  NbtKind.byte => (v.value as int) != 0,
  NbtKind.byteArray || NbtKind.intArray || NbtKind.longArray => v.value,
  _ => v.value,
};
