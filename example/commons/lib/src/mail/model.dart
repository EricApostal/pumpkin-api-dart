import 'package:dart_mappable/dart_mappable.dart';

part 'model.mapper.dart';

/// Settings from `mail/config.json`. Missing keys use these defaults.
@MappableClass()
class MailConfig with MailConfigMappable {
  /// How many messages one inbox holds. A full inbox refuses new mail.
  final int maxInboxSize;

  /// The longest message, in characters (after cleaning).
  final int maxMessageLength;

  /// How long a player waits between two sent messages. `0` turns it off.
  final int sendCooldownSeconds;

  /// How many sent messages `/mail sent` remembers per player.
  final int sentHistorySize;

  /// Whether players may block each other (`/mail block`).
  final bool allowBlocking;

  /// Whether mail itself tells players about unread mail when they join.
  /// Off by default: the chat module's welcome summary does that. Turn it on
  /// if the chat module is not installed.
  final bool notifyOnJoin;

  /// Messages per page of `/mail`.
  final int pageSize;

  const MailConfig({
    this.maxInboxSize = 50,
    this.maxMessageLength = 256,
    this.sendCooldownSeconds = 30,
    this.sentHistorySize = 20,
    this.allowBlocking = true,
    this.notifyOnJoin = false,
    this.pageSize = 6,
  });

  Duration get sendCooldown => Duration(seconds: sendCooldownSeconds);
}

/// A message in an inbox. [id] is unique across the whole server and never
/// reused, so it stays valid when other messages are deleted.
@MappableClass()
class MailMessage with MailMessageMappable {
  final int id;

  /// The sender, as they were when the message was sent.
  final String fromUuid;
  final String fromName;

  final String text;
  final DateTime sentAt;
  final bool read;

  const MailMessage({
    required this.id,
    required this.fromUuid,
    required this.fromName,
    required this.text,
    required this.sentAt,
    this.read = false,
  });
}

/// An entry of a player's outbox. It shares its [id] with the message in the
/// recipient's inbox, which tells whether it was read (or deleted) since.
@MappableClass()
class SentMail with SentMailMappable {
  final int id;
  final String toUuid;
  final String toName;
  final String text;
  final DateTime sentAt;

  const SentMail({
    required this.id,
    required this.toUuid,
    required this.toName,
    required this.text,
    required this.sentAt,
  });
}

/// Everything in `mail/mail.json`.
@MappableClass()
class MailData with MailDataMappable {
  /// The id the next message gets.
  final int nextId;

  /// Inboxes by recipient UUID.
  final Map<String, List<MailMessage>> inboxes;

  /// Outboxes by sender UUID, oldest first.
  final Map<String, List<SentMail>> sent;

  /// The UUIDs each player blocked, by blocking player's UUID.
  final Map<String, List<String>> blocked;

  const MailData({
    this.nextId = 1,
    this.inboxes = const {},
    this.sent = const {},
    this.blocked = const {},
  });
}
