import '../core/clock.dart';
import '../core/storage.dart';
import 'model.dart';
import 'spam.dart';

/// Who last talked privately with whom, for `/reply`. Both sides are
/// remembered; a player's entry is dropped when they leave.
final class Conversations {
  final Map<String, String> _partners = {};

  /// [a] and [b] are now each other's `/reply` target.
  void record(String a, String b) {
    _partners[a] = b;
    _partners[b] = a;
  }

  /// Only [from] is told: [to] never got the message (they ignore [from]), so
  /// their own `/reply` target does not change.
  void recordOneWay(String from, String to) => _partners[from] = to;

  /// Who [uuid] would reply to, or `null`.
  String? lastPartner(String uuid) => _partners[uuid];

  /// Forgets [uuid]'s own partner.
  void forget(String uuid) => _partners.remove(uuid);
}

/// The logic of the chat module that doesn't need the server: who ignores
/// whom (persisted), `/reply` partners, spies and the anti-spam guard.
final class ChatService {
  final JsonDocument<IgnoreData> _ignores;
  final Set<String> _spies = {};

  final ChatConfig config;
  final SpamGuard spam;
  final Conversations conversations = Conversations();

  ChatService(this._ignores, Clock clock, this.config)
    : spam = SpamGuard(clock, config.spam);

  // -- Ignoring --------------------------------------------------------------

  /// Whether [uuid] ignores [target].
  bool isIgnoring(String uuid, String target) =>
      _ignores.value.ignored[uuid]?.contains(target) ?? false;

  /// The UUIDs [uuid] ignores, in the order they were added.
  List<String> ignoredBy(String uuid) => [...?_ignores.value.ignored[uuid]];

  /// Ignores [target] (or stops ignoring them, if [ignoring] is `false`).
  /// Returns whether anything changed.
  bool setIgnoring(String uuid, String target, {required bool ignoring}) {
    final current = ignoredBy(uuid);
    if (current.contains(target) == ignoring) return false;
    final next = ignoring
        ? [...current, target]
        : [
            for (final other in current)
              if (other != target) other,
          ];
    final all = {..._ignores.value.ignored};
    if (next.isEmpty) {
      all.remove(uuid);
    } else {
      all[uuid] = next;
    }
    _ignores.value = IgnoreData(ignored: all);
    return true;
  }

  /// Whether [viewer] gets messages of [sender]. Senders [exempt] from
  /// ignoring (staff) always reach everybody.
  bool canSee({
    required String viewer,
    required String sender,
    bool exempt = false,
  }) => exempt || !isIgnoring(viewer, sender);

  // -- Spying ----------------------------------------------------------------

  bool isSpying(String uuid) => _spies.contains(uuid);

  /// Players currently spying.
  Set<String> get spies => Set.unmodifiable(_spies);

  /// Turns spying on or off (flips it without [on]). Returns the new state.
  bool setSpying(String uuid, {bool? on}) {
    final next = on ?? !_spies.contains(uuid);
    if (next) {
      _spies.add(uuid);
    } else {
      _spies.remove(uuid);
    }
    return next;
  }

  // -- Lifecycle -------------------------------------------------------------

  /// Drops everything remembered only for the session of [uuid].
  void playerLeft(String uuid) {
    conversations.forget(uuid);
    spam.forget(uuid);
    _spies.remove(uuid);
  }
}
