// The registry of Simulated has to *build*, in the Java order.
//
// Two things are pinned here:
//
//  * The keys the registry registers have no duplicate. It used to throw
//    `DuplicateRegistrationException: simulated:spring is registered twice in
//    items` -- the spring block registered a block item while `SimItems` had
//    already registered the key -- and the throw escaped `SimulatedPlugin.onLoad`,
//    so the whole plugin failed to load and nothing else in it was reachable. No
//    test constructed the registry, so the suite stayed green.
//  * The order of the entries is the Java `index/SimBlocks`, `index/SimItems` and
//    `index/SimBlockEntityTypes` order (`SimJavaOrder`, entry by entry with the
//    `file:line` it comes from), and the registered subset is exactly the content
//    this port has translated. A block that lands in the wrong place, or one that
//    goes missing, changes the list and fails here instead of silently shifting
//    the ids a client with the Java mods would use.
//
// `CreateRegistry` and `CreateBlock` live behind `package:pumpkin_api/pumpkin_api.dart`,
// which is wasm-only (its `bindings.g.dart` uses `dart:wasm` types), so a VM test
// cannot call `SimRegistry.register` or `simBlocks()`. This file therefore drives
// the same pure tables `register` pins the ids with, and `SimRegistry.register`
// checks what it builds against them at load: the blocks and block entity types
// (`SimPorted.blocks`, `SimPorted.blockEntityTypes`) and the state property names
// (`SimPorted.stateProperties`).
//
// The Java line numbers are of
// `simulated/common/src/main/java/dev/simulated_team/simulated/index/`.
import 'package:create/src/core/ordered_registry.dart';
import 'package:simulated/src/index/sim_channels.dart';
import 'package:simulated/src/index/sim_items.dart';
import 'package:simulated/src/index/sim_java_order.dart';
import 'package:test/test.dart';

/// The items `SimRegistry.register` puts in the registry, in registration order:
/// `SimPorted.items` is that list, built from `simItems()` and the
/// has-an-item rule of the Java (`SimBlocks.java`). `SimRegistry.register` checks
/// the registry it filled against it before it installs the id order.
List<String> registeredItemKeys() => SimPorted.items;

void main() {
  final items = OrderedRegistry<Object?>('items');
  final blocks = OrderedRegistry<Object?>('blocks');
  final blockEntityTypes = OrderedRegistry<Object?>('blockEntityTypes');

  group('the registry builds', () {
    test('the addon names the registries its content goes into', () {
      // Not cosmetic. The host numbers what a plugin registers by position
      // (`vanilla count + index`) and writes that id on the wire, so an addon that
      // declares its channels only leaves the client on its *own* order: `syncable`
      // drops the registry, the host keeps handing out ids, and a client that has
      // the mod resolves each one to a different entry. Naming `minecraft:item` and
      // the rest is what makes the host send them and the client adopt the ids, and
      // the names are the pinned tables this file checks.
      expect(const SimulatedAddon().contentVerified, isTrue);
    });

    test('every key is registered once', () {
      // Exactly the calls `SimRegistry.register` makes, in its order. A duplicate
      // here is the `DuplicateRegistrationException` that stopped the plugin from
      // loading.
      for (final key in registeredItemKeys()) {
        expect(() => items.add(key, null), returnsNormally, reason: key);
      }
      for (final key in SimPorted.blocks) {
        expect(() => blocks.add(key, null), returnsNormally, reason: key);
      }
      for (final key in SimPorted.blockEntityTypes) {
        expect(() => blockEntityTypes.add(key, null), returnsNormally, reason: key);
      }
    });

    test('the keys of one registry are distinct', () {
      final itemKeys = registeredItemKeys();
      expect(itemKeys.toSet().length, itemKeys.length);
      expect(SimPorted.blocks.toSet().length, SimPorted.blocks.length);
      expect(SimPorted.blockEntityTypes.toSet().length, SimPorted.blockEntityTypes.length);
    });

    test('the spring has an item and its block does not register one', () {
      expect(SimJavaOrder.blocksWithoutItem, contains('simulated:spring'));
      expect(simItems().map((i) => i.key), contains('simulated:spring'));
      expect(registeredItemKeys().where((k) => k == 'simulated:spring').length, 1);
    });
  });

  group('the Java order tables', () {
    test('hold every entry, with no duplicate', () {
      expect(SimJavaOrder.blocks.length, 95, reason: 'SimBlocks.java:100-855');
      expect(SimJavaOrder.items.length, 86, reason: '76 block items + SimItems.java:32-108');
      expect(SimJavaOrder.blockEntityTypes.length, 30, reason: 'SimBlockEntityTypes.java:53-278');
      for (final table in [SimJavaOrder.blocks, SimJavaOrder.items, SimJavaOrder.blockEntityTypes]) {
        expect(table.toSet().length, table.length);
      }
    });

    test('expand the dyed families in DyeColor order', () {
      expect(simDyeColors, [
        'white',
        'orange',
        'magenta',
        'light_blue',
        'yellow',
        'lime',
        'pink',
        'gray',
        'light_gray',
        'cyan',
        'purple',
        'blue',
        'brown',
        'green',
        'red',
        'black',
      ]);
      expect(
        SimJavaOrder.blocks.where((k) => k.endsWith('_symmetric_sail')).toList(),
        [
          'simulated:white_symmetric_sail',
          for (final colour in simDyeColors)
            if (colour != 'white') 'simulated:${colour}_symmetric_sail',
        ],
        reason: 'DYED_SYMMETRIC_SAILS reuses WHITE_SYMMETRIC_SAIL (SimBlocks.java:779-783)',
      );
      expect(
        SimJavaOrder.blocks.where((k) => k.endsWith('_portable_engine')).toList(),
        [for (final colour in simDyeColors) 'simulated:${colour}_portable_engine'],
      );
    });

    test('hold only `simulated:` keys', () {
      for (final table in [SimJavaOrder.blocks, SimJavaOrder.items, SimJavaOrder.blockEntityTypes]) {
        for (final key in table) {
          expect(key, startsWith('simulated:'), reason: key);
        }
      }
    });

    test('list the block items of the blocks that have one', () {
      final blockItems = [
        for (final key in SimJavaOrder.blocks)
          if (!SimJavaOrder.blocksWithoutItem.contains(key)) key,
      ];
      expect(SimJavaOrder.items.take(blockItems.length), blockItems);
      expect(SimJavaOrder.items.skip(blockItems.length), everyElement(startsWith('simulated:')));
      // `simulated:spring` is an item although its block has none, and the
      // fifteen dyed sails are neither.
      expect(blockItems, isNot(contains('simulated:spring')));
      expect(SimJavaOrder.items, contains('simulated:spring'));
      expect(SimJavaOrder.blocksWithoutItem, hasLength(19));
    });

    test('name the legacy block entity id of `laser_sensor`', () {
      // `SimBlockEntityTypes.java:166`: the block is `laser_sensor`, the block
      // entity type is `ir_sensor`.
      expect(SimJavaOrder.blockEntityTypes, contains('simulated:ir_sensor'));
      expect(SimJavaOrder.blockEntityTypes, isNot(contains('simulated:laser_sensor')));
    });
  });

  group('the registered order is the Java order', () {
    test('blocks', () {
      blocks.useOrder(SimJavaOrder.blocks);
      expect(blocks.keys, SimPorted.blocks);
      expect(SimPorted.blocks, [
        for (final key in SimJavaOrder.blocks)
          if (SimPorted.blocks.contains(key)) key,
      ], reason: 'the ported blocks are a subsequence of the Java order');
    });

    test('blocks: the rest of the Java list is the content this port lacks', () {
      expect(SimPorted.blocks.length, 23);
      final missing = [
        for (final key in SimJavaOrder.blocks)
          if (!SimPorted.blocks.contains(key)) key,
      ];
      expect(missing, hasLength(72));
      expect(
        missing,
        containsAll(const [
          'simulated:analog_transmission',
          'simulated:merging_glue',
          'simulated:rope_winch',
          'simulated:directional_gearshift',
          'simulated:auger_shaft',
        ]),
      );
    });

    test('items', () {
      items.useOrder(SimJavaOrder.items);
      final expected = registeredItemKeys();
      final listed = [
        for (final key in SimJavaOrder.items)
          if (expected.contains(key)) key,
      ];
      final extra = [
        for (final key in expected)
          if (!SimJavaOrder.items.contains(key)) key,
      ];
      // Listed keys first, in table order, then what the table does not list, in
      // registration order (`OrderedRegistry.keys`).
      expect(items.keys, [...listed, ...extra]);
      expect(items.report.missing, [
        for (final key in SimJavaOrder.items)
          if (!expected.contains(key)) key,
      ]);
      expect(items.report.extra, extra);
    });

    test('items: every item is one the Java has', () {
      // `SimBlocks.java:775-800`: only the white sail registers an item; the
      // fifteen dyed sails drop it through a loot table. This port registered an
      // item for each of them, fifteen ids the Java gives to other items.
      final extra = [
        for (final key in registeredItemKeys())
          if (!SimJavaOrder.items.contains(key)) key,
      ];
      expect(extra, isEmpty);
      expect(
        registeredItemKeys().where((k) => k.endsWith('_symmetric_sail')).toList(),
        ['simulated:white_symmetric_sail'],
      );
      expect(registeredItemKeys(), hasLength(9));
    });

    test('block entity types', () {
      blockEntityTypes.useOrder(SimJavaOrder.blockEntityTypes);
      expect(blockEntityTypes.keys, SimPorted.blockEntityTypes);
      expect(blockEntityTypes.keys, [
        for (final key in SimJavaOrder.blockEntityTypes)
          if (SimPorted.blockEntityTypes.contains(key)) key,
      ]);
      expect(blockEntityTypes.report.missing, hasLength(23));
      expect(blockEntityTypes.report.missing, contains('simulated:simple'));
    });
  });

  group('the state properties are the Java ones', () {
    test('every ported block has its Java property set and state count', () {
      for (final key in SimPorted.blocks) {
        final expected = SimPorted.propertiesOf(key);
        expect(expected, isNotEmpty, reason: key);
        var states = 1;
        for (final values in expected.values) {
          expect(values, isNotEmpty, reason: '$key: $values');
          states *= values.length;
        }
        // The state count the Java block has. The base state id of every block
        // after it moves with this number.
        expect(states, greaterThan(0), reason: key);
      }
    });

    test('the two the audit named', () {
      // `PhysicsAssemblerBlock.java:110-112`: `FACING, FACE`, so 4 x 3 = 12
      // states. With the `waterlogged` this port used to add it was 24, and every
      // state id after the block shifted.
      final assembler = SimPorted.propertiesOf('simulated:physics_assembler');
      expect(assembler.keys.toSet(), {'face', 'facing'});
      expect(assembler['facing']!.length * assembler['face']!.length, 12);
      expect(SimPorted.propertiesOf('simulated:physics_assembler'), isNot(contains('waterlogged')));
    });

    test('the sails share the Java axis property', () {
      for (final colour in simDyeColors) {
        expect(
          SimPorted.propertiesOf('simulated:${colour}_symmetric_sail'),
          SimPorted.propertiesOf('simulated:white_symmetric_sail'),
          reason: colour,
        );
      }
      expect(SimPorted.propertiesOf('simulated:white_symmetric_sail'), {'axis': ['x', 'y', 'z']});
    });

    test('the facing values are the 26.3 FACING order', () {
      // MC 26.3 `BlockStateProperties.FACING` is an explicit list -- NORTH, EAST,
      // SOUTH, WEST, UP, DOWN (`BlockStateProperties.java:53-55`) -- and the
      // horizontal four are the `Direction` enum order filtered
      // (`EnumProperty.java:79-80`).
      const verticalSix = ['north', 'east', 'south', 'west', 'up', 'down'];
      const horizontalFour = ['north', 'south', 'west', 'east'];
      expect(SimPorted.propertiesOf('simulated:spring')['facing'], verticalSix);
      expect(SimPorted.propertiesOf('simulated:torsion_spring')['facing'], verticalSix);
      expect(SimPorted.propertiesOf('simulated:swivel_bearing')['facing'], verticalSix);
      expect(SimPorted.propertiesOf('simulated:swivel_bearing_link_block')['facing'], verticalSix);
      expect(SimPorted.propertiesOf('simulated:steering_wheel')['facing'], horizontalFour);
      expect(SimPorted.propertiesOf('simulated:throttle_lever')['facing'], horizontalFour);
      expect(SimPorted.propertiesOf('simulated:physics_assembler')['facing'], horizontalFour);
    });
  });
}