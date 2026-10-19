// Bridges between the conveyance belt stack types ([TransportedItemStack] of `belt/`) and the
// processing machines' types (`processing/transport`). Belts move [ItemValue]s; the machines
// above them (press, saw, basin, fan, ...) add `BeltProcessingBehaviour`,
// `DirectBeltInputBehaviour` and `TransportedItemStackHandlerBehaviour`, which speak [PStack].
// The adapters convert at the boundary and copy mutable fields back after each call.
import 'dart:async';

import '../../common/direction.dart';
import '../../common/vec_helper.dart' show Vec3;
import '../../processing/transport/transport_behaviours.dart' as pt;
import '../belt/transported_item.dart' as belt;
import '../items/item_data.dart';
import '../items/stack_bridge.dart';
import 'belt_interfaces.dart';

/// The processing form of a belt item.
pt.TransportedItemStack toProcessing(belt.TransportedItemStack t) {
  final p = pt.TransportedItemStack(toPStack(t.stack));
  p.beltPosition = t.beltPosition;
  p.prevBeltPosition = t.prevBeltPosition;
  p.sideOffset = t.sideOffset;
  p.prevSideOffset = t.prevSideOffset;
  p.angle = t.angle;
  p.insertedAt = t.insertedAt;
  p.insertedFrom = t.insertedFrom.serializedName;
  p.locked = t.locked;
  p.lockedExternally = t.lockedExternally;
  p.processedBy = t.processedBy;
  p.processingTime = t.processingTime;
  return p;
}

/// Copies the (possibly mutated) processing form back into the belt item.
void copyBack(pt.TransportedItemStack from, belt.TransportedItemStack to) {
  to.stack = fromPStack(from.stack);
  to.beltPosition = from.beltPosition;
  to.prevBeltPosition = from.prevBeltPosition;
  to.sideOffset = from.sideOffset;
  to.prevSideOffset = from.prevSideOffset;
  to.angle = from.angle;
  to.insertedAt = from.insertedAt;
  to.insertedFrom = Direction.byName(from.insertedFrom) ?? to.insertedFrom;
  to.locked = from.locked;
  to.lockedExternally = from.lockedExternally;
  to.processedBy = from.processedBy;
  to.processingTime = from.processingTime;
}

/// Copies the (possibly mutated) belt item into the processing form.
void copyToProcessing(
  belt.TransportedItemStack from,
  pt.TransportedItemStack to,
) {
  to.stack = toPStack(from.stack);
  to.beltPosition = from.beltPosition;
  to.prevBeltPosition = from.prevBeltPosition;
  to.sideOffset = from.sideOffset;
  to.prevSideOffset = from.prevSideOffset;
  to.angle = from.angle;
  to.insertedAt = from.insertedAt;
  to.insertedFrom = from.insertedFrom.serializedName;
  to.locked = from.locked;
  to.lockedExternally = from.lockedExternally;
  to.processedBy = from.processedBy;
  to.processingTime = from.processingTime;
}

/// The belt form of a processing item (new instance).
belt.TransportedItemStack fromProcessing(pt.TransportedItemStack t) {
  final out = belt.TransportedItemStack.raw(fromPStack(t.stack));
  copyBack(t, out);
  return out;
}

/// The belt form of a processing result.
TransportedResult fromProcessingResult(pt.TransportedResult result) {
  if (result.doesNothing) return TransportedResult.doNothing();
  final outputs = [for (final o in result.outputs) fromProcessing(o)];
  if (result.hasHeldOutput)
    return TransportedResult.convertToAndLeaveHeld(
      outputs,
      fromProcessing(result.heldOutput),
    );
  return TransportedResult.convertToAll(outputs);
}

/// The processing form of a belt result.
pt.TransportedResult toProcessingResult(TransportedResult result) {
  if (result.doesNothing) return pt.TransportedResult.doNothing();
  final outputs = [for (final o in result.outputs!) toProcessing(o)];
  if (result.hasHeldOutput)
    return pt.TransportedResult.convertToAndLeaveHeld(
      outputs,
      toProcessing(result.heldOutput!),
    );
  return pt.TransportedResult.convertToAll(outputs);
}

ProcessingResult _processingResult(pt.ProcessingResult r) => switch (r) {
  pt.ProcessingResult.pass => ProcessingResult.pass,
  pt.ProcessingResult.hold => ProcessingResult.hold,
  pt.ProcessingResult.remove => ProcessingResult.remove,
};

/// `BeltProcessingBehaviour` (processing module) as the belt's [BeltProcessing].
final class ProcessingBeltAdapter implements BeltProcessing {
  final pt.BeltProcessingBehaviour behaviour;

  ProcessingBeltAdapter(this.behaviour);

  @override
  ProcessingResult handleReceivedItem(
    belt.TransportedItemStack stack,
    TransportedItemStackHandler inventory,
  ) {
    final p = toProcessing(stack);
    final result = behaviour.handleReceivedItem(
      p,
      ProcessingHandlerView(inventory),
    );
    copyBack(p, stack);
    return _processingResult(result);
  }

  @override
  ProcessingResult handleHeldItem(
    belt.TransportedItemStack stack,
    TransportedItemStackHandler inventory,
  ) {
    final p = toProcessing(stack);
    final result = behaviour.handleHeldItem(
      p,
      ProcessingHandlerView(inventory),
    );
    copyBack(p, stack);
    return _processingResult(result);
  }
}

/// `DirectBeltInputBehaviour` (processing module) as the belt's [DirectBeltInput].
final class DirectInputAdapter implements DirectBeltInput {
  final pt.DirectBeltInputBehaviour behaviour;

  DirectInputAdapter(this.behaviour);

  @override
  bool canInsertFromSide(Direction side) =>
      behaviour.canInsertFromSide(side.serializedName);

  @override
  bool isOccupied(Direction side) => behaviour.isOccupied(side.serializedName);

  @override
  FutureOr<ItemValue> handleInsertion(
    belt.TransportedItemStack stack,
    Direction side, {
    bool simulate = false,
  }) {
    final p = toProcessing(stack);
    final remainder = behaviour.handleInsertion(
      p,
      side.serializedName,
      simulate,
    );
    copyBack(p, stack);
    return fromPStack(remainder);
  }

  @override
  bool get canSupportBeltFunnels => behaviour.supportsBeltFunnels;
}

/// A processing [pt.TransportedItemStackHandler] seen by the belt: its results are converted
/// back into belt items.
final class ConveyanceHandlerView implements TransportedItemStackHandler {
  final pt.TransportedItemStackHandler inner;

  ConveyanceHandlerView(this.inner);

  @override
  void handleCenteredProcessingOnAllItems(
    double maxDistanceFromCenter,
    ItemProcessor processFunction,
  ) {
    inner.handleCenteredProcessingOnAllItems(maxDistanceFromCenter, (pItem) {
      final convItem = fromProcessing(pItem);
      final result = processFunction(convItem);
      copyToProcessing(convItem, pItem);
      if (result == null) return null;
      return toProcessingResult(result);
    });
  }

  @override
  void handleProcessingOnAllItems(ItemProcessor processFunction) =>
      handleCenteredProcessingOnAllItems(.51, processFunction);

  @override
  void handleProcessingOnItem(
    belt.TransportedItemStack item,
    TransportedResult result,
  ) => handleCenteredProcessingOnAllItems(
    .51,
    (t) => identical(t, item) ? result : null,
  );

  @override
  Vec3 getWorldPositionOf(belt.TransportedItemStack transported) =>
      inner.worldPositionOf(toProcessing(transported));
}

/// A belt [TransportedItemStackHandler] seen by a processing machine: the machine's results are
/// converted back into belt items.
final class ProcessingHandlerView implements pt.TransportedItemStackHandler {
  final TransportedItemStackHandler inner;

  ProcessingHandlerView(this.inner);

  @override
  void handleCenteredProcessingOnAllItems(
    double maxDistanceFromCenter,
    pt.TransportedResult? Function(pt.TransportedItemStack) processFunction,
  ) {
    inner.handleCenteredProcessingOnAllItems(maxDistanceFromCenter, (convItem) {
      final p = toProcessing(convItem);
      final result = processFunction(p);
      copyBack(p, convItem);
      if (result == null) return null;
      return fromProcessingResult(result);
    });
  }

  @override
  void handleProcessingOnAllItems(
    pt.TransportedResult? Function(pt.TransportedItemStack) processFunction,
  ) => handleCenteredProcessingOnAllItems(.51, processFunction);

  @override
  void handleProcessingOnItem(
    pt.TransportedItemStack item,
    pt.TransportedResult result,
  ) => handleCenteredProcessingOnAllItems(
    .51,
    (t) => identical(t, item) ? result : null,
  );

  @override
  (double, double, double) worldPositionOf(
    pt.TransportedItemStack transported,
  ) => inner.getWorldPositionOf(fromProcessing(transported));
}
