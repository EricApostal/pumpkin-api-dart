// `PackagePortMenu`: the eighteen package slots of a frogport or postbox and the player's
// inventory. The menu is a host menu of type `create:package_port`; its slots mirror the port's
// buffer (only packages go in, one per slot).
import 'package:pumpkin_api/pumpkin_api.dart';
// The `menus` interface (options, rules) is not part of the public wrappers yet.
// ignore: implementation_imports
import 'package:pumpkin_api/src/bindings.g.dart' as raw show menus;

import '../../core/pos.dart' show packPos;
import '../host/runtime.dart';
import '../model/package.dart';
import '../model/stack.dart';
import 'package_port_block_entity.dart';

abstract final class PackagePortMenus {
  static const String menuType = 'create:package_port';

  /// `PackagePortMenu.addSlots`: two rows of nine.
  static const int slots = 18;

  static MenuClickRules get rules => MenuClickRules(
    slotRules: [
      for (var i = 0; i < slots; i++)
        MenuSlotRule(
          slot: i,
          kind: MenuSlotKindFilter(PackageStyles.allKeys),
          maxStackSize: 1,
        ),
    ],
    quickMoveTargets: const [MenuSlotRange(start: 0, end: slots)],
  );

  /// `player.openMenu(this, worldPosition)`: the extra data is the block position
  /// (`createOnClient` reads it).
  static Future<bool> open(Player player, PackagePortBlockEntity be) async {
    final extra = PacketBuffer.encode(
      (w) => w.writeLong(packPos(be.pos.x, be.pos.y, be.pos.z)),
    );
    final result = raw.menus.openMenuWithOptions(
      player: player,
      menuTypeKey: menuType,
      // `PackagePortBlockEntity.getDisplayName()` is an empty component.
      title: TextComponent.text(plain: ''),
      extraData: extra,
      slotCount: slots,
      options: MenuOptions(
        applyVanillaClicks: true,
        playerInventory: true,
        rules: rules,
      ),
    );
    if (result is ErrorResult) {
      Lg.i.log.warn('Could not open the package port: ${(result as ErrorResult).value}');
      return false;
    }
    be.openViewers.add(player.getId().asString);
    await fill(player, be);
    return true;
  }

  /// The buffer into the menu slots.
  static Future<void> fill(Player player, PackagePortBlockEntity be) async {
    for (var i = 0; i < slots; i++) {
      final host = await Lg.i.write(be.packages.at(i));
      try {
        if (host == null) {
          player.clearPluginMenuSlot(i);
        } else {
          player.setPluginMenuSlot(i, host);
        }
      } on Object {
        // the menu closed meanwhile
      }
    }
  }

  /// `menuSlotChanged` of an open port menu: the slots are the port's buffer.
  static Future<void> applySlotChange(
    Player player,
    PackagePortBlockEntity be,
    MenuSlotChange change,
  ) async {
    if (change.slot < 0 || change.slot >= slots) return;
    final stack = await Lg.i.read(change.stack);
    final box = PackageItem.isPackage(stack) ? stack.withCount(1) : LStack.empty;
    if (be.packages.at(change.slot) == box) return;
    be.packages.set(change.slot, box);
    be.markDirty();
  }
}
