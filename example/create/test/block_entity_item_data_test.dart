// The item data of the tank and the schematicannon across break -> place, on the VM: the
// canonical layouts, `FluidTankItem.place`'s sanitising and the merge a placement does
// (`block_entity_item_data.dart`; the host side is `block_entity_item_data_host.dart` and needs
// the server).
import 'package:create/src/common/block_entity_item_data.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/fluids/fluid_stack.dart';
import 'package:create/src/fluids/nbt_util.dart';
import 'package:test/test.dart';

/// One block's saved NBT, as `FluidTankBlockEntity.write` produces it.
Map<String, NbtValue> tankSave({
  required int width,
  required int height,
  FStack fluid = FStack.empty,
}) => {
  'Window': const NbtValue.byte(1),
  'Size': NbtValue.int32(width),
  'Height': NbtValue.int32(height),
  'TankContent': fluidTankNbt(fluid),
  'Luminosity': const NbtValue.int32(0),
  'Boiler': const NbtValue.compound({
    'Supply': NbtValue.double64(0),
    'Engines': NbtValue.int32(0),
  }),
};

/// The fluid of a saved `TankContent`.
FStack fluidOf(Map<String, NbtValue> nbt) => readFluidTankNbt(nbt['TankContent']);

/// The number of a saved key.
int number(Map<String, NbtValue> nbt, String key) => nbt[key]!.value as int;

/// A break -> place of a tank block: what the drop stamps on the item, then what the placement
/// reads back (`FluidTankItem.place` + `TypedEntityData.loadInto`).
Map<String, NbtValue> breakAndPlace(
  Map<String, NbtValue> broken, {
  int capacityMultiplier = 1000,
}) {
  final item = BlockEntityItemData.encodeBlockEntityData(broken);
  final data = BlockEntityItemData.decodeBlockEntityData(item)!;
  // The fresh single tank: its own geometry is what rusts it as one block.
  final fresh = tankSave(width: 1, height: 1);
  return BlockEntityItemData.merge(
    fresh,
    BlockEntityItemData.sanitiseTankItemData(
      data,
      capacityMultiplier: capacityMultiplier,
    ),
  );
}

void main() {
  group('the saved NBT of a tank', () {
    test('drops the multiblock keys on the way into the item', () {
      final broken = {
        ...tankSave(width: 2, height: 3, fluid: const FStack('minecraft:water', 500)),
        'Controller': const NbtValue.intArray([4, 5, 6]),
        'LastKnownPos': const NbtValue.intArray([1, 2, 3]),
      };

      final item = BlockEntityItemData.sanitiseTankItemData(
        broken,
        capacityMultiplier: 1000,
      );

      for (final key in BlockEntityItemData.tankStrippedKeys) {
        expect(item.containsKey(key), isFalse, reason: key);
      }
      expect(item.keys, containsAll(['Window', 'TankContent', 'Boiler']));
    });

    test('clamps the contents of a multiblock to one block', () {
      final controller = BlockEntityItemData.sanitiseTankItemData(
        {'TankContent': fluidTankNbt(const FStack('minecraft:water', 4000))},
        capacityMultiplier: 1000,
      );

      expect(fluidOf(controller), const FStack('minecraft:water', 1000));
    });

    test('leaves contents that fit alone', () {
      final single = BlockEntityItemData.sanitiseTankItemData(
        {'TankContent': fluidTankNbt(const FStack('minecraft:lava', 250))},
        capacityMultiplier: 1000,
      );

      expect(fluidOf(single), const FStack('minecraft:lava', 250));
    });
  });

  group('the placement merge', () {
    test('the item wins per key and two compounds merge key by key', () {
      final fresh = {
        'Size': const NbtValue.int32(1),
        'TankContent': NbtValue.emptyCompound(),
        'Boiler': const NbtValue.compound({
          'Supply': NbtValue.double64(0),
          'Engines': NbtValue.int32(0),
        }),
      };
      final item = {
        'TankContent': fluidTankNbt(const FStack('minecraft:water', 500)),
        'Boiler': const NbtValue.compound({'Engines': NbtValue.int32(2)}),
      };

      final merged = BlockEntityItemData.merge(fresh, item);

      expect(number(merged, 'Size'), 1);
      expect(fluidOf(merged), const FStack('minecraft:water', 500));
      final boiler = merged['Boiler']!.asCompound;
      expect(boiler['Engines']!.value, 2);
      expect(boiler['Supply']!.value, 0.0);
    });
  });

  group('the block_entity_data component', () {
    test('round trips the saved NBT with the type id the host writes', () {
      final nbt = tankSave(
        width: 1,
        height: 1,
        fluid: const FStack('minecraft:water', 500),
      );

      final bytes = BlockEntityItemData.encodeBlockEntityData(nbt);
      final back = BlockEntityItemData.decodeBlockEntityData(bytes)!;

      expect(bytes[0], 0);
      expect(back.keys, nbt.keys);
      expect(fluidOf(back), const FStack('minecraft:water', 500));
      expect(number(back, 'Size'), 1);
    });

    test('a value the host did not write reads as null', () {
      expect(BlockEntityItemData.decodeBlockEntityData(const []), isNull);
    });
  });

  group('the schematicannon options', () {
    test('an item without the component places the default (2, true, false)', () {
      expect(BlockEntityItemData.cannonOptions(null), defaultCannonOptions);
      expect(defaultCannonOptions.replaceMode, 2);
      expect(defaultCannonOptions.skipMissing, isTrue);
      expect(defaultCannonOptions.replaceBlockEntities, isFalse);
    });

    test('round trips the three fields as an int and two bools', () {
      final bytes = BlockEntityItemData.encodeCannonOptions(0, false, true);
      expect(bytes, [0, 0, 0, 0, 0, 1]);
      expect(BlockEntityItemData.cannonOptions(bytes), (
        replaceMode: 0,
        skipMissing: false,
        replaceBlockEntities: true,
      ));
    });
  });

  group('break -> place', () {
    test('a single tank keeps its fluid', () {
      final placed = breakAndPlace(
        tankSave(width: 1, height: 1, fluid: const FStack('minecraft:water', 500)),
      );

      expect(fluidOf(placed), const FStack('minecraft:water', 500));
      expect(number(placed, 'Size'), 1);
      expect(number(placed, 'Height'), 1);
    });

    test('a controller comes back as one tank with the clamped fluid', () {
      final placed = breakAndPlace(
        tankSave(
          width: 2,
          height: 2,
          fluid: const FStack('minecraft:water', 3000),
        ),
      );

      expect(fluidOf(placed), const FStack('minecraft:water', 1000));
      expect(number(placed, 'Size'), 1);
      expect(number(placed, 'Height'), 1);
      expect(placed.containsKey('Controller'), isFalse);
    });

    test('an empty tank stays empty', () {
      final placed = breakAndPlace(tankSave(width: 1, height: 1));

      expect(fluidOf(placed).isEmpty, isTrue);
    });
  });
}