import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/api.dart';
import '../core/module.dart';
import '../core/permissions.dart';
import '../core/players.dart';
import 'commands.dart';
import 'messages.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';
import 'ui.dart';

/// Offline messaging: `/mail`. Provides [MailApi].
///
/// Mail only notifies players when a message arrives. The reminder about
/// unread mail on join belongs to the chat module's welcome summary, so
/// players are not told twice; set `notifyOnJoin` in `mail/config.json` to let
/// mail do it when the chat module is not installed.
final class MailModule extends Module {
  @override
  String get name => 'mail';

  /// Moderation loads first so muted players can be refused.
  @override
  List<String> get dependsOn => const ['moderation'];

  @override
  List<PermNode> get permissions => MailPerms.all;

  @override
  void onLoad(ModuleHost host) {
    final configDoc = host.docs.open<MailConfig>(
      'mail/config.json',
      decode: MailConfigMapper.fromJson,
      encode: (v) => v.toJson(),
      create: MailConfig.new,
    )..save();
    final config = configDoc.value;
    final data = host.docs.open<MailData>(
      'mail/mail.json',
      decode: MailDataMapper.fromJson,
      encode: (v) => v.toJson(),
      create: MailData.new,
    );

    final service = MailService(
      data,
      host.clock,
      config: config,
      muteOf: (uuid) => host.services.find<ModerationApi>()?.activeMute(uuid),
    );
    host.services.provide<MailApi>(service);

    final messages = host.messages(mailMessages, prefix: '&8[&6Mail&8] &r');
    MailCommands(
      service: service,
      players: host.services.require<PlayerDirectory>(),
      messages: messages,
      clock: host.clock,
    ).register(host.context);

    if (config.notifyOnJoin) {
      host.context.listen(Events.playerJoin, (server, event) {
        final uuid = event.player.uuidString;
        server.after(const Duration(seconds: 2), (server) {
          final unread = service.unreadCount(uuid);
          final player = onlinePlayer(server, uuid);
          if (unread > 0 && player != null) {
            notifyUnread(player, messages, unread);
          }
        });
      });
    }
    host.log.info('Mail ready: ${config.maxInboxSize} messages per inbox.');
  }
}
