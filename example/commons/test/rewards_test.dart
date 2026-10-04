import 'package:commons/src/core/api.dart';
import 'package:commons/src/core/clock.dart';
import 'package:commons/src/core/players.dart';
import 'package:commons/src/core/storage.dart';
import 'package:commons/src/rewards/model.dart';
import 'package:commons/src/rewards/playtime.dart';
import 'package:commons/src/rewards/service.dart';
import 'package:test/test.dart';

/// An economy that remembers what it was asked to do. [refuse] makes every
/// deposit fail like a full balance would.
final class FakeEconomy implements Economy {
  final balances = <String, int>{};
  final deposits = <(String, int, String?)>[];
  bool refuse = false;

  @override
  String get currencyName => 'coins';

  @override
  String format(int amount) => '$amount coins';

  @override
  int balance(String uuid) => balances[uuid] ?? 0;

  @override
  bool canAfford(String uuid, int amount) => balance(uuid) >= amount;

  @override
  Transaction deposit(String uuid, int amount, {String? reason}) {
    if (refuse) {
      return Transaction.failed(
        TransactionFailure.invalidAmount,
        balance(uuid),
      );
    }
    deposits.add((uuid, amount, reason));
    return Transaction.ok(balances[uuid] = balance(uuid) + amount);
  }

  @override
  Transaction withdraw(String uuid, int amount, {String? reason}) =>
      throw UnimplementedError();

  @override
  Transaction transfer(String from, String to, int amount, {String? reason}) =>
      throw UnimplementedError();
}

DateTime at(int day, [int hour = 0, int minute = 0, int second = 0]) =>
    DateTime.utc(2026, 1, day, hour, minute, second);

JsonDocument<DailyFile> openDaily(Documents docs) => docs.open<DailyFile>(
  'rewards/daily.json',
  decode: DailyFileMapper.fromJson,
  encode: (v) => v.toJson(),
  create: DailyFile.new,
);

JsonDocument<PlaytimeFile> openPlaytime(Documents docs) =>
    docs.open<PlaytimeFile>(
      'rewards/playtime.json',
      decode: PlaytimeFileMapper.fromJson,
      encode: (v) => v.toJson(),
      create: PlaytimeFile.new,
    );

/// A daily service on an in-memory disk; [restart] reloads it from there.
final class DailyWorld {
  final clock = FakeClock(at(1, 10));
  final backend = MemoryBackend();
  final economy = FakeEconomy();
  final DailyConfig config;
  late DailyService daily;

  DailyWorld({this.config = const DailyConfig()}) {
    daily = restart();
  }

  DailyService restart() => daily = DailyService(
    economy: economy,
    doc: openDaily(Documents(backend, clock: clock)),
    config: config,
    clock: clock,
  );
}

/// A playtime service for players a (Alice), b (Bob) and c (Carol).
final class PlaytimeWorld {
  final clock = FakeClock(at(1));
  final backend = MemoryBackend();
  final economy = FakeEconomy();
  final PlaytimeConfig config;
  late PlaytimeService playtime;

  PlaytimeWorld({this.config = const PlaytimeConfig()}) {
    final docs = Documents(backend, clock: clock);
    final players = PlayerDirectory(docs, clock);
    for (final (uuid, name) in [('a', 'Alice'), ('b', 'Bob'), ('c', 'Carol')]) {
      players.touch(uuid, name);
    }
    docs.saveDirty();
    playtime = restart();
  }

  /// A new service that only knows what reached the disk, like after a crash
  /// and restart.
  PlaytimeService restart() {
    final docs = Documents(backend, clock: clock);
    return playtime = PlaytimeService(
      economy: economy,
      doc: openPlaytime(docs),
      players: PlayerDirectory(docs, clock),
      config: config,
      clock: clock,
    );
  }
}

void main() {
  group('RewardsConfig', () {
    test('has defaults for everything', () {
      const config = RewardsConfig();
      expect(config.daily.enabled, isTrue);
      expect(config.daily.baseAmount, 100);
      expect(config.daily.graceDays, 1);
      expect(config.daily.milestones.map((m) => m.day), [7, 14, 30]);
      expect(config.playtime.tickSeconds, 60);
      expect(config.playtime.milestones.map((m) => m.minutes), [60, 600, 3000]);
    });

    test('a partial file keeps the defaults of what it leaves out', () {
      final config = RewardsConfigMapper.fromJson(
        '{"daily": {"baseAmount": 5}, "playtime": {"tickSeconds": 30}}',
      );
      expect(config.daily.baseAmount, 5);
      expect(config.daily.incrementPerDay, 25);
      expect(config.daily.milestones, hasLength(3));
      expect(config.playtime.tickSeconds, 30);
      expect(config.playtime.milestones, hasLength(3));
      expect(RewardsConfigMapper.fromJson('{}'), const RewardsConfig());
    });

    test('round trips through JSON, milestones and items included', () {
      const config = RewardsConfig(
        daily: DailyConfig(
          enabled: false,
          baseAmount: 1,
          incrementPerDay: 2,
          maxGrowthDays: 3,
          resetHourUtc: 4,
          graceDays: 5,
          joinReminder: false,
          milestones: [
            StreakMilestone(
              day: 2,
              currency: 9,
              items: [ItemReward('apple', count: 4)],
              label: 'Apples',
            ),
          ],
        ),
        playtime: PlaytimeConfig(
          tickSeconds: 10,
          milestones: [PlaytimeMilestone(minutes: 5, currency: 6)],
        ),
      );
      expect(RewardsConfigMapper.fromJson(config.toJson()), config);
    });

    test('sanitized daily config repairs nonsense', () {
      final fixed = const DailyConfig(
        baseAmount: -1,
        incrementPerDay: -1,
        maxGrowthDays: 0,
        resetHourUtc: 99,
        graceDays: -2,
        milestones: [
          StreakMilestone(day: 0, currency: 5),
          StreakMilestone(
            day: 3,
            currency: -5,
            items: [ItemReward('x', count: 0)],
          ),
          StreakMilestone(day: 3, currency: 7),
        ],
      ).sanitized();
      expect(fixed.baseAmount, 0);
      expect(fixed.incrementPerDay, 0);
      expect(fixed.maxGrowthDays, 1);
      expect(fixed.resetHourUtc, 23);
      expect(fixed.graceDays, 0);
      expect(
        fixed.milestones,
        hasLength(1),
        reason: 'day 0 and a repeated day',
      );
      expect(fixed.milestones.single.currency, 0);
      expect(fixed.milestones.single.items, isEmpty);
    });

    test('sanitized playtime config sorts and repairs', () {
      final fixed = const PlaytimeConfig(
        tickSeconds: 0,
        milestones: [
          PlaytimeMilestone(minutes: 100, currency: 1),
          PlaytimeMilestone(minutes: 0, currency: 1),
          PlaytimeMilestone(minutes: 10, currency: -5),
          PlaytimeMilestone(minutes: 10, currency: 3),
        ],
      ).sanitized();
      expect(fixed.tickSeconds, 5);
      expect(fixed.milestones.map((m) => m.minutes), [10, 100]);
      expect(fixed.milestones.first.currency, 0);
    });
  });

  group('daily reward', () {
    test('a new player can claim, and gets the day 1 reward', () {
      final world = DailyWorld();
      final status = world.daily.status('a');
      expect(status.claimable, isTrue);
      expect(status.streak, 0);
      expect(status.nextDay, 1);
      expect(status.nextReward, 100);
      expect(status.lapsed, isFalse);
      expect(world.daily.canClaimDaily('a'), isTrue);

      final result = world.daily.claim('a');
      expect(result.isOk, isTrue);
      expect(result.day, 1);
      expect(result.currency, 100);
      expect(result.balance, 100);
      expect(result.milestone, isNull);
      expect(result.streakWasReset, isFalse);
      expect(world.economy.deposits.single, ('a', 100, 'Daily reward, day 1'));
    });

    test('only once per day, and says how long to wait', () {
      final world = DailyWorld();
      world.daily.claim('a');
      expect(world.daily.canClaimDaily('a'), isFalse);
      final again = world.daily.claim('a');
      expect(again.failure, ClaimFailure.alreadyClaimed);
      expect(again.retryIn, const Duration(hours: 14));
      expect(world.economy.deposits, hasLength(1));
      expect(world.daily.status('a').untilNext, const Duration(hours: 14));

      world.clock.advance(const Duration(hours: 13, minutes: 59, seconds: 59));
      expect(world.daily.claim('a').failure, ClaimFailure.alreadyClaimed);
      expect(world.daily.status('a').untilNext, const Duration(seconds: 1));
    });

    test('a new day starts exactly at the reset hour', () {
      final world = DailyWorld();
      world.clock.set(at(1, 23, 59, 59));
      world.daily.claim('a');
      world.clock.set(at(2, 0, 0, 0));
      final next = world.daily.claim('a');
      expect(next.isOk, isTrue);
      expect(next.day, 2);
    });

    test(
      'claiming early in a day does not allow a second claim late in it',
      () {
        final world = DailyWorld();
        world.clock.set(at(1, 0, 0, 0));
        world.daily.claim('a');
        world.clock.set(at(1, 23, 59, 59));
        expect(world.daily.claim('a').failure, ClaimFailure.alreadyClaimed);
      },
    );

    test('the reset hour shifts the day boundary', () {
      final world = DailyWorld(config: const DailyConfig(resetHourUtc: 6));
      world.clock.set(at(2, 5, 0));
      world.daily.claim('a'); // still "day of Jan 1"
      world.clock.set(at(2, 5, 59, 59));
      expect(world.daily.claim('a').failure, ClaimFailure.alreadyClaimed);
      expect(world.daily.status('a').untilNext, const Duration(seconds: 1));
      world.clock.set(at(2, 6, 0));
      expect(world.daily.claim('a').day, 2);
    });

    test('consecutive days build the streak and grow the reward', () {
      final world = DailyWorld();
      final rewards = <int>[];
      for (var day = 1; day <= 5; day++) {
        world.clock.set(at(day, 12));
        rewards.add(world.daily.claim('a').currency);
      }
      expect(rewards, [100, 125, 150, 175, 200]);
      final status = world.daily.status('a');
      expect(status.streak, 5);
      expect(status.bestStreak, 5);
      expect(status.totalClaims, 5);
    });

    test('the reward stops growing at the cap while the streak goes on', () {
      final world = DailyWorld(
        config: const DailyConfig(
          baseAmount: 10,
          incrementPerDay: 5,
          maxGrowthDays: 3,
          milestones: [],
        ),
      );
      final rewards = <int>[];
      for (var day = 1; day <= 6; day++) {
        world.clock.set(at(day, 8));
        rewards.add(world.daily.claim('a').currency);
      }
      expect(rewards, [10, 15, 20, 20, 20, 20]);
      expect(world.daily.status('a').streak, 6);
      expect(world.daily.rewardFor(1000), 20);
      expect(world.daily.rewardFor(0), 10, reason: 'never below day 1');
    });

    test('skipping a day is forgiven with a grace day', () {
      final world = DailyWorld();
      world.clock.set(at(1, 12));
      world.daily.claim('a');
      world.clock.set(at(3, 12)); // one whole day skipped
      final status = world.daily.status('a');
      expect(status.claimable, isTrue);
      expect(status.streak, 1);
      expect(status.lapsed, isFalse);
      final result = world.daily.claim('a');
      expect(result.day, 2);
      expect(result.streakWasReset, isFalse);
    });

    test('skipping more than the grace days resets the streak', () {
      final world = DailyWorld();
      world.clock.set(at(1, 12));
      world.daily.claim('a');
      world.clock.set(at(2, 12));
      world.daily.claim('a');
      world.clock.set(at(5, 12)); // two whole days skipped
      final status = world.daily.status('a');
      expect(status.claimable, isTrue);
      expect(status.streak, 0);
      expect(status.lapsed, isTrue);
      expect(status.nextReward, 100);
      final result = world.daily.claim('a');
      expect(result.day, 1);
      expect(result.streakWasReset, isTrue);
      expect(result.currency, 100);
      final after = world.daily.status('a');
      expect(after.streak, 1);
      expect(after.bestStreak, 2, reason: 'the best streak is kept');
      expect(after.totalClaims, 3);
    });

    test('without grace days any missed day resets', () {
      final world = DailyWorld(config: const DailyConfig(graceDays: 0));
      world.clock.set(at(1, 12));
      world.daily.claim('a');
      world.clock.set(at(3, 12));
      expect(world.daily.claim('a').day, 1);
      world.clock.set(at(4, 12));
      expect(world.daily.claim('a').day, 2);
    });

    test('a long gap resets, whatever the length', () {
      final world = DailyWorld();
      world.daily.claim('a');
      world.clock.advance(const Duration(days: 400));
      final result = world.daily.claim('a');
      expect(result.day, 1);
      expect(result.streakWasReset, isTrue);
    });

    test('milestones add their bonus money and items on their day only', () {
      final world = DailyWorld();
      final results = <ClaimResult>[];
      for (var day = 1; day <= 8; day++) {
        world.clock.set(at(day, 9));
        results.add(world.daily.claim('a'));
      }
      expect(results[5].milestone, isNull);
      expect(results[5].currency, 100 + 25 * 5);
      final seventh = results[6];
      expect(seventh.day, 7);
      expect(seventh.milestone?.label, 'Weekly bonus');
      expect(seventh.bonus, 500);
      expect(seventh.currency, 250 + 500);
      expect(seventh.items.single.item, 'diamond');
      expect(seventh.items.single.count, 3);
      expect(results[7].milestone, isNull);
      expect(results[7].items, isEmpty);
      expect(world.economy.deposits[6].$3, 'Daily reward, day 7');
    });

    test('a milestone is earned again after the streak was lost', () {
      final world = DailyWorld(
        config: const DailyConfig(
          milestones: [StreakMilestone(day: 2, currency: 1000)],
        ),
      );
      world.clock.set(at(1, 9));
      world.daily.claim('a');
      world.clock.set(at(2, 9));
      expect(world.daily.claim('a').bonus, 1000);
      world.clock.set(at(10, 9));
      world.daily.claim('a'); // streak starts again
      world.clock.set(at(11, 9));
      expect(world.daily.claim('a').bonus, 1000);
    });

    test('milestones are seen in the status before they are claimed', () {
      final world = DailyWorld();
      for (var day = 1; day <= 6; day++) {
        world.clock.set(at(day, 9));
        world.daily.claim('a');
      }
      world.clock.set(at(7, 9));
      expect(world.daily.status('a').nextMilestone?.day, 7);
    });

    test('players are independent', () {
      final world = DailyWorld();
      world.daily.claim('a');
      expect(world.daily.canClaimDaily('a'), isFalse);
      expect(world.daily.canClaimDaily('b'), isTrue);
      expect(world.daily.claim('b').day, 1);
    });

    test('a refused payment claims nothing and can be retried', () {
      final world = DailyWorld();
      world.economy.refuse = true;
      final failed = world.daily.claim('a');
      expect(failed.failure, ClaimFailure.paymentFailed);
      expect(world.daily.canClaimDaily('a'), isTrue);
      expect(world.daily.status('a').totalClaims, 0);
      world.economy.refuse = false;
      expect(world.daily.claim('a').isOk, isTrue);
    });

    test('a reward of zero is claimed without paying', () {
      final world = DailyWorld(
        config: const DailyConfig(
          baseAmount: 0,
          incrementPerDay: 0,
          milestones: [],
        ),
      );
      final result = world.daily.claim('a');
      expect(result.isOk, isTrue);
      expect(result.currency, 0);
      expect(world.economy.deposits, isEmpty);
      expect(world.daily.canClaimDaily('a'), isFalse);
    });

    test('can be switched off', () {
      final world = DailyWorld(config: const DailyConfig(enabled: false));
      expect(world.daily.canClaimDaily('a'), isFalse);
      expect(world.daily.claim('a').failure, ClaimFailure.disabled);
      expect(world.economy.deposits, isEmpty);
    });

    test('a clock that goes backwards never allows a second claim', () {
      final world = DailyWorld();
      world.clock.set(at(5, 12));
      world.daily.claim('a');
      world.clock.set(at(3, 12));
      expect(world.daily.canClaimDaily('a'), isFalse);
      expect(world.daily.claim('a').failure, ClaimFailure.alreadyClaimed);
      expect(world.daily.status('a').streak, 1);
    });

    test('the streak survives a restart', () {
      final world = DailyWorld();
      world.clock.set(at(1, 9));
      world.daily.claim('a');
      world.clock.set(at(2, 9));
      world.daily.claim('a');
      final restarted = world.restart();
      expect(restarted.status('a').streak, 2);
      expect(restarted.canClaimDaily('a'), isFalse);
      world.clock.set(at(3, 9));
      expect(restarted.claim('a').day, 3);
    });

    test('items that did not fit are kept until they are taken', () {
      final world = DailyWorld();
      world.daily.stash('a', [const ItemReward('diamond', count: 2)]);
      world.daily.stash('a', [const ItemReward('emerald')]);
      world.daily.stash('a', const []);
      expect(world.daily.pending('a'), hasLength(2));
      expect(world.daily.pending('b'), isEmpty);

      expect(world.restart().pending('a'), hasLength(2));
      final taken = world.daily.takePending('a');
      expect(taken.map((i) => i.item), ['diamond', 'emerald']);
      expect(world.daily.takePending('a'), isEmpty);
      expect(world.restart().pending('a'), isEmpty);
    });

    test('claiming keeps the pending items and stashing keeps the streak', () {
      final world = DailyWorld();
      world.daily.stash('a', [const ItemReward('diamond')]);
      expect(world.daily.canClaimDaily('a'), isTrue);
      world.daily.claim('a');
      world.daily.stash('a', [const ItemReward('emerald')]);
      expect(world.daily.pending('a'), hasLength(2));
      expect(world.daily.status('a').streak, 1);
      world.daily.takePending('a');
      expect(world.daily.status('a').streak, 1);
      expect(world.daily.status('a').totalClaims, 1);
    });
  });

  group('calendar', () {
    test('a new player has day 1 available and the rest locked', () {
      final world = DailyWorld();
      final days = world.daily.calendar('a', page: 0);
      expect(days, hasLength(calendarPageDays));
      expect(days.first.day, 1);
      expect(days.first.state, CalendarState.available);
      expect(
        days.skip(1).every((d) => d.state == CalendarState.locked),
        isTrue,
      );
      expect(days[6].milestone?.day, 7);
      expect(days[13].milestone?.day, 14);
      expect(days.first.reward, 100);
    });

    test('shows claimed days, then the next one as waiting', () {
      final world = DailyWorld();
      for (var day = 1; day <= 3; day++) {
        world.clock.set(at(day, 9));
        world.daily.claim('a');
      }
      final days = world.daily.calendar('a', page: 0);
      expect(
        days.take(3).every((d) => d.state == CalendarState.claimed),
        isTrue,
      );
      expect(days[3].state, CalendarState.next);
      expect(days[4].state, CalendarState.locked);

      world.clock.set(at(4, 9));
      expect(
        world.daily.calendar('a', page: 0)[3].state,
        CalendarState.available,
      );
    });

    test('a lapsed streak shows nothing as claimed', () {
      final world = DailyWorld();
      world.daily.claim('a');
      world.clock.advance(const Duration(days: 10));
      final days = world.daily.calendar('a', page: 0);
      expect(days.first.state, CalendarState.available);
      expect(days.where((d) => d.state == CalendarState.claimed), isEmpty);
    });

    test('pages follow the streak', () {
      final world = DailyWorld();
      expect(world.daily.currentCalendarPage('a'), 0);
      for (var day = 1; day <= 28; day++) {
        world.clock.set(at(day, 9));
        world.daily.claim('a');
      }
      world.clock.set(at(29, 9));
      expect(world.daily.status('a').nextDay, 29);
      expect(world.daily.currentCalendarPage('a'), 1);
      final second = world.daily.calendar('a', page: 1);
      expect(second.first.day, 29);
      expect(second.first.state, CalendarState.available);
      final first = world.daily.calendar('a', page: 0);
      expect(first.every((d) => d.state == CalendarState.claimed), isTrue);
    });
  });

  group('playtime', () {
    test('adds up the time between join and leave', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 5, seconds: 30));
      world.playtime.leave('a');
      expect(
        world.playtime.playtime('a'),
        const Duration(minutes: 5, seconds: 30),
      );
      expect(world.playtime.isTracking('a'), isFalse);
      world.clock.advance(const Duration(hours: 5));
      expect(
        world.playtime.playtime('a'),
        const Duration(minutes: 5, seconds: 30),
        reason: 'offline time does not count',
      );
    });

    test('counts the running session too', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 2));
      expect(world.playtime.playtime('a'), const Duration(minutes: 2));
      world.playtime.tick(['a']);
      world.clock.advance(const Duration(minutes: 1));
      expect(world.playtime.playtime('a'), const Duration(minutes: 3));
    });

    test('several sessions add up', () {
      final world = PlaytimeWorld();
      for (var i = 0; i < 3; i++) {
        world.playtime.join('a');
        world.clock.advance(const Duration(minutes: 10));
        world.playtime.leave('a');
        world.clock.advance(const Duration(minutes: 30));
      }
      expect(world.playtime.playtime('a'), const Duration(minutes: 30));
    });

    test('joining twice does not restart or double count', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 1));
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 1));
      world.playtime.leave('a');
      expect(world.playtime.playtime('a'), const Duration(minutes: 2));
      world.playtime.leave('a'); // leaving twice is harmless
      expect(world.playtime.playtime('a'), const Duration(minutes: 2));
    });

    test('ticks lose no fractions of a second', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      for (var i = 0; i < 4; i++) {
        world.clock.advance(const Duration(milliseconds: 1500));
        world.playtime.tick(['a']);
      }
      world.playtime.leave('a');
      expect(world.playtime.playtime('a'), const Duration(seconds: 6));
    });

    test('a crash loses at most one tick', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.playtime.join('b');
      for (var i = 0; i < 5; i++) {
        world.clock.advance(const Duration(seconds: 60));
        world.playtime.tick(['a', 'b']);
      }
      world.clock.advance(const Duration(seconds: 45)); // the server dies here
      final recovered = world.restart();
      expect(recovered.playtime('a'), const Duration(minutes: 5));
      expect(recovered.playtime('b'), const Duration(minutes: 5));
      expect(recovered.isTracking('a'), isFalse);
      // Players are tracked again from the first tick after the restart.
      recovered.tick(['a']);
      world.clock.advance(const Duration(seconds: 60));
      recovered.tick(['a']);
      expect(recovered.playtime('a'), const Duration(minutes: 6));
    });

    test('a clean shutdown loses nothing', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.clock.advance(const Duration(seconds: 100));
      final running = world.playtime..flush();
      expect(running.isTracking('a'), isTrue, reason: 'flush keeps tracking');
      expect(world.restart().playtime('a'), const Duration(seconds: 100));
    });

    test('a leave is saved at once', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 7));
      world.playtime.leave('a');
      expect(world.restart().playtime('a'), const Duration(minutes: 7));
    });

    test(
      'tick starts tracking players it has not seen and drops those gone',
      () {
        final world = PlaytimeWorld();
        world.playtime.tick([
          'a',
          'b',
        ]); // the plugin was reloaded with both online
        expect(world.playtime.isTracking('a'), isTrue);
        world.clock.advance(const Duration(minutes: 1));
        world.playtime.tick(['a']); // b left without a leave event
        expect(world.playtime.isTracking('b'), isFalse);
        expect(world.playtime.playtime('a'), const Duration(minutes: 1));
        expect(
          world.playtime.playtime('b'),
          Duration.zero,
          reason: 'nothing is invented for someone who is gone',
        );
        world.clock.advance(const Duration(minutes: 1));
        expect(world.playtime.playtime('b'), Duration.zero);
      },
    );

    test('a clock that goes backwards adds nothing', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 10));
      world.playtime.tick(['a']);
      world.clock.set(at(1)); // back to the start
      world.playtime.tick(['a']);
      world.clock.advance(const Duration(minutes: 1));
      world.playtime.leave('a');
      expect(world.playtime.playtime('a'), const Duration(minutes: 11));
    });

    test('a player who left is not counted by the next tick', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 1));
      world.playtime.leave('a');
      world.clock.advance(const Duration(minutes: 1));
      world.playtime.tick([]);
      expect(world.playtime.playtime('a'), const Duration(minutes: 1));
    });
  });

  group('playtime milestones', () {
    test('are paid once when reached', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 59));
      expect(world.playtime.tick(['a']), isEmpty);
      expect(world.economy.deposits, isEmpty);
      world.clock.advance(const Duration(minutes: 1));
      final payouts = world.playtime.tick(['a']);
      expect(payouts, hasLength(1));
      expect(payouts.single.milestone.minutes, 60);
      expect(payouts.single.balance, 250);
      expect(world.economy.deposits.single, (
        'a',
        250,
        'Playtime reward, 60 minutes',
      ));
      world.clock.advance(const Duration(minutes: 5));
      expect(world.playtime.tick(['a']), isEmpty);
      expect(world.economy.deposits, hasLength(1));
    });

    test('are not paid again after a restart or a rejoin', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 61));
      world.playtime.leave('a');
      expect(world.economy.deposits, hasLength(1));

      final restarted = world.restart();
      restarted.join('a');
      world.clock.advance(const Duration(minutes: 30));
      expect(restarted.tick(['a']), isEmpty);
      restarted.leave('a');
      expect(world.economy.deposits, hasLength(1));
    });

    test('a long absence of ticks pays every milestone passed', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.clock.advance(const Duration(hours: 11));
      final payouts = world.playtime.tick(['a']);
      expect(payouts.map((p) => p.milestone.minutes), [60, 600]);
      expect(world.economy.balance('a'), 250 + 1500);
    });

    test('are tried again later when the payment fails', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 61));
      world.economy.refuse = true;
      expect(world.playtime.tick(['a']), isEmpty);
      expect(world.playtime.playtime('a'), const Duration(minutes: 61));
      world.economy.refuse = false;
      world.clock.advance(const Duration(minutes: 1));
      expect(world.playtime.tick(['a']), hasLength(1));
      expect(world.economy.deposits, hasLength(1));
    });

    test('a milestone without money is still marked reached', () {
      final world = PlaytimeWorld(
        config: const PlaytimeConfig(
          milestones: [PlaytimeMilestone(minutes: 1, currency: 0)],
        ),
      );
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 2));
      expect(world.playtime.tick(['a']), hasLength(1));
      expect(world.playtime.tick(['a']), isEmpty);
      expect(world.economy.deposits, isEmpty);
    });

    test('nextMilestone is the first one not reached', () {
      final world = PlaytimeWorld();
      expect(world.playtime.nextMilestone('a')?.minutes, 60);
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 90));
      world.playtime.tick(['a']);
      expect(world.playtime.nextMilestone('a')?.minutes, 600);
      world.clock.advance(const Duration(hours: 100));
      world.playtime.tick(['a']);
      expect(world.playtime.nextMilestone('a'), isNull);
    });

    test('players are independent', () {
      final world = PlaytimeWorld();
      world.playtime.join('a');
      world.clock.advance(const Duration(minutes: 30));
      world.playtime.join('b');
      world.clock.advance(const Duration(minutes: 30));
      final payouts = world.playtime.tick(['a', 'b']);
      expect(payouts.map((p) => p.uuid), ['a']);
    });
  });

  group('playtime leaderboard', () {
    test('orders by time, then by name', () {
      final world = PlaytimeWorld();
      for (final uuid in ['a', 'b', 'c']) {
        world.playtime.join(uuid);
      }
      world.clock.advance(const Duration(minutes: 10));
      world.playtime.leave('c');
      world.clock.advance(const Duration(minutes: 10));
      world.playtime.leave('b');
      world.playtime.leave('a');
      world.playtime.join('c');
      final board = world.playtime.leaderboard();
      expect(board.map((e) => e.name), ['Alice', 'Bob', 'Carol']);
      expect(board.map((e) => e.time.inMinutes), [20, 20, 10]);
    });

    test('includes the running session and skips players without time', () {
      final world = PlaytimeWorld();
      world.playtime.join('b');
      world.clock.advance(const Duration(minutes: 3));
      world.playtime.join('c');
      final board = world.playtime.leaderboard();
      expect(board.map((e) => e.name), ['Bob']);
    });

    test('shows the uuid of a player the server forgot', () {
      final world = PlaytimeWorld();
      world.backend.files['rewards/playtime.json'] =
          '{"players":{"zzz":{"seconds":90,"paidMilestones":[]}}}';
      final board = world.restart().leaderboard();
      expect(board.single.name, 'zzz');
      expect(board.single.time, const Duration(seconds: 90));
    });
  });

  test('formatPlaytime', () {
    expect(formatPlaytime(Duration.zero), '0s');
    expect(formatPlaytime(const Duration(seconds: 42)), '42s');
    expect(formatPlaytime(const Duration(minutes: 5)), '5m');
    expect(formatPlaytime(const Duration(minutes: 5, seconds: 59)), '5m');
    expect(formatPlaytime(const Duration(hours: 1)), '1h');
    expect(formatPlaytime(const Duration(hours: 2, minutes: 3)), '2h 3m');
    expect(
      formatPlaytime(const Duration(days: 3, hours: 4, minutes: 12)),
      '3d 4h 12m',
    );
    expect(formatPlaytime(const Duration(days: 1)), '1d');
    expect(formatPlaytime(const Duration(seconds: -5)), '0s');
  });
}
