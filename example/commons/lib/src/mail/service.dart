import '../core/api.dart';
import '../core/clock.dart';
import '../core/storage.dart';
import 'model.dart';

/// Why a message was not sent.
enum SendFailure {
  /// Nothing left after cleaning the text.
  empty,
  tooLong,
  toSelf,

  /// The sender is muted, see [SendResult.mute].
  muted,

  /// The recipient blocked the sender. Show a neutral message.
  blocked,
  inboxFull,

  /// The sender must wait, see [SendResult.wait].
  cooldown,
}

/// The outcome of [MailService.send].
final class SendResult {
  /// The delivered message, or `null` if it failed.
  final MailMessage? message;
  final SendFailure? failure;

  /// For [SendFailure.cooldown]: how long until the next message.
  final Duration? wait;

  /// For [SendFailure.muted]: the mute.
  final MuteInfo? mute;

  const SendResult.sent(MailMessage this.message)
    : failure = null,
      wait = null,
      mute = null;

  const SendResult.failed(SendFailure this.failure, {this.wait, this.mute})
    : message = null;

  bool get isSent => message != null;
}

/// What happened to a sent message since.
enum SentStatus { unread, read, deleted }

/// Removes the section sign and control characters (which clients would
/// interpret as formatting) and collapses whitespace.
String cleanMailText(String input) => input
    .replaceAll('§', '')
    .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// A short "time since" for lists: `just now`, `5m`, `3h`, `2d`.
String formatAgo(Duration since) {
  if (since < const Duration(minutes: 1)) return 'just now';
  if (since < const Duration(hours: 1)) return '${since.inMinutes}m ago';
  if (since < const Duration(days: 1)) return '${since.inHours}h ago';
  return '${since.inDays}d ago';
}

/// Offline messaging between players: inboxes, outboxes, blocks and the
/// limits of `MailConfig`. Plain Dart, so it is unit tested without a server.
///
/// Players are identified by UUID. Changes go through the [JsonDocument], the
/// plugin saves it periodically and on unload.
final class MailService implements MailApi {
  final JsonDocument<MailData> _doc;
  final Clock _clock;
  final MuteInfo? Function(String uuid) _muteOf;
  final Map<String, DateTime> _lastSent = {};

  final MailConfig config;

  /// [muteOf] reports an active mute of a sender (muted players can't send).
  MailService(
    this._doc,
    this._clock, {
    this.config = const MailConfig(),
    this._muteOf = _noMutes,
  });

  static MuteInfo? _noMutes(String uuid) => null;

  MailData get _data => _doc.value;

  // -- Sending ---------------------------------------------------------------

  /// Delivers [text] from [fromUuid] to [toUuid]. Checks, in order: mute,
  /// empty or too long text, mailing yourself, the recipient's block list,
  /// the recipient's inbox size and the sender's cooldown ([bypassCooldown]
  /// skips only the last). A failed send changes nothing and does not start
  /// the cooldown.
  SendResult send({
    required String fromUuid,
    required String fromName,
    required String toUuid,
    required String toName,
    required String text,
    bool bypassCooldown = false,
  }) {
    final mute = _muteOf(fromUuid);
    if (mute != null) return SendResult.failed(SendFailure.muted, mute: mute);
    final clean = cleanMailText(text);
    if (clean.isEmpty) return const SendResult.failed(SendFailure.empty);
    if (clean.length > config.maxMessageLength) {
      return const SendResult.failed(SendFailure.tooLong);
    }
    if (fromUuid == toUuid) return const SendResult.failed(SendFailure.toSelf);
    if (config.allowBlocking && isBlocked(toUuid, fromUuid)) {
      return const SendResult.failed(SendFailure.blocked);
    }
    if (inboxSize(toUuid) >= config.maxInboxSize) {
      return const SendResult.failed(SendFailure.inboxFull);
    }
    if (!bypassCooldown) {
      final wait = cooldownLeft(fromUuid);
      if (wait != null) {
        return SendResult.failed(SendFailure.cooldown, wait: wait);
      }
    }

    final now = _clock.now();
    final data = _data;
    final message = MailMessage(
      id: data.nextId,
      fromUuid: fromUuid,
      fromName: fromName,
      text: clean,
      sentAt: now,
    );
    var outbox = [
      ...?data.sent[fromUuid],
      SentMail(
        id: message.id,
        toUuid: toUuid,
        toName: toName,
        text: clean,
        sentAt: now,
      ),
    ];
    if (outbox.length > config.sentHistorySize) {
      outbox = outbox.sublist(outbox.length - config.sentHistorySize);
    }
    _doc.value = data.copyWith(
      nextId: message.id + 1,
      inboxes: {
        ...data.inboxes,
        toUuid: [...?data.inboxes[toUuid], message],
      },
      sent: {...data.sent, if (outbox.isNotEmpty) fromUuid: outbox},
    );
    _lastSent[fromUuid] = now;
    return SendResult.sent(message);
  }

  /// How long [uuid] still has to wait before sending again, or `null`.
  Duration? cooldownLeft(String uuid) {
    final last = _lastSent[uuid];
    if (last == null) return null;
    final left = last.add(config.sendCooldown).difference(_clock.now());
    return left > Duration.zero ? left : null;
  }

  // -- Inbox -----------------------------------------------------------------

  /// The messages of [uuid], newest first.
  List<MailMessage> inbox(String uuid) =>
      [...?_data.inboxes[uuid]]..sort((a, b) => b.id.compareTo(a.id));

  int inboxSize(String uuid) => _data.inboxes[uuid]?.length ?? 0;

  @override
  int unreadCount(String uuid) =>
      _data.inboxes[uuid]?.where((m) => !m.read).length ?? 0;

  /// Message [id] of [uuid]'s inbox, or `null`.
  MailMessage? find(String uuid, int id) {
    for (final message in _data.inboxes[uuid] ?? const <MailMessage>[]) {
      if (message.id == id) return message;
    }
    return null;
  }

  /// Marks message [id] as read and returns it, or `null` if there is none.
  MailMessage? read(String uuid, int id) {
    final message = find(uuid, id);
    if (message == null || message.read) return message;
    final updated = message.copyWith(read: true);
    _setInbox(uuid, [
      for (final m in _data.inboxes[uuid]!) m.id == id ? updated : m,
    ]);
    return updated;
  }

  /// Deletes message [id]. Returns whether it existed.
  bool delete(String uuid, int id) {
    final inbox = _data.inboxes[uuid];
    if (inbox == null || !inbox.any((m) => m.id == id)) return false;
    _setInbox(uuid, [
      for (final m in inbox)
        if (m.id != id) m,
    ]);
    return true;
  }

  /// Deletes every message that was read. Returns how many.
  int deleteRead(String uuid) {
    final inbox = _data.inboxes[uuid] ?? const <MailMessage>[];
    final kept = [
      for (final m in inbox)
        if (!m.read) m,
    ];
    _setInbox(uuid, kept);
    return inbox.length - kept.length;
  }

  /// Deletes the whole inbox. Returns how many messages there were.
  int deleteAll(String uuid) {
    final count = inboxSize(uuid);
    _setInbox(uuid, const []);
    return count;
  }

  void _setInbox(String uuid, List<MailMessage> messages) {
    final inboxes = {..._data.inboxes};
    if (messages.isEmpty) {
      inboxes.remove(uuid);
    } else {
      inboxes[uuid] = messages;
    }
    _doc.value = _data.copyWith(inboxes: inboxes);
  }

  // -- Outbox ----------------------------------------------------------------

  /// What [uuid] sent recently, newest first.
  List<SentMail> sent(String uuid) => [...?_data.sent[uuid]].reversed.toList();

  /// Whether the recipient of [mail] read it, or deleted it.
  SentStatus statusOf(SentMail mail) {
    final message = find(mail.toUuid, mail.id);
    if (message == null) return SentStatus.deleted;
    return message.read ? SentStatus.read : SentStatus.unread;
  }

  // -- Blocking --------------------------------------------------------------

  /// Whether [blocker] blocked [sender].
  bool isBlocked(String blocker, String sender) =>
      _data.blocked[blocker]?.contains(sender) ?? false;

  /// The UUIDs [uuid] blocked.
  List<String> blockedBy(String uuid) => [...?_data.blocked[uuid]];

  /// Blocks [target]. Returns `false` if already blocked.
  bool block(String uuid, String target) {
    if (isBlocked(uuid, target)) return false;
    _doc.value = _data.copyWith(
      blocked: {
        ..._data.blocked,
        uuid: [...?_data.blocked[uuid], target],
      },
    );
    return true;
  }

  /// Unblocks [target]. Returns `false` if they were not blocked.
  bool unblock(String uuid, String target) {
    if (!isBlocked(uuid, target)) return false;
    final rest = [
      for (final other in _data.blocked[uuid]!)
        if (other != target) other,
    ];
    final blocked = {..._data.blocked};
    if (rest.isEmpty) {
      blocked.remove(uuid);
    } else {
      blocked[uuid] = rest;
    }
    _doc.value = _data.copyWith(blocked: blocked);
    return true;
  }
}
