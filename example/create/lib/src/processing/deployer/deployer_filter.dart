// `DeployerBlockEntity.filtering` (the `DeployerFilterSlot`): one item that decides what the
// deployer may pick up and what it processes. Ported from
// `content/kinetics/deployer/DeployerFilterSlot.java` and the `FilteringBehaviour` it configures.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/redstone.dart' show ItemFilterApi;
import '../../api/value_settings.dart';
import '../../core/block_entity.dart';
import '../common/stack.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../crafter/machine_support.dart'
    show consumeFromHand, giveToPlayerStack, isWrenchItem;

/// The filter items (`AllItems`): their contents are matched by the redstone module's filter API.
const Set<String> _filterItemKeys = {
  'create:filter',
  'create:attribute_filter',
  'create:package_filter',
};

/// `FilteringBehaviour.test(stack)` for a [filter] stack in the world [worldId].
bool deployerFilterTest(PStack filter, PStack candidate, String worldId) {
  if (filter.isEmpty) return true;
  if (_filterItemKeys.contains(filter.key)) {
    final api = ProcessingRuntime.instance.services.find<ItemFilterApi>();
    if (api == null) return false;
    return api.testItem(worldId, filter.key, candidate.key);
  }
  return candidate.key == filter.key;
}

/// The deployer's filter slot.
class DeployerFilterBehaviour extends BlockEntityBehaviour
    implements ValueSettingsTarget, ShortInteractTarget {
  static const String type = 'deployer_filter';

  @override
  String get id => type;

  /// The filter stack; empty accepts everything.
  PStack filter = PStack.empty;

  /// `FilteringBehaviour.count` / `upTo` (written for NBT parity; the deployer's value box does
  /// not show a count).
  int count = 64;
  bool upTo = true;

  bool get isEmpty => filter.isEmpty;

  /// `FilteringBehaviour.getMaxStackSize()`.
  int get maxStackSize => filter.isEmpty ? 64 : filter.maxStack;

  /// `FilteringBehaviour.test(stack)`.
  bool test(PStack stack) => deployerFilterTest(filter, stack, owner.worldId);

  /// `FilteringBehaviour.setFilter(stack)`: stores [stack] as given (the caller decides on the
  /// count, `onShortInteract` uses one for a filter item). Returns false when
  /// [canShortInteract] refuses the item.
  bool setFilter(PStack stack) {
    if (stack.isNotEmpty && !canShortInteract(stack)) return false;
    filter = stack.isEmpty ? PStack.empty : stack;
    if (!upTo && filter.isNotEmpty && count > filter.maxStack) {
      count = filter.maxStack;
    }
    owner.markDirty();
    owner.sendData();
    return true;
  }

  /// `FilteringBehaviour.canShortInteract`: the wrench and the mechanical arm are tools, not
  /// filter items, so they never land in the slot.
  bool canShortInteract(PStack stack) {
    if (isWrenchItem(ProcessingRuntime.instance, stack.key)) return false;
    if (stack.key == 'create:mechanical_arm') return false;
    return true;
  }

  // -- Value box (`create:value_settings`) -----------------------------------------------------

  /// `FilteringBehaviour.netId`.
  @override
  int get netId => 1;

  /// The deployer's filter has no count; the flag is set so the short interaction of the slot
  /// (the click that sets the filter item) reaches [onShortInteract].
  @override
  bool get acceptsValueSettings => true;

  @override
  (int, int) get valueSettings => (0, 0);

  @override
  void setValueSettings(
    Player? player,
    int row,
    int value, {
    required bool ctrlDown,
  }) {}

  /// `FilteringBehaviour.onShortInteract`: sets the filter from the player's held item.
  @override
  void onShortInteract(Player player) {
    final rt = ProcessingRuntime.instance;
    unawaited(_shortInteract(rt, player));
  }

  Future<void> _shortInteract(ProcessingRuntime rt, Player player) async {
    final world = owner.world;
    final held = player.getItemInHand(hand: Hand.right);
    final inHand = await HostStacks.read(held);
    held?.dispose();

    if (!canShortInteract(inHand)) return;

    final previous = filter;
    // Java refunds the old filter when it is a filter item, and only takes it back out of a
    // creative player's inventory when that player has a spare.
    if (_filterItemKeys.contains(previous.key)) {
      if (!player.isCreative && world != null) {
        await giveToPlayerStack(player, world, previous);
      }
    }

    // `if (toApply.getItem() instanceof FilterItem) toApply.setCount(1)`.
    final toApply = _filterItemKeys.contains(inHand.key)
        ? inHand.withCount(1)
        : inHand;
    if (!setFilter(toApply)) {
      player.showActionbar(text: TextComponent.text(plain: 'Invalid item'));
      if (world != null) {
        world.playSound(
          sound: Sound.entityVillagerNo,
          category: SoundCategory.blocks,
          pos: (owner.pos.x + .5, owner.pos.y + .5, owner.pos.z + .5),
          volume: 1,
          pitch: 1,
        );
      }
      return;
    }
    if (inHand.isEmpty) {
      player.showActionbar(text: TextComponent.text(plain: 'Filter cleared'));
    }

    // Only a filter item is taken out of the hand.
    if (!player.isCreative && _filterItemKeys.contains(inHand.key)) {
      await consumeFromHand(player, Hand.right, 1);
    }
    if (world != null) {
      world.playSound(
        sound: Sound.entityItemFrameAddItem,
        category: SoundCategory.blocks,
        pos: (owner.pos.x + .5, owner.pos.y + .5, owner.pos.z + .5),
        volume: .25,
        pitch: .1,
      );
    }
    rt.log.debug('The deployer filter at ${owner.pos} is now ${filter.key}');
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    filter = StackNbt.read(tag.getCompound('Filter'));
    count = tag.getInt('FilterAmount') ?? 0;
    upTo = tag.getBool('UpTo') ?? false;
    // `FilteringBehaviour.read`: migrate data written before the count existed.
    if (count == 0) {
      upTo = true;
      count = maxStackSize;
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putCompound('Filter', StackNbt.writeOrEmpty(filter));
    tag.putInt('FilterAmount', count);
    tag.putBool('UpTo', upTo);
  }
}
