import 'package:create/src/equipment/equipment_items.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

void main() {
  final tea = equipmentItem('builders_tea');

  test('builder tea is registered in stacks of 16', () {
    expect(tea.key, 'create:builders_tea');
    expect(tea.maxStackSize, 16);
  });

  test('builder tea is edible and grants haste', () {
    final byName = {for (final c in tea.components) c.name: c.bytes};
    // Both components decide edibility: `minecraft:food` is what the host's eat check reads and
    // `minecraft:consumable` is what gives the use its 42 ticks.
    expect(byName.keys, contains('minecraft:food'));
    expect(byName.keys, contains('minecraft:consumable'));

    final food = PacketReader(byName['minecraft:food']!);
    expect(food.readVarInt(), 1); // `food(1, 0.6, alwaysEdible)`
    expect(food.readFloat(), closeTo(0.6, 1e-6));
    expect(food.readBool(), isTrue);
    food.expectEnd();

    final consumable = PacketReader(byName['minecraft:consumable']!);
    // 42 ticks (`BuildersTeaItem.getUseDuration`), `UseAnimation.DRINK`.
    expect(consumable.readFloat(), closeTo(2.1, 1e-6));
    expect(consumable.readVarInt(), 2);
    // The consume sound is a `Holder<SoundEvent>`: the id plus one.
    expect(consumable.readVarInt(), VanillaIds.sounds.idOf('entity.generic.eat')! + 1);
    expect(consumable.readBool(), isTrue); // has_consume_particles
    expect(consumable.readVarInt(), 1); // one on-consume effect
    expect(consumable.readVarInt(), 0); // `apply_effects`
    expect(consumable.readVarInt(), 1); // one status effect
    expect(consumable.readVarInt(), VanillaIds.mobEffects.idOf('minecraft:haste'));
    expect(consumable.readVarInt(), 0); // amplifier
    expect(consumable.readVarInt(), 3 * 60 * 20); // 3:00
    expect(consumable.readBool(), isFalse); // ambient
    expect(consumable.readBool(), isFalse); // show particles
    expect(consumable.readBool(), isFalse); // show icon
    expect(consumable.readBool(), isFalse); // no hidden effect
    expect(consumable.readFloat(), 1.0); // probability
    consumable.expectEnd();
  });

  test('the tea has no food component without the encoders', () {
    expect(DataComponentCodec.supported, contains('minecraft:food'));
    expect(DataComponentCodec.supported, contains('minecraft:consumable'));
  });
}