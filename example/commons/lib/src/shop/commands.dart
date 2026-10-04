import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/permissions.dart';
import '../core/storage.dart';
import 'bag.dart';
import 'catalog.dart';
import 'messages.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';
import 'ui.dart';

/// A large purchase waiting for `/buy confirm`.
typedef PendingPurchase = ({String item, int amount, int cost});

const _confirmTtl = Duration(seconds: 20);

/// The permission of a command, registered with the node's default.
CommandPermission _commandPermission(PermNode node) =>
    switch (node.defaultFor) {
      PermDefault.everyone => CommandPermission(
        node.node,
        description: node.description,
      ),
      PermDefault.op => CommandPermission.op(
        node.node,
        description: node.description,
      ),
      PermDefault.nobody => CommandPermission.deny(
        node.node,
        description: node.description,
      ),
    };

/// Registers `/shop`, `/buy`, `/sell`, `/worth` and `/shopadmin`.
///
/// [onReloaded] runs after `/shopadmin reload` succeeded (the module uses it
/// to register the permissions of new entries).
void registerShopCommands(
  Context context, {
  required ShopService shop,
  required ShopUi ui,
  required ShopTexts texts,
  required StorageBackend backend,
  required ConfirmationManager<PendingPurchase> confirmations,
  required void Function() onReloaded,
  required Logger log,
}) {
  final commands = _ShopCommands(
    shop,
    ui,
    texts,
    backend,
    confirmations,
    onReloaded,
    log,
  );
  commands.register(context);
}

final class _ShopCommands {
  final ShopService shop;
  final ShopUi ui;
  final ShopTexts texts;
  final StorageBackend backend;
  final ConfirmationManager<PendingPurchase> confirmations;
  final void Function() onReloaded;
  final Logger log;

  _ShopCommands(
    this.shop,
    this.ui,
    this.texts,
    this.backend,
    this.confirmations,
    this.onReloaded,
    this.log,
  );

  static final _amount = ArgumentTypes.integer(min: 1, max: maxTradeAmount);

  Iterable<String> _itemNames(SuggestionContext _) => shop.catalog.names;

  void register(Context context) {
    context.command(
      'shop',
      description: 'Open the shop',
      permission: _commandPermission(ShopPerms.use),
      (c) => c
        ..requirePlayer()
        ..arg(
          'category',
          ArgumentTypes.word,
          optional: true,
          suggestsWith: (_) => [for (final c in shop.catalog.categories) c.id],
          runs: _openShop,
        ),
    );

    context.command(
      'buy',
      description: 'Buy items from the shop',
      permission: _commandPermission(ShopPerms.buy),
      (c) => c
        ..requirePlayer()
        ..sub(
          'confirm',
          description: 'Confirm a large purchase',
          runs: _confirmPurchase,
        )
        ..arg(
          'item',
          ArgumentTypes.word,
          suggestsWith: _itemNames,
          build: (a) => a.arg('amount', _amount, optional: true, runs: _buy),
        ),
    );

    context.command(
      'sell',
      description: 'Sell items to the shop (an item, "hand" or "all")',
      permission: _commandPermission(ShopPerms.sell),
      (c) => c
        ..requirePlayer()
        ..arg(
          'what',
          ArgumentTypes.word,
          suggestsWith: (s) => ['hand', 'all', ..._itemNames(s)],
          build: (a) => a.arg('amount', _amount, optional: true, runs: _sell),
        ),
    );

    context.command(
      'worth',
      description: 'Show the price of an item (default: the one you hold)',
      permission: _commandPermission(ShopPerms.use),
      (c) => c
        ..requirePlayer()
        ..arg(
          'item',
          ArgumentTypes.word,
          optional: true,
          suggestsWith: _itemNames,
          runs: _worth,
        ),
    );

    context.command(
      'shopadmin',
      description: 'Manage the shop',
      permission: _commandPermission(ShopPerms.admin),
      (c) => c
        ..sub('reload', description: 'Reload the shop files', runs: _reload)
        ..sub(
          'setprice',
          description: 'Set the buy (and sell) price of an item',
          build: (s) => s.arg(
            'item',
            ArgumentTypes.word,
            suggestsWith: _itemNames,
            build: (i) => i.arg(
              'buy',
              ArgumentTypes.integer(min: 1),
              build: (b) => b.arg(
                'sell',
                ArgumentTypes.integer(min: 0),
                optional: true,
                runs: _setPrice,
              ),
            ),
          ),
        )
        ..sub(
          'additem',
          description: 'List the item in your hand in a category',
          build: (s) => s.arg(
            'category',
            ArgumentTypes.word,
            suggestsWith: (_) => [
              for (final c in shop.catalog.categories) c.id,
            ],
            build: (cat) => cat.arg(
              'buy',
              ArgumentTypes.integer(min: 1),
              build: (b) => b.arg(
                'sell',
                ArgumentTypes.integer(min: 0),
                optional: true,
                runs: _addItem,
              ),
            ),
          ),
        )
        ..sub(
          'removeitem',
          description: 'Remove an item from the shop',
          build: (s) => s.arg(
            'item',
            ArgumentTypes.word,
            suggestsWith: _itemNames,
            runs: _removeItem,
          ),
        )
        ..sub(
          'log',
          description: 'Show the latest trades',
          build: (s) => s.arg(
            'count',
            ArgumentTypes.integer(min: 1, max: 50),
            optional: true,
            runs: _log,
          ),
        ),
    );
  }

  // -- Helpers ----------------------------------------------------------------

  /// Fails the command with the message [key], shown without colors.
  Never _fail(String key, [Map<String, Object?> values = const {}]) =>
      throw CommandException(
        MessageFormat.stripColors(texts.plain(key, values)),
      );

  ShopEntry _entry(String name) =>
      shop.catalog.find(name) ??
      _fail('err.unknown_item', {'item': MessageFormat.escape(name)});

  void _say(CommandContext ctx, String line) => ctx.sender.send(line);

  // -- Player commands --------------------------------------------------------

  void _openShop(CommandContext ctx) {
    final category = ctx.stringOrNull('category');
    if (category == null) {
      ui.open(ctx.player);
    } else if (!ui.openCategory(ctx.player, category)) {
      _fail('err.no_category', {'name': MessageFormat.escape(category)});
    }
  }

  void _buy(CommandContext ctx) {
    final player = ctx.player;
    final entry = _entry(ctx.string('item'));
    final amount = ctx.integerOrNull('amount') ?? 1;
    final cost = shop.buyCost(entry, amount);
    if (shop.needsConfirmation(cost)) {
      confirmations.request(_uuid(player), (
        item: entry.item,
        amount: amount,
        cost: cost,
      ), ttl: _confirmTtl);
      player.send(
        Text.legacy(
          texts.line('confirm.ask', {
            'amount': amount,
            'item': prettyItemName(entry.item),
            'money': texts.money(cost),
          }),
        ).add(
          Text(texts.plain('confirm.button'))
              .green()
              .bold()
              .runCommand('/buy confirm')
              .hover(texts.plain('confirm.hover')),
        ),
      );
      return;
    }
    _say(ctx, texts.trade(shop.buy(PlayerShopper(player), entry, amount)));
  }

  void _confirmPurchase(CommandContext ctx) {
    final player = ctx.player;
    final pending = confirmations.confirm(_uuid(player));
    if (pending == null) _fail('err.not_confirmed');
    final entry = _entry(pending.item);
    _say(
      ctx,
      texts.trade(
        shop.buy(
          PlayerShopper(player),
          entry,
          pending.amount,
          expectedCost: pending.cost,
        ),
      ),
    );
  }

  void _sell(CommandContext ctx) {
    final player = ctx.player;
    final shopper = PlayerShopper(player);
    final what = ctx.string('what').toLowerCase();
    final typedAmount = ctx.integerOrNull('amount');

    if (what == 'all') {
      if (typedAmount != null) ctx.failUsage('"all" takes no amount.');
      final sale = shop.sellAll(shopper);
      for (final line in texts.bulkSale(
        sale,
        shop.economy.balance(shopper.uuid),
      )) {
        _say(ctx, line);
      }
      return;
    }

    final ShopEntry entry;
    final int amount;
    if (what == 'hand') {
      final held = shopper.bag.held();
      if (held == null) _fail('err.hand_empty');
      if (!held.plain) _fail('err.hand_custom');
      entry = _entry(held.key);
      amount = typedAmount ?? held.count;
    } else {
      entry = _entry(what);
      amount = typedAmount ?? 1;
    }
    _say(ctx, texts.trade(shop.sell(shopper, entry, amount)));
  }

  void _worth(CommandContext ctx) {
    final typed = ctx.stringOrNull('item');
    final String key;
    if (typed != null) {
      key = typed;
    } else {
      final held = PlayerBag(ctx.player).held();
      if (held == null) _fail('err.hand_empty');
      key = held.key;
    }
    final entry = _entry(key);
    final sell = shop.sellPriceOf(entry);
    final values = {
      'item': prettyItemName(entry.item),
      'buy': texts.money(entry.buy),
      'sell': sell == null ? '' : texts.money(sell),
    };
    _say(
      ctx,
      texts.line(sell == null ? 'worth.buy_only' : 'worth.both', values),
    );
  }

  // -- Admin ------------------------------------------------------------------

  void _reload(CommandContext ctx) {
    final report = shop.reload(backend);
    if (!report.ok) {
      _say(ctx, texts.line('admin.reload_failed', {'error': report.error}));
      return;
    }
    _say(
      ctx,
      texts.line('admin.reloaded', {
        'categories': report.categories,
        'entries': report.entries,
      }),
    );
    for (final problem in report.problems) {
      log.warn(problem);
      _say(ctx, texts.plain('admin.problem', {'problem': problem}));
    }
    onReloaded();
  }

  /// Runs an edit and turns a [ShopException] into a failed command.
  void _edit(void Function() change) {
    try {
      change();
    } on ShopException catch (e) {
      throw CommandException(e.message);
    }
  }

  void _setPrice(CommandContext ctx) {
    final item = ctx.string('item');
    _edit(
      () => shop.setPrice(
        item,
        ctx.integer('buy'),
        sell: ctx.integerOrNull('sell'),
      ),
    );
    final entry = _entry(item);
    final sell = shop.sellPriceOf(entry);
    _say(
      ctx,
      texts.line('admin.price', {
        'item': prettyItemName(entry.item),
        'buy': texts.money(entry.buy),
        'sell': sell == null ? texts.plain('sell.none') : texts.money(sell),
      }),
    );
  }

  void _addItem(CommandContext ctx) {
    final held = PlayerBag(ctx.player).held();
    if (held == null) _fail('err.hand_empty');
    final category = ctx.string('category');
    final buy = ctx.integer('buy');
    _edit(
      () => shop.addItem(
        category,
        held.key,
        buy,
        sell: ctx.integerOrNull('sell'),
      ),
    );
    _say(
      ctx,
      texts.line('admin.added', {
        'item': prettyItemName(held.key),
        'category': category,
        'buy': texts.money(buy),
      }),
    );
  }

  void _removeItem(CommandContext ctx) {
    final item = ctx.string('item');
    _edit(() => shop.removeItem(item));
    _say(
      ctx,
      texts.line('admin.removed', {
        'item': prettyItemName(normalizeItemKey(item)),
      }),
    );
  }

  void _log(CommandContext ctx) {
    final count = ctx.integerOrNull('count') ?? 10;
    final all = shop.ledger;
    if (all.isEmpty) {
      _say(ctx, texts.line('admin.log_empty'));
      return;
    }
    final shown = all.length > count ? all.sublist(all.length - count) : all;
    _say(ctx, texts.line('admin.log_header', {'count': shown.length}));
    for (final e in shown.reversed) {
      _say(
        ctx,
        texts.plain('admin.log_line', {
          'time': e.time
              .toUtc()
              .toIso8601String()
              .substring(0, 16)
              .replaceFirst('T', ' '),
          'player': MessageFormat.escape(e.player),
          'kind': e.kind.name,
          'amount': e.amount,
          'item': prettyItemName(e.item),
          'total': texts.money(e.total),
        }),
      );
    }
  }

  String _uuid(Player player) => player.asEntity().getUuid().asString;
}
