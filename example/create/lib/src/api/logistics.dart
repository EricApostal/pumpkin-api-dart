/// The logistics module's API for the other modules (published by `LogisticsModule`): packages,
/// stock, filters, unpacking. Import `package:create/src/api/logistics.dart`.
///
/// Pure model (usable in tests): [LStack] (an item stack as a value), [BigStack],
/// [InventorySummary], the orders, [PackageItem] / [PackageStyles], [ItemInv] / [MemoryInv],
/// [GlobalLogisticsManager], the filters and item attributes, the unpacking handlers and the
/// package port targets.
library;

export '../logistics/filter/filter_item_stack.dart';
export '../logistics/filter/item_attribute.dart';
export '../logistics/model/glob.dart' show globMatches, globToRegexPattern;
export '../logistics/model/inventory.dart';
export '../logistics/model/manager.dart';
export '../logistics/model/network.dart';
export '../logistics/model/orders.dart';
export '../logistics/model/package.dart';
export '../logistics/model/stack.dart';
export '../logistics/model/stack_wire.dart'
    show StackWire, StackInfo, removedComponent;
export '../logistics/packager/repackager/repackage_helper.dart';
export '../logistics/packager/unpacking.dart';
export '../logistics/port/package_port_target.dart';
export '../logistics/requester/auto_request_data.dart';
