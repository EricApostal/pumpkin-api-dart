// Item and fluid storage for the processing machines (pure): the plugin-side equivalent of
// NeoForge's `IItemHandler` / `IFluidHandler` and Create's `SmartInventory` /
// `SmartFluidTank`. The block entities of the machines (basin, deployer, crafter, millstone,
// ...) keep their contents in these; `host/inventory_mirror.dart` shows them to hoppers.
import 'stack.dart';

/// `IItemHandler`: slots that can be inserted into and extracted from.
abstract interface class ItemStorage {
  int get slots;

  /// `getStackInSlot` (do not mutate; stacks are immutable values).
  PStack stackIn(int slot);

  /// `insertItem`: returns the remainder ([PStack.empty] when everything went in).
  PStack insert(int slot, PStack stack, {bool simulate = false});

  /// `extractItem`: the extracted stack.
  PStack extract(int slot, int amount, {bool simulate = false});

  /// `getSlotLimit`.
  int slotLimit(int slot);

  /// `isItemValid`.
  bool isItemValid(int slot, PStack stack);
}

/// Create's `SmartInventory` (an `ItemStackHandler` with insertion / extraction switches
/// and a change callback).
class SmartInventory implements ItemStorage {
  final List<PStack> _stacks;
  int stackSize;

  /// `allowInsertion` / `allowExtraction`.
  bool insertionAllowed = true;
  bool extractionAllowed = true;

  /// Called after the contents changed (`onContentsChanged`).
  void Function(int slot)? onChanged;

  /// Extra validity rule (`whenContentsChanged` / `forbidInsertion` helpers in Java).
  bool Function(int slot, PStack stack)? validator;

  SmartInventory(int size, {this.stackSize = 64, this.onChanged}) : _stacks = List.filled(size, PStack.empty);

  @override
  int get slots => _stacks.length;

  @override
  PStack stackIn(int slot) => _stacks[slot];

  /// `setStackInSlot`.
  void setStack(int slot, PStack stack) {
    _stacks[slot] = stack.isEmpty ? PStack.empty : stack;
    onChanged?.call(slot);
  }

  @override
  int slotLimit(int slot) => stackSize;

  @override
  bool isItemValid(int slot, PStack stack) => validator?.call(slot, stack) ?? true;

  @override
  PStack insert(int slot, PStack stack, {bool simulate = false}) {
    if (stack.isEmpty) return PStack.empty;
    if (!insertionAllowed || !isItemValid(slot, stack)) return stack;
    final existing = _stacks[slot];
    var limit = slotLimit(slot);
    if (limit > stack.maxStack) limit = stack.maxStack;
    if (existing.isNotEmpty) {
      if (!stack.sameItemSameComponents(existing)) return stack;
      limit -= existing.count;
    }
    if (limit <= 0) return stack;
    final reachedLimit = stack.count > limit;
    if (!simulate) {
      _stacks[slot] = existing.isEmpty
          ? (reachedLimit ? stack.withCount(limit) : stack)
          : existing.withCount(existing.count + (reachedLimit ? limit : stack.count));
      onChanged?.call(slot);
    }
    return reachedLimit ? stack.withCount(stack.count - limit) : PStack.empty;
  }

  @override
  PStack extract(int slot, int amount, {bool simulate = false}) {
    if (amount == 0 || !extractionAllowed) return PStack.empty;
    final existing = _stacks[slot];
    if (existing.isEmpty) return PStack.empty;
    final toExtract = amount < existing.maxStack ? amount : existing.maxStack;
    if (existing.count <= toExtract) {
      if (!simulate) {
        _stacks[slot] = PStack.empty;
        onChanged?.call(slot);
      }
      return existing;
    }
    if (!simulate) {
      _stacks[slot] = existing.withCount(existing.count - toExtract);
      onChanged?.call(slot);
    }
    return existing.withCount(toExtract);
  }

  /// All stacks, in slot order (a copy).
  List<PStack> get contents => List.of(_stacks);

  /// Replaces the contents (extra slots are dropped, missing ones emptied) without callbacks.
  void load(Iterable<PStack> stacks) {
    final list = stacks.toList();
    for (var i = 0; i < _stacks.length; i++) {
      _stacks[i] = i < list.length && list[i].isNotEmpty ? list[i] : PStack.empty;
    }
  }

  bool get isEmpty => _stacks.every((s) => s.isEmpty);

  void clear() {
    for (var i = 0; i < _stacks.length; i++) {
      _stacks[i] = PStack.empty;
    }
  }
}

/// `CombinedInvWrapper`: several storages as one.
class CombinedStorage implements ItemStorage {
  final List<ItemStorage> parts;

  CombinedStorage(this.parts);

  @override
  int get slots => parts.fold(0, (n, p) => n + p.slots);

  (ItemStorage, int) _locate(int slot) {
    var s = slot;
    for (final p in parts) {
      if (s < p.slots) return (p, s);
      s -= p.slots;
    }
    throw RangeError.index(slot, this, 'slot');
  }

  @override
  PStack stackIn(int slot) {
    final (p, s) = _locate(slot);
    return p.stackIn(s);
  }

  @override
  PStack insert(int slot, PStack stack, {bool simulate = false}) {
    final (p, s) = _locate(slot);
    return p.insert(s, stack, simulate: simulate);
  }

  @override
  PStack extract(int slot, int amount, {bool simulate = false}) {
    final (p, s) = _locate(slot);
    return p.extract(s, amount, simulate: simulate);
  }

  @override
  int slotLimit(int slot) {
    final (p, s) = _locate(slot);
    return p.slotLimit(s);
  }

  @override
  bool isItemValid(int slot, PStack stack) {
    final (p, s) = _locate(slot);
    return p.isItemValid(s, stack);
  }
}

/// A view of a storage restricted to one direction (`ItemHandlerWrapper`s that only allow
/// insertion or only extraction, like the basin's input / output inventories seen from outside).
class RestrictedStorage implements ItemStorage {
  final ItemStorage inner;
  final bool allowInsert;
  final bool allowExtract;

  RestrictedStorage(this.inner, {this.allowInsert = true, this.allowExtract = true});

  @override
  int get slots => inner.slots;
  @override
  PStack stackIn(int slot) => inner.stackIn(slot);
  @override
  int slotLimit(int slot) => inner.slotLimit(slot);
  @override
  bool isItemValid(int slot, PStack stack) => allowInsert && inner.isItemValid(slot, stack);
  @override
  PStack insert(int slot, PStack stack, {bool simulate = false}) =>
      allowInsert ? inner.insert(slot, stack, simulate: simulate) : stack;
  @override
  PStack extract(int slot, int amount, {bool simulate = false}) =>
      allowExtract ? inner.extract(slot, amount, simulate: simulate) : PStack.empty;
}

/// `ItemHandlerHelper` / `ItemHelper` for [ItemStorage].
abstract final class ItemStorages {
  /// `ItemHandlerHelper.insertItem`: first fills stacks that hold the same item, then empty slots.
  /// Returns the remainder.
  static PStack insertStacked(ItemStorage s, PStack stack, {bool simulate = false}) {
    if (stack.isEmpty) return PStack.empty;
    var rest = stack;
    for (var i = 0; i < s.slots && rest.isNotEmpty; i++) {
      final existing = s.stackIn(i);
      if (existing.isNotEmpty && existing.sameItemSameComponents(rest)) {
        rest = s.insert(i, rest, simulate: simulate);
      }
    }
    for (var i = 0; i < s.slots && rest.isNotEmpty; i++) {
      if (s.stackIn(i).isEmpty) rest = s.insert(i, rest, simulate: simulate);
    }
    return rest;
  }

  /// `ItemHandlerHelper.insertItem` (slot by slot in order, no preference).
  static PStack insertInOrder(ItemStorage s, PStack stack, {bool simulate = false}) {
    var rest = stack;
    for (var i = 0; i < s.slots && rest.isNotEmpty; i++) {
      rest = s.insert(i, rest, simulate: simulate);
    }
    return rest;
  }

  /// Whether all of [stack] would fit.
  static bool canInsertAll(ItemStorage s, PStack stack) => insertStacked(s, stack, simulate: true).isEmpty;

  /// `ItemHelper.extract(inv, predicate, amount, simulate)`: takes up to [amount] items that
  /// match [test] (first matching slots first) and returns them merged into one stack.
  static PStack extractMatching(
    ItemStorage s,
    bool Function(PStack) test,
    int amount, {
    bool simulate = false,
    bool exactAmount = false,
  }) {
    var extracted = PStack.empty;
    for (var i = 0; i < s.slots; i++) {
      final stack = s.stackIn(i);
      if (stack.isEmpty || !test(stack)) continue;
      if (extracted.isNotEmpty && !extracted.sameItemSameComponents(stack)) continue;
      final want = amount - extracted.count;
      if (want <= 0) break;
      final taken = s.extract(i, want, simulate: true);
      if (taken.isEmpty) continue;
      if (!simulate) s.extract(i, taken.count);
      extracted = extracted.isEmpty ? taken : extracted.withCount(extracted.count + taken.count);
    }
    if (exactAmount && extracted.count != amount) return PStack.empty;
    return extracted;
  }

  /// The first non-empty stack's extraction, whatever it is.
  static PStack extractAny(ItemStorage s, int amount, {bool simulate = false}) =>
      extractMatching(s, (_) => true, amount, simulate: simulate);

  /// Total count of items matching [test].
  static int count(ItemStorage s, bool Function(PStack) test) {
    var n = 0;
    for (var i = 0; i < s.slots; i++) {
      final st = s.stackIn(i);
      if (st.isNotEmpty && test(st)) n += st.count;
    }
    return n;
  }

  static bool isEmpty(ItemStorage s) {
    for (var i = 0; i < s.slots; i++) {
      if (s.stackIn(i).isNotEmpty) return false;
    }
    return true;
  }

  /// Whether every slot is full (comparator `ItemHelper.calcRedstoneFromInventory`-like input).
  static double fillFraction(ItemStorage s) {
    if (s.slots == 0) return 0;
    var total = 0.0;
    for (var i = 0; i < s.slots; i++) {
      final st = s.stackIn(i);
      if (st.isEmpty) continue;
      final limit = s.slotLimit(i) < st.maxStack ? s.slotLimit(i) : st.maxStack;
      total += st.count / limit;
    }
    return total / s.slots;
  }

  /// `ItemHelper.calcRedstoneFromInventory`.
  static int redstoneFromInventory(ItemStorage s) {
    if (s.slots == 0) return 0;
    var empty = true;
    for (var i = 0; i < s.slots; i++) {
      if (s.stackIn(i).isNotEmpty) {
        empty = false;
        break;
      }
    }
    if (empty) return 0;
    return (1 + fillFraction(s) * 14).floor();
  }
}

// -- Fluids ---------------------------------------------------------------------------------

/// `IFluidHandler`.
abstract interface class FluidStorage {
  int get tanks;
  PFluid fluidIn(int tank);
  int tankCapacity(int tank);
  bool isFluidValid(int tank, PFluid fluid);

  /// `fill`: the amount that was (or would be) accepted.
  int fill(PFluid fluid, {bool simulate = false});

  /// `drain(FluidStack)`: drains the given fluid type.
  PFluid drainFluid(PFluid fluid, {bool simulate = false});

  /// `drain(int)`: drains any fluid.
  PFluid drainAny(int maxAmount, {bool simulate = false});
}

/// Create's `SmartFluidTank` / `FluidTank`: one tank.
class SmartFluidTank implements FluidStorage {
  int capacity;
  PFluid fluid = PFluid.empty;
  bool Function(PFluid fluid)? validator;
  void Function()? onChanged;
  bool fillAllowed = true;
  bool drainAllowed = true;

  SmartFluidTank(this.capacity, {this.onChanged});

  @override
  int get tanks => 1;

  @override
  PFluid fluidIn(int tank) => fluid;

  @override
  int tankCapacity(int tank) => capacity;

  @override
  bool isFluidValid(int tank, PFluid f) => validator?.call(f) ?? true;

  int get space => capacity - fluid.amount;
  bool get isEmpty => fluid.isEmpty;

  /// `setFluid`.
  void setFluid(PFluid f) {
    fluid = f.isEmpty ? PFluid.empty : f;
    onChanged?.call();
  }

  @override
  int fill(PFluid resource, {bool simulate = false}) {
    if (resource.isEmpty || !fillAllowed || !isFluidValid(0, resource)) return 0;
    if (fluid.isEmpty) {
      final filled = resource.amount < capacity ? resource.amount : capacity;
      if (!simulate) {
        fluid = resource.withAmount(filled);
        onChanged?.call();
      }
      return filled;
    }
    if (!fluid.sameFluid(resource)) return 0;
    var filled = capacity - fluid.amount;
    if (resource.amount < filled) filled = resource.amount;
    if (filled > 0 && !simulate) {
      fluid = fluid.withAmount(fluid.amount + filled);
      onChanged?.call();
    }
    return filled > 0 ? filled : 0;
  }

  @override
  PFluid drainFluid(PFluid resource, {bool simulate = false}) {
    if (resource.isEmpty || !fluid.sameFluid(resource)) return PFluid.empty;
    return drainAny(resource.amount, simulate: simulate);
  }

  @override
  PFluid drainAny(int maxAmount, {bool simulate = false}) {
    if (!drainAllowed || fluid.isEmpty || maxAmount <= 0) return PFluid.empty;
    final drained = maxAmount < fluid.amount ? maxAmount : fluid.amount;
    final out = fluid.withAmount(drained);
    if (!simulate) {
      fluid = fluid.withAmount(fluid.amount - drained);
      onChanged?.call();
    }
    return out;
  }
}

/// `CombinedTankWrapper`: several tanks as one handler (fill goes to the first tank that
/// accepts).
class CombinedFluidStorage implements FluidStorage {
  final List<FluidStorage> parts;

  CombinedFluidStorage(this.parts);

  @override
  int get tanks => parts.fold(0, (n, p) => n + p.tanks);

  (FluidStorage, int) _locate(int tank) {
    var t = tank;
    for (final p in parts) {
      if (t < p.tanks) return (p, t);
      t -= p.tanks;
    }
    throw RangeError.index(tank, this, 'tank');
  }

  @override
  PFluid fluidIn(int tank) {
    final (p, t) = _locate(tank);
    return p.fluidIn(t);
  }

  @override
  int tankCapacity(int tank) {
    final (p, t) = _locate(tank);
    return p.tankCapacity(t);
  }

  @override
  bool isFluidValid(int tank, PFluid fluid) {
    final (p, t) = _locate(tank);
    return p.isFluidValid(t, fluid);
  }

  @override
  int fill(PFluid fluid, {bool simulate = false}) {
    var remaining = fluid.amount;
    // Tanks that already hold the fluid first, then the rest.
    for (final pass in [true, false]) {
      for (final p in parts) {
        if (remaining <= 0) break;
        final holds = [for (var i = 0; i < p.tanks; i++) p.fluidIn(i)].any((f) => f.isNotEmpty && f.sameFluid(fluid));
        if (holds != pass) continue;
        remaining -= p.fill(fluid.withAmount(remaining), simulate: simulate);
      }
    }
    return fluid.amount - remaining;
  }

  @override
  PFluid drainFluid(PFluid fluid, {bool simulate = false}) {
    var out = PFluid.empty;
    for (final p in parts) {
      final want = fluid.amount - out.amount;
      if (want <= 0) break;
      final d = p.drainFluid(fluid.withAmount(want), simulate: simulate);
      if (d.isEmpty) continue;
      out = out.isEmpty ? d : out.withAmount(out.amount + d.amount);
    }
    return out;
  }

  @override
  PFluid drainAny(int maxAmount, {bool simulate = false}) {
    var out = PFluid.empty;
    for (final p in parts) {
      final want = maxAmount - out.amount;
      if (want <= 0) break;
      final d = out.isEmpty ? p.drainAny(want, simulate: simulate) : p.drainFluid(out.withAmount(want), simulate: simulate);
      if (d.isEmpty) continue;
      out = out.isEmpty ? d : out.withAmount(out.amount + d.amount);
    }
    return out;
  }
}
