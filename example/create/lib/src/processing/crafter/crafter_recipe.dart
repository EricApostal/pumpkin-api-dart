// The crafting lookup of the mechanical crafter (pure): turning a [GroupedItems] grid into the
// shaped input vanilla recipes see (`MechanicalCraftingInput`), matching Create's
// `MechanicalCraftingRecipe` (with its optional mirroring) and building the rows the host's
// crafting recipe manager expects.
//
// `MechanicalCraftingRecipe` matching is ported from
// `content/kinetics/crafter/MechanicalCraftingRecipe.java` (`matches` / `matchesSpecific`).
import '../common/stack.dart';
import '../recipe/ingredient.dart';
import '../recipe/recipe.dart';
import 'crafter_model.dart';

/// `MechanicalCraftingInput`: the grid's non-empty bounding box, row-major, top row first.
final class CraftingGridInput {
  final int width;
  final int height;

  /// `width * height` stacks, row by row (`null` cells are [PStack.empty]).
  final List<PStack> cells;

  const CraftingGridInput(this.width, this.height, this.cells);

  static const CraftingGridInput empty = CraftingGridInput(0, 0, []);

  bool get isEmpty => width == 0 || height == 0;

  PStack cellAt(int x, int y) => cells[x + y * width];

  /// The item keys, row by row (`null` for empty cells), as `RecipeManager.matchCrafting` wants.
  List<List<String?>> get rows => [
    for (var y = 0; y < height; y++)
      [
        for (var x = 0; x < width; x++)
          cellAt(x, y).isEmpty ? null : cellAt(x, y).key,
      ],
  ];
}

/// `MechanicalCraftingInput.of(GroupedItems)`.
CraftingGridInput craftingInputOf(GroupedItems items) {
  items.calcStats();

  var minX = 1 << 30, maxX = -(1 << 30), minY = 1 << 30, maxY = -(1 << 30);
  for (var y = 0; y < items.height; y++) {
    for (var x = 0; x < items.width; x++) {
      final xp = x + items.minX;
      final yp = y + items.minY;
      final stack = items.grid[(xp, yp)];
      if (stack == null || stack.isEmpty) continue;
      if (xp < minX) minX = xp;
      if (xp > maxX) maxX = xp;
      if (yp < minY) minY = yp;
      if (yp > maxY) maxY = yp;
    }
  }

  if (minX > maxX || minY > maxY) return CraftingGridInput.empty;

  final w = maxX - minX + 1;
  final h = maxY - minY + 1;
  final cells = <PStack>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      cells.add(items.grid[(x + minX, maxY - y)] ?? PStack.empty);
    }
  }
  return CraftingGridInput(w, h, cells);
}

/// `MechanicalCraftingRecipe.matches`: the pattern has to appear in the grid, mirrored only when
/// the recipe accepts it.
bool mechanicalCraftingMatches(
  MechanicalCraftingRecipe recipe,
  GroupedItems items,
  TagLookup tags,
) {
  final input = craftingInputOf(items);
  if (input.isEmpty) return false;
  if (recipe.width == 0 || recipe.height == 0) return false;

  if (_matchesOrientation(recipe, input, tags, mirrored: false)) return true;
  if (recipe.acceptMirrored &&
      _matchesOrientation(recipe, input, tags, mirrored: true)) {
    return true;
  }
  return false;
}

bool _matchesOrientation(
  MechanicalCraftingRecipe recipe,
  CraftingGridInput input,
  TagLookup tags, {
  required bool mirrored,
}) {
  final patternWidth = recipe.width;
  final patternHeight = recipe.height;
  if (patternWidth > input.width || patternHeight > input.height) return false;

  for (var offsetY = 0; offsetY <= input.height - patternHeight; offsetY++) {
    for (var offsetX = 0; offsetX <= input.width - patternWidth; offsetX++) {
      if (_matchesAt(recipe, input, tags, offsetX, offsetY, mirrored)) {
        return true;
      }
    }
  }
  return false;
}

/// `MechanicalCraftingRecipe.matchesSpecific`.
bool _matchesAt(
  MechanicalCraftingRecipe recipe,
  CraftingGridInput input,
  TagLookup tags,
  int offsetX,
  int offsetY,
  bool mirrored,
) {
  final patternWidth = recipe.width;
  final patternHeight = recipe.height;
  final cells = recipe.cells;

  for (var i = 0; i < input.width; i++) {
    for (var j = 0; j < input.height; j++) {
      final k = i - offsetX;
      final l = j - offsetY;
      Ingredient? ingredient;
      if (k >= 0 && l >= 0 && k < patternWidth && l < patternHeight) {
        final x = mirrored ? patternWidth - 1 - k : k;
        final index = l * patternWidth + x;
        ingredient = index < cells.length ? cells[index] : null;
      }
      final stack = input.cellAt(i, j);
      if (ingredient == null) {
        if (stack.isNotEmpty) return false;
      } else if (!ingredient.test(stack, tags)) {
        return false;
      }
    }
  }
  return true;
}

/// The first mechanical crafting recipe matching [items], `null` when there is none.
MechanicalCraftingRecipe? findMechanicalCraftingRecipe(
  Iterable<MechanicalCraftingRecipe> recipes,
  GroupedItems items,
  TagLookup tags,
) {
  for (final recipe in recipes) {
    if (mechanicalCraftingMatches(recipe, items, tags)) return recipe;
  }
  return null;
}
