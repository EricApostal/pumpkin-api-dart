import 'dart:math';

import 'package:create/src/processing/common/stack.dart';
import 'package:create/src/processing/deployer/deployer_items.dart';
import 'package:create/src/processing/deployer/deployer_types.dart';
import 'package:create/src/processing/recipe/ingredient.dart';
import 'package:create/src/processing/recipe/recipe_book.dart';
import 'package:test/test.dart';

void main() {
  group('DeployerMode NBT', () {
    test('a missing mode reads back as PUNCH (Java reads constants[0])', () {
      // DeployerBlockEntity.readEnum returns the first constant for an unknown name, and
      // `Mode` declares PUNCH first.
      expect(DeployerMode.fromJavaName(null), DeployerMode.punch);
      expect(DeployerMode.fromJavaName(''), DeployerMode.punch);
      expect(DeployerMode.fromJavaName('SOMETHING_ELSE'), DeployerMode.punch);
    });

    test('the two written names round trip', () {
      expect(DeployerMode.fromJavaName('PUNCH'), DeployerMode.punch);
      expect(DeployerMode.fromJavaName('USE'), DeployerMode.use);
      expect(DeployerMode.use.javaName, 'USE');
      expect(DeployerMode.punch.javaName, 'PUNCH');
    });
  });

  group('upright items on a belt', () {
    final tags = MapTagLookup(
      items: {
        'create:upright_on_belt': {'create:blaze_cake', 'minecraft:lantern'},
        'create:not_upright_on_belt': {'minecraft:lantern'},
      },
    );

    test('fluid containers and tagged items stand upright', () {
      expect(isItemUprightStack(const PStack('minecraft:water_bucket', 1), tags), isTrue);
      expect(isItemUprightStack(const PStack('minecraft:glass_bottle', 1), tags), isFalse);
      expect(isItemUprightStack(const PStack('create:blaze_cake', 1), tags), isTrue);
    });

    test('not_upright_on_belt wins over the upright tag', () {
      expect(isItemUprightStack(const PStack('minecraft:lantern', 1), tags), isFalse);
    });

    test('an upright result keeps angle 180 instead of a random one', () {
      // BeltDeployerCallbacks.activate: `centered ? 180 : RANDOM.nextInt(360)`.
      for (var i = 0; i < 16; i++) {
        expect(
          transportedAngleFor(const PStack('minecraft:water_bucket', 1), tags, Random(i)),
          180,
        );
      }
      final angles = {
        for (var i = 0; i < 16; i++)
          transportedAngleFor(const PStack('minecraft:diamond', 1), tags, Random(i)),
      };
      expect(angles.length, greaterThan(1));
      expect(angles, isNot(contains(180)));
    });
  });

  group('crafting remainders', () {
    test('the container items give their container back', () {
      expect(craftingRemainderOf(const PStack('minecraft:water_bucket', 1))?.key, 'minecraft:bucket');
      expect(craftingRemainderOf(const PStack('minecraft:milk_bucket', 1))?.key, 'minecraft:bucket');
      expect(craftingRemainderOf(const PStack('minecraft:honey_bottle', 1))?.key, 'minecraft:glass_bottle');
      expect(craftingRemainderOf(const PStack('minecraft:ominous_bottle', 1))?.key, 'minecraft:glass_bottle');
    });

    test('the stews give their bowl back', () {
      for (final key in const [
        'minecraft:mushroom_stew',
        'minecraft:rabbit_stew',
        'minecraft:beetroot_soup',
        'minecraft:suspicious_stew',
      ]) {
        expect(craftingRemainderOf(PStack(key, 1))?.key, 'minecraft:bowl', reason: key);
      }
    });

    test('a modded remainder can be registered', () {
      craftingRemainderOverrides['test:flask'] = const PStack('test:empty_flask', 1);
      addTearDown(() => craftingRemainderOverrides.remove('test:flask'));
      expect(craftingRemainderOf(const PStack('test:flask', 1))?.key, 'test:empty_flask');
    });

    test('an item without a remainder has none', () {
      expect(craftingRemainderOf(const PStack('minecraft:diamond', 1)), isNull);
      expect(craftingRemainderOf(PStack.empty), isNull);
    });
  });

  group('automation policy', () {
    test('manual-only recipes are ignored', () {
      expect(ignoredInAutomation('create:cutting/andesite_manual_only'), isTrue);
      expect(ignoredInAutomation('create:cutting/andesite'), isFalse);
    });
  });
}
