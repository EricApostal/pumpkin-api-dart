import '../core/permissions.dart';

/// Permission nodes of the moderation module. All of them are for operators
/// unless the server owner grants them.
abstract final class ModerationPerms {
  static const warn = PermNode(
    'commons:moderation.warn',
    'Warn players with /warn',
    PermDefault.op,
  );
  static const unwarn = PermNode(
    'commons:moderation.unwarn',
    'Take back warnings with /unwarn',
    PermDefault.op,
  );
  static const mute = PermNode(
    'commons:moderation.mute',
    'Mute players with /mute',
    PermDefault.op,
  );
  static const unmute = PermNode(
    'commons:moderation.unmute',
    'Unmute players with /unmute',
    PermDefault.op,
  );
  static const ban = PermNode(
    'commons:moderation.ban',
    'Ban players permanently with /ban',
    PermDefault.op,
  );
  static const tempban = PermNode(
    'commons:moderation.tempban',
    'Ban players for a while with /tempban',
    PermDefault.op,
  );
  static const unban = PermNode(
    'commons:moderation.unban',
    'Lift bans with /unban',
    PermDefault.op,
  );
  static const kick = PermNode(
    'commons:moderation.kick',
    'Kick players with /kick',
    PermDefault.op,
  );
  static const history = PermNode(
    'commons:moderation.history',
    'See the punishment history of a player with /history',
    PermDefault.op,
  );
  static const punishments = PermNode(
    'commons:moderation.punishments',
    'List recent and active punishments with /punishments',
    PermDefault.op,
  );
  static const checkban = PermNode(
    'commons:moderation.checkban',
    'Look up the ban, mute and warnings of a player with /checkban',
    PermDefault.op,
  );
  static const vanish = PermNode(
    'commons:moderation.vanish',
    'Hide from other players with /vanish',
    PermDefault.op,
  );
  static const staffchat = PermNode(
    'commons:moderation.staffchat',
    'Use the private staff chat with /staffchat',
    PermDefault.op,
  );
  static const notify = PermNode(
    'commons:moderation.notify',
    'Be told about every punishment and about staff going into vanish',
    PermDefault.op,
  );
  static const exempt = PermNode(
    'commons:moderation.exempt',
    'Cannot be warned, muted, banned or kicked (the console still can)',
    PermDefault.op,
  );

  static const all = [
    warn,
    unwarn,
    mute,
    unmute,
    ban,
    tempban,
    unban,
    kick,
    history,
    punishments,
    checkban,
    vanish,
    staffchat,
    notify,
    exempt,
  ];
}
