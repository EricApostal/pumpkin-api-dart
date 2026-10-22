// `PotionFluidHandler`'s two directions over the item's `minecraft:potion_contents` component:
// emptying a potion bottle gives the potion's fluid (not water), and filling a bottle from a
// potion fluid gives a bottle that carries the potion (`PotionFluidHandler.java:63-71`, `:84-92`,
// `GenericItemFilling.java:116-126`).
import 'package:create/src/fluids/fluid_stack.dart';
import 'package:create/src/fluids/generic_item_fluid.dart';
import 'package:create/src/fluids/potion_data.dart';
import 'package:test/test.dart';

void main() {
  final rules = ItemFluidRules();
  const bottle = FluidItemSpec('minecraft:potion');

  /// A bottle item with the potion contents the client would send for [data].
  FluidItemSpec bottleOf(PotionFluidData data, [String key = 'minecraft:potion']) =>
      FluidItemSpec(key, 1, PotionContentsComponent.componentsOf(data));

  group('PotionContentsComponent', () {
    test('round trips a potion and its custom effects', () {
      const data = PotionFluidData(
        'minecraft:strong_healing',
        customEffects: [
          PotionEffectData('minecraft:absorption', duration: 300, amplifier: 2, ambient: true),
        ],
      );
      final read = PotionContentsComponent.read(
        PotionContentsComponent.encode(data),
        bottle: BottleType.regular,
      );
      expect(read.potion, 'minecraft:strong_healing');
      expect(read.customEffects, hasLength(1));
      expect(read.customEffects.single.effect, 'minecraft:absorption');
      expect(read.customEffects.single.duration, 300);
      expect(read.customEffects.single.amplifier, 2);
      expect(read.customEffects.single.ambient, isTrue);
    });

    test('a bottle without the component holds water', () {
      // `Items.POTION` defaults to `new PotionContents(Potions.WATER)`.
      final read = PotionContentsComponent.read(null, bottle: BottleType.splash);
      expect(read.potion, 'minecraft:water');
      expect(read.bottle, BottleType.splash);
      expect(read.customEffects, isEmpty);
    });

    test('unreadable bytes fall back to water instead of a wrong potion', () {
      final read = PotionContentsComponent.read(const [0x7f, 0x01], bottle: BottleType.regular);
      expect(read.potion, 'minecraft:water');
    });
  });

  group('emptying', () {
    final emptying = GenericItemEmptying(rules);

    test('a potion of healing gives its potion fluid, not water', () {
      final fluid = emptying.emptyItem(
        bottleOf(const PotionFluidData('minecraft:healing')),
        simulate: true,
      ).$1;
      expect(fluid.fluid, FluidKeys.potion);
      expect(fluid.amount, 250);
      expect(PotionFluidData.decode(fluid.data)?.potion, 'minecraft:healing');
    });

    test('a plain bottle gives plain water', () {
      final fluid = emptying.emptyItem(bottle, simulate: true).$1;
      expect(fluid.fluid, FluidKeys.water);
      expect(fluid.data, isNull);
      expect(fluid.amount, 250);
    });

    test('a splash water bottle gives a water potion fluid, not plain water', () {
      final fluid = emptying.emptyItem(
        bottleOf(
          const PotionFluidData('minecraft:water', bottle: BottleType.splash),
          'minecraft:splash_potion',
        ),
        simulate: true,
      ).$1;
      expect(fluid.fluid, FluidKeys.potion);
      final data = PotionFluidData.decode(fluid.data);
      expect(data?.potion, 'minecraft:water');
      expect(data?.bottle, BottleType.splash);
    });

    test('the bottle is replaced by a glass bottle', () {
      final (_, remainder, stack) = emptying.emptyItem(
        bottleOf(const PotionFluidData('minecraft:healing')),
        simulate: false,
      );
      expect(remainder.key, 'minecraft:glass_bottle');
      expect(stack.isEmpty, isTrue);
    });
  });

  group('filling', () {
    final filling = GenericItemFilling(rules);
    const glassBottle = FluidItemSpec('minecraft:glass_bottle');

    test('a potion fluid fills a bottle that carries the potion', () {
      final fluid = const PotionFluidData('minecraft:healing').toStack(250);
      final result = filling.fillItem(250, glassBottle, fluid).$1;
      expect(result.key, 'minecraft:potion');
      final data = PotionContentsComponent.read(
        result.component(PotionContentsComponent.key),
        bottle: BottleType.regular,
      );
      expect(data.potion, 'minecraft:healing');
    });

    test('water fills a bottle with the explicit water contents', () {
      final result = filling.fillItem(250, glassBottle, const FStack(FluidKeys.water, 250)).$1;
      expect(result.key, 'minecraft:potion');
      final bytes = result.component(PotionContentsComponent.key);
      expect(bytes, isNotNull, reason: '`PotionContents.createItemStack(POTION, WATER)`');
      expect(
        PotionContentsComponent.read(bytes, bottle: BottleType.regular).potion,
        'minecraft:water',
      );
    });

    test('a lingering potion fluid fills a lingering bottle', () {
      final fluid = const PotionFluidData('minecraft:poison', bottle: BottleType.lingering).toStack(250);
      final result = filling.fillItem(250, glassBottle, fluid).$1;
      expect(result.key, 'minecraft:lingering_potion');
      expect(
        PotionContentsComponent.read(
          result.component(PotionContentsComponent.key),
          bottle: BottleType.lingering,
        ).potion,
        'minecraft:poison',
      );
    });

    test('tea fills a builders tea, with no potion component', () {
      final result = filling.fillItem(250, glassBottle, const FStack(FluidKeys.tea, 250)).$1;
      expect(result.key, 'create:builders_tea');
      expect(result.component(PotionContentsComponent.key), isNull);
    });
  });
}