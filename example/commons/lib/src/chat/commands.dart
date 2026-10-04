import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/clock.dart';
import '../core/players.dart';
import '../core/services.dart';
import 'format.dart';
import 'permissions.dart';
import 'service.dart';
import 'ui.dart';

/// `/msg`, `/reply`, `/ignore`, `/ignorelist` and `/spy`.
final class ChatCommands {
  final ChatService _service;
  final PlayerDirectory _players;
  final MessageCatalog _messages;
  final Services _services;
  final Clock _clock;

  ChatCommands({
    required this._service,
    required this._players,
    required this._messages,
    required this._services,
    required this._clock,
  });

  ModerationApi? get _moderation => _services.find<ModerationApi>();

  void register(Context context) {
    context.command(
      'msg',
      aliases: ['tell', 'w', 'm'],
      description: 'Send a private message',
      permission: ChatPerms.msg.node,
      (c) => c
        ..requirePlayer()
        ..cooldown(const Duration(seconds: 1), bypass: ChatPerms.bypass.node)
        ..arg(
          'player',
          ArgumentTypes.word,
          suggestsWith: _onlineNames,
          build: (a) =>
              a.arg('message', ArgumentTypes.greedyString, runs: _message),
        ),
    );
    context.command(
      'reply',
      aliases: ['r'],
      description: 'Answer the last private message',
      permission: ChatPerms.msg.node,
      (c) => c
        ..requirePlayer()
        ..cooldown(const Duration(seconds: 1), bypass: ChatPerms.bypass.node)
        ..arg('message', ArgumentTypes.greedyString, runs: _reply),
    );
    context.command(
      'ignore',
      description: 'Hide the chat and messages of a player (again to undo)',
      permission: ChatPerms.ignore.node,
      (c) => c
        ..requirePlayer()
        ..arg(
          'player',
          ArgumentTypes.word,
          suggestsWith: _knownNames,
          runs: _ignore,
        ),
    );
    context.command(
      'ignorelist',
      aliases: ['ignores'],
      description: 'List the players you ignore',
      permission: ChatPerms.ignore.node,
      (c) => c
        ..requirePlayer()
        ..runs(_ignoreList),
    );
    context.command(
      'spy',
      description: 'See the private messages of everybody',
      permission: ChatPerms.spy.node,
      (c) => c
        ..requirePlayer()
        ..arg(
          'state',
          ArgumentTypes.oneOf(['on', 'off']),
          optional: true,
          runs: _spy,
        ),
    );
  }

  // -- Tab completion --------------------------------------------------------

  /// Players that are online, without the sender, and without vanished ones
  /// unless the sender may see them.
  Iterable<String> _onlineNames(SuggestionContext s) {
    final seeVanished = s.hasPermission(ChatPerms.seeVanished.node);
    return [
      for (final p in s.server.getAllPlayers())
        if (p.getName() != s.senderName &&
            (seeVanished || !_isVanished(p.uuidString)))
          p.getName(),
    ];
  }

  Iterable<String> _knownNames(SuggestionContext s) =>
      _players.names.where((name) => name != s.senderName);

  bool _isVanished(String uuid) => _moderation?.isVanished(uuid) ?? false;

  // -- Private messages ------------------------------------------------------

  void _message(CommandContext ctx) {
    final name = ctx.string('player');
    final seeVanished = ctx.hasPermission(ChatPerms.seeVanished.node);
    final target = onlinePlayerByName(ctx.server, name);
    if (target == null || (!seeVanished && _isVanished(target.uuidString))) {
      ctx.fail(_messages['error.offline'].format({'name': name}));
    }
    _deliver(ctx, target, ctx.string('message'));
  }

  void _reply(CommandContext ctx) {
    final partner =
        _service.conversations.lastPartner(ctx.player.uuidString) ??
        ctx.fail(_messages['error.noReply'].format());
    final target =
        onlinePlayer(ctx.server, partner) ??
        ctx.fail(
          _messages['error.replyGone'].format({
            'name': _players.nameOf(partner) ?? 'That player',
          }),
        );
    _deliver(ctx, target, ctx.string('message'));
  }

  /// Sends [rawText] from the command's sender to [to], and tells spies.
  ///
  /// A player who ignores the sender is not told: the sender sees the message
  /// as sent (so nobody can tell they are ignored) but it never arrives.
  void _deliver(CommandContext ctx, Player to, String rawText) {
    final from = ctx.player;
    final fromUuid = from.uuidString;
    final toUuid = to.uuidString;
    if (fromUuid == toUuid) ctx.fail(_messages['error.self'].format());
    final mute = _moderation?.activeMute(fromUuid);
    if (mute != null) {
      ctx.fail(
        _messages['error.muted'].format({
          'reason': mute.reason,
          'until': muteSuffix(mute, _clock),
        }),
      );
    }
    final text = cleanText(rawText);
    if (text.isEmpty) ctx.fail(_messages['error.empty'].format());

    final body = from.hasPermission(node: ChatPerms.color.node)
        ? text
        : escapeLegacy(text);
    final fromName = from.getName();
    final toName = to.getName();
    final config = _service.config;
    final delivered = _service.canSee(
      viewer: toUuid,
      sender: fromUuid,
      exempt: from.hasPermission(node: ChatPerms.ignoreExempt.node),
    );

    from.send(
      Text.legacy(
        MessageFormat.format(config.pmSentFormat, {
          'player': MessageFormat.escape(toName),
          'message': body,
        }),
      ).suggestCommand('/msg $toName ').hover('Click to write again'),
    );
    if (delivered) {
      to.send(
        Text.legacy(
          MessageFormat.format(config.pmReceivedFormat, {
            'player': MessageFormat.escape(fromName),
            'message': body,
          }),
        ).suggestCommand('/msg $fromName ').hover('Click to reply'),
      );
      to.customSound(pmSound, volume: 0.6, pitch: 1.4);
      _service.conversations.record(fromUuid, toUuid);
    } else {
      _service.conversations.recordOneWay(fromUuid, toUuid);
    }
    _tellSpies(ctx.server, {fromUuid, toUuid}, fromName, toName, body);
  }

  void _tellSpies(
    Server server,
    Set<String> participants,
    String fromName,
    String toName,
    String body,
  ) {
    if (_service.spies.isEmpty) return;
    final line = MessageFormat.format(_service.config.spyFormat, {
      'from': MessageFormat.escape(fromName),
      'to': MessageFormat.escape(toName),
      'message': body,
    });
    for (final player in server.getAllPlayers()) {
      final uuid = player.uuidString;
      if (_service.isSpying(uuid) &&
          !participants.contains(uuid) &&
          player.hasPermission(node: ChatPerms.spy.node)) {
        player.send(line);
      }
    }
  }

  // -- Ignoring --------------------------------------------------------------

  void _ignore(CommandContext ctx) {
    final me = ctx.player.uuidString;
    final name = ctx.string('player');
    final target =
        _players.byName(name) ??
        ctx.fail(_messages['error.unknownPlayer'].format({'name': name}));
    if (target.uuid == me) ctx.fail(_messages['error.ignoreSelf'].format());

    final ignoring = !_service.isIgnoring(me, target.uuid);
    if (ignoring) {
      final online = onlinePlayer(ctx.server, target.uuid);
      if (online != null &&
          online.hasPermission(node: ChatPerms.ignoreExempt.node)) {
        ctx.fail(_messages['error.exempt'].format({'name': target.name}));
      }
    }
    _service.setIgnoring(me, target.uuid, ignoring: ignoring);
    ctx.sender.sendTemplate(_messages, ignoring ? 'ignore.on' : 'ignore.off', {
      'player': MessageFormat.escape(target.name),
    });
  }

  void _ignoreList(CommandContext ctx) {
    final ignored = _service.ignoredBy(ctx.player.uuidString);
    if (ignored.isEmpty) {
      ctx.sender.sendTemplate(_messages, 'ignore.none');
      return;
    }
    ctx.sender.sendTemplate(_messages, 'ignore.title');
    for (final uuid in ignored) {
      final name = _players.nameOf(uuid) ?? uuid;
      ctx.sender.send(
        Text('  $name ').white() +
            button(
              'Unignore',
              '/ignore $name',
              'Stop ignoring $name',
              color: (t) => t.red(),
            ),
      );
    }
  }

  // -- Spying ----------------------------------------------------------------

  void _spy(CommandContext ctx) {
    final state = ctx.stringOrNull('state');
    final on = _service.setSpying(
      ctx.player.uuidString,
      on: state == null ? null : state == 'on',
    );
    ctx.sender.sendTemplate(_messages, on ? 'spy.on' : 'spy.off');
  }
}
