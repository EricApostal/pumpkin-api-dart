import '../core/clock.dart';
import 'model.dart';

/// Why a message was refused.
enum SpamReason {
  /// Sent too soon after the previous one.
  tooFast,

  /// Too many messages in the time window.
  tooMany,

  /// The same message again.
  repeated,
}

/// The decision of [SpamGuard.check].
final class SpamVerdict {
  final SpamReason? reason;

  /// How long until the player may try again.
  final Duration wait;

  const SpamVerdict.allowed() : reason = null, wait = Duration.zero;
  const SpamVerdict.refused(SpamReason this.reason, this.wait);

  bool get allowed => reason == null;
}

/// The message in lower case without whitespace and ASCII punctuation, so
/// `Hello!!` and `hello` count as the same message. A message that is nothing
/// but punctuation falls back to its trimmed lower case.
String normalizeMessage(String message) {
  final kept = StringBuffer();
  for (final unit in message.toLowerCase().codeUnits) {
    final ignorable =
        unit <= 0x20 ||
        (unit >= 0x21 && unit <= 0x2f) ||
        (unit >= 0x3a && unit <= 0x40) ||
        (unit >= 0x5b && unit <= 0x60) ||
        (unit >= 0x7b && unit <= 0x7f);
    if (!ignorable) kept.writeCharCode(unit);
  }
  return kept.isEmpty ? message.trim().toLowerCase() : kept.toString();
}

final class _History {
  /// Accepted messages inside the rate window.
  final List<DateTime> window = [];
  DateTime? lastAt;
  String? lastText;
}

/// Rate limiting for chat: a minimum pause, a maximum number of messages per
/// window and a ban on repeating yourself. Plain Dart with an injected clock.
final class SpamGuard {
  final Clock _clock;
  final SpamConfig config;
  final Map<String, _History> _players = {};

  SpamGuard(this._clock, this.config);

  /// Checks [message] of [uuid] and, when it passes, records it. A refused
  /// message is not recorded, so waiting out [SpamVerdict.wait] is enough.
  SpamVerdict check(String uuid, String message) {
    if (!config.enabled) return const SpamVerdict.allowed();
    final now = _clock.now();
    final history = _players.putIfAbsent(uuid, _History.new);
    final span = Duration(seconds: config.windowSeconds);
    history.window.removeWhere((at) => !now.isBefore(at.add(span)));

    final lastAt = history.lastAt;
    if (lastAt != null) {
      final cooldown = Duration(milliseconds: config.cooldownMillis);
      final left = lastAt.add(cooldown).difference(now);
      if (left > Duration.zero) {
        return SpamVerdict.refused(SpamReason.tooFast, left);
      }
    }
    if (config.maxMessages > 0 && history.window.length >= config.maxMessages) {
      final left = history.window.first.add(span).difference(now);
      return SpamVerdict.refused(SpamReason.tooMany, left);
    }
    final text = normalizeMessage(message);
    if (lastAt != null && history.lastText == text) {
      final repeat = Duration(seconds: config.repeatSeconds);
      final left = lastAt.add(repeat).difference(now);
      if (left > Duration.zero) {
        return SpamVerdict.refused(SpamReason.repeated, left);
      }
    }
    history.window.add(now);
    history.lastAt = now;
    history.lastText = text;
    return const SpamVerdict.allowed();
  }

  /// Forgets [uuid], when they leave.
  void forget(String uuid) => _players.remove(uuid);
}
