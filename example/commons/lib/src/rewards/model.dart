/// Data of the rewards module: the config file and what is remembered about
/// each player. Plain dart_mappable classes, no server bindings.
library;

import 'package:dart_mappable/dart_mappable.dart';

part 'model.mapper.dart';

/// Some of an item, given to the player's inventory.
@MappableClass()
class ItemReward with ItemRewardMappable {
  /// The item's registry key, `diamond` or `minecraft:diamond`.
  final String item;
  final int count;

  const ItemReward(this.item, {this.count = 1});
}

/// A bonus for reaching a streak of [day] days.
@MappableClass()
class StreakMilestone with StreakMilestoneMappable {
  /// The streak day that earns the bonus (counted from 1).
  final int day;

  /// Money paid in addition to the daily reward.
  final int currency;

  /// Items given in addition to the daily reward.
  final List<ItemReward> items;

  /// Shown to the player, like `Weekly bonus`.
  final String label;

  const StreakMilestone({
    required this.day,
    this.currency = 0,
    this.items = const [],
    this.label = 'Milestone',
  });
}

/// Settings of the daily reward.
///
/// A "day" runs from [resetHourUtc] to the same hour on the next calendar day
/// (UTC), and a player can claim once per day. The streak goes up by one for
/// every claim on a following day; missing up to [graceDays] whole days keeps
/// it alive, missing more starts it again at day 1.
@MappableClass()
class DailyConfig with DailyConfigMappable {
  final bool enabled;

  /// The reward of streak day 1.
  final int baseAmount;

  /// How much each further streak day adds, up to [maxGrowthDays].
  final int incrementPerDay;

  /// The streak day at which the reward stops growing. Longer streaks keep
  /// earning the reward of this day.
  final int maxGrowthDays;

  /// The hour (0-23, UTC) at which a new day starts.
  final int resetHourUtc;

  /// How many whole days a player may skip without losing the streak.
  final int graceDays;

  /// Remind players who can claim when they join.
  final bool joinReminder;

  final List<StreakMilestone> milestones;

  const DailyConfig({
    this.enabled = true,
    this.baseAmount = 100,
    this.incrementPerDay = 25,
    this.maxGrowthDays = 7,
    this.resetHourUtc = 0,
    this.graceDays = 1,
    this.joinReminder = true,
    this.milestones = const [
      StreakMilestone(
        day: 7,
        currency: 500,
        items: [ItemReward('diamond', count: 3)],
        label: 'Weekly bonus',
      ),
      StreakMilestone(
        day: 14,
        currency: 1000,
        items: [ItemReward('diamond', count: 8)],
        label: 'Two week bonus',
      ),
      StreakMilestone(
        day: 30,
        currency: 3000,
        items: [ItemReward('netherite_ingot', count: 1)],
        label: 'Monthly bonus',
      ),
    ],
  });

  /// This config with values brought into range: no negative money, a growth
  /// cap of at least one day, an hour between 0 and 23, and only milestones
  /// on positive days (the first one of a day wins).
  DailyConfig sanitized() {
    final seen = <int>{};
    return DailyConfig(
      enabled: enabled,
      baseAmount: baseAmount < 0 ? 0 : baseAmount,
      incrementPerDay: incrementPerDay < 0 ? 0 : incrementPerDay,
      maxGrowthDays: maxGrowthDays < 1 ? 1 : maxGrowthDays,
      resetHourUtc: resetHourUtc.clamp(0, 23),
      graceDays: graceDays < 0 ? 0 : graceDays,
      joinReminder: joinReminder,
      milestones: [
        for (final m in milestones)
          if (m.day >= 1 && seen.add(m.day))
            StreakMilestone(
              day: m.day,
              currency: m.currency < 0 ? 0 : m.currency,
              items: [
                for (final item in m.items)
                  if (item.count >= 1) item,
              ],
              label: m.label,
            ),
      ],
    );
  }
}

/// Money paid once when a player has been online for [minutes] in total.
@MappableClass()
class PlaytimeMilestone with PlaytimeMilestoneMappable {
  final int minutes;
  final int currency;

  const PlaytimeMilestone({required this.minutes, required this.currency});
}

/// Settings of playtime tracking.
@MappableClass()
class PlaytimeConfig with PlaytimeConfigMappable {
  /// How often the time of everyone online is added up and saved. A crash
  /// loses at most this much per player.
  final int tickSeconds;

  final List<PlaytimeMilestone> milestones;

  const PlaytimeConfig({
    this.tickSeconds = 60,
    this.milestones = const [
      PlaytimeMilestone(minutes: 60, currency: 250),
      PlaytimeMilestone(minutes: 600, currency: 1500),
      PlaytimeMilestone(minutes: 3000, currency: 5000),
    ],
  });

  /// Ticks of at least 5 seconds, milestones at positive minutes with
  /// non-negative money, each minute count once, in ascending order.
  PlaytimeConfig sanitized() {
    final seen = <int>{};
    final valid = [
      for (final m in milestones)
        if (m.minutes >= 1 && seen.add(m.minutes))
          PlaytimeMilestone(
            minutes: m.minutes,
            currency: m.currency < 0 ? 0 : m.currency,
          ),
    ]..sort((a, b) => a.minutes.compareTo(b.minutes));
    return PlaytimeConfig(
      tickSeconds: tickSeconds < 5 ? 5 : tickSeconds,
      milestones: valid,
    );
  }
}

/// `rewards/config.json`.
@MappableClass()
class RewardsConfig with RewardsConfigMappable {
  final DailyConfig daily;
  final PlaytimeConfig playtime;

  const RewardsConfig({
    this.daily = const DailyConfig(),
    this.playtime = const PlaytimeConfig(),
  });
}

/// What is remembered about one player's daily rewards.
@MappableClass()
class DailyState with DailyStateMappable {
  /// When the reward was last claimed.
  final DateTime? lastClaimAt;

  /// The streak as of the last claim (it may have lapsed since, see
  /// `DailyService.status`).
  final int streak;

  final int bestStreak;
  final int totalClaims;

  /// Items that did not fit into the inventory and wait to be handed over.
  final List<ItemReward> pendingItems;

  const DailyState({
    this.lastClaimAt,
    this.streak = 0,
    this.bestStreak = 0,
    this.totalClaims = 0,
    this.pendingItems = const [],
  });
}

/// `rewards/daily.json`: [DailyState] by player UUID.
@MappableClass()
class DailyFile with DailyFileMappable {
  final Map<String, DailyState> players;

  const DailyFile({this.players = const {}});
}

/// What is remembered about one player's playtime.
@MappableClass()
class PlaytimeEntry with PlaytimeEntryMappable {
  /// Seconds online, as of the last time the server added them up.
  final int seconds;

  /// The `minutes` of the playtime milestones that were already paid.
  final List<int> paidMilestones;

  const PlaytimeEntry({this.seconds = 0, this.paidMilestones = const []});
}

/// `rewards/playtime.json`: [PlaytimeEntry] by player UUID.
@MappableClass()
class PlaytimeFile with PlaytimeFileMappable {
  final Map<String, PlaytimeEntry> players;

  const PlaytimeFile({this.players = const {}});
}
