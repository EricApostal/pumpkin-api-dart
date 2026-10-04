/// Every text the moderation module shows, and the formatting around it.
/// Binding-free, so the texts and layouts are unit tested.
library;

// Binding-free parts of pumpkin_api, so this file runs in `dart test`.
// ignore: implementation_imports
import 'package:pumpkin_api/src/command_help.dart' show formatDuration;
// ignore: implementation_imports
import 'package:pumpkin_api/src/message_format.dart'
    show MessageCatalog, MessageFormat;

import 'model.dart';
import 'span.dart';

/// Prefix of chat messages of the module.
const moderationPrefix = '&8[&cMod&8] &r';

/// Default texts. Server owners can change them in `messages/moderation.json`;
/// `{name}` marks a value filled in at runtime. Error texts (`issue.*`,
/// `revoke.*`, ...) are plain: the server shows them in red.
const moderationMessages = <String, String>{
  // Errors.
  'player.unknown': 'No player called "{name}" has joined this server yet.',
  'player.offline': '{name} is not online.',
  'issue.self': 'You cannot punish yourself.',
  'issue.protected': '{name} is protected and cannot be punished.',
  'issue.alreadyMuted':
      '{name} is already muted ({remaining}). Use /unmute first.',
  'issue.alreadyBanned':
      '{name} is already banned ({remaining}). Use /unban first.',
  'revoke.notMuted': '{name} is not muted.',
  'revoke.notBanned': '{name} is not banned.',
  'revoke.noWarning': '{name} has no active warning.',
  'revoke.warningNotFound': '{name} has no active warning #{id}.',
  'duration.invalid': '"{input}" is not a length of time. Use something like 30m, 12h, 7d, 2w or perm.',
  'duration.finite': 'A temporary ban needs a length like 12h or 7d. Use /ban for a permanent ban.',

  // Told to staff (and to the console).
  'notice.warn': '&e{issuer} &7warned &f{target}&7: &f{reason} &8(#{id})',
  'notice.mute':
      '&e{issuer} &7muted &f{target} &7{length}: &f{reason} &8(#{id})',
  'notice.ban':
      '&e{issuer} &7banned &f{target} &7{length}: &f{reason} &8(#{id})',
  'notice.kick': '&e{issuer} &7kicked &f{target}&7: &f{reason} &8(#{id})',
  'notice.unmute': '&e{issuer} &7unmuted &f{target}&7.',
  'notice.unban': '&e{issuer} &7unbanned &f{target}&7.',
  'notice.unwarn': '&e{issuer} &7took back warning #{id} of &f{target}&7.',
  'notice.vanish.on': '&e{player} &7is now vanished.',
  'notice.vanish.off': '&e{player} &7is visible again.',

  // Told to the punished player when they are online.
  'target.warn': '&c&lWarning &r&7from &e{issuer}&7: &f{reason} &8(active warnings: {count})',
  'target.mute': '&cYou were muted by &e{issuer} &c{length}: &f{reason}',
  'target.unmute': '&aYou were unmuted.',
  'target.muteExpired': '&aYour mute has ended. Please keep to the rules.',
  'mute.command': '&cYou are muted ({remaining}) and cannot use /{command}. &7Reason: &f{reason}',

  // Disconnect screens, no prefix.
  'screen.ban.permanent':
      '&c&lYou are permanently banned from this server\n\n'
      '&7Reason: &f{reason}\n'
      '&7Banned by: &f{issuer}\n'
      '&7Ban ID: &f#{id}\n\n'
      '&7{appeal}',
  'screen.ban.temporary':
      '&c&lYou are banned from this server\n\n'
      '&7Reason: &f{reason}\n'
      '&7Banned by: &f{issuer}\n'
      '&7Time left: &f{remaining}\n'
      '&7Ban ID: &f#{id}\n\n'
      '&7{appeal}',
  'screen.kick':
      '&c&lYou were kicked from the server\n\n'
      '&7Reason: &f{reason}\n'
      '&7Kicked by: &f{issuer}',

  // /history and /punishments.
  'history.title': 'Punishments of {name}',
  'history.empty': '&7{name} has a clean record.',
  'history.line':
      '&8#{id} {type} {status} &f{reason} &8- {issuer}, {age} ago{length}',
  'punishments.title.recent': 'Recent punishments',
  'punishments.title.active': 'Active mutes and bans',
  'punishments.empty.recent': '&7Nothing was punished yet.',
  'punishments.empty.active': '&7Nobody is muted or banned right now.',
  'punishments.line': '&8#{id} {type} &f{target} {status} &7{reason} &8- {issuer}, {age} ago{length}',
  'type.warn': '&eWARN',
  'type.mute': '&6MUTE',
  'type.ban': '&cBAN',
  'type.kick': '&7KICK',
  'status.active': '&c&lACTIVE',
  'status.expired': '&7expired',
  'status.revoked': '&arevoked by {by}',
  'status.done': '&7done',

  // /checkban.
  'check.header': '&6Moderation status of &e{name}&6:',
  'check.ban.none': '&7Ban: &anot banned',
  'check.ban.active':
      '&7Ban: &cbanned &8(#{id}) &7- &f{reason} &8- by {issuer}, {remaining}',
  'check.mute.none': '&7Mute: &anot muted',
  'check.mute.active':
      '&7Mute: &cmuted &8(#{id}) &7- &f{reason} &8- by {issuer}, {remaining}',
  'check.warns':
      '&7Active warnings: &e{count}&7, {total} punishments in total.',

  // /vanish and /staffchat.
  'vanish.on': '&aYou are vanished: invisible, off the tab list and silent when you leave. Run /vanish again to show yourself.',
  'vanish.off': '&7You are visible again.',
  'staffchat.on': '&aStaff chat is on: everything you type now only goes to staff. Run /staffchat to leave it.',
  'staffchat.off': '&7Staff chat is off.',
  'staffchat.line': '&8[&cStaff&8] &7{player}&8: &f{message}',
};

/// Turns punishments into the texts above. Player controlled values (names,
/// reasons) are escaped, so nobody can smuggle color codes or placeholders in.
final class ModerationMessages {
  final MessageCatalog catalog;

  /// Shown at the bottom of ban screens.
  final String appeal;

  ModerationMessages(this.catalog, {required this.appeal});

  /// [text] made safe to put into a template: color codes in it stay literal.
  static String escape(String text) => MessageFormat.escape(text);

  /// A text without the prefix, for screens and list lines.
  String plain(String key, [Map<String, Object?> values = const {}]) =>
      catalog[key].format(values);

  /// A chat message with the prefix.
  String chat(String key, [Map<String, Object?> values = const {}]) =>
      catalog.text(key, values);

  /// A plain error text for `CommandException`.
  String error(String key, [Map<String, Object?> values = const {}]) =>
      catalog[key].format(values);

  String _timeLeft(Punishment p, DateTime now) {
    final left = p.expiresAt!.difference(now);
    return left <= Duration.zero ? 'a moment' : formatDuration(left);
  }

  /// `permanent`, or `1d 2h left`, for a punishment at [now].
  String remaining(Punishment p, DateTime now) =>
      p.expiresAt == null ? 'permanent' : '${_timeLeft(p, now)} left';

  /// `permanently` or `for 1d 2h`, for what was just issued.
  String lengthPhrase(Punishment p) {
    final length = p.length;
    return length == null ? 'permanently' : 'for ${formatSpan(length)}';
  }

  // -- Screens ----------------------------------------------------------------

  /// What a banned player sees when they are turned away or removed.
  String banScreen(Punishment ban, DateTime now) => plain(
    ban.expiresAt == null ? 'screen.ban.permanent' : 'screen.ban.temporary',
    {
      'reason': escape(ban.reason),
      'issuer': escape(ban.issuerName),
      'remaining': ban.expiresAt == null ? 'permanent' : _timeLeft(ban, now),
      'id': ban.id,
      'appeal': appeal,
    },
  );

  /// What a kicked player sees.
  String kickScreen(Punishment kick) => plain('screen.kick', {
    'reason': escape(kick.reason),
    'issuer': escape(kick.issuerName),
  });

  // -- Staff and player notices -----------------------------------------------

  /// The line staff see when [p] was issued.
  String notice(Punishment p) => chat('notice.${p.type.name}', {
    'issuer': escape(p.issuerName),
    'target': escape(p.targetName),
    'reason': escape(p.reason),
    'length': lengthPhrase(p),
    'id': p.id,
  });

  /// The line staff see when [by] took back [p].
  String revokeNotice(Punishment p, String by) => chat(
    'notice.un${p.type.name}',
    {'issuer': escape(by), 'target': escape(p.targetName), 'id': p.id},
  );

  /// What the punished player is told, for warnings and mutes. [warnCount] is
  /// their active warnings including this one.
  String targetNotice(Punishment p, {int warnCount = 1}) =>
      chat('target.${p.type.name}', {
        'issuer': escape(p.issuerName),
        'reason': escape(p.reason),
        'length': lengthPhrase(p),
        'count': warnCount,
      });

  /// What a muted player sees when they try a blocked command.
  String mutedCommand(Punishment mute, DateTime now, String command) =>
      chat('mute.command', {
        'remaining': remaining(mute, now),
        'reason': escape(mute.reason),
        'command': escape(command),
      });

  // -- Lists -------------------------------------------------------------------

  String _type(Punishment p) => plain('type.${p.type.name}');

  String _status(Punishment p, DateTime now) {
    if (p.type == PunishmentType.kick) return plain('status.done');
    return switch (p.statusAt(now)) {
      PunishmentStatus.active => plain('status.active'),
      PunishmentStatus.expired => plain('status.expired'),
      PunishmentStatus.revoked => plain('status.revoked', {
        'by': escape(p.revokedBy ?? '?'),
      }),
    };
  }

  String _length(Punishment p) {
    final length = p.length;
    if (p.type == PunishmentType.kick) return '';
    return length == null ? ' &8[perm]' : ' &8[${formatSpan(length)}]';
  }

  /// One line of `/history`.
  String historyLine(Punishment p, DateTime now) => plain('history.line', {
    'id': p.id,
    'type': _type(p),
    'status': _status(p, now),
    'reason': escape(p.reason),
    'issuer': escape(p.issuerName),
    'age': formatAge(now.difference(p.issuedAt)),
    'length': _length(p),
  });

  /// One line of `/punishments`, which also names the player.
  String punishmentsLine(Punishment p, DateTime now) =>
      plain('punishments.line', {
        'id': p.id,
        'type': _type(p),
        'target': escape(p.targetName),
        'status': _status(p, now),
        'reason': escape(p.reason),
        'issuer': escape(p.issuerName),
        'age': formatAge(now.difference(p.issuedAt)),
        'length': _length(p),
      });

  /// The lines of `/checkban` for [name].
  List<String> check({
    required String name,
    required Punishment? ban,
    required Punishment? mute,
    required int activeWarns,
    required int totalPunishments,
    required DateTime now,
  }) {
    String line(String none, String active, Punishment? p) => p == null
        ? plain(none)
        : plain(active, {
            'id': p.id,
            'reason': escape(p.reason),
            'issuer': escape(p.issuerName),
            'remaining': remaining(p, now),
          });
    return [
      plain('check.header', {'name': escape(name)}),
      line('check.ban.none', 'check.ban.active', ban),
      line('check.mute.none', 'check.mute.active', mute),
      plain('check.warns', {'count': activeWarns, 'total': totalPunishments}),
    ];
  }
}

/// How long ago something was, with its two largest units: `5s`, `12m`,
/// `3h 20m`, `4d 6h`.
String formatAge(Duration age) {
  if (age < const Duration(minutes: 1)) {
    return '${age.inSeconds < 0 ? 0 : age.inSeconds}s';
  }
  final parts = <String>[];
  final days = age.inDays;
  final hours = age.inHours % 24;
  final minutes = age.inMinutes % 60;
  if (days > 0) parts.add('${days}d');
  if (hours > 0) parts.add('${hours}h');
  if (minutes > 0 && days == 0) parts.add('${minutes}m');
  return parts.take(2).join(' ');
}

/// `2026-01-31 14:05 UTC`, for hover texts and logs.
String formatTimestamp(DateTime time) {
  final t = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)} UTC';
}
