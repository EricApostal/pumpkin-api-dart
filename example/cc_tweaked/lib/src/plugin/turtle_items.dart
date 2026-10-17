// Host item stacks as the turtle model sees them, and the turtle items
// themselves: the data components CC: Tweaked puts on a turtle item
// (`TurtleBlockEntity.collectSafeComponents` / `applyImplicitComponents`).
//
// A turtle's inventory is plain data (`TurtleStack`: item key, count and the
// network bytes of the components), so the plugin converts at the edge. What the
// host can read and write of a stack is what survives: vanilla components that
// the host can serialise (`item-stack.get-components` returns the set ones in
// their network encoding) and CC's own custom components. Components of other
// plugins' custom types are not visible to `get-components` and are lost when
// an item passes through a turtle (docs/host-requirements.md).
import 'dart:async';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart' show VanillaRegistries;

import '../protocol/components.dart';
import '../protocol/registries.dart';
import '../turtle/stack.dart';
import '../turtle/upgrades.dart';

/// The custom components of CC: Tweaked, the keys the host keeps apart from
/// the vanilla ones.
final List<String> _customKeys = [for (final type in CcComponents.all) type.key];

/// Converts between host stacks and [TurtleStack]s and answers item questions.
final class HostItems implements ItemInfo {
  final Map<String, int> _maxStack = {};

  /// The stack size of [item]. The host answers asynchronously, so this
  /// reads what [loadMaxStack] has fetched (every item that enters a turtle
  /// through [fromHost] or [toHost] has been) and assumes 64 for others, which
  /// it starts to fetch.
  @override
  int maxStack(String item) {
    final cached = _maxStack[item];
    if (cached != null) return cached;
    unawaited(loadMaxStack(item));
    return 64;
  }

  /// Fetches the stack size of [item] from the host and remembers it.
  Future<int> loadMaxStack(String item) async {
    final cached = _maxStack[item];
    if (cached != null) return cached;
    var max = 64;
    try {
      final probe = ItemStack.create(registryKey: item, count: 1);
      try {
        max = await probe.getMaxCount();
      } finally {
        probe.dispose();
      }
    } catch (_) {
      // An item the host does not know: treat it as a normal stack.
    }
    if (max < 1) max = 1;
    return _maxStack[item] = max;
  }

  /// The model of [stack]; the host stack is not changed or disposed.
  Future<TurtleStack> fromHost(ItemStack stack) async {
    final components = <StackComponent>[];
    var damaged = false;
    var enchanted = false;
    for (final value in await stack.getComponents()) {
      components.add(StackComponent(value.component.index, Uint8List.fromList(value.value)));
      if (value.component == DataComponent.damage) {
        damaged = _varInt(value.value) > 0;
      } else if (value.component == DataComponent.enchantments || value.component == DataComponent.attributeModifiers) {
        enchanted = true;
      }
    }
    final custom = <String, Uint8List>{};
    for (final key in _customKeys) {
      final bytes = stack.customComponent(key);
      if (bytes != null) custom[key] = bytes;
    }
    final key = await stack.getRegistryKey();
    await loadMaxStack(key);
    return TurtleStack(
      key,
      await stack.getCount(),
      components: components,
      custom: custom,
      damaged: damaged,
      enchanted: enchanted,
    );
  }

  /// A new host stack for [stack] (owned by the caller).
  Future<ItemStack> toHost(TurtleStack stack) async {
    await loadMaxStack(stack.item);
    final result = ItemStack.create(registryKey: stack.item, count: stack.count);
    for (final component in stack.components) {
      if (component.type < 0 || component.type >= DataComponent.values.length) continue;
      try {
        await result.setComponent(component: DataComponent.values[component.type], value: component.value);
      } catch (e) {
        logger.warn('Could not restore a component of ${stack.item}: $e');
      }
    }
    for (final entry in stack.custom.entries) {
      try {
        result.setCustomComponent(entry.key, entry.value);
      } on PluginRegistryException catch (e) {
        logger.warn('Could not restore ${entry.key} of ${stack.item}: ${e.message}');
      }
    }
    return result;
  }

  static int _varInt(List<int> bytes) {
    try {
      return PacketReader(bytes).readVarInt();
    } on PacketException {
      return 0;
    }
  }

  /// A short text that changes when the stack changes (to tell whether a menu
  /// slot needs to be sent again).
  static String signature(TurtleStack? stack) {
    if (stack == null) return '';
    final buffer = StringBuffer('${stack.item}#${stack.count}');
    for (final component in stack.components) {
      buffer.write('|${component.type}:${component.value.length}:${_hash(component.value)}');
    }
    for (final entry in stack.custom.entries) {
      buffer.write('|${entry.key}:${_hash(entry.value)}');
    }
    return buffer.toString();
  }

  static int _hash(List<int> bytes) {
    var h = 17;
    for (final b in bytes) {
      h = (h * 31 + b) & 0x3FFFFFFF;
    }
    return h;
  }
}

/// The turtle items' item key of a block: `computercraft:turtle_normal` is both.
bool isTurtleKey(String key) => key == 'computercraft:turtle_normal' || key == 'computercraft:turtle_advanced';

/// What a turtle item carries (the components of `TurtleItem`).
final class TurtleItemData {
  int? computerId;
  String? label;

  /// `dyed_color` (0xRRGGBB) or -1.
  int colour = -1;
  int fuel = 0;
  String? overlay;
  UpgradeInstance? left;
  UpgradeInstance? right;

  TurtleItemData();

  /// Reads the components of a turtle item.
  static Future<TurtleItemData> read(ItemStack stack, TurtleUpgrades upgrades) async {
    final data = TurtleItemData();
    final id = stack.customComponent(CcComponents.computerId);
    if (id != null) {
      try {
        data.computerId = CcComponents.decodeComputerId(id);
      } on PacketException {
        // A corrupt component: the turtle starts without an id.
      }
    }
    final name = (await stack.getCustomName())?.getText();
    data.label = name == null || name.isEmpty ? null : name;
    final fuel = stack.customComponent(CcComponents.fuel);
    if (fuel != null) {
      try {
        data.fuel = CcComponents.decodeFuel(fuel);
      } on PacketException {
        data.fuel = 0;
      }
    }
    final overlay = stack.customComponent(CcComponents.overlay);
    if (overlay != null) {
      try {
        data.overlay = CcComponents.decodeOverlay(overlay);
      } on PacketException {
        data.overlay = null;
      }
    }
    data.left = _readUpgrade(stack.customComponent(CcComponents.leftTurtleUpgrade), upgrades);
    data.right = _readUpgrade(stack.customComponent(CcComponents.rightTurtleUpgrade), upgrades);
    for (final component in await stack.getComponents()) {
      if (component.component == DataComponent.dyedColor && component.value.length >= 4) {
        final v = component.value;
        data.colour = ((v[0] << 24) | (v[1] << 16) | (v[2] << 8) | v[3]) & 0xFFFFFF;
      }
    }
    return data;
  }

  static UpgradeInstance? _readUpgrade(Uint8List? bytes, TurtleUpgrades upgrades) {
    if (bytes == null) return null;
    try {
      final (id, patch) = CcComponents.decodeUpgrade(bytes);
      final upgrade = upgrades.byId(id);
      return upgrade == null ? null : UpgradeInstance(upgrade, patch.isEmpty ? null : patch);
    } on PacketException {
      return null;
    }
  }

  /// A new turtle item stack of [blockKey] (`computercraft:turtle_normal`)
  /// with these components (owned by the caller).
  Future<ItemStack> build(String blockKey) async {
    final stack = ItemStack.create(registryKey: blockKey, count: 1);
    final id = computerId;
    if (id != null) stack.setCustomComponent(CcComponents.computerId, CcComponents.encodeComputerId(id));
    final name = label;
    if (name != null) await stack.setCustomName(name: Text(name).build());
    if (fuel > 0) stack.setCustomComponent(CcComponents.fuel, CcComponents.encodeFuel(fuel));
    final overlayKey = overlay;
    if (overlayKey != null) stack.setCustomComponent(CcComponents.overlay, CcComponents.encodeOverlay(overlayKey));
    final l = left;
    if (l != null) stack.setCustomComponent(CcComponents.leftTurtleUpgrade, CcComponents.encodeUpgrade(l.upgrade.id, l.patch));
    final r = right;
    if (r != null) stack.setCustomComponent(CcComponents.rightTurtleUpgrade, CcComponents.encodeUpgrade(r.upgrade.id, r.patch));
    if (colour >= 0) {
      await stack.setComponent(
        component: DataComponent.dyedColor,
        value: [(colour >> 24) & 0xFF, (colour >> 16) & 0xFF, (colour >> 8) & 0xFF, colour & 0xFF],
      );
    }
    return stack;
  }
}

/// The registry key of the item with the numeric [id]: vanilla items first,
/// then this plugin's (`CcRegistries.items`).
String? itemKeyOfId(int id) {
  final vanilla = VanillaRegistries.require('minecraft:item');
  if (id >= 0 && id < vanilla.length) return vanilla[id];
  final index = id - vanilla.length;
  if (index >= 0 && index < CcRegistries.items.length) return CcRegistries.items[index];
  return null;
}
