// `MountedStorageManager` (pure): all the storages of one contraption, how they are saved and
// synced, and the combined views actors use.
import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../core/nbt.dart';
import '../core/contraption.dart';
import '../core/level.dart';
import '../core/movement.dart';
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

  /// `MountedStorageSyncPacket`: the fields of `create:mounted_storage_sync`, as the payload bus
  /// hands them over (`{contraptionId, items: {pos: nbt}, fluids: {pos: nbt}}`). Storages of an
  /// unknown type are dropped, like a failed codec on the client.
  static StorageSync fromWire(Map<String, Object?> fields) {
    final items = <Pos, MountedItemStorage>{};
    final fluids = <Pos, MountedFluidStorage>{};
    final rawItems = fields['items'];
    if (rawItems is Map) {
      for (final e in rawItems.entries) {
        final pos = e.key;
        final value = e.value;
        if (pos is! (int, int, int) || value is! NbtValue) continue;
        final storage = MountedStorages.decodeItem(NbtMap.of(value));
        if (storage != null) items[pos] = storage;
      }
    }
    final rawFluids = fields['fluids'];
    if (rawFluids is Map) {
      for (final e in rawFluids.entries) {
        final pos = e.key;
        final value = e.value;
        if (pos is! (int, int, int) || value is! NbtValue) continue;
        final storage = MountedStorages.decodeFluid(NbtMap.of(value));
        if (storage != null) fluids[pos] = storage;
      }
    }
    return StorageSync(items, fluids);
  }
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

  /// `read`. [contraption] is given on the client for the initial `afterSync` callbacks.
  void read(
    NbtMap nbt, {
    bool clientPacket = false,
    Contraption? contraption,
  }) {
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
      _readLegacy(nbt);
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

    // for client sync, run initial afterSync callbacks
    if (!clientPacket || contraption == null) return;
    for (final e in _allItemStorages.entries) {
      final s = e.value;
      if (s is SyncedMountedStorage) {
        (s as SyncedMountedStorage).afterSync(contraption, e.key);
      }
    }
    for (final e in _fluids.entries) {
      final s = e.value;
      if (s is SyncedMountedStorage) {
        (s as SyncedMountedStorage).afterSync(contraption, e.key);
      }
    }
  }

  /// `handleSync`: applies the storages of a `MountedStorageSyncPacket`; the packet only carries
  /// the changed ones, the others are kept. Then runs their `afterSync` callbacks.
  void handleSync(StorageSync sync, Contraption contraption) {
    final items = Map<Pos, MountedItemStorage>.of(allItemStorages);
    final fluids = Map<Pos, MountedFluidStorage>.of(fluidStorages);
    reset();

    // track freshly synced storages (identity: two storages may compare equal by content)
    final synced = <SyncedMountedStorage, Pos>{};

    try {
      // re-add the existing ones, then override them with the synced ones
      items.forEach((pos, storage) => addItemStorage(storage, pos));
      fluids.forEach((pos, storage) => addFluidStorage(storage, pos));
      sync.items.forEach((pos, storage) {
        addItemStorage(storage, pos);
        if (storage is SyncedMountedStorage) {
          synced[storage as SyncedMountedStorage] = pos;
        }
      });
      sync.fluids.forEach((pos, storage) {
        addFluidStorage(storage, pos);
        if (storage is SyncedMountedStorage) {
          synced[storage as SyncedMountedStorage] = pos;
        }
      });
    } on Object {
      // an exception leaves the manager valid through initialize() below
    }

    initialize();

    for (final e in synced.entries) {
      e.key.afterSync(contraption, e.value);
    }
  }

  /// `readLegacy`: the `Storage`/`FluidStorage` lists of contraptions saved before the codec.
  void _readLegacy(NbtMap nbt) {
    for (final v in nbt.getList('Storage')) {
      final tag = NbtMap.of(v);
      final pos = tag.getBlockPos('Pos');
      final data = tag.getCompound('Data');
      final MountedItemStorage storage;
      if (data.contains('Toolbox')) {
        storage = MountedStorages.toolbox.fromLegacy(data);
      } else if (data.contains('NoFuel')) {
        storage = MountedStorages.vault.fromLegacy(data);
      } else if (data.contains('Bottomless')) {
        storage = MountedStorages.creativeCrate.fromLegacy(data);
      } else if (data.contains('Synced')) {
        storage = MountedStorages.depot.fromLegacy(data);
      } else {
        storage = MountedStorages.fallback.fromLegacy(data);
      }
      addItemStorage(storage, pos);
    }

    for (final v in nbt.getList('FluidStorage')) {
      final tag = NbtMap.of(v);
      final pos = tag.getBlockPos('Pos');
      final data = tag.getCompound('Data');
      addFluidStorage(
        data.contains('Bottomless')
            ? MountedStorages.creativeFluidTank.fromLegacy(data)
            : MountedStorages.fluidTank.fromLegacy(data),
        pos,
      );
    }
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

  /// `getAllItemStorages()[localPos]`: the storage of the block at [localPos], if any.
  MountedItemStorage? storageAt(Pos localPos) {
    _assertInitialized();
    return _allItemStorages[localPos];
  }

  /// `handlePlayerStorageInteraction(contraption, player, localPos)`: whether clicking [localPos]
  /// opens a container. The host then opens the menu of [storageAt]; a client host checks
  /// [isInteractable] instead, because it does not have the storages.
  bool handlePlayerStorageInteraction(
    Contraption contraption,
    InteractingPlayer player,
    Pos localPos,
  ) {
    if (!isInitialized) return false;
    if (contraption.blocks[localPos] == null) return false;
    return _allItemStorages[localPos]?.menuLayout != null;
  }

  /// Whether a position holds a storage a player can open.
  bool isInteractable(Pos localPos) {
    if (!isInitialized) return false;
    return _allItemStorages[localPos]?.canOpen ?? false;
  }
}
