import 'dart:convert';

import 'package:commons/src/core/api.dart';
import 'package:commons/src/core/clock.dart';
import 'package:commons/src/core/players.dart';
import 'package:commons/src/core/storage.dart';
import 'package:commons/src/economy/amount.dart';
import 'package:commons/src/economy/model.dart';
import 'package:commons/src/economy/rpc.dart';
import 'package:commons/src/economy/service.dart';
import 'package:test/test.dart';

EconomyService openEconomy(
  Documents docs,
  PlayerDirectory players,
  Clock clock,
  EconomyConfig config,
) => EconomyService(
  accounts: docs.open<Accounts>(
    'economy/accounts.json',
    decode: AccountsMapper.fromJson,
    encode: (v) => v.toJson(),
    create: Accounts.new,
  ),
  history: docs.open<History>(
    'economy/history.json',
    decode: HistoryMapper.fromJson,
    encode: (v) => v.toJson(),
    create: History.new,
  ),
  config: config,
  players: players,
  clock: clock,
);

/// A server with a clock, a disk, three known players (a, b, c) and an economy.
final class World {
  final clock = FakeClock();
  final backend = MemoryBackend();
  final EconomyConfig config;
  late final Documents docs = Documents(backend, clock: clock);
  late final PlayerDirectory players = PlayerDirectory(docs, clock);
  late final EconomyService economy;

  World({this.config = const EconomyConfig()}) {
    for (final (uuid, name) in [('a', 'Alice'), ('b', 'Bob'), ('c', 'Carol')]) {
      players.touch(uuid, name);
    }
    economy = openEconomy(docs, players, clock, config);
  }

  /// A new economy that only knows what was written to disk, like after a
  /// restart.
  EconomyService restart() {
    final fresh = Documents(backend, clock: clock);
    return openEconomy(fresh, PlayerDirectory(fresh, clock), clock, config);
  }
}

Object? replyJson(EconomyReply reply) => jsonDecode(jsonEncode(reply.toMap()));

void main() {
  group('EconomyConfig', () {
    test('has sane defaults', () {
      const config = EconomyConfig();
      expect(config.currencySingular, 'coin');
      expect(config.currencyPlural, 'coins');
      expect(config.startingBalance, 100);
      expect(config.payMinimum, 1);
      expect(config.confirmAbove, 1000);
      expect(config.ipcEnabled, isTrue);
    });

    test('missing keys use the defaults', () {
      final config = EconomyConfigMapper.fromJson('{"startingBalance": 5}');
      expect(config.startingBalance, 5);
      expect(config.currencyPlural, 'coins');
      expect(config.maxBalance, const EconomyConfig().maxBalance);
    });

    test('round trips through JSON', () {
      const config = EconomyConfig(
        currencySingular: 'gem',
        currencyPlural: 'gems',
        symbol: 'G',
        startingBalance: 7,
        payMinimum: 3,
        confirmAbove: 0,
        confirmSeconds: 30,
        maxBalance: 999,
        historyPerAccount: 4,
        ipcEnabled: false,
      );
      expect(EconomyConfigMapper.fromJson(config.toJson()), config);
    });

    test('sanitized repairs nonsense', () {
      final fixed = const EconomyConfig(
        currencySingular: ' ',
        currencyPlural: '',
        startingBalance: -5,
        payMinimum: 0,
        confirmAbove: -1,
        confirmSeconds: 0,
        maxBalance: -10,
        historyPerAccount: 9999,
      ).sanitized();
      expect(fixed.currencySingular, 'coin');
      expect(fixed.currencyPlural, 'coins');
      expect(fixed.maxBalance, 1);
      expect(fixed.startingBalance, 0);
      expect(fixed.payMinimum, 1);
      expect(fixed.confirmAbove, 0);
      expect(fixed.confirmSeconds, 1);
      expect(fixed.historyPerAccount, 500);
    });

    test('sanitized caps the maximum balance and fits the start into it', () {
      final capped = const EconomyConfig(
        maxBalance: 1 << 62,
        startingBalance: 1 << 61,
      ).sanitized();
      expect(capped.maxBalance, maxSupportedBalance);
      expect(capped.startingBalance, maxSupportedBalance);
      final small = const EconomyConfig(
        maxBalance: 50,
        startingBalance: 80,
      ).sanitized();
      expect(small.startingBalance, 50);
    });
  });

  group('amounts', () {
    test('parses plain numbers, separators and suffixes', () {
      expect(parseAmount('0'), 0);
      expect(parseAmount('250'), 250);
      expect(parseAmount('1,500'), 1500);
      expect(parseAmount(' 12 '), 12);
      expect(parseAmount('2k'), 2000);
      expect(parseAmount('1.5K'), 1500);
      expect(parseAmount('1.5m'), 1500000);
      expect(parseAmount('3b'), 3000000000);
      expect(parseAmount('2t'), 2000000000000);
      expect(parseAmount('1.250k'), 1250);
      expect(parseAmount('1.2500k'), 1250);
    });

    test('rejects anything that is not an exact whole amount', () {
      for (final bad in [
        '',
        'abc',
        '1.5',
        '1.0005k',
        '1e3',
        '--1',
        '1 000',
        '1k2',
        '.5k',
      ]) {
        expect(
          () => parseAmount(bad),
          throwsA(isA<AmountException>()),
          reason: bad,
        );
      }
      expect(
        () => parseAmount('-5'),
        throwsA(
          isA<AmountException>().having(
            (e) => e.message,
            'message',
            contains('positive'),
          ),
        ),
      );
    });

    test('rejects amounts that are too large instead of overflowing', () {
      expect(parseAmount('$maxSupportedBalance'), maxSupportedBalance);
      for (final big in [
        '9007199254740992',
        '99999999999999999999999',
        '9999999999t',
        '9223372036854775808',
      ]) {
        expect(
          () => parseAmount(big),
          throwsA(isA<AmountException>()),
          reason: big,
        );
      }
    });

    test('groups digits', () {
      expect(groupDigits(0), '0');
      expect(groupDigits(999), '999');
      expect(groupDigits(1000), '1,000');
      expect(groupDigits(1234567), '1,234,567');
      expect(groupDigits(-1234), '-1,234');
    });
  });

  group('formatting', () {
    test('uses the singular for one and the plural otherwise', () {
      final economy = World().economy;
      expect(economy.format(1), '1 coin');
      expect(economy.format(0), '0 coins');
      expect(economy.format(1250), '1,250 coins');
      expect(economy.currencyName, 'coins');
      expect(economy.formatChange(50), '+50 coins');
      expect(economy.formatChange(-1), '-1 coin');
    });

    test('a symbol replaces the name', () {
      final economy = World(config: const EconomyConfig(symbol: r'$')).economy;
      expect(economy.format(1250), r'$1,250');
      expect(economy.formatChange(-5), r'-$5');
    });
  });

  group('accounts', () {
    test('a known player without an account has the starting balance', () {
      final economy = World().economy;
      expect(economy.hasAccount('a'), isFalse);
      expect(economy.balance('a'), 100);
      expect(economy.canAfford('a', 100), isTrue);
      expect(economy.canAfford('a', 101), isFalse);
    });

    test('an unknown player has nothing and cannot be used', () {
      final economy = World().economy;
      expect(economy.balance('ghost'), 0);
      expect(economy.canAfford('ghost', 1), isFalse);
      expect(
        economy.deposit('ghost', 5).failure,
        TransactionFailure.unknownAccount,
      );
      expect(
        economy.withdraw('ghost', 5).failure,
        TransactionFailure.unknownAccount,
      );
      expect(
        economy.transfer('a', 'ghost', 5).failure,
        TransactionFailure.unknownAccount,
      );
      expect(
        economy.transfer('ghost', 'a', 5).failure,
        TransactionFailure.unknownAccount,
      );
      expect(
        economy.set('ghost', 5).failure,
        TransactionFailure.unknownAccount,
      );
      expect(economy.hasAccount('ghost'), isFalse);
      expect(economy.balance('a'), 100);
    });

    test('ensureAccount opens the account once, with a history line', () {
      final economy = World().economy;
      expect(economy.ensureAccount('a'), isTrue);
      expect(economy.ensureAccount('a'), isFalse);
      expect(economy.hasAccount('a'), isTrue);
      expect(economy.balance('a'), 100);
      final history = economy.history('a');
      expect(history, hasLength(1));
      expect(history.single.reason, 'Starting balance');
      expect(history.single.balance, 100);
    });

    test('the first money movement opens the account with the start', () {
      final economy = World().economy;
      final result = economy.deposit('b', 50);
      expect(result.isOk, isTrue);
      expect(result.balance, 150);
      expect(economy.history('b').map((e) => e.balance), [150, 100]);
      expect(economy.history('b').map((e) => e.change), [50, 100]);
    });

    test('a zero starting balance works', () {
      final economy = World(config: const EconomyConfig(startingBalance: 0))
          .economy;
      expect(economy.balance('a'), 0);
      expect(
        economy.withdraw('a', 1).failure,
        TransactionFailure.insufficientFunds,
      );
      expect(economy.deposit('a', 7).balance, 7);
    });
  });

  group('deposit and withdraw', () {
    test('move the balance and report it', () {
      final economy = World().economy;
      expect(economy.deposit('a', 25).balance, 125);
      expect(economy.withdraw('a', 100).balance, 25);
      expect(economy.balance('a'), 25);
      expect(economy.withdraw('a', 25).balance, 0);
      expect(economy.balance('a'), 0);
    });

    test('zero and negative amounts are invalid and change nothing', () {
      final economy = World().economy;
      for (final amount in [0, -1, -1000000000000]) {
        expect(
          economy.deposit('a', amount).failure,
          TransactionFailure.invalidAmount,
        );
        expect(
          economy.withdraw('a', amount).failure,
          TransactionFailure.invalidAmount,
        );
        expect(
          economy.transfer('a', 'b', amount).failure,
          TransactionFailure.invalidAmount,
        );
      }
      expect(economy.hasAccount('a'), isFalse);
      expect(economy.balance('a'), 100);
      expect(economy.canAfford('a', 0), isFalse);
      expect(economy.canAfford('a', -5), isFalse);
    });

    test('cannot withdraw more than the balance', () {
      final economy = World().economy;
      final result = economy.withdraw('a', 101);
      expect(result.failure, TransactionFailure.insufficientFunds);
      expect(result.balance, 100);
      expect(
        economy.hasAccount('a'),
        isFalse,
        reason: 'a failed call opens no account',
      );
    });

    test('a deposit cannot exceed the maximum balance', () {
      final economy = World(config: const EconomyConfig(maxBalance: 500))
          .economy;
      expect(economy.deposit('a', 400).balance, 500);
      final result = economy.deposit('a', 1);
      expect(result.failure, TransactionFailure.invalidAmount);
      expect(result.balance, 500);
      expect(economy.canHold('a', 1), isFalse);
      expect(economy.canHold('b', 400), isTrue);
    });

    test('huge amounts neither overflow nor wrap around', () {
      final economy = World().economy;
      const huge = 9223372036854775807; // the largest int
      expect(
        economy.deposit('a', huge).failure,
        TransactionFailure.invalidAmount,
      );
      expect(
        economy.withdraw('a', huge).failure,
        TransactionFailure.insufficientFunds,
      );
      expect(
        economy.transfer('a', 'b', huge).failure,
        TransactionFailure.insufficientFunds,
      );
      expect(economy.set('a', huge).failure, TransactionFailure.invalidAmount);

      final rich = World(
        config: const EconomyConfig(
          maxBalance: maxSupportedBalance,
          startingBalance: maxSupportedBalance,
        ),
      ).economy;
      expect(rich.deposit('a', huge).failure, TransactionFailure.invalidAmount);
      expect(rich.deposit('a', 1).failure, TransactionFailure.invalidAmount);
      expect(rich.balance('a'), maxSupportedBalance);
      expect(
        rich.transfer('b', 'a', maxSupportedBalance).failure,
        TransactionFailure.invalidAmount,
      );
      expect(rich.balance('b'), maxSupportedBalance);
    });

    test('an account above a lowered maximum can spend but not receive', () {
      final world = World(
        config: const EconomyConfig(maxBalance: 50, startingBalance: 10),
      );
      world.backend.files['economy/accounts.json'] = '{"balances":{"a":900}}';
      final economy = world.restart();
      expect(economy.balance('a'), 900);
      expect(economy.deposit('a', 1).failure, TransactionFailure.invalidAmount);
      expect(economy.withdraw('a', 899).balance, 1);
    });
  });

  group('transfer', () {
    test('moves exactly the amount between two accounts', () {
      final economy = World().economy;
      final result = economy.transfer('a', 'b', 30, reason: 'rent');
      expect(result.isOk, isTrue);
      expect(result.balance, 70);
      expect(economy.balance('a'), 70);
      expect(economy.balance('b'), 130);
      expect(economy.totalSupply, 200);
    });

    test('everything can be sent, and money is conserved', () {
      final economy = World().economy;
      economy.transfer('a', 'b', 100);
      expect(economy.balance('a'), 0);
      expect(economy.balance('b'), 200);
      economy.transfer('b', 'a', 200);
      expect(economy.balance('a'), 200);
      expect(economy.balance('b'), 0);
    });

    test('insufficient funds change nothing at all', () {
      final world = World();
      final economy = world.economy
        ..ensureAccount('a')
        ..ensureAccount('b');
      world.docs.saveDirty();
      final before = Map.of(world.backend.files);
      final result = economy.transfer('a', 'b', 101);
      expect(result.failure, TransactionFailure.insufficientFunds);
      expect(result.balance, 100);
      expect(economy.balance('a'), 100);
      expect(economy.balance('b'), 100);
      expect(
        world.docs.dirtyCount,
        0,
        reason: 'a failed transfer writes nothing',
      );
      expect(world.backend.files, before);
    });

    test('a receiver that cannot hold it fails the whole transfer', () {
      final economy = World(config: const EconomyConfig(maxBalance: 120))
          .economy;
      final result = economy.transfer('a', 'b', 30);
      expect(result.failure, TransactionFailure.invalidAmount);
      expect(economy.balance('a'), 100);
      expect(economy.balance('b'), 100);
      expect(economy.hasAccount('a'), isFalse);
      expect(economy.transfer('a', 'b', 20).isOk, isTrue);
    });

    test('paying yourself is rejected', () {
      final economy = World().economy;
      final result = economy.transfer('a', 'a', 10);
      expect(result.failure, TransactionFailure.invalidAmount);
      expect(economy.balance('a'), 100);
    });

    test('opens missing accounts of both sides', () {
      final economy = World().economy..transfer('a', 'b', 1);
      expect(economy.hasAccount('a'), isTrue);
      expect(economy.hasAccount('b'), isTrue);
    });

    test(
      'is written to disk immediately, without waiting for the autosave',
      () {
        final world = World();
        world.economy.transfer('a', 'b', 40);
        final restarted = world.restart();
        expect(restarted.balance('a'), 60);
        expect(restarted.balance('b'), 140);
      },
    );

    test('every single change survives a restart', () {
      final world = World();
      world.economy.deposit('a', 5);
      expect(world.restart().balance('a'), 105);
      world.economy.withdraw('a', 5);
      expect(world.restart().balance('a'), 100);
      world.economy.set('c', 9);
      expect(world.restart().balance('c'), 9);
      world.economy.ensureAccount('b');
      expect(world.restart().hasAccount('b'), isTrue);
    });
  });

  group('set and reset', () {
    test('set accepts zero up to the maximum', () {
      final economy = World(config: const EconomyConfig(maxBalance: 1000))
          .economy;
      expect(economy.set('a', 0).balance, 0);
      expect(economy.balance('a'), 0);
      expect(economy.set('a', 1000).balance, 1000);
      expect(economy.set('a', 1001).failure, TransactionFailure.invalidAmount);
      expect(economy.set('a', -1).failure, TransactionFailure.invalidAmount);
      expect(economy.balance('a'), 1000);
    });

    test(
      'reset gives the starting balance back and says so in the history',
      () {
        final economy = World().economy..deposit('a', 900);
        expect(economy.reset('a').balance, 100);
        final last = economy.history('a').first;
        expect(last.reason, 'Reset');
        expect(last.change, -900);
        expect(last.kind, TransactionKind.set);
      },
    );
  });

  group('history', () {
    test('is newest first and describes both sides of a transfer', () {
      final world = World();
      final economy = world.economy..ensureAccount('a');
      world.clock.advance(const Duration(minutes: 5));
      economy.deposit('a', 10, reason: 'quest');
      world.clock.advance(const Duration(minutes: 5));
      economy.transfer('a', 'b', 30, reason: 'gift');

      final a = economy.history('a');
      expect(a.map((e) => e.kind), [
        TransactionKind.transferOut,
        TransactionKind.deposit,
        TransactionKind.set,
      ]);
      expect(a.first.change, -30);
      expect(a.first.balance, 80);
      expect(a.first.other, 'b');
      expect(a.first.reason, 'gift');
      expect(a.first.at, DateTime.utc(2026, 1, 1, 0, 10));

      final b = economy.history('b');
      expect(b.first.kind, TransactionKind.transferIn);
      expect(b.first.change, 30);
      expect(b.first.other, 'a');
      expect(economy.history('a', limit: 1), hasLength(1));
    });

    test('is bounded per account', () {
      final economy = World(config: const EconomyConfig(historyPerAccount: 5))
          .economy;
      for (var i = 1; i <= 20; i++) {
        economy.deposit('a', i);
      }
      final history = economy.history('a');
      expect(history, hasLength(5));
      expect(history.first.change, 20, reason: 'keeps the newest');
      expect(history.last.change, 16);
      economy.deposit('b', 1);
      expect(
        economy.history('b'),
        hasLength(2),
        reason: 'others are unaffected',
      );
    });

    test('can be turned off', () {
      final economy = World(
        config: const EconomyConfig(historyPerAccount: 0),
      ).economy..deposit('a', 1);
      expect(economy.history('a'), isEmpty);
      expect(economy.balance('a'), 101);
    });

    test('is saved with the autosave and survives a restart', () {
      final world = World();
      world.economy.deposit('a', 5, reason: 'x');
      world.docs.saveDirty();
      final entry = world.restart().history('a').first;
      expect(entry.reason, 'x');
      expect(entry.at, world.clock.now());
    });
  });

  group('payProblem', () {
    test('reports the first thing that is wrong', () {
      final economy = World(
        config: const EconomyConfig(payMinimum: 10, maxBalance: 500),
      ).economy;
      expect(economy.payProblem('a', 'a', 50), PayProblem.self);
      expect(economy.payProblem('a', 'ghost', 50), PayProblem.unknownRecipient);
      expect(economy.payProblem('a', 'b', 9), PayProblem.belowMinimum);
      expect(economy.payProblem('a', 'b', 0), PayProblem.belowMinimum);
      expect(economy.payProblem('a', 'b', 101), PayProblem.insufficientFunds);
      expect(economy.payProblem('a', 'b', 100), isNull);
      economy.set('b', 450);
      expect(economy.payProblem('a', 'b', 100), PayProblem.recipientFull);
      expect(economy.payProblem('a', 'b', 50), isNull);
    });

    test('confirmation is strictly above the threshold, 0 disables it', () {
      final economy = World().economy;
      expect(economy.needsConfirmation(1000), isFalse);
      expect(economy.needsConfirmation(1001), isTrue);
      final never = World(config: const EconomyConfig(confirmAbove: 0)).economy;
      expect(never.needsConfirmation(1 << 40), isFalse);
    });
  });

  group('leaderboard', () {
    test('orders by balance, then by name, and skips empty accounts', () {
      final economy = World().economy
        ..set('a', 500)
        ..set('b', 900)
        ..set('c', 500);
      final board = economy.leaderboard();
      expect(board.map((e) => e.name), ['Bob', 'Alice', 'Carol']);
      expect(board.map((e) => e.balance), [900, 500, 500]);
      economy.set('a', 0);
      expect(economy.leaderboard().map((e) => e.name), ['Bob', 'Carol']);
    });

    test('equal names fall back to the uuid, strangers show as their uuid', () {
      final world = World();
      world.backend.files['economy/accounts.json'] =
          '{"balances":{"z":5,"y":5}}';
      final board = world.restart().leaderboard();
      expect(board.map((e) => e.uuid), ['y', 'z']);
      expect(board.map((e) => e.name), ['y', 'z']);
    });

    test('rankOf and totalSupply', () {
      final economy = World().economy
        ..set('a', 10)
        ..set('b', 20);
      expect(economy.rankOf('b'), 1);
      expect(economy.rankOf('a'), 2);
      expect(economy.rankOf('c'), isNull);
      expect(economy.totalSupply, 30);
    });
  });

  group('EconomyRpc', () {
    late World world;
    late EconomyRpc rpc;

    setUp(() {
      world = World();
      rpc = EconomyRpc(world.economy, world.players);
    });

    test('balance by name (any case) and by uuid', () {
      expect(
        rpc.balance('shop', const BalanceQuery(player: 'aLiCe')).balance,
        100,
      );
      expect(
        rpc.balance('shop', const BalanceQuery(player: 'a')).error,
        EconomyErrorCode.unknownPlayer,
      );
      final unknown = rpc.balance(
        'shop',
        const BalanceQuery(player: '12345678-1234-1234-1234-123456789abc'),
      );
      expect(unknown.ok, isFalse);
      expect(unknown.error, EconomyErrorCode.unknownAccount);
      world.economy.deposit('a', 1);
      expect(
        rpc.balance('shop', const BalanceQuery(player: 'ALICE')).formatted,
        '101 coins',
      );
    });

    test('charge and pay move money and tag the history with the plugin', () {
      final charged = rpc.charge(
        'shop',
        const MoneyRequest(player: 'Alice', amount: 40, reason: 'sword'),
      );
      expect(charged.ok, isTrue);
      expect(charged.balance, 60);
      expect(world.economy.history('a').first.reason, 'shop: sword');
      final paid = rpc.pay(
        'quests',
        const MoneyRequest(player: 'Alice', amount: 15),
      );
      expect(paid.balance, 75);
      expect(world.economy.history('a').first.reason, 'quests');
    });

    test('failures say why and change nothing', () {
      final tooMuch = rpc.charge(
        'shop',
        const MoneyRequest(player: 'Alice', amount: 101),
      );
      expect(tooMuch.ok, isFalse);
      expect(tooMuch.error, EconomyErrorCode.insufficientFunds);
      expect(tooMuch.balance, 100);
      expect(
        rpc
            .charge('shop', const MoneyRequest(player: 'Alice', amount: 0))
            .error,
        EconomyErrorCode.invalidAmount,
      );
      expect(
        rpc.pay('shop', const MoneyRequest(player: 'Alice', amount: -4)).error,
        EconomyErrorCode.invalidAmount,
      );
      expect(
        rpc.pay('shop', const MoneyRequest(player: 'Nobody', amount: 4)).error,
        EconomyErrorCode.unknownPlayer,
      );
      expect(world.economy.hasAccount('a'), isFalse);
    });

    test('transfer between players', () {
      final reply = rpc.transfer(
        'bank',
        const TransferRequest(from: 'Alice', to: 'bob', amount: 60),
      );
      expect(reply.ok, isTrue);
      expect(reply.balance, 40);
      expect(world.economy.balance('b'), 160);
      expect(
        rpc
            .transfer(
              'bank',
              const TransferRequest(from: 'Alice', to: 'Alice', amount: 1),
            )
            .error,
        EconomyErrorCode.invalidAmount,
      );
      expect(
        rpc
            .transfer(
              'bank',
              const TransferRequest(from: 'Alice', to: 'x', amount: 1),
            )
            .error,
        EconomyErrorCode.unknownPlayer,
      );
      expect(
        rpc
            .transfer(
              'bank',
              const TransferRequest(from: 'Alice', to: 'Bob', amount: 41),
            )
            .error,
        EconomyErrorCode.insufficientFunds,
      );
    });

    test('can be turned off by the server owner', () {
      final off = EconomyRpc(
        World(config: const EconomyConfig(ipcEnabled: false)).economy,
        world.players,
      );
      const disabled = EconomyErrorCode.disabled;
      expect(
        off.balance('x', const BalanceQuery(player: 'Alice')).error,
        disabled,
      );
      expect(
        off.pay('x', const MoneyRequest(player: 'Alice', amount: 1)).error,
        disabled,
      );
      expect(
        off.charge('x', const MoneyRequest(player: 'Alice', amount: 1)).error,
        disabled,
      );
      expect(
        off
            .transfer(
              'x',
              const TransferRequest(from: 'Alice', to: 'Bob', amount: 1),
            )
            .error,
        disabled,
      );
    });

    test('info describes the currency', () {
      final info = rpc.info();
      expect(info.plural, 'coins');
      expect(info.singular, 'coin');
      expect(info.maxBalance, const EconomyConfig().maxBalance);
    });

    test('payloads round trip through the wire format', () {
      Object? wire(Object? value) => jsonDecode(jsonEncode(value));

      const money = MoneyRequest(player: 'Alice', amount: 5, reason: 'x');
      expect(
        decodePayload(wire(money.toMap()), MoneyRequestMapper.fromMap),
        money,
      );
      const bare = MoneyRequest(player: 'Alice', amount: 5);
      expect(wire(bare.toMap()), {'player': 'Alice', 'amount': 5});
      expect(
        decodePayload(wire(bare.toMap()), MoneyRequestMapper.fromMap),
        bare,
      );
      const transfer = TransferRequest(from: 'a', to: 'b', amount: 1);
      expect(
        decodePayload(wire(transfer.toMap()), TransferRequestMapper.fromMap),
        transfer,
      );
      const query = BalanceQuery(player: 'a');
      expect(
        decodePayload(wire(query.toMap()), BalanceQueryMapper.fromMap),
        query,
      );
    });

    test('replies use stable snake_case error codes', () {
      final failed = rpc.charge(
        'shop',
        const MoneyRequest(player: 'Alice', amount: 500),
      );
      expect(replyJson(failed), {
        'ok': false,
        'error': 'insufficient_funds',
        'balance': 100,
        'formatted': '100 coins',
      });
      final ok = rpc.pay(
        'shop',
        const MoneyRequest(player: 'Alice', amount: 1),
      );
      expect(replyJson(ok), {
        'ok': true,
        'balance': 101,
        'formatted': '101 coins',
      });
      expect(
        EconomyReplyMapper.fromMap(replyJson(ok) as Map<String, dynamic>),
        ok,
      );
      expect(
        replyJson(rpc.balance('x', const BalanceQuery(player: 'nobody'))),
        {'ok': false, 'error': 'unknown_player'},
      );
    });

    test('malformed payloads are rejected', () {
      expect(
        () => decodePayload('nope', MoneyRequestMapper.fromMap),
        throwsFormatException,
      );
      expect(
        () => decodePayload(<String, dynamic>{
          'player': 'x',
        }, MoneyRequestMapper.fromMap),
        throwsA(anything),
      );
      expect(
        () => decodePayload(<String, dynamic>{
          'player': 'x',
          'amount': 'lots',
        }, MoneyRequestMapper.fromMap),
        throwsA(anything),
      );
    });
  });
}
