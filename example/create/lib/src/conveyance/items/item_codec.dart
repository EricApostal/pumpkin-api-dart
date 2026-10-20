// Host glue for [ItemValue]: reading and writing the host's `ItemStack` resources (item,
// count and data components as raw bytes), the persistence tag of a stack (Java's
// `ItemStack.CODEC` shape, see `common/stack_tag.dart`), the client NBT form, and dropping /
// giving stacks.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/nbt_convert.dart';
import '../../common/stack_tag.dart';
import '../../manifest/manifest.dart';
import 'item_data.dart';

/// The custom `create:*` components of the manifest: they are invisible to `getComponents`,
/// so they are read by key.
final List<String> customComponentKeys = [for (final c in kDataComponents) 'create:${c.key}'];

abstract final class ItemCodec {
  /// Prefix of component names that are custom (`create:*`) components.
  static const String customPrefix = customComponentPrefix;

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

  /// The persistence form of a stack: Java's `ItemStack.CODEC` tag (`id`, `count`, and the
  /// `components` of a Java save, written back unchanged), plus the plugin's own lossless extras
  /// (`Max`, `Dmg`, and `Comps` with the network-encoded component bytes). An empty compound for
  /// an empty stack.
  static NbtCompound toNbt(ItemValue t) => t.isEmpty
      ? NbtCompound()
      : compoundOf(
          JavaStackTag.write(
            id: t.key,
            count: t.count,
            comps: t.comps,
            components: t.rawComponents,
            maxStack: t.maxStack,
            damageable: t.damageable,
          ),
        );

  /// The stack of either persistence form, or [ItemValue.empty] when the tag holds none.
  static ItemValue fromNbt(NbtCompound? c) {
    final t = JavaStackTag.read(c == null ? null : valueOfCompound(c));
    if (t == null) return ItemValue.empty;
    return ItemValue(
      t.id,
      t.count,
      maxStack: t.maxStack ?? defaultMaxStack(t.id),
      damageable: t.damageable ?? false,
      comps: t.comps,
      rawComponents: t.components,
    );
  }

  /// The stack tag the Create client reads from an update tag (`ItemStack.CODEC`: `{id, count}`
  /// and, when a Java save provided them, its components).
  static NbtCompound toClientNbt(ItemValue t) => t.isEmpty
      ? NbtCompound()
      : compoundOf(JavaStackTag.writeClient(id: t.key, count: t.count, components: t.rawComponents));

  /// `TransferUtil.parseItem` for the client form: the item and count, with the components of a
  /// Java save preserved (the plugin cannot decode them).
  static ItemValue fromClientNbt(NbtCompound? c) => fromNbt(c);

  /// Reads either the Java form ([fromNbt] handles both) or the plugin's own older form.
  static ItemValue fromAnyNbt(NbtCompound? c) => fromNbt(c);

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
