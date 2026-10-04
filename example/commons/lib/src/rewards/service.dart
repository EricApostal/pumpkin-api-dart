// ignore_for_file: prefer_initializing_formals
// (the public named parameters differ from the private fields)

import '../core/api.dart';
import '../core/clock.dart';
import '../core/storage.dart';
import 'model.dart';

const _millisPerDay = 24 * 60 * 60 * 1000;

/// How many days one page of the calendar shows (four weeks).
const calendarPageDays = 28;

/// Where a player stands with the daily reward right now.
final class DailyStatus {
  /// Whether a claim would succeed.
  final bool claimable;

  /// The streak that a claim would continue: 0 if the player never claimed
  /// or let it lapse, otherwise the number of days claimed in a row so far.
  final int streak;

  /// Whether the player had a streak that has lapsed and would start over.
  final bool lapsed;

  /// The streak day the next claim is for.
  int get nextDay => streak + 1;

  /// What the next claim pays in money (without a milestone bonus).
  final int nextReward;

  /// The milestone the next claim reaches, if any.
  final StreakMilestone? nextMilestone;

  /// How long until the next claim is possible; zero when [claimable].
  final Duration untilNext;

  final int bestStreak;
  final int totalClaims;
  final DateTime? lastClaimAt;

  const DailyStatus({
    required this.claimable,
    required this.streak,
    required this.lapsed,
    required this.nextReward,
    required this.nextMilestone,
    required this.untilNext,
    required this.bestStreak,
    required this.totalClaims,
    required this.lastClaimAt,
  });
}

enum ClaimFailure {
  /// The daily reward is switched off in the config.
  disabled,

  /// Already claimed today, see [ClaimResult.retryIn].
  alreadyClaimed,

  /// The money could not be paid (the balance is at its maximum). Nothing was
  /// claimed, the player can try again later.
  paymentFailed,
}

/// The outcome of [DailyService.claim].
final class ClaimResult {
  final ClaimFailure? failure;

  /// For [ClaimFailure.alreadyClaimed]: when the next claim is possible.
  final Duration retryIn;

  /// The streak day that was claimed.
  final int day;

  /// Whether the claim started a new streak after a lapse.
  final bool streakWasReset;

  /// Money paid in total (the daily reward and the milestone bonus).
  final int currency;

  /// The part of [currency] that came from the [milestone].
  final int bonus;

  /// The milestone reached, if any.
  final StreakMilestone? milestone;

  /// Items to hand over; give them and [DailyService.stash] what did not fit.
  final List<ItemReward> items;

  /// The player's balance after being paid.
  final int balance;

  const ClaimResult._({
    this.failure,
    this.retryIn = Duration.zero,
    this.day = 0,
    this.streakWasReset = false,
    this.currency = 0,
    this.bonus = 0,
    this.milestone,
    this.items = const [],
    this.balance = 0,
  });

  const ClaimResult.failed(
    ClaimFailure failure, {
    Duration retryIn = Duration.zero,
  }) : this._(failure: failure, retryIn: retryIn);

  bool get isOk => failure == null;
}

/// How a day of the calendar looks to a player.
enum CalendarState {
  /// Already claimed in the current streak.
  claimed,

  /// Can be claimed now.
  available,

  /// The next day to claim, but today's reward is already taken.
  next,

  /// Further in the future.
  locked,
}

/// One day on a page of the calendar.
final class CalendarDay {
  final int day;
  final CalendarState state;

  /// The money the day pays, without the bonus.
  final int reward;
  final StreakMilestone? milestone;

  const CalendarDay(this.day, this.state, this.reward, this.milestone);
}

/// The daily reward with a login streak.
///
/// The server day starts at [DailyConfig.resetHourUtc] (UTC). A player claims
/// once per day. The streak counts days claimed in a row; skipping up to
/// [DailyConfig.graceDays] whole days keeps it, skipping more starts again at
/// day 1. If the clock goes backwards a claim is never possible twice for the
/// same moment: a last claim in the "future" counts as claimed today.
///
/// The money is paid through [Economy] before the claim is recorded, so a
/// player whose balance is full loses nothing: the claim fails and can be
/// repeated.
final class DailyService implements RewardsApi {
  final Economy _economy;
  final JsonDocument<DailyFile> _doc;
  final Clock _clock;

  /// The (sanitized) settings.
  final DailyConfig config;

  DailyService({
    required Economy economy,
    required JsonDocument<DailyFile> doc,
    required DailyConfig config,
    required Clock clock,
  }) : _economy = economy,
       _doc = doc,
       _clock = clock,
       config = config.sanitized();

  @override
  bool canClaimDaily(String uuid) => config.enabled && status(uuid).claimable;

  /// The index of the server day that [time] belongs to.
  int dayIndex(DateTime time) {
    final shifted =
        time.toUtc().millisecondsSinceEpoch - config.resetHourUtc * 3600000;
    return (shifted - shifted % _millisPerDay) ~/ _millisPerDay;
  }

  DateTime _startOfDay(int index) => DateTime.fromMillisecondsSinceEpoch(
    index * _millisPerDay + config.resetHourUtc * 3600000,
    isUtc: true,
  );

  /// The money paid for streak day [day] (1 or more), without bonuses.
  int rewardFor(int day) {
    final growing =
        (day < config.maxGrowthDays ? day : config.maxGrowthDays) - 1;
    return config.baseAmount +
        config.incrementPerDay * (growing < 0 ? 0 : growing);
  }

  /// The milestone of streak day [day], if there is one.
  StreakMilestone? milestoneFor(int day) {
    for (final milestone in config.milestones) {
      if (milestone.day == day) return milestone;
    }
    return null;
  }

  DailyState _stateOf(String uuid) =>
      _doc.value.players[uuid] ?? const DailyState();

  void _put(String uuid, DailyState state) {
    _doc.value = DailyFile(players: {..._doc.value.players, uuid: state});
    _doc.save();
  }

  /// Where [uuid] stands right now.
  DailyStatus status(String uuid) {
    final state = _stateOf(uuid);
    final now = _clock.now();
    final last = state.lastClaimAt;
    var claimable = true;
    var streak = state.streak;
    var lapsed = false;
    var untilNext = Duration.zero;
    if (last != null) {
      final today = dayIndex(now);
      final gap = today - dayIndex(last);
      if (gap <= 0) {
        claimable = false;
        untilNext = _startOfDay(today + 1).difference(now);
      } else if (gap > 1 + config.graceDays) {
        lapsed = state.streak > 0;
        streak = 0;
      }
    } else {
      streak = 0;
    }
    final next = streak + 1;
    return DailyStatus(
      claimable: claimable,
      streak: streak,
      lapsed: lapsed,
      nextReward: rewardFor(next),
      nextMilestone: milestoneFor(next),
      untilNext: untilNext,
      bestStreak: state.bestStreak,
      totalClaims: state.totalClaims,
      lastClaimAt: last,
    );
  }

  /// Claims today's reward: pays the money and records the claim. The caller
  /// hands over [ClaimResult.items] and [stash]es what did not fit.
  ClaimResult claim(String uuid) {
    if (!config.enabled) return const ClaimResult.failed(ClaimFailure.disabled);
    final current = status(uuid);
    if (!current.claimable) {
      return ClaimResult.failed(
        ClaimFailure.alreadyClaimed,
        retryIn: current.untilNext,
      );
    }
    final day = current.nextDay;
    final milestone = current.nextMilestone;
    final bonus = milestone?.currency ?? 0;
    final currency = current.nextReward + bonus;
    var balance = _economy.balance(uuid);
    if (currency > 0) {
      final payment = _economy.deposit(
        uuid,
        currency,
        reason: 'Daily reward, day $day',
      );
      if (!payment.isOk) {
        return const ClaimResult.failed(ClaimFailure.paymentFailed);
      }
      balance = payment.balance;
    }
    final state = _stateOf(uuid);
    _put(
      uuid,
      DailyState(
        lastClaimAt: _clock.now(),
        streak: day,
        bestStreak: day > state.bestStreak ? day : state.bestStreak,
        totalClaims: state.totalClaims + 1,
        pendingItems: state.pendingItems,
      ),
    );
    return ClaimResult._(
      day: day,
      streakWasReset: current.lapsed,
      currency: currency,
      bonus: bonus,
      milestone: milestone,
      items: milestone?.items ?? const [],
      balance: balance,
    );
  }

  /// Remembers [items] that did not fit into the player's inventory, to be
  /// handed over later by [takePending].
  void stash(String uuid, List<ItemReward> items) {
    if (items.isEmpty) return;
    final state = _stateOf(uuid);
    _put(
      uuid,
      DailyState(
        lastClaimAt: state.lastClaimAt,
        streak: state.streak,
        bestStreak: state.bestStreak,
        totalClaims: state.totalClaims,
        pendingItems: [...state.pendingItems, ...items],
      ),
    );
  }

  /// The items waiting for [uuid], without removing them.
  List<ItemReward> pending(String uuid) => _stateOf(uuid).pendingItems;

  /// Removes and returns the items waiting for [uuid].
  List<ItemReward> takePending(String uuid) {
    final state = _stateOf(uuid);
    if (state.pendingItems.isEmpty) return const [];
    _put(
      uuid,
      DailyState(
        lastClaimAt: state.lastClaimAt,
        streak: state.streak,
        bestStreak: state.bestStreak,
        totalClaims: state.totalClaims,
      ),
    );
    return state.pendingItems;
  }

  /// The first page that shows the day the player claims next, 0-based.
  int currentCalendarPage(String uuid) =>
      (status(uuid).nextDay - 1) ~/ calendarPageDays;

  /// The days of calendar page [page] (0-based, [calendarPageDays] days).
  List<CalendarDay> calendar(String uuid, {required int page}) {
    final current = status(uuid);
    final first = page * calendarPageDays + 1;
    return [
      for (var day = first; day < first + calendarPageDays; day++)
        CalendarDay(
          day,
          day <= current.streak
              ? CalendarState.claimed
              : day == current.nextDay
              ? (current.claimable
                    ? CalendarState.available
                    : CalendarState.next)
              : CalendarState.locked,
          rewardFor(day),
          milestoneFor(day),
        ),
    ];
  }
}
