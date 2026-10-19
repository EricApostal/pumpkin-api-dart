// `RecipeApplier` and the stack helpers of `ItemHelper` it uses (pure): turning an input stack
// into the stacks a recipe produces, merging equal results.
import 'dart:math';

import '../common/stack.dart';
import 'output.dart';
import 'recipe.dart';

/// `ItemHelper.multipliedOutput(in, out)`: `in.count * out.count` items of `out`, split into
/// stacks of at most the max stack size.
List<PStack> multipliedOutput(PStack input, PStack output) {
  final stacks = <PStack>[];
  var remaining = input.count * output.count;
  final max = output.maxStack <= 0 ? 64 : output.maxStack;
  while (remaining > max) {
    stacks.add(output.withCount(max));
    remaining -= max;
  }
  if (remaining > 0) stacks.add(output.withCount(remaining));
  return stacks;
}

/// `ItemHelper.addToList(stack, stacks)`: tops up the equal stacks in [stacks] first, then appends
/// the rest.
void addToList(PStack stack, List<PStack> stacks) {
  var rest = stack;
  for (var i = 0; i < stacks.length; i++) {
    final s = stacks[i];
    if (!rest.sameItemSameComponents(s)) continue;
    final transferred = min(s.maxStack - s.count, rest.count);
    if (transferred <= 0) continue;
    stacks[i] = s.withCount(s.count + transferred);
    rest = rest.withCount(rest.count - transferred);
    if (rest.isEmpty) break;
  }
  if (rest.count > 0) stacks.add(rest);
}

/// `RecipeApplier.applyRecipeOn(level, stackIn, recipe, returnProcessingRemainder)` for the
/// parameter based recipes: every item of [stackIn] rolls the recipe's results; equal results
/// are merged. [rollFirst] replaces the roll of the first result of every round (the sequenced
/// assembly's forced result, `enforceNextResult`); [craftingRemainder] is the item's crafting
/// remainder (`Item.getCraftingRemainder`), given back per input item when
/// [returnProcessingRemainder] is set.
List<PStack> applyRecipeOn(
  PStack stackIn,
  ProcessingRecipe recipe,
  Random random, {
  bool returnProcessingRemainder = false,
  PStack? Function(PStack input)? craftingRemainder,
  PStack Function()? rollFirst,
}) {
  final stacks = <PStack>[];
  for (var i = 0; i < stackIn.count; i++) {
    for (final rolled in recipe.rollResults(random, forcedFirst: rollFirst)) {
      addToList(rolled, stacks);
    }
    if (returnProcessingRemainder) {
      final remainder = craftingRemainder?.call(stackIn);
      if (remainder != null && remainder.isNotEmpty) addToList(remainder, stacks);
    }
  }
  return stacks;
}

/// `applyRecipeOn` for recipes that only have a result item (vanilla smelting, smoking, blasting,
/// stonecutting, crafting): `multipliedOutput(stackIn, result)`.
List<PStack> applyResultOn(PStack stackIn, PStack result) => multipliedOutput(stackIn, result);

/// The merged list of rolled outputs, for tests and tooling.
List<PStack> rollAll(Iterable<ProcessingOutput> outputs, Random random) {
  final stacks = <PStack>[];
  for (final o in outputs) {
    final r = o.roll(random);
    if (r.isNotEmpty) addToList(r, stacks);
  }
  return stacks;
}
