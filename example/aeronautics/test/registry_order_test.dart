// The Aeronautics registry: the Java order, and the state properties a Java
// client numbers.
//
// `CreateRegistry`, `CreateBlock` and `CreateProps` are behind
// `package:pumpkin_api/pumpkin_api.dart`, which is wasm-only (its
// `bindings.g.dart` uses `dart:wasm` types), so a VM test cannot call
// `registerAeronautics` or read a `CreateBlock`. This file checks the pure tables
// the ids are pinned against (`index/aero_java_order.dart`), and
// `AeronauticsModule.register` runs the same tables against the blocks it builds
// (`aeronautics_module.dart`, `checkAeroStateProperties`) at load.
//
// The Java line numbers are of
// `aeronautics/common/src/main/java/dev/eriksonn/aeronautics/index/` unless the
// file says otherwise.
import 'package:aeronautics/src/index/aero_java_order.dart';
import 'package:aeronautics/src/plugin/aeronautics_addon.dart';
import 'package:test/test.dart';

/// The number of states a block has: the product of its value counts.
int statesOf(String key) {
  final properties = AeroJavaOrder.propertiesOf(key)!;
  var states = 1;
  for (final values in properties.values) {
    expect(values, isNotEmpty, reason: '$key: $values');
    states *= values.length;
  }
  return states;
}

void main() {
  group('the Java order tables', () {
    test('the addon names the registries its content goes into', () {
      // Not cosmetic. The host numbers what a plugin registers by position
      // (`vanilla count + index`) and writes that id on the wire, so an addon that
      // declares its channels only leaves the client on its *own* order: the
      // registry is dropped from the sync, the host keeps handing out ids, and a
      // client that has the mod resolves each one to a different entry — the
      // "adding an item gives a different item" divergence. Naming `minecraft:item`
      // and the rest is what makes the host send them, and the names are the tables
      // this file pins.
      expect(const AeronauticsAddon().contentVerified, isTrue);
    });

    test('hold every entry, with no duplicate', () {
      expect(AeroJavaOrder.blocks.length, 43, reason: 'AeroBlocks.java:73-413 + the fluid block');
      expect(AeroJavaOrder.items.length, 46, reason: 'AeroBlocks.java + AeroItems.java:21,40,55');
      expect(AeroJavaOrder.blockEntityTypes.length, 9, reason: 'AeroBlockEntityTypes.java:35-80');
      expect(AeroJavaOrder.entityTypes.length, 2, reason: 'AeroEntityTypes.java:23,37');
      expect(AeroJavaOrder.dataComponents.length, 2, reason: 'AeroDataComponents.java:16-20');
      for (final table in [
        AeroJavaOrder.blocks,
        AeroJavaOrder.items,
        AeroJavaOrder.blockEntityTypes,
        AeroJavaOrder.entityTypes,
        AeroJavaOrder.dataComponents,
      ]) {
        expect(table.toSet().length, table.length);
        for (final key in table) {
          expect(key, startsWith('aeronautics:'), reason: key);
        }
      }
    });

    test('expand the dyed families in DyeColor order', () {
      expect(aeroDyeColorOrder, [
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
      expect(AeroJavaOrder.blocks.take(16), [
        'aeronautics:white_envelope',
        for (final colour in aeroDyeColorOrder)
          if (colour != 'white') 'aeronautics:${colour}_envelope',
      ], reason: 'AeroBlocks.java:107-118 returns WHITE_ENVELOPE_BLOCK for white');
      expect(AeroJavaOrder.blocks.skip(16).take(16), [
        for (final colour in aeroDyeColorOrder) 'aeronautics:${colour}_envelope_encased_shaft',
      ]);
    });

    test('keep the block entity types of the blocks that have one', () {
      // The encased shaft has one shared type for its sixteen colours, so its
      // type id is not a block id; every other type is named after its block.
      for (final key in AeroJavaOrder.blockEntityTypes) {
        if (key == 'aeronautics:envelope_encased_shaft') continue;
        expect(AeroJavaOrder.blocks, contains(key), reason: key);
      }
      for (final colour in aeroDyeColorOrder) {
        expect(
          AeroJavaOrder.blocks,
          contains('aeronautics:${colour}_envelope_encased_shaft'),
          reason: colour,
        );
      }
      // The fluid block is not a block entity.
      expect(AeroJavaOrder.blockEntityTypes, isNot(contains('aeronautics:levitite_blend')));
    });

    test('list every registered block with its state properties', () {
      for (final key in AeroJavaOrder.blocks) {
        expect(AeroJavaOrder.propertiesOf(key), isNotNull, reason: key);
      }
      expect(AeroJavaOrder.propertiesOf('aeronautics:not_a_block'), isNull);
    });

    test('register each fluid pair source first, flowing variant last', () {
      // `AeroFluidsNeoForge.java:23-52` -> `FluidBuilder.java:597-614`: the source
      // enters the registry first and the flowing entry last, and Registrate names
      // the flowing entry `flowing_<name>` (`FluidBuilder.java:291`).
      expect(AeroJavaOrder.fluidOrder, [
        'aeronautics:levitite_blend',
        'aeronautics:flowing_levitite_blend',
      ]);
      for (final pair in AeroJavaOrder.fluidPairs) {
        expect(AeroJavaOrder.fluidOrder, containsAllInOrder([pair.still, pair.flowing]));
        expect(pair.flowing, 'aeronautics:flowing_${pair.still.split(':').last}');
        expect(pair.bucket, '${pair.still}_bucket');
        expect(AeroJavaOrder.blocks, contains(pair.block));
        expect(AeroJavaOrder.items, contains(pair.bucket));
      }
    });

    test('the fluid pair check accepts the table and rejects a reversed pair', () {
      // `fluidPairProblems` is what `AeronauticsModule.checkAeroFluidPairs` runs
      // against the real registry at load; here it is fed the table itself.
      final table = {
        for (final pair in AeroJavaOrder.fluidPairs) pair.still: pair.flowing,
        for (final pair in AeroJavaOrder.fluidPairs) pair.flowing: null,
      };
      expect(fluidPairProblems(table), isEmpty);
      final reversed = {
        for (final pair in AeroJavaOrder.fluidPairs) pair.flowing: null,
        for (final pair in AeroJavaOrder.fluidPairs) pair.still: pair.flowing,
      };
      expect(fluidPairProblems(reversed), isNotEmpty);
      expect(
        fluidPairProblems({'aeronautics:levitite_blend': 'aeronautics:flowing_levitite_blend'}),
        contains(contains('not registered')),
      );
    });
  });

  group('the state properties are the Java ones', () {
    test('aeronautics:adjustable_burner is POWERED + VARIANT', () {
      // `HotAirBurnerBlock extends Block` and adds `POWERED, VARIANT`
      // (`HotAirBurnerBlock.java:51-52,103-105`); the variants are `FIRE("fire")`
      // and `SOUL_FIRE("soulful")` (`:168-171`), and the light is
      // `POWERED ? 15 : 0` (`:58-60`). The port had `facing` and `lit` as well,
      // sixteen states, and every state id from `steam_vent` on was twelve off.
      expect(AeroJavaOrder.propertiesOf('aeronautics:adjustable_burner'), {
        'powered': ['true', 'false'],
        'variant': ['fire', 'soulful'],
      });
      expect(statesOf('aeronautics:adjustable_burner'), 4);
    });

    test('aeronautics:steam_vent is POWERED + WATERLOGGED + VARIANT + FACING', () {
      // `SteamVentBlock extends Block` (`SteamVentBlock.java:47`) with
      // `builder.add(POWERED, WATERLOGGED, VARIANT, FACING)` (`:60`); the variants
      // are `GOLD, IRON` (`:156-158`): 32 states.
      expect(AeroJavaOrder.propertiesOf('aeronautics:steam_vent'), {
        'facing': ['north', 'south', 'west', 'east'],
        'powered': ['true', 'false'],
        'variant': ['gold', 'iron'],
        'waterlogged': ['true', 'false'],
      });
      expect(statesOf('aeronautics:steam_vent'), 32);
    });

    test('the envelopes have no state of their own', () {
      // `EnvelopeBlock extends CasingBlock extends Block`
      // (`EnvelopeBlock.java:37`, `CasingBlock.java:9`): one state. The encased
      // shaft is a pillar (`EnvelopeEncasedShaftBlock.java:35`): three.
      for (final colour in aeroDyeColorOrder) {
        expect(AeroJavaOrder.propertiesOf('aeronautics:${colour}_envelope'), isEmpty, reason: colour);
        expect(
          AeroJavaOrder.propertiesOf('aeronautics:${colour}_envelope_encased_shaft'),
          {'axis': ['x', 'y', 'z']},
          reason: colour,
        );
      }
    });

    test('the propellers and the cannon carry what the Java adds', () {
      // `BasePropellerBlock extends DirectionalKineticBlock`
      // (`BasePropellerBlock.java:23`) plus `REVERSED` (`:34`): 12 states.
      for (final key in ['aeronautics:andesite_propeller', 'aeronautics:wooden_propeller']) {
        expect(statesOf(key), 12, reason: key);
      }
      // `SmartPropellerBlock extends HorizontalAxisKineticBlock` (`:24`) plus
      // `REVERSED, CEILING` (`:35-36`): 8 states.
      expect(statesOf('aeronautics:smart_propeller'), 8);
      // `MountedPotatoCannonBlock extends DirectionalAxisKineticBlock` (`:31`)
      // plus `POWERED, BLOCKED` (`:108`): 48 states.
      expect(statesOf('aeronautics:mounted_potato_cannon'), 48);
      // Both bearings are plain `BearingBlock`s (`:23,24`): 6 states.
      expect(statesOf('aeronautics:propeller_bearing'), 6);
      expect(statesOf('aeronautics:gyroscopic_propeller_bearing'), 6);
      // The levitite blocks are `Block::new` (`AeroBlocks.java:382,402`): one state
      // each. The fluid block is a vanilla `LiquidBlock` with `LEVEL` 0..15
      // (`LiquidBlock.java:39,225`, `BlockStateProperties.java:116`): sixteen.
      expect(statesOf('aeronautics:levitite'), 1);
      expect(statesOf('aeronautics:pearlescent_levitite'), 1);
      expect(statesOf('aeronautics:levitite_blend'), 16);
      expect(AeroJavaOrder.propertiesOf('aeronautics:levitite_blend'), {
        'level': [for (var level = 0; level <= 15; level++) '$level'],
      });
    });

    test('the state count of the whole mod', () {
      // The sum is what a client has to know before it can number the states of
      // the `simulated:` and `create:` blocks that come after `aeronautics:` ones
      // in the same world, and it is the sum the port must register.
      var total = 0;
      for (final key in AeroJavaOrder.blocks) {
        total += statesOf(key);
      }
      expect(total, 16 + 16 * 3 + 4 + 32 + 6 + 6 + 8 + 12 + 12 + 48 + 1 + 1 + 16);
      expect(total, 210);
    });
  });
}