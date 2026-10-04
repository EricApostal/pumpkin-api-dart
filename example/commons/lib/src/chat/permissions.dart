import '../core/permissions.dart';

/// Permission nodes of the chat module.
abstract final class ChatPerms {
  static const msg = PermNode(
    'commons:chat.msg',
    'Send private messages with /msg and /reply',
  );
  static const ignore = PermNode(
    'commons:chat.ignore',
    'Ignore players with /ignore',
  );
  static const color = PermNode(
    'commons:chat.color',
    'Use & color codes in chat and private messages',
    PermDefault.op,
  );
  static const spy = PermNode(
    'commons:chat.spy',
    'See private messages with /spy',
    PermDefault.op,
  );
  static const bypass = PermNode(
    'commons:chat.bypass',
    'Skip the anti-spam checks',
    PermDefault.op,
  );
  static const ignoreExempt = PermNode(
    'commons:chat.ignore.exempt',
    "Can't be ignored: chat and messages always reach everybody",
    PermDefault.op,
  );
  static const seeVanished = PermNode(
    'commons:chat.seevanished',
    'Send private messages to vanished players',
    PermDefault.op,
  );

  /// The ranks of the default configuration.
  static const rankAdmin = PermNode(
    'commons:chat.rank.admin',
    'Shown as [Admin] in chat',
    PermDefault.op,
  );
  static const rankModerator = PermNode(
    'commons:chat.rank.moderator',
    'Shown as [Mod] in chat',
    PermDefault.nobody,
  );
  static const rankVip = PermNode(
    'commons:chat.rank.vip',
    'Shown as [VIP] in chat',
    PermDefault.nobody,
  );

  static const all = [
    msg,
    ignore,
    color,
    spy,
    bypass,
    ignoreExempt,
    seeVanished,
    rankAdmin,
    rankModerator,
    rankVip,
  ];
}
