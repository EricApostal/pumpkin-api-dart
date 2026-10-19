// The `create:toolbox_inventory` component value of a toolbox item <-> the inventory model.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../protocol/item_stack.dart';
import '../data/equipment_components.dart';
import 'toolbox_model.dart';

/// Components worth carrying inside the item form of a toolbox (what players modify). The
/// host reports all components of a stack, defaults included.
const _carried = {
  'damage',
  'enchantments',
  'stored-enchantments',
  'custom-name',
  'lore',
  'repair-cost',
  'custom-data',
  'unbreakable',
  'dyed-color',
  'trim',
  'potion-contents',
  'enchantment-glint-override',
  'custom-model-data',
  'item-name',
};

abstract final class ToolboxInventoryDataBridge {
  static String _vanillaKey(String wireName) => 'minecraft:${wireName.replaceAll('-', '_')}';

  static String _wireName(String key) {
    final bare = key.startsWith('minecraft:') ? key.substring(10) : key;
    return bare.replaceAll('_', '-');
  }

  static ItemStackData? _toStackData(TStack t, ItemIdResolver ids) {
    if (t.isEmpty) return ItemStackData.empty;
    final id = ids.idOf(t.key);
    if (id == null) return null;
    final added = <(int, Uint8List)>[];
    for (final (name, bytes) in t.comps) {
      if (!_carried.contains(name)) continue;
      final typeId = VanillaIds.dataComponentTypes.idOf(_vanillaKey(name));
      if (typeId != null) added.add((typeId, Uint8List.fromList(bytes)));
    }
    return ItemStackData(id, t.count, ItemComponentPatch(added: added));
  }

  /// The wire bytes of [inv] as the component value, or `null` when an item has no id.
  static Uint8List? toData(ToolboxInv inv, ItemIdResolver ids) {
    final data = ToolboxInventoryData();
    for (var i = 0; i < ToolboxInv.slotCount; i++) {
      final d = _toStackData(inv.slots[i], ids);
      if (d == null) return null;
      data.slots[i] = d;
    }
    for (var i = 0; i < ToolboxInv.compartments; i++) {
      final d = _toStackData(inv.filters[i], ids);
      if (d == null) return null;
      data.filters[i] = d;
    }
    return EquipmentWire.toolboxInventory(data);
  }

  /// Reads the component value into [inv]. [maxStackOf] gives the stack size of an item key
  /// (the wire form does not carry it).
  static Future<void> fromData(
    List<int> bytes,
    ToolboxInv inv,
    ItemIdResolver ids,
    Future<({int max, bool damageable})> Function(String key) infoOf,
  ) async {
    final data = EquipmentWire.readToolboxInventory(bytes);
    Future<TStack> conv(ItemStackData d) async {
      if (d.isEmpty) return TStack.empty;
      final key = ids.keyOf(d.itemId);
      if (key == null) return TStack.empty;
      final info = await infoOf(key);
      final comps = <(String, List<int>)>[];
      for (final (typeId, value) in d.patch.added) {
        final k = VanillaIds.dataComponentTypes.keyOf(typeId);
        if (k != null) comps.add((_wireName(k), value));
      }
      comps.sort((a, b) => a.$1.compareTo(b.$1));
      return TStack(key, d.count, maxStack: info.max, damageable: info.damageable, comps: comps);
    }

    for (var i = 0; i < ToolboxInv.slotCount && i < data.slots.length; i++) {
      inv.slots[i] = await conv(data.slots[i]);
    }
    for (var i = 0; i < ToolboxInv.compartments && i < data.filters.length; i++) {
      inv.filters[i] = await conv(data.filters[i]);
    }
  }
}
