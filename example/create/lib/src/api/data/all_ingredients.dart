// `AllIngredients` (pure): Create's custom ingredient type for datagen-only ingredients
// (`create:simple_datagen`). The runtime never tests one (Java throws if it does); the type only
// exists so recipes generated for compat mods can be encoded.

/// `SimpleDatagenIngredient`: an item of a compat mod, written as
/// `{"type": "create:simple_datagen", "item": "<mod>:<id>"}`.
final class SimpleDatagenIngredient {
  /// The compat mod id (`create`, `thermal`, ...).
  final String mod;

  /// The item path inside [mod].
  final String id;

  const SimpleDatagenIngredient(this.mod, this.id);

  /// `SimpleDatagenIngredient.of(mod, id)`: the item key.
  String get item => '$mod:$id';

  /// `isSimple()`.
  bool get isSimple => true;

  /// `SimpleDatagenIngredient.MAP_CODEC` output.
  Map<String, Object?> toJson() => {
    'type': AllIngredients.simpleDatagenType,
    'item': item,
  };

  /// Reads the object form; `null` when `item` is missing or not an id.
  static SimpleDatagenIngredient? fromJson(Map<String, Object?> json) {
    final value = json['item'];
    if (value is! String) return null;
    final colon = value.indexOf(':');
    if (colon <= 0 || colon == value.length - 1) return null;
    return SimpleDatagenIngredient(
      value.substring(0, colon),
      value.substring(colon + 1),
    );
  }

  @override
  String toString() => item;
}

/// `AllIngredients`: the ingredient types Create adds to NeoForge's registry.
abstract final class AllIngredients {
  /// `INGREDIENT_TYPES.register("simple_datagen", ...)`.
  static const String simpleDatagenType = 'create:simple_datagen';

  /// The registered ingredient type ids.
  static const List<String> ingredientTypes = [simpleDatagenType];

  /// `SimpleDatagenIngredient.of(mod, id)`: the JSON form.
  static Map<String, Object?> simpleDatagen(String mod, String id) =>
      SimpleDatagenIngredient(mod, id).toJson();
}
