// `FilteringBehaviour` as the smart observer and the threshold switch use it: one filter
// item slot with an amount. Only the item identity is kept; the contents of list and
// attribute filters (`create:filter`, `create:attribute_filter`) belong to the logistics
// module's `FilterItemStack` and are consulted through [ItemFilterApi] when present.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/redstone.dart';
import '../../api/value_settings.dart';
import '../../core/block_entity.dart';
import '../link/frequency_stacks.dart';
import '../support/rs_runtime.dart';

/// Items that are not applied as a filter when held (`canShortInteract`).
const Set<String> _notFilters = {'create:wrench', 'create:mechanical_arm'};

/// `FilteringBehaviour` (`netId` 1).
class FilterBehaviour extends BlockEntityBehaviour implements ValueSettingsTarget, ObserverFilter {
  static const String behaviourId = 'Filtering';

  @override
  String get id => behaviourId;

  /// The filter item key, `null` for no filter.
  String? filter;

  /// `count`.
  int count = 64;

  /// `upTo`.
  bool upTo = true;

  /// `withCallback`.
  final void Function(String? filter)? callback;

  /// Whether the filter shows its amount (the observer and the switch do not).
  final bool showCount;

  FilterBehaviour({this.callback, this.showCount = false});

  @override
  bool get isEmpty => filter == null;

  /// `getMaxStackSize()`: 64 (the registry's per item maximum is not known to the plugin).
  int get maxStackSize => 64;

  /// `setFilter(stack)`; always accepted.
  bool setFilter(String? itemKey) {
    filter = itemKey == null || itemKey == 'minecraft:air' ? null : itemKey;
    if (!upTo && filter != null) count = count < maxStackSize ? count : maxStackSize;
    callback?.call(filter);
    owner.sendData();
    return true;
  }

  /// `test(ItemStack)`: no filter accepts everything. The slot keeps the item key only (Java keeps
  /// the whole stack), so a list or attribute filter matches itself here.
  @override
  bool testItem(String itemKey) {
    final f = filter;
    if (f == null) return true;
    final api = Rs.i.ctx.services.find<ItemFilterApi>();
    if (api != null) {
      return api.testItem(owner.worldId, FilterItemValue.key(f), itemKey);
    }
    return f == itemKey;
  }

  /// `test(FluidStack)`: a bucket filter matches its fluid.
  @override
  bool testFluid(String fluidKey) {
    final f = filter;
    if (f == null) return true;
    final api = Rs.i.ctx.services.find<ItemFilterApi>();
    if (api != null) {
      return api.testFluid(owner.worldId, FilterItemValue.key(f), fluidKey);
    }
    return bucketFluid(f) == fluidKey;
  }

  /// The fluid a bucket item holds (`minecraft:water_bucket` -> `minecraft:water`).
  static String? bucketFluid(String itemKey) {
    if (!itemKey.endsWith('_bucket')) return null;
    return itemKey.substring(0, itemKey.length - '_bucket'.length);
  }

  // -- Value settings (the amount row) -------------------------------------------------------

  @override
  int get netId => 1;

  @override
  bool get acceptsValueSettings => showCount && maxStackSize > 1;

  @override
  (int row, int value) get valueSettings => (upTo ? 0 : 1, count == 0 ? maxStackSize : count);

  @override
  void setValueSettings(Player? player, int row, int value, {required bool ctrlDown}) {
    if (valueSettings == (row, value)) return;
    count = value.clamp(1, maxStackSize);
    upTo = row == 0;
    owner.sendData();
  }

  /// `onShortInteract`: a right click with an item sets it as the filter.
  Future<void> onShortInteract(Player player, Hand hand) async {
    final held = player.getItemInHand(hand: hand);
    if (held == null) return;
    final key = await held.getRegistryKey();
    if (_notFilters.contains(key)) return;
    final empty = await held.getCount() <= 0;
    setFilter(empty ? null : key);
    owner.world?.playSound(
      sound: Sound.entityItemFrameAddItem,
      category: SoundCategory.blocks,
      pos: (owner.pos.x + 0.5, owner.pos.y + 0.5, owner.pos.z + 0.5),
      volume: 0.25,
      pitch: 0.1,
    );
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    final f = filter;
    final item = NbtCompound();
    if (f != null) {
      item.putString('id', f);
      item.putInt('count', 1);
    }
    tag.putCompound('Filter', item);
    tag.putInt('FilterAmount', count);
    tag.putBool('UpTo', upTo);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    final freq = frequencyFromNbt(tag.getCompound('Filter'));
    filter = freq.item;
    count = tag.getInt('FilterAmount') ?? 0;
    upTo = tag.getBool('UpTo') ?? false;
    // Migrate from the previous behaviour.
    if (count == 0) {
      upTo = true;
      count = maxStackSize;
    }
  }

  /// `destroy()`: nothing is dropped, only filter items would be, and they are not kept.
  @override
  void onRemoved() {}
}
