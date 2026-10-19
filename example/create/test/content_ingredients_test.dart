import 'package:create/src/api/data/all_ingredients.dart';
import 'package:test/test.dart';

void main() {
  test(
    'the simple_datagen ingredient type is registered as create:simple_datagen',
    () {
      expect(AllIngredients.simpleDatagenType, 'create:simple_datagen');
      expect(AllIngredients.ingredientTypes, [
        AllIngredients.simpleDatagenType,
      ]);
    },
  );

  test('simple datagen ingredients serialize to the create:simple_datagen object form', () {
    const ingredient = SimpleDatagenIngredient('thermal', 'tin_ingot');
    expect(ingredient.item, 'thermal:tin_ingot');
    expect(ingredient.isSimple, isTrue);
    expect(ingredient.toJson(), {
      'type': 'create:simple_datagen',
      'item': 'thermal:tin_ingot',
    });
    expect(
      AllIngredients.simpleDatagen('thermal', 'tin_ingot'),
      ingredient.toJson(),
    );
  });

  test('simple datagen ingredients parse the object form', () {
    final parsed = SimpleDatagenIngredient.fromJson(const {
      'type': 'create:simple_datagen',
      'item': 'create:brass_ingot',
    });
    expect(parsed, isNotNull);
    expect(parsed!.mod, 'create');
    expect(parsed.id, 'brass_ingot');
    expect(parsed.item, 'create:brass_ingot');
  });

  test('invalid object forms are rejected', () {
    expect(SimpleDatagenIngredient.fromJson(const {}), isNull);
    expect(SimpleDatagenIngredient.fromJson(const {'item': 3}), isNull);
    expect(
      SimpleDatagenIngredient.fromJson(const {'item': 'brass_ingot'}),
      isNull,
    );
    expect(
      SimpleDatagenIngredient.fromJson(const {'item': ':brass_ingot'}),
      isNull,
    );
    expect(SimpleDatagenIngredient.fromJson(const {'item': 'create:'}), isNull);
  });
}
