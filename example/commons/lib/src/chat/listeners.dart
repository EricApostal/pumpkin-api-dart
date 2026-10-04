import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/clock.dart';
import '../core/players.dart';
import '../core/services.dart';
import 'format.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';
import 'ui.dart';
import 'welcome.dart';

/// The event side of the chat module: chat formatting, join and leave
/// messages and the welcome summary.
///
/// How chat is formatted: the `player-chat-event` only lets a plugin change
/// the message text, not the line the server builds (`<name> message`), and
/// its recipient list is empty. So the handler cancels the event and sends
/// the formatted line to every player itself, as a system message. That means
/// chat lines are not signed (the "report chat" feature has nothing to report)
/// and other plugins listening for chat see a cancelled event.
final class ChatListeners {
  final ChatService _service;
  final PlayerDirectory _players;
  final MessageCatalog _messages;
  final Services _services;
  final Clock _clock;
  final Logger _log;
  final ChatTemplate _template;

  ChatListeners({
    required this._service,
    required this._players,
    required this._messages,
    required this._services,
    required this._clock,
    required this._log,
  }) : _template = ChatTemplate(_service.config.format);

  ChatConfig get _config => _service.config;

  ModerationApi? get _moderation => _services.find<ModerationApi>();

  void register(Context context) {
    context
      ..intercept(Events.playerChat, _safe('chat', _onChat))
      ..intercept(Events.playerJoin, _safe('join', _onJoin))
      ..intercept(Events.playerLeave, _safe('leave', _onLeave));
  }

  /// A handler that never throws into the server: on an error the event
  /// continues unchanged (vanilla chat, vanilla join message).
  T Function(Server, T) _safe<T>(String name, T Function(Server, T) handler) {
    return (server, event) {
      try {
        return handler(server, event);
      } catch (e, s) {
        _log.error('The $name handler failed', error: e, stackTrace: s);
        return event;
      }
    };
  }

  // -- Chat ------------------------------------------------------------------

  PlayerChatEventData _onChat(Server server, PlayerChatEventData event) {
    // Someone else (staff chat) already took this message.
    if (event.cancelled) return event;
    final player = event.player;
    final uuid = player.uuidString;
    final name = player.getName();

    final mute = _moderation?.activeMute(uuid);
    if (mute != null) {
      player.send(
        _messages.text('muted', {
          'reason': MessageFormat.escape(mute.reason),
          'until': muteSuffix(mute, _clock),
        }),
      );
      return event.cancel();
    }
    if (!player.hasPermission(node: ChatPerms.bypass.node)) {
      final verdict = _service.spam.check(uuid, event.message);
      final reason = verdict.reason;
      if (reason != null) {
        player.send(
          _messages.text(spamMessageKey(reason), {
            'wait': formatDuration(verdict.wait),
          }),
        );
        return event.cancel();
      }
    }

    final everyone = server.getAllPlayers();
    final moderation = _moderation;
    final spans = _template.render(
      rank: _rankOf(player),
      playerName: name,
      message: event.message,
      allowColor: player.hasPermission(node: ChatPerms.color.node),
      mentionable: !_config.mentions
          ? const []
          : [
              for (final p in everyone)
                if (!(moderation?.isVanished(p.uuidString) ?? false))
                  p.getName(),
            ],
    );
    final line = chatLine(spans, name, _nameHover(player));
    final mentioned = {
      for (final span in spans)
        if (span.mention != null) span.mention!.toLowerCase(),
    };
    final exempt = player.hasPermission(node: ChatPerms.ignoreExempt.node);

    _log.info('<$name> ${event.message}');
    for (final recipient in everyone) {
      if (!_service.canSee(
        viewer: recipient.uuidString,
        sender: uuid,
        exempt: exempt,
      )) {
        continue;
      }
      recipient.send(line);
      if (mentioned.contains(recipient.getName().toLowerCase()) &&
          recipient.uuidString != uuid) {
        recipient.customSound(_config.mentionSound, pitch: 1.2);
        recipient.actionBar(
          _messages['mention.actionBar'].format({
            'player': MessageFormat.escape(name),
          }),
        );
      }
    }
    return event.cancel();
  }

  RankStyle _rankOf(Player player) => selectRank(
    _config.ranks,
    _config.defaultRank,
    (permission) => player.hasPermission(node: permission),
  );

  Text _nameHover(Player player) =>
      Text(player.getName())
          .yellow()
          .add(Text('\nClick to send a private message').gray());

  // -- Join and leave --------------------------------------------------------

  PlayerJoinEventData _onJoin(Server server, PlayerJoinEventData event) {
    final player = event.player;
    final uuid = player.uuidString;
    // The core records the player in the directory when its (non-blocking)
    // join listener runs. The server runs blocking handlers like this one
    // first, so an unknown player here is really a new one.
    final firstJoin = _players.byUuid(uuid) == null;

    if (_config.welcome.enabled) {
      server.after(Duration(seconds: _config.welcome.delaySeconds), (server) {
        final joined = onlinePlayer(server, uuid);
        if (joined == null) return;
        showWelcome(
          joined,
          _messages,
          _config.welcome,
          WelcomeSummary.collect(
            uuid,
            economy: _services.find<Economy>(),
            mail: _services.find<MailApi>(),
            rewards: _services.find<RewardsApi>(),
          ),
          firstJoin: firstJoin,
          online: server.getPlayerCount(),
          max: server.getMaxPlayers(),
        );
      });
    }

    final template = firstJoin ? _config.firstJoinFormat : _config.joinFormat;
    if (event.cancelled) return event;
    if (template.isEmpty || (_moderation?.isVanished(uuid) ?? false)) {
      return event.cancel();
    }
    return event.copyWith(
      joinMessage: Messages.component(
        _presence(server, template, player, count: _players.count + 1),
      ),
    );
  }

  PlayerLeaveEventData _onLeave(Server server, PlayerLeaveEventData event) {
    final player = event.player;
    final uuid = player.uuidString;
    _service.playerLeft(uuid);

    final template = _config.leaveFormat;
    if (event.cancelled) return event;
    if (template.isEmpty || (_moderation?.isVanished(uuid) ?? false)) {
      return event.cancel();
    }
    return event.copyWith(
      leaveMessage: Messages.component(
        _presence(server, template, player, count: _players.count),
      ),
    );
  }

  String _presence(
    Server server,
    String template,
    Player player, {
    required int count,
  }) {
    final rank = _rankOf(player);
    return MessageFormat.format(template, {
      'prefix': rank.prefix,
      'suffix': rank.suffix,
      'name': MessageFormat.escape(player.getName()),
      'online': server.getPlayerCount(),
      'count': count,
    });
  }
}
