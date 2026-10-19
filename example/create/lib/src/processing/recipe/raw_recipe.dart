// The JSON document of a Create recipe as a dart_mappable model (snake_case keys, see
// build.yaml). Ingredients and results stay loosely typed here because their JSON has many
// shapes (item / tag / NeoForge ingredient types, items mixed with fluids); `recipe_json.dart`
// turns this into the recipe models.
import 'package:dart_mappable/dart_mappable.dart';

part 'raw_recipe.mapper.dart';

/// One recipe file of `data/create/recipe`.
@MappableClass()
class RawRecipe with RawRecipeMappable {
  final String type;

  /// `ingredients` of the processing types (items and fluids mixed).
  final List<Object?>? ingredients;

  /// `ingredient` of the sequenced assembly.
  final Object? ingredient;

  /// `results` of the processing types and the sequenced assembly.
  final List<Object?>? results;

  /// `result` of the mechanical crafting recipe.
  final Object? result;

  final int? processingTime;
  final String? heatRequirement;
  final bool? keepHeldItem;

  // Mechanical crafting (a vanilla shaped recipe plus `accept_mirrored`).
  final bool? acceptMirrored;
  final List<String>? pattern;
  final Map<String, Object?>? key;
  final String? category;
  final String? group;
  final bool? showNotification;

  // Sequenced assembly.
  final List<Object?>? sequence;
  final Object? transitionalItem;
  final int? loops;

  /// NeoForge load conditions.
  @MappableField(key: 'neoforge:conditions')
  final List<Object?>? conditions;

  const RawRecipe({
    required this.type,
    this.ingredients,
    this.ingredient,
    this.results,
    this.result,
    this.processingTime,
    this.heatRequirement,
    this.keepHeldItem,
    this.acceptMirrored,
    this.pattern,
    this.key,
    this.category,
    this.group,
    this.showNotification,
    this.sequence,
    this.transitionalItem,
    this.loops,
    this.conditions,
  });
}
