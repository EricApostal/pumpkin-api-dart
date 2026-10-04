import 'package:commons/src/core/api.dart';
import 'package:commons/src/core/clock.dart';
import 'package:commons/src/core/storage.dart';
import 'package:commons/src/mail/model.dart';
import 'package:commons/src/mail/service.dart';
import 'package:test/test.dart';

void main() {
  late FakeClock clock;
  late MemoryBackend backend;
  late Documents docs;
  late MuteInfo? mute;

  JsonDocument<MailData> open() => docs.open<MailData>(
    'mail/mail.json',
    decode: MailDataMapper.fromJson,
    encode: (v) => v.toJson(),
    create: MailData.new,
  );

  MailService service([MailConfig config = const MailConfig()]) => MailService(
    open(),
    clock,
    config: config,
    muteOf: (uuid) => uuid == 'muted' ? mute : null,
  );

  setUp(() {
    clock = FakeClock();
    backend = MemoryBackend();
    docs = Documents(backend, clock: clock);
    mute = const MuteInfo(reason: 'spam', until: null, by: 'Mod');
  });

  SendResult send(
    MailService mail, {
    String from = 'a',
    String to = 'b',
    String text = 'hi',
    bool bypass = false,
  }) => mail.send(
    fromUuid: from,
    fromName: 'Name-$from',
    toUuid: to,
    toName: 'Name-$to',
    text: text,
    bypassCooldown: bypass,
  );

  const noCooldown = MailConfig(sendCooldownSeconds: 0);

  group('sending and reading', () {
    test('delivers, newest first, with unread count', () {
      final mail = service(noCooldown);
      expect(send(mail, text: 'first').isSent, isTrue);
      clock.advance(const Duration(minutes: 1));
      send(mail, text: 'second', from: 'c');

      final inbox = mail.inbox('b');
      expect([for (final m in inbox) m.text], ['second', 'first']);
      expect(inbox.first.fromName, 'Name-c');
      expect(inbox.last.sentAt, DateTime.utc(2026, 1, 1));
      expect(mail.unreadCount('b'), 2);
      expect(mail.unreadCount('a'), 0);
      expect(mail.inbox('nobody'), isEmpty);
    });

    test('reading marks a message as read, once', () {
      final mail = service(noCooldown);
      final id = send(mail).message!.id;
      send(mail, text: 'other');

      expect(mail.find('b', id)!.read, isFalse);
      expect(mail.read('b', id)!.read, isTrue);
      expect(mail.unreadCount('b'), 1);
      expect(mail.read('b', id)!.read, isTrue);
      expect(mail.read('b', 999), isNull);
      expect(mail.read('somebody else', id), isNull);
    });

    test('cleans the text', () {
      final mail = service(noCooldown);
      final message = send(
        mail,
        text: '  §hello\n\tthere   you\u0000 ',
      ).message!;
      expect(message.text, 'hello there you');
      expect(cleanMailText('§§'), '');
    });
  });

  group('limits', () {
    test('empty, too long and self', () {
      final mail = service(
        const MailConfig(maxMessageLength: 5, sendCooldownSeconds: 0),
      );
      expect(send(mail, text: ' §  ').failure, SendFailure.empty);
      expect(send(mail, text: '123456').failure, SendFailure.tooLong);
      expect(send(mail, text: '12345').isSent, isTrue);
      expect(send(mail, to: 'a').failure, SendFailure.toSelf);
      expect(mail.inboxSize('b'), 1);
    });

    test('a full inbox refuses mail until something is deleted', () {
      final mail = service(
        const MailConfig(maxInboxSize: 2, sendCooldownSeconds: 0),
      );
      send(mail);
      final second = send(mail).message!;
      final full = send(mail, from: 'c');
      expect(full.failure, SendFailure.inboxFull);
      expect(mail.inboxSize('b'), 2);

      mail.delete('b', second.id);
      expect(send(mail, from: 'c').isSent, isTrue);
    });

    test('cooldown per sender, failures do not start it', () {
      final mail = service(const MailConfig(sendCooldownSeconds: 30));
      expect(send(mail, text: ' ').failure, SendFailure.empty);
      expect(send(mail).isSent, isTrue);

      final blocked = send(mail, to: 'c');
      expect(blocked.failure, SendFailure.cooldown);
      expect(blocked.wait, const Duration(seconds: 30));
      expect(send(mail, from: 'x').isSent, isTrue);
      expect(send(mail, to: 'c', bypass: true).isSent, isTrue);

      clock.advance(const Duration(seconds: 29));
      expect(mail.cooldownLeft('a'), const Duration(seconds: 1));
      expect(send(mail, to: 'c').failure, SendFailure.cooldown);
      clock.advance(const Duration(seconds: 1));
      expect(mail.cooldownLeft('a'), isNull);
      expect(send(mail, to: 'c').isSent, isTrue);
    });

    test('a full inbox does not start the cooldown', () {
      final mail = service(
        const MailConfig(maxInboxSize: 0, sendCooldownSeconds: 30),
      );
      expect(send(mail).failure, SendFailure.inboxFull);
      expect(mail.cooldownLeft('a'), isNull);
    });

    test('muted senders cannot send', () {
      final mail = service(noCooldown);
      final result = send(mail, from: 'muted');
      expect(result.failure, SendFailure.muted);
      expect(result.mute!.reason, 'spam');
      expect(mail.inboxSize('b'), 0);

      mute = null;
      expect(send(mail, from: 'muted').isSent, isTrue);
    });
  });

  group('ids and deleting', () {
    test('ids are never reused', () {
      final mail = service(noCooldown);
      final ids = [for (var i = 0; i < 3; i++) send(mail).message!.id];
      expect(ids, [1, 2, 3]);

      expect(mail.delete('b', 2), isTrue);
      expect(mail.delete('b', 2), isFalse);
      expect([for (final m in mail.inbox('b')) m.id], [3, 1]);
      expect(send(mail).message!.id, 4);

      mail.deleteAll('b');
      expect(send(mail).message!.id, 5);
    });

    test('delete read and delete all', () {
      final mail = service(noCooldown);
      for (var i = 0; i < 4; i++) {
        send(mail);
      }
      mail.read('b', 1);
      mail.read('b', 3);

      expect(mail.deleteRead('b'), 2);
      expect([for (final m in mail.inbox('b')) m.id], [4, 2]);
      expect(mail.deleteRead('b'), 0);
      expect(mail.deleteAll('b'), 2);
      expect(mail.inboxSize('b'), 0);
      expect(mail.deleteAll('b'), 0);
    });

    test("one player cannot delete another's mail", () {
      final mail = service(noCooldown);
      final id = send(mail).message!.id;
      expect(mail.delete('a', id), isFalse);
      expect(mail.inboxSize('b'), 1);
    });
  });

  group('outbox', () {
    test('is bounded, newest first, and reports what happened', () {
      final mail = service(
        const MailConfig(sentHistorySize: 2, sendCooldownSeconds: 0),
      );
      final first = send(mail, text: 'one').message!;
      send(mail, text: 'two');
      send(mail, text: 'three', to: 'c');

      final sent = mail.sent('a');
      expect([for (final s in sent) s.text], ['three', 'two']);
      expect(mail.sent('b'), isEmpty);
      expect(mail.statusOf(sent[0]), SentStatus.unread);
      expect(mail.statusOf(sent[1]), SentStatus.unread);

      mail.read('b', sent[1].id);
      expect(mail.statusOf(sent[1]), SentStatus.read);
      mail.delete('b', sent[1].id);
      expect(mail.statusOf(sent[1]), SentStatus.deleted);
      expect(first.id, 1);
    });

    test('a history size of zero keeps nothing', () {
      final mail = service(
        const MailConfig(sentHistorySize: 0, sendCooldownSeconds: 0),
      );
      expect(send(mail).isSent, isTrue);
      expect(mail.sent('a'), isEmpty);
    });
  });

  group('blocking', () {
    test('a blocked sender cannot send, unblocking restores it', () {
      final mail = service(noCooldown);
      expect(mail.block('b', 'a'), isTrue);
      expect(mail.block('b', 'a'), isFalse);
      expect(mail.isBlocked('b', 'a'), isTrue);
      expect(mail.isBlocked('a', 'b'), isFalse);
      expect(mail.blockedBy('b'), ['a']);

      expect(send(mail).failure, SendFailure.blocked);
      expect(mail.inboxSize('b'), 0);
      expect(mail.sent('a'), isEmpty);
      expect(send(mail, from: 'c').isSent, isTrue);

      expect(mail.unblock('b', 'a'), isTrue);
      expect(mail.unblock('b', 'a'), isFalse);
      expect(mail.blockedBy('b'), isEmpty);
      expect(send(mail).isSent, isTrue);
    });

    test('blocks are ignored when blocking is turned off', () {
      final mail = service(
        const MailConfig(allowBlocking: false, sendCooldownSeconds: 0),
      );
      mail.block('b', 'a');
      expect(send(mail).isSent, isTrue);
    });
  });

  group('persistence', () {
    test('survives a restart', () {
      final first = service(noCooldown);
      send(first, text: 'keep me');
      send(first, text: 'read me', from: 'c');
      first.read('b', 2);
      first.block('b', 'x');
      docs.saveDirty();
      expect(backend.files.keys, contains('mail/mail.json'));

      docs = Documents(backend, clock: clock);
      final second = service(noCooldown);
      expect(
        [for (final m in second.inbox('b')) (m.id, m.text, m.read)],
        [(2, 'read me', true), (1, 'keep me', false)],
      );
      expect(second.inbox('b').first.sentAt, DateTime.utc(2026, 1, 1));
      expect(second.unreadCount('b'), 1);
      expect(second.isBlocked('b', 'x'), isTrue);
      expect(second.sent('a').single.toName, 'Name-b');
      expect(send(second, text: 'next').message!.id, 3);
    });

    test('the config reads missing keys as defaults', () {
      final config = MailConfigMapper.fromJson('{"maxInboxSize": 7}');
      expect(config.maxInboxSize, 7);
      expect(config.maxMessageLength, 256);
      expect(config.notifyOnJoin, isFalse);
      expect(config.sendCooldown, const Duration(seconds: 30));
    });
  });

  test('formatAgo', () {
    expect(formatAgo(const Duration(seconds: 20)), 'just now');
    expect(formatAgo(const Duration(minutes: 5, seconds: 59)), '5m ago');
    expect(formatAgo(const Duration(hours: 3, minutes: 59)), '3h ago');
    expect(formatAgo(const Duration(days: 2, hours: 23)), '2d ago');
  });
}
