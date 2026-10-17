// Turtle upgrades as the model sees them: the entries of the
// `computercraft:turtle_upgrade` datapack registry (`UpgradeType`s:
// `computercraft:tool`, `wireless_modem`, `speaker`, `workbench`) with their
// ids, and an upgrade placed on a side of a turtle. Binding-free.
//
// Source: `TurtleTool`, `TurtleModem`, `TurtleSpeaker`, `TurtleCraftingTable`
// (shared/turtle/upgrades), `TurtleToolSpec` (impl/upgrades), `UpgradeManager`.
import 'dart:typed_data';

import '../protocol/datapack_registries.dart';
import 'stack.dart';

/// Which side of a turtle an upgrade is on.
enum TurtleSide {
  left,
  right;

  /// The Lua name (`"left"`, `"right"`).
  String get luaName => name;
}

enum UpgradeKind { tool, modem, speaker, workbench, unknown }

/// `TurtleToolDurability`.
enum ToolDurability { never, whenEnchanted, always }

/// One turtle upgrade.
final class TurtleUpgrade {
  /// `minecraft:diamond_pickaxe`, `computercraft:wireless_modem_normal`, ...
  final String key;

  /// Its id: the position in the registry the client was sent.
  final int id;
  final UpgradeKind kind;

  /// The crafting item (`getCraftingItem`).
  final String item;

  // Tools (`TurtleToolSpec`).
  final double damageMultiplier;
  final bool allowEnchantments;
  final ToolDurability consumeDurability;

  /// The block tag a tool may break (`breakable`), `null` for any block.
  final String? breakable;

  // Modems.
  final bool advancedModem;

  const TurtleUpgrade({
    required this.key,
    required this.id,
    required this.kind,
    required this.item,
    this.damageMultiplier = 3.0,
    this.allowEnchantments = false,
    this.consumeDurability = ToolDurability.never,
    this.breakable,
    this.advancedModem = false,
  });

  factory TurtleUpgrade.fromEntry(DatapackEntry entry, int id) {
    final json = entry.json;
    final item = json['item'] is String ? json['item']! as String : 'minecraft:air';
    final kind = switch (entry.type) {
      'computercraft:tool' => UpgradeKind.tool,
      'computercraft:wireless_modem' => UpgradeKind.modem,
      'computercraft:speaker' => UpgradeKind.speaker,
      'computercraft:workbench' => UpgradeKind.workbench,
      _ => UpgradeKind.unknown,
    };
    final durability = switch (json['consumeDurability']) {
      'always' => ToolDurability.always,
      'when_enchanted' => ToolDurability.whenEnchanted,
      _ => ToolDurability.never,
    };
    return TurtleUpgrade(
      key: entry.key,
      id: id,
      kind: kind,
      item: item,
      damageMultiplier: json['damageMultiplier'] is num ? (json['damageMultiplier']! as num).toDouble() : 3.0,
      allowEnchantments: json['allowEnchantments'] == true,
      consumeDurability: durability,
      breakable: json['breakable'] is String ? json['breakable']! as String : null,
      advancedModem: json['advanced'] == true,
    );
  }

  bool get isTool => kind == UpgradeKind.tool;

  /// `getUpgradeType().isPeripheral()`: modems, speakers and the workbench.
  bool get isPeripheral => kind == UpgradeKind.modem || kind == UpgradeKind.speaker || kind == UpgradeKind.workbench;

  /// `isItemSuitable`: a tool does not take a damaged item unless it uses
  /// durability, nor an enchanted one unless it allows enchantments.
  bool isItemSuitable(TurtleStack stack) {
    if (!isTool) return true;
    if (consumeDurability == ToolDurability.never && stack.damaged) return false;
    if (!allowEnchantments && stack.enchanted) return false;
    return true;
  }

  @override
  String toString() => 'TurtleUpgrade($key)';
}

/// An upgrade on a turtle with its data (the `DataComponentPatch` of
/// `UpgradeData`, kept as its network bytes).
final class UpgradeInstance {
  final TurtleUpgrade upgrade;

  /// The component patch in network form (`VarInt added, VarInt removed,
  /// ...`); [emptyPatch] for plain upgrades.
  final Uint8List patch;

  UpgradeInstance(this.upgrade, [Uint8List? patch]) : patch = patch ?? emptyPatch;

  /// A patch with nothing in it.
  static final Uint8List emptyPatch = Uint8List.fromList([0, 0]);

  bool get hasData => !(patch.length == 2 && patch[0] == 0 && patch[1] == 0);
}

/// The turtle upgrades of the registry.
final class TurtleUpgrades {
  final List<TurtleUpgrade> all;

  TurtleUpgrades(this.all);

  /// Builds the upgrades of [registry] (a `turtle_upgrade` registry).
  factory TurtleUpgrades.of(DatapackRegistry registry) => TurtleUpgrades([
    for (var i = 0; i < registry.entries.length; i++) TurtleUpgrade.fromEntry(registry.entries[i], i),
  ]);

  TurtleUpgrade? byKey(String key) {
    for (final upgrade in all) {
      if (upgrade.key == key) return upgrade;
    }
    return null;
  }

  TurtleUpgrade? byId(int id) => id >= 0 && id < all.length ? all[id] : null;

  /// `UpgradeManager.get`: the upgrade whose crafting item is [stack]'s item
  /// and that accepts the stack, or null.
  TurtleUpgrade? forItem(TurtleStack stack) {
    for (final upgrade in all) {
      if (upgrade.item == stack.item && upgrade.isItemSuitable(stack)) return upgrade;
    }
    return null;
  }
}
