// Host glue for [ItemValue]: reading and writing the host's `ItemStack` resources (item,
// count and data components as raw bytes), the plugin's private NBT form of a stack, the
// client NBT form, and dropping / giving stacks.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../manifest/manifest.dart';
import 'item_data.dart';

/// The custom `create:*` components of the manifest: they are invisible to `getComponents`,
/// so they are read by key.
final List<String> customComponentKeys = [for (final c in kDataComponents) 'create:${c.key}'];

abstract final class ItemCodec {
  /// Prefix of component names that are custom (`create:*`) components.
  static const String customPrefix = 'custom:';

  /// Reads [stack] (not consumed) into a value.
  static Future<ItemValue> read(ItemStack? stack) async {
    if (stack == null) return ItemValue.empty;
    final count = await stack.getCount();
    if (count <= 0) return ItemValue.empty;
    final key = await stack.getRegistryKey();
    final max = await stack.getMaxCount();
    final comps = <(String, List<int>)>[];
    var maxDamage = 0;
    for (final c in await stack.getComponents()) {
      comps.add((c.component.wireName, List<int>.of(c.value)));
      if (c.component == DataComponent.maxDamage) maxDamage = _varInt(c.value);
    }
    for (final k in customComponentKeys) {
      List<int>? v;
      try {
        v = stack.customComponent(k);
      } on Object {
        v = null;
      }
      if (v != null) comps.add(('$customPrefix$k', List<int>.of(v)));
    }
    comps.sort((a, b) => a.$1.compareTo(b.$1));
    return ItemValue(_normalizeKey(key), count, maxStack: max, damageable: maxDamage > 0, comps: comps);
  }

  /// A new host stack for [data] with its components (the caller owns it), `null` when empty.
  static Future<ItemStack?> write(ItemValue data) async {
    if (data.isEmpty) return null;
    final s = ItemStack.create(registryKey: data.key, count: data.count);
    for (final (name, bytes) in data.comps) {
      if (name.startsWith(customPrefix)) {
        try {
          s.setCustomComponent(name.substring(customPrefix.length), bytes);
        } on Object {
          // a custom component the host rejects is dropped
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

  static String _normalizeKey(String key) => key.contains(':') ? key : 'minecraft:$key';

  static int _varInt(List<int> bytes) {
    var value = 0;
    var shift = 0;
    for (final b in bytes) {
      value |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
    }
    return value;
  }

  // -- Plugin NBT -------------------------------------------------------------------------

  /// The private persistence form of a stack (`Key`, `Count`, `Max`, `Dmg`, `Comps`), an
  /// empty compound for an empty stack.
  static NbtCompound toNbt(ItemValue t) {
    final c = NbtCompound();
    if (t.isEmpty) return c;
    c
      ..putString('Key', t.key)
      ..putInt('Count', t.count)
      ..putInt('Max', t.maxStack)
      ..putBool('Dmg', t.damageable);
    if (t.comps.isNotEmpty) {
      c.putList('Comps', [
        for (final (name, bytes) in t.comps)
          NbtCompound()
            ..putString('N', name)
            ..putByteArray('V', bytes),
      ]);
    }
    return c;
  }

  static ItemValue fromNbt(NbtCompound? c) {
    if (c == null) return ItemValue.empty;
    final key = c.getString('Key');
    final count = c.getInt('Count') ?? 0;
    if (key == null || count <= 0) return ItemValue.empty;
    final comps = <(String, List<int>)>[];
    for (final e in c.getList('Comps') ?? const <Object>[]) {
      if (e is NbtCompound) {
        final n = e.getString('N');
        final v = e.getByteArray('V');
        if (n != null && v != null) comps.add((n, v));
      }
    }
    comps.sort((a, b) => a.$1.compareTo(b.$1));
    return ItemValue(key, count, maxStack: c.getInt('Max') ?? defaultMaxStack(key), damageable: c.getBool('Dmg') ?? false, comps: comps);
  }

  /// The stack tag the Create client reads from an update tag (`ItemStack.CODEC`:
  /// `{id, count}`; components are not representable).
  static NbtCompound toClientNbt(ItemValue t) {
    final c = NbtCompound();
    if (t.isEmpty) return c;
    return c
      ..putString('id', t.key)
      ..putInt('count', t.count);
  }

  /// `TransferUtil.parseItem` for the client form (no components).
  static ItemValue fromClientNbt(NbtCompound? c) {
    if (c == null) return ItemValue.empty;
    final id = c.getString('id');
    final count = c.getInt('count') ?? c.getInt('Count') ?? 1;
    if (id == null || count <= 0) return ItemValue.empty;
    return ItemValue(id, count, maxStack: defaultMaxStack(id));
  }

  /// Reads either the private form ([toNbt]) or the client form ([toClientNbt]).
  static ItemValue fromAnyNbt(NbtCompound? c) {
    if (c == null) return ItemValue.empty;
    return c.getString('Key') != null ? fromNbt(c) : fromClientNbt(c);
  }

  /// [toNbt] when saving, [toClientNbt] for the client update tag.
  static NbtCompound toTag(ItemValue t, {required bool clientPacket}) => clientPacket ? toClientNbt(t) : toNbt(t);

  // -- Writing into the world ---------------------------------------------------------------

  /// Drops [data] as an item entity at [pos] (`new ItemEntity` + `addFreshEntity`).
  static Future<void> drop(
    World world,
    (double, double, double) pos,
    ItemValue data, {
    (double, double, double)? velocity,
    int? pickupDelay,
  }) async {
    final stack = await write(data);
    if (stack == null) return;
    await world.dropItem(pos, stack, velocity: velocity, pickupDelay: pickupDelay);
  }

  /// `Inventory.placeItemBackInInventory`: gives [data] to [player], dropping what does not fit
  /// at the player.
  static Future<void> giveToPlayer(Player player, ItemValue data) async {
    final stack = await write(data);
    if (stack == null) return;
    final left = await player.give(stack);
    if (left != null) {
      final pos = player.getPosition();
      await player.getWorld().dropItem(pos, left);
    }
  }
}
