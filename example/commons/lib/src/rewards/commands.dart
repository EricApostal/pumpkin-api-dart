import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/module.dart';
import '../core/players.dart';
import 'permissions.dart';
import 'playtime.dart';
import 'ui.dart';

/// `/daily`, `/rewards`, `/playtime` and `/playtop`.
final class RewardsCommands {
  final ModuleHost _host;
  final RewardsUi _ui;
  final PlaytimeService _playtime;
  final PlayerDirectory _players;
  final Economy _economy;

  RewardsCommands(
    this._host,
    this._ui,
    this._playtime,
    this._players,
    this._economy,
  );

  MessageCatalog get _messages => _ui.messages;

  void register() {
    final context = _host.context;
    context.command(
      'daily',
      description: 'Claim your daily reward',
      permission: RewardsPerms.daily.node,
      (c) => c
        ..requirePlayer()
        ..runs((ctx) => _ui.claim(ctx.player)),
    );

    context.command(
      'rewards',
      description: 'Open the daily reward calendar',
      permission: RewardsPerms.calendar.node,
      (c) => c
        ..requirePlayer()
        ..runs((ctx) => _ui.openCalendar(ctx.player)),
    );

    context.command(
      'playtime',
      description: 'Show how long a player has played',
      aliases: ['pt'],
      permission: RewardsPerms.playtime.node,
      (c) => c.arg(
        'player',
        ArgumentTypes.word,
        optional: true,
        suggestsWith: (s) => _players.names,
        runs: _playtimeOf,
        build: (a) => a.requirePermission(RewardsPerms.playtimeOthers.node),
      ),
    );

    context.command(
      'playtop',
      description: 'Show the players with the most playtime',
      permission: RewardsPerms.playtop.node,
      (c) => c.arg(
        'page',
        ArgumentTypes.integer(min: 1),
        optional: true,
        runs: _playtop,
      ),
    );
  }

  void _playtimeOf(CommandContext ctx) {
    final name = ctx.stringOrNull('player');
    if (name == null && !ctx.isPlayer) {
      _fail('console.needsPlayer', {'command': 'playtime'});
    }
    final record = name == null ? null : _players.byName(name);
    if (name != null && record == null) {
      _fail('player.unknown', {'player': name});
    }

    final uuid = record?.uuid ?? uuidOf(ctx.player);
    final isSelf =
        record == null || (ctx.isPlayer && uuidOf(ctx.player) == uuid);
    final time = formatPlaytime(_playtime.playtime(uuid));
    ctx.sender.sendTemplate(
      _messages,
      isSelf ? 'playtime.self' : 'playtime.other',
      {'time': time, 'player': MessageFormat.escape(record?.name ?? '')},
    );
    final next = isSelf ? _playtime.nextMilestone(uuid) : null;
    if (next != null) {
      ctx.sender.sendTemplate(_messages, 'playtime.next', {
        'amount': _economy.format(next.currency),
        'target': formatPlaytime(Duration(minutes: next.minutes)),
        'left': formatPlaytime(
          Duration(minutes: next.minutes) - _playtime.playtime(uuid),
        ),
      });
    }
  }

  void _playtop(CommandContext ctx) {
    final board = _playtime.leaderboard();
    if (board.isEmpty) {
      ctx.sender.sendTemplate(_messages, 'playtop.empty');
      return;
    }
    ctx.sender.sendPage(
      Paginator(board, pageSize: 10),
      ctx.integerOrNull('page') ?? 1,
      title: _messages['playtop.title'].format(),
      command: '/playtop {page}',
      format: (entry, index) => _messages['playtop.line'].format({
        'rank': index + 1,
        'player': MessageFormat.escape(entry.name),
        'time': formatPlaytime(entry.time),
      }),
    );
  }

  /// Fails the command with the plain text of message [key].
  Never _fail(String key, [Map<String, Object?> values = const {}]) {
    final escaped = {
      for (final MapEntry(:key, :value) in values.entries)
        key: value is String ? MessageFormat.escape(value) : value,
    };
    throw CommandException(
      MessageFormat.stripColors(_messages[key].format(escaped)),
    );
  }
}
