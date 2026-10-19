// `CreativeCrateBlockEntity` (server behaviour): an endless supply of the item in its filter that
// voids everything inserted. (This Create version has no plain `create:crate` block in the
// manifest, only the creative one.)
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart';
import '../../../common/direction.dart';
import '../../../core/block_entity.dart';
import '../../behaviours/filtering.dart';
import '../../behaviours/value_box.dart';
import '../../items/inventory.dart';
import '../../items/item_codec.dart';
import '../../items/item_data.dart';
import '../../runtime.dart';
import '../transport_inventory_api.dart';

/// `CreativeCrateBlockEntity`.
class CreativeCrateBlockEntity extends CreateBlockEntity
    implements ItemInventoryProvider {
  late final FilteringBehaviour filtering;
  late final _BottomlessInventory _inventory = _BottomlessInventory(this);

  CreativeCrateBlockEntity(super.worldId, super.pos) {
    filtering = addBehaviour(FilteringBehaviour(const FixedSlot(_filterSlot)))
      ..withPredicate((stack) => true);
  }

  static Vec3 _filterSlot(BState state) => voxel(8, 13.5, 8);

  ConveyanceRuntime get rt => ConveyanceRuntime.i;

  /// The supplied stack: the filter.
  ItemValue get suppliedStack => filtering.filter;

  @override
  ItemInventory? itemInventory(Direction? side) => _inventory;

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    // The contraption's mounted storage reads `Filter` as a vanilla stack (`id` / `count`); write
    // both that and the private form the filtering behaviour reads.
    final stack = filtering.filter;
    final filter = ItemCodec.toNbt(stack)
      ..putString('id', stack.isEmpty ? 'minecraft:air' : stack.key)
      ..putInt('count', stack.count);
    tag.putCompound('Filter', filter);
  }
}

/// `BottomlessItemHandler`: two slots, an endless supply of the filter and nothing else.
final class _BottomlessInventory implements ItemInventory {
  final CreativeCrateBlockEntity be;

  _BottomlessInventory(this.be);

  @override
  int get slots => 2;

  @override
  ItemValue getStack(int slot) {
    if (slot == 1) return ItemValue.empty;
    final stack = be.suppliedStack;
    return stack.isEmpty ? ItemValue.empty : stack.withCount(stack.maxStack);
  }

  @override
  int slotLimit(int slot) => 64;

  @override
  bool isItemValid(int slot, ItemValue stack) => true;

  @override
  ItemValue insert(int slot, ItemValue stack, {bool simulate = false}) =>
      ItemValue.empty;

  @override
  ItemValue extract(int slot, int amount, {bool simulate = false}) {
    if (slot == 1) return ItemValue.empty;
    final stack = be.suppliedStack;
    if (stack.isEmpty) return ItemValue.empty;
    final count = amount < stack.maxStack ? amount : stack.maxStack;
    return stack.withCount(count);
  }
}
