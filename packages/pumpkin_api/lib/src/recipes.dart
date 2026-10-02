
import 'bindings.g.dart';

/// Thrown when a recipe is invalid.
final class RecipeException implements Exception {
  /// What is wrong with the recipe.
  final String message;
  const RecipeException(this.message);

  @override
  String toString() => 'RecipeException: $message';
}

String _namespaced(String id) => id.contains(':') ? id : 'minecraft:$id';

/// Creates recipe [Ingredient]s. Item ids and tags default to the
/// `minecraft:` namespace when none is given.
abstract final class Ingredients {
  /// A single item, e.g. `diamond` or `my_plugin:ruby`.
  static Ingredient item(String id) => IngredientItem(_namespaced(id));

  /// An item tag, e.g. `logs`; a leading `#` is allowed.
  static Ingredient tag(String tag) =>
      IngredientTag(_namespaced(tag.startsWith('#') ? tag.substring(1) : tag));

  /// Any one of several items.
  static Ingredient oneOf(Iterable<String> items) =>
      IngredientOneOf([for (final item in items) _namespaced(item)]);

  /// Converts [value] to an [Ingredient]: an [Ingredient] is kept, a `String`
  /// is a tag if it starts with `#` and an item otherwise, and an
  /// `Iterable<String>` is [oneOf].
  static Ingredient from(Object value) => switch (value) {
    Ingredient() => value,
    String() => value.startsWith('#') ? tag(value) : item(value),
    Iterable<String>() => oneOf(value),
    _ => throw ArgumentError.value(
      value,
      'ingredient',
      'Expected an Ingredient, String or Iterable<String>',
    ),
  };
}

ItemStack _outputStack(String item, int count) =>
    ItemStack.create(registryKey: _namespaced(item), count: count);


/// Builds a shaped crafting recipe. Ingredients are given as in
/// [Ingredients.from]:
///
/// ```dart
/// ShapedRecipeBuilder('my_plugin:super_sword', output: 'diamond_sword')
///   ..shape([' D ', ' D ', ' S '])
///   ..key('D', 'diamond_block')
///   ..key('S', 'stick')
///   ..category = RecipeCategory.equipment
///   ..register(server.getRecipeManager());
/// ```
final class ShapedRecipeBuilder {
  /// Unique recipe id.
  final String id;

  /// Output item id.
  final String output;

  /// Number of output items.
  final int count;

  /// Recipe book group.
  String? group;

  /// Recipe book category.
  RecipeCategory? category;

  /// Whether unlocking the recipe shows a toast.
  bool? showNotification;

  List<String> _pattern = [];
  final List<(String, Ingredient)> _keys = [];

  /// Starts a recipe producing [count] of the item [output].
  ShapedRecipeBuilder(this.id, {required this.output, this.count = 1});

  /// Sets the rows of the pattern (at most 3x3; a space is an empty slot).
  void shape(Iterable<String> rows) => _pattern = List.of(rows);

  /// Appends one row to the pattern.
  void row(String row) => _pattern.add(row);

  /// Maps the single character [symbol] used in the pattern to an ingredient.
  void key(String symbol, Object ingredient) {
    if (symbol.runes.length != 1) {
      throw ArgumentError.value(symbol, 'symbol', 'Must be a single character');
    }
    _keys.removeWhere((entry) => entry.$1 == symbol);
    _keys.add((symbol, Ingredients.from(ingredient)));
  }

  /// Throws a [RecipeException] if the recipe is invalid.
  void validate() {
    if (id.isEmpty) throw const RecipeException('recipe id cannot be empty');
    if (_pattern.isEmpty) throw const RecipeException('shaped recipe pattern cannot be empty');
    final width = _pattern.first.runes.length;
    if (_pattern.length > 3 || width > 3 || width == 0) {
      throw RecipeException(
        'shaped recipe pattern is too large (${width}x${_pattern.length}, max 3x3)',
      );
    }
    for (final row in _pattern) {
      if (row.runes.length != width) {
        throw RecipeException(
          'inconsistent row width in pattern (expected $width, found ${row.runes.length})',
        );
      }
      final units = row.codeUnits;
      for (var i = 0; i < units.length; i++) {
        if (units[i] != 32 && !_keys.any((entry) => entry.$1.codeUnits.first == units[i])) {
          throw RecipeException("pattern contains '${row.substring(i, i + 1)}' with no matching key");
        }
      }
    }
  }

  /// Validates and creates the [ShapedRecipe]. The result owns a fresh
  /// output [ItemStack] that is consumed when it is registered.
  ShapedRecipe build() {
    validate();
    return ShapedRecipe(
      pattern: List.of(_pattern),
      key: List.of(_keys),
      output: _outputStack(output, count),
      group: group,
      category: category,
      showNotification: showNotification,
    );
  }

  /// Registers the recipe with [manager]. Throws a [RecipeException] if invalid.
  void register(RecipeManager manager) => manager.registerShaped(id: id, recipe: build());
}

/// Builds a shapeless crafting recipe (at most 9 ingredients).
final class ShapelessRecipeBuilder {
  /// Unique recipe id.
  final String id;

  /// Output item id.
  final String output;

  /// Number of output items.
  final int count;

  /// Recipe book group.
  String? group;

  /// Recipe book category.
  RecipeCategory? category;

  final List<Ingredient> _ingredients = [];

  /// Starts a recipe producing [count] of the item [output].
  ShapelessRecipeBuilder(this.id, {required this.output, this.count = 1});

  /// Adds an ingredient (see [Ingredients.from]) [times] times.
  void ingredient(Object ingredient, {int times = 1}) {
    final value = Ingredients.from(ingredient);
    for (var i = 0; i < times; i++) {
      _ingredients.add(value);
    }
  }

  /// Throws a [RecipeException] if the recipe is invalid.
  void validate() {
    if (id.isEmpty) throw const RecipeException('recipe id cannot be empty');
    if (_ingredients.isEmpty) {
      throw const RecipeException('shapeless recipe requires at least one ingredient');
    }
    if (_ingredients.length > 9) {
      throw RecipeException(
        'shapeless recipe has too many ingredients (${_ingredients.length}, max 9)',
      );
    }
  }

  /// Validates and creates the [ShapelessRecipe].
  ShapelessRecipe build() {
    validate();
    return ShapelessRecipe(
      ingredients: List.of(_ingredients),
      output: _outputStack(output, count),
      group: group,
      category: category,
    );
  }

  /// Registers the recipe with [manager]. Throws a [RecipeException] if invalid.
  void register(RecipeManager manager) =>
      manager.registerShapeless(id: id, recipe: build());
}

/// Builds a cooking recipe for a furnace, blast furnace, smoker or campfire.
final class CookingRecipeBuilder {
  /// Unique recipe id.
  final String id;

  /// The station that cooks the ingredient.
  final CookingType type;

  /// The ingredient, see [Ingredients.from].
  final Object ingredient;

  /// Output item id.
  final String output;

  /// Number of output items.
  final int count;

  /// Cooking time in ticks. Defaults to the vanilla time of the [type].
  late int cookingTime = switch (type) {
    CookingType.smelting => 200,
    CookingType.blasting || CookingType.smoking => 100,
    CookingType.campfire => 600,
  };

  /// Experience awarded.
  double experience = 0;

  /// Recipe book group.
  String? group;

  /// Recipe book category.
  RecipeCategory? category;

  /// Starts a cooking recipe for [type].
  CookingRecipeBuilder(
    this.id,
    this.type, {
    required this.ingredient,
    required this.output,
    this.count = 1,
  });

  /// A furnace recipe.
  CookingRecipeBuilder.smelting(String id, {required Object ingredient, required String output, int count = 1})
    : this(id, CookingType.smelting, ingredient: ingredient, output: output, count: count);

  /// A blast furnace recipe.
  CookingRecipeBuilder.blasting(String id, {required Object ingredient, required String output, int count = 1})
    : this(id, CookingType.blasting, ingredient: ingredient, output: output, count: count);

  /// A smoker recipe.
  CookingRecipeBuilder.smoking(String id, {required Object ingredient, required String output, int count = 1})
    : this(id, CookingType.smoking, ingredient: ingredient, output: output, count: count);

  /// A campfire recipe.
  CookingRecipeBuilder.campfire(String id, {required Object ingredient, required String output, int count = 1})
    : this(id, CookingType.campfire, ingredient: ingredient, output: output, count: count);

  /// Throws a [RecipeException] if the recipe is invalid.
  void validate() {
    if (id.isEmpty) throw const RecipeException('recipe id cannot be empty');
  }

  /// Validates and creates the [CookingRecipe].
  CookingRecipe build() {
    validate();
    return CookingRecipe(
      ingredient: Ingredients.from(ingredient),
      output: _outputStack(output, count),
      experience: experience,
      cookingTime: cookingTime,
      group: group,
      category: category,
    );
  }

  /// Registers the recipe with [manager]. Throws a [RecipeException] if invalid.
  void register(RecipeManager manager) =>
      manager.registerCooking(id: id, stationType: type, recipe: build());
}

extension RecipeManagerApi on RecipeManager {
  /// Registers a recipe from a [ShapedRecipeBuilder], [ShapelessRecipeBuilder]
  /// or [CookingRecipeBuilder].
  void register(Object builder) => switch (builder) {
    ShapedRecipeBuilder() => builder.register(this),
    ShapelessRecipeBuilder() => builder.register(this),
    CookingRecipeBuilder() => builder.register(this),
    _ => throw ArgumentError.value(builder, 'builder', 'Expected a recipe builder'),
  };
}

extension RecipeRegistration on Server {
  /// Registers a recipe, see [RecipeManagerApi.register].
  void registerRecipe(Object builder) => getRecipeManager().register(builder);
}

extension RecipeContextRegistration on Context {
  /// Registers a recipe, see [RecipeManagerApi.register].
  void registerRecipe(Object builder) => getServer().registerRecipe(builder);
}
