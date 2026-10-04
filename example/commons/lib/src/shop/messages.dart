// ignore: implementation_imports
import 'package:pumpkin_api/src/message_format.dart';

import '../core/api.dart';
import 'catalog.dart';
import 'model.dart';
import 'service.dart';

/// Every text of the shop, as defaults for `messages/shop.json`. Owners can
/// translate or restyle them; `{name}` placeholders are filled in.
const shopMessageDefaults = <String, String>{
  // Trades.
  'buy.ok':
      '&aBought &f{amount}x {item} &afor &6{money}&a. Balance: &6{balance}&a.',
  'buy.partial':
      '&e{missing} item(s) did not fit and &6{refund} &ewas refunded.',
  'sell.ok':
      '&aSold &f{amount}x {item} &afor &6{money}&a. Balance: &6{balance}&a.',
  'sell_all.ok':
      '&aSold &f{items} items &afor &6{money}&a. Balance: &6{balance}&a.',
  'sell_all.none': '&cYou carry nothing the shop buys.',
  'sell_all.skipped': '&7{count} kind(s) of item could not be sold.',
  'err.funds': '&cYou need &6{missing} &cmore for that.',
  'err.space_none': '&cYour inventory is full.',
  'err.space': '&cYour inventory only has room for {fit} more of that.',
  'err.no_item': '&cYou have no {item} to sell.',
  'err.few_items': '&cYou only have {have} {item}.',
  'err.not_bought': '&cThe shop does not buy {item}.',
  'err.permission': '&cYou are not allowed to trade {item}.',
  'err.amount': '&cThe amount must be between 1 and {max}.',
  'err.price_changed': '&cThe price of {item} changed, please try again.',
  'err.failed': '&cThat did not work. Your money and items are safe.',
  'err.payment': '&cThe payment was refused.',
  'err.unknown_item': '&c{item} is not in the shop. Browse with /shop.',
  'err.not_confirmed': '&cThere is nothing to confirm (it may have expired).',
  'err.hand_empty': '&cHold the item you mean in your hand.',
  'err.hand_custom': '&cThe shop only deals in plain items, not renamed, enchanted or damaged ones.',
  'err.no_category': '&cThere is no category called {name}.',
  // Confirmation of large purchases.
  'confirm.ask': '&eBuy &f{amount}x {item} &efor &6{money}&e? Type &a/buy confirm &eor click ',
  'confirm.button': '[Confirm]',
  'confirm.hover': 'Buy now',
  // /worth.
  'worth.both': '&e{item}&7: buy &6{buy}&7, sell &6{sell} &7(each)',
  'worth.buy_only':
      '&e{item}&7: buy &6{buy} &7(each), the shop does not buy it',
  // Admin.
  'admin.reloaded':
      '&aShop reloaded: {categories} categories, {entries} items.',
  'admin.problem': '&e- {problem}',
  'admin.reload_failed': '&cNothing was reloaded: {error}',
  'admin.price': '&aThe price of {item} is now {buy} (sell {sell}).',
  'admin.added': '&aAdded {item} to {category} for {buy}.',
  'admin.removed': '&aRemoved {item} from the shop.',
  'admin.log_header': '&6Last {count} trades:',
  'admin.log_line':
      '&7{time} &f{player} &7{kind} &f{amount}x {item} &7for &6{total}',
  'admin.log_empty': '&7No trades yet.',
  'sell.none': 'not bought',
  // Menus.
  'menu.title': '&8Shop',
  'menu.items_title': '&8Shop - {category}',
  'menu.confirm_title': '&8Confirm purchase',
  'menu.balance': '&6Balance: &f{balance}',
  'menu.back': '&eBack to the categories',
  'menu.empty': '&cThe shop has nothing to sell yet',
  'menu.category_lore': '&7{count} items',
  'menu.category_click': '&eClick to browse',
  'menu.confirm': '&aConfirm: pay &6{money}',
  'menu.confirm_item': '&f{amount}x {item}',
  'menu.cancel': '&cCancel',
  // Item lore.
  'lore.buy': '&7Buy: &6{price} &7each',
  'lore.sell': '&7Sell: &6{price} &7each',
  'lore.no_sell': '&8The shop does not buy this',
  'lore.locked': '&cYou are not allowed to trade this',
  'lore.left': '&eLeft click&7: buy {amount} for &6{money}',
  'lore.shift_left': '&eShift + left&7: buy {amount} for &6{money}',
  'lore.right': '&eRight click&7: sell {amount} for &6{money}',
  'lore.shift_right': '&eShift + right&7: sell everything you carry',
};

/// Builds the player-facing text of the shop from a [MessageCatalog] (the
/// module's `messages/shop.json`). Binding-free, so it is unit tested.
final class ShopTexts {
  final MessageCatalog _messages;
  final Economy _economy;
  final String Function() _prefix;

  /// [prefix] is read on every use, so `/shopadmin reload` can change it.
  ShopTexts(this._messages, this._economy, this._prefix);

  /// The message [key] filled with [values], without the prefix.
  String plain(String key, [Map<String, Object?> values = const {}]) =>
      _messages[key].format(values);

  /// The message [key] filled with [values], with the prefix.
  String line(String key, [Map<String, Object?> values = const {}]) =>
      '${_prefix()}${plain(key, values)}';

  String money(int amount) => _economy.format(amount);

  /// What happened in [result], for the player. With [withPrefix] false the
  /// line fits an action bar.
  String trade(TradeResult result, {bool withPrefix = true}) {
    String say(String key, [Map<String, Object?> values = const {}]) =>
        withPrefix ? line(key, values) : plain(key, values);

    final entry = result.entry!;
    final item = prettyItemName(entry.item);
    final failure = result.failure;
    if (failure == null) {
      final key = result.kind == TradeKind.buy ? 'buy.ok' : 'sell.ok';
      final text = say(key, {
        'amount': result.items,
        'item': item,
        'money': money(result.money),
        'balance': money(result.balance),
      });
      if (result.refunded == 0) return text;
      final missing = result.refunded ~/ entry.buy;
      return '$text ${plain('buy.partial', {'missing': missing, 'refund': money(result.refunded)})}';
    }
    return switch (failure) {
      TradeFailure.insufficientFunds => say('err.funds', {
        'missing': money(result.detail),
      }),
      TradeFailure.noSpace when result.detail == 0 => say('err.space_none'),
      TradeFailure.noSpace => say('err.space', {'fit': result.detail}),
      TradeFailure.nothingToSell when result.detail == 0 => say('err.no_item', {
        'item': item,
      }),
      TradeFailure.nothingToSell => say('err.few_items', {
        'have': result.detail,
        'item': item,
      }),
      TradeFailure.notForSale => say('err.not_bought', {'item': item}),
      TradeFailure.noPermission => say('err.permission', {'item': item}),
      TradeFailure.invalidAmount => say('err.amount', {'max': maxTradeAmount}),
      TradeFailure.priceChanged => say('err.price_changed', {'item': item}),
      TradeFailure.paymentRefused => say('err.payment'),
      TradeFailure.deliveryFailed => say('err.failed'),
    };
  }

  /// The summary of a "sell all".
  List<String> bulkSale(BulkSale sale, int balance) {
    if (sale.sales.isEmpty) return [line('sell_all.none')];
    return [
      line('sell_all.ok', {
        'items': sale.items,
        'money': money(sale.money),
        'balance': money(balance),
      }),
      if (sale.skipped > 0) line('sell_all.skipped', {'count': sale.skipped}),
    ];
  }
}
