import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import 'model.dart';
import 'playtime.dart';
import 'service.dart';

String uuidOf(Player player) => player.asEntity().getUuid().asString;

/// `minecraft:iron_ingot` as `Iron ingot`.
String prettyItem(String key) {
  final plain = key.contains(':') ? key.substring(key.indexOf(':') + 1) : key;
  final words = plain.replaceAll('_', ' ');
  return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

String _itemList(List<ItemReward> items) => items
    .map(
      (i) => i.count == 1
          ? prettyItem(i.item)
          : '${i.count}x ${prettyItem(i.item)}',
    )
    .join(', ');

/// Everything players see of the rewards: claim feedback, the calendar menu
/// and the messages around playtime. Uses the server, so it is not unit
/// tested; the logic it shows lives in [DailyService] and [PlaytimeService].
final class RewardsUi {
  final DailyService _daily;
  final Economy _economy;
  final MessageCatalog messages;

  RewardsUi(this._daily, this._economy, this.messages);

  // -- Claiming ---------------------------------------------------------------

  /// `/daily`: claims the reward, or says when the next one is due.
  void claim(Player player) {
    final uuid = uuidOf(player);
    final result = _daily.claim(uuid);
    switch (result.failure) {
      case ClaimFailure.disabled:
        player.sendTemplate(messages, 'daily.disabled');
      case ClaimFailure.paymentFailed:
        player.sendTemplate(messages, 'daily.full');
      case ClaimFailure.alreadyClaimed:
        final status = _daily.status(uuid);
        player.sendTemplate(messages, 'daily.wait', {
          'time': formatDuration(result.retryIn),
          'streak': status.streak,
          'amount': _economy.format(status.nextReward),
        });
      case null:
        _celebrate(player, result);
    }
    deliverPending(player);
  }

  void _celebrate(Player player, ClaimResult result) {
    final amount = _economy.format(result.currency);
    player.title(
      messages['daily.title'].format(),
      subtitle: messages['daily.subtitle'].format({
        'amount': amount,
        'day': result.day,
      }),
      stay: const Duration(seconds: 2),
    );
    // Sounds go by registry name: the Sound enum path crashes the host.
    player.customSound(
      result.milestone == null
          ? 'minecraft:entity.player.levelup'
          : 'minecraft:ui.toast.challenge_complete',
      volume: 0.7,
    );
    player.sendTemplate(messages, 'daily.claimed', {
      'amount': amount,
      'day': result.day,
      'balance': _economy.format(result.balance),
    });
    if (result.streakWasReset) player.sendTemplate(messages, 'daily.reset');
    final milestone = result.milestone;
    if (milestone != null) {
      player.sendTemplate(messages, 'daily.bonus', {
        'label': MessageFormat.escape(milestone.label),
        'bonus': _economy.format(result.bonus),
      });
      _daily.stash(uuidOf(player), _give(player, result.items));
    }
  }

  /// Puts [items] into the player's inventory and returns what did not fit.
  List<ItemReward> _give(Player player, List<ItemReward> items) {
    final delivered = <ItemReward>[];
    final leftover = <ItemReward>[];
    for (final item in items) {
      final notFitting = player.giveItem(item.item, count: item.count);
      if (notFitting < item.count) {
        delivered.add(ItemReward(item.item, count: item.count - notFitting));
      }
      if (notFitting > 0) {
        leftover.add(ItemReward(item.item, count: notFitting));
      }
    }
    if (delivered.isNotEmpty) {
      player.sendTemplate(messages, 'daily.items', {
        'items': _itemList(delivered),
      });
    }
    return leftover;
  }

  /// Hands over reward items that did not fit earlier, as far as they fit now.
  void deliverPending(Player player) {
    final uuid = uuidOf(player);
    final waiting = _daily.takePending(uuid);
    if (waiting.isEmpty) return;
    final leftover = _give(player, waiting);
    if (leftover.isEmpty) return;
    _daily.stash(uuid, leftover);
    player.sendTemplate(messages, 'items.waiting', {
      'count': leftover.fold(0, (sum, item) => sum + item.count),
    });
  }

  /// Tells a player who joined about waiting items and an unclaimed reward.
  void welcome(Player player) {
    deliverPending(player);
    if (!_daily.config.joinReminder || !_daily.canClaimDaily(uuidOf(player))) {
      return;
    }
    player.send(
      Text.legacy(messages.text('daily.ready'))
          .add(' ')
          .add(
            Text(messages['daily.button'].format())
                .green()
                .bold()
                .runCommand('/daily')
                .hover(messages['daily.button.hover'].format()),
          ),
    );
  }

  // -- Playtime ---------------------------------------------------------------

  /// Tells a player about a playtime reward they just earned.
  void milestone(Player player, MilestonePayout payout, Duration total) {
    final values = {
      'time': formatPlaytime(total),
      'amount': _economy.format(payout.milestone.currency),
    };
    player.sendTemplate(messages, 'playtime.milestone', values);
    player.actionBar(messages.text('playtime.milestone.bar', values));
    player.customSound('minecraft:entity.experience_orb.pickup');
  }

  // -- Calendar ---------------------------------------------------------------

  /// Opens the calendar on the page of [page] (0-based), by default the one
  /// with the day the player claims next.
  void openCalendar(Player player, {int? page}) {
    final uuid = uuidOf(player);
    _calendar(uuid, page ?? _daily.currentCalendarPage(uuid)).open(player);
  }

  Menu _calendar(String uuid, int page) {
    final status = _daily.status(uuid);
    final menu = Menu(title: messages['calendar.title'].format(), rows: 6);

    final days = _daily.calendar(uuid, page: page);
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      menu.button(
        row: 1 + i ~/ 7,
        column: 1 + i % 7,
        item: _dayItem(day, status),
        onClick: day.state == CalendarState.available
            ? (click) {
                claim(click.player);
                click.open(_calendar(click.playerId, page));
              }
            : null,
      );
    }

    menu.button(
      row: 0,
      column: 4,
      item: ItemSpec(
        'clock',
        name: messages['calendar.header.name'].format(),
        lore: [
          messages['calendar.header.streak'].format({
            'streak': status.streak,
            'best': status.bestStreak,
          }),
          messages['calendar.header.claims'].format({
            'claims': status.totalClaims,
          }),
          messages['calendar.header.next'].format({
            'amount': _economy.format(status.nextReward),
          }),
          if (status.lapsed) messages['calendar.header.lapsed'].format(),
        ],
      ),
    );
    if (page > 0) {
      menu.button(
        row: 5,
        column: 3,
        item: ItemSpec('arrow', name: messages['calendar.previous'].format()),
        onClick: (click) => click.open(_calendar(click.playerId, page - 1)),
      );
    }
    menu.button(
      row: 5,
      column: 5,
      item: ItemSpec('arrow', name: messages['calendar.next'].format()),
      onClick: (click) => click.open(_calendar(click.playerId, page + 1)),
    );
    menu.fill(const ItemSpec('gray_stained_glass_pane', name: ' '));
    return menu;
  }

  ItemSpec _dayItem(CalendarDay day, DailyStatus status) {
    final state = day.state;
    final milestone = day.milestone;
    final key = milestone == null
        ? switch (state) {
            CalendarState.claimed => 'lime_stained_glass_pane',
            CalendarState.available => 'chest',
            CalendarState.next => 'clock',
            CalendarState.locked => 'gray_stained_glass_pane',
          }
        : switch (state) {
            CalendarState.claimed => 'emerald',
            CalendarState.available || CalendarState.next => 'nether_star',
            CalendarState.locked => 'diamond',
          };
    return ItemSpec(
      key,
      count: day.day.clamp(1, 64),
      name: messages['calendar.name.${state.name}'].format({'day': day.day}),
      glint: state == CalendarState.available ? true : null,
      lore: [
        messages['calendar.reward'].format({
          'amount': _economy.format(day.reward),
        }),
        if (milestone != null) ...[
          messages['calendar.milestone'].format({
            'label': MessageFormat.escape(milestone.label),
          }),
          if (milestone.currency > 0)
            messages['calendar.bonus'].format({
              'amount': _economy.format(milestone.currency),
            }),
          for (final item in milestone.items)
            messages['calendar.item'].format({
              'item': _itemList([item]),
            }),
        ],
        ?switch (state) {
          CalendarState.claimed => messages['calendar.state.claimed'].format(),
          CalendarState.available =>
            messages['calendar.state.available'].format(),
          CalendarState.next => messages['calendar.state.next'].format({
            'time': formatDuration(status.untilNext),
          }),
          CalendarState.locked => null,
        },
      ],
    );
  }
}
