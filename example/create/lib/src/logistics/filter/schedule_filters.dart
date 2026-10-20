// `FilterItemStack.test` for the schedule's threshold conditions.
//
// Java: `ItemThresholdCondition.test` / `FluidThresholdCondition.test` call
// `FilterItemStack.test(level, stack)` (`FilterItemStack.java:76-100`), which resolves list and
// attribute filter items through `FilterItem.testDirect`. The port's `ScheduleLevel` asks for the
// same through [ScheduleFilters]; the matching itself is the logistics module's [ItemFilterStack],
// reached with [ItemFilterApi] so no filter logic is duplicated here.
//
// The schedule keeps its filter item as `ItemStack.CODEC` NBT (`ItemThresholdCondition
// .writeAdditional` -> `FilterItemStack.serializeNBT` -> `TransferUtil.saveItem`), so the
// components arrive in their *codec* form. [ScheduleFiltersImpl] turns the components a filter
// uses into the network bytes [ItemFilterApi] expects:
//  * `create:filter_items` (`ItemContainerContents.CODEC` -> its stream codec),
//  * `create:filter_items_respect_nbt` / `_blacklist` (`Codec.BOOL` -> one byte),
//  * `create:attribute_filter_whitelist_mode` (enum name -> the enum ordinal).
// `create:attribute_filter_matched_attributes` is a registry dispatch of `ItemAttributeEntry`,
// whose type registry the plugin does not carry (see `FilterComponents.privateAttributes`), so an
// attribute filter's entries cannot be read from a client-written tag; its whitelist mode alone
// is passed on.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../api/filter_api.dart' show FilterItemValue, ItemFilterApi;
import '../../common/stack_tag.dart' show JavaStackTag;
import '../../core/nbt.dart';
import '../../trains/schedule/schedule_level.dart'
    show CargoFluid, CargoItem, PlainScheduleFilters, ScheduleFilters;
import '../../trains/util/ctag.dart';
import '../model/stack.dart';
import '../model/stack_wire.dart';
import 'filter_api.dart' show ItemFilterApiAdapter;
import 'filter_item_stack.dart' show FilterComponents;

/// `FilterItemStack.test` behind [ScheduleFilters].
final class ScheduleFiltersImpl implements ScheduleFilters {
  const ScheduleFiltersImpl(this._api);

  /// The `ItemFilterApi` of this module; `null` when it is not installed.
  final ItemFilterApi? _api;

  @override
  bool testItem(CTag filter, CargoItem stack) {
    if (filter.isEmpty) return true;
    final api = _api;
    if (api == null) return const PlainScheduleFilters().testItem(filter, stack);
    return api.testItem('', valueOf(filter), stack.id);
  }

  @override
  bool testFluid(CTag filter, CargoFluid stack) {
    if (filter.isEmpty) return true;
    if (stack.isEmpty) return false;
    final api = _api;
    if (api == null) return const PlainScheduleFilters().testFluid(filter, stack);
    return api.testFluid('', valueOf(filter), stack.id);
  }

  /// The filter stack of a schedule condition as [ItemFilterApi] reads it.
  static FilterItemValue valueOf(CTag stack) {
    final count = stack.getInt('count');
    return FilterItemValue(
      stack.getString('id'),
      count: count <= 0 ? 1 : count,
      components: _components(stack),
    );
  }

  // -- `ItemStack.CODEC` -> the network component bytes ------------------------------------------

  /// The components of [stack] as `(name, network bytes)`.
  static List<(String, List<int>)> _components(CTag stack) {
    // A tag the plugin wrote itself keeps the bytes in `Comps` (`JavaStackTag`).
    final own = <(String, List<int>)>[];
    for (final e in stack.getCompoundList(JavaStackTag.compsKey)) {
      final name = e.getString('N');
      if (name.isEmpty) continue;
      own.add((name, e.getByteArray('V')));
    }
    if (own.isNotEmpty) return own;

    final components = stack.getCompoundOrNull(JavaStackTag.componentsKey);
    if (components == null) return const [];
    final out = <(String, List<int>)>[];
    for (final entry in components.entries.entries) {
      final bytes = _wireOf(entry.key, entry.value);
      if (bytes != null) out.add((entry.key, bytes));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  /// The network encoding of the codec-form component [value], `null` when it cannot be read.
  static List<int>? _wireOf(String name, NbtValue value) {
    switch (name) {
      case FilterComponents.respectNbt:
      case FilterComponents.blacklist:
        if (value.kind != NbtKind.byte) return null;
        return [(value.value as int) == 0 ? 0 : 1];
      case FilterComponents.whitelistMode:
        if (value.kind != NbtKind.string) return null;
        final ordinal = _whitelistModes.indexOf(value.value as String);
        return ordinal < 0 ? null : [ordinal];
      case FilterComponents.filterItems:
        return _contentsWire(value);
      default:
        return null;
    }
  }

  /// The serialised names of `AttributeFilterWhitelistMode`, in ordinal order
  /// (`Lang.asId(name())` of `WHITELIST_DISJ`, `WHITELIST_CONJ`, `BLACKLIST`).
  static const List<String> _whitelistModes = [
    'whitelist_disj',
    'whitelist_conj',
    'blacklist',
  ];

  /// `ItemContainerContents.CODEC` (`{items: [{slot, item}]}`) as its stream codec bytes, the form
  /// the logistics module reads (`StackWire.readContents`).
  static List<int>? _contentsWire(NbtValue value) {
    final wire = ItemFilterApiAdapter.wire();
    if (wire == null || value.kind != NbtKind.compound) return null;
    final items = value.asCompound['items'];
    if (items == null || items.kind != NbtKind.list) return const [];
    final slots = <int, LStack>{};
    for (final entry in items.value as List<NbtValue>) {
      if (entry.kind != NbtKind.compound) continue;
      final slot = entry.asCompound['slot'];
      final item = entry.asCompound['item'];
      if (slot == null || item == null || item.kind != NbtKind.compound) continue;
      slots[slot.value as int] = _stackOf(item, wire);
    }
    if (slots.isEmpty) return const [];
    final size = slots.keys.reduce((a, b) => a > b ? a : b) + 1;
    final ordered = [
      for (var i = 0; i < size; i++) slots[i] ?? LStack.empty,
    ];
    return PacketBuffer.encode((w) => wire.writeContents(w, ordered));
  }

  /// An `ItemStack.CODEC` compound as the [LStack] the wire codec writes.
  static LStack _stackOf(NbtValue item, StackWire wire) {
    final map = item.asCompound;
    final id = map['id'];
    final count = map['count'];
    if (id == null || id.kind != NbtKind.string) return LStack.empty;
    final key = id.value as String;
    final n = count == null ? 1 : count.value as int;
    if (n <= 0) return LStack.empty;
    var stack = LStack(
      key,
      n,
      maxStack: wire.info.maxStackOf(key),
      damageable: wire.info.damageableOf(key),
    );
    final components = map[JavaStackTag.componentsKey];
    if (components != null && components.kind == NbtKind.compound) {
      for (final entry in components.asCompound.entries) {
        final bytes = _wireOf(entry.key, entry.value);
        if (bytes != null) stack = stack.withComp(entry.key, bytes);
      }
    }
    return stack;
  }
}