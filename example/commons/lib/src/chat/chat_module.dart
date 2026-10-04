import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/module.dart';
import '../core/permissions.dart';
import '../core/players.dart';
import 'commands.dart';
import 'listeners.dart';
import 'messages.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';

/// Chat formatting with ranks, mentions and anti-spam, private messages,
/// ignoring, join and leave messages and the welcome summary.
///
/// The welcome summary reads the optional services of the economy, mail and
/// rewards modules, so each part only appears when its module is installed.
final class ChatModule extends Module {
  @override
  String get name => 'chat';

  @override
  List<String> get dependsOn => const [
    'economy',
    'mail',
    'rewards',
    'moderation',
  ];

  @override
  List<PermNode> get permissions => ChatPerms.all;

  @override
  void onLoad(ModuleHost host) {
    final config = (host.docs.open<ChatConfig>(
      'chat/config.json',
      decode: ChatConfigMapper.fromJson,
      encode: (v) => v.toJson(),
      create: ChatConfig.new,
    )..save()).value;
    final service = ChatService(
      host.docs.open<IgnoreData>(
        'chat/ignores.json',
        decode: IgnoreDataMapper.fromJson,
        encode: (v) => v.toJson(),
        create: IgnoreData.new,
      ),
      host.clock,
      config,
    );
    _registerRankPermissions(host.context, config);

    final players = host.services.require<PlayerDirectory>();
    final messages = host.messages(chatMessages, prefix: '&8[&6Chat&8] &r');
    ChatListeners(
      service: service,
      players: players,
      messages: messages,
      services: host.services,
      clock: host.clock,
      log: host.log,
    ).register(host.context);
    ChatCommands(
      service: service,
      players: players,
      messages: messages,
      services: host.services,
      clock: host.clock,
    ).register(host.context);
  }

  /// Rank permissions of the configuration that the module doesn't declare
  /// itself are registered too, granted to nobody until a permission manager
  /// says otherwise.
  void _registerRankPermissions(Context context, ChatConfig config) {
    final known = {for (final perm in ChatPerms.all) perm.node};
    final extra = {
      for (final rank in config.ranks)
        if (rank.permission.isNotEmpty && !known.contains(rank.permission))
          rank.permission,
    };
    context.registerPermissions([
      for (final node in extra)
        PermissionNode(
          node,
          description: 'Chat rank from chat/config.json',
          defaultValue: PermissionDefaultKind.deny,
        ),
    ]);
  }
}
