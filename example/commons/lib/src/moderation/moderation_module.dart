import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/module.dart';
import '../core/permissions.dart';
import '../core/players.dart';
import 'commands.dart';
import 'enforcement.dart';
import 'messages.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';

/// Warnings, mutes, bans and kicks with a history, plus the staff tools
/// (`/vanish`, `/staffchat`). Provides [ModerationApi] to the chat module.
///
/// See `docs/moderation.md` for what is enforced where.
final class ModerationModule extends Module {
  ModuleHost? _host;
  Enforcement? _enforcement;

  @override
  String get name => 'moderation';

  @override
  List<PermNode> get permissions => ModerationPerms.all;

  @override
  void onLoad(ModuleHost host) {
    final configDocument = host.docs.open<ModerationConfig>(
      'moderation/config.json',
      decode: ModerationConfigMapper.fromJson,
      encode: (v) => const JsonEncoder.withIndent('  ').convert(v.toMap()),
      create: ModerationConfig.new,
    );
    final checked = configDocument.value.checked();
    for (final problem in checked.problems) {
      host.log.warn('moderation/config.json: $problem');
    }
    configDocument.save(); // Creates the file so owners can edit it.
    final config = checked.config;

    final service = ModerationService(
      log: host.docs.open<PunishmentLog>(
        'moderation/punishments.json',
        decode: PunishmentLogMapper.fromJson,
        encode: (v) => v.toJson(),
        create: PunishmentLog.new,
      ),
      protectedPlayers: host.docs.open<ProtectedPlayers>(
        'moderation/protected.json',
        decode: ProtectedPlayersMapper.fromJson,
        encode: (v) => v.toJson(),
        create: ProtectedPlayers.new,
      ),
      players: host.services.require<PlayerDirectory>(),
      clock: host.clock,
      config: config,
    );
    host.services.provide<ModerationApi>(service);

    final messages = ModerationMessages(
      host.messages(moderationMessages, prefix: moderationPrefix),
      appeal: config.appeal,
    );
    final enforcement = Enforcement(
      service: service,
      messages: messages,
      clock: host.clock,
      log: host.log,
    );
    _host = host;
    _enforcement = enforcement;

    ModerationCommands(
      service: service,
      messages: messages,
      enforcement: enforcement,
      clock: host.clock,
    ).register(host.context);
    _enforceBans(host, service, messages, enforcement);
    _trackPlayers(host, service, enforcement);
    _routeChat(host, service, messages, enforcement, config);
    host.context.every(
      Duration(seconds: config.sweepSeconds),
      (server) => _sweep(server, service, messages, enforcement),
    );

    host.log.info(
      'Moderation loaded: ${service.activePunishments().length} mutes and '
      'bans in force.',
    );
  }

  /// Bans are enforced when a player logs in: the login event can be
  /// cancelled with a kick message, so a banned player never enters the world.
  /// As a backstop for a login the check let through, the join event checks
  /// again and kicks.
  void _enforceBans(
    ModuleHost host,
    ModerationService service,
    ModerationMessages messages,
    Enforcement enforcement,
  ) {
    host.context.intercept(Events.playerLogin, (server, event) {
      final ban = service.activeBan(event.player.uuidString);
      if (ban == null) return event;
      host.log.info(
        'Turned away ${event.player.getName()}: banned (#${ban.id})',
      );
      return event.copyWith(
        kickMessage: Messages.component(
          messages.banScreen(ban, host.clock.now()),
        ),
        cancelled: true,
      );
    });

    host.context.listen(Events.playerJoin, (server, event) {
      final player = event.player;
      final ban = service.activeBan(player.uuidString);
      if (ban != null) {
        host.log.warn(
          '${player.getName()} joined despite a ban (#${ban.id}), kicking',
        );
        enforcement.kick(player, messages.banScreen(ban, host.clock.now()));
      }
    });
  }

  /// Keeps what depends on who is online up to date: protection of staff,
  /// vanish, staff chat membership.
  void _trackPlayers(
    ModuleHost host,
    ModerationService service,
    Enforcement enforcement,
  ) {
    host.context.listen(Events.playerJoin, (server, event) {
      final player = event.player;
      service.setProtected(
        player.uuidString,
        player.hasPermission(node: ModerationPerms.exempt.node),
      );
      enforcement.hideVanishedFrom(server);
    });

    // Intercepted, not just listened to: a vanished player leaves silently
    // by cancelling the leave message.
    host.context.intercept(Events.playerLeave, (server, event) {
      final player = event.player;
      final uuid = player.uuidString;
      service.setProtected(
        uuid,
        player.hasPermission(node: ModerationPerms.exempt.node),
      );
      enforcement.staffChatMembers.remove(uuid);
      if (!service.isVanished(uuid)) return event;
      enforcement.setVanished(player, vanished: false);
      return event.cancel();
    });
  }

  /// Staff chat takes the messages of players who switched it on, and muted
  /// players cannot use the commands that would bypass their mute. Plain chat
  /// of muted players is the chat module's job, through [ModerationApi].
  void _routeChat(
    ModuleHost host,
    ModerationService service,
    ModerationMessages messages,
    Enforcement enforcement,
    ModerationConfig config,
  ) {
    // First in line, so the chat module never sees staff chat.
    host.context.intercept(Events.playerChat, (server, event) {
      final members = enforcement.staffChatMembers;
      final player = event.player;
      final uuid = player.uuidString;
      if (event.cancelled || !members.contains(uuid)) return event;
      if (!player.hasPermission(node: ModerationPerms.staffchat.node)) {
        members.remove(uuid);
        return event;
      }
      enforcement.sendStaffChat(server, player.getName(), event.message);
      return event.cancel();
    }, priority: EventPriority.highest);

    if (config.mutedCommands.isEmpty) return;
    host.context.intercept(Events.playerCommandSend, (server, event) {
      final command = service.mutedCommand(event.command);
      if (event.cancelled || command == null) return event;
      final mute = service.activeMuteRecord(event.player.uuidString);
      if (mute == null) return event;
      event.player.send(messages.mutedCommand(mute, host.clock.now(), command));
      return event.cancel();
    });
  }

  /// Cleans finished mutes and bans out of the indexes and tells players
  /// that their mute ended.
  void _sweep(
    Server server,
    ModerationService service,
    ModerationMessages messages,
    Enforcement enforcement,
  ) {
    for (final punishment in service.sweep()) {
      if (punishment.type != PunishmentType.mute) continue;
      enforcement
          .online(server, punishment.targetUuid)
          ?.send(messages.chat('target.muteExpired'));
    }
  }

  @override
  void onUnload() {
    final host = _host;
    final enforcement = _enforcement;
    if (host == null || enforcement == null) return;
    try {
      enforcement.showAllVanished(host.context.getServer());
    } catch (e) {
      host.log.warn('Could not show vanished players while unloading: $e');
    }
  }
}
