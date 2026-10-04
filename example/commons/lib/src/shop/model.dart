import 'package:dart_mappable/dart_mappable.dart';

part 'model.mapper.dart';

/// One item the shop trades. Prices are per single item, in whole currency
/// units.
@MappableClass(ignoreNull: true)
class ShopEntry with ShopEntryMappable {
  /// Registry key, `diamond` or `minecraft:diamond`.
  final String item;

  /// What the shop charges for one item. Must be at least 1.
  final int buy;

  /// What the shop pays for one item. `null` means "`buy` times the sell
  /// percentage of the config" (rounded down), `0` means the item can't be
  /// sold.
  final int? sell;

  /// Items moved by a plain click in the menu.
  final int amount;

  /// Items moved by a shift-click in the menu (one stack).
  final int stack;

  /// A permission node a player needs to buy or sell this entry, or `null`
  /// for everyone.
  final String? permission;

  const ShopEntry({
    required this.item,
    required this.buy,
    this.sell,
    this.amount = 1,
    this.stack = 64,
    this.permission,
  });
}

/// A group of entries, shown as one button of the shop menu.
@MappableClass(ignoreNull: true)
class ShopCategory with ShopCategoryMappable {
  /// Short lowercase id (`blocks`), used in the file and by admin commands.
  final String id;

  /// Name shown to players. May use `&` colour codes.
  final String name;

  /// Registry key of the item that represents the category.
  final String icon;

  final List<ShopEntry> entries;

  const ShopCategory({
    required this.id,
    required this.name,
    required this.icon,
    this.entries = const [],
  });
}

/// The content of `shop/catalog.json`.
@MappableClass()
class ShopCatalog with ShopCatalogMappable {
  final List<ShopCategory> categories;

  const ShopCatalog({this.categories = const []});
}

/// The content of `shop/config.json`.
@MappableClass()
class ShopConfig with ShopConfigMappable {
  /// What the shop pays for items without an explicit sell price, in percent
  /// of the buy price.
  final int sellPercent;

  /// A purchase of at least this much asks for confirmation first. `0` turns
  /// confirmations off.
  final int confirmThreshold;

  /// Put before every shop message (`&` colour codes).
  final String prefix;

  /// How many transactions `shop/ledger.json` keeps.
  final int ledgerSize;

  const ShopConfig({
    this.sellPercent = 50,
    this.confirmThreshold = 5000,
    this.prefix = '&8[&6Shop&8] &r',
    this.ledgerSize = 500,
  });
}

@MappableEnum()
enum TradeKind { buy, sell }

/// One finished purchase or sale.
@MappableClass()
class LedgerEntry with LedgerEntryMappable {
  final DateTime time;
  final String uuid;
  final String player;
  final TradeKind kind;

  /// Normalised registry key.
  final String item;
  final int amount;

  /// Money that changed hands.
  final int total;

  const LedgerEntry({
    required this.time,
    required this.uuid,
    required this.player,
    required this.kind,
    required this.item,
    required this.amount,
    required this.total,
  });
}

/// The content of `shop/ledger.json`: the latest transactions, oldest first.
@MappableClass()
class Ledger with LedgerMappable {
  final List<LedgerEntry> entries;

  const Ledger({this.entries = const []});
}
