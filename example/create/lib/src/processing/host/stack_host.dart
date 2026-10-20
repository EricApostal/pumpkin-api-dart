// Conversions between the pure stacks ([PStack], [PFluid]) and the host's `ItemStack`
// resource and NBT (host side; cannot run on the VM).
//
// The host exposes the vanilla data components of a stack as raw bytes (`getComponents`) and
// the plugin's own `create:*` components through `customComponent`, so a stack survives a
// round trip with all of its components (damage, enchantments, `create:sequenced_assembly`,
// filters, ...). Components that are not registered with the host are dropped.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../content/components.dart' show createComponents;
import '../common/stack.dart';

/// The prefix that marks `create:*` components in [PStack.comps] (as in the equipment module).
const String customComponentPrefix = 'custom:';

final List<String> _customKeys = [for (final c in createComponents) c.key];

/// Host stack conversions.
abstract final class HostStacks {
  /// `ItemStack.getRegistryKey()` drops the namespace of vanilla items (`cobblestone`), while
  /// every recipe, tag and item key of the mod is `namespace:path`. Add the default namespace
  /// back, or no vanilla item ever matches a recipe ingredient.
  static String namespaced(String key) => namespacedItemKey(key);

  /// Reads [stack] (not consumed). `null` and empty stacks give [PStack.empty].
  static Future<PStack> read(ItemStack? stack) async {
    if (stack == null) return PStack.empty;
    final count = await stack.getCount();
    if (count <= 0) return PStack.empty;
    final key = namespaced(await stack.getRegistryKey());
    final max = await stack.getMaxCount();
    final comps = <(String, List<int>)>[];
    for (final c in await stack.getComponents()) {
      comps.add((c.component.wireName, List<int>.of(c.value)));
    }
    for (final k in _customKeys) {
      List<int>? v;
      try {
        v = stack.customComponent(k);
      } on Object {
        v = null;
      }
      if (v != null) comps.add(('$customComponentPrefix$k', List<int>.of(v)));
    }
    comps.sort((a, b) => a.$1.compareTo(b.$1));
    return PStack(key, count, maxStack: max, comps: comps);
  }

  /// A new host stack for [data] (the caller owns it), or `null` for an empty stack.
  static Future<ItemStack?> write(PStack data) async {
    if (data.isEmpty) return null;
    final s = ItemStack.create(registryKey: data.key, count: data.count);
    for (final (name, bytes) in data.comps) {
      if (name.startsWith(customComponentPrefix)) {
        try {
          s.setCustomComponent(
            name.substring(customComponentPrefix.length),
            bytes,
          );
        } on Object {
          // a component the host rejects is dropped
        }
        continue;
      }
      final c = DataComponent.fromWireName(name);
      if (c == null) continue;
      try {
        await s.setComponent(component: c, value: bytes);
      } on Object {
        // a component the host cannot set is dropped
      }
    }
    return s;
  }

  /// A stack without components (cheap): item and count only.
  static ItemStack? simple(PStack data) => data.isEmpty
      ? null
      : ItemStack.create(registryKey: data.key, count: data.count);

  /// Replaces the contents of [stack] with [data]'s component bytes for one component.
  static Future<void> setComponentBytes(
    ItemStack stack,
    String name,
    List<int> bytes,
  ) async {
    if (name.startsWith(customComponentPrefix)) {
      stack.setCustomComponent(
        name.substring(customComponentPrefix.length),
        bytes,
      );
    } else {
      final c = DataComponent.fromWireName(name);
      if (c != null) await stack.setComponent(component: c, value: bytes);
    }
  }
}

/// Persistence of stacks in block entity NBT.
abstract final class StackNbt {
  /// The private persistence form (`id`, `count`, `max`, and `Comps` with the component bytes).
  /// `id` / `count` are also what the Create client reads from an update tag.
  static NbtCompound write(PStack s) {
    final c = NbtCompound()
      ..putString('id', s.key)
      ..putInt('count', s.count);
    if (s.maxStack != 64) c.putInt('Max', s.maxStack);
    if (s.comps.isNotEmpty) {
      c.putList('Comps', <Object>[
        for (final (name, bytes) in s.comps)
          NbtCompound()
            ..putString('N', name)
            ..putByteArray('V', bytes),
      ]);
    }
    return c;
  }

  /// The client form: `{id, count}` only.
  static NbtCompound writeClient(PStack s) => NbtCompound()
    ..putString('id', s.key)
    ..putInt('count', s.count);

  /// `TransferUtil.saveItem` for a possibly empty stack: an empty compound, not
  /// `{id: minecraft:air}` (the Create client and `FilteringBehaviour` expect that).
  static NbtCompound writeOrEmpty(PStack s) =>
      s.isEmpty ? NbtCompound() : write(s);

  static PStack read(NbtCompound? c) {
    if (c == null) return PStack.empty;
    final key = c.getString('id');
    final count = c.getInt('count') ?? 0;
    if (key == null || count <= 0) return PStack.empty;
    final comps = <(String, List<int>)>[];
    for (final e in c.getList('Comps') ?? const <Object>[]) {
      if (e is NbtCompound) {
        final n = e.getString('N');
        final v = e.getByteArray('V');
        if (n != null && v != null) comps.add((n, v));
      }
    }
    comps.sort((a, b) => a.$1.compareTo(b.$1));
    return PStack(key, count, maxStack: c.getInt('Max') ?? 64, comps: comps);
  }

  /// A list of stacks as `{Items: [{Slot, ...stack}], Size}` (`ItemStackHandler.serializeNBT`).
  static NbtCompound writeList(List<PStack> stacks) {
    final items = <Object>[];
    for (var i = 0; i < stacks.length; i++) {
      if (stacks[i].isEmpty) continue;
      items.add(write(stacks[i])..putInt('Slot', i));
    }
    return NbtCompound()
      ..putList('Items', items)
      ..putInt('Size', stacks.length);
  }

  static List<PStack> readList(NbtCompound? c, int size) {
    final out = List<PStack>.filled(size, PStack.empty);
    if (c == null) return out;
    for (final e in c.getList('Items') ?? const <Object>[]) {
      if (e is NbtCompound) {
        final slot = e.getInt('Slot') ?? -1;
        if (slot >= 0 && slot < size) out[slot] = read(e);
      }
    }
    return out;
  }

  /// A fluid stack: `{FluidName, Amount}` (the 1.20 form Create's block entities write; the
  /// client reads it back through the same names).
  static NbtCompound writeFluid(PFluid f) => NbtCompound()
    ..putString('id', f.key)
    ..putInt('amount', f.amount);

  static PFluid readFluid(NbtCompound? c) {
    if (c == null) return PFluid.empty;
    final key = c.getString('id');
    final amount = c.getInt('amount') ?? 0;
    if (key == null || amount <= 0) return PFluid.empty;
    return PFluid(key, amount);
  }
}
