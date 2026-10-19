// `BasinBlockEntity.filtering` (`FilteringBehaviour` with a `BasinValueBox`): the item (or
// bucket, for fluids) a basin's recipe result must match. The client sets it through the
// `create:value_settings` board; a plain click with an item in hand also replaces it.
// Ported from `foundation/blockEntity/behaviour/filtering/FilteringBehaviour.java`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/value_settings.dart';
import '../../core/block_entity.dart';
import '../common/stack.dart';
import '../crafter/machine_support.dart'
    show consumeFromHand, giveToPlayerStack, isWrenchItem;
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import 'basin_block_entity.dart';

/// The filter items whose stack is consumed when they are placed in the slot.
const Set<String> basinFilterItemKeys = {
  'create:filter',
  'create:attribute_filter',
  'create:package_filter',
};

/// The basin's filter slot.
class BasinFilterBehaviour extends BlockEntityBehaviour
    implements ValueSettingsTarget, ShortInteractTarget {
  static const String type = 'basin_filter';

  @override
  String get id => type;

  BasinBlockEntity get basin => owner as BasinBlockEntity;

  /// `upTo`: whether the count row means "up to" rather than "exactly".
  bool upTo = true;

  /// `count`: the amount row of the value box.
  int count = 64;

  /// `getFilter()`.
  PStack get filter => basin.filter;

  /// `setFilter(stack)`.
  void setFilter(PStack stack) {
    basin.filter = stack.isEmpty ? PStack.empty : stack.withCount(1);
    basin.notifyChangeOfContents();
    basin.markDirty();
    basin.sendData();
  }

  /// `FilteringBehaviour.test(stack)`.
  bool test(PStack stack) => basin.filterAccepts(stack);

  /// `FilteringBehaviour.test(fluid)`.
  bool testFluid(PFluid fluid) => basin.filterAcceptsFluid(fluid);

  // -- Value box (`create:value_settings`) -----------------------------------------------------

  @override
  int get netId => 0;

  @override
  bool get acceptsValueSettings => true;

  @override
  (int, int) get valueSettings => (upTo ? 0 : 1, count <= 0 ? 64 : count);

  @override
  void setValueSettings(
    Player? player,
    int row,
    int value, {
    required bool ctrlDown,
  }) {
    count = value.clamp(1, 64);
    upTo = row == 0;
    basin.markDirty();
    basin.sendData();
  }

  /// `onShortInteract`: sets the filter from the item in the main hand.
  @override
  void onShortInteract(Player player) {
    unawaited(_shortInteract(player));
  }

  Future<void> _shortInteract(Player player) async {
    final held = player.getItemInHand(hand: Hand.right);
    final inHand = await HostStacks.read(held);
    held?.dispose();

    if (isWrenchItem(ProcessingRuntime.instance, inHand.key) ||
        inHand.key == 'create:mechanical_arm') {
      return;
    }

    final previous = basin.filter;
    setFilter(inHand);

    final world = basin.world;
    if (world == null) return;
    if (basinFilterItemKeys.contains(previous.key)) {
      await giveToPlayerStack(player, world, previous);
    }
    if (!player.isCreative && basinFilterItemKeys.contains(inHand.key)) {
      await consumeFromHand(player, Hand.right, 1);
    }
    world.playSound(
      sound: Sound.entityItemFrameAddItem,
      category: SoundCategory.blocks,
      pos: (basin.pos.x + .5, basin.pos.y + .5, basin.pos.z + .5),
      volume: .25,
      pitch: .1,
    );
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    upTo = tag.getBool('UpTo') ?? true;
    count = tag.getInt('FilterAmount') ?? 64;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putBool('UpTo', upTo);
    tag.putInt('FilterAmount', count);
  }
}
