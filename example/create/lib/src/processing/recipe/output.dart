// `ProcessingOutput` (pure): an item with a count, a chance and optional components.
import 'dart:math';

import '../common/stack.dart';

/// `ProcessingOutput`.
final class ProcessingOutput {
  final String item;
  final int count;
  final double chance;

  /// The `components` of the JSON, kept for the network form (the host stack cannot take
  /// arbitrary components, see `host/stack_host.dart`).
  final Map<String, Object?> components;

  const ProcessingOutput(this.item, {this.count = 1, this.chance = 1.0, this.components = const {}});

  /// `getStack()`.
  PStack get stack => PStack(item, count);

  /// `rollOutput`: every item of the stack is rolled on its own when `chance < 1`.
  PStack roll(Random random) {
    if (chance < 1) {
      var c = count;
      for (var roll = 0; roll < count; roll++) {
        if (random.nextDouble() > chance) c--;
      }
      if (c == 0) return PStack.empty;
      return PStack(item, c);
    }
    return PStack(item, count);
  }

  @override
  String toString() => '${chance < 1 ? '${(chance * 100).round()}% ' : ''}$count x $item';
}
