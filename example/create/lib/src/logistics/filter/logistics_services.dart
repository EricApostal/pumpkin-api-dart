// What the logistics module offers the other modules: the `ItemFilterApi` provider and the
// `in_item_group` hook of the attribute filter. Kept apart from `logistics_module.dart` (which
// imports the parts and so the host bindings) so the wiring is testable on the VM.
import '../../api/filter_api.dart' show ItemFilterApi;
import '../../core/services.dart';
import 'filter_api.dart';
import 'item_attribute.dart' show ItemAttributeHooks, creativeTabContainsItem;

/// Registers the services of the logistics module (called from `LogisticsModule.onLoad`).
///
/// A server without logistics has no [ItemFilterApi] provider: the consumers (`filtering.dart`,
/// the smart observer, the deployer, the track observer) answer "no" for a filter item instead of
/// pretending it matches.
void installLogisticsServices(CreateServices services) {
  services.provide<ItemFilterApi>(const ItemFilterApiAdapter());
  // `InItemGroupAttribute.Type`: the creative tabs of the shipped manifest.
  ItemAttributeHooks.itemInGroup = creativeTabContainsItem;
}
