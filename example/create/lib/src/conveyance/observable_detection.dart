// The detection rules of the observable probes (pure): what the smart observer does with the
// items on a belt/depot and the packages looping on a chain conveyor.
// `SmartObserverBlockEntity.tick` of the Java mod.
import '../api/observable.dart';
import 'behaviours/belt_interfaces.dart';
import 'items/item_data.dart';

/// `TransportedItemStackHandlerBehaviour.handleCenteredProcessingOnAllItems(.45f, ...)` with a
/// filter test: whether any item near the belt centre passes [filter].
bool beltDetects(TransportedItemStackHandler handler, ObserverFilter filter) {
  var detected = false;
  handler.handleCenteredProcessingOnAllItems(.45, (item) {
    if (!detected && filter.testItem(item.stack.key)) detected = true;
    // `TransportedResult.doNothing()`: the observer never changes the belt.
    return null;
  });
  return detected;
}

/// The addresses of the packages looping on a chain conveyor that pass [filter]
/// (`ChainConveyorBlockEntity.getLoopingPackages` then `filtering.test(box.item)`).
List<String> chainLoopingAddresses(Iterable<ItemValue> looping, ObserverFilter filter) => [
  for (final item in looping)
    if (filter.testItem(item.key)) packageAddressOf(item),
];
