import 'package:pumpkin_api/pumpkin_api.dart';

import 'bag.dart';
import 'catalog.dart';
import 'messages.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';

const _filler = ItemSpec('gray_stained_glass_pane', name: ' ');

/// The chest menus of the shop: the categories, a paged list of the items of
/// one category, and the confirmation of a large purchase.
///
/// Click mapping in the item menu (also shown in each item's lore):
///
/// | Click | Action |
/// | --- | --- |
/// | left | buy `amount` items (1 by default) |
/// | shift + left | buy one `stack` |
/// | right | sell `amount` items |
/// | shift + right | sell everything the player carries of it |
///
/// Everything a click does is synchronous, so a second click can never run
/// in the middle of a first one. The confirmation menu additionally ignores
/// clicks after the first one, because it is replaced on the next tick.
final class ShopUi {
  final ShopService shop;
  final ShopTexts texts;
  final Logger log;

  ShopUi(this.shop, this.texts, this.log);

  /// Opens the category menu for [player].
  void open(Player player) => _categories(player).open(player);

  /// Opens the items of [categoryId] for [player]. Returns `false` if there
  /// is no such category.
  bool openCategory(Player player, String categoryId) {
    final category = shop.catalog.category(categoryId);
    if (category == null) return false;
    _items(player, category).open(player);
    return true;
  }

  // -- Menus ------------------------------------------------------------------

  /// What a menu needs to know about a player, as plain data. Player handles
  /// are only valid inside the callback that received them, but a menu is
  /// drawn again later (page changes, refreshes).
  _Viewer _viewer(Player player) =>
      _Viewer(player.asEntity().getUuid().asString, {
        for (final node in shop.catalog.permissions)
          if (player.hasPermission(node: node)) node,
      });

  ItemSpec _balance(String uuid) => ItemSpec(
    'gold_ingot',
    name: texts.plain('menu.balance', {
      'balance': texts.money(shop.economy.balance(uuid)),
    }),
  );

  Menu _categories(Player player) {
    final viewer = _viewer(player);
    final categories = shop.catalog.categories;
    final rows = ((categories.length + 6) ~/ 7 + 2).clamp(3, 6);
    final menu = Menu(title: texts.plain('menu.title'), rows: rows)
      ..border(_filler);
    if (categories.isEmpty) {
      menu.button(
        row: 1,
        column: 4,
        item: ItemSpec('barrier', name: texts.plain('menu.empty')),
      );
    }
    final slots = MenuLayout.innerSlots(rows);
    for (var i = 0; i < categories.length; i++) {
      final category = categories[i];
      menu.button(
        slot: slots[i],
        item: ItemSpec(
          category.icon,
          name: category.name,
          lore: [
            texts.plain('menu.category_lore', {
              'count': category.entries.length,
            }),
            '',
            texts.plain('menu.category_click'),
          ],
        ),
        onClick: (click) => _guard(click.player, () {
          click.open(_items(click.player, category));
        }),
      );
    }
    menu.button(row: rows - 1, column: 4, item: _balance(viewer.uuid));
    return menu;
  }

  Menu _items(Player player, ShopCategory category) {
    final viewer = _viewer(player);
    late final PagedMenu<ShopEntry> menu;
    menu = PagedMenu<ShopEntry>(
      title: texts.plain('menu.items_title', {
        'category': MessageFormat.stripColors(category.name),
      }),
      items: () => shop.catalog.category(category.id)?.entries ?? const [],
      render: (entry) => _entryItem(viewer, entry),
      onSelect: (click, entry) =>
          _guard(click.player, () => _entryClick(click, menu, category, entry)),
    );
    menu.button(
      row: 5,
      column: 0,
      item: ItemSpec('arrow', name: texts.plain('menu.back')),
      onClick: (click) => _guard(click.player, () {
        click.open(_categories(click.player));
      }),
    );
    menu.button(row: 5, column: 8, item: _balance(viewer.uuid));
    return menu;
  }

  ItemSpec _entryItem(_Viewer viewer, ShopEntry entry) {
    final allowed =
        entry.permission == null || viewer.granted.contains(entry.permission);
    final sellPrice = shop.sellPriceOf(entry);
    String money(int n) => texts.money(n);
    return ItemSpec(
      entry.item,
      lore: [
        texts.plain('lore.buy', {'price': money(entry.buy)}),
        sellPrice == null
            ? texts.plain('lore.no_sell')
            : texts.plain('lore.sell', {'price': money(sellPrice)}),
        '',
        if (!allowed)
          texts.plain('lore.locked')
        else ...[
          texts.plain('lore.left', {
            'amount': entry.amount,
            'money': money(shop.buyCost(entry, entry.amount)),
          }),
          if (entry.stack != entry.amount)
            texts.plain('lore.shift_left', {
              'amount': entry.stack,
              'money': money(shop.buyCost(entry, entry.stack)),
            }),
          if (sellPrice != null) ...[
            texts.plain('lore.right', {
              'amount': entry.amount,
              'money': money(sellPrice * entry.amount),
            }),
            texts.plain('lore.shift_right'),
          ],
        ],
      ],
    );
  }

  Menu _confirm(
    Player player,
    ShopCategory back,
    ShopEntry entry,
    int amount,
    int cost,
  ) {
    final menu = Menu(title: texts.plain('menu.confirm_title'), rows: 3)
      ..fill(_filler);
    var answered = false;
    menu.button(
      row: 1,
      column: 4,
      item: ItemSpec(
        entry.item,
        count: amount.clamp(1, 64),
        name: texts.plain('menu.confirm_item', {
          'amount': amount,
          'item': prettyItemName(entry.item),
        }),
      ),
    );
    menu.button(
      row: 1,
      column: 2,
      item: ItemSpec(
        'lime_stained_glass_pane',
        name: texts.plain('menu.confirm', {'money': texts.money(cost)}),
      ),
      onClick: (click) => _guard(click.player, () {
        if (answered) return;
        answered = true;
        final result = shop.buy(
          PlayerShopper(click.player),
          entry,
          amount,
          expectedCost: cost,
        );
        _report(click.player, result);
        click.open(_items(click.player, back));
      }),
    );
    menu.button(
      row: 1,
      column: 6,
      item: ItemSpec(
        'red_stained_glass_pane',
        name: texts.plain('menu.cancel'),
      ),
      onClick: (click) => _guard(click.player, () {
        if (answered) return;
        answered = true;
        click.open(_items(click.player, back));
      }),
    );
    return menu;
  }

  // -- Clicks -----------------------------------------------------------------

  void _entryClick(
    MenuClick click,
    PagedMenu<ShopEntry> menu,
    ShopCategory category,
    ShopEntry entry,
  ) {
    final player = click.player;
    if (click.isLeft) {
      if (!player.hasPermission(node: ShopPerms.buy.node)) {
        return _report(
          player,
          TradeResult.failed(
            TradeKind.buy,
            TradeFailure.noPermission,
            entry: entry,
          ),
        );
      }
      final amount = click.isShift ? entry.stack : entry.amount;
      final cost = shop.buyCost(entry, amount);
      if (shop.needsConfirmation(cost)) {
        click.open(_confirm(player, category, entry, amount, cost));
        return;
      }
      _report(player, shop.buy(PlayerShopper(player), entry, amount));
    } else if (click.isRight) {
      if (!player.hasPermission(node: ShopPerms.sell.node)) {
        return _report(
          player,
          TradeResult.failed(
            TradeKind.sell,
            TradeFailure.noPermission,
            entry: entry,
          ),
        );
      }
      final shopper = PlayerShopper(player);
      final amount = click.isShift
          ? shopper.bag.countOf(entry.item).clamp(1, maxTradeAmount)
          : entry.amount;
      _report(player, shop.sell(shopper, entry, amount));
    } else {
      return;
    }
    menu.button(
      row: 5,
      column: 8,
      item: _balance(player.asEntity().getUuid().asString),
    );
  }

  /// Shows what a trade did above the hotbar, with a sound.
  void _report(Player player, TradeResult result) {
    player.actionBar(texts.trade(result, withPrefix: false));
    _sound(
      player,
      result.isOk
          ? 'minecraft:entity.experience_orb.pickup'
          : 'minecraft:entity.villager.no',
    );
  }

  void _sound(Player player, String name) {
    try {
      player.customSound(name, volume: 0.6);
    } catch (e) {
      log.debug('Could not play $name: $e');
    }
  }

  /// Runs a click handler so that a failure is logged and shown to the
  /// player instead of reaching the server.
  void _guard(Player player, void Function() body) {
    try {
      body();
    } catch (e, s) {
      log.error('Shop menu action failed', error: e, stackTrace: s);
      try {
        player.actionBar(texts.plain('err.failed'));
      } catch (_) {
        // The player is gone, nothing to tell.
      }
    }
  }
}

final class _Viewer {
  final String uuid;
  final Set<String> granted;

  const _Viewer(this.uuid, this.granted);
}
