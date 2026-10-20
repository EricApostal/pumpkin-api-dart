// `ContraptionControlsBlock` and `ContraptionControlsBlockEntity`: the controls that switch actor
// types of a contraption on and off, with an optional filter item.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/value_settings.dart';
import '../../../common/common.dart';
import '../../../common/host_bridge.dart';
import '../../../core/block_entity.dart';
import '../../../core/blocks.dart';
import '../../../core/nbt.dart';
import '../../core/nbt_map.dart';
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
final class ContraptionControlsBlockEntity extends CreateBlockEntity
    implements ValueSettingsHost {
  static const String type = 'create:contraption_controls';

  ContraptionControlsBlockEntity(super.worldId, super.pos);

  /// `filtering`: the item filter slot on top of the block (`ControlsSlot`).
  late final ControlsFilter filtering = addBehaviour(ControlsFilter());

  @override
  List<ValueSettingsTarget> get valueSettingsTargets => [filtering];

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
    // `DyeHelper.getDyeColors(enabled ? LIME : ORANGE).getFirst()`: the bright dye colour.
    final (r, g, b) = enabled ? (0xA3, 0xDF, 0x55) : (0xEE, 0x92, 0x46);
    final state = TextComponent.translate(
      key: 'create.contraption.controls.actor_toggle.${enabled ? 'on' : 'off'}',
      with_: const [],
    )..colorRgb(color: RgbColor(r: r, g: g, b: b));
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
          // `filter.getHoverName().getString()`: a renamed stack shows its name.
          TextComponent.text(plain: filterHoverName(filter)),
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

/// `ItemStack.getHoverName().getString()`: the `custom_name` of the stack, else a readable
/// name for the item key (the host resolves no item names).
String filterHoverName(StoredStack stack) {
  final custom = stack.components?['minecraft:custom_name'];
  if (custom != null) {
    final text = _plainText(custom);
    if (text != null && text.isNotEmpty) return text;
  }
  final key = stack.item;
  final path = key.substring(key.indexOf(':') + 1);
  return path.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

/// The plain text of a text component tag (`{"text": ...}` or `{"translate": ...}`).
String? _plainText(NbtValue value) {
  if (value.kind != NbtKind.compound) return null;
  final map = NbtMap.of(value);
  final literal = map['text'];
  if (literal != null && literal.kind == NbtKind.string) return literal.value as String;
  final key = map['translate'];
  if (key != null && key.kind == NbtKind.string) return key.value as String;
  return null;
}

/// `FilteringBehaviour` of the contraption controls: one filter item, restricted to the
/// items in `create:contraption_controlled` (`withPredicate(AllItemTags.CONTRAPTION_CONTROLLED)`).
final class ControlsFilter extends BlockEntityBehaviour
    implements ValueSettingsTarget, ShortInteractTarget {
  static const String behaviourId = 'Filtering';
  static const String tag = 'create:contraption_controlled';

  @override
  String get id => behaviourId;

  ContraptionControlsBlockEntity get controls => owner as ContraptionControlsBlockEntity;

  /// `withPredicate(AllItemTags.CONTRAPTION_CONTROLLED::matches)`.
  static bool accepts(String itemKey) =>
      itemKey == 'minecraft:air' || Tags.item(itemKey, tag);

  /// `setFilter(stack)`: false for an item the predicate refuses.
  bool setFilter(StoredStack stack) {
    if (stack.isNotEmpty && !accepts(stack.item)) return false;
    controls.filterStack = stack.isEmpty ? StoredStack.empty : stack;
    controls.sendData();
    return true;
  }

  /// `onShortInteract(player, hand, side, hit)`: the held item becomes the filter.
  @override
  void onShortInteract(Player player) {
    unawaited(_applyHeld(player, Hand.right));
  }

  Future<void> _applyHeld(Player player, Hand hand) async {
    final held = player.getItemInHand(hand: hand);
    if (held == null) return;
    final key = await held.getRegistryKey();
    if (key == 'create:wrench' || key == 'create:mechanical_arm') return;
    final count = await held.getCount();
    if (count <= 0) {
      setFilter(StoredStack.empty);
      return;
    }
    final applied = StoredStack(key, 1);
    if (!setFilter(applied)) return;
    controls.world?.playSound(
      sound: Sound.entityItemFrameAddItem,
      category: SoundCategory.blocks,
      pos: (owner.pos.x + .5, owner.pos.y + .5, owner.pos.z + .5),
      volume: .25,
      pitch: .1,
    );
  }

  // -- ValueSettingsTarget: the slot has no amount row (`ControlsSlot`, no `showCount`). ----

  @override
  int get netId => 1;

  @override
  bool get acceptsValueSettings => false;

  @override
  (int row, int value) get valueSettings => (0, 0);

  @override
  void setValueSettings(Player? player, int row, int value, {required bool ctrlDown}) {}
}
