// Bridges between the conveyance belt stack types ([TransportedItemStack] of `belt/`) and the
// processing machines' types (`processing/transport`). Belts move [ItemValue]s; the machines
// above them (press, saw, basin, fan, ...) add `BeltProcessingBehaviour`,
// `DirectBeltInputBehaviour` and `TransportedItemStackHandlerBehaviour`, which speak [PStack].
// The conversions and the handler views live in `item_forms.dart` (pure, and where the identity
// of an item across the bridge is kept); this file only adapts the host behaviours.
import 'dart:async';

import '../../common/direction.dart';
import '../../processing/transport/transport_behaviours.dart' as pt;
import '../belt/transported_item.dart' as belt;
import '../items/item_data.dart';
import '../items/stack_bridge.dart';
import 'belt_interfaces.dart';
import 'item_forms.dart';

export 'item_forms.dart';

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
    final result = live(
      () => behaviour.handleReceivedItem(p, ProcessingHandlerView(inventory)),
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
    final result = live(
      () => behaviour.handleHeldItem(p, ProcessingHandlerView(inventory)),
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
    final remainder = live(
      () => behaviour.handleInsertion(p, side.serializedName, simulate),
    );
    copyBack(p, stack);
    return fromPStack(remainder);
  }

  @override
  bool get canSupportBeltFunnels => behaviour.supportsBeltFunnels;
}
