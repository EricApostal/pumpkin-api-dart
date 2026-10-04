import 'package:commons/src/core/clock.dart';
import 'package:commons/src/core/storage.dart';
import 'package:commons/src/shop/catalog.dart';
import 'package:commons/src/shop/defaults.dart';
import 'package:commons/src/shop/messages.dart';
import 'package:commons/src/shop/model.dart';
import 'package:commons/src/shop/service.dart';
import 'package:pumpkin_api/src/message_format.dart';
import 'package:test/test.dart';

import 'fakes_shop_kits.dart';

/// An inventory with [slots] slots of 64.
final class FakeBag implements ItemBag {
  final int slots;
  final Map<String, int> items = {};

  /// Fail [add] after putting this many items in (`null`: never).
  int? failAddAfter;

  /// Throw from [add] when set.
  bool addThrows = false;

  FakeBag({this.slots = 36});

  int get _used => items.values.fold(0, (sum, n) => sum + (n + 63) ~/ 64);

  @override
  int spaceFor(String key) {
    final have = items[key] ?? 0;
    final slack = (64 - have % 64) % 64;
    final free = (slots - _used) * 64;
    return slack + free;
  }

  @override
  int countOf(String key) => items[key] ?? 0;

  @override
  int add(String key, int count) {
    if (addThrows) throw StateError('inventory is gone');
    final room = failAddAfter ?? spaceFor(key);
    final put = count < room ? count : room;
    if (put > 0) items[key] = (items[key] ?? 0) + put;
    return count - put;
  }

  @override
  int remove(String key, int count) {
    final have = items[key] ?? 0;
    final taken = count < have ? count : have;
    if (have - taken == 0) {
      items.remove(key);
    } else {
      items[key] = have - taken;
    }
    return taken;
  }
}

final class FakeShopper implements Shopper {
  @override
  final String uuid;
  @override
  final String name;
  @override
  final FakeBag bag;
  final Set<String> permissions;

  FakeShopper(this.uuid, this.name, {FakeBag? bag, this.permissions = const {}})
    : bag = bag ?? FakeBag();

  @override
  bool hasPermission(String node) => permissions.contains(node);
}

const _known = {
  'minecraft:diamond',
  'minecraft:stone',
  'minecraft:dirt',
  'minecraft:chest',
  'minecraft:iron_sword',
  'minecraft:apple',
  'minecraft:grass_block',
};

bool isKnown(String key) => _known.contains(key);

void main() {
  group('normalizeItemKey', () {
    test('adds the namespace and lower-cases', () {
      expect(normalizeItemKey('Diamond'), 'minecraft:diamond');
      expect(normalizeItemKey(' minecraft:Stone '), 'minecraft:stone');
      expect(normalizeItemKey('mymod:ruby'), 'mymod:ruby');
      expect(shortItemKey('minecraft:diamond'), 'diamond');
      expect(shortItemKey('mymod:ruby'), 'mymod:ruby');
    });
  });

  group('validateCatalog', () {
    ShopCatalog one(List<ShopEntry> entries, {String id = 'blocks'}) =>
        ShopCatalog(
          categories: [
            ShopCategory(
              id: id,
              name: 'Blocks',
              icon: 'stone',
              entries: entries,
            ),
          ],
        );

    test('keeps good entries and normalises their keys', () {
      final report = validateCatalog(
        one([const ShopEntry(item: 'Stone', buy: 4)]),
        isKnownItem: isKnown,
      );
      expect(report.problems, isEmpty);
      expect(report.catalog.find('stone')!.item, 'minecraft:stone');
      expect(report.catalog.find('MINECRAFT:STONE'), isNotNull);
      expect(report.catalog.names, ['stone']);
    });

    test('skips and reports unknown items and bad numbers', () {
      final report = validateCatalog(
        one([
          const ShopEntry(item: 'stone', buy: 4),
          const ShopEntry(item: 'bedrock_x', buy: 4),
          const ShopEntry(item: 'dirt', buy: 0),
          const ShopEntry(item: 'chest', buy: 5, sell: -1),
          const ShopEntry(item: 'apple', buy: 5, amount: 0),
          const ShopEntry(item: 'diamond', buy: 5, amount: 8, stack: 4),
          const ShopEntry(item: 'iron_sword', buy: 5, permission: 'nocolon'),
          const ShopEntry(item: 'stone', buy: 9),
        ]),
        isKnownItem: isKnown,
      );
      expect(report.catalog.entryCount, 1);
      expect(report.problems, hasLength(7));
      expect(report.problems.first, contains('bedrock_x'));
      expect(report.problems.last, contains('listed twice'));
      expect(report.catalog.find('stone')!.buy, 4);
    });

    test('skips broken categories and replaces unknown icons', () {
      final report = validateCatalog(
        ShopCatalog(
          categories: [
            const ShopCategory(id: 'Bad Id', name: 'x', icon: 'stone'),
            const ShopCategory(id: 'ok', name: ' ', icon: 'nope'),
            const ShopCategory(id: 'ok', name: 'dup', icon: 'stone'),
          ],
        ),
        isKnownItem: isKnown,
      );
      expect(report.catalog.categories.map((c) => c.id), ['ok']);
      final ok = report.catalog.category('OK')!;
      expect(ok.icon, 'minecraft:chest');
      expect(ok.name, 'ok');
      expect(report.problems, hasLength(3));
    });

    test('limits the number of categories', () {
      final report = validateCatalog(
        ShopCatalog(
          categories: [
            for (var i = 0; i < maxCategories + 2; i++)
              ShopCategory(id: 'c$i', name: 'c', icon: 'stone'),
          ],
        ),
        isKnownItem: isKnown,
      );
      expect(report.catalog.categories, hasLength(maxCategories));
      expect(report.problems, hasLength(2));
    });

    test('the first of two categories listing an item wins', () {
      final report = validateCatalog(
        ShopCatalog(
          categories: [
            const ShopCategory(
              id: 'a',
              name: 'a',
              icon: 'stone',
              entries: [ShopEntry(item: 'stone', buy: 4)],
            ),
            const ShopCategory(
              id: 'b',
              name: 'b',
              icon: 'stone',
              entries: [ShopEntry(item: 'stone', buy: 9)],
            ),
          ],
        ),
        isKnownItem: isKnown,
      );
      expect(report.catalog.find('stone')!.buy, 4);
    });
  });

  group('default catalog', () {
    test('is valid when every item exists', () {
      final report = validateCatalog(
        defaultCatalog(),
        isKnownItem: (_) => true,
      );
      expect(report.problems, isEmpty);
      expect(report.catalog.categories.map((c) => c.id), [
        'blocks',
        'tools',
        'food',
        'redstone',
        'misc',
      ]);
    });

    test('survives a JSON round trip', () {
      final json = defaultCatalog().toJson();
      final back = ShopCatalogMapper.fromJson(json);
      expect(back, defaultCatalog());
    });

    test('has no duplicate items', () {
      final report = validateCatalog(
        defaultCatalog(),
        isKnownItem: (_) => true,
      );
      final all = [
        for (final c in report.catalog.categories)
          for (final e in c.entries) e.item,
      ];
      expect(all.toSet(), hasLength(all.length));
    });

    test('every item can be sold at the default percentage', () {
      final report = validateCatalog(
        defaultCatalog(),
        isKnownItem: (_) => true,
      );
      for (final c in report.catalog.categories) {
        for (final e in c.entries) {
          expect(e.buy * 50 ~/ 100, greaterThanOrEqualTo(1), reason: e.item);
        }
      }
    });
  });

  group('ShopService', () {
    late MemoryBackend backend;
    late Documents docs;
    late FakeEconomy economy;
    late FakeClock clock;
    late ShopService shop;
    late FakeShopper steve;

    ShopService build({ShopCatalog? catalog, ShopConfig? config}) {
      docs = Documents(backend, clock: clock);
      return ShopService(
        economy: economy,
        clock: clock,
        catalog: docs.open(
          catalogPath,
          decode: ShopCatalogMapper.fromJson,
          encode: (v) => v.toJson(),
          create: () =>
              catalog ??
              const ShopCatalog(
                categories: [
                  ShopCategory(
                    id: 'blocks',
                    name: 'Blocks',
                    icon: 'stone',
                    entries: [
                      ShopEntry(item: 'stone', buy: 10),
                      ShopEntry(item: 'dirt', buy: 1),
                      ShopEntry(item: 'diamond', buy: 100, sell: 80),
                      ShopEntry(item: 'chest', buy: 20, sell: 0),
                      ShopEntry(
                        item: 'iron_sword',
                        buy: 50,
                        permission: 'x:vip',
                      ),
                    ],
                  ),
                ],
              ),
        ),
        config: docs.open(
          configPath,
          decode: ShopConfigMapper.fromJson,
          encode: (v) => v.toJson(),
          create: () => config ?? const ShopConfig(),
        ),
        ledger: docs.open(
          ledgerPath,
          decode: LedgerMapper.fromJson,
          encode: (v) => v.toJson(),
          create: Ledger.new,
        ),
        isKnownItem: isKnown,
      );
    }

    setUp(() {
      backend = MemoryBackend();
      clock = FakeClock();
      economy = FakeEconomy();
      economy.balances['u1'] = 1000;
      shop = build();
      steve = FakeShopper('u1', 'Steve');
    });

    ShopEntry entry(String item) => shop.catalog.find(item)!;

    group('prices', () {
      test('sell price is the percentage of the buy price, rounded down', () {
        expect(shop.sellPriceOf(entry('stone')), 5);
        expect(shop.sellPriceOf(entry('dirt')), isNull); // 1 * 50% = 0
        expect(shop.sellPriceOf(entry('diamond')), 80); // explicit
        expect(shop.sellPriceOf(entry('chest')), isNull); // explicit 0
        expect(shop.sellValue(entry('stone'), 7), 35);
        expect(shop.buyCost(entry('stone'), 7), 70);
      });

      test('the sell percentage is limited to 0-100', () {
        shop = build(config: const ShopConfig(sellPercent: 300));
        expect(shop.sellPriceOf(shop.catalog.find('stone')!), 10);
        shop = build(config: const ShopConfig(sellPercent: -5));
        expect(shop.sellPriceOf(shop.catalog.find('stone')!), isNull);
      });

      test('confirmation threshold', () {
        expect(shop.needsConfirmation(4999), isFalse);
        expect(shop.needsConfirmation(5000), isTrue);
        shop = build(config: const ShopConfig(confirmThreshold: 0));
        expect(shop.needsConfirmation(1000000), isFalse);
      });
    });

    group('buy', () {
      test('charges and delivers', () {
        final r = shop.buy(steve, entry('stone'), 5);
        expect(r.isOk, isTrue);
        expect(r.items, 5);
        expect(r.money, 50);
        expect(r.balance, 950);
        expect(economy.balance('u1'), 950);
        expect(steve.bag.countOf('minecraft:stone'), 5);
      });

      test('refuses when the player cannot pay and changes nothing', () {
        economy.balances['u1'] = 30;
        final r = shop.buy(steve, entry('stone'), 5);
        expect(r.failure, TradeFailure.insufficientFunds);
        expect(r.detail, 20); // 20 coins short
        expect(r.balance, 30);
        expect(economy.balance('u1'), 30);
        expect(steve.bag.items, isEmpty);
        expect(shop.ledger, isEmpty);
      });

      test('checks space before charging', () {
        steve = FakeShopper('u1', 'Steve', bag: FakeBag(slots: 1));
        steve.bag.items['minecraft:dirt'] = 64; // the only slot is taken
        final r = shop.buy(steve, entry('stone'), 1);
        expect(r.failure, TradeFailure.noSpace);
        expect(r.detail, 0);
        expect(economy.balance('u1'), 1000);
        expect(economy.log, isEmpty);
      });

      test('reports how many would fit', () {
        steve = FakeShopper('u1', 'Steve', bag: FakeBag(slots: 1));
        final r = shop.buy(steve, entry('stone'), 100);
        expect(r.failure, TradeFailure.noSpace);
        expect(r.detail, 64);
        expect(economy.log, isEmpty);
      });

      test('tops up an existing stack', () {
        steve = FakeShopper('u1', 'Steve', bag: FakeBag(slots: 1));
        steve.bag.items['minecraft:stone'] = 60;
        final r = shop.buy(steve, entry('stone'), 4);
        expect(r.isOk, isTrue);
        expect(steve.bag.countOf('minecraft:stone'), 64);
      });

      test('refunds the items that did not fit', () {
        // The space check said yes, but the hand-over delivers only 3 of 5.
        steve.bag.failAddAfter = 3;
        final r = shop.buy(steve, entry('stone'), 5);
        expect(r.isOk, isTrue);
        expect(r.items, 3);
        expect(r.money, 30);
        expect(r.refunded, 20);
        expect(economy.balance('u1'), 970);
        expect(steve.bag.countOf('minecraft:stone'), 3);
        expect(shop.ledger.single.amount, 3);
        expect(shop.ledger.single.total, 30);
      });

      test('refunds everything when nothing was delivered', () {
        steve.bag.failAddAfter = 0;
        final r = shop.buy(steve, entry('stone'), 5);
        expect(r.failure, TradeFailure.deliveryFailed);
        expect(economy.balance('u1'), 1000);
        expect(steve.bag.items, isEmpty);
        expect(shop.ledger, isEmpty);
      });

      test('refunds everything when the hand-over throws', () {
        steve.bag.addThrows = true;
        final warnings = <String>[];
        shop = ShopService(
          economy: economy,
          clock: clock,
          catalog: docs.open(
            'c2.json',
            decode: ShopCatalogMapper.fromJson,
            encode: (v) => v.toJson(),
            create: defaultCatalog,
          ),
          config: docs.open(
            'cf2.json',
            decode: ShopConfigMapper.fromJson,
            encode: (v) => v.toJson(),
            create: ShopConfig.new,
          ),
          ledger: docs.open(
            'l2.json',
            decode: LedgerMapper.fromJson,
            encode: (v) => v.toJson(),
            create: Ledger.new,
          ),
          isKnownItem: (_) => true,
          warn: warnings.add,
        );
        final r = shop.buy(steve, shop.catalog.find('stone')!, 5);
        expect(r.failure, TradeFailure.deliveryFailed);
        expect(economy.balance('u1'), 1000);
        expect(warnings, hasLength(1));
      });

      test('never charges twice for the same click', () {
        // Two clicks are two calls; each one is charged once.
        shop.buy(steve, entry('stone'), 1);
        shop.buy(steve, entry('stone'), 1);
        expect(economy.balance('u1'), 980);
        expect(steve.bag.countOf('minecraft:stone'), 2);
      });

      test('rejects invalid amounts', () {
        expect(
          shop.buy(steve, entry('stone'), 0).failure,
          TradeFailure.invalidAmount,
        );
        expect(
          shop.buy(steve, entry('stone'), -3).failure,
          TradeFailure.invalidAmount,
        );
        expect(
          shop.buy(steve, entry('stone'), maxTradeAmount + 1).failure,
          TradeFailure.invalidAmount,
        );
        expect(economy.log, isEmpty);
      });

      test('needs the entry permission', () {
        expect(
          shop.buy(steve, entry('iron_sword'), 1).failure,
          TradeFailure.noPermission,
        );
        final vip = FakeShopper('u1', 'Steve', permissions: {'x:vip'});
        expect(shop.buy(vip, entry('iron_sword'), 1).isOk, isTrue);
      });

      test('refuses a confirmed purchase whose price changed', () {
        final quote = shop.buyCost(entry('stone'), 10);
        shop.setPrice('stone', 20);
        final r = shop.buy(steve, entry('stone'), 10, expectedCost: quote);
        expect(r.failure, TradeFailure.priceChanged);
        expect(economy.balance('u1'), 1000);
        expect(
          shop.buy(steve, entry('stone'), 10, expectedCost: 200).isOk,
          isTrue,
        );
      });

      test('a failing deposit during a refund does not throw', () {
        steve.bag.failAddAfter = 0;
        economy.refuseDeposits = true;
        final warnings = <String>[];
        final s = ShopService(
          economy: economy,
          clock: clock,
          catalog: docs.open(
            'c3.json',
            decode: ShopCatalogMapper.fromJson,
            encode: (v) => v.toJson(),
            create: defaultCatalog,
          ),
          config: docs.open(
            'cf3.json',
            decode: ShopConfigMapper.fromJson,
            encode: (v) => v.toJson(),
            create: ShopConfig.new,
          ),
          ledger: docs.open(
            'l3.json',
            decode: LedgerMapper.fromJson,
            encode: (v) => v.toJson(),
            create: Ledger.new,
          ),
          isKnownItem: (_) => true,
          warn: warnings.add,
        );
        final r = s.buy(steve, s.catalog.find('stone')!, 2);
        expect(r.failure, TradeFailure.deliveryFailed);
        expect(warnings, hasLength(1));
        expect(warnings.single, contains('refund'));
      });
    });

    group('sell', () {
      test('takes the items and pays', () {
        steve.bag.items['minecraft:stone'] = 10;
        final r = shop.sell(steve, entry('stone'), 4);
        expect(r.isOk, isTrue);
        expect(r.items, 4);
        expect(r.money, 20);
        expect(economy.balance('u1'), 1020);
        expect(steve.bag.countOf('minecraft:stone'), 6);
      });

      test('verifies the player has the items first', () {
        steve.bag.items['minecraft:stone'] = 3;
        final r = shop.sell(steve, entry('stone'), 4);
        expect(r.failure, TradeFailure.nothingToSell);
        expect(r.detail, 3);
        expect(economy.balance('u1'), 1000);
        expect(steve.bag.countOf('minecraft:stone'), 3);
      });

      test('refuses items the shop does not buy', () {
        steve.bag.items['minecraft:chest'] = 1;
        steve.bag.items['minecraft:dirt'] = 1;
        expect(
          shop.sell(steve, entry('chest'), 1).failure,
          TradeFailure.notForSale,
        );
        expect(
          shop.sell(steve, entry('dirt'), 1).failure,
          TradeFailure.notForSale,
        );
        expect(steve.bag.items, hasLength(2));
      });

      test('pays only for what really left the inventory', () {
        steve.bag.items['minecraft:stone'] = 4;
        final partial = _PartialBag(steve.bag, takes: 2);
        final who = FakeShopper('u1', 'Steve', bag: partial);
        final r = shop.sell(who, entry('stone'), 4);
        expect(r.items, 2);
        expect(r.money, 10);
      });

      test('pays for the difference when the removal throws', () {
        steve.bag.items['minecraft:stone'] = 4;
        final bag = _ThrowingBag(steve.bag, removeFirst: 1);
        final who = FakeShopper('u1', 'Steve', bag: bag);
        final r = shop.sell(who, entry('stone'), 4);
        expect(r.items, 1);
        expect(economy.balance('u1'), 1005);
      });

      test('pays nothing when nothing left the inventory', () {
        steve.bag.items['minecraft:stone'] = 4;
        final who = FakeShopper(
          'u1',
          'Steve',
          bag: _PartialBag(steve.bag, takes: 0),
        );
        final r = shop.sell(who, entry('stone'), 4);
        expect(r.failure, TradeFailure.deliveryFailed);
        expect(economy.balance('u1'), 1000);
      });

      test('selling needs the permission too', () {
        steve.bag.items['minecraft:iron_sword'] = 1;
        expect(
          shop.sell(steve, entry('iron_sword'), 1).failure,
          TradeFailure.noPermission,
        );
      });
    });

    group('sellAll', () {
      test('sells everything the shop buys and leaves the rest', () {
        steve.bag.items
          ..['minecraft:stone'] = 10
          ..['minecraft:diamond'] = 2
          ..['minecraft:chest'] =
              5 // not bought
          ..['minecraft:grass_block'] = 9; // not in the shop
        final r = shop.sellAll(steve);
        expect(r.items, 12);
        expect(r.money, 10 * 5 + 2 * 80);
        expect(economy.balance('u1'), 1000 + 210);
        expect(steve.bag.items.keys.toSet(), {
          'minecraft:chest',
          'minecraft:grass_block',
        });
      });

      test('counts what it could not sell', () {
        steve.bag.items['minecraft:iron_sword'] = 1; // needs x:vip
        final r = shop.sellAll(steve);
        expect(r.sales, isEmpty);
        expect(r.skipped, 1);
      });

      test('splits piles larger than one trade', () {
        steve = FakeShopper('u1', 'Steve', bag: FakeBag(slots: 100));
        steve.bag.items['minecraft:stone'] = maxTradeAmount + 100;
        final r = shop.sellAll(steve);
        expect(r.items, maxTradeAmount + 100);
        expect(r.sales, hasLength(2));
        expect(steve.bag.items, isEmpty);
      });
    });

    group('ledger', () {
      test('records trades and stays bounded', () {
        shop = build(config: const ShopConfig(ledgerSize: 3));
        steve.bag.items['minecraft:stone'] = 50;
        for (var i = 1; i <= 5; i++) {
          clock.advance(const Duration(minutes: 1));
          shop.buy(steve, shop.catalog.find('dirt')!, i);
        }
        shop.sell(steve, shop.catalog.find('stone')!, 2);
        final log = shop.ledger;
        expect(log, hasLength(3));
        expect(log.map((e) => e.amount), [4, 5, 2]);
        expect(log.last.kind, TradeKind.sell);
        expect(log.last.total, 10);
        expect(log.last.player, 'Steve');
        expect(log.last.time, clock.now());
      });

      test('can be switched off', () {
        shop = build(config: const ShopConfig(ledgerSize: 0));
        shop.buy(steve, shop.catalog.find('dirt')!, 1);
        expect(shop.ledger, isEmpty);
      });

      test('is persisted', () {
        shop.buy(steve, entry('dirt'), 1);
        docs.saveDirty();
        expect(backend.files[ledgerPath], contains('dirt'));
      });
    });

    group('admin', () {
      test('setPrice changes the price and saves', () {
        shop.setPrice('Stone', 12, sell: 6);
        expect(entry('stone').buy, 12);
        expect(shop.sellPriceOf(entry('stone')), 6);
        expect(backend.files[catalogPath], isNotNull);
        expect(
          ShopCatalogMapper.fromJson(backend.files[catalogPath]!)
              .categories
              .first
              .entries
              .first
              .buy,
          12,
        );
      });

      test('setPrice keeps the sell price when none is given', () {
        shop.setPrice('diamond', 90);
        expect(entry('diamond').sell, 80);
      });

      test('setPrice validates', () {
        expect(() => shop.setPrice('stone', 0), throwsA(isA<ShopException>()));
        expect(
          () => shop.setPrice('stone', 5, sell: -1),
          throwsA(isA<ShopException>()),
        );
        expect(
          () => shop.setPrice('grass_block', 5),
          throwsA(isA<ShopException>()),
        );
      });

      test('addItem lists a new item', () {
        shop.addItem('blocks', 'minecraft:apple', 7);
        expect(entry('apple').buy, 7);
        expect(shop.catalog.names, contains('apple'));
      });

      test('addItem rejects unknown items, categories and duplicates', () {
        expect(
          () => shop.addItem('blocks', 'nonsense', 7),
          throwsA(isA<ShopException>()),
        );
        expect(
          () => shop.addItem('nope', 'apple', 7),
          throwsA(isA<ShopException>()),
        );
        expect(
          () => shop.addItem('blocks', 'stone', 7),
          throwsA(isA<ShopException>()),
        );
        expect(
          () => shop.addItem('blocks', 'apple', 0),
          throwsA(isA<ShopException>()),
        );
      });

      test('removeItem removes it everywhere', () {
        shop.removeItem('stone');
        expect(shop.catalog.find('stone'), isNull);
        expect(() => shop.removeItem('stone'), throwsA(isA<ShopException>()));
      });

      test('reload picks up a hand-edited file', () {
        backend.files[catalogPath] = const ShopCatalog(
          categories: [
            ShopCategory(
              id: 'one',
              name: 'One',
              icon: 'stone',
              entries: [
                ShopEntry(item: 'apple', buy: 3),
                ShopEntry(item: 'bogus', buy: 3),
              ],
            ),
          ],
        ).toJson();
        backend.files[configPath] = const ShopConfig(sellPercent: 10).toJson();
        final report = shop.reload(backend);
        expect(report.ok, isTrue);
        expect(report.categories, 1);
        expect(report.entries, 1);
        expect(report.problems, hasLength(1));
        expect(shop.catalog.find('stone'), isNull);
        expect(shop.sellPercent, 10);
        // The bad entry stays in the file for the owner to fix.
        docs.saveDirty();
        expect(backend.files[catalogPath], contains('bogus'));
      });

      test('reload keeps the old shop when the file is broken', () {
        backend.files[catalogPath] = '{oops';
        final report = shop.reload(backend);
        expect(report.ok, isFalse);
        expect(report.error, isNotNull);
        expect(shop.catalog.find('stone'), isNotNull);
      });
    });
  });

  group('ShopTexts', () {
    final texts = ShopTexts(
      MessageCatalog(shopMessageDefaults),
      FakeEconomy(),
      () => '[Shop] ',
    );
    const stone = ShopEntry(item: 'minecraft:stone', buy: 10);

    test('describes every failure without leftover placeholders', () {
      for (final failure in TradeFailure.values) {
        for (final kind in TradeKind.values) {
          for (final detail in [0, 7]) {
            final text = texts.trade(
              TradeResult.failed(kind, failure, entry: stone, detail: detail),
            );
            expect(text, startsWith('[Shop] '), reason: '$failure');
            expect(text, isNot(contains('{')), reason: '$failure $detail');
            expect(text.length, greaterThan(10));
          }
        }
      }
    });

    test('describes a purchase with a refund', () {
      const result = TradeResult.ok(
        TradeKind.buy,
        stone,
        items: 3,
        money: 30,
        refunded: 20,
        balance: 970,
      );
      final text = texts.trade(result, withPrefix: false);
      expect(text, contains('Bought'));
      expect(text, contains('3x Stone'));
      expect(text, contains('30 coins'));
      expect(text, contains('2 item(s) did not fit'));
      expect(text, isNot(startsWith('[Shop]')));
    });

    test('shows how much is missing', () {
      final text = texts.trade(
        const TradeResult.failed(
          TradeKind.buy,
          TradeFailure.insufficientFunds,
          entry: stone,
          detail: 20,
        ),
      );
      expect(text, contains('20 coins'));
    });

    test('summarises a bulk sale', () {
      expect(
        texts.bulkSale(const BulkSale([], 0), 5).single,
        contains('nothing'),
      );
      const sale = BulkSale([
        TradeResult.ok(TradeKind.sell, stone, items: 4, money: 20, balance: 70),
      ], 1);
      final lines = texts.bulkSale(sale, 70);
      expect(lines, hasLength(2));
      expect(lines.first, contains('4 items'));
    });

    test('prettyItemName', () {
      expect(prettyItemName('minecraft:diamond_sword'), 'Diamond Sword');
      expect(prettyItemName('mymod:ruby'), 'Ruby');
    });
  });
}

/// A bag whose [remove] takes fewer items than asked.
final class _PartialBag extends FakeBag {
  final int takes;
  _PartialBag(FakeBag from, {required this.takes}) {
    items.addAll(from.items);
  }

  @override
  int remove(String key, int count) => super.remove(key, takes);
}

/// A bag that removes [removeFirst] items and then throws.
final class _ThrowingBag extends FakeBag {
  final int removeFirst;
  _ThrowingBag(FakeBag from, {required this.removeFirst}) {
    items.addAll(from.items);
  }

  @override
  int remove(String key, int count) {
    super.remove(key, removeFirst);
    throw StateError('lost the player');
  }
}
