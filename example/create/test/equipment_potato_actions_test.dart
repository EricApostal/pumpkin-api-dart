import 'package:create/src/equipment/potato/potato_model.dart';
import 'package:test/test.dart';

void main() {
  test('food effects keep the per-effect probability', () {
    const json =
        '{"damage":1,"items":"minecraft:apple","on_entity_hit":{'
        '"type":"create:food_effects","food_property":{"effects":['
        '{"effect":{"id":"minecraft:poison","duration":100},"probability":0.5},'
        '{"effect":{"id":"minecraft:hunger","duration":50}}'
        ']},"recoverable":true}}';
    final type = PotatoType.fromJson('test', json);
    final action = type.onEntityHit as FoodEffectsAction;
    expect(action.effects.length, 2);
    expect(action.effects[0].probability, 0.5);
    expect(action.effects[1].probability, 1.0);
    expect(action.effects[0].effect['id'], 'minecraft:poison');
    expect(action.recoverable, isTrue);
  });

  test('food effects ignore entries without an effect map', () {
    const json =
        '{"on_entity_hit":{"type":"create:food_effects","food_property":{'
        '"effects":[{"probability":0.5},{"effect":{"id":"minecraft:poison"}}]},'
        '"recoverable":false}}';
    final action = PotatoType.fromJson('test', json).onEntityHit as FoodEffectsAction;
    expect(action.effects.length, 1);
    expect(action.effects.single.probability, 1.0);
    expect(action.recoverable, isFalse);
  });
}
