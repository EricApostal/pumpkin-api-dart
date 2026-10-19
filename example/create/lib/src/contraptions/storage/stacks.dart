// Item and fluid stacks as plain data (pure), the slot based handlers contraptions store them in,
// and the helpers that move items between handlers (`ItemHelper`).
import '../../core/nbt.dart';
import '../core/nbt_map.dart';

/// How many items of a kind fit in a stack. The host installs a resolver that asks the item
/// registry; the default is 64 with a few well known exceptions.
abstract final class ItemStackLimits {
  static int Function(String item) resolver = _defaultLimit;

  static int of(String item) => resolver(item);

  static int _defaultLimit(String item) {
    final p = item.contains(':') ? item.substring(item.indexOf(':') + 1) : item;
    if (p == 'ender_pearl' ||
        p == 'snowball' ||
        p == 'egg' ||
        p == 'bucket' ||
        p == 'honey_bottle' ||
        p == 'sign' ||
        p.endsWith('_sign')) {
      return 16;
    }
    if (p.endsWith('_pickaxe') ||
        p.endsWith('_axe') ||
        p.endsWith('_shovel') ||
        p.endsWith('_hoe') ||
        p.endsWith('_sword') ||
        p.endsWith('_helmet') ||
        p.endsWith('_chestplate') ||
        p.endsWith('_leggings') ||
        p.endsWith('_boots') ||
        p == 'shears' ||
        p == 'bow' ||
        p == 'crossbow' ||
        p == 'water_bucket' ||
        p == 'lava_bucket' ||
        p == 'milk_bucket' ||
        p.endsWith('_boat') ||
        p.endsWith('_minecart') ||
        p == 'minecart') {
      return 1;
    }
    return 64;
  }
}

/// An item stack: the item key, the count and the data components as saved (`ItemStack`).
final class StoredStack {
  final String item;
  final int count;

  /// The `components` compound of the saved stack, `null` for none.
  final NbtMap? components;

  const StoredStack(this.item, this.count, [this.components]);

  static const StoredStack empty = StoredStack('minecraft:air', 0);

  bool get isEmpty => count <= 0 || item == 'minecraft:air';

  bool get isNotEmpty => !isEmpty;

  int get maxStackSize => ItemStackLimits.of(item);

  StoredStack copyWithCount(int n) =>
      n <= 0 ? empty : StoredStack(item, n, components);

  StoredStack grow(int n) => copyWithCount(count + n);

  StoredStack shrink(int n) => copyWithCount(count - n);

  /// `ItemStack.isSameItemSameComponents`.
  bool sameItemSameComponents(StoredStack other) {
    if (item != other.item) return false;
    final a = components, b = other.components;
    if ((a == null || a.isEmpty) && (b == null || b.isEmpty)) return true;
    if (a == null || b == null) return false;
    return nbtEquals(a.toValue(), b.toValue());
  }

  /// The stack as saved by `ItemStack.CODEC`: `{id, count, components?}`.
  NbtMap toNbt() {
    final t = NbtMap()
      ..putString('id', item)
      ..putInt('count', count);
    final c = components;
    if (c != null && c.isNotEmpty) t.putCompound('components', c.copy());
    return t;
  }

  /// Reads a saved stack; an unreadable one is [empty].
  static StoredStack fromNbt(NbtMap? t) {
    if (t == null || !t.contains('id')) return empty;
    final count = t.contains('count')
        ? t.getInt('count', 1)
        : t.getInt('Count', 1);
    final c = t.getCompoundOrNull('components');
    return StoredStack(
      t.getString('id'),
      count,
      c == null || c.isEmpty ? null : c.copy(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StoredStack &&
          other.count == count &&
          sameItemSameComponents(other) ||
      (isEmpty && other is StoredStack && other.isEmpty);

  @override
  int get hashCode => isEmpty ? 0 : Object.hash(item, count);

  @override
  String toString() => isEmpty ? 'empty' : '$count x $item';
}

/// A fluid stack (`FluidStack`): the fluid key, an amount in millibuckets and the components.
final class StoredFluid {
  final String fluid;
  final int amount;
  final NbtMap? components;

  const StoredFluid(this.fluid, this.amount, [this.components]);

  static const StoredFluid empty = StoredFluid('minecraft:empty', 0);

  bool get isEmpty => amount <= 0 || fluid == 'minecraft:empty';

  StoredFluid copyWithAmount(int n) =>
      n <= 0 ? empty : StoredFluid(fluid, n, components);

  bool isFluidEqual(StoredFluid other) {
    if (fluid != other.fluid) return false;
    final a = components, b = other.components;
    if ((a == null || a.isEmpty) && (b == null || b.isEmpty)) return true;
    if (a == null || b == null) return false;
    return nbtEquals(a.toValue(), b.toValue());
  }

  NbtMap toNbt() {
    final t = NbtMap()
      ..putString('id', fluid)
      ..putInt('amount', amount);
    final c = components;
    if (c != null && c.isNotEmpty) t.putCompound('components', c.copy());
    return t;
  }

  static StoredFluid fromNbt(NbtMap? t) {
    if (t == null || !t.contains('id')) return empty;
    final c = t.getCompoundOrNull('components');
    return StoredFluid(
      t.getString('id'),
      t.getInt('amount'),
      c == null || c.isEmpty ? null : c.copy(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StoredFluid &&
      ((isEmpty && other.isEmpty) ||
          (other.amount == amount && isFluidEqual(other)));

  @override
  int get hashCode => isEmpty ? 0 : Object.hash(fluid, amount);

  @override
  String toString() => isEmpty ? 'empty' : '$amount mB $fluid';
}

/// A slot based item container (`IItemHandlerModifiable`).
abstract interface class ItemSlots {
  int get slots;

  StoredStack stackInSlot(int slot);

  /// Puts [stack] into [slot] directly (no insertion rules).
  void setStackInSlot(int slot, StoredStack stack);

  /// Tries to insert [stack] into [slot]; returns what did not fit.
  StoredStack insertItem(int slot, StoredStack stack, {bool simulate = false});

  /// Takes up to [amount] items out of [slot].
  StoredStack extractItem(int slot, int amount, {bool simulate = false});

  int slotLimit(int slot);

  bool isItemValid(int slot, StoredStack stack);
}

/// A plain list of slots (`ItemStackHandler` / `CreateItemStackHandler`).
class ItemStackHandler implements ItemSlots {
  final List<StoredStack> stacks;

  /// Called after a slot changed.
  void Function(int slot)? onChange;

  ItemStackHandler(int size)
    : stacks = List<StoredStack>.filled(
        size,
        StoredStack.empty,
        growable: true,
      );

  ItemStackHandler.of(List<StoredStack> items)
    : stacks = List<StoredStack>.of(items, growable: true);

  @override
  int get slots => stacks.length;

  @override
  StoredStack stackInSlot(int slot) =>
      slot < 0 || slot >= stacks.length ? StoredStack.empty : stacks[slot];

  @override
  void setStackInSlot(int slot, StoredStack stack) {
    if (slot < 0 || slot >= stacks.length) return;
    stacks[slot] = stack.isEmpty ? StoredStack.empty : stack;
    onChange?.call(slot);
  }

  @override
  int slotLimit(int slot) => 64;

  @override
  bool isItemValid(int slot, StoredStack stack) => true;

  @override
  StoredStack insertItem(int slot, StoredStack stack, {bool simulate = false}) {
    if (stack.isEmpty) return StoredStack.empty;
    if (slot < 0 || slot >= stacks.length || !isItemValid(slot, stack))
      return stack;
    final existing = stacks[slot];
    final limit = stack.maxStackSize < slotLimit(slot)
        ? stack.maxStackSize
        : slotLimit(slot);
    if (existing.isNotEmpty) {
      if (!stack.sameItemSameComponents(existing)) return stack;
    }
    final space = limit - existing.count;
    if (space <= 0) return stack;
    final moved = stack.count < space ? stack.count : space;
    if (!simulate) {
      stacks[slot] = existing.isEmpty
          ? stack.copyWithCount(moved)
          : existing.grow(moved);
      onChange?.call(slot);
    }
    return moved >= stack.count ? StoredStack.empty : stack.shrink(moved);
  }

  @override
  StoredStack extractItem(int slot, int amount, {bool simulate = false}) {
    if (amount <= 0 || slot < 0 || slot >= stacks.length)
      return StoredStack.empty;
    final existing = stacks[slot];
    if (existing.isEmpty) return StoredStack.empty;
    final toExtract = amount < existing.maxStackSize
        ? amount
        : existing.maxStackSize;
    if (existing.count <= toExtract) {
      if (!simulate) {
        stacks[slot] = StoredStack.empty;
        onChange?.call(slot);
      }
      return existing;
    }
    if (!simulate) {
      stacks[slot] = existing.shrink(toExtract);
      onChange?.call(slot);
    }
    return existing.copyWithCount(toExtract);
  }

  /// `ItemStackHandler.serializeNBT`: `{Size, Items: [{Slot, id, count, components?}]}`.
  NbtMap serialize() {
    final items = <NbtValue>[];
    for (var i = 0; i < stacks.length; i++) {
      if (stacks[i].isEmpty) continue;
      final t = stacks[i].toNbt()..putInt('Slot', i);
      items.add(t.toValue());
    }
    return NbtMap()
      ..putInt('Size', stacks.length)
      ..putList('Items', items);
  }

  /// `ItemSlots.CODEC` (`CreateCodecs.ITEM_STACK_HANDLER`): `{items: {"<slot>": stack}, size}`.
  /// Only non-empty slots are written.
  NbtMap serializeItemSlots() {
    final items = NbtMap();
    for (var i = 0; i < stacks.length; i++) {
      if (stacks[i].isEmpty) continue;
      items.putCompound('$i', stacks[i].toNbt());
    }
    return NbtMap()
      ..putCompound('items', items)
      ..putInt('size', stacks.length);
  }

  /// Reads a handler from an `ItemSlots.CODEC` compound (`{items, size}`).
  static ItemStackHandler fromItemSlotsNbt(NbtMap nbt) {
    final size = nbt.getInt('size');
    final h = ItemStackHandler(size < 0 ? 0 : size);
    final items = nbt.getCompound('items');
    for (final key in items.keys) {
      final slot = int.tryParse(key);
      if (slot == null || slot < 0 || slot >= h.stacks.length) continue;
      final stack = StoredStack.fromNbt(items.getCompoundOrNull(key));
      if (stack.isNotEmpty) h.stacks[slot] = stack;
    }
    return h;
  }

  /// `ItemStackHandler.deserializeNBT`.
  void deserialize(NbtMap nbt) {
    final size = nbt.contains('Size') ? nbt.getInt('Size') : stacks.length;
    stacks
      ..clear()
      ..addAll(List<StoredStack>.filled(size, StoredStack.empty));
    for (final v in nbt.getList('Items')) {
      final t = NbtMap.of(v);
      final slot = t.getInt('Slot', -1);
      if (slot >= 0 && slot < stacks.length)
        stacks[slot] = StoredStack.fromNbt(t);
    }
  }

  /// A handler read from a saved `{Size, Items}` compound.
  static ItemStackHandler fromNbt(NbtMap nbt) {
    final h = ItemStackHandler(nbt.getInt('Size'));
    h.deserialize(nbt);
    return h;
  }

  /// A deep copy.
  ItemStackHandler copy() => ItemStackHandler.of(stacks);
}

/// Several handlers seen as one (`CombinedInvWrapper`).
class CombinedItemSlots implements ItemSlots {
  final List<ItemSlots> parts;

  CombinedItemSlots(this.parts);

  (ItemSlots, int)? _locate(int slot) {
    var s = slot;
    for (final p in parts) {
      if (s < p.slots) return (p, s);
      s -= p.slots;
    }
    return null;
  }

  @override
  int get slots => parts.fold(0, (n, p) => n + p.slots);

  @override
  StoredStack stackInSlot(int slot) {
    final l = _locate(slot);
    return l == null ? StoredStack.empty : l.$1.stackInSlot(l.$2);
  }

  @override
  void setStackInSlot(int slot, StoredStack stack) {
    final l = _locate(slot);
    if (l != null) l.$1.setStackInSlot(l.$2, stack);
  }

  @override
  StoredStack insertItem(int slot, StoredStack stack, {bool simulate = false}) {
    final l = _locate(slot);
    return l == null ? stack : l.$1.insertItem(l.$2, stack, simulate: simulate);
  }

  @override
  StoredStack extractItem(int slot, int amount, {bool simulate = false}) {
    final l = _locate(slot);
    return l == null
        ? StoredStack.empty
        : l.$1.extractItem(l.$2, amount, simulate: simulate);
  }

  @override
  int slotLimit(int slot) {
    final l = _locate(slot);
    return l == null ? 0 : l.$1.slotLimit(l.$2);
  }

  @override
  bool isItemValid(int slot, StoredStack stack) {
    final l = _locate(slot);
    return l != null && l.$1.isItemValid(l.$2, stack);
  }
}

/// `ItemHelper` for [ItemSlots].
abstract final class ItemSlotsHelper {
  /// `ItemHandlerHelper.insertItem`: first into slots that already hold the item, then empty ones.
  /// Returns the remainder.
  static StoredStack insert(
    ItemSlots to,
    StoredStack stack, {
    bool simulate = false,
  }) {
    if (stack.isEmpty) return StoredStack.empty;
    var remaining = stack;
    for (var pass = 0; pass < 2 && remaining.isNotEmpty; pass++) {
      for (var i = 0; i < to.slots && remaining.isNotEmpty; i++) {
        final held = to.stackInSlot(i);
        if (pass == 0 &&
            (held.isEmpty || !held.sameItemSameComponents(remaining)))
          continue;
        if (pass == 1 && held.isNotEmpty) continue;
        remaining = to.insertItem(i, remaining, simulate: simulate);
      }
    }
    return remaining;
  }

  /// `ItemHelper.extract(inv, test, amount, simulate)`: takes up to [amount] items accepted by
  /// [test], from several slots if needed (all of one kind).
  static StoredStack extract(
    ItemSlots from,
    bool Function(StoredStack) test,
    int amount, {
    bool simulate = false,
  }) {
    var extracted = StoredStack.empty;
    for (
      var i = 0;
      i < from.slots && (extracted.isEmpty || extracted.count < amount);
      i++
    ) {
      final held = from.stackInSlot(i);
      if (held.isEmpty || !test(held)) continue;
      if (extracted.isNotEmpty && !extracted.sameItemSameComponents(held))
        continue;
      final want = amount - extracted.count;
      final got = from.extractItem(i, want, simulate: simulate);
      if (got.isEmpty) continue;
      extracted = extracted.isEmpty ? got : extracted.grow(got.count);
    }
    return extracted;
  }

  /// `ItemHelper.copyContents(from, to)`: slot by slot.
  static void copyContents(ItemSlots from, ItemSlots to) {
    for (var i = 0; i < to.slots; i++) {
      to.setStackInSlot(
        i,
        i < from.slots ? from.stackInSlot(i) : StoredStack.empty,
      );
    }
  }

  /// The number of items in all slots.
  static int count(ItemSlots from) {
    var n = 0;
    for (var i = 0; i < from.slots; i++) {
      n += from.stackInSlot(i).count;
    }
    return n;
  }
}

/// A tank based fluid container (`IFluidHandler`).
abstract interface class FluidTanks {
  int get tanks;

  StoredFluid fluidInTank(int tank);

  int tankCapacity(int tank);

  bool isFluidValid(int tank, StoredFluid fluid);

  /// Fills [fluid] in; returns the amount that went in.
  int fill(StoredFluid fluid, {bool simulate = false});

  /// Drains up to [maxAmount] of the first fluid.
  StoredFluid drain(int maxAmount, {bool simulate = false});

  /// Drains up to the amount of [fluid] if it is contained.
  StoredFluid drainFluid(StoredFluid fluid, {bool simulate = false});
}

/// A single tank (`FluidTank` / `CreateFluidTank`).
class SingleFluidTank implements FluidTanks {
  int capacity;
  StoredFluid fluid;
  void Function()? onChange;

  SingleFluidTank(this.capacity, [this.fluid = StoredFluid.empty]);

  @override
  int get tanks => 1;

  @override
  StoredFluid fluidInTank(int tank) => fluid;

  @override
  int tankCapacity(int tank) => capacity;

  @override
  bool isFluidValid(int tank, StoredFluid f) => true;

  @override
  int fill(StoredFluid resource, {bool simulate = false}) {
    if (resource.isEmpty) return 0;
    if (fluid.isEmpty) {
      final filled = resource.amount < capacity ? resource.amount : capacity;
      if (!simulate) {
        fluid = resource.copyWithAmount(filled);
        onChange?.call();
      }
      return filled;
    }
    if (!fluid.isFluidEqual(resource)) return 0;
    final space = capacity - fluid.amount;
    final filled = resource.amount < space ? resource.amount : space;
    if (filled <= 0) return 0;
    if (!simulate) {
      fluid = fluid.copyWithAmount(fluid.amount + filled);
      onChange?.call();
    }
    return filled;
  }

  @override
  StoredFluid drain(int maxAmount, {bool simulate = false}) {
    if (fluid.isEmpty || maxAmount <= 0) return StoredFluid.empty;
    final drained = maxAmount < fluid.amount ? maxAmount : fluid.amount;
    final out = fluid.copyWithAmount(drained);
    if (!simulate) {
      fluid = fluid.copyWithAmount(fluid.amount - drained);
      onChange?.call();
    }
    return out;
  }

  @override
  StoredFluid drainFluid(StoredFluid resource, {bool simulate = false}) {
    if (resource.isEmpty || !resource.isFluidEqual(fluid))
      return StoredFluid.empty;
    return drain(resource.amount, simulate: simulate);
  }
}

/// Several tanks as one (`CombinedTankWrapper`).
class CombinedFluidTanks implements FluidTanks {
  final List<FluidTanks> parts;

  CombinedFluidTanks(this.parts);

  @override
  int get tanks => parts.fold(0, (n, p) => n + p.tanks);

  (FluidTanks, int)? _locate(int tank) {
    var t = tank;
    for (final p in parts) {
      if (t < p.tanks) return (p, t);
      t -= p.tanks;
    }
    return null;
  }

  @override
  StoredFluid fluidInTank(int tank) {
    final l = _locate(tank);
    return l == null ? StoredFluid.empty : l.$1.fluidInTank(l.$2);
  }

  @override
  int tankCapacity(int tank) {
    final l = _locate(tank);
    return l == null ? 0 : l.$1.tankCapacity(l.$2);
  }

  @override
  bool isFluidValid(int tank, StoredFluid fluid) {
    final l = _locate(tank);
    return l != null && l.$1.isFluidValid(l.$2, fluid);
  }

  @override
  int fill(StoredFluid fluid, {bool simulate = false}) {
    var remaining = fluid;
    var total = 0;
    for (final p in parts) {
      if (remaining.isEmpty) break;
      final f = p.fill(remaining, simulate: simulate);
      total += f;
      remaining = remaining.copyWithAmount(remaining.amount - f);
    }
    return total;
  }

  @override
  StoredFluid drain(int maxAmount, {bool simulate = false}) {
    var out = StoredFluid.empty;
    for (final p in parts) {
      final want = maxAmount - (out.isEmpty ? 0 : out.amount);
      if (want <= 0) break;
      final got = out.isEmpty
          ? p.drain(want, simulate: simulate)
          : p.drainFluid(out.copyWithAmount(want), simulate: simulate);
      if (got.isEmpty) continue;
      out = out.isEmpty ? got : out.copyWithAmount(out.amount + got.amount);
    }
    return out;
  }

  @override
  StoredFluid drainFluid(StoredFluid fluid, {bool simulate = false}) {
    var out = StoredFluid.empty;
    for (final p in parts) {
      final want = fluid.amount - (out.isEmpty ? 0 : out.amount);
      if (want <= 0) break;
      final got = p.drainFluid(fluid.copyWithAmount(want), simulate: simulate);
      if (got.isEmpty) continue;
      out = out.isEmpty ? got : out.copyWithAmount(out.amount + got.amount);
    }
    return out;
  }
}
