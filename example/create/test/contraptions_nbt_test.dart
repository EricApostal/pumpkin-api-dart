// Pure NBT round-trip tests for the contraption core, its actors and mounted storages. The host
// is not involved; the tests run on the Dart VM.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/core/contraption.dart';
import 'package:create/src/contraptions/core/level.dart';
import 'package:create/src/contraptions/core/movement.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/contraptions/core/nbt_map.dart';
import 'package:create/src/contraptions/core/structure_info.dart';
import 'package:create/src/contraptions/entity/oriented_contraption_nbt.dart';
import 'package:create/src/contraptions/storage/mounted_storage.dart';
import 'package:create/src/contraptions/storage/stacks.dart';
import 'package:create/src/contraptions/storage/storage_manager.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;
import 'package:test/test.dart';

/// A level over a map of states and block entity data.
final class _MapLevel extends ContraptionLevel {
  final Map<Pos, BState> blocks;
  final Map<Pos, NbtMap> blockEntities;

  _MapLevel(this.blocks, [Map<Pos, NbtMap>? blockEntities])
    : blockEntities = blockEntities ?? {};

  @override
  String get worldId => 'test:world';

  @override
  ContraptionSettings get settings => DefaultContraptionSettings();

  @override
  BState stateAt(Pos p) => blocks[p] ?? BState.air;

  @override
  bool isLoaded(Pos p) => true;

  @override
  bool isFaceSturdy(Pos p, Direction face) => !stateCollisionEmpty(stateAt(p));

  @override
  List<BlockBox> collisionBoxes(Pos p) => stateCollisionBoxes(stateAt(p));

  @override
  bool supportShapeEmpty(Pos p) => stateCollisionEmpty(stateAt(p));

  @override
  bool canBeReplaced(Pos p) => stateReplaceable(stateAt(p));

  @override
  bool hasTag(Pos p, String tag) => false;

  @override
  bool isWater(Pos p) => false;

  @override
  bool isOutsideBuildHeight(Pos p) => false;

  @override
  int get minY => -64;

  @override
  CapturedBlockEntity? blockEntityAt(Pos p) {
    final nbt = blockEntities[p];
    if (nbt == null) return null;
    return CapturedBlockEntity(nbt.getString('id'), nbt.copy(), nbt.copy());
  }

  @override
  PushReaction pushReaction(BState state) => PushReaction.normal;

  @override
  bool isUnbreakable(BState state) => false;

  @override
  bool stateHasTag(BState state, String tag) => false;

  @override
  bool stateCollisionEmpty(BState state) => state.isAir;

  @override
  bool stateReplaceable(BState state) => state.isAir;

  @override
  List<BlockBox> stateCollisionBoxes(BState state) =>
      state.isAir ? const [] : const [BlockBox(0, 0, 0, 1, 1, 1)];
}

const _stone = BState('minecraft:stone');
const _uuid = '12345678-1234-5678-9abc-def012345678';
const _uuid2 = '00000000-0000-0000-0000-000000000002';

/// A movement behaviour that records its extra data, so the actor round trip can be checked.
final class _RecordingBehaviour extends MovementBehaviour {
  const _RecordingBehaviour();

  @override
  void writeExtraData(MovementContext context) {
    context.data.putInt('Extra', 7);
  }
}

void main() {
  group('uuid codec', () {
    test('writes the four ints of UUIDUtil.CODEC and reads them back', () {
      final tag = NbtMap()..putUuid('Id', _uuid);
      expect(tag['Id']!.kind, NbtKind.intArray);
      expect(tag.getIntArray('Id'), hasLength(4));
      expect(tag.getUuid('Id'), _uuid);
    });

    test('missing keys use the fallback', () {
      expect(NbtMap().getUuid('Id'), isNull);
      expect(NbtMap().getUuid('Id', 'none'), 'none');
    });

    test('legacy string ids are still accepted', () {
      final tag = NbtMap()..putString('Id', _uuid);
      expect(tag.getUuid('Id'), _uuid);
    });
  });

  group('contraption NBT', () {
    late _MapLevel level;
    late Contraption contraption;

    setUp(() {
      MovementBehaviours.register(
        'minecraft:stone',
        const _RecordingBehaviour(),
      );
      MovingInteractions.register('minecraft:stone', const _TestInteraction());
      addTearDown(MovementBehaviours.registry.clear);
      addTearDown(MovingInteractions.registry.clear);

      level = _MapLevel({(0, 0, 0): _stone, (1, 0, 0): _stone});
      contraption = Contraption();
      contraption.blocks[(0, 0, 0)] = StructureBlockInfo(
        (0, 0, 0),
        _stone,
        NbtMap()..putInt('Value', 42),
      );
      contraption.blocks[(1, 0, 0)] = const StructureBlockInfo((
        1,
        0,
        0,
      ), _stone);
      contraption.updateTags[(0, 0, 0)] = NbtMap()..putInt('Tag', 1);

      contraption.actors.add(
        MovementContext(
            level,
            level.worldId,
            contraption.blocks[(0, 0, 0)]!,
            contraption,
          )
          ..motion = (1, 0, 0)
          ..relativeMotion = (0, 0, 1)
          ..position = (0.5, 0.5, 0.5)
          ..stall = true
          ..firstMovement = false,
      );

      contraption.seats.add((2, 3, 4));
      contraption.seatMapping[_uuid] = 0;
      contraption.stabilizedSubContraptions[_uuid2] = BlockFace((
        5,
        6,
        7,
      ), Direction.north);
      contraption.superglue.add(const Aabb(0, 0, 0, 1, 2, 3));
      contraption.capturedMultiblocks[(9, 9, 9)] = [
        const StructureBlockInfo((1, 0, 0), _stone),
      ];
      contraption.interactors[(0, 0, 0)] = const _TestInteraction();
      contraption.disabledActors = [const StoredStack('minecraft:dirt', 1)];
      contraption.bounds = const Aabb(0, 0, 0, 4, 5, 6);
      contraption.anchor = (5, 64, 5);
      contraption.stalled = true;
      contraption.hasUniversalCreativeCrate = true;
    });

    test('round trips every key', () {
      final nbt = contraption.writeNbt();
      final restored = Contraption.fromNbt(level, nbt);

      expect(restored.anchor, (5, 64, 5));
      expect(restored.stalled, isTrue);
      expect(restored.hasUniversalCreativeCrate, isTrue);
      expect(restored.bounds!.maxY, 5);

      expect(restored.blocks.length, 2);
      expect(restored.blocks[(0, 0, 0)]!.nbt!.getInt('Value'), 42);
      expect(restored.updateTags[(0, 0, 0)]!.getInt('Tag'), 1);

      final actor = restored.actors.single;
      expect(actor.localPos, (0, 0, 0));
      expect(actor.motion, (1.0, 0.0, 0.0));
      expect(actor.relativeMotion, (0.0, 0.0, 1.0));
      expect(actor.position, (0.5, 0.5, 0.5));
      expect(actor.stall, isTrue);
      expect(actor.firstMovement, isFalse);
      // `writeExtraData` is applied before the context is written.
      expect(actor.data.getInt('Extra'), 7);

      expect(restored.seats, [(2, 3, 4)]);
      expect(restored.seatMapping, {_uuid: 0});

      final sub = restored.stabilizedSubContraptions[_uuid2]!;
      expect(sub.pos, (5, 6, 7));
      expect(sub.face, Direction.north);

      final glue = restored.superglue.single;
      expect((glue.minX, glue.minY, glue.minZ), (0.0, 0.0, 0.0));
      expect((glue.maxX, glue.maxY, glue.maxZ), (1.0, 2.0, 3.0));

      expect(restored.capturedMultiblocks[(9, 9, 9)]!.single.pos, (1, 0, 0));
      expect(restored.disabledActors.single.item, 'minecraft:dirt');
      expect(restored.interactors.containsKey((0, 0, 0)), isTrue);
    });

    test('writes the Java key layout', () {
      final nbt = contraption.writeNbt();

      final passenger = NbtMap.of(nbt.getList('Passengers').single);
      expect(passenger['Id']!.kind, NbtKind.intArray);
      expect(passenger.getUuid('Id'), _uuid);
      expect(passenger.getInt('Seat'), 0);

      final sub = NbtMap.of(nbt.getList('SubContraptions').single);
      expect(sub['Id']!.kind, NbtKind.intArray);
      expect(sub.getUuid('Id'), _uuid2);
      expect(sub.contains('Pos'), isFalse);
      expect(sub.contains('Face'), isFalse);
      final location = sub.getCompound('Location');
      expect(location.getBlockPos('pos'), (5, 6, 7));
      expect(location.getString('direction'), 'north');

      final glue = NbtMap.of(nbt.getList('Superglue').single);
      expect(glue.contains('From'), isTrue);
      expect(glue.contains('To'), isTrue);
      expect(glue.getVec('From'), (0.0, 0.0, 0.0));
      expect(glue.getVec('To'), (1.0, 2.0, 3.0));
      expect(glue.contains('minX'), isFalse);

      final seat = NbtMap.of(nbt.getList('Seats').single);
      expect(seat['Pos']!.kind, NbtKind.intArray);
      expect(seat.getBlockPos('Pos'), (2, 3, 4));
    });

    test('spawn data uses the update tag as the block data', () {
      final nbt = contraption.writeNbt(spawnPacket: true);
      final blockList = NbtMap.of(nbt['Blocks']!).getList('BlockList');
      final entry = NbtMap.of(
        blockList.firstWhere((v) => NbtMap.of(v).getInt('Pos') == 0),
      );
      expect(entry.getCompound('Data').getInt('Tag'), 1);
      expect(entry.contains('UpdateTag'), isFalse);
      expect(entry.contains('Legacy'), isFalse);
    });

    test('spawn data marks blocks saved before update tags as legacy', () {
      contraption.updateTags.remove((0, 0, 0));
      final nbt = contraption.writeNbt(spawnPacket: true);
      final blockList = NbtMap.of(nbt['Blocks']!).getList('BlockList');
      final entry = NbtMap.of(
        blockList.firstWhere((v) => NbtMap.of(v).getInt('Pos') == 0),
      );
      expect(entry.getCompound('Data').getInt('Value'), 42);
      expect(entry.contains('Legacy'), isTrue);
    });
  });

  group('movement context NBT', () {
    test('round trips motion, position, stall and data', () {
      final level = _MapLevel({(0, 0, 0): _stone});
      final contraption = Contraption();
      final info = const StructureBlockInfo((0, 0, 0), _stone);
      final context = MovementContext(level, level.worldId, info, contraption)
        ..motion = (1, 2, 3)
        ..relativeMotion = (4, 5, 6)
        ..position = (7, 8, 9)
        ..stall = true
        ..firstMovement = false
        ..data = (NbtMap()..putInt('A', 1));

      final nbt = NbtMap();
      context.writeToNbt(nbt);
      final restored = MovementContext.readNbt(
        level,
        level.worldId,
        info,
        nbt,
        contraption,
      );

      expect(restored.motion, (1.0, 2.0, 3.0));
      expect(restored.relativeMotion, (4.0, 5.0, 6.0));
      expect(restored.position, (7.0, 8.0, 9.0));
      expect(restored.stall, isTrue);
      expect(restored.firstMovement, isFalse);
      expect(restored.data.getInt('A'), 1);
    });

    test('a missing position stays null', () {
      final level = _MapLevel({(0, 0, 0): _stone});
      final contraption = Contraption();
      final info = const StructureBlockInfo((0, 0, 0), _stone);
      final restored = MovementContext.readNbt(
        level,
        level.worldId,
        info,
        NbtMap(),
        contraption,
      );
      expect(restored.position, isNull);
      expect(restored.motion, vec3Zero);
      expect(restored.firstMovement, isFalse);
    });
  });

  group('mounted storage codec', () {
    setUpAll(MountedStorages.installDefaults);

    test('ItemSlots.CODEC keeps non-empty slots and the size', () {
      final handler = ItemStackHandler(3)
        ..stacks[1] = const StoredStack('minecraft:stone', 5);

      final nbt = handler.serializeItemSlots();
      expect(nbt.getInt('size'), 3);
      expect(nbt.getCompound('items').keys, ['1']);
      expect(nbt.getCompound('items').getCompound('1').getInt('count'), 5);

      final restored = ItemStackHandler.fromItemSlotsNbt(nbt);
      expect(restored.slots, 3);
      expect(restored.stackInSlot(1), const StoredStack('minecraft:stone', 5));
      expect(restored.stackInSlot(0).isEmpty, isTrue);
    });

    test('round trips a simple storage through the manager', () {
      final handler = ItemStackHandler(3)
        ..stacks[1] = const StoredStack('minecraft:stone', 5);
      final manager = MountedStorageManager()
        ..addItemStorage(
          SimpleMountedStorage(MountedStorages.simple, handler),
          (1, 2, 3),
        )
        ..initialize();

      final nbt = NbtMap();
      manager.write(nbt, clientPacket: false);

      final entry = NbtMap.of(nbt.getList('items').single);
      expect(entry.getBlockPos('pos'), (1, 2, 3));
      final storage = entry.getCompound('storage');
      expect(storage.getString('type'), 'create:simple');
      final value = storage.getCompound('value');
      expect(value.getInt('size'), 3);
      expect(
        value.getCompound('items').getCompound('1').getString('id'),
        'minecraft:stone',
      );

      final restored = MountedStorageManager()..read(nbt);
      final stack = restored.allItemStorages[(1, 2, 3)]!.stackInSlot(1);
      expect(stack, const StoredStack('minecraft:stone', 5));
    });

    test('round trips a toolbox with its filters', () {
      final handler = ItemStackHandler(32)
        ..stacks[0] = const StoredStack('minecraft:iron_pickaxe', 1);
      final filters = List<StoredStack>.filled(8, StoredStack.empty)
        ..[2] = const StoredStack('minecraft:iron_ingot', 1);
      final manager = MountedStorageManager()
        ..addItemStorage(
          ToolboxMountedStorage(
            MountedStorages.toolbox,
            handler,
            NbtMap(),
            filters,
          ),
          (0, 0, 0),
        )
        ..initialize();

      final nbt = NbtMap();
      manager.write(nbt, clientPacket: false);

      final value = NbtMap.of(nbt.getList('items').single)
          .getCompound('storage')
          .getCompound('value');
      expect(value.getCompound('items').getInt('size'), 32);
      expect(value.getList('filters'), hasLength(8));

      final restored = MountedStorageManager()..read(nbt);
      final toolbox =
          restored.allItemStorages[(0, 0, 0)]! as ToolboxMountedStorage;
      expect(toolbox.stackInSlot(0).item, 'minecraft:iron_pickaxe');
      expect(toolbox.filters[2].item, 'minecraft:iron_ingot');
    });

    test('round trips the depot, creative crate and tanks', () {
      final manager = MountedStorageManager()
        ..addItemStorage(
          DepotMountedStorage(
            MountedStorages.depot,
            const StoredStack('minecraft:diamond', 2),
          ),
          (0, 0, 0),
        )
        ..addItemStorage(
          CreativeCrateMountedStorage(
            MountedStorages.creativeCrate,
            const StoredStack('minecraft:oak_log', 1),
          ),
          (1, 0, 0),
        )
        ..addFluidStorage(
          FluidTankMountedStorage(
            MountedStorages.fluidTank,
            1000,
            const StoredFluid('minecraft:water', 500),
          ),
          (2, 0, 0),
        )
        ..addFluidStorage(
          CreativeFluidTankMountedStorage(
            MountedStorages.creativeFluidTank,
            2000,
            const StoredFluid('minecraft:lava', 1000),
          ),
          (3, 0, 0),
        )
        ..initialize();

      final nbt = NbtMap();
      manager.write(nbt, clientPacket: false);

      final items = {
        for (final v in nbt.getList('items'))
          NbtMap.of(v).getBlockPos('pos'): NbtMap.of(v).getCompound('storage'),
      };
      expect(
        items[(0, 0, 0)]!.getCompound('value').getString('id'),
        'minecraft:diamond',
      );
      expect(
        items[(1, 0, 0)]!.getCompound('value').getString('id'),
        'minecraft:oak_log',
      );

      final fluids = {
        for (final v in nbt.getList('fluids'))
          NbtMap.of(v).getBlockPos('pos'): NbtMap.of(v).getCompound('storage'),
      };
      expect(fluids[(2, 0, 0)]!.getInt('capacity'), 1000);
      expect(
        fluids[(2, 0, 0)]!.getCompound('fluid').getString('id'),
        'minecraft:water',
      );
      expect(fluids[(3, 0, 0)]!.getCompound('value').getInt('capacity'), 2000);
      expect(
        fluids[(3, 0, 0)]!
            .getCompound('value')
            .getCompound('fluid')
            .getString('id'),
        'minecraft:lava',
      );

      final restored = MountedStorageManager()..read(nbt);
      expect(
        restored.allItemStorages[(0, 0, 0)]!.stackInSlot(0),
        const StoredStack('minecraft:diamond', 2),
      );
      expect(
        restored.allItemStorages[(1, 0, 0)]!.stackInSlot(0),
        const StoredStack('minecraft:oak_log', 64),
      );
      expect(
        restored.fluidStorages[(2, 0, 0)]!.fluidInTank(0),
        const StoredFluid('minecraft:water', 500),
      );
      expect(
        restored.fluidStorages[(3, 0, 0)]!.fluidInTank(0).fluid,
        'minecraft:lava',
      );
    });

    test('reads the legacy Storage and FluidStorage lists', () {
      final legacy = NbtMap()
        ..putList('Storage', [
          (NbtMap()
                ..putBlockPos('Pos', (1, 2, 3))
                ..putCompound(
                  'Data',
                  NbtMap()
                    ..putInt('Size', 2)
                    ..putList('Items', [
                      (NbtMap()
                            ..putInt('Slot', 0)
                            ..putString('id', 'minecraft:stone')
                            ..putInt('count', 4))
                          .toValue(),
                    ]),
                ))
              .toValue(),
        ])
        ..putList('FluidStorage', [
          (NbtMap()
                ..putBlockPos('Pos', (4, 5, 6))
                ..putCompound(
                  'Data',
                  NbtMap()
                    ..putInt('Capacity', 800)
                    ..putString('id', 'minecraft:water')
                    ..putInt('amount', 300),
                ))
              .toValue(),
        ]);

      final manager = MountedStorageManager()..read(legacy);
      expect(
        manager.allItemStorages[(1, 2, 3)]!.stackInSlot(0),
        const StoredStack('minecraft:stone', 4),
      );
      expect(
        manager.fluidStorages[(4, 5, 6)]!.fluidInTank(0),
        const StoredFluid('minecraft:water', 300),
      );
    });
  });

  // `OrientedContraptionEntity`'s `InitialOrientation` (and the minecart item's
  // copy of it): Java writes `Direction.name()` and reads it with `readEnum`, so
  // the intended direction must come back instead of the fallback `down`.
  group('InitialOrientation', () {
    test('the Java name resolves to the intended direction, not the fallback', () {
      expect(initialOrientationNbtName(Direction.north), 'NORTH');
      expect(initialOrientationFromNbt('NORTH'), Direction.north);
      expect(
        initialOrientationFromNbt('NORTH'),
        isNot(Direction.values.first),
      );
    });

    test('a vertical direction writes no key', () {
      expect(initialOrientationNbtName(Direction.up), isNull);
      expect(initialOrientationNbtName(Direction.down), isNull);
    });

    test('an unknown name falls back to the first constant, as readEnum', () {
      expect(initialOrientationFromNbt('sideways'), Direction.down);
    });

    test('the minecart item writes the same Java name', () {
      expect(minecartInitialOrientationNbtName(Direction.east), 'EAST');
      expect(
        initialOrientationFromNbt(
          minecartInitialOrientationNbtName(Direction.east),
        ),
        Direction.east,
      );
    });
  });
}

/// A moving interaction that the interactor round trip can find.
final class _TestInteraction extends MovingInteractionBehaviour {
  const _TestInteraction();
}
