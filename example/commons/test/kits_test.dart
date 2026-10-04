import 'package:commons/src/core/clock.dart';
import 'package:commons/src/core/storage.dart';
import 'package:commons/src/kits/catalog.dart';
import 'package:commons/src/kits/defaults.dart';
import 'package:commons/src/kits/messages.dart';
import 'package:commons/src/kits/model.dart';
import 'package:commons/src/kits/permissions.dart';
import 'package:commons/src/kits/service.dart';
import 'package:pumpkin_api/src/message_format.dart';
import 'package:test/test.dart';

import 'fakes_shop_kits.dart';

const _items = {
  'minecraft:bread',
  'minecraft:diamond',
  'minecraft:stone_sword',
  'minecraft:chest',
  'minecraft:diamond_pickaxe',
};
const _enchantments = {'efficiency', 'unbreaking'};

bool knownItem(String key) => _items.contains(key);
bool knownEnchantment(String key) => _enchantments.contains(key);

/// A player with [slots] free slots who can be made to fail.
final class FakeRecipient implements KitRecipient {
  @override
  final String uuid;
  @override
  final String name;
  final Set<String> permissions;
  int slots;
  final List<List<KitItem>> received = [];
  bool giveThrows = false;

  FakeRecipient(
    this.uuid,
    this.name, {
    this.permissions = const {},
    this.slots = 36,
  });

  @override
  bool hasPermission(String node) => permissions.contains(node);

  @override
  bool canFit(List<KitItem> items) => items.length <= slots;

  @override
  void give(List<KitItem> items) {
    if (giveThrows) throw StateError('player left');
    slots -= items.length;
    received.add(items);
  }
}

String _node(String kit) => kitPermission(kit);

void main() {
  group('validateKits', () {
    KitReport validate(List<Kit> kits) => validateKits(
      KitCatalog(kits: kits),
      isKnownItem: knownItem,
      isKnownEnchantment: knownEnchantment,
    );

    test('keeps good kits and normalises item keys', () {
      final report = validate([
        const Kit(
          name: 'a',
          icon: 'Diamond',
          items: [
            KitItem(item: 'Bread', count: 3),
            KitItem(
              item: 'diamond_pickaxe',
              enchantments: {'minecraft:Efficiency': 2},
            ),
          ],
        ),
      ]);
      expect(report.problems, isEmpty);
      final kit = report.kits.single;
      expect(kit.icon, 'minecraft:diamond');
      expect(kit.items.first.item, 'minecraft:bread');
      expect(kit.items.last.enchantments, {'efficiency': 2});
      expect(kit.permission, 'commons:kits.kit.a');
    });

    test('drops a kit with a bad item instead of giving less', () {
      final report = validate([
        const Kit(
          name: 'a',
          items: [
            KitItem(item: 'bread'),
            KitItem(item: 'unobtainium'),
          ],
        ),
        const Kit(
          name: 'b',
          items: [KitItem(item: 'bread')],
        ),
      ]);
      expect(report.kits.map((k) => k.name), ['b']);
      expect(report.problems.single, contains('unobtainium'));
    });

    test('checks names, numbers, enchantments and emptiness', () {
      final report = validate([
        const Kit(
          name: 'Bad Name',
          items: [KitItem(item: 'bread')],
        ),
        const Kit(
          name: 'dup',
          items: [KitItem(item: 'bread')],
        ),
        const Kit(
          name: 'dup',
          items: [KitItem(item: 'bread')],
        ),
        const Kit(name: 'empty'),
        const Kit(
          name: 'neg',
          cooldownSeconds: -1,
          items: [KitItem(item: 'bread')],
        ),
        const Kit(
          name: 'cheap',
          price: -5,
          items: [KitItem(item: 'bread')],
        ),
        const Kit(
          name: 'zero',
          items: [KitItem(item: 'bread', count: 0)],
        ),
        const Kit(
          name: 'ench',
          items: [
            KitItem(item: 'diamond_pickaxe', enchantments: {'luck': 1}),
          ],
        ),
        const Kit(
          name: 'level',
          items: [
            KitItem(item: 'diamond_pickaxe', enchantments: {'efficiency': 0}),
          ],
        ),
        Kit(
          name: 'huge',
          items: [for (var i = 0; i < 37; i++) const KitItem(item: 'bread')],
        ),
      ]);
      expect(report.kits.map((k) => k.name), ['dup']);
      expect(report.problems, hasLength(9));
    });

    test('replaces an unknown icon', () {
      final report = validate([
        const Kit(
          name: 'a',
          icon: 'nope',
          items: [KitItem(item: 'bread')],
        ),
      ]);
      expect(report.kits.single.icon, 'minecraft:chest');
      expect(report.problems, hasLength(1));
    });
  });

  group('defaults', () {
    test('are valid when every item and enchantment exists', () {
      final report = validateKits(
        defaultKits(),
        isKnownItem: (_) => true,
        isKnownEnchantment: (_) => true,
      );
      expect(report.problems, isEmpty);
      expect(report.kits.map((k) => k.name), ['starter', 'daily', 'vip']);
    });

    test('starter is one-time, daily repeats every day, vip is restricted', () {
      final kits = {for (final k in defaultKits().kits) k.name: k};
      expect(kits['starter']!.oneTime, isTrue);
      expect(kits['daily']!.cooldown, const Duration(days: 1));
      expect(kits['vip']!.restricted, isTrue);
      expect(kitNode(kits['vip']!).defaultFor.name, 'op');
      expect(kitNode(kits['daily']!).defaultFor.name, 'everyone');
    });

    test('survive a JSON round trip', () {
      expect(KitCatalogMapper.fromJson(defaultKits().toJson()), defaultKits());
    });
  });

  group('KitService', () {
    late MemoryBackend backend;
    late Documents docs;
    late FakeClock clock;
    late FakeEconomy economy;
    late KitService kits;
    late FakeRecipient steve;

    KitService build({KitCatalog? catalog, KitsConfig? config}) {
      docs = Documents(backend, clock: clock);
      return KitService(
        economy: economy,
        clock: clock,
        catalog: docs.open(
          kitsPath,
          decode: KitCatalogMapper.fromJson,
          encode: (v) => v.toJson(),
          create: () =>
              catalog ??
              const KitCatalog(
                kits: [
                  Kit(
                    name: 'starter',
                    oneTime: true,
                    items: [
                      KitItem(item: 'stone_sword'),
                      KitItem(item: 'bread', count: 8),
                    ],
                  ),
                  Kit(
                    name: 'daily',
                    cooldownSeconds: 3600,
                    items: [KitItem(item: 'bread', count: 16)],
                  ),
                  Kit(
                    name: 'vip',
                    restricted: true,
                    items: [KitItem(item: 'diamond', count: 8)],
                  ),
                  Kit(
                    name: 'paid',
                    price: 100,
                    cooldownSeconds: 60,
                    items: [KitItem(item: 'diamond')],
                  ),
                  Kit(
                    name: 'free',
                    items: [KitItem(item: 'bread')],
                  ),
                ],
              ),
        ),
        config: docs.open(
          configPath,
          decode: KitsConfigMapper.fromJson,
          encode: (v) => v.toJson(),
          create: () => config ?? const KitsConfig(),
        ),
        claims: docs.open(
          claimsPath,
          decode: KitClaimsMapper.fromJson,
          encode: (v) => v.toJson(),
          create: KitClaims.new,
        ),
        isKnownItem: knownItem,
        isKnownEnchantment: knownEnchantment,
      );
    }

    // Everyone may claim the kits that are not restricted, like the real
    // permission defaults.
    FakeRecipient player(String uuid, {Set<String> extra = const {}}) =>
        FakeRecipient(
          uuid,
          'P$uuid',
          permissions: {
            _node('starter'),
            _node('daily'),
            _node('paid'),
            _node('free'),
            KitPerms.use.node,
            ...extra,
          },
        );

    setUp(() {
      backend = MemoryBackend();
      clock = FakeClock();
      economy = FakeEconomy()..balances['u1'] = 500;
      kits = build();
      steve = player('u1');
    });

    test('looks kits up ignoring case', () {
      expect(kits.kit('STARTER')!.name, 'starter');
      expect(kits.kit('nope'), isNull);
      expect(kits.kits.map((k) => k.name), [
        'starter',
        'daily',
        'vip',
        'paid',
        'free',
      ]);
    });

    group('one-time kits', () {
      test('can be claimed once, ever', () {
        expect(kits.claim(steve, 'starter').isOk, isTrue);
        expect(steve.received.single, hasLength(2));
        clock.advance(const Duration(days: 365));
        final again = kits.claim(steve, 'starter');
        expect(again.failure, ClaimFailure.alreadyClaimed);
        expect(steve.received, hasLength(1));
      });

      test('are per player', () {
        kits.claim(steve, 'starter');
        expect(kits.claim(player('u2'), 'starter').isOk, isTrue);
      });
    });

    group('cooldowns', () {
      test('block until they run out, across clock advances', () {
        expect(kits.claim(steve, 'daily').isOk, isTrue);

        clock.advance(const Duration(minutes: 20));
        var r = kits.claim(steve, 'daily');
        expect(r.failure, ClaimFailure.onCooldown);
        expect(r.remaining, const Duration(minutes: 40));

        clock.advance(const Duration(minutes: 39, seconds: 59));
        r = kits.claim(steve, 'daily');
        expect(r.failure, ClaimFailure.onCooldown);
        expect(r.remaining, const Duration(seconds: 1));

        clock.advance(const Duration(seconds: 1));
        expect(kits.claim(steve, 'daily').isOk, isTrue);
        expect(kits.claimOf('u1', 'daily')!.count, 2);
        expect(steve.received, hasLength(2));
      });

      test('a failed claim does not restart the cooldown', () {
        kits.claim(steve, 'daily');
        clock.advance(const Duration(minutes: 30));
        kits.claim(steve, 'daily');
        clock.advance(const Duration(minutes: 30));
        expect(kits.claim(steve, 'daily').isOk, isTrue);
      });

      test('a kit without cooldown can be claimed again and again', () {
        expect(kits.claim(steve, 'free').isOk, isTrue);
        expect(kits.claim(steve, 'free').isOk, isTrue);
      });

      test('a clock that went back does not lock a player out for longer', () {
        kits.claim(steve, 'daily');
        clock.advance(const Duration(days: -2));
        final r = kits.claim(steve, 'daily');
        expect(r.failure, ClaimFailure.onCooldown);
        expect(r.remaining, const Duration(hours: 1));
      });
    });

    group('permissions', () {
      test('a restricted kit needs its node', () {
        expect(kits.claim(steve, 'vip').failure, ClaimFailure.noPermission);
        final vip = player('u3', extra: {_node('vip')});
        expect(kits.claim(vip, 'vip').isOk, isTrue);
      });

      test('the status says locked', () {
        final vip = kits.kit('vip')!;
        expect(
          kits.status('u1', vip, steve.hasPermission).state,
          KitState.locked,
        );
      });

      test('bypass ignores cooldowns and the one-time limit', () {
        final admin = player('u4', extra: {KitPerms.bypass.node});
        expect(kits.claim(admin, 'starter').isOk, isTrue);
        expect(kits.claim(admin, 'starter').isOk, isTrue);
        expect(kits.claim(admin, 'daily').isOk, isTrue);
        expect(kits.claim(admin, 'daily').isOk, isTrue);
        // The permission of the kit itself still counts.
        expect(kits.claim(admin, 'vip').failure, ClaimFailure.noPermission);
      });
    });

    group('price', () {
      test('is charged on a successful claim', () {
        final r = kits.claim(steve, 'paid');
        expect(r.isOk, isTrue);
        expect(r.charged, 100);
        expect(r.balance, 400);
        expect(economy.balance('u1'), 400);
      });

      test('a player who cannot pay gets nothing and no cooldown', () {
        economy.balances['u1'] = 30;
        final r = kits.claim(steve, 'paid');
        expect(r.failure, ClaimFailure.insufficientFunds);
        expect(r.missing, 70);
        expect(steve.received, isEmpty);
        expect(kits.claimOf('u1', 'paid'), isNull);
        economy.balances['u1'] = 100;
        expect(kits.claim(steve, 'paid').isOk, isTrue);
        expect(economy.balance('u1'), 0);
      });

      test('free kits never touch the economy', () {
        kits.claim(steve, 'free');
        expect(economy.log, isEmpty);
      });

      test('the cooldown is checked before anything is charged', () {
        kits.claim(steve, 'paid');
        final r = kits.claim(steve, 'paid');
        expect(r.failure, ClaimFailure.onCooldown);
        expect(economy.balance('u1'), 400);
      });
    });

    group('never half-applies', () {
      test('a full inventory charges nothing and records nothing', () {
        steve.slots = 0;
        final r = kits.claim(steve, 'paid');
        expect(r.failure, ClaimFailure.noSpace);
        expect(economy.balance('u1'), 500);
        expect(economy.log, isEmpty);
        expect(kits.claimOf('u1', 'paid'), isNull);
      });

      test('a failing hand-over refunds the price and records nothing', () {
        steve.giveThrows = true;
        final warnings = <String>[];
        kits = KitService(
          economy: economy,
          clock: clock,
          catalog: docs.open(
            'k2.json',
            decode: KitCatalogMapper.fromJson,
            encode: (v) => v.toJson(),
            create: () => const KitCatalog(
              kits: [
                Kit(
                  name: 'paid',
                  price: 100,
                  items: [KitItem(item: 'diamond')],
                ),
              ],
            ),
          ),
          config: docs.open(
            'c2.json',
            decode: KitsConfigMapper.fromJson,
            encode: (v) => v.toJson(),
            create: KitsConfig.new,
          ),
          claims: docs.open(
            'cl2.json',
            decode: KitClaimsMapper.fromJson,
            encode: (v) => v.toJson(),
            create: KitClaims.new,
          ),
          isKnownItem: knownItem,
          isKnownEnchantment: knownEnchantment,
          warn: warnings.add,
        );
        final r = kits.claim(steve, 'paid');
        expect(r.failure, ClaimFailure.deliveryFailed);
        expect(economy.balance('u1'), 500);
        expect(kits.claimOf('u1', 'paid'), isNull);
        expect(warnings, hasLength(1));
        // The player can simply try again.
        steve.giveThrows = false;
        expect(kits.claim(steve, 'paid').isOk, isTrue);
      });

      test('an unknown kit fails cleanly', () {
        final r = kits.claim(steve, 'nope');
        expect(r.failure, ClaimFailure.unknownKit);
        expect(r.requested, 'nope');
      });
    });

    group('claims', () {
      test('are saved right away and survive a restart', () {
        kits.claim(steve, 'starter');
        clock.advance(const Duration(minutes: 5));
        kits.claim(steve, 'daily');

        // No saveDirty: claims are written immediately.
        final reloaded = build();
        expect(reloaded.hasClaimed('u1', 'starter'), isTrue);
        expect(reloaded.claimOf('u1', 'daily')!.count, 1);
        expect(reloaded.claimOf('u1', 'daily')!.lastClaimed, clock.now());
        final fresh = player('u1');
        expect(
          reloaded.claim(fresh, 'starter').failure,
          ClaimFailure.alreadyClaimed,
        );
        expect(reloaded.claim(fresh, 'daily').failure, ClaimFailure.onCooldown);
      });

      test('the file has the documented shape', () {
        kits.claim(steve, 'starter');
        final decoded = KitClaimsMapper.fromJson(backend.files[claimsPath]!);
        expect(decoded.players['u1']!['starter']!.count, 1);
      });

      test('are kept when a kit is deleted and created again', () {
        kits.claim(steve, 'starter');
        kits.deleteKit('starter');
        kits.createKit('starter', [const KitItem(item: 'bread')]);
        // Re-created kits are plain (not one-time), but the history stays.
        expect(kits.hasClaimed('u1', 'starter'), isTrue);
      });
    });

    group('first join', () {
      test('gives the starter kit to a new player once', () {
        final r = kits.grantStarterKit(steve, isNewPlayer: true);
        expect(r!.isOk, isTrue);
        expect(kits.grantStarterKit(steve, isNewPlayer: true), isNull);
        expect(steve.received, hasLength(1));
      });

      test('not to a returning player', () {
        expect(kits.grantStarterKit(steve, isNewPlayer: false), isNull);
        expect(steve.received, isEmpty);
      });

      test('can be switched off', () {
        kits = build(config: const KitsConfig(giveStarterKit: false));
        expect(kits.grantStarterKit(steve, isNewPlayer: true), isNull);
      });

      test('does nothing for a missing or paid starter kit', () {
        kits = build(config: const KitsConfig(starterKit: 'ghost'));
        expect(kits.grantStarterKit(steve, isNewPlayer: true), isNull);
        kits = build(config: const KitsConfig(starterKit: 'paid'));
        expect(kits.grantStarterKit(steve, isNewPlayer: true), isNull);
        expect(economy.balance('u1'), 500);
      });

      test('a full inventory leaves the kit claimable later', () {
        steve.slots = 0;
        expect(
          kits.grantStarterKit(steve, isNewPlayer: true)!.failure,
          ClaimFailure.noSpace,
        );
        steve.slots = 36;
        expect(kits.claim(steve, 'starter').isOk, isTrue);
      });
    });

    group('admin', () {
      test('createKit adds a kit and saves the file', () {
        final replaced = kits.createKit('Tools', [
          const KitItem(
            item: 'diamond_pickaxe',
            enchantments: {'efficiency': 3},
          ),
        ]);
        expect(replaced, isFalse);
        expect(
          kits.kit('tools')!.items.single.item,
          'minecraft:diamond_pickaxe',
        );
        expect(
          KitCatalogMapper.fromJson(backend.files[kitsPath]!).kits.last.name,
          'tools',
        );
      });

      test('createKit replaces the items and keeps the settings', () {
        final replaced = kits.createKit('daily', [
          const KitItem(item: 'diamond'),
        ]);
        expect(replaced, isTrue);
        final daily = kits.kit('daily')!;
        expect(daily.items.single.item, 'minecraft:diamond');
        expect(daily.cooldownSeconds, 3600);
      });

      test('createKit validates', () {
        expect(
          () => kits.createKit('bad name', [const KitItem(item: 'bread')]),
          throwsA(isA<KitException>()),
        );
        expect(
          () => kits.createKit('empty', const []),
          throwsA(isA<KitException>()),
        );
        expect(
          () => kits.createKit('x', [const KitItem(item: 'nonsense')]),
          throwsA(isA<KitException>()),
        );
      });

      test('deleteKit', () {
        kits.deleteKit('free');
        expect(kits.kit('free'), isNull);
        expect(() => kits.deleteKit('free'), throwsA(isA<KitException>()));
      });

      test('reload picks up edits and keeps the old kits on a broken file', () {
        backend.files[kitsPath] = const KitCatalog(
          kits: [
            Kit(
              name: 'only',
              items: [KitItem(item: 'bread')],
            ),
            Kit(
              name: 'broken',
              items: [KitItem(item: 'nonsense')],
            ),
          ],
        ).toJson();
        final report = kits.reload(backend);
        expect(report.ok, isTrue);
        expect(report.kits, 1);
        expect(report.problems, hasLength(1));
        expect(kits.kits.single.name, 'only');

        backend.files[kitsPath] = '{nope';
        final bad = kits.reload(backend);
        expect(bad.ok, isFalse);
        expect(kits.kits.single.name, 'only');
      });
    });
  });

  group('KitTexts', () {
    final texts = KitTexts(
      MessageCatalog(kitMessageDefaults),
      FakeEconomy(),
      () => '[Kits] ',
    );
    const kit = Kit(
      name: 'daily',
      displayName: '&eDaily',
      price: 50,
      cooldownSeconds: 3600,
      items: [
        KitItem(item: 'bread', count: 16),
        KitItem(item: 'diamond_pickaxe', name: '&bPick'),
      ],
    );

    test('describes every failure without leftover placeholders', () {
      for (final failure in ClaimFailure.values) {
        final text = texts.claim(
          ClaimResult.failed(
            failure,
            kit: kit,
            remaining: const Duration(minutes: 90),
            missing: 7,
            requested: 'x',
          ),
        );
        expect(text, startsWith('[Kits] '), reason: '$failure');
        expect(text, isNot(contains('{')), reason: '$failure');
      }
    });

    test('formats the cooldown with formatDuration', () {
      final text = texts.claim(
        const ClaimResult.failed(
          ClaimFailure.onCooldown,
          kit: kit,
          remaining: Duration(hours: 1, minutes: 30),
        ),
      );
      expect(text, contains('1h 30m'));
    });

    test('a paid claim mentions the price and the balance', () {
      final text = texts.claim(
        const ClaimResult.ok(kit, charged: 50, balance: 450),
      );
      expect(text, contains('50 coins'));
      expect(text, contains('450 coins'));
    });

    test('lore lists the state, price and items', () {
      final lore = texts.kitLore(
        kit,
        const KitStatus(KitState.cooldown, Duration(minutes: 5)),
        canAfford: false,
      );
      final joined = lore.join('\n');
      expect(joined, contains('5m'));
      expect(joined, contains('50 coins'));
      expect(joined, contains('16x Bread'));
      expect(joined, contains('1x Pick'));
      expect(joined, isNot(contains('Left click'))); // can not claim now
      expect(joined, contains('Right click'));
    });

    test('lore of an available kit offers the claim and warns when poor', () {
      final lore = texts
          .kitLore(kit, const KitStatus(KitState.available), canAfford: false)
          .join('\n');
      expect(lore, contains('Left click'));
      expect(lore, contains('can not afford'));
    });

    test('lore cuts long item lists', () {
      final big = Kit(
        name: 'big',
        items: [for (var i = 0; i < 12; i++) const KitItem(item: 'bread')],
      );
      final lore = texts.kitLore(
        big,
        const KitStatus(KitState.available),
        canAfford: true,
      );
      expect(lore.where((l) => l.contains('Bread')), hasLength(8));
      expect(lore.join('\n'), contains('4 more'));
    });

    test('unknown kit lists the choices', () {
      expect(texts.unknown('foo', ['a', 'b']), contains('a, b'));
      expect(texts.unknown('foo', const []), isNot(contains('Kits:')));
    });

    test('state words for lists', () {
      expect(texts.state(const KitStatus(KitState.locked)), contains('locked'));
      expect(
        texts.state(const KitStatus(KitState.cooldown, Duration(hours: 2))),
        contains('2h'),
      );
    });
  });
}
