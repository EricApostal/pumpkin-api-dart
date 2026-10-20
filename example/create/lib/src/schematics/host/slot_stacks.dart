// Host item stacks <-> [SlotStack] (plain data), with persistence in plugin NBT. The vanilla
// components travel as raw bytes (`get-components`), the custom `create:*` components through the
// custom component API.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/nbt_convert.dart';
import '../../common/stack_tag.dart';
import '../../content/components.dart';
import '../schematic_stack.dart';

abstract final class HostSlotStacks {
  /// Keys of the custom components read from stacks.
  static final List<String> customKeys = [for (final c in createComponents) c.key];

  /// Reads [stack] (not consumed). `null` and empty stacks give [SlotStack.empty].
  static Future<SlotStack> read(ItemStack? stack, {bool vanillaComponents = true}) async {
    if (stack == null) return SlotStack.empty;
    final count = await stack.getCount();
    if (count <= 0) return SlotStack.empty;
    final key = await stack.getRegistryKey();
    final components = <String, Uint8List>{};
    if (vanillaComponents) {
      for (final c in await stack.getComponents()) {
        components[c.component.wireName] = Uint8List.fromList(c.value);
      }
    }
    // Only the schematic family of custom components is worth the host calls for most stacks.
    for (final k in SchematicStackData.allKeys) {
      final v = stack.customComponent(k);
      if (v != null) components[k] = v;
    }
    return SlotStack(key, count, components);
  }

  /// Reads all custom components (used when the stack may carry any Create data).
  static Future<SlotStack> readAll(ItemStack? stack) async {
    final base = await read(stack);
    if (base.isEmpty) return base;
    final components = Map<String, Uint8List>.of(base.components);
    for (final k in customKeys) {
      final v = stack!.customComponent(k);
      if (v != null) components[k] = v;
    }
    return SlotStack(base.item, base.count, components);
  }

  /// A new host stack (owned by the caller), or `null` for an empty stack.
  static Future<ItemStack?> write(SlotStack s) async {
    if (s.isEmpty) return null;
    final stack = ItemStack.create(registryKey: s.item, count: s.count);
    for (final e in s.components.entries) {
      try {
        if (e.key.contains(':')) {
          stack.setCustomComponent(e.key, e.value);
        } else {
          final c = DataComponent.fromWireName(e.key);
          if (c != null) await stack.setComponent(component: c, value: e.value);
        }
      } on Object {
        // a component the host does not accept is dropped
      }
    }
    return stack;
  }

  /// The persistence form of a slot stack: Java's `ItemStack.CODEC` shape, with the plugin's own
  /// component bytes (see `common/stack_tag.dart`).
  static NbtCompound toNbt(SlotStack s) => compoundOf(
        JavaStackTag.write(
          id: s.item,
          count: s.count,
          comps: [for (final e in s.components.entries) (e.key, e.value)],
          components: s.rawComponents,
        ),
      );

  static SlotStack fromNbt(NbtCompound c) {
    final t = JavaStackTag.read(valueOfCompound(c));
    if (t == null) return SlotStack.empty;
    return SlotStack(
      t.id,
      t.count,
      {for (final (name, bytes) in t.comps) name: Uint8List.fromList(bytes)},
      t.components,
    );
  }

  /// The client's view of a stack (`ItemStack.CODEC`: `id` and `count`, plus the components of a
  /// Java save), used for the missing item shown in the cannon GUI.
  static NbtCompound toClientNbt(SlotStack s) =>
      compoundOf(JavaStackTag.writeClient(id: s.item, count: s.count, components: s.rawComponents));
}
