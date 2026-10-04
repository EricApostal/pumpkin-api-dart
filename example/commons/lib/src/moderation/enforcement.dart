/// The server-facing half of moderation: finding players, removing them, and
/// telling staff. Everything here needs a running server, so the rules it
/// applies live in `service.dart`.
library;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/clock.dart';
import 'messages.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';

/// Sound played to players who are warned or muted.
const _warnSound = 'minecraft:block.note_block.bass';

/// Carries out punishments on online players and keeps staff informed.
final class Enforcement {
  final ModerationService service;
  final ModerationMessages messages;
  final Clock clock;
  final Logger log;

  /// Players whose chat goes to staff chat until they leave or toggle it off,
  /// by UUID.
  final Set<String> staffChatMembers = {};

  Enforcement({
    required this.service,
    required this.messages,
    required this.clock,
    required this.log,
  });

  // -- Finding players --------------------------------------------------------

  /// The online player with [uuid], or `null`.
  Player? online(Server server, String uuid) {
    final id = Uuids.tryParse(uuid);
    return id == null ? null : server.getPlayerByUuid(id: id);
  }

  /// Looks up the protection of [uuid] if they are online, so a permission
  /// that changed since they joined counts.
  void refreshProtection(Server server, String uuid) {
    final player = online(server, uuid);
    if (player != null) {
      service.setProtected(
        uuid,
        player.hasPermission(node: ModerationPerms.exempt.node),
      );
    }
  }

  // -- Acting on players --------------------------------------------------------

  /// Disconnects [player] with [screen] (legacy text with `&` codes).
  void kick(Player player, String screen) {
    final java = player.asJava();
    if (java != null) {
      java.kick(options: KickOptions.java(Messages.component(screen)));
      return;
    }
    player.asBedrock()?.kick(
      options: KickOptions.bedrock(message: MessageFormat.colorize(screen)),
    );
  }

  /// Carries out [punishment] on its target if they are online: a warning or
  /// mute is told to them, a ban or kick removes them.
  void enforce(Server server, Punishment punishment) {
    final player = online(server, punishment.targetUuid);
    if (player == null) return;
    final now = clock.now();
    switch (punishment.type) {
      case PunishmentType.warn:
        player.send(
          messages.targetNotice(
            punishment,
            warnCount: service.activeWarns(punishment.targetUuid).length,
          ),
        );
        _bestEffort('warning title', () {
          player.title(
            '&c&lWarning',
            subtitle: MessageFormat.escape(punishment.reason),
          );
          player.customSound(_warnSound);
        });
      case PunishmentType.mute:
        player.send(messages.targetNotice(punishment));
        _bestEffort('mute sound', () => player.customSound(_warnSound));
      case PunishmentType.ban:
        kick(player, messages.banScreen(punishment, now));
      case PunishmentType.kick:
        kick(player, messages.kickScreen(punishment));
    }
  }

  /// Runs a nicety (title, sound) whose failure must not undo the punishment.
  void _bestEffort(String what, void Function() action) {
    try {
      action();
    } catch (e) {
      log.warn('Could not show $what: $e');
    }
  }

  // -- Telling staff ------------------------------------------------------------

  /// Sends [line] to every online player who may see moderation notices
  /// (except [except]) and logs it. Returns the UUIDs that were told.
  Set<String> notifyStaff(Server server, String line, {String? except}) {
    final told = <String>{};
    for (final player in server.getAllPlayers()) {
      final uuid = player.uuidString;
      if (uuid == except) continue;
      if (!player.hasPermission(node: ModerationPerms.notify.node)) continue;
      player.send(line);
      told.add(uuid);
    }
    log.info(MessageFormat.stripColors(line));
    return told;
  }

  /// Tells staff about what [issuer] just did, and makes sure [issuer] sees
  /// it too: players with the notice permission got it with everybody else,
  /// the console and other players get it as the command's reply.
  void announce(
    Server server,
    CommandSender issuerSender,
    Actor issuer,
    String line,
  ) {
    final told = notifyStaff(server, line);
    if (!told.contains(issuer.uuid)) issuerSender.send(line);
  }

  // -- Staff chat ---------------------------------------------------------------

  /// Sends [message] from [sender] to every online player who may read staff
  /// chat, and logs it.
  void sendStaffChat(Server server, String sender, String message) {
    final line = messages.plain('staffchat.line', {
      'player': MessageFormat.escape(sender),
      'message': MessageFormat.escape(message),
    });
    for (final player in server.getAllPlayers()) {
      if (player.hasPermission(node: ModerationPerms.staffchat.node)) {
        player.send(line);
      }
    }
    log.info('[staff chat] $sender: $message');
  }

  // -- Vanish -------------------------------------------------------------------

  /// Hides [player] (or shows them again): invisible, and removed from the tab
  /// list. The host has no way to remove the entity for other players, see
  /// `docs/moderation.md`.
  void setVanished(Player player, {required bool vanished}) {
    service.setVanished(player.uuidString, vanished);
    _applyVanish(player, vanished);
  }

  void _applyVanish(Player player, bool vanished) {
    player.asEntity().setInvisible(invisible: vanished);
    player.setTabListListed(listed: !vanished);
  }

  /// Makes joining players drop the tab entries of the vanished again: the
  /// list is built when a player joins, so the unlisting is repeated.
  void hideVanishedFrom(Server server) {
    for (final uuid in service.vanished) {
      final player = online(server, uuid);
      if (player != null) player.setTabListListed(listed: false);
    }
  }

  /// Shows everybody who is still vanished, when the plugin unloads: a hidden
  /// player must not stay invisible without the plugin that can undo it.
  void showAllVanished(Server server) {
    for (final uuid in service.vanished) {
      final player = online(server, uuid);
      if (player != null) _applyVanish(player, false);
      service.setVanished(uuid, false);
    }
  }
}
