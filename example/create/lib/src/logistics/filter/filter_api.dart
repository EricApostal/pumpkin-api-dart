// The `ItemFilterApi` service: other modules keep a filter slot's item and ask this module to
// match candidates against it. The matching itself is `FilterItemStack`; this adapter only turns
// the API's [FilterItemValue] into the module's [LStack] and hands over the wire that decodes the
// ghost slots of a list filter.
import 'dart:convert';

import '../../api/filter_api.dart' show FilterItemValue, ItemFilterApi;
import '../model/stack.dart';
import '../model/stack_wire.dart';
import 'filter_item_stack.dart';

/// `FilterItemStack` behind [ItemFilterApi].
///
/// [worldId] is not used: Java's item test (`FilterItem.testDirect`, `ListFilterItemStack.test`)
/// compares stacks only, and the fluid of a filter item comes from the `FilterItemStack.filterFluid`
/// hook the filter part installs (`FilterPart._installFluidHooks`), not from a level.
final class ItemFilterApiAdapter implements ItemFilterApi {
  const ItemFilterApiAdapter();

  /// The wire that decodes the stacks contained in a list filter: the logistics runtime's
  /// (`LgRuntime.wire`, the server's component ids). The filter part installs it; `null` outside
  /// a loaded module, which leaves a list filter's ghost slots undecodable (it then matches
  /// nothing as a whitelist, everything as a blacklist, like an unreadable component).
  static StackWire? Function() wire = () => null;

  @override
  bool testItem(String worldId, FilterItemValue filter, String candidateItem) =>
      _stackOf(filter).test(LStack.of(candidateItem));

  @override
  bool testFluid(String worldId, FilterItemValue filter, String fluidKey) =>
      _stackOf(filter).testFluid(fluidKey);

  FilterItemStack _stackOf(FilterItemValue filter) {
    if (filter.isEmpty) return FilterItemStack.empty;
    return FilterItemStack.of(
      LStack(filter.key, filter.count, comps: _components(filter)),
      wire: wire(),
    );
  }

  /// [LStack] keeps components base64-encoded; the sort makes [LStack.sameItemSameComponents]
  /// a plain map comparison.
  static Map<String, String> _components(FilterItemValue filter) {
    if (filter.components.isEmpty) return const {};
    final comps = <String, String>{
      for (final (name, bytes) in filter.components) name: base64Encode(bytes),
    };
    return Map.fromEntries(
      comps.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }
}
