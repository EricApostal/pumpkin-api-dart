// `MountedStorageManager` (pure): all the storages of one contraption, how they are saved and
// synced, and the combined views actors use.
import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../core/nbt.dart';
import '../core/level.dart';
import '../core/nbt_map.dart';
import '../core/structure_info.dart';
import 'mounted_storage.dart';
import 'stacks.dart';

/// The dirty storages that have to be sent to clients (`MountedStorageSyncPacket`).
final class StorageSync {
  final Map<Pos, MountedItemStorage> items;
  final Map<Pos, MountedFluidStorage> fluids;

  const StorageSync(this.items, this.fluids);

  bool get isEmpty => items.isEmpty && fluids.isEmpty;
}

class MountedStorageManager {
  Map<Pos, MountedItemStorage>? _itemsBuilder;
  Map<Pos, MountedFluidStorage>? _fluidsBuilder;

  Map<Pos, MountedItemStorage> _allItemStorages = const {};
  Map<Pos, MountedFluidStorage> _fluids = const {};
  ItemSlots _mountedItems = CombinedItemSlots([]);
  ItemSlots? _fuelItems;
  ItemSlots _allItems = CombinedItemSlots([]);
  final List<ItemSlots> _externalHandlers = [];
  Set<Pos>? interactablePositions;

  /// Ticks until the storages can sync again.
  int syncCooldown = 0;

  MountedStorageManager() {
    reset();
  }

  bool get isInitialized => _itemsBuilder == null;

  /// `initialize`: builds the views. Calling it twice does nothing.
  void initialize() {
    if (isInitialized) return;
    _allItemStorages = Map.unmodifiable(_itemsBuilder!);
    _mountedItems = CombinedItemSlots([
      for (final s in _allItemStorages.values)
        if (!s.type.isInternal) s,
    ]);
    _allItems = _mountedItems;
    _itemsBuilder = null;
    final fuel = [
      for (final s in _allItemStorages.values)
        if (!s.type.isInternal && !s.type.isFuelBlacklisted) s,
    ];
    _fuelItems = fuel.isEmpty ? null : CombinedItemSlots(fuel);
    _fluids = Map.unmodifiable(_fluidsBuilder!);
    _fluidsBuilder = null;
  }

  /// `reset`.
  void reset() {
    _allItemStorages = const {};
    _fluids = const {};
    _mountedItems = CombinedItemSlots([]);
    _fuelItems = null;
    _allItems = CombinedItemSlots([]);
    _itemsBuilder = {};
    _fluidsBuilder = {};
  }

  void _assertInitialized() {
    if (!isInitialized)
      throw StateError('MountedStorageManager is uninitialized');
  }

  /// `getAllItems`: the contraption inventory: all exposed storages plus external ones (minecart).
  ItemSlots get allItems {
    _assertInitialized();
    return _allItems;
  }

  /// `getAllItemStorages`: every item storage by local position, internal ones too.
  Map<Pos, MountedItemStorage> get allItemStorages {
    _assertInitialized();
    return _allItemStorages;
  }

  /// `getMountedItems`: the exposed storages, without external ones.
  ItemSlots get mountedItems {
    _assertInitialized();
    return _mountedItems;
  }

  /// `getFuelItems`: exposed storages that may provide fuel, `null` if there are none.
  ItemSlots? get fuelItems {
    _assertInitialized();
    return _fuelItems;
  }

  /// `getFluids().storages`.
  Map<Pos, MountedFluidStorage> get fluidStorages {
    _assertInitialized();
    return _fluids;
  }

  /// `getFluids()`: all fluid storages as one handler.
  FluidTanks get fluids {
    _assertInitialized();
    return CombinedFluidTanks(_fluids.values.toList());
  }

  /// `attachExternal`: adds a handler that is not part of the blocks (a minecart container).
  void attachExternal(ItemSlots external) {
    _externalHandlers.add(external);
    _allItems = CombinedItemSlots([_mountedItems, ..._externalHandlers]);
  }

  /// `addBlock`: mounts the storages of a block that joins the contraption.
  void addBlock(
    ContraptionLevel level,
    BState state,
    Pos localPos,
    CapturedBlockEntity? be,
  ) {
    final itemType = MountedStorages.itemTypeOf(state, level);
    if (itemType != null) {
      final storage = itemType.mount(level, state, localPos, be);
      if (storage != null) addItemStorage(storage, localPos);
    }
    final fluidType = MountedStorages.fluidTypeOf(state);
    if (fluidType != null) {
      final storage = fluidType.mount(
        level,
        state,
        localPos,
        be,
        level.settings,
      );
      if (storage != null) addFluidStorage(storage, localPos);
    }
  }

  void addItemStorage(MountedItemStorage storage, Pos pos) {
    (_itemsBuilder ?? (throw StateError('already initialized')))[pos] = storage;
  }

  void addFluidStorage(MountedFluidStorage storage, Pos pos) {
    (_fluidsBuilder ?? (throw StateError('already initialized')))[pos] =
        storage;
  }

  /// `unmount`: the data of the block entity that is placed with [info], with the stored items
  /// in it. Returns [be] unchanged when the block has no matching storage.
  NbtMap? unmount(ContraptionLevel level, StructureBlockInfo info, NbtMap? be) {
    var nbt = be;
    final itemStorage = allItemStorages[info.pos];
    if (itemStorage != null) {
      final expected = MountedStorages.itemTypeOf(info.state, level);
      if (identical(itemStorage.type, expected) ||
          itemStorage.type.id == expected?.id) {
        nbt = itemStorage.unmount(info, nbt);
      }
    }
    final fluidStorage = fluidStorages[info.pos];
    if (fluidStorage != null) {
      final expected = MountedStorages.fluidTypeOf(info.state);
      if (fluidStorage.type.id == expected?.id)
        nbt = fluidStorage.unmount(info, nbt);
    }
    return nbt;
  }

  /// `tick`: the storages whose content changed, to send to the clients tracking the entity;
  /// `null` when nothing has to be sent now.
  StorageSync? tick() {
    if (syncCooldown > 0) {
      syncCooldown--;
      return null;
    }
    final items = <Pos, MountedItemStorage>{};
    final fluids = <Pos, MountedFluidStorage>{};
    for (final e in _allItemStorages.entries) {
      final s = e.value;
      if (s is SyncedMountedStorage && (s as SyncedMountedStorage).isDirty) {
        items[e.key] = e.value;
        (s as SyncedMountedStorage).markClean();
      }
    }
    for (final e in _fluids.entries) {
      final s = e.value;
      if (s is SyncedMountedStorage && (s as SyncedMountedStorage).isDirty) {
        fluids[e.key] = e.value;
        (s as SyncedMountedStorage).markClean();
      }
    }
    if (items.isEmpty && fluids.isEmpty) return null;
    syncCooldown = 8;
    return StorageSync(items, fluids);
  }

  /// `read`.
  void read(NbtMap nbt) {
    reset();
    try {
      for (final v in nbt.getList('items')) {
        final tag = NbtMap.of(v);
        final storage = MountedStorages.decodeItem(tag.getCompound('storage'));
        if (storage != null) addItemStorage(storage, tag.getBlockPos('pos'));
      }
      for (final v in nbt.getList('fluids')) {
        final tag = NbtMap.of(v);
        final storage = MountedStorages.decodeFluid(tag.getCompound('storage'));
        if (storage != null) addFluidStorage(storage, tag.getBlockPos('pos'));
      }
      if (nbt.contains('interactable_positions')) {
        interactablePositions = {
          for (final v in nbt.getList('interactable_positions'))
            (
              NbtMap.of(v).getInt('X'),
              NbtMap.of(v).getInt('Y'),
              NbtMap.of(v).getInt('Z'),
            ),
        };
      }
    } on Object {
      // an unreadable storage leaves the others; initialize() below makes the manager valid
    }
    initialize();
  }

  /// `write`: for the spawn packet only the synced storages, plus the positions of all of them.
  void write(NbtMap nbt, {required bool clientPacket}) {
    final items = <NbtValue>[];
    for (final e in allItemStorages.entries) {
      if (clientPacket && e.value is! SyncedMountedStorage) continue;
      items.add(
        (NbtMap()
              ..putBlockPos('pos', e.key)
              ..putCompound('storage', e.value.encode()))
            .toValue(),
      );
    }
    if (items.isNotEmpty) nbt.putList('items', items);

    final fluidList = <NbtValue>[];
    for (final e in fluidStorages.entries) {
      if (clientPacket && e.value is! SyncedMountedStorage) continue;
      fluidList.add(
        (NbtMap()
              ..putBlockPos('pos', e.key)
              ..putCompound('storage', e.value.encode()))
            .toValue(),
      );
    }
    if (fluidList.isNotEmpty) nbt.putList('fluids', fluidList);

    if (clientPacket) {
      final positions = <Pos>{...allItemStorages.keys, ...fluidStorages.keys};
      nbt.putList('interactable_positions', [
        for (final p in positions)
          (NbtMap()
                ..putInt('X', p.$1)
                ..putInt('Y', p.$2)
                ..putInt('Z', p.$3))
              .toValue(),
      ]);
    }
  }

  /// Whether a position holds a storage a player can open.
  bool isInteractable(Pos localPos) {
    if (!isInitialized) return false;
    return _allItemStorages[localPos]?.canOpen ?? false;
  }
}
