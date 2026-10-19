// `ContraptionControlsBlock` and `ContraptionControlsBlockEntity`: the controls that switch actor
// types of a contraption on and off, with an optional filter item.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../common/common.dart';
import '../../../common/host_bridge.dart';
import '../../../core/block_entity.dart';
import '../../../core/blocks.dart';
import '../../core/movement.dart';
import '../../storage/stacks.dart';
import '../actor_runtime.dart';
import '../actor_shapes.dart';
import '../filter_nbt.dart';
import '../host_interacting_player.dart';
import '../train_controls/controls_block.dart';

/// `AllShapes.CONTRAPTION_CONTROLS`.
final List<BlockBox> _contraptionControlsShape = [
  actorBox(0, 0, 6, 2, 16, 16),
  actorBox(14, 0, 6, 16, 16, 16),
  actorBox(0, 0, 14, 16, 16, 16),
  actorBox(0, 0, 6, 16, 12, 16),
  actorBox(0, 0, 4, 16, 2, 16),
];

/// `AllShapes.CONTRAPTION_CONTROLS_COLLISION`.
final List<BlockBox> _contraptionControlsCollision = [
  actorBox(0, 0, 6, 2, 16, 16),
  actorBox(14, 0, 6, 16, 16, 16),
  actorBox(0, 0, 14, 16, 16, 16),
  actorBox(0, 0, 7, 16, 12, 16),
];

/// `ContraptionControlsBlockEntity`.
final class ContraptionControlsBlockEntity extends CreateBlockEntity {
  static const String type = 'create:contraption_controls';

  ContraptionControlsBlockEntity(super.worldId, super.pos);

  /// `filtering.getFilter()`.
  StoredStack filterStack = StoredStack.empty;

  /// `filtering.count` and `filtering.upTo` (`FilterAmount`, `UpTo`).
  int filterCount = 64;
  bool filterUpTo = true;

  /// `disabled`.
  bool disabled = false;

  /// `powered`.
  bool powered = false;

  /// `pressButton`: the client animation only; the server keeps no state for it.
  void pressButton() {}

  /// `updatePoweredState`.
  Future<void> updatePoweredState() async {
    final w = world;
    if (w == null) return;
    final isPowered = await w.hasNeighborSignal(pos: this.pos);
    if (powered == isPowered) return;
    powered = isPowered;
    disabled = isPowered;
    sendData();
  }

  @override
  void initialize() {
    super.initialize();
    unawaited(updatePoweredState());
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    final filtering = readFilteringBehaviour(tag);
    filterStack = filtering.filter;
    filterCount = filtering.count;
    filterUpTo = filtering.upTo;
    disabled = tag.getBool('Disabled') ?? false;
    powered = tag.getBool('Powered') ?? false;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    writeFilteringBehaviour(tag, filterStack, filterCount, filterUpTo);
    tag.putBool('Disabled', disabled);
    tag.putBool('Powered', powered);
  }

  /// `sendStatus`: tells the player whether the actor type is now on or off.
  static void sendStatus(
    InteractingPlayer player,
    StoredStack filter,
    bool enabled,
  ) {
    final host = player.hostPlayer;
    if (host is! Player) return;
    final state = TextComponent.translate(
      key: 'create.contraption.controls.actor_toggle.${enabled ? 'on' : 'off'}',
      with_: const [],
    );
    final TextComponent message;
    if (filter.isEmpty) {
      message = TextComponent.translate(
        key: 'create.contraption.controls.all_actor_toggle',
        with_: [state],
      );
    } else {
      message = TextComponent.translate(
        key: 'create.contraption.controls.specific_actor_toggle',
        with_: [
          TextComponent.text(plain: filter.item),
          state,
        ],
      );
    }
    host.sendSystemMessage(text: message, overlay: true);
  }
}

/// `ContraptionControlsBlock`.
CreateBlock buildContraptionControlsBlock() => buildControlsBlock(
  'contraption_controls',
  selection: _contraptionControlsShape,
  collision: _contraptionControlsCollision,
  blockEntityType: ContraptionControlsBlockEntity.type,
  behavior: BlockBehavior(
    onUseWithoutItem: (server, e) async {
      final be = actors?.blockEntities.typed<ContraptionControlsBlockEntity>(
        e.targetWorld.getId(),
        e.pos,
      );
      if (be == null) return BlockUseResult.pass;
      be.pressButton();
      be.disabled = !be.disabled;
      be.sendData();
      ContraptionControlsBlockEntity.sendStatus(
        HostInteractingPlayer(e.player),
        be.filterStack,
        !be.disabled,
      );
      e.targetWorld.playCustomSound(
        soundName: 'create:controller_click',
        category: SoundCategory.blocks,
        pos: e.pos.toPos().center,
        volume: 1,
        pitch: be.disabled ? 0.8 : 1.5,
      );
      return BlockUseResult.success;
    },
    onNeighborUpdate: (server, e) {
      final be = actors?.blockEntities.typed<ContraptionControlsBlockEntity>(
        e.targetWorld.getId(),
        e.pos,
      );
      unawaited(be?.updatePoweredState() ?? Future.value());
    },
  ),
);
