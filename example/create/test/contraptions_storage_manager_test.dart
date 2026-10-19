// Pure tests of the mounted storage manager: external handlers, the sync diff, applying a sync
// payload, the menu layout of the storages and the interaction check. The host is not involved.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/core/contraption.dart';
import 'package:create/src/contraptions/core/movement.dart';
import 'package:create/src/contraptions/core/nbt_map.dart';
import 'package:create/src/contraptions/core/structure_info.dart';
import 'package:create/src/contraptions/storage/mounted_storage.dart';
import 'package:create/src/contraptions/storage/stacks.dart';
import 'package:create/src/contraptions/storage/storage_manager.dart';
import 'package:test/test.dart';

final class _Player extends InteractingPlayer {
  @override
  String get uuid => '00000000-0000-0000-0000-000000000001';
  @override
  bool get isSneaking => false;
  @override
  bool get isCreative => false;
  @override
  bool get holdsWrench => false;
  @override
  void playSound(String sound, double pitch, {double volume = 0.3}) {}
  @override
  Object get hostPlayer => this;
}

MountedStorageManager _managerWithChest(Pos pos) => MountedStorageManager()
  ..addItemStorage(
    SimpleMountedStorage(
      MountedStorages.chest,
      ItemStackHandler(27)..stacks[0] = const StoredStack('minecraft:stone', 5),
    ),
    pos,
  )
  ..initialize();

void main() {
  setUpAll(MountedStorages.installDefaults);

  group('MountedStorageManager', () {
    test('attachExternal adds the cart container to the contraption inventory', () {
      final manager = _managerWithChest((0, 0, 0));
      expect(manager.allItems.slots, 27);

      manager.attachExternal(
        ItemStackHandler(9)..stacks[2] = const StoredStack('minecraft:coal', 3),
      );
      manager.attachExternal(
        ItemStackHandler(1)..stacks[0] = const StoredStack('minecraft:apple', 1),
      );

      expect(manager.allItems.slots, 37);
      expect(manager.mountedItems.slots, 27, reason: 'external handlers stay out of it');
      expect(manager.allItems.stackInSlot(27 + 2).item, 'minecraft:coal');
      expect(manager.allItems.stackInSlot(36).item, 'minecraft:apple');
    });

    test('fuelItems excludes internal and blacklisted storages', () {
      final manager = MountedStorageManager()
        ..addItemStorage(
          SimpleMountedStorage(MountedStorages.chest, ItemStackHandler(27)),
          (0, 0, 0),
        )
        ..addItemStorage(
          SimpleMountedStorage(MountedStorages.dispenser, ItemStackHandler(9)),
          (1, 0, 0),
        )
        ..addItemStorage(
          VaultMountedStorage(MountedStorages.vault, ItemStackHandler(27)),
          (2, 0, 0),
        )
        ..initialize();

      expect(manager.mountedItems.slots, 27 + 27, reason: 'the dispenser is internal');
      expect(manager.fuelItems!.slots, 27, reason: 'the vault is fuel blacklisted');
    });

    test('tick reports the dirty storages once and then cools down', () {
      final manager = MountedStorageManager()
        ..addItemStorage(
          DepotMountedStorage(
            MountedStorages.depot,
            const StoredStack('minecraft:diamond', 1),
          ),
          (0, 0, 0),
        )
        ..addFluidStorage(
          FluidTankMountedStorage(
            MountedStorages.fluidTank,
            1000,
            const StoredFluid('minecraft:water', 500),
          ),
          (1, 0, 0),
        )
        ..initialize();

      expect(manager.tick(), isNull, reason: 'nothing changed yet');

      final depot = manager.storageAt((0, 0, 0))!;
      depot.setStackInSlot(0, const StoredStack('minecraft:emerald', 2));
      final tank = manager.fluidStorages[(1, 0, 0)]!;
      tank.drain(100);

      final sync = manager.tick()!;
      expect(sync.items.keys, [(0, 0, 0)]);
      expect(sync.fluids.keys, [(1, 0, 0)]);
      expect(
        sync.items[(0, 0, 0)]!.stackInSlot(0),
        const StoredStack('minecraft:emerald', 2),
      );
      expect(sync.fluids[(1, 0, 0)]!.fluidInTank(0).amount, 400);

      // marked clean, and the cooldown delays the next send
      depot.setStackInSlot(0, const StoredStack('minecraft:gold_ingot', 1));
      for (var i = 0; i < 8; i++) {
        expect(manager.tick(), isNull, reason: 'cooldown tick $i');
      }
      expect(manager.tick(), isNotNull);
    });

    test('handleSync applies only the storages of the packet and keeps the rest', () {
      final contraption = Contraption();
      final manager = contraption.storage
        ..addItemStorage(
          SimpleMountedStorage(
            MountedStorages.chest,
            ItemStackHandler(27)
              ..stacks[0] = const StoredStack('minecraft:stone', 5),
          ),
          (0, 0, 0),
        )
        ..addItemStorage(
          SimpleMountedStorage(
            MountedStorages.chest,
            ItemStackHandler(27)
              ..stacks[1] = const StoredStack('minecraft:dirt', 2),
          ),
          (1, 0, 0),
        )
        ..initialize();

      final synced = DepotMountedStorage(
        MountedStorages.depot,
        const StoredStack('minecraft:diamond', 7),
      );
      manager.handleSync(StorageSync({(1, 0, 0): synced}, const {}), contraption);

      expect(manager.allItemStorages.keys, containsAll([(0, 0, 0), (1, 0, 0)]));
      expect(
        manager.storageAt((0, 0, 0))!.stackInSlot(0),
        const StoredStack('minecraft:stone', 5),
        reason: 'a storage the packet does not carry is kept',
      );
      expect(identical(manager.storageAt((1, 0, 0)), synced), isTrue);
      expect(synced.item, const StoredStack('minecraft:diamond', 7));
    });

    test('handleSync decodes the wire fields of the payload', () {
      final manager = _managerWithChest((0, 0, 0));
      final packetStorage = SimpleMountedStorage(
        MountedStorages.chest,
        ItemStackHandler(27)..stacks[3] = const StoredStack('minecraft:oak_log', 9),
      );
      final sync = StorageSync.fromWire({
        'contraptionId': 42,
        'items': {(2, 0, 0): packetStorage.encode().toValue()},
        'fluids': <Pos, Object?>{},
      });
      expect(sync.items.keys, [(2, 0, 0)]);

      final contraption = Contraption();
      contraption.storage = manager;
      manager.handleSync(sync, contraption);

      expect(manager.storageAt((0, 0, 0)), isNotNull);
      expect(
        manager.storageAt((2, 0, 0))!.stackInSlot(3),
        const StoredStack('minecraft:oak_log', 9),
      );
    });

    test('handleSync keeps identity so afterSync runs on the synced storage', () {
      final recorded = <Pos>[];
      final contraption = Contraption();
      final manager = contraption.storage..initialize();
      final synced = _RecordingStorage(recorded);
      manager.handleSync(StorageSync({(4, 5, 6): synced}, const {}), contraption);

      expect(recorded, [(4, 5, 6)]);
      expect(identical(manager.storageAt((4, 5, 6)), synced), isTrue);
    });

    test('read with a client packet restores the synced storages', () {
      final manager = MountedStorageManager()
        ..addItemStorage(
          DepotMountedStorage(
            MountedStorages.depot,
            const StoredStack('minecraft:diamond', 2),
          ),
          (0, 0, 0),
        )
        ..addItemStorage(
          SimpleMountedStorage(MountedStorages.chest, ItemStackHandler(27)),
          (1, 0, 0),
        )
        ..initialize();
      final nbt = NbtMap();
      manager.write(nbt, clientPacket: true);
      expect(nbt.getList('items'), hasLength(1), reason: 'only synced storages');

      final contraption = Contraption();
      final restored = MountedStorageManager()
        ..read(nbt, clientPacket: true, contraption: contraption);
      expect(
        restored.storageAt((0, 0, 0))!.stackInSlot(0),
        const StoredStack('minecraft:diamond', 2),
      );
      expect(restored.storageAt((1, 0, 0)), isNull);
      expect(
        restored.interactablePositions,
        containsAll([(0, 0, 0), (1, 0, 0)]),
        reason: 'the spawn packet tells the client every interactable position',
      );
      expect(restored.isInteractable((1, 0, 0)), isFalse);
    });

    test('only openable storages answer a player interaction', () {
      final contraption = Contraption();
      contraption.storage = MountedStorageManager()
        ..addItemStorage(
          SimpleMountedStorage(MountedStorages.chest, ItemStackHandler(27)),
          (0, 0, 0),
        )
        ..addItemStorage(
          VaultMountedStorage(MountedStorages.vault, ItemStackHandler(27)),
          (1, 0, 0),
        )
        ..initialize();
      contraption.blocks[(0, 0, 0)] = StructureBlockInfo(
        (0, 0, 0),
        BState('minecraft:chest'),
      );
      contraption.blocks[(1, 0, 0)] = StructureBlockInfo(
        (1, 0, 0),
        BState('create:item_vault'),
      );
      contraption.blocks[(2, 0, 0)] = StructureBlockInfo(
        (2, 0, 0),
        BState('minecraft:stone'),
      );

      final player = _Player();
      expect(
        contraption.storage.handlePlayerStorageInteraction(
          contraption,
          player,
          (0, 0, 0),
        ),
        isTrue,
      );
      expect(
        contraption.storage.handlePlayerStorageInteraction(
          contraption,
          player,
          (1, 0, 0),
        ),
        isFalse,
        reason: 'a vault has no menu',
      );
      expect(
        contraption.storage.handlePlayerStorageInteraction(
          contraption,
          player,
          (2, 0, 0),
        ),
        isFalse,
        reason: 'no storage at that position',
      );
      expect(contraption.storage.isInteractable((0, 0, 0)), isTrue);
      expect(contraption.storage.isInteractable((1, 0, 0)), isFalse);
    });

    test('a stack keeps its components when it stays in its slot', () {
      final enchanted = NbtMap()..putInt('minecraft:damage', 7);
      final previous = [
        StoredStack('minecraft:diamond_sword', 1, enchanted),
        StoredStack.empty,
      ];
      final next = [
        const StoredStack('minecraft:diamond_sword', 1),
        StoredStack.empty,
      ];

      carryStackComponents(previous, next);

      expect(next[0].components, isNotNull);
      expect(next[0].components!.getInt('minecraft:damage'), 7);
    });

    test('a stack keeps its components when it is moved to another slot', () {
      final enchanted = NbtMap()..putInt('minecraft:damage', 7);
      final previous = [
        StoredStack('minecraft:diamond_sword', 1, enchanted),
        StoredStack.empty,
      ];
      final next = [
        StoredStack.empty,
        const StoredStack('minecraft:diamond_sword', 1),
      ];

      carryStackComponents(previous, next);

      expect(next[0].isEmpty, isTrue);
      expect(next[1].components, isNotNull);
      expect(next[1].components!.getInt('minecraft:damage'), 7);
    });

    test('components are not invented for a stack that came from the player', () {
      final previous = [
        const StoredStack('minecraft:stone', 1),
        StoredStack.empty,
      ];
      final next = [
        const StoredStack('minecraft:stone', 1),
        const StoredStack('minecraft:diamond_sword', 1),
      ];

      carryStackComponents(previous, next);

      expect(next[0].components, isNull);
      expect(next[1].components, isNull);
    });

    test('an ambiguous move does not swap components between two stacks', () {
      final a = NbtMap()..putInt('minecraft:damage', 1);
      final b = NbtMap()..putInt('minecraft:damage', 2);
      final previous = [
        StoredStack('minecraft:diamond_sword', 1, a),
        StoredStack('minecraft:diamond_sword', 1, b),
      ];
      final next = [
        const StoredStack('minecraft:diamond_sword', 1),
        const StoredStack('minecraft:diamond_sword', 1),
      ];

      carryStackComponents(previous, next);

      expect(next[0].components!.getInt('minecraft:damage'), 1);
      expect(next[1].components!.getInt('minecraft:damage'), 2);
    });

    test('the menu layout follows the storage', () {
      MountedItemStorage storageOf(int slots) =>
          SimpleMountedStorage(MountedStorages.chest, ItemStackHandler(slots));

      expect(storageOf(27).menuLayout, (dispenser: false, rows: 3));
      expect(storageOf(54).menuLayout, (dispenser: false, rows: 6));
      expect(storageOf(3).menuLayout, isNull, reason: 'not full rows of nine');

      final dispenser = DispenserMountedStorage(
        MountedStorages.dispenser,
        ItemStackHandler(9),
      );
      expect(dispenser.menuLayout, (dispenser: true, rows: 0));
      expect(dispenser.openingSound, isNull);

      final vault = VaultMountedStorage(MountedStorages.vault, ItemStackHandler(27));
      expect(vault.menuLayout, isNull, reason: 'canOpen is false');
    });
  });
}

/// A storage whose `afterSync` records the position it was synced at.
final class _RecordingStorage extends WrapperMountedItemStorage
    with SyncedMountedStorage {
  final List<Pos> recorded;

  _RecordingStorage(this.recorded)
    : super(
        MountedStorages.chest,
        ItemStackHandler(27)
          ..stacks[0] = const StoredStack('minecraft:stone', 5),
      );

  @override
  NbtMap? unmount(StructureBlockInfo info, NbtMap? be) => be;

  @override
  void afterSync(Object contraption, Pos localPos) => recorded.add(localPos);
}
