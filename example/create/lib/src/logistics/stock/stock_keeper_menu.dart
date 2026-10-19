// The stock keeper screen (`StockKeeperCategoryMenu`): the stock ticker opens it from
// `StockTickerBlock.useItemOn` when a keeper is present. It has one slot for the category filter
// item being edited, followed by the player inventory (`StockKeeperCategoryMenu.addSlots`), so
// the host's slot order matches and the vanilla click logic applies. The client's screen sends
// the edited filter with `GhostItemSubmitPacket`, which only has to be mirrored into the server's
// slot (the screen reads its own copy).
import 'package:pumpkin_api/pumpkin_api.dart';
// The `menus` interface (options, rules) is not part of the public wrappers yet.
// ignore: implementation_imports
import 'package:pumpkin_api/src/bindings.g.dart' as raw show menus;

import '../../core/pos.dart';
import '../filter/filter_item_stack.dart';
import '../host/runtime.dart';
import '../model/stack.dart';
import 'stock_ticker_block_entity.dart';

/// The menu types of the stock keeper (`AllMenuTypes`).
const String stockKeeperCategoryMenuType = 'create:stock_keeper_category';
const String stockKeeperRequestMenuType = 'create:stock_keeper_request';

abstract final class StockKeeperMenus {
  /// `StockKeeperCategoryMenu.addSlots`: one proxy slot, then the 36 player slots.
  static const int categorySlots = 1;

  /// `InactiveItemHandlerSlot.mayPlace`: only a filter item can be edited as a category.
  static const List<String> categoryFilterKeys = [
    FilterItemKeys.list,
    FilterItemKeys.attribute,
    FilterItemKeys.package,
  ];

  static final MenuClickRules _categoryRules = MenuClickRules(
    slotRules: [
      MenuSlotRule(
        slot: 0,
        kind: const MenuSlotKindFilter(categoryFilterKeys),
        maxStackSize: null,
      ),
    ],
    quickMoveTargets: const [MenuSlotRange(start: 0, end: categorySlots)],
  );

  /// `player.openMenu(stbe.new CategoryMenuProvider(), stbe.getBlockPos())`: the extra data is
  /// the block position (`createOnClient` reads it).
  static Future<bool> openCategory(
    Player player,
    StockTickerBlockEntity be,
  ) async {
    final extra = PacketBuffer.encode(
      (w) => w.writeLong(packPos(be.pos.x, be.pos.y, be.pos.z)),
    );
    final result = raw.menus.openMenuWithOptions(
      player: player,
      menuTypeKey: stockKeeperCategoryMenuType,
      // `CategoryMenuProvider.getDisplayName()` is an empty component.
      title: TextComponent.text(plain: ''),
      extraData: extra,
      slotCount: categorySlots,
      options: MenuOptions(
        applyVanillaClicks: true,
        playerInventory: true,
        rules: _categoryRules,
      ),
    );
    if (result is ErrorResult) {
      Lg.i.log.warn(
        'Could not open the stock keeper: ${(result as ErrorResult).value}',
      );
      return false;
    }
    return true;
  }

  /// `player.openMenu(stbe.new RequestMenuProvider(), buf -> ...)`: the stock keeper's request
  /// screen, opened by right-clicking a keeper (a seated entity) next to the ticker. It has no
  /// server tracked slots; the screen talks through `create:logistics_stock_request` and
  /// `create:logistics_package_request`.
  static Future<bool> openRequest(
    Player player,
    StockTickerBlockEntity be, {
    required bool showLockOption,
    required bool currentlyLocked,
  }) async {
    final extra = PacketBuffer.encode((w) {
      w.writeBool(showLockOption);
      w.writeBool(currentlyLocked);
      w.writeLong(packPos(be.pos.x, be.pos.y, be.pos.z));
    });
    try {
      player.openPluginMenu(
        stockKeeperRequestMenuType,
        // `RequestMenuProvider.getDisplayName()` is an empty component.
        TextComponent.text(plain: ''),
        extraData: extra,
      );
    } on Object catch (e) {
      Lg.i.log.warn('Could not open the stock keeper request screen: $e');
      return false;
    }
    return true;
  }

  /// `GhostItemSubmitPacket.handle` for the category screen: the proxy slot holds the filter item
  /// being edited (`ItemStack.EMPTY` while the list is shown). Only a filter item is accepted.
  static Future<void> submitGhost(
    Player player,
    int slot,
    LStack stack,
  ) async {
    if (slot != 0) return;
    if (stack.isNotEmpty && !categoryFilterKeys.contains(stack.key)) return;
    final host = await Lg.i.write(stack);
    try {
      if (host == null) {
        player.clearPluginMenuSlot(0);
      } else {
        player.setPluginMenuSlot(0, host);
      }
    } on Object {
      // the menu closed meanwhile
    }
  }
}
