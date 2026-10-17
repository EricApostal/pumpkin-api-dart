// The block entity data of a turtle: the save data and the client data.
//
// Save data (`TurtleBlockEntity.saveAdditional` + `AbstractComputerBlockEntity`
// + `TurtleBrain.writeToNBT`), with CC's key names where the format is the same:
//
//     ComputerId  int          (absent until the turtle has a computer)
//     Label       string
//     On          byte
//     Fuel        int
//     Color       int          (absent when not dyed)
//     Overlay     string       (an identifier)
//     LeftUpgrade, RightUpgrade   {id: "minecraft:diamond_pickaxe"}
//     LeftUpgradeData, RightUpgradeData   byte array: the component patch of the
//                              upgrade, only when it has data (this plugin's key;
//                              CC writes `components` as NBT)
//     Slot        int          the selected slot
//     OwnerUuid, OwnerName     string (this plugin's keys; CC: `Owner`, a profile)
//     Items       list of {Slot, id, count, vc?, cc?}   (this plugin's format;
//                              CC writes `ItemStack.CODEC` entries)
//
// Client data (`TurtleBlockEntity.getUpdateTag` + `TurtleBrain.writeDescription`),
// what the client's `loadClient` / `readDescription` read:
//
//     Label (string, if any), Fuel (int), Color (int, only if dyed),
//     Overlay (string), LeftUpgrade / RightUpgrade ({id}), Animation (int,
//     the ordinal of `TurtleAnimation`)
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../turtle/brain.dart';
import '../turtle/stack.dart';
import '../turtle/upgrades.dart';

abstract final class TurtleNbt {
  /// The save data of [brain].
  static NbtCompound save(TurtleBrain brain, {String? label, bool on = false}) {
    final tag = NbtCompound();
    final id = brain.computerId;
    if (id != null) tag.putInt('ComputerId', id);
    if (label != null) tag.putString('Label', label);
    tag.putBool('On', on);
    tag.putInt('Fuel', brain.fuelLevel);
    if (brain.colour >= 0) tag.putInt('Color', brain.colour);
    final overlay = brain.overlay;
    if (overlay != null) tag.putString('Overlay', overlay);
    _putUpgrade(tag, 'LeftUpgrade', brain.upgradeOn(TurtleSide.left), withData: true);
    _putUpgrade(tag, 'RightUpgrade', brain.upgradeOn(TurtleSide.right), withData: true);
    tag.putInt('Slot', brain.selectedSlot);
    final owner = brain.ownerUuid;
    if (owner != null) tag.putString('OwnerUuid', owner);
    final ownerName = brain.ownerName;
    if (ownerName != null) tag.putString('OwnerName', ownerName);
    final items = <Object>[];
    for (var slot = 0; slot < TurtleBrain.inventorySize; slot++) {
      final stack = brain.inventory[slot];
      if (stack != null) items.add(_saveStack(slot, stack));
    }
    if (items.isNotEmpty) tag.putList('Items', items);
    return tag;
  }

  static void _putUpgrade(NbtCompound tag, String key, UpgradeInstance? instance, {required bool withData}) {
    if (instance == null) return;
    tag.putCompound(key, NbtCompound()..putString('id', instance.upgrade.key));
    if (withData && instance.hasData) tag.putByteArray('${key}Data', instance.patch);
  }

  static NbtCompound _saveStack(int slot, TurtleStack stack) {
    final tag = NbtCompound()
      ..putByte('Slot', slot)
      ..putString('id', stack.item)
      ..putInt('count', stack.count);
    if (stack.components.isNotEmpty) {
      tag.putList('vc', [
        for (final c in stack.components)
          NbtCompound()
            ..putInt('t', c.type)
            ..putByteArray('v', c.value),
      ]);
    }
    if (stack.custom.isNotEmpty) {
      final custom = NbtCompound();
      for (final entry in stack.custom.entries) {
        custom.putByteArray(entry.key, entry.value);
      }
      tag.putCompound('cc', custom);
    }
    return tag;
  }

  /// Reads [tag] into [brain] (inventory, fuel, colour, overlay, upgrades,
  /// selected slot, owner). The brain's position and facing, the computer id,
  /// label and power state are the caller's.
  static void load(TurtleBrain brain, NbtCompound tag) {
    brain.fuelLevel = tag.getInt('Fuel') ?? 0;
    brain.colour = tag.getInt('Color') ?? -1;
    brain.overlay = tag.getString('Overlay');
    brain.setUpgradeDirect(TurtleSide.left, _readUpgrade(tag, 'LeftUpgrade', brain.upgradeTable));
    brain.setUpgradeDirect(TurtleSide.right, _readUpgrade(tag, 'RightUpgrade', brain.upgradeTable));
    final slot = tag.getInt('Slot') ?? 0;
    brain.selectedSlot = slot >= 0 && slot < TurtleBrain.inventorySize ? slot : 0;
    brain.ownerUuid = tag.getString('OwnerUuid');
    brain.ownerName = tag.getString('OwnerName');
    for (var i = 0; i < TurtleBrain.inventorySize; i++) {
      brain.inventory[i] = null;
    }
    final items = tag.getList('Items');
    if (items != null) {
      for (final item in items) {
        if (item is! NbtCompound) continue;
        final stack = _readStack(item);
        final index = item.getInt('Slot');
        if (stack != null && index != null && index >= 0 && index < TurtleBrain.inventorySize) {
          brain.inventory[index] = stack;
        }
      }
    }
    brain.resetSnapshot();
  }

  static UpgradeInstance? _readUpgrade(NbtCompound tag, String key, TurtleUpgrades upgrades) {
    // CC's codec accepts a bare id string as well as `{id, components}`.
    final compound = tag.getCompound(key);
    final id = compound != null ? compound.getString('id') : tag.getString(key);
    if (id == null) return null;
    final upgrade = upgrades.byKey(id);
    if (upgrade == null) return null;
    final data = tag.getByteArray('${key}Data');
    return UpgradeInstance(upgrade, data == null || data.isEmpty ? null : Uint8List.fromList(data));
  }

  static TurtleStack? _readStack(NbtCompound tag) {
    final id = tag.getString('id');
    final count = tag.getInt('count');
    if (id == null || count == null || count <= 0) return null;
    final components = <StackComponent>[];
    final vc = tag.getList('vc');
    if (vc != null) {
      for (final entry in vc) {
        if (entry is! NbtCompound) continue;
        final type = entry.getInt('t');
        final value = entry.getByteArray('v');
        if (type != null && value != null) components.add(StackComponent(type, Uint8List.fromList(value)));
      }
    }
    final custom = <String, Uint8List>{};
    final cc = tag.getCompound('cc');
    if (cc != null) {
      for (final key in cc.keys) {
        final value = cc.getByteArray(key);
        if (value != null) custom[key] = Uint8List.fromList(value);
      }
    }
    return TurtleStack(id, count, components: components, custom: custom);
  }

  /// The client data: what the client's turtle needs to draw itself.
  static NbtCompound client(TurtleBrain brain, {String? label}) {
    final tag = NbtCompound();
    if (label != null) tag.putString('Label', label);
    tag.putInt('Fuel', brain.fuelLevel);
    if (brain.colour >= 0) tag.putInt('Color', brain.colour);
    final overlay = brain.overlay;
    if (overlay != null) tag.putString('Overlay', overlay);
    _putUpgrade(tag, 'LeftUpgrade', brain.upgradeOn(TurtleSide.left), withData: false);
    _putUpgrade(tag, 'RightUpgrade', brain.upgradeOn(TurtleSide.right), withData: false);
    tag.putInt('Animation', brain.animation.index);
    return tag;
  }
}
