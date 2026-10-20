// The identity-preserving forms of the two stack types (pure). Java passes the live
// `TransportedItemStack` from a belt into the machine above it and back
// (`BeltInventory.java:254,287` -> `BeltPressingCallbacks.whenItemHeld` ->
// `TransportedItemStackHandlerBehaviour.handleProcessingOnItem`, which matches with `t == item`),
// so a belt item and its processing form have to be the same object for as long as both sides can
// see it. This file keeps one form per item and the two handler views the bridge is built from;
// the host behaviours themselves are adapted in `processing_bridge.dart`.
import '../../common/direction.dart';
import '../../common/vec_helper.dart' show Vec3;
import '../../processing/transport/transported_stack.dart' as pt;
import '../belt/transported_item.dart' as belt;
import '../items/stack_bridge.dart';
import 'belt_interfaces.dart';

/// One processing form per belt item; one belt form per processing item. Java passes the *live*
/// `TransportedItemStack` through both sides of this bridge, and `handleProcessingOnItem`
/// compares with `t == item` (`TransportedItemStackHandlerBehaviour.java:102-108`): the machine
/// above a belt hands back its result for the very object the belt gave it. Converting at the
/// boundary would give every call a fresh object and the identity test would never pass, so each
/// live object keeps a single form that is re-synced on the way in and written back on the way
/// out. (`Expando` keys weakly: the form dies with the item.)
final Expando<pt.TransportedItemStack> _processingForms = Expando('processing form of a belt item');
final Expando<belt.TransportedItemStack> _beltForms = Expando('belt form of a processing item');

/// How many machine callbacks are running right now (`live`).
int _liveDepth = 0;

/// Runs a machine callback with the pairs it was handed treated as live: nested conversions
/// return the very object the machine already holds instead of re-syncing it from the other side,
/// which would undo the mutations it made in place (Java keeps those by passing one object all
/// the way through). Outside of [live] a conversion re-syncs, because the belt side owns the item.
T live<T>(T Function() body) {
  _liveDepth++;
  try {
    return body();
  } finally {
    _liveDepth--;
  }
}

/// The processing form of a belt item: one instance per [t], re-synced from [t] unless a machine
/// callback is running.
pt.TransportedItemStack toProcessing(belt.TransportedItemStack t) {
  final existing = _processingForms[t];
  if (existing != null) {
    if (_liveDepth == 0) copyToProcessing(t, existing);
    return existing;
  }
  final p = pt.TransportedItemStack(toPStack(t.stack));
  copyToProcessing(t, p);
  _processingForms[t] = p;
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

/// The belt form of a processing item: one instance per [t] (see [toProcessing]).
belt.TransportedItemStack fromProcessing(pt.TransportedItemStack t) {
  final existing = _beltForms[t];
  if (existing != null) {
    if (_liveDepth == 0) copyBack(t, existing);
    return existing;
  }
  final out = belt.TransportedItemStack.raw(fromPStack(t.stack));
  copyBack(t, out);
  _beltForms[t] = out;
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
      final result = live(() => processFunction(convItem));
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
      final result = live(() => processFunction(p));
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
