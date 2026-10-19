// `FilteringBehaviour`: a block entity's filter slot (and optionally an amount). The table cloth,
// the factory panel and the packager-adjacent blocks extend or configure it. OWNER: filter part.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/value_settings.dart';
import '../../core/block_entity.dart';
import '../host/nbt_util.dart';
import '../host/runtime.dart';
import '../model/stack.dart';
import 'filter_item_stack.dart';

/// Items that are not applied as a filter when held (`canShortInteract`).
const Set<String> _notFilters = {'create:wrench', 'create:mechanical_arm'};

class FilteringBehaviour extends BlockEntityBehaviour
    implements ValueSettingsTarget, ShortInteractTarget {
  static const String behaviourId = 'Filtering';

  @override
  String get id => behaviourId;

  /// The filter slot.
  FilterItemStack filter = FilterItemStack.empty;

  /// `count`.
  int count = 64;

  /// `upTo`.
  bool upTo = true;

  /// `withPredicate`: which stacks may be set.
  bool Function(LStack stack)? predicate;

  /// `withCallback`.
  void Function(LStack stack)? callback;

  /// `onlyActiveWhen`.
  bool Function()? activeWhen;

  /// `showCountWhen` / `showCount()`.
  bool Function()? showCountWhen;

  /// `forRecipes()` / `forFluids()`.
  bool recipeFilter = false;
  bool fluidFilter = false;

  FilteringBehaviour({
    this.predicate,
    this.callback,
    this.activeWhen,
    this.showCountWhen,
  });

  /// `getFilter()`.
  LStack get filterItem => filter.item;

  /// `isActive()`.
  bool get isActive => activeWhen?.call() ?? true;

  /// `getMaxStackSize()`.
  int get maxStackSize => filter.item.isEmpty ? 64 : filter.item.maxStack;

  /// `isCountVisible()`.
  bool get isCountVisible =>
      (showCountWhen?.call() ?? false) && maxStackSize > 1;

  /// `getAmount()`.
  int get amount => count;

  /// `anyAmount()`.
  bool get anyAmount => count == 0;

  /// `setFilter(stack)`: false if the predicate refuses the stack.
  bool setFilter(LStack stack) {
    if (stack.isNotEmpty && predicate != null && !predicate!(stack))
      return false;
    filter = FilterItemStack.of(stack, wire: Lg.loaded ? Lg.i.wire : null);
    if (!upTo && stack.isNotEmpty)
      count = count < stack.maxStack ? count : stack.maxStack;
    callback?.call(stack);
    owner.markDirty();
    owner.sendData();
    return true;
  }

  /// `test(ItemStack)`.
  bool test(LStack stack) => !isActive || filter.test(stack);

  /// `test(FluidStack)`.
  bool testFluid(String fluidKey) => !isActive || filter.testFluid(fluidKey);

  // -- ValueSettingsTarget ------------------------------------------------------------------

  @override
  int get netId => 1;

  @override
  bool get acceptsValueSettings => isCountVisible;

  @override
  (int row, int value) get valueSettings =>
      (upTo ? 0 : 1, count == 0 ? maxStackSize : count);

  @override
  void setValueSettings(
    Player? player,
    int row,
    int value, {
    required bool ctrlDown,
  }) {
    if (valueSettings == (row, value)) return;
    count = value.clamp(1, maxStackSize);
    upTo = row == 0;
    owner.markDirty();
    owner.sendData();
  }

  // -- ShortInteractTarget --------------------------------------------------------------------

  /// `canShortInteract(toApply)`.
  bool canShortInteract(String itemKey) => !_notFilters.contains(itemKey);

  @override
  void onShortInteract(Player player) {
    // The hand is not part of the target interface; the block's use handler calls
    // [interactWith] with the held stack instead.
  }

  /// `onShortInteract(player, hand, side, hit)` for the stack in hand [held]: sets it as the filter.
  /// Returns false when the stack was refused. Giving back / consuming filter items is done by the
  /// caller (it owns the player's inventory).
  bool interactWith(LStack held) {
    if (!canShortInteract(held.key)) return false;
    return setFilter(held.isEmpty ? LStack.empty : held.withCount(1));
  }

  // -- NBT ----------------------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putCompound('Filter', stackToNbt(filter.item, client: clientPacket));
    tag.putInt('FilterAmount', count);
    tag.putBool('UpTo', upTo);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    filter = FilterItemStack.of(
      stackFromNbt(tag.getCompound('Filter')),
      wire: Lg.loaded ? Lg.i.wire : null,
    );
    count = tag.getInt('FilterAmount') ?? 0;
    upTo = tag.getBool('UpTo') ?? false;
    // Migrate from the previous behaviour.
    if (count == 0) {
      upTo = true;
      count = maxStackSize;
    }
  }
}
