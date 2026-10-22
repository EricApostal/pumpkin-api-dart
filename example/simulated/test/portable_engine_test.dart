// The portable engine's state machine, the fuel table and the block's placement
// rule. Pure: no host imports (the block entity file is the host glue and is not
// covered here).
import 'package:simulated/src/content/blocks/portable_engine/portable_engine_logic.dart';
import 'package:simulated/src/service/sim_services.dart';
import 'package:test/test.dart';

void main() {
  group('the fuel table', () {
    test('resolves the host cooking-fuel providers', () {
      // The values the host's own furnaces burn (`CookingFuelImpl`).
      expect(SimServices().host.burnTime('minecraft:coal'), 1600);
      expect(SimServices().host.burnTime('minecraft:charcoal'), 1600);
      expect(SimServices().host.burnTime('minecraft:coal_block'), 16000);
      expect(SimServices().host.burnTime('minecraft:lava_bucket'), 20000);
      expect(SimServices().host.burnTime('minecraft:blaze_rod'), 2400);
      expect(SimServices().host.burnTime('minecraft:oak_planks'), 300);
      expect(SimServices().host.burnTime('minecraft:oak_sapling'), 100);
      expect(SimServices().host.burnTime('minecraft:bamboo'), 50);
      expect(SimServices().host.burnTime('minecraft:diamond'), 0);
    });

    test('the superheated fuel is Create\'s data map', () {
      expect(SimServices().host.superheatedBurnTime('create:blaze_cake'), 3200);
      expect(SimServices().host.superheatedBurnTime('minecraft:coal'), 0);
    });
  });

  group('analogPower', () {
    test('is one step per ten seconds, 15 at the top', () {
      expect(analogPower(0), 0);
      expect(analogPower(1), 1);
      expect(analogPower(burnTimeThreshold), 2);
      expect(analogPower(burnTimeThreshold * 2 - 1), 2);
      expect(analogPower(burnTimeThreshold * 14), 15);
      expect(analogPower(burnTimeThreshold * 100), 15);
    });
  });

  group('burnTimeLabel', () {
    test('matches `getTime`', () {
      expect(burnTimeLabel(3), '3s');
      expect(burnTimeLabel(63), '1m 03s');
      expect(burnTimeLabel(3723), '1h 02m 03s');
      // Java's `getTime` pads the minutes but not the seconds once there are no
      // minutes left: 3600 s is `1h 00m 0s`.
      expect(burnTimeLabel(3600), '1h 00m 0s');
      expect(burnTimeLabel(600), '10m 00s');
    });
  });

  group('PortableEngineBurn', () {
    test('burns down, then takes the next item from the slot', () {
      final burn = PortableEngineBurn()..burnTime = 2;
      var consumed = 0;
      // Two ticks of the current item, no consumption yet.
      expect(burn.tick(nextFuelTicks: 1600, slotCount: 1, nextSuperHeated: false,
          consumeOne: () => consumed++), isFalse);
      expect(burn.burnTime, 1);
      // The last tick empties it and the next item is consumed.
      burn.tick(nextFuelTicks: 1600, slotCount: 1, nextSuperHeated: true, consumeOne: () => consumed++);
      expect(burn.burnTime, 1600);
      expect(burn.superHeated, isTrue, reason: 'the consumed item was superheated fuel');
      expect(consumed, 1);
      expect(burn.isLit, isTrue);
    });

    test('goes out when the slot is empty', () {
      final burn = PortableEngineBurn()..burnTime = 1;
      burn.tick(nextFuelTicks: 0, slotCount: 0, nextSuperHeated: false, consumeOne: () {});
      expect(burn.burnTime, 0);
      expect(burn.isLit, isFalse);
      expect(burn.superHeated, isFalse);
      expect(analogPower(burn.burnTime), 0);
    });

    test('the comparator output steps when the fuel crosses a threshold', () {
      final burn = PortableEngineBurn()..burnTime = burnTimeThreshold * 2;
      final changed = burn.tick(nextFuelTicks: 0, slotCount: 0, nextSuperHeated: false, consumeOne: () {});
      expect(changed, isTrue, reason: '$burnTimeThreshold * 2 is the last tick of step 3');
      expect(analogPower(burn.burnTime), 2);
    });

    test('infinite fuel is a month', () {
      final burn = PortableEngineBurn()..burnTime = infiniteBurnThreshold;
      expect(burn.isCurrentFuelInfinite, isTrue);
      expect(burn.isTotalFuelInfinite(0), isTrue);
      expect(burn.isTotalFuelInfinite(infiniteBurnThreshold), isTrue);
      expect(PortableEngineBurn().isTotalFuelInfinite(20000), isFalse);
    });

    test('a creative blaze cake superheats, then puts it out, then feeds it forever', () {
      final burn = PortableEngineBurn();
      burn.applyCreativeBlazeCake();
      expect(burn.isCurrentFuelInfinite, isTrue);
      burn.applyCreativeBlazeCake();
      expect(burn.superHeated, isTrue);
      burn.applyCreativeBlazeCake();
      expect(burn.burnTime, 0);
      expect(burn.superHeated, isFalse);
    });

    test('the generated speed follows the direction, the facing and the heat', () {
      final burn = PortableEngineBurn()..burnTime = 100;
      // The positive side of the axis, scroll box at 0: +32.
      expect(burn.generatedSpeed(0, 1), 32);
      // The negative side: -32.
      expect(burn.generatedSpeed(0, -1), -32);
      // Scroll box above 0 reverses.
      expect(burn.generatedSpeed(1, 1), -32);
      // Superheated doubles.
      burn.superHeated = true;
      expect(burn.generatedSpeed(0, 1), 64);
      // Out of fuel: nothing.
      burn.burnTime = 0;
      expect(burn.generatedSpeed(0, 1), 0);
    });

    test('the direction is corrected when it would fight the network', () {
      final burn = PortableEngineBurn()..burnTime = 100;
      // Turning with the network: nothing to do.
      expect(burn.directionFix(movementDirection: 0, speed: 32, directionSign: 1), isNull);
      // Turning against it: the scroll box moves one step.
      expect(burn.directionFix(movementDirection: 0, speed: -32, directionSign: 1), 1);
      // The scroll box cycles through `MovementMode.values()`.
      expect(burn.directionFix(movementDirection: movementModeCount - 1, speed: 64, directionSign: 1), 0);
      // Not lit, or not turning: nothing.
      burn.burnTime = 0;
      expect(burn.directionFix(movementDirection: 0, speed: -32, directionSign: 1), isNull);
    });
  });
}