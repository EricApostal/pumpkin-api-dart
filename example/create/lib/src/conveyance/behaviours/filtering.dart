// `FilteringBehaviour` and `SidedFilteringBehaviour` of the conveyance blocks: one filter item
// slot (with an optional extraction amount), the value box that sets it, the matching of stacks
// against it, and the NBT Create's client reads.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/direction.dart' as d;
import '../../common/host_bridge.dart';
import '../../core/block_entity.dart';
import '../items/item_codec.dart';
import '../items/filter_match.dart';
import '../items/item_data.dart';
import '../runtime.dart';
import 'value_box.dart';

export '../items/filter_match.dart' show filterTest, isFilterItemKey;

/// `FilteringBehaviour`.
class FilteringBehaviour extends BlockEntityBehaviour implements ValueBox {
  static const String behaviourId = 'Filtering';

  @override
  String get id => behaviourId;

  @override
  final ValueSlot slot;

  ItemValue _filter = ItemValue.empty;
  int count = 64;
  bool upTo = true;

  bool Function() _isActive = _always;
  bool Function() _showCountPredicate = _never;
  bool Function(ItemValue stack) _predicate = _accept;
  void Function(ItemValue stack) _callback = _ignore;
  bool _showCount = false;
  String? customLabel;
  bool recipeFilter = false;
  bool fluidFilter = false;

  FilteringBehaviour(this.slot);

  static bool _always() => true;
  static bool _never() => false;
  static bool _accept(ItemValue _) => true;
  static void _ignore(ItemValue _) {}

  /// `withCallback`.
  FilteringBehaviour withCallback(void Function(ItemValue stack) cb) {
    _callback = cb;
    return this;
  }

  /// `withPredicate`.
  FilteringBehaviour withPredicate(bool Function(ItemValue stack) p) {
    _predicate = p;
    return this;
  }

  /// `onlyActiveWhen`.
  FilteringBehaviour onlyActiveWhen(bool Function() condition) {
    _isActive = condition;
    return this;
  }

  /// `showCountWhen`.
  FilteringBehaviour showCountWhen(bool Function() condition) {
    _showCountPredicate = condition;
    return this;
  }

  /// `showCount()`.
  FilteringBehaviour showCountAlways() {
    _showCount = true;
    _showCountPredicate = () => _showCount;
    return this;
  }

  // -- Filter ---------------------------------------------------------------------------------

  /// `getFilter()`.
  ItemValue get filter => _filter;

  ItemValue getFilter([d.Direction? side]) => _filter;

  /// `setFilter(stack)`: false when the predicate refuses the item.
  bool setFilter(ItemValue stack) {
    if (stack.isNotEmpty && !_predicate(stack)) return false;
    _filter = stack.isEmpty ? ItemValue.empty : stack;
    if (!upTo && stack.isNotEmpty) count = count < stack.maxStack ? count : stack.maxStack;
    _callback(_filter);
    owner.markDirty();
    owner.sendData();
    return true;
  }

  /// `setFilter(face, stack)`.
  bool setFilterOn(d.Direction face, ItemValue stack) => setFilter(stack);

  /// `getMaxStackSize()`.
  int get maxStackSize => _filter.isEmpty ? 64 : _filter.maxStack;

  /// `isCountVisible()`.
  bool get isCountVisible => _showCountPredicate() && maxStackSize > 1;

  /// `getAmount()`.
  int get amount => count;

  /// `anyAmount()`.
  bool get anyAmount => count == 0;

  @override
  bool get isActive => _isActive();

  /// `test(stack)`.
  bool test(ItemValue stack) => !isActive || filterTest(_filter, stack, worldId: owner.worldId);

  /// Whether no filter item is set.
  bool get isEmpty => _filter.isEmpty;

  // -- Value settings --------------------------------------------------------------------------

  @override
  int get netId => 1;

  @override
  bool get acceptsValueSettings => isCountVisible;

  @override
  (int, int) get valueSettings => (upTo ? 0 : 1, count == 0 ? maxStackSize : count);

  @override
  void setValueSettings(Player? player, int row, int value, {required bool ctrlDown}) {
    if (valueSettings == (row, value)) return;
    count = value.clamp(1, maxStackSize);
    upTo = row == 0;
    owner.markDirty();
    owner.sendData();
    _feedback();
  }

  void _feedback() {
    final w = owner.world;
    if (w == null) return;
    final pos = (owner.pos.x + .5, owner.pos.y + .5, owner.pos.z + .5);
    w.playSound(sound: Sound.entityItemFrameAddItem, category: SoundCategory.blocks, pos: pos, volume: 0.25, pitch: 2);
  }

  @override
  ValueBox? forSide(d.Direction side) => this;

  /// `canShortInteract(toApply)`.
  bool canShortInteract(ItemValue toApply) => !notFilterItems.contains(toApply.key);

  @override
  Future<void> onShortInteract(Player player, Hand hand, d.Direction side) async {
    final w = owner.world;
    if (w == null) return;
    final held = player.getItemInHand(hand: hand);
    final inHand = await ItemCodec.read(held);
    var toApply = inHand;
    if (toApply.isNotEmpty && !canShortInteract(toApply)) return;

    final current = getFilter(side);
    if (isFilterItemKey(current.key)) {
      var refund = true;
      if (player.isCreative) refund = !await _inventoryHas(player, current);
      if (refund) await ItemCodec.giveToPlayer(player, current);
    }
    if (isFilterItemKey(toApply.key)) toApply = toApply.withCount(1);
    if (!setFilterOn(side, toApply)) {
      player.actionBar('&cInvalid item for this filter');
      ConveyanceRuntime.i.playCreateSound(w, owner.pos.toPos(), 'deny');
      return;
    }
    if (!player.isCreative && isFilterItemKey(toApply.key) && held != null) {
      final n = inHand.count;
      final inv = player.getInventory();
      if (n <= 1) {
        await inv.setItemInHand(hand: hand, item: null);
      } else {
        await held.setCount(count: n - 1);
        await inv.setItemInHand(hand: hand, item: held);
      }
    }
    w.playSound(
      sound: Sound.entityItemFrameAddItem,
      category: SoundCategory.blocks,
      pos: (owner.pos.x + .5, owner.pos.y + .5, owner.pos.z + .5),
      volume: .25,
      pitch: .1,
    );
  }

  Future<bool> _inventoryHas(Player player, ItemValue item) async {
    final inv = player.getInventory().storage;
    for (var slot = 0; slot < 36; slot++) {
      final s = inv.getItem(slot: slot);
      if (s == null) continue;
      final v = await ItemCodec.read(s);
      if (v.sameItemSameComponents(item)) return true;
    }
    return false;
  }

  // -- Lifecycle and NBT ------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putCompound('Filter', ItemCodec.toTag(_filter, clientPacket: clientPacket));
    tag.putInt('FilterAmount', count);
    tag.putBool('UpTo', upTo);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    _filter = ItemCodec.fromAnyNbt(tag.getCompound('Filter'));
    count = tag.getInt('FilterAmount') ?? 0;
    upTo = tag.getBool('UpTo') ?? false;
    // Migrate from the previous behaviour.
    if (count == 0) {
      upTo = true;
      count = maxStackSize;
    }
  }

  /// `destroy()`: a filter item drops.
  @override
  void onRemoved() {
    final f = _filter;
    if (!isFilterItemKey(f.key)) return;
    final w = owner.world;
    if (w == null) return;
    ConveyanceRuntime.i.fire('Dropping the filter', () => ItemCodec.drop(w, blockCenter(owner.pos.toPos()), f));
  }
}

/// `SidedFilteringBehaviour`: one filter per face where [validDirections] says so.
class SidedFilteringBehaviour extends FilteringBehaviour {
  final bool Function(d.Direction side) validDirections;
  final Map<d.Direction, FilteringBehaviour> sidedFilters = {};

  SidedFilteringBehaviour(super.slot, this.validDirections) {
    updateFilterPresence();
  }

  /// `get(side)`.
  FilteringBehaviour? get(d.Direction side) => sidedFilters[side];

  /// `updateFilterPresence()`.
  void updateFilterPresence() {
    final valid = <d.Direction>{
      for (final side in d.Direction.values)
        if (validDirections(side)) side,
    };
    for (final side in d.Direction.values) {
      if (valid.contains(side)) {
        if (!sidedFilters.containsKey(side)) {
          final f = FilteringBehaviour(slot);
          if (_hasOwner) f.owner = owner;
          sidedFilters[side] = f;
        }
      } else if (sidedFilters.containsKey(side)) {
        removeFilter(side);
      }
    }
  }

  bool _hasOwner = false;

  @override
  set owner(CreateBlockEntity value) {
    super.owner = value;
    _hasOwner = true;
    for (final f in sidedFilters.values) {
      f.owner = value;
    }
  }

  @override
  CreateBlockEntity get owner => super.owner;

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putList('Filters', [
      for (final e in sidedFilters.entries)
        (NbtCompound()..putInt('Side', e.key.index)).also((c) => e.value.write(c, clientPacket: clientPacket)),
    ]);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    for (final e in tag.getList('Filters') ?? const <Object>[]) {
      if (e is! NbtCompound) continue;
      final face = d.Direction.from3DDataValue(e.getInt('Side') ?? 0);
      sidedFilters[face]?.read(e, clientPacket: clientPacket);
    }
    super.read(tag, clientPacket: clientPacket);
  }

  @override
  bool setFilterOn(d.Direction side, ItemValue stack) {
    final f = sidedFilters[side];
    if (f == null) return true;
    f.setFilter(stack);
    return true;
  }

  @override
  ItemValue getFilter([d.Direction? side]) {
    if (side == null) return super.getFilter();
    final f = sidedFilters[side];
    return f == null ? ItemValue.empty : f.filter;
  }

  /// `test(side, stack)`.
  bool testSide(d.Direction side, ItemValue stack) {
    final f = sidedFilters[side];
    return f == null || f.test(stack);
  }

  @override
  ValueBox? forSide(d.Direction side) => sidedFilters[side];

  /// `removeFilter(side)`.
  void removeFilter(d.Direction side) {
    final f = sidedFilters.remove(side);
    f?.onRemoved();
  }

  @override
  void onRemoved() {
    for (final f in sidedFilters.values) {
      f.onRemoved();
    }
    super.onRemoved();
  }
}

extension _Also<T> on T {
  T also(void Function(T value) block) {
    block(this);
    return this;
  }
}
