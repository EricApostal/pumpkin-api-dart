// The mounted storage wrappers of Create's contraption API (pure): many storages of one
// contraption seen as a single handler, plus the container a mounted storage opens for a player.
//
// Java's `MountedItemStorageWrapper`/`MountedFluidStorageWrapper` extend `CombinedItemHandler` /
// `CombinedTankWrapper`; the item wrapper uses lookup arrays so a slot resolves in O(1) even with
// many storages. The Dart implementation keeps that layout. `StorageInteractionWrapper` is the
// `ItemHandlerContainer` that validates the player and runs a close callback.
import '../../../contraptions/storage/mounted_storage.dart';
import '../../../contraptions/storage/stacks.dart';
import '../../../common/pos.dart';
import 'item_handler_container.dart';

/// `MountedItemStorageWrapper`: all item storages of a contraption as one [ItemSlots].
class MountedItemStorageWrapper implements ItemSlots {
  /// `storages`: the individual storages, by local position.
  final Map<Pos, MountedItemStorage> storages;

  late final List<MountedItemStorage> _parts = storages.values.toList(
    growable: false,
  );
  late final List<int> _slotToStorage = _buildSlotToStorage();
  late final List<int> _slotOffsets = _buildSlotOffsets();

  MountedItemStorageWrapper(Map<Pos, MountedItemStorage> storages)
    : storages = Map.unmodifiable(storages);

  List<int> _buildSlotToStorage() {
    final result = <int>[];
    for (var i = 0; i < _parts.length; i++) {
      result.addAll(List<int>.filled(_parts[i].slots, i));
    }
    return result;
  }

  List<int> _buildSlotOffsets() {
    final result = <int>[];
    var current = 0;
    for (final part in _parts) {
      result.add(current);
      current += part.slots;
    }
    return result;
  }

  /// `getIndexForSlot` / `getSlotFromIndex`: the storage and its local slot, `null` out of range.
  (MountedItemStorage, int)? _locate(int slot) {
    if (slot < 0 || slot >= _slotToStorage.length) return null;
    final index = _slotToStorage[slot];
    return (_parts[index], slot - _slotOffsets[index]);
  }

  @override
  int get slots => _slotToStorage.length;

  @override
  StoredStack stackInSlot(int slot) {
    final location = _locate(slot);
    return location == null
        ? StoredStack.empty
        : location.$1.stackInSlot(location.$2);
  }

  @override
  void setStackInSlot(int slot, StoredStack stack) {
    final location = _locate(slot);
    if (location != null) location.$1.setStackInSlot(location.$2, stack);
  }

  @override
  StoredStack insertItem(int slot, StoredStack stack, {bool simulate = false}) {
    final location = _locate(slot);
    return location == null
        ? stack
        : location.$1.insertItem(location.$2, stack, simulate: simulate);
  }

  @override
  StoredStack extractItem(int slot, int amount, {bool simulate = false}) {
    final location = _locate(slot);
    return location == null
        ? StoredStack.empty
        : location.$1.extractItem(location.$2, amount, simulate: simulate);
  }

  @override
  int slotLimit(int slot) {
    final location = _locate(slot);
    return location == null ? 0 : location.$1.slotLimit(location.$2);
  }

  @override
  bool isItemValid(int slot, StoredStack stack) {
    final location = _locate(slot);
    return location != null && location.$1.isItemValid(location.$2, stack);
  }
}

/// `MountedFluidStorageWrapper`: all fluid storages of a contraption as one [FluidTanks].
class MountedFluidStorageWrapper implements FluidTanks {
  /// `storages`: the individual storages, by local position.
  final Map<Pos, MountedFluidStorage> storages;

  late final List<MountedFluidStorage> _parts = storages.values.toList(
    growable: false,
  );
  late final List<int> _tankToStorage = _buildTankToStorage();
  late final List<int> _tankOffsets = _buildTankOffsets();

  MountedFluidStorageWrapper(Map<Pos, MountedFluidStorage> storages)
    : storages = Map.unmodifiable(storages);

  List<int> _buildTankToStorage() {
    final result = <int>[];
    for (var i = 0; i < _parts.length; i++) {
      result.addAll(List<int>.filled(_parts[i].tanks, i));
    }
    return result;
  }

  List<int> _buildTankOffsets() {
    final result = <int>[];
    var current = 0;
    for (final part in _parts) {
      result.add(current);
      current += part.tanks;
    }
    return result;
  }

  (MountedFluidStorage, int)? _locate(int tank) {
    if (tank < 0 || tank >= _tankToStorage.length) return null;
    final index = _tankToStorage[tank];
    return (_parts[index], tank - _tankOffsets[index]);
  }

  @override
  int get tanks => _tankToStorage.length;

  @override
  StoredFluid fluidInTank(int tank) {
    final location = _locate(tank);
    return location == null
        ? StoredFluid.empty
        : location.$1.fluidInTank(location.$2);
  }

  @override
  int tankCapacity(int tank) {
    final location = _locate(tank);
    return location == null ? 0 : location.$1.tankCapacity(location.$2);
  }

  @override
  bool isFluidValid(int tank, StoredFluid fluid) {
    final location = _locate(tank);
    return location != null && location.$1.isFluidValid(location.$2, fluid);
  }

  @override
  int fill(StoredFluid fluid, {bool simulate = false}) {
    var remaining = fluid;
    var total = 0;
    for (final part in _parts) {
      if (remaining.isEmpty) break;
      final filled = part.fill(remaining, simulate: simulate);
      total += filled;
      remaining = remaining.copyWithAmount(remaining.amount - filled);
    }
    return total;
  }

  @override
  StoredFluid drain(int maxAmount, {bool simulate = false}) {
    var drained = StoredFluid.empty;
    for (final part in _parts) {
      final want = maxAmount - (drained.isEmpty ? 0 : drained.amount);
      if (want <= 0) break;
      final got = drained.isEmpty
          ? part.drain(want, simulate: simulate)
          : part.drainFluid(drained.copyWithAmount(want), simulate: simulate);
      if (got.isEmpty) continue;
      drained = drained.isEmpty
          ? got
          : drained.copyWithAmount(drained.amount + got.amount);
    }
    return drained;
  }

  @override
  StoredFluid drainFluid(StoredFluid fluid, {bool simulate = false}) {
    if (fluid.isEmpty) return StoredFluid.empty;
    var remaining = fluid;
    var drained = StoredFluid.empty;
    for (final part in _parts) {
      final got = part.drainFluid(remaining, simulate: simulate);
      if (got.isEmpty) continue;
      drained = drained.isEmpty
          ? got
          : drained.copyWithAmount(drained.amount + got.amount);
      remaining = remaining.copyWithAmount(remaining.amount - got.amount);
      if (remaining.isEmpty) break;
    }
    return drained;
  }
}

/// `StorageInteractionWrapper`: the container a mounted storage opens for a player. [stillValid]
/// is checked every time the menu validates, [onClose] runs when the menu closes.
class StorageInteractionWrapper<P> extends ItemHandlerContainer<P> {
  final bool Function(P) _stillValid;
  final void Function(P) _onClose;

  StorageInteractionWrapper(
    ItemSlots inv, {
    required bool Function(P) stillValid,
    required void Function(P) onClose,
  }) : _stillValid = stillValid,
       _onClose = onClose,
       super(inv);

  @override
  bool stillValid(P player) => _stillValid(player);

  /// `getMaxStackSize`: 64, unlike the base container.
  @override
  int get maxStackSize => 64;

  @override
  void stopOpen(P user) => _onClose(user);
}
