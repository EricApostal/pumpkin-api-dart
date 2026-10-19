// `SequencedAssemblyRecipe` (pure): the recipe that threads an item through a series of
// machine steps, and the `create:sequenced_assembly` item component that tracks progress.
import 'dart:math';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../common/stack.dart';
import 'ingredient.dart';
import 'output.dart';
import 'recipe.dart';
import 'recipe_type.dart';

/// The component key of `AllDataComponents.SEQUENCED_ASSEMBLY` as stored in [PStack.comps]
/// (the `custom:` prefix marks plugin components, see the equipment module's `StackCodec`).
const String sequencedAssemblyComponent = 'custom:create:sequenced_assembly';

/// `SequencedAssemblyRecipe.SequencedAssembly`: the recipe the item is in, the step and the
/// progress (0..1).
final class SequencedAssemblyState {
  final String id;
  final int step;
  final double progress;

  const SequencedAssemblyState(this.id, this.step, this.progress);

  /// The component bytes: text, int, float (`Identifier`, `INT`, `FLOAT` stream codecs).
  List<int> encode() => PacketBuffer.encode((w) {
    w.writeString(id, maxLength: 32767);
    w.writeInt(step);
    w.writeFloat(progress);
  });

  static SequencedAssemblyState decode(List<int> bytes) =>
      PacketBuffer.decode(bytes, (r) => SequencedAssemblyState(r.readString(maxLength: 32767), r.readInt(), r.readFloat()));

  /// The state stored on [stack], or `null`.
  static SequencedAssemblyState? of(PStack stack) {
    final bytes = stack.component(sequencedAssemblyComponent);
    if (bytes == null) return null;
    try {
      return decode(bytes);
    } on PacketException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SequencedAssemblyState && other.id == id && other.step == step && other.progress == progress;

  @override
  int get hashCode => Object.hash(id, step, progress);

  @override
  String toString() => 'SequencedAssembly($id, step $step, ${(progress * 100).round()}%)';
}

/// `SequencedAssemblyItem.getProgress`.
double sequencedProgress(PStack stack) => SequencedAssemblyState.of(stack)?.progress ?? 0;

/// `SequencedAssemblyRecipe`.
final class SequencedAssemblyRecipe {
  final String id;
  final Ingredient ingredient;
  final ProcessingOutput transitionalItem;

  /// The steps, in order.
  final List<SequencedRecipe> sequence;

  /// The result pool; the chance of an entry is its weight.
  final List<ProcessingOutput> resultPool;
  final int loops;

  const SequencedAssemblyRecipe({
    required this.id,
    required this.ingredient,
    required this.transitionalItem,
    required this.sequence,
    required this.resultPool,
    this.loops = 1,
  });

  /// `getTransitionalItem`.
  PStack get transitionalStack => transitionalItem.stack;

  /// `getStep(input)`.
  int stepOf(PStack input) => SequencedAssemblyState.of(input)?.step ?? 0;

  /// `appliesTo(id, input)`.
  bool appliesTo(PStack input, TagLookup tags) {
    final state = SequencedAssemblyState.of(input);
    if (state != null) return transitionalItem.item == input.key && state.id == id;
    return ingredient.test(input, tags);
  }

  /// `getNextRecipe(input)`.
  SequencedRecipe nextRecipe(PStack input) => sequence[stepOf(input) % sequence.length];

  /// `advance(id, input, random)`: the item after one more step, or the rolled result when the
  /// last step of the last loop is done.
  PStack advance(PStack input, Random random) {
    final step = stepOf(input);
    // Java: `(step + 1) / sequence.size()` is an integer division.
    if ((step + 1) ~/ sequence.length >= loops) return rollResult(random);
    final advanced = transitionalStack.withCount(1).withComponent(
      sequencedAssemblyComponent,
      SequencedAssemblyState(id, step + 1, (step + 1) / (sequence.length * loops)).encode(),
    );
    return advanced;
  }

  /// `rollResult`: a weighted pick of the result pool.
  PStack rollResult(Random random) {
    var totalWeight = 0.0;
    for (final e in resultPool) {
      totalWeight += e.chance;
    }
    var number = random.nextDouble() * totalWeight;
    for (final e in resultPool) {
      number -= e.chance;
      if (number < 0) return e.stack;
    }
    return PStack.empty;
  }

  /// `getOutputChance`.
  double get outputChance {
    var totalWeight = 0.0;
    for (final e in resultPool) {
      totalWeight += e.chance;
    }
    return resultPool.first.chance / totalWeight;
  }

  /// `getResultItem`.
  PStack get resultItem => resultPool.first.stack;

  /// `initFromSequencedAssembly`: the step recipes with their first ingredient replaced by the
  /// transitional item (the first step also takes the start ingredient).
  static SequencedAssemblyRecipe create({
    required String id,
    required Ingredient ingredient,
    required ProcessingOutput transitionalItem,
    required List<ProcessingRecipe> steps,
    required List<ProcessingOutput> resultPool,
    int loops = 1,
  }) {
    final transit = Ingredient.item(transitionalItem.item);
    final rewritten = <SequencedRecipe>[];
    for (var j = 0; j < steps.length; j++) {
      final step = steps[j];
      if (!step.type.assembly || step.ingredients.isEmpty) {
        rewritten.add(SequencedRecipe(step));
        continue;
      }
      final first = j == 0 ? Ingredient.anyOf([transit, ingredient]) : transit;
      rewritten.add(SequencedRecipe(step.withIngredients([first, ...step.ingredients.skip(1)])));
    }
    return SequencedAssemblyRecipe(
      id: id,
      ingredient: ingredient,
      transitionalItem: transitionalItem,
      sequence: rewritten,
      resultPool: resultPool,
      loops: loops,
    );
  }

  /// The type of the step [step].
  CreateRecipeType stepType(int step) => sequence[step % sequence.length].recipe.type;

  @override
  String toString() => 'sequenced_assembly($id, ${sequence.length} steps x $loops)';
}

/// What a sequenced assembly lookup finds: the step recipe to run and the item the machine
/// must output in place of the recipe's first result (`enforceNextResult`).
final class SequencedMatch {
  final SequencedAssemblyRecipe assembly;
  final ProcessingRecipe recipe;

  /// The input stack this match was made for.
  final PStack input;

  const SequencedMatch(this.assembly, this.recipe, this.input);

  /// `recipe.enforceNextResult(() -> advance(...))`: pass the result to
  /// `ProcessingRecipe.rollResults(forcedFirst: ...)`.
  PStack Function() forcedResult(Random random) =>
      () => assembly.advance(input, random);
}
