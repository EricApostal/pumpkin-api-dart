import 'dart:math';

import '../core/clock.dart';
import 'model.dart';

/// Picks which entry comes next, without repeating the one just shown.
final class Rotation {
  final Random _random;
  int? _last;

  Rotation({Random? random}) : _random = random ?? Random();

  /// The index of the next entry out of [count], or `null` if none of them is
  /// [eligible] (everything is eligible by default).
  ///
  /// In order, it continues after the previous index and skips ineligible
  /// entries. Shuffled, it picks any eligible entry except the previous one,
  /// unless that is the only one eligible.
  int? next(
    int count, {
    required bool shuffle,
    bool Function(int index)? eligible,
  }) {
    if (count <= 0) return null;
    bool ok(int index) => eligible?.call(index) ?? true;
    final last = _last;
    int? chosen;
    if (shuffle) {
      var candidates = [
        for (var i = 0; i < count; i++)
          if (ok(i)) i,
      ];
      if (candidates.length > 1) {
        candidates = [
          for (final i in candidates)
            if (i != last) i,
        ];
      }
      if (candidates.isNotEmpty) {
        chosen = candidates[_random.nextInt(candidates.length)];
      }
    } else {
      final start = last == null ? 0 : (last + 1) % count;
      for (var i = 0; i < count; i++) {
        final index = (start + i) % count;
        if (ok(index)) {
          chosen = index;
          break;
        }
      }
    }
    if (chosen != null) _last = chosen;
    return chosen;
  }

  /// Starts again from the beginning.
  void reset() => _last = null;
}

/// Names of worlds with the `minecraft:` prefix removed and lower case, so
/// `minecraft:overworld`, `Overworld` and `overworld` are the same world.
String normalizeWorld(String name) {
  final lower = name.trim().toLowerCase();
  return lower.startsWith('minecraft:') ? lower.substring(10) : lower;
}

/// Whether a player with [hasPermission] in [worldName] sees [announcement].
bool isVisibleTo(
  Announcement announcement, {
  required bool Function(String node) hasPermission,
  required String worldName,
}) {
  final permission = announcement.permission;
  if (permission != null &&
      permission.isNotEmpty &&
      !hasPermission(permission)) {
    return false;
  }
  final world = announcement.world;
  if (world != null && world.isNotEmpty) {
    return normalizeWorld(world) == normalizeWorld(worldName);
  }
  return true;
}

/// `14:05`: the time of day of [utc] moved by [offsetMinutes].
String formatClock(DateTime utc, int offsetMinutes) {
  final shifted = utc.toUtc().add(Duration(minutes: offsetMinutes));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(shifted.hour)}:${two(shifted.minute)}';
}

/// What is wrong with [config], one sentence each. Empty if it is fine.
List<String> configProblems(AnnouncementsConfig config) {
  final problems = <String>[];
  if (config.intervalSeconds < 5) {
    problems.add('intervalSeconds should be at least 5.');
  }
  if (config.displaySeconds < 1) {
    problems.add('displaySeconds should be at least 1.');
  }
  if (!bossBarColorNames.contains(config.bossBarColor.toLowerCase())) {
    problems.add(
      'bossBarColor "${config.bossBarColor}" is unknown, use one of '
      '${bossBarColorNames.join(', ')}.',
    );
  }
  for (final (i, a) in config.messages.indexed) {
    final entry = 'Message ${i + 1}';
    if (a.text.trim().isEmpty) problems.add('$entry has no text.');
    final hasCommand = a.command != null && a.command!.isNotEmpty;
    final hasUrl = a.url != null && a.url!.isNotEmpty;
    if (a.mode != AnnouncementMode.chat && (hasCommand || hasUrl)) {
      problems.add('$entry: click actions only work in chat mode.');
    }
    if (hasCommand && hasUrl) {
      problems.add(
        '$entry has both command and url, only the command is used.',
      );
    }
    if (hasUrl &&
        !a.url!.startsWith('http://') &&
        !a.url!.startsWith('https://')) {
      problems.add('$entry: url must start with http:// or https://.');
    }
  }
  return problems;
}

/// When to announce and what: the timer and the [Rotation] over the configured
/// messages. It never talks to the server; the caller asks [poll] regularly
/// (every second is enough) and shows what it returns.
final class AnnouncementService {
  final Clock _clock;
  final Rotation _rotation;
  AnnouncementsConfig _config;
  DateTime _lastRun;

  AnnouncementService(this._clock, this._config, {Random? random})
    : _rotation = Rotation(random: random),
      _lastRun = _clock.now();

  AnnouncementsConfig get config => _config;

  /// Replaces the configuration (on reload). The rotation starts over and the
  /// next announcement is due one interval from now.
  set config(AnnouncementsConfig value) {
    _config = value;
    _rotation.reset();
    _lastRun = _clock.now();
  }

  /// The announcement to show now if one is due, otherwise `null`.
  /// [hasAudience] says whether anybody would see an entry, so entries nobody
  /// can see are skipped. A due turn with nobody to show is used up.
  Announcement? poll({required bool Function(Announcement) hasAudience}) {
    if (!_config.enabled || _config.messages.isEmpty) return null;
    final now = _clock.now();
    if (now.difference(_lastRun) < _config.interval) return null;
    _lastRun = now;
    return _pick(hasAudience);
  }

  /// The next announcement right now, for `/announcements next`. The timer
  /// starts over.
  Announcement? next({required bool Function(Announcement) hasAudience}) {
    if (_config.messages.isEmpty) return null;
    _lastRun = _clock.now();
    return _pick(hasAudience);
  }

  Announcement? _pick(bool Function(Announcement) hasAudience) {
    final messages = _config.messages;
    final index = _rotation.next(
      messages.length,
      shuffle: _config.random,
      eligible: (i) => hasAudience(messages[i]),
    );
    return index == null ? null : messages[index];
  }
}
