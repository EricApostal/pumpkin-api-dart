/// Data of the moderation module: the config file, the punishment history and
/// the list of protected players. Plain dart_mappable classes, no server
/// bindings.
library;

import 'package:dart_mappable/dart_mappable.dart';

import 'span.dart';

part 'model.mapper.dart';

/// What kind of punishment a [Punishment] record is.
@MappableEnum()
enum PunishmentType {
  /// A recorded warning. Enough of them can trigger an automatic punishment.
  warn,

  /// The player cannot chat (the chat module asks `ModerationApi.activeMute`).
  mute,

  /// The player cannot join.
  ban,

  /// The player was removed from the server once. Kicks only live in history.
  kick,
}

/// Where a punishment stands, derived from its timestamps (never stored).
enum PunishmentStatus {
  /// Still in force.
  active,

  /// Ran out by itself, or happened once (a kick).
  expired,

  /// Taken back by a staff member.
  revoked,
}

/// Issuer id of the console (and of rcon and command blocks).
const consoleId = 'console';

/// Issuer id of punishments the module hands out by itself (warning
/// escalation).
const autoId = 'auto';

/// One entry of the punishment history, stored in `moderation/punishments.json`.
@MappableClass()
class Punishment with PunishmentMappable {
  /// Counts up from 1 and is never reused.
  final int id;
  final PunishmentType type;

  /// UUID of the punished player.
  final String targetUuid;

  /// The name the player had when they were punished.
  final String targetName;

  /// UUID of the staff member, [consoleId] or [autoId].
  final String issuerUuid;
  final String issuerName;
  final String reason;
  final DateTime issuedAt;

  /// When the punishment ends by itself, `null` if it never does.
  final DateTime? expiresAt;

  /// When a staff member took it back.
  final DateTime? revokedAt;

  /// The name of the staff member that took it back.
  final String? revokedBy;

  const Punishment({
    required this.id,
    required this.type,
    required this.targetUuid,
    required this.targetName,
    required this.issuerUuid,
    required this.issuerName,
    required this.reason,
    required this.issuedAt,
    this.expiresAt,
    this.revokedAt,
    this.revokedBy,
  });

  /// Whether this punishment can still be in force: warnings, mutes and bans
  /// that were not revoked and have not run out at [now]. A kick never is.
  bool isActiveAt(DateTime now) =>
      type != PunishmentType.kick &&
      revokedAt == null &&
      (expiresAt == null || now.isBefore(expiresAt!));

  /// [PunishmentStatus] at [now].
  PunishmentStatus statusAt(DateTime now) {
    if (revokedAt != null) return PunishmentStatus.revoked;
    return isActiveAt(now) ? PunishmentStatus.active : PunishmentStatus.expired;
  }

  /// How long it lasted when issued, `null` if permanent or instant.
  Duration? get length => expiresAt?.difference(issuedAt);

  /// Whether a staff member (and not the module itself) handed it out.
  bool get isAutomatic => issuerUuid == autoId;
}

/// The whole history. [nextId] is stored so ids stay unique even if records
/// are ever removed by hand.
@MappableClass()
class PunishmentLog with PunishmentLogMappable {
  final int nextId;

  /// Oldest first.
  final List<Punishment> records;

  const PunishmentLog({this.nextId = 1, this.records = const []});
}

/// Players that were protected (had `commons:moderation.exempt`) when they
/// last played, so they stay protected while offline. Stored in
/// `moderation/protected.json`.
@MappableClass()
class ProtectedPlayers with ProtectedPlayersMappable {
  final List<String> players;

  const ProtectedPlayers({this.players = const []});
}

/// Settings stored in `moderation/config.json`. Keys that are missing use the
/// defaults, and [checked] repairs values that make no sense.
///
/// Lengths are written like `30m`, `12h`, `7d`, `2w` or `1h30m`; `perm` means
/// forever.
@MappableClass()
class ModerationConfig with ModerationConfigMappable {
  /// Used when a punishment is issued without a reason.
  final String defaultReason;

  /// Shown at the bottom of the ban screen.
  final String appeal;

  /// Length of `/mute` without a duration.
  final String defaultMuteDuration;

  /// How long a warning stays active. `perm` keeps it forever.
  final String warnExpiry;

  /// This many active warnings inside [escalationWindow] punish the player
  /// automatically. `0` turns it off.
  final int escalationWarns;

  /// Only warnings issued this recently count towards [escalationWarns].
  /// `perm` counts every active warning.
  final String escalationWindow;

  /// What the automatic punishment is: `mute` or `tempban`.
  final String escalationAction;

  /// How long the automatic punishment lasts (`perm` is forever).
  final String escalationDuration;

  /// Reason of the automatic punishment, with `{count}` and `{window}`.
  final String escalationReason;

  /// Commands a muted player cannot use (without the slash), because they
  /// would get chat past the mute.
  final List<String> mutedCommands;

  /// How often finished mutes and bans are cleaned up, in seconds.
  final int sweepSeconds;

  /// Entries per page of `/history` and `/punishments`.
  final int pageSize;

  /// Reasons are cut to this many characters.
  final int maxReasonLength;

  const ModerationConfig({
    this.defaultReason = 'No reason given',
    this.appeal = 'If you think this is a mistake, contact the staff.',
    this.defaultMuteDuration = 'perm',
    this.warnExpiry = '30d',
    this.escalationWarns = 3,
    this.escalationWindow = '7d',
    this.escalationAction = 'mute',
    this.escalationDuration = '1h',
    this.escalationReason = 'Automatic: {count} warnings within {window}',
    this.mutedCommands = const [
      'msg',
      'tell',
      'w',
      'whisper',
      'r',
      'reply',
      'me',
      'say',
      'mail',
    ],
    this.sweepSeconds = 30,
    this.pageSize = 8,
    this.maxReasonLength = 200,
  });

  static const escalationActions = ['mute', 'tempban'];

  Duration? get defaultMuteLength => parseSpan(defaultMuteDuration)?.length;
  Duration? get warnExpiryLength => parseSpan(warnExpiry)?.length;
  Duration? get escalationWindowLength => parseSpan(escalationWindow)?.length;
  Duration? get escalationLength => parseSpan(escalationDuration)?.length;

  /// A [ModerationConfig] with every value usable, and what had to be
  /// repaired. Always read the lengths and the action from the result.
  ({ModerationConfig config, List<String> problems}) checked() {
    const defaults = ModerationConfig();
    final problems = <String>[];

    String span(String key, String value, String fallback) {
      if (parseSpan(value) != null) return value;
      problems.add(
        '$key "$value" is not a duration like 30m, 12h, 7d or perm, using $fallback',
      );
      return fallback;
    }

    int atLeast(String key, int value, int min, int max) {
      final fixed = value.clamp(min, max);
      if (fixed != value) {
        problems.add('$key $value is out of range, using $fixed');
      }
      return fixed;
    }

    var action = escalationAction.trim().toLowerCase();
    if (!escalationActions.contains(action)) {
      problems.add(
        'escalationAction "$escalationAction" must be one of ${escalationActions.join(', ')}, using mute',
      );
      action = 'mute';
    }
    String text(String key, String value, String fallback) {
      if (value.trim().isNotEmpty) return value;
      problems.add('$key is empty, using the default');
      return fallback;
    }

    return (
      config: ModerationConfig(
        defaultReason: text(
          'defaultReason',
          defaultReason,
          defaults.defaultReason,
        ),
        appeal: appeal,
        defaultMuteDuration: span(
          'defaultMuteDuration',
          defaultMuteDuration,
          defaults.defaultMuteDuration,
        ),
        warnExpiry: span('warnExpiry', warnExpiry, defaults.warnExpiry),
        escalationWarns: atLeast('escalationWarns', escalationWarns, 0, 1000),
        escalationWindow: span(
          'escalationWindow',
          escalationWindow,
          defaults.escalationWindow,
        ),
        escalationAction: action,
        escalationDuration: span(
          'escalationDuration',
          escalationDuration,
          defaults.escalationDuration,
        ),
        escalationReason: text(
          'escalationReason',
          escalationReason,
          defaults.escalationReason,
        ),
        mutedCommands: [
          for (final command in mutedCommands)
            if (command.trim().isNotEmpty)
              command.trim().toLowerCase().replaceFirst('/', ''),
        ],
        sweepSeconds: atLeast('sweepSeconds', sweepSeconds, 1, 3600),
        pageSize: atLeast('pageSize', pageSize, 1, 50),
        maxReasonLength: atLeast('maxReasonLength', maxReasonLength, 20, 1000),
      ),
      problems: problems,
    );
  }
}
