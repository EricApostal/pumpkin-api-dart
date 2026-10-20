// Pure tests for the funnel / depot decisions: the filter that gates extraction, which belt
// funnel above a depot may take its output, and the weighted ejector's lid chase.
// Java references: `InvManipulationBehaviour.getFilterTest`, `FunnelBlockEntity.getAmountToExtract`
// / `getModeToExtract`, `DirectBeltInputBehaviour.tryExportingToBeltFunnel`,
// `EjectorBlockEntity.tick`.
import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/direction.dart';
import 'package:create/src/conveyance/items/inventory.dart';
import 'package:create/src/conveyance/items/item_data.dart';
import 'package:create/src/conveyance/transport/depot/ejector_lid.dart';
import 'package:create/src/conveyance/transport/funnel/funnel_logic.dart';
import 'package:test/test.dart';

ItemValue item(String key, int count) => ItemValue(key, count);

void main() {
  group('filtered extraction', () {
    test('only stacks the filter accepts leave the inventory', () async {
      final inv = ListInventory(3)
        ..setStack(0, item('minecraft:cobblestone', 16))
        ..setStack(1, item('minecraft:iron_ingot', 8))
        ..setStack(2, item('minecraft:cobblestone', 4));

      // `InvManipulationBehaviour.getFilterTest`: `customFilter.and(filter::test)`.
      final extracted = await extractMatching(
        inv,
        (s) => s.key == 'minecraft:iron_ingot',
        ExtractionCountMode.upTo,
        64,
      );

      expect(extracted.key, 'minecraft:iron_ingot');
      expect(extracted.count, 8);
      expect(inv.getStack(1).isEmpty, isTrue);
      // The rejected cobblestone is untouched.
      expect(inv.getStack(0).count, 16);
      expect(inv.getStack(2).count, 4);
    });

    test('a filter that rejects everything extracts nothing', () async {
      final inv = ListInventory(1)..setStack(0, item('minecraft:cobblestone', 4));

      final extracted = await extractMatching(
        inv,
        (_) => false,
        ExtractionCountMode.upTo,
        64,
      );

      expect(extracted.isEmpty, isTrue);
      expect(inv.getStack(0).count, 4);
    });

    test('a simulation leaves the inventory alone', () async {
      final inv = ListInventory(1)..setStack(0, item('minecraft:iron_ingot', 8));

      final peek = await extractMatching(
        inv,
        (s) => s.key == 'minecraft:iron_ingot',
        ExtractionCountMode.upTo,
        64,
        simulate: true,
      );

      expect(peek.count, 8);
      expect(inv.getStack(0).count, 8);
    });
  });

  group('belt funnel eligibility', () {
    const pulling = BState('create:brass_belt_funnel', {
      'facing': 'north',
      'shape': 'pulling',
      'powered': 'false',
    });

    test('a pulling belt funnel facing the depot takes output', () {
      expect(beltFunnelTakesOutput(pulling, null), isTrue);
      expect(beltFunnelTakesOutput(pulling, Direction.north), isTrue);
    });

    test('a belt funnel of any other shape takes nothing', () {
      for (final shape in ['retracted', 'extended', 'pushing']) {
        expect(
          beltFunnelTakesOutput(pulling.setValue('shape', shape), null),
          isFalse,
          reason: shape,
        );
      }
    });

    test('the funnel has to face the requested side', () {
      expect(beltFunnelTakesOutput(pulling, Direction.south), isFalse);
    });

    test('a plain funnel above the depot takes nothing', () {
      const funnel = BState('create:brass_funnel', {
        'facing': 'north',
        'extracting': 'false',
        'powered': 'false',
      });
      expect(beltFunnelTakesOutput(funnel, null), isFalse);
    });

    test('a powered funnel still answers, so it is eligible but keeps the stack', () {
      // `tryExportingToBeltFunnel` returns the stack unchanged for a powered funnel instead of
      // `null`: the caller must not fall through to launching the item.
      expect(
        beltFunnelTakesOutput(pulling.setFlag('powered', true), null),
        isTrue,
      );
    });
  });

  group('extraction amount and mode', () {
    test('a funnel without amount support always takes 64', () {
      expect(
        funnelExtractionAmount(
          supportsAmount: false,
          filterActive: false,
          filterAmount: 7,
        ),
        64,
      );
    });

    test('an unfiltered extractor takes one item at a time', () {
      expect(
        funnelExtractionAmount(
          supportsAmount: true,
          filterActive: false,
          filterAmount: 7,
        ),
        1,
      );
    });

    test('a filtered extractor takes the configured amount', () {
      expect(
        funnelExtractionAmount(
          supportsAmount: true,
          filterActive: true,
          filterAmount: 7,
        ),
        7,
      );
    });

    test('EXACTLY only with an active filter on an amount funnel', () {
      expect(
        funnelExtractionMode(
          supportsAmount: true,
          filterActive: true,
          filterUpTo: false,
        ),
        ExtractionCountMode.exactly,
      );
      expect(
        funnelExtractionMode(
          supportsAmount: true,
          filterActive: true,
          filterUpTo: true,
        ),
        ExtractionCountMode.upTo,
      );
      expect(
        funnelExtractionMode(
          supportsAmount: true,
          filterActive: false,
          filterUpTo: false,
        ),
        ExtractionCountMode.upTo,
      );
      expect(
        funnelExtractionMode(
          supportsAmount: false,
          filterActive: true,
          filterUpTo: false,
        ),
        ExtractionCountMode.upTo,
      );
    });
  });

  group('ejector lid', () {
    test('launching opens the lid instead of closing it', () {
      // The regression: the lid used to be driven from 1 down to 0 while launching.
      expect(ejectorLidChase(0, 1, ejectorLidChaseSpeed), greaterThan(0));
      var value = 0.0;
      for (var i = 0; i < 5; i++) {
        value = ejectorLidChase(value, 1, ejectorLidChaseSpeed);
      }
      expect(value, closeTo(1 - 0.2 * 0.2 * 0.2 * 0.2 * 0.2, 1e-9));
    });

    test('the chase reaches the open threshold within a handful of ticks', () {
      var value = 0.0;
      var ticks = 0;
      while (value <= ejectorLidOpenThreshold) {
        value = ejectorLidChase(value, 1, ejectorLidChaseSpeed);
        ticks++;
        expect(ticks, lessThan(100));
      }
      // `1 - .2^n` passes `1 - 1/16` once `.2^n < 1/16`, i.e. on the second tick.
      expect(ticks, 2);
    });

    test('a zero chase speed leaves the value alone', () {
      expect(ejectorLidChase(.4, 0, 0), .4);
    });

    test('retracting pulls the lid down at the wind-up speed, clamped at zero', () {
      expect(ejectorLidRetract(1, .1), closeTo(.9, 1e-9));
      expect(ejectorLidRetract(.05, .1), 0);
    });

    test('a wind-up speed of zero never closes the lid', () {
      // Java only advances the lid while `state == RETRACTING`, so a stopped ejector keeps its
      // lid where it is; the recharge is therefore the wind-up, not a fixed delay.
      expect(ejectorLidRetract(.5, 0), .5);
    });
  });
}
