// The native half of the `peripheral` API. `rom/apis/peripheral.lua` builds
// `peripheral.wrap`, `find` and `getNames` on top of these functions.
import '../../lua/lua.dart';
import '../peripheral.dart';
import '../side.dart';

/// Looks up what is attached to a side, for the `peripheral` table.
abstract interface class PeripheralLookup {
  /// The peripheral on [side] with the access it was attached with.
  (Peripheral, PeripheralAccess)? attached(ComputerSide side);
}

LuaTable buildPeripheralApi(PeripheralLookup lookup) {
  final table = LuaTable();

  (Peripheral, PeripheralAccess)? find(String name) {
    final side = ComputerSide.parse(name);
    return side == null ? null : lookup.attached(side);
  }

  void def(String name, NativeImpl impl) =>
      table.setString(name, NativeFunction(name, impl));

  def('isPresent', (list) => one(find(Args('isPresent', list).string(0)) != null));

  def('getType', (list) {
    final found = find(Args('getType', list).string(0));
    if (found == null) return one(null);
    return <Object?>[found.$1.type, ...found.$1.additionalTypes];
  });

  def('hasType', (list) {
    final args = Args('hasType', list);
    final found = find(args.string(0));
    if (found == null) return one(null);
    final type = args.string(1);
    return one(found.$1.type == type || found.$1.additionalTypes.contains(type));
  });

  def('getMethods', (list) {
    final found = find(Args('getMethods', list).string(0));
    if (found == null) return one(null);
    final methods = LuaTable();
    var i = 1;
    for (final name in found.$1.methodNames) {
      methods.setInt(i++, name);
    }
    return one(methods);
  });

  def('call', (list) {
    final args = Args('call', list);
    final found = find(args.string(0));
    final method = args.string(1);
    if (found == null) throw LuaError.message('No peripheral attached');
    return found.$1.call(found.$2, method, list.sublist(2));
  });

  return table;
}
