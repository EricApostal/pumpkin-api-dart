import 'dart:io';

import 'package:commons/src/moderation/messages.dart';
import 'package:commons/src/moderation/model.dart';
import 'package:pumpkin_api/src/message_format.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 3, 1, 12);

Punishment record({
  int id = 7,
  PunishmentType type = PunishmentType.ban,
  String reason = 'griefing',
  String issuer = 'Mod',
  Duration? length,
  DateTime? issuedAt,
  DateTime? revokedAt,
  String? revokedBy,
}) {
  final at = issuedAt ?? now;
  return Punishment(
    id: id,
    type: type,
    targetUuid: 'u',
    targetName: 'Steve',
    issuerUuid: 'i',
    issuerName: issuer,
    reason: reason,
    issuedAt: at,
    expiresAt: length == null ? null : at.add(length),
    revokedAt: revokedAt,
    revokedBy: revokedBy,
  );
}

ModerationMessages messages({String appeal = 'Appeal at example.com'}) =>
    ModerationMessages(
      MessageCatalog(moderationMessages, prefix: moderationPrefix),
      appeal: appeal,
    );

void main() {
  group('screens', () {
    test('a permanent ban names reason, issuer, id and the appeal text', () {
      final text = messages().banScreen(record(), now);
      expect(text, contains('permanently banned'));
      expect(
        text,
        contains(
          'Reason: &f'
          'griefing',
        ),
      );
      expect(text, contains('Banned by: &fMod'));
      expect(text, contains('Ban ID: &f#7'));
      expect(text, contains('Appeal at example.com'));
      expect(text, isNot(contains('Time left')));
      expect(text.split('\n').length, greaterThan(5));
    });

    test('a temporary ban shows the time left', () {
      final ban = record(length: const Duration(days: 2));
      expect(messages().banScreen(ban, now), contains('Time left: &f2d'));
      expect(
        messages().banScreen(
          ban,
          now.add(const Duration(days: 1, hours: 23, minutes: 30)),
        ),
        contains('Time left: &f30m'),
      );
      expect(
        messages().banScreen(ban, now.add(const Duration(days: 3))),
        contains('a moment'),
      );
    });

    test('player controlled text cannot add colors or placeholders', () {
      final text = messages().banScreen(
        record(reason: '&4&lFAKE {appeal}', issuer: '&cEvil'),
        now,
      );
      expect(text, contains('&&4&&lFAKE {appeal}'));
      expect(text, contains('&&cEvil'));
      // After coloring, the ampersands are literal.
      expect(MessageFormat.colorize(text), contains('&4&lFAKE {appeal}'));
    });

    test('a kick screen has the reason and who kicked', () {
      final text = messages().kickScreen(record(type: PunishmentType.kick));
      expect(text, contains('kicked'));
      expect(text, contains('griefing'));
      expect(text, contains('Mod'));
    });
  });

  group('notices', () {
    test('every type has one, with its length phrase', () {
      final m = messages();
      expect(m.notice(record(type: PunishmentType.ban)), contains('banned'));
      expect(
        m.notice(record(type: PunishmentType.ban)),
        contains('permanently'),
      );
      expect(
        m.notice(
          record(
            type: PunishmentType.mute,
            length: const Duration(hours: 1, minutes: 30),
          ),
        ),
        contains('for 1h 30m'),
      );
      expect(m.notice(record(type: PunishmentType.warn)), contains('warned'));
      expect(m.notice(record(type: PunishmentType.kick)), contains('kicked'));
      expect(m.notice(record()), startsWith(moderationPrefix));
    });

    test('revoking says who took it back', () {
      final m = messages();
      expect(
        m.revokeNotice(record(type: PunishmentType.mute), 'Admin'),
        contains('Admin'),
      );
      expect(
        m.revokeNotice(record(type: PunishmentType.mute), 'Admin'),
        contains('unmuted'),
      );
      expect(m.revokeNotice(record(), 'Admin'), contains('unbanned'));
      expect(
        m.revokeNotice(record(type: PunishmentType.warn, id: 3), 'Admin'),
        contains('warning #3'),
      );
    });

    test('players are told what happened to them', () {
      final m = messages();
      expect(
        m.targetNotice(record(type: PunishmentType.warn), warnCount: 2),
        contains('active warnings: 2'),
      );
      expect(
        m.targetNotice(
          record(type: PunishmentType.mute, length: const Duration(minutes: 5)),
        ),
        contains('for 5m'),
      );
      final command = m.mutedCommand(
        record(type: PunishmentType.mute, length: const Duration(minutes: 5)),
        now,
        'msg',
      );
      expect(command, contains('/msg'));
      expect(command, contains('5m left'));
    });
  });

  group('lists', () {
    test(
      'a history line shows type, status, reason, issuer, age and length',
      () {
        final m = messages();
        final later = now.add(const Duration(hours: 3, minutes: 20));
        final active = m.historyLine(
          record(type: PunishmentType.mute, length: const Duration(days: 1)),
          later,
        );
        expect(active, contains('#7'));
        expect(active, contains('MUTE'));
        expect(active, contains('ACTIVE'));
        expect(active, contains('3h 20m ago'));
        expect(active, contains('[1d]'));

        final expired = m.historyLine(
          record(type: PunishmentType.ban, length: const Duration(hours: 1)),
          later,
        );
        expect(expired, contains('expired'));
        expect(expired, isNot(contains('ACTIVE')));

        final revoked = m.historyLine(
          record(revokedAt: later, revokedBy: 'Admin'),
          later,
        );
        expect(revoked, contains('revoked by Admin'));
        expect(revoked, contains('[perm]'));

        final kick = m.historyLine(record(type: PunishmentType.kick), later);
        expect(kick, contains('done'));
        expect(kick, isNot(contains('[')));
      },
    );

    test('a punishments line names the player', () {
      expect(messages().punishmentsLine(record(), now), contains('Steve'));
    });

    test('checkban lists ban, mute and warnings', () {
      final m = messages();
      final clean = m.check(
        name: 'Steve',
        ban: null,
        mute: null,
        activeWarns: 0,
        totalPunishments: 0,
        now: now,
      );
      expect(clean, hasLength(4));
      expect(clean[1], contains('not banned'));
      expect(clean[2], contains('not muted'));
      final dirty = m.check(
        name: 'Steve',
        ban: record(length: const Duration(days: 1)),
        mute: record(type: PunishmentType.mute),
        activeWarns: 2,
        totalPunishments: 5,
        now: now,
      );
      expect(dirty[1], contains('1d left'));
      expect(dirty[2], contains('permanent'));
      expect(dirty[3], contains('2'));
      expect(dirty[3], contains('5 punishments'));
    });
  });

  group('formatting', () {
    test('ages use their two largest units', () {
      expect(formatAge(const Duration(seconds: 5)), '5s');
      expect(formatAge(const Duration(seconds: -5)), '0s');
      expect(formatAge(const Duration(minutes: 12, seconds: 40)), '12m');
      expect(formatAge(const Duration(hours: 3, minutes: 20)), '3h 20m');
      expect(formatAge(const Duration(hours: 5)), '5h');
      expect(
        formatAge(const Duration(days: 4, hours: 6, minutes: 30)),
        '4d 6h',
      );
      expect(formatAge(const Duration(days: 40)), '40d');
    });

    test('timestamps are UTC', () {
      expect(
        formatTimestamp(DateTime.utc(2026, 1, 5, 9, 3)),
        '2026-01-05 09:03 UTC',
      );
    });
  });

  group('defaults', () {
    test('every message key the code uses exists', () {
      final used = <String>{};
      final call = RegExp(
        r"""(?:_fail|messages\.(?:chat|plain|error)|plain|chat|error)\(\s*'([a-z]+(?:\.[A-Za-z]+)+)'""",
      );
      for (final file in ['commands', 'enforcement', 'messages']) {
        final source = File('lib/src/moderation/$file.dart').readAsStringSync();
        used.addAll(call.allMatches(source).map((m) => m.group(1)!));
      }
      expect(used, isNotEmpty);
      expect(moderationMessages.keys, containsAll(used));
    });

    test('keys built from a type exist for every type', () {
      for (final type in PunishmentType.values) {
        expect(moderationMessages, contains('type.${type.name}'));
      }
      for (final type in [
        PunishmentType.warn,
        PunishmentType.mute,
        PunishmentType.ban,
        PunishmentType.kick,
      ]) {
        expect(moderationMessages, contains('notice.${type.name}'));
      }
      for (final name in ['unwarn', 'unmute', 'unban']) {
        expect(moderationMessages, contains('notice.$name'));
      }
      expect(moderationMessages, contains('target.warn'));
      expect(moderationMessages, contains('target.mute'));
      for (final key in [
        'status.active',
        'status.expired',
        'status.revoked',
        'status.done',
      ]) {
        expect(moderationMessages, contains(key));
      }
    });

    test('no template has an unknown placeholder left after rendering', () {
      final m = messages();
      final rendered = [
        m.banScreen(record(), now),
        m.banScreen(record(length: const Duration(hours: 1)), now),
        m.kickScreen(record(type: PunishmentType.kick)),
        m.notice(record()),
        m.targetNotice(record(type: PunishmentType.warn)),
        m.historyLine(record(), now),
        m.punishmentsLine(record(), now),
        ...m.check(
          name: 'x',
          ban: record(),
          mute: record(),
          activeWarns: 1,
          totalPunishments: 2,
          now: now,
        ),
      ];
      for (final text in rendered) {
        expect(text, isNot(matches(RegExp(r'\{[a-zA-Z]+\}'))), reason: text);
      }
    });
  });
}
