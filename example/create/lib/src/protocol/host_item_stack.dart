// Conversions between the wire item stack (`ItemStackData`) and the host's `ItemStack`
// resource. The host resource exposes no component serialisation, so:
//
//  * `HostItemStacks.toHost` creates a stack of the item and the count; the component
//    patch is NOT applied (a client-sent patch such as custom_data cannot be set generically).
//  * `HostItemStacks.fromHost` reads item and count; the patch is empty.
//
// Modules that need components keep their own representation (for example Create's
// filter items live in the block entity NBT) and use `ItemStackData` only for the wire.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/registry.dart' show RegistryKind;
import '../core/registry_apply.dart' show AppliedIds;
import 'item_stack.dart';

abstract final class HostItemStacks {
  /// An [ItemIdResolver] for the vanilla items plus the items this plugin registered
  /// (`ctx.ids`). [ids] is read lazily, so passing `() => ctx.ids` is fine.
  static ItemIdResolver resolverFor(AppliedIds Function() ids) {
    Map<int, String>? reverse;
    return ItemIdResolver.vanilla(
      custom: (key) => ids().of(RegistryKind.items, key),
      customKey: (id) {
        reverse ??= {for (final e in ids().all(RegistryKind.items).entries) e.value: e.key};
        return reverse![id];
      },
    );
  }

  /// A host stack (owned by the caller) for [data], or `null` when empty or the item id is unknown.
  static ItemStack? toHost(ItemStackData data, ItemIdResolver ids) {
    if (data.isEmpty) return null;
    final key = ids.keyOf(data.itemId);
    if (key == null) return null;
    return ItemStack.create(registryKey: key, count: data.count);
  }

  /// The wire form of [stack] (empty patch), or [ItemStackData.empty] for a null stack,
  /// a count of 0, or an item the resolver does not know.
  static Future<ItemStackData> fromHost(ItemStack? stack, ItemIdResolver ids) async {
    if (stack == null) return ItemStackData.empty;
    final count = await stack.getCount();
    if (count <= 0) return ItemStackData.empty;
    final id = ids.idOf(await stack.getRegistryKey());
    return id == null ? ItemStackData.empty : ItemStackData(id, count);
  }
}
