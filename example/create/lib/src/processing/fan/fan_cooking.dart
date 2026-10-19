// The vanilla cooking recipes the fan's smoking and blasting types use (`RecipeType.SMELTING`,
// `BLASTING`, `SMOKING`), cached from the host recipe manager. Pure: the entries are matched with
// the processing tag lookup.
import '../common/stack.dart';
import '../recipe/ingredient.dart';

/// One cooking recipe (`AbstractCookingRecipe`): its ingredient and the item it produces.
final class CookingEntry {
  final String id;
  final Ingredient ingredient;
  final PStack output;

  const CookingEntry(this.id, this.ingredient, this.output);

  bool matches(PStack stack, TagLookup tags) => ingredient.test(stack, tags);

  @override
  String toString() => 'cooking($id -> $output)';
}

/// The cooking recipes by station, loaded by the fan part at server load and on a datapack reload.
final class FanCookingCache {
  static FanCookingCache? current;

  List<CookingEntry> smelting = const [];
  List<CookingEntry> blasting = const [];
  List<CookingEntry> smoking = const [];

  /// `RecipeManager.getRecipeFor(type, stack, level)`: the first matching recipe.
  static CookingEntry? firstOf(
    List<CookingEntry> recipes,
    PStack stack,
    TagLookup tags,
  ) {
    for (final r in recipes) {
      if (r.matches(stack, tags)) return r;
    }
    return null;
  }
}
