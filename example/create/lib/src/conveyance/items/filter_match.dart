// `FilterItemStack.test(world, stack)` as the conveyance filter slots use it (pure): the filter
// item of a funnel, brass tunnel, chute or smart chute is matched by the logistics module's
// `ItemFilterApi`; a plain item matches itself, an empty slot everything.
import '../../api/filter_api.dart' show FilterItemValue, ItemFilterApi;
import 'item_data.dart';

/// Items that never act as a filter when held (`canShortInteract`).
const Set<String> notFilterItems = {'create:wrench', 'create:mechanical_arm'};

/// The filter items (`FilterItem`): list, attribute and package filters.
bool isFilterItemKey(String key) =>
    key == 'create:filter' || key == 'create:attribute_filter' || key == 'create:package_filter';

/// Where [filterTest] finds the logistics module's `ItemFilterApi`. The conveyance module
/// installs its runtime's services in `onLoad`; without them (no logistics module) a filter item
/// matches nothing.
ItemFilterApi? Function() itemFilterApi = () => null;

/// `FilterItemStack.test(world, stack)` for the filter [filter].
bool filterTest(ItemValue filter, ItemValue stack, {required String worldId}) {
  if (filter.isEmpty) return true;
  switch (filter.key) {
    case 'create:filter' || 'create:attribute_filter':
      final api = itemFilterApi();
      if (api == null) return false;
      return api.testItem(
        worldId,
        FilterItemValue(
          filter.key,
          count: filter.count,
          components: filter.comps,
        ),
        stack.key,
      );
    case 'create:package_filter':
      if (!isPackageKey(stack.key)) return false;
      return matchPackage(stack, packageAddressOf(filter));
  }
  return !stack.isEmpty && stack.key == filter.key;
}
