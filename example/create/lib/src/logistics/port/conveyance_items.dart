// Conversions between the logistics module's [LStack] and the conveyance module's [ItemValue]
// (pure). Both describe an item, a count and the data components; the two modules only differ in
// how the package components are held:
//  * [LStack.comps] keeps them by logical name with their *logical* (UTF-8 / JSON) value,
//  * [ItemValue.comps] keeps them under `custom:<name>` with their *wire* value.
// The chain conveyor hands packages to a frogport as an [ItemValue] and takes them back the same
// way, so a frogport needs both directions.
import 'dart:convert';

import '../../conveyance/items/item_data.dart' as cv;
import '../model/package.dart';
import '../model/stack.dart';
import '../model/stack_wire.dart';

const String _customPrefix = 'custom:';

/// The conveyance value of [stack]. Components that cannot be encoded in the wire form are left
/// out (like a stack that lost them on the way through a vanilla container).
cv.ItemValue toItemValue(LStack stack, StackWire wire) {
  if (stack.isEmpty) return cv.ItemValue.empty;
  final comps = <(String, List<int>)>[];
  for (final entry in stack.comps.entries) {
    if (entry.value == removedComponent) continue;
    final bytes = base64Decode(entry.value);
    if (PackageComponents.logical.contains(entry.key)) {
      final encoded = wire.logicalToWire(entry.key, bytes);
      if (encoded != null) comps.add(('$_customPrefix${entry.key}', encoded));
    } else if (entry.key.startsWith('create:')) {
      comps.add(('$_customPrefix${entry.key}', bytes));
    } else {
      comps.add((entry.key, bytes));
    }
  }
  comps.sort((a, b) => a.$1.compareTo(b.$1));
  return cv.ItemValue(
    stack.key,
    stack.count,
    maxStack: stack.maxStack,
    damageable: stack.damageable,
    comps: comps,
  );
}

/// The logistics value of [value]; unreadable package components are dropped.
LStack fromItemValue(cv.ItemValue value, StackWire wire) {
  if (value.isEmpty) return LStack.empty;
  final comps = <String, String>{};
  for (final (name, bytes) in value.comps) {
    final key = name.startsWith(_customPrefix)
        ? name.substring(_customPrefix.length)
        : name;
    if (PackageComponents.logical.contains(key)) {
      final logical = wire.wireToLogical(key, bytes);
      if (logical != null) comps[key] = base64Encode(logical);
    } else {
      comps[key] = base64Encode(bytes);
    }
  }
  return LStack(
    value.key,
    value.count,
    maxStack: value.maxStack,
    damageable: value.damageable,
    comps: Map.fromEntries(
      comps.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
  );
}
