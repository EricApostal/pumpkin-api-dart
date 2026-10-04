/// The rules of moderation: issuing, revoking and expiring punishments,
/// warning escalation, protection and the in-memory indexes the other modules
/// read. Plain Dart (no server bindings) so it is unit tested; the commands,
/// the login check and the messages live in the files that talk to the server.
library;

// Binding-free parts of pumpkin_api, so this file runs in `dart test`.
// ignore: implementation_imports
import 'package:pumpkin_api/src/message_format.dart' show MessageFormat;

import '../core/api.dart';
import '../core/clock.dart';
import '../core/players.dart';
import '../core/storage.dart';
import 'model.dart';
import 'span.dart';

/// Who issues a punishment or takes it back.
final class Actor {
  /// The player's UUID, [consoleId] or [autoId].
  final String uuid;
  final String name;

  const Actor(this.uuid, this.name);

  /// The console, rcon and command blocks.
  const Actor.console([this.name = 'Console']) : uuid = consoleId;

  /// The module itself, for the punishment that warning escalation hands out.
  const Actor.auto() : uuid = autoId, name = 'Auto-moderation';

  bool get isConsole => uuid == consoleId;
}

/// Who gets punished: a player that joined the server at least once.
final class Target {
  final String uuid;
  final String name;

  const Target(this.uuid, this.name);
}

/// Why a punishment was not issued.
enum Refusal {
  /// Staff cannot punish themselves.
  self,

  /// The target has `commons:moderation.exempt` and the issuer is not the
  /// console.
  protected,

  /// The target already has an active mute, see [IssueResult.existing].
  alreadyMuted,

  /// The target already has an active ban, see [IssueResult.existing].
  alreadyBanned,
}

/// The outcome of issuing a punishment.
final class IssueResult {
  /// The new record, `null` if the punishment was [refusal]ed.
  final Punishment? punishment;

  /// Why nothing happened.
  final Refusal? refusal;

  /// For [Refusal.alreadyMuted] and [Refusal.alreadyBanned]: the active one.
  final Punishment? existing;

  /// For a warning that was the last straw: the automatic punishment that
  /// followed.
  final Punishment? escalation;

  const IssueResult.issued(Punishment this.punishment, {this.escalation})
    : refusal = null,
      existing = null;

  const IssueResult.refused(Refusal this.refusal, {this.existing})
    : punishment = null,
      escalation = null;

  bool get isIssued => punishment != null;
}

/// Longest `/history`-style listing the service hands out at once.
const _recentLimit = 500;

/// Punishments, their history and the lookups used on hot paths (login and
/// chat). Every change is saved to disk right away.
final class ModerationService implements ModerationApi {
  final JsonDocument<PunishmentLog> _log;
  final JsonDocument<ProtectedPlayers> _protected;
  final PlayerDirectory _directory;
  final Clock _clock;

  /// Already passed through [ModerationConfig.checked].
  final ModerationConfig config;

  /// The active mute and ban of each player, by UUID, so the login and chat
  /// checks are a map lookup. Entries are dropped when they expire or are
  /// revoked.
  final Map<String, Punishment> _mutes = {};
  final Map<String, Punishment> _bans = {};

  /// Mutes and bans found expired by a lookup, reported by the next [sweep]
  /// so the player is still told.
  final List<Punishment> _expiredSeen = [];

  final Set<String> _protectedPlayers;
  final Set<String> _vanished = {};

  ModerationService({
    required JsonDocument<PunishmentLog> log,
    required JsonDocument<ProtectedPlayers> protectedPlayers,
    required PlayerDirectory players,
    required Clock clock,
    required this.config,
  }) : _log = log,
       _protected = protectedPlayers,
       _directory = players,
       _clock = clock,
       _protectedPlayers = {...protectedPlayers.value.players} {
    final now = clock.now();
    for (final record in log.value.records) {
      if (!record.isActiveAt(now)) continue;
      _indexFor(record.type)?[record.targetUuid] = record;
    }
  }

  Map<String, Punishment>? _indexFor(PunishmentType type) => switch (type) {
    PunishmentType.mute => _mutes,
    PunishmentType.ban => _bans,
    _ => null,
  };

  // -- Looking players up -----------------------------------------------------

  /// The player called [name] (case-insensitive) if they ever joined.
  Target? find(String name) {
    final record = _directory.byName(name);
    return record == null ? null : Target(record.uuid, record.name);
  }

  /// Every name the server knows, for tab completion.
  List<String> get knownNames => _directory.names;

  // -- Protection -------------------------------------------------------------

  /// Whether [uuid] cannot be punished by anyone but the console.
  bool isProtected(String uuid) => _protectedPlayers.contains(uuid);

  /// Remembers whether [uuid] has `commons:moderation.exempt`, so the
  /// protection also holds while they are offline.
  void setProtected(String uuid, bool value) {
    final changed = value
        ? _protectedPlayers.add(uuid)
        : _protectedPlayers.remove(uuid);
    if (changed) {
      _protected.value = ProtectedPlayers(
        players: _protectedPlayers.toList()..sort(),
      );
    }
  }

  // -- Issuing ----------------------------------------------------------------

  /// Records a warning. If it makes [ModerationConfig.escalationWarns] active
  /// warnings inside the window, the automatic punishment follows and is
  /// returned in [IssueResult.escalation].
  IssueResult warn(Actor issuer, Target target, {String? reason}) {
    final refusal = _refuse(issuer, target);
    if (refusal != null) return IssueResult.refused(refusal);
    final warning = _record(
      PunishmentType.warn,
      issuer,
      target,
      reason: reason,
      length: config.warnExpiryLength,
    );
    return IssueResult.issued(warning, escalation: _escalate(target));
  }

  /// Mutes [target] for [duration] (`null` is permanent).
  IssueResult mute(
    Actor issuer,
    Target target, {
    Duration? duration,
    String? reason,
  }) {
    final refusal = _refuse(issuer, target);
    if (refusal != null) return IssueResult.refused(refusal);
    final current = _activeIn(_mutes, target.uuid);
    if (current != null) {
      return IssueResult.refused(Refusal.alreadyMuted, existing: current);
    }
    return IssueResult.issued(
      _record(
        PunishmentType.mute,
        issuer,
        target,
        reason: reason,
        length: duration,
      ),
    );
  }

  /// Bans [target] for [duration] (`null` is permanent). Kicking them if they
  /// are online is up to the caller.
  IssueResult ban(
    Actor issuer,
    Target target, {
    Duration? duration,
    String? reason,
  }) {
    final refusal = _refuse(issuer, target);
    if (refusal != null) return IssueResult.refused(refusal);
    final current = _activeIn(_bans, target.uuid);
    if (current != null) {
      return IssueResult.refused(Refusal.alreadyBanned, existing: current);
    }
    return IssueResult.issued(
      _record(
        PunishmentType.ban,
        issuer,
        target,
        reason: reason,
        length: duration,
      ),
    );
  }

  /// Records a kick. Removing the player is up to the caller.
  IssueResult kick(Actor issuer, Target target, {String? reason}) {
    final refusal = _refuse(issuer, target);
    if (refusal != null) return IssueResult.refused(refusal);
    return IssueResult.issued(
      _record(PunishmentType.kick, issuer, target, reason: reason),
    );
  }

  Refusal? _refuse(Actor issuer, Target target) {
    if (issuer.uuid == target.uuid) return Refusal.self;
    if (!issuer.isConsole && isProtected(target.uuid)) return Refusal.protected;
    return null;
  }

  Punishment _record(
    PunishmentType type,
    Actor issuer,
    Target target, {
    required String? reason,
    Duration? length,
  }) {
    final now = _clock.now();
    final log = _log.value;
    final record = Punishment(
      id: log.nextId,
      type: type,
      targetUuid: target.uuid,
      targetName: target.name,
      issuerUuid: issuer.uuid,
      issuerName: issuer.name,
      reason: _cleanReason(reason),
      issuedAt: now,
      expiresAt: length == null ? null : now.add(length),
    );
    _log.value = PunishmentLog(
      nextId: log.nextId + 1,
      records: [...log.records, record],
    );
    _indexFor(type)?[target.uuid] = record;
    _log.save();
    return record;
  }

  /// One line, trimmed and cut to the configured length; the default reason
  /// when nothing is left.
  String _cleanReason(String? raw) {
    final text = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return config.defaultReason;
    final max = config.maxReasonLength;
    return text.length <= max ? text : '${text.substring(0, max - 3)}...';
  }

  // -- Escalation -------------------------------------------------------------

  /// Hands out the automatic punishment when [target] has enough active
  /// warnings. Warnings from before the player's last automatic punishment do
  /// not count again, and a player who is already muted (or banned) is left
  /// alone.
  Punishment? _escalate(Target target) {
    final threshold = config.escalationWarns;
    if (threshold <= 0) return null;
    final now = _clock.now();
    final window = config.escalationWindowLength;
    final since = window == null ? null : now.subtract(window);
    final records = _log.value.records;
    var lastAutomatic = 0;
    for (final record in records) {
      if (record.isAutomatic && record.targetUuid == target.uuid) {
        lastAutomatic = record.id;
      }
    }
    final count = records
        .where(
          (r) =>
              r.type == PunishmentType.warn &&
              r.targetUuid == target.uuid &&
              r.id > lastAutomatic &&
              r.isActiveAt(now) &&
              (since == null || !r.issuedAt.isBefore(since)),
        )
        .length;
    if (count < threshold) return null;

    final reason = MessageFormat.format(config.escalationReason, {
      'count': count,
      'window': window == null ? 'any time' : formatSpan(window),
    });
    const auto = Actor.auto();
    if (config.escalationAction == 'mute') {
      if (_activeIn(_mutes, target.uuid) != null) return null;
      return _record(
        PunishmentType.mute,
        auto,
        target,
        reason: reason,
        length: config.escalationLength,
      );
    }
    if (_activeIn(_bans, target.uuid) != null) return null;
    return _record(
      PunishmentType.ban,
      auto,
      target,
      reason: reason,
      length: config.escalationLength,
    );
  }

  // -- Revoking ---------------------------------------------------------------

  /// Takes back the active mute of [uuid]. Returns it, or `null` if there was
  /// none.
  Punishment? unmute(Actor by, String uuid) =>
      _revoke(by, (r) => r.type == PunishmentType.mute && r.targetUuid == uuid);

  /// Takes back the active ban of [uuid]. Returns it, or `null` if there was
  /// none.
  Punishment? unban(Actor by, String uuid) =>
      _revoke(by, (r) => r.type == PunishmentType.ban && r.targetUuid == uuid);

  /// Takes back the active warning [id] of [uuid], or the latest active one
  /// without [id]. Returns it, or `null` if there is no such warning.
  Punishment? unwarn(Actor by, String uuid, {int? id}) {
    final warnings = activeWarns(uuid);
    if (warnings.isEmpty) return null;
    final wanted = id ?? warnings.first.id;
    if (!warnings.any((r) => r.id == wanted)) return null;
    return _revoke(by, (r) => r.id == wanted);
  }

  Punishment? _revoke(Actor by, bool Function(Punishment record) test) {
    final now = _clock.now();
    final revoked = <Punishment>[];
    final records = <Punishment>[];
    for (final record in _log.value.records) {
      if (record.isActiveAt(now) && test(record)) {
        final updated = record.copyWith(revokedAt: now, revokedBy: by.name);
        revoked.add(updated);
        records.add(updated);
      } else {
        records.add(record);
      }
    }
    if (revoked.isEmpty) return null;
    final ids = {for (final record in revoked) record.id};
    _log.value = PunishmentLog(nextId: _log.value.nextId, records: records);
    _mutes.removeWhere((_, r) => ids.contains(r.id));
    _bans.removeWhere((_, r) => ids.contains(r.id));
    _log.save();
    return revoked.last;
  }

  // -- Looking punishments up -------------------------------------------------

  Punishment? _activeIn(Map<String, Punishment> index, String uuid) {
    final record = index[uuid];
    if (record == null) return null;
    if (record.isActiveAt(_clock.now())) return record;
    index.remove(uuid);
    _expiredSeen.add(record);
    return null;
  }

  /// The active ban of [uuid], if any. Expired bans are dropped on the way.
  Punishment? activeBan(String uuid) => _activeIn(_bans, uuid);

  /// The active mute of [uuid] as a record, if any.
  Punishment? activeMuteRecord(String uuid) => _activeIn(_mutes, uuid);

  @override
  MuteInfo? activeMute(String uuid) {
    final record = _activeIn(_mutes, uuid);
    if (record == null) return null;
    return MuteInfo(
      reason: record.reason,
      until: record.expiresAt,
      by: record.issuerName,
    );
  }

  /// The active warnings of [uuid], newest first.
  List<Punishment> activeWarns(String uuid) {
    final now = _clock.now();
    return [
      for (final record in _log.value.records.reversed)
        if (record.type == PunishmentType.warn &&
            record.targetUuid == uuid &&
            record.isActiveAt(now))
          record,
    ];
  }

  /// Everything [uuid] ever got, newest first.
  List<Punishment> history(String uuid) => [
    for (final record in _log.value.records.reversed)
      if (record.targetUuid == uuid) record,
  ];

  /// The latest punishments of everybody, newest first.
  List<Punishment> recent() =>
      _log.value.records.reversed.take(_recentLimit).toList();

  /// The mutes and bans in force right now, newest first.
  List<Punishment> activePunishments() {
    final now = _clock.now();
    return [
      for (final record in _log.value.records.reversed)
        if (record.type != PunishmentType.warn && record.isActiveAt(now))
          record,
    ];
  }

  /// Names (as they were when punished) of the players with an active
  /// punishment of [type], for tab completion.
  List<String> namesWith(PunishmentType type) {
    final now = _clock.now();
    final names = <String>{
      for (final record in _log.value.records)
        if (record.type == type && record.isActiveAt(now)) record.targetName,
    };
    return names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  // -- Commands ---------------------------------------------------------------

  /// The name of the command in [line] (as typed, `msg Steve hi`, `/MSG` or
  /// `minecraft:msg`) if a muted player may not use it, otherwise `null`.
  String? mutedCommand(String line) {
    var word = line.trimLeft().split(RegExp(r'\s')).first.toLowerCase();
    if (word.startsWith('/')) word = word.substring(1);
    final colon = word.lastIndexOf(':');
    if (colon != -1) word = word.substring(colon + 1);
    return config.mutedCommands.contains(word) ? word : null;
  }

  // -- Expiry -----------------------------------------------------------------

  /// Drops the mutes and bans that ran out from the indexes and returns them
  /// (including the ones a lookup already dropped), so the players can be told.
  /// The history needs no update: [Punishment.statusAt] already reads them as
  /// expired the moment their time is up.
  List<Punishment> sweep() {
    final now = _clock.now();
    final expired = [..._expiredSeen];
    _expiredSeen.clear();
    for (final index in [_mutes, _bans]) {
      final done = [
        for (final entry in index.entries)
          if (!entry.value.isActiveAt(now)) entry.key,
      ];
      for (final uuid in done) {
        expired.add(index.remove(uuid)!);
      }
    }
    return expired;
  }

  // -- Vanish -----------------------------------------------------------------

  @override
  bool isVanished(String uuid) => _vanished.contains(uuid);

  /// Marks [uuid] as vanished or visible again. Only held in memory.
  void setVanished(String uuid, bool vanished) {
    if (vanished) {
      _vanished.add(uuid);
    } else {
      _vanished.remove(uuid);
    }
  }

  /// Everybody currently vanished.
  List<String> get vanished => _vanished.toList();
}
