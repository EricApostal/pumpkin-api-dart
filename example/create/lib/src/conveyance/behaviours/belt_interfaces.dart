// What belts, depots and the machines around them know of each other (pure interfaces): the
// views of `DirectBeltInputBehaviour`, `TransportedItemStackHandlerBehaviour` and
// `BeltProcessingBehaviour`. The host behaviours (`direct_belt_input.dart`, ...) implement
// them; the belt logic and its tests use only these.
import 'dart:async';

import '../../common/direction.dart';
import '../../common/vec_helper.dart';
import '../belt/transported_item.dart';
import '../items/item_data.dart';

/// `DirectBeltInputBehaviour`: a block entity belts can transfer items to directly.
abstract interface class DirectBeltInput {
  /// `canInsertFromSide(side)`.
  bool canInsertFromSide(Direction side);

  /// `isOccupied(side)`.
  bool isOccupied(Direction side);

  /// `handleInsertion(stack, side, simulate)`: the remainder.
  FutureOr<ItemValue> handleInsertion(TransportedItemStack stack, Direction side, {bool simulate = false});

  /// `canSupportBeltFunnels()`.
  bool get canSupportBeltFunnels;
}

/// `TransportedItemStackHandlerBehaviour.TransportedResult`.
final class TransportedResult {
  /// `null`: do nothing.
  final List<TransportedItemStack>? outputs;
  final TransportedItemStack? heldOutput;

  const TransportedResult._(this.outputs, this.heldOutput);

  static const TransportedResult _doNothing = TransportedResult._(null, null);
  static const TransportedResult _removeItem = TransportedResult._([], null);

  /// `doNothing()`.
  static TransportedResult doNothing() => _doNothing;

  /// `removeItem()`.
  static TransportedResult removeItem() => _removeItem;

  /// `convertTo(output)`.
  factory TransportedResult.convertTo(TransportedItemStack output) => TransportedResult._([output], null);

  /// `convertTo(outputs)`.
  factory TransportedResult.convertToAll(List<TransportedItemStack> outputs) => TransportedResult._(outputs, null);

  /// `convertToAndLeaveHeld(outputs, heldOutput)`.
  factory TransportedResult.convertToAndLeaveHeld(List<TransportedItemStack> outputs, TransportedItemStack heldOutput) =>
      TransportedResult._(outputs, heldOutput);

  /// `doesNothing()`.
  bool get doesNothing => outputs == null;

  /// `didntChangeFrom(stackBefore)`.
  bool didntChangeFrom(ItemValue stackBefore) =>
      doesNothing || (outputs!.length == 1 && outputs!.first.stack.matches(stackBefore) && !hasHeldOutput);

  bool get hasHeldOutput => heldOutput != null;
}

/// A function applied to the items near a position: the result tells what to do with the item.
typedef ItemProcessor = TransportedResult? Function(TransportedItemStack item);

/// `TransportedItemStackHandlerBehaviour`: a belt segment or depot whose items can be processed.
abstract interface class TransportedItemStackHandler {
  /// `handleCenteredProcessingOnAllItems(maxDistanceFromCenter, processFunction)`.
  void handleCenteredProcessingOnAllItems(double maxDistanceFromCenter, ItemProcessor processFunction);

  /// `handleProcessingOnAllItems(processFunction)`: within .51 of the centre.
  void handleProcessingOnAllItems(ItemProcessor processFunction);

  /// `handleProcessingOnItem(item, result)`.
  void handleProcessingOnItem(TransportedItemStack item, TransportedResult result);

  /// `getWorldPositionOf(transported)`.
  Vec3 getWorldPositionOf(TransportedItemStack transported);
}

/// `BeltProcessingBehaviour.ProcessingResult`.
enum ProcessingResult { pass, hold, remove }

/// `BeltProcessingBehaviour`: a machine above a belt or depot that processes the items passing
/// beneath it.
abstract interface class BeltProcessing {
  /// `handleReceivedItem(stack, inventory)`.
  ProcessingResult handleReceivedItem(TransportedItemStack stack, TransportedItemStackHandler inventory);

  /// `handleHeldItem(stack, inventory)`.
  ProcessingResult handleHeldItem(TransportedItemStack stack, TransportedItemStackHandler inventory);
}
