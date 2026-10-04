import 'package:dart_mappable/dart_mappable.dart' show MapperException;

import '../core/api.dart';
import '../core/clock.dart';
import '../core/storage.dart';
import 'catalog.dart';
import 'model.dart';

const catalogPath = 'shop/catalog.json';
const configPath = 'shop/config.json';
const ledgerPath = 'shop/ledger.json';

/// The items of one player, as far as the shop cares. The server side
/// implements it on the player's inventory (`ui.dart`), tests use a fake, so
/// the whole purchase flow can be tested without a server.
///
/// Only *plain* stacks count: items with a custom name, lore, enchantments or
/// durability damage are never sold, and only plain stacks are topped up.
abstract interface class ItemBag {
  /// How many more items of [key] fit.
  int spaceFor(String key);

  /// How many sellable items of [key] there are.
  int countOf(String key);

  /// Puts [count] items of [key] in, returns how many did **not** fit.
  int add(String key, int count);

  /// Takes up to [count] sellable items of [key] out, returns how many were
  /// taken.
  int remove(String key, int count);
}

/// A player doing business with the shop.
abstract interface class Shopper {
  String get uuid;
  String get name;
  bool hasPermission(String node);
  ItemBag get bag;
}

enum TradeFailure {
  /// The amount is below 1 or above [maxTradeAmount].
  invalidAmount,

  /// The entry needs a permission the player does not have.
  noPermission,

  /// The shop does not buy this item (sell price 0).
  notForSale,

  /// The player can not pay.
  insufficientFunds,

  /// The economy refused the payment for another reason.
  paymentRefused,

  /// The items do not fit in the inventory (nothing was charged).
  noSpace,

  /// The player does not have (enough of) the item to sell.
  nothingToSell,

  /// The price changed since the player was asked to confirm.
  priceChanged,

  /// The items could not be handed over; any money was refunded.
  deliveryFailed,
}

/// The outcome of a purchase or a sale.
final class TradeResult {
  final TradeKind kind;
  final TradeFailure? failure;
  final ShopEntry? entry;

  /// Items that changed hands.
  final int items;

  /// Money the player paid (buy) or received (sell), after refunds.
  final int money;

  /// Money handed back because some items did not fit (buy only).
  final int refunded;

  /// The player's balance afterwards.
  final int balance;

  /// For [TradeFailure.insufficientFunds]: how much is missing. For
  /// [TradeFailure.noSpace] and [TradeFailure.nothingToSell]: how many items
  /// would fit or are available.
  final int detail;

  const TradeResult.ok(
    this.kind,
    ShopEntry this.entry, {
    required this.items,
    required this.money,
    required this.balance,
    this.refunded = 0,
  }) : failure = null,
       detail = 0;

  const TradeResult.failed(
    this.kind,
    TradeFailure this.failure, {
    this.entry,
    this.balance = 0,
    this.detail = 0,
  }) : items = 0,
       money = 0,
       refunded = 0;

  bool get isOk => failure == null;
}

/// Everything a "sell all" sold.
final class BulkSale {
  final List<TradeResult> sales;

  /// Entries that matched but could not be sold (no permission, ...), not
  /// counting items the player simply does not have.
  final int skipped;

  const BulkSale(this.sales, this.skipped);

  int get items => sales.fold(0, (sum, s) => sum + s.items);
  int get money => sales.fold(0, (sum, s) => sum + s.money);
}

/// What `/shopadmin reload` found.
final class ReloadReport {
  /// Why nothing was reloaded, or `null` if it worked.
  final String? error;
  final List<String> problems;
  final int categories;
  final int entries;

  const ReloadReport.failed(String this.error)
    : problems = const [],
      categories = 0,
      entries = 0;

  const ReloadReport.ok(this.categories, this.entries, this.problems)
    : error = null;

  bool get ok => error == null;
}

/// An admin edit that could not be done; [message] is shown to the admin.
final class ShopException implements Exception {
  final String message;
  const ShopException(this.message);

  @override
  String toString() => message;
}

/// The shop's logic: prices, the purchase and sale flows, the ledger and the
/// admin edits of the catalog. Plain Dart, no server bindings.
///
/// Money is always charged **before** items are handed out and refunded when
/// the hand-over fails, and items are always removed **before** they are
/// paid, so a player is never charged without getting the items and never
/// paid for items they still have.
final class ShopService {
  final Economy economy;
  final Clock clock;
  final JsonDocument<ShopCatalog> _catalogDoc;
  final JsonDocument<ShopConfig> _configDoc;
  final JsonDocument<Ledger> _ledgerDoc;
  final bool Function(String key) isKnownItem;
  final LogSink _warn;

  Catalog _catalog = Catalog(const []);
  List<String> _problems = const [];

  ShopService({
    required this.economy,
    required this.clock,
    required JsonDocument<ShopCatalog> catalog,
    required JsonDocument<ShopConfig> config,
    required JsonDocument<Ledger> ledger,
    required this.isKnownItem,
    LogSink? warn,
  }) : _catalogDoc = catalog,
       _configDoc = config,
       _ledgerDoc = ledger,
       _warn = warn ?? ((_) {}) {
    _rebuild();
  }

  Catalog get catalog => _catalog;
  ShopConfig get config => _configDoc.value;

  /// What was wrong with the catalog file the last time it was read.
  List<String> get problems => _problems;

  List<LedgerEntry> get ledger => _ledgerDoc.value.entries;

  void _rebuild() {
    final report = validateCatalog(_catalogDoc.value, isKnownItem: isKnownItem);
    _catalog = report.catalog;
    _problems = report.problems;
  }

  // -- Prices -----------------------------------------------------------------

  /// The sell percentage, limited to 0-100 so the shop never pays more than it
  /// charges by accident.
  int get sellPercent => config.sellPercent.clamp(0, 100);

  /// What the shop pays for one [entry], or `null` if it does not buy it.
  int? sellPriceOf(ShopEntry entry) {
    final price = entry.sell ?? entry.buy * sellPercent ~/ 100;
    return price > 0 ? price : null;
  }

  int buyCost(ShopEntry entry, int amount) => entry.buy * amount;

  /// What the shop pays for [amount] of [entry], or `null` if it does not buy
  /// it.
  int? sellValue(ShopEntry entry, int amount) {
    final price = sellPriceOf(entry);
    return price == null ? null : price * amount;
  }

  /// Whether a purchase costing [cost] has to be confirmed first.
  bool needsConfirmation(int cost) =>
      config.confirmThreshold > 0 && cost >= config.confirmThreshold;

  // -- Buying and selling -----------------------------------------------------

  /// Sells [amount] of [entry] to [who]. With [expectedCost] the purchase is
  /// refused if it would cost something else (the price changed while the
  /// player was confirming).
  TradeResult buy(
    Shopper who,
    ShopEntry entry,
    int amount, {
    int? expectedCost,
  }) {
    TradeResult fail(TradeFailure failure, {int detail = 0}) =>
        TradeResult.failed(
          TradeKind.buy,
          failure,
          entry: entry,
          balance: economy.balance(who.uuid),
          detail: detail,
        );

    if (amount < 1 || amount > maxTradeAmount) {
      return fail(TradeFailure.invalidAmount);
    }
    final permission = entry.permission;
    if (permission != null && !who.hasPermission(permission)) {
      return fail(TradeFailure.noPermission);
    }
    final cost = buyCost(entry, amount);
    if (expectedCost != null && expectedCost != cost) {
      return fail(TradeFailure.priceChanged);
    }
    final room = who.bag.spaceFor(entry.item);
    if (room < amount) return fail(TradeFailure.noSpace, detail: room);

    final paid = economy.withdraw(
      who.uuid,
      cost,
      reason: 'shop: ${shortItemKey(entry.item)} x$amount',
    );
    if (!paid.isOk) {
      return paid.failure == TransactionFailure.insufficientFunds
          ? fail(TradeFailure.insufficientFunds, detail: cost - paid.balance)
          : fail(TradeFailure.paymentRefused);
    }

    var notDelivered = amount;
    try {
      notDelivered = who.bag.add(entry.item, amount);
    } catch (e) {
      _warn('Could not give ${entry.item} x$amount to ${who.name}: $e');
    }
    final delivered = amount - notDelivered;
    final refund = notDelivered * entry.buy;
    if (refund > 0) {
      final back = economy.deposit(
        who.uuid,
        refund,
        reason: 'shop refund: ${shortItemKey(entry.item)} x$notDelivered',
      );
      if (!back.isOk) {
        _warn('Could not refund $refund to ${who.name} (${who.uuid})');
      }
    }
    if (delivered == 0) return fail(TradeFailure.deliveryFailed);

    final money = delivered * entry.buy;
    _record(who, TradeKind.buy, entry, delivered, money);
    return TradeResult.ok(
      TradeKind.buy,
      entry,
      items: delivered,
      money: money,
      refunded: refund,
      balance: economy.balance(who.uuid),
    );
  }

  /// Buys [amount] of [entry] from [who].
  TradeResult sell(Shopper who, ShopEntry entry, int amount) {
    TradeResult fail(TradeFailure failure, {int detail = 0}) =>
        TradeResult.failed(
          TradeKind.sell,
          failure,
          entry: entry,
          balance: economy.balance(who.uuid),
          detail: detail,
        );

    if (amount < 1 || amount > maxTradeAmount) {
      return fail(TradeFailure.invalidAmount);
    }
    final permission = entry.permission;
    if (permission != null && !who.hasPermission(permission)) {
      return fail(TradeFailure.noPermission);
    }
    final price = sellPriceOf(entry);
    if (price == null) return fail(TradeFailure.notForSale);
    final have = who.bag.countOf(entry.item);
    if (have < amount) return fail(TradeFailure.nothingToSell, detail: have);

    var removed = 0;
    try {
      removed = who.bag.remove(entry.item, amount);
    } catch (e) {
      _warn('Could not take ${entry.item} x$amount from ${who.name}: $e');
      // Pay for whatever really left the inventory.
      removed = have - who.bag.countOf(entry.item);
    }
    if (removed <= 0) return fail(TradeFailure.deliveryFailed);

    final money = removed * price;
    final paid = economy.deposit(
      who.uuid,
      money,
      reason: 'shop: sold ${shortItemKey(entry.item)} x$removed',
    );
    if (!paid.isOk) {
      _warn('Could not pay $money to ${who.name} (${who.uuid}) for a sale');
    }
    _record(who, TradeKind.sell, entry, removed, money);
    return TradeResult.ok(
      TradeKind.sell,
      entry,
      items: removed,
      money: money,
      balance: economy.balance(who.uuid),
    );
  }

  /// Sells everything [who] carries that the shop buys.
  BulkSale sellAll(Shopper who) {
    final sales = <TradeResult>[];
    var skipped = 0;
    final seen = <String>{};
    for (final category in catalog.categories) {
      for (final entry in category.entries) {
        if (!seen.add(entry.item)) continue;
        final have = who.bag.countOf(entry.item);
        if (have == 0) continue;
        // A single trade is capped, so large piles are sold in several.
        var left = have;
        while (left > 0) {
          final result = sell(who, entry, left.clamp(1, maxTradeAmount));
          if (!result.isOk) {
            skipped++;
            break;
          }
          sales.add(result);
          left -= result.items;
        }
      }
    }
    return BulkSale(sales, skipped);
  }

  void _record(
    Shopper who,
    TradeKind kind,
    ShopEntry entry,
    int amount,
    int total,
  ) {
    final size = config.ledgerSize;
    if (size <= 0) return;
    final all = [
      ..._ledgerDoc.value.entries,
      LedgerEntry(
        time: clock.now(),
        uuid: who.uuid,
        player: who.name,
        kind: kind,
        item: entry.item,
        amount: amount,
        total: total,
      ),
    ];
    _ledgerDoc.value = Ledger(
      entries: all.length > size ? all.sublist(all.length - size) : all,
    );
  }

  // -- Admin ------------------------------------------------------------------

  /// Re-reads the catalog and the config from [backend]. A file that can not
  /// be parsed is reported and the shop keeps what it had.
  ReloadReport reload(StorageBackend backend) {
    try {
      final catalogText = backend.read(catalogPath);
      final configText = backend.read(configPath);
      final catalog = catalogText == null
          ? _catalogDoc.value
          : ShopCatalogMapper.fromJson(catalogText);
      final config = configText == null
          ? _configDoc.value
          : ShopConfigMapper.fromJson(configText);
      _catalogDoc.value = catalog;
      _configDoc.value = config;
    } on MapperException catch (e) {
      return ReloadReport.failed('A shop file is not valid JSON: $e');
    } on FormatException catch (e) {
      return ReloadReport.failed('A shop file is not valid JSON: $e');
    }
    _rebuild();
    return ReloadReport.ok(
      _catalog.categories.length,
      _catalog.entryCount,
      _problems,
    );
  }

  /// Sets the buy price of [item] in every category it is listed in. [sell]
  /// replaces the sell price when given (`0` stops the shop buying it).
  void setPrice(String item, int buy, {int? sell}) {
    if (buy < 1) throw const ShopException('The buy price must be at least 1.');
    if (sell != null && sell < 0) {
      throw const ShopException('The sell price can not be negative.');
    }
    final key = normalizeItemKey(item);
    final changed = _editEntries(
      key,
      (entry) => entry.copyWith(buy: buy, sell: sell ?? entry.sell),
    );
    if (changed == 0) {
      throw ShopException('${shortItemKey(key)} is not in the shop.');
    }
  }

  /// Lists [item] in the category [categoryId].
  void addItem(String categoryId, String item, int buy, {int? sell}) {
    final key = normalizeItemKey(item);
    final entry = ShopEntry(item: shortItemKey(key), buy: buy, sell: sell);
    final problem = entryProblem(entry, isKnownItem);
    if (problem != null) {
      throw ShopException('Can not add ${shortItemKey(key)}: $problem.');
    }
    final categories = _catalogDoc.value.categories;
    final index = categories.indexWhere(
      (c) => c.id == categoryId.toLowerCase(),
    );
    if (index < 0) {
      throw ShopException('There is no category called $categoryId.');
    }
    final category = categories[index];
    if (category.entries.any((e) => normalizeItemKey(e.item) == key)) {
      throw ShopException(
        '${shortItemKey(key)} is already in ${category.id}, use setprice to '
        'change it.',
      );
    }
    _catalogDoc.value = ShopCatalog(
      categories: [...categories]
        ..[index] = category.copyWith(entries: [...category.entries, entry]),
    );
    _commit();
  }

  /// Removes [item] from every category.
  void removeItem(String item) {
    final key = normalizeItemKey(item);
    if (_editEntries(key, (_) => null) == 0) {
      throw ShopException('${shortItemKey(key)} is not in the shop.');
    }
  }

  /// Replaces every entry of the item [key] with `change(entry)` (or removes
  /// it when that is `null`) and returns how many entries matched.
  int _editEntries(String key, ShopEntry? Function(ShopEntry entry) change) {
    var matched = 0;
    final categories = <ShopCategory>[];
    for (final category in _catalogDoc.value.categories) {
      final entries = <ShopEntry>[];
      for (final entry in category.entries) {
        if (normalizeItemKey(entry.item) != key) {
          entries.add(entry);
          continue;
        }
        matched++;
        final next = change(entry);
        if (next != null) entries.add(next);
      }
      categories.add(category.copyWith(entries: entries));
    }
    if (matched > 0) {
      _catalogDoc.value = ShopCatalog(categories: categories);
      _commit();
    }
    return matched;
  }

  /// Rebuilds the catalog and writes the change to disk: an admin edit should
  /// survive a crash.
  void _commit() {
    _rebuild();
    _catalogDoc.save();
  }
}
