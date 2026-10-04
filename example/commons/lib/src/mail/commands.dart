import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/clock.dart';
import '../core/players.dart';
import 'permissions.dart';
import 'service.dart';
import 'ui.dart';

/// `/mail` and its subcommands.
final class MailCommands {
  final MailService _service;
  final PlayerDirectory _players;
  final MessageCatalog _messages;
  final Clock _clock;
  final ConfirmationManager<int Function()> _confirmations;

  MailCommands({
    required this._service,
    required this._players,
    required this._messages,
    required this._clock,
  }) : _confirmations = ConfirmationManager(now: _clock.now);

  void register(Context context) {
    context.command(
      'mail',
      description: 'Send and read offline messages',
      permission: MailPerms.read.node,
      (c) => c
        ..requirePlayer()
        ..runs((ctx) => _inbox(ctx, 1))
        ..sub(
          'read',
          description: 'List your mail, or read one message',
          runs: (ctx) => _inbox(ctx, 1),
          build: (s) => s.arg(
            'id',
            ArgumentTypes.integer(min: 1),
            suggestsWith: _inboxIds,
            runs: _readOne,
          ),
        )
        ..sub(
          'page',
          description: 'Show a page of your inbox',
          build: (s) => s.arg(
            'page',
            ArgumentTypes.integer(min: 1),
            runs: (ctx) => _inbox(ctx, ctx.integer('page')),
          ),
        )
        ..sub(
          'send',
          description: 'Send a message to a player, online or not',
          permission: MailPerms.send.node,
          build: (s) => s.arg(
            'player',
            ArgumentTypes.word,
            suggestsWith: _playerNames,
            build: (a) =>
                a.arg('message', ArgumentTypes.greedyString, runs: _send),
          ),
        )
        ..sub(
          'delete',
          description: 'Delete a message, all read ones, or all of them',
          build: (s) => s.arg(
            'which',
            ArgumentTypes.word,
            suggestsWith: (s) => ['read', 'all', ..._inboxIds(s)],
            runs: _delete,
          ),
        )
        ..sub(
          'clear',
          description: 'Delete your whole inbox (asks to confirm)',
          runs: _askToClear,
          build: (s) => s.sub(
            'confirm',
            description: 'Confirm /mail clear',
            runs: _confirmClear,
          ),
        )
        ..sub(
          'sent',
          description: 'Show the messages you sent',
          runs: (ctx) => _sent(ctx, 1),
          build: (s) => s.arg(
            'page',
            ArgumentTypes.integer(min: 1),
            runs: (ctx) => _sent(ctx, ctx.integer('page')),
          ),
        )
        ..sub(
          'block',
          description: 'Stop a player from mailing you',
          permission: MailPerms.block.node,
          build: (s) => s.arg(
            'player',
            ArgumentTypes.word,
            suggestsWith: _playerNames,
            runs: (ctx) => _block(ctx, block: true),
          ),
        )
        ..sub(
          'unblock',
          description: 'Let a blocked player mail you again',
          permission: MailPerms.block.node,
          build: (s) => s.arg(
            'player',
            ArgumentTypes.word,
            suggestsWith: _blockedNames,
            runs: (ctx) => _block(ctx, block: false),
          ),
        )
        ..sub(
          'blocked',
          description: 'List the players you blocked',
          permission: MailPerms.block.node,
          runs: _listBlocked,
        ),
    );
  }

  // -- Tab completion --------------------------------------------------------

  Iterable<String> _playerNames(SuggestionContext s) =>
      _players.names.where((name) => name != s.senderName);

  Iterable<String> _inboxIds(SuggestionContext s) {
    final uuid = s.player?.uuidString;
    if (uuid == null) return const [];
    return [for (final m in _service.inbox(uuid)) '${m.id}'];
  }

  Iterable<String> _blockedNames(SuggestionContext s) {
    final uuid = s.player?.uuidString;
    if (uuid == null) return const [];
    return [
      for (final blocked in _service.blockedBy(uuid)) ?_players.nameOf(blocked),
    ];
  }

  // -- Reading ---------------------------------------------------------------

  void _inbox(CommandContext ctx, int pageNumber) {
    final uuid = ctx.player.uuidString;
    final inbox = _service.inbox(uuid);
    if (inbox.isEmpty) {
      ctx.sender.sendTemplate(_messages, 'inbox.empty');
      return;
    }
    final page = Paginator(
      inbox,
      pageSize: _service.config.pageSize,
    ).page(pageNumber);
    final unread = _service.unreadCount(uuid);
    final header = Text(
      '--- ${_messages['inbox.title']} (${page.number}/${page.count}) ',
    ).yellow();
    if (unread > 0) header.add(Text('· $unread unread ').gold());
    ctx.sender.send(header.add(Text('---').yellow()));
    final now = _clock.now();
    for (final mail in page.items) {
      ctx.sender.send(inboxLine(mail, now));
    }
    if (page.count > 1) ctx.sender.send(pageFooter(page, '/mail page {page}'));
  }

  void _readOne(CommandContext ctx) {
    final id = ctx.integer('id');
    final mail =
        _service.read(ctx.player.uuidString, id) ??
        ctx.fail(_messages['error.noMessage'].format({'id': id}));
    final sender = ctx.sender;
    sender.send(
      _messages['read.header'].format({
        'id': mail.id,
        'player': MessageFormat.escape(mail.fromName),
        'ago': formatAgo(_clock.now().difference(mail.sentAt)),
      }),
    );
    sender.send(Text(mail.text).white());
    sender.send(
      button(
            'Reply',
            '/mail send ${mail.fromName} ',
            'Reply to ${mail.fromName}',
            suggest: true,
            color: (t) => t.aqua(),
          ) +
          Text(' ') +
          button(
            'Delete',
            '/mail delete ${mail.id}',
            'Delete this message',
            color: (t) => t.red(),
          ) +
          Text(' ') +
          button(
            'Inbox',
            '/mail',
            'Back to your inbox',
            color: (t) => t.yellow(),
          ),
    );
  }

  // -- Sending ---------------------------------------------------------------

  void _send(CommandContext ctx) {
    final from = ctx.player;
    final name = ctx.string('player');
    final to =
        _players.byName(name) ??
        ctx.fail(_messages['error.unknownPlayer'].format({'name': name}));
    final result = _service.send(
      fromUuid: from.uuidString,
      fromName: from.getName(),
      toUuid: to.uuid,
      toName: to.name,
      text: ctx.string('message'),
      bypassCooldown: ctx.hasPermission(MailPerms.bypass.node),
    );
    final mail = result.message;
    if (mail == null) ctx.fail(_failureText(result, to.name));

    final recipient = onlinePlayer(ctx.server, to.uuid);
    if (recipient != null) notifyNewMail(recipient, _messages, mail);
    ctx.sender.sendTemplate(_messages, 'send.done', {
      'player': MessageFormat.escape(to.name),
    });
  }

  String _failureText(SendResult result, String recipient) {
    final m = _messages;
    return switch (result.failure!) {
      SendFailure.empty => m['error.empty'].format(),
      SendFailure.tooLong => m['error.tooLong'].format({
        'max': _service.config.maxMessageLength,
      }),
      SendFailure.toSelf => m['error.self'].format(),
      SendFailure.muted => m['error.muted'].format({
        'reason': result.mute!.reason,
        'until': _muteRemaining(result.mute!),
      }),
      SendFailure.blocked => m['error.blocked'].format({'player': recipient}),
      SendFailure.inboxFull => m['error.inboxFull'].format({
        'player': recipient,
      }),
      SendFailure.cooldown => m['send.cooldown'].format({
        'wait': formatDuration(result.wait!),
      }),
    };
  }

  String _muteRemaining(MuteInfo mute) {
    final until = mute.until;
    if (until == null) return ' (permanent)';
    return ' (${formatDuration(until.difference(_clock.now()))} left)';
  }

  // -- Deleting --------------------------------------------------------------

  void _delete(CommandContext ctx) {
    final uuid = ctx.player.uuidString;
    final which = ctx.string('which').toLowerCase();
    switch (which) {
      case 'all':
        _askToClear(ctx);
      case 'read':
        final count = _service.deleteRead(uuid);
        ctx.sender.sendTemplate(
          _messages,
          count == 0 ? 'delete.none' : 'delete.read',
          {'count': count},
        );
      default:
        final id = int.tryParse(which);
        if (id == null) ctx.fail(_messages['error.badTarget'].format());
        if (!_service.delete(uuid, id)) {
          ctx.fail(_messages['error.noMessage'].format({'id': id}));
        }
        ctx.sender.sendTemplate(_messages, 'delete.one', {'id': id});
    }
  }

  void _askToClear(CommandContext ctx) {
    final uuid = ctx.player.uuidString;
    final count = _service.inboxSize(uuid);
    if (count == 0) {
      ctx.sender.sendTemplate(_messages, 'delete.none');
      return;
    }
    _confirmations.request(
      uuid,
      () => _service.deleteAll(uuid),
      ttl: const Duration(seconds: 15),
    );
    ctx.sender.send(
      Text.legacy(_messages['clear.confirm'].format({'count': count})) +
          button(
            'Confirm',
            '/mail clear confirm',
            'Delete everything',
            color: (t) => t.red(),
          ),
    );
  }

  void _confirmClear(CommandContext ctx) {
    final clear = _confirmations.confirm(ctx.player.uuidString);
    if (clear == null) ctx.fail(_messages['error.nothingToConfirm'].format());
    ctx.sender.sendTemplate(_messages, 'delete.all', {'count': clear()});
  }

  // -- Outbox ----------------------------------------------------------------

  void _sent(CommandContext ctx, int pageNumber) {
    final sent = _service.sent(ctx.player.uuidString);
    if (sent.isEmpty) {
      ctx.sender.sendTemplate(_messages, 'sent.empty');
      return;
    }
    final page = Paginator(
      sent,
      pageSize: _service.config.pageSize,
    ).page(pageNumber);
    ctx.sender.send(
      Text('--- ${_messages['sent.title']} (${page.number}/${page.count}) ---')
          .yellow(),
    );
    final now = _clock.now();
    for (final mail in page.items) {
      final status = switch (_service.statusOf(mail)) {
        SentStatus.unread => Text('unread').gold(),
        SentStatus.read => Text('read').green(),
        SentStatus.deleted => Text('deleted').darkGray(),
      };
      ctx.sender.send(
        Text.empty()
            .add(Text('→ ').darkGray())
            .add(Text(mail.toName).yellow())
            .add(Text(' ${formatAgo(now.difference(mail.sentAt))} ').darkGray())
            .add(Text('(').darkGray())
            .add(status)
            .add(Text('): ').darkGray())
            .add(Text(mail.text).gray()),
      );
    }
    if (page.count > 1) ctx.sender.send(pageFooter(page, '/mail sent {page}'));
  }

  // -- Blocking --------------------------------------------------------------

  void _block(CommandContext ctx, {required bool block}) {
    if (!_service.config.allowBlocking) {
      ctx.fail(_messages['error.blockingOff'].format());
    }
    final me = ctx.player.uuidString;
    final name = ctx.string('player');
    final target =
        _players.byName(name) ??
        ctx.fail(_messages['error.unknownPlayer'].format({'name': name}));
    if (target.uuid == me) ctx.fail(_messages['error.blockSelf'].format());
    final changed = block
        ? _service.block(me, target.uuid)
        : _service.unblock(me, target.uuid);
    final key = block
        ? (changed ? 'block.done' : 'block.already')
        : (changed ? 'unblock.done' : 'unblock.not');
    ctx.sender.sendTemplate(_messages, key, {
      'player': MessageFormat.escape(target.name),
    });
  }

  void _listBlocked(CommandContext ctx) {
    final names = [
      for (final uuid in _service.blockedBy(ctx.player.uuidString))
        _players.nameOf(uuid) ?? uuid,
    ];
    if (names.isEmpty) {
      ctx.sender.sendTemplate(_messages, 'blocked.none');
      return;
    }
    ctx.sender.sendTemplate(_messages, 'blocked.title', {
      'players': MessageFormat.escape(names.join(', ')),
    });
  }
}
