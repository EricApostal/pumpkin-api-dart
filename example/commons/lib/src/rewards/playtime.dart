// ignore_for_file: prefer_initializing_formals
// (the public named parameters differ from the private fields)

import '../core/api.dart';
import '../core/clock.dart';
import '../core/players.dart';
import '../core/storage.dart';
import 'model.dart';

/// One place of the playtime list.
final class PlaytimeRank {
  final String uuid;

  /// The player's name, or the UUID for a player the server no longer knows.
  final String name;
  final Duration time;

  const PlaytimeRank(this.uuid, this.name, this.time);
}

/// A playtime milestone that was just paid to [uuid].
final class MilestonePayout {
  final String uuid;
  final PlaytimeMilestone milestone;

  /// The player's balance after the payment.
  final int balance;

  const MilestonePayout(this.uuid, this.milestone, this.balance);
}

/// Time online per player.
///
/// The service remembers, for everyone online, since when their time has not
/// been added to their total (a checkpoint). [join] starts it, [leave] adds
/// the time and ends it, and [tick] adds everyone's time and saves, so what a
/// crash can lose is at most one tick interval per player. [tick] is also
/// given the real list of online players: someone who is missing is dropped
/// without crediting more than was already counted, and someone not tracked
/// yet (the plugin was reloaded) starts being tracked.
///
/// Milestones are paid through [Economy] once per player when the total
/// reaches them. A payment that fails (balance full) is tried again at the
/// next tick.
final class PlaytimeService {
  final Economy _economy;
  final JsonDocument<PlaytimeFile> _doc;
  final PlayerDirectory _players;
  final Clock _clock;

  /// The (sanitized) settings.
  final PlaytimeConfig config;

  /// For each player online: the moment up to which their time is counted.
  final Map<String, DateTime> _checkpoints = {};

  PlaytimeService({
    required Economy economy,
    required JsonDocument<PlaytimeFile> doc,
    required PlayerDirectory players,
    required PlaytimeConfig config,
    required Clock clock,
  }) : _economy = economy,
       _doc = doc,
       _players = players,
       _clock = clock,
       config = config.sanitized();

  /// Whether [uuid] is being tracked as online.
  bool isTracking(String uuid) => _checkpoints.containsKey(uuid);

  /// [uuid] came online. Does nothing if they are tracked already.
  void join(String uuid) => _checkpoints.putIfAbsent(uuid, _clock.now);

  /// [uuid] went offline: their time is added and saved. Returns the
  /// milestones that were paid.
  List<MilestonePayout> leave(String uuid) {
    final payouts = _credit(uuid, _clock.now());
    _checkpoints.remove(uuid);
    _doc.save();
    return payouts;
  }

  /// Adds the time of everyone in [online] (UUIDs), starts tracking those that
  /// are new, stops tracking those that are gone, and saves. Returns the
  /// milestones that were paid.
  List<MilestonePayout> tick(Iterable<String> online) {
    final now = _clock.now();
    final present = online.toSet();
    _checkpoints.removeWhere((uuid, _) => !present.contains(uuid));
    final payouts = <MilestonePayout>[];
    for (final uuid in present) {
      if (_checkpoints.containsKey(uuid)) {
        payouts.addAll(_credit(uuid, now));
      } else {
        _checkpoints[uuid] = now;
      }
    }
    _doc.save();
    return payouts;
  }

  /// Adds and saves the time of everyone tracked, for when the plugin unloads.
  /// Tracking continues.
  void flush() {
    final now = _clock.now();
    for (final uuid in _checkpoints.keys.toList()) {
      _credit(uuid, now);
    }
    _doc.save();
  }

  /// Total time online, including the part of the current session that was
  /// not added up yet.
  Duration playtime(String uuid) {
    final stored = _doc.value.players[uuid]?.seconds ?? 0;
    final checkpoint = _checkpoints[uuid];
    final live = checkpoint == null
        ? 0
        : _clock.now().difference(checkpoint).inSeconds;
    return Duration(seconds: stored + (live > 0 ? live : 0));
  }

  /// The next milestone [uuid] has not reached yet, or `null`.
  PlaytimeMilestone? nextMilestone(String uuid) {
    final paid = _doc.value.players[uuid]?.paidMilestones ?? const [];
    final total = playtime(uuid);
    for (final milestone in config.milestones) {
      if (!paid.contains(milestone.minutes) &&
          total < Duration(minutes: milestone.minutes)) {
        return milestone;
      }
    }
    return null;
  }

  /// Everyone with playtime, longest first (equal times by name).
  List<PlaytimeRank> leaderboard() {
    final list = [
      for (final uuid in _doc.value.players.keys.toSet().union(
        _checkpoints.keys.toSet(),
      ))
        if (playtime(uuid) > Duration.zero)
          PlaytimeRank(uuid, _players.nameOf(uuid) ?? uuid, playtime(uuid)),
    ];
    list.sort((a, b) {
      final byTime = b.time.compareTo(a.time);
      if (byTime != 0) return byTime;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.uuid.compareTo(b.uuid);
    });
    return list;
  }

  /// Adds the whole seconds since the checkpoint of [uuid] to their total and
  /// pays the milestones that are reached. The checkpoint moves by exactly
  /// what was added, so no fraction of a second is lost. A clock that went
  /// backwards adds nothing and restarts the checkpoint.
  List<MilestonePayout> _credit(String uuid, DateTime now) {
    final checkpoint = _checkpoints[uuid];
    if (checkpoint == null) return const [];
    final seconds = now.difference(checkpoint).inSeconds;
    if (seconds < 0) {
      _checkpoints[uuid] = now;
    } else if (seconds > 0) {
      _checkpoints[uuid] = checkpoint.add(Duration(seconds: seconds));
      final entry = _doc.value.players[uuid] ?? const PlaytimeEntry();
      _put(
        uuid,
        PlaytimeEntry(
          seconds: entry.seconds + seconds,
          paidMilestones: entry.paidMilestones,
        ),
      );
    }
    return _payMilestones(uuid);
  }

  List<MilestonePayout> _payMilestones(String uuid) {
    final entry = _doc.value.players[uuid] ?? const PlaytimeEntry();
    final paid = [...entry.paidMilestones];
    final payouts = <MilestonePayout>[];
    for (final milestone in config.milestones) {
      if (paid.contains(milestone.minutes) ||
          entry.seconds < milestone.minutes * 60) {
        continue;
      }
      var balance = _economy.balance(uuid);
      if (milestone.currency > 0) {
        final payment = _economy.deposit(
          uuid,
          milestone.currency,
          reason: 'Playtime reward, ${milestone.minutes} minutes',
        );
        if (!payment.isOk) continue;
        balance = payment.balance;
      }
      paid.add(milestone.minutes);
      payouts.add(MilestonePayout(uuid, milestone, balance));
    }
    if (payouts.isNotEmpty) {
      _put(uuid, PlaytimeEntry(seconds: entry.seconds, paidMilestones: paid));
    }
    return payouts;
  }

  void _put(String uuid, PlaytimeEntry entry) {
    _doc.value = PlaytimeFile(players: {..._doc.value.players, uuid: entry});
  }
}

/// A duration for players: `3d 4h 12m`, `5m`, `42s`. Seconds only show below
/// a minute.
String formatPlaytime(Duration time) {
  final total = time.inSeconds;
  if (total < 60) return '${total < 0 ? 0 : total}s';
  final days = total ~/ 86400;
  final hours = total % 86400 ~/ 3600;
  final minutes = total % 3600 ~/ 60;
  return [
    if (days > 0) '${days}d',
    if (hours > 0) '${hours}h',
    if (minutes > 0 || (days == 0 && hours == 0)) '${minutes}m',
  ].join(' ');
}
