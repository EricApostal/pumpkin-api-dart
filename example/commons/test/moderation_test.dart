import 'dart:convert';

import 'package:commons/src/core/clock.dart';
import 'package:commons/src/core/players.dart';
import 'package:commons/src/core/storage.dart';
import 'package:commons/src/moderation/model.dart';
import 'package:commons/src/moderation/service.dart';
import 'package:commons/src/moderation/span.dart';
import 'package:pumpkin_api/src/pagination.dart';
import 'package:test/test.dart';

const steve = Target('uuid-steve', 'Steve');
const alex = Target('uuid-alex', 'Alex');
const mod = Actor('uuid-mod', 'Mod');
const console = Actor.console();

/// A service on in-memory storage that can be "restarted" over the same files.
final class Harness {
  final MemoryBackend backend = MemoryBackend();
  final FakeClock clock = FakeClock(DateTime.utc(2026, 3, 1, 12));
  final ModerationConfig config;
  late Documents docs;
  late PlayerDirectory players;
  late ModerationService service;

  Harness({this.config = const ModerationConfig()}) {
    start();
    players.touch(steve.uuid, steve.name);
    players.touch(alex.uuid, alex.name);
    players.touch(mod.uuid, mod.name);
  }

  /// Opens everything again from what was saved, like a server restart.
  void start() {
    docs = Documents(backend, clock: clock);
    players = PlayerDirectory(docs, clock);
    service = ModerationService(
      log: docs.open(
        'moderation/punishments.json',
        decode: PunishmentLogMapper.fromJson,
        encode: (v) => v.toJson(),
        create: PunishmentLog.new,
      ),
      protectedPlayers: docs.open(
        'moderation/protected.json',
        decode: ProtectedPlayersMapper.fromJson,
        encode: (v) => v.toJson(),
        create: ProtectedPlayers.new,
      ),
      players: players,
      clock: clock,
      config: config.checked().config,
    );
  }

  /// The saved punishments file, decoded.
  PunishmentLog get saved => PunishmentLogMapper.fromJson(
    backend.files['moderation/punishments.json']!,
  );
}

void main() {
  group('spans', () {
    test('perm and durations with units', () {
      expect(parseSpan('perm'), permanent);
      expect(parseSpan('Forever'), permanent);
      expect(parseSpan('7d')?.length, const Duration(days: 7));
      expect(parseSpan('12h')?.length, const Duration(hours: 12));
      expect(parseSpan('30m')?.length, const Duration(minutes: 30));
      expect(parseSpan('1h30m')?.length, const Duration(hours: 1, minutes: 30));
      expect(parseSpan('2w')?.length, const Duration(days: 14));
    });

    test(
      'refuses bare numbers, zero, nonsense, negatives and absurd lengths',
      () {
        for (final bad in [
          '5',
          '0m',
          '',
          'soon',
          '-5m',
          '10x',
          '99999999999999999999d',
          '999999d',
        ]) {
          expect(parseSpan(bad), isNull, reason: bad);
        }
      },
    );

    test('splits the duration off a mute command', () {
      expect(
        splitSpanAndReason('1h spamming chat').span?.length,
        const Duration(hours: 1),
      );
      expect(splitSpanAndReason('1h spamming chat').reason, 'spamming chat');
      expect(splitSpanAndReason('perm').span, permanent);
      expect(splitSpanAndReason('perm').reason, '');
      // No duration: everything is the reason, even a number of minutes.
      expect(splitSpanAndReason('5 minutes of quiet').span, isNull);
      expect(
        splitSpanAndReason('5 minutes of quiet').reason,
        '5 minutes of quiet',
      );
      expect(splitSpanAndReason(null).reason, '');
      expect(splitSpanAndReason('   ').span, isNull);
    });
  });

  group('muting', () {
    test('a temporary mute ends when the clock passes it', () {
      final h = Harness();
      final result = h.service.mute(
        mod,
        steve,
        duration: const Duration(hours: 1),
        reason: 'spam',
      );
      expect(result.isIssued, isTrue);
      final info = h.service.activeMute(steve.uuid)!;
      expect(info.reason, 'spam');
      expect(info.by, 'Mod');
      expect(info.until, h.clock.now().add(const Duration(hours: 1)));

      h.clock.advance(const Duration(minutes: 59, seconds: 59));
      expect(h.service.activeMute(steve.uuid), isNotNull);
      h.clock.advance(const Duration(seconds: 1));
      expect(
        h.service.activeMute(steve.uuid),
        isNull,
        reason: 'expires lazily on check',
      );
    });

    test('a permanent mute never ends', () {
      final h = Harness();
      h.service.mute(mod, steve);
      h.clock.advance(const Duration(days: 365 * 50));
      expect(h.service.activeMute(steve.uuid)!.until, isNull);
    });

    test('other players are not muted', () {
      final h = Harness();
      h.service.mute(mod, steve);
      expect(h.service.activeMute(alex.uuid), isNull);
      expect(h.service.activeMute('unknown'), isNull);
    });

    test('muting twice is refused until the mute is lifted', () {
      final h = Harness();
      h.service.mute(mod, steve, duration: const Duration(hours: 1));
      final again = h.service.mute(mod, steve);
      expect(again.refusal, Refusal.alreadyMuted);
      expect(again.existing!.id, 1);
      h.service.unmute(mod, steve.uuid);
      expect(h.service.mute(mod, steve).isIssued, isTrue);
    });

    test('an expired mute can be replaced', () {
      final h = Harness();
      h.service.mute(mod, steve, duration: const Duration(minutes: 1));
      h.clock.advance(const Duration(minutes: 2));
      expect(h.service.mute(mod, steve).isIssued, isTrue);
    });

    test('unmute revokes it and records who did', () {
      final h = Harness();
      h.service.mute(mod, steve);
      h.clock.advance(const Duration(minutes: 5));
      final revoked = h.service.unmute(
        const Actor('uuid-admin', 'Admin'),
        steve.uuid,
      )!;
      expect(revoked.revokedBy, 'Admin');
      expect(revoked.revokedAt, h.clock.now());
      expect(h.service.activeMute(steve.uuid), isNull);
      expect(h.service.unmute(mod, steve.uuid), isNull);
      expect(
        h.service.history(steve.uuid).single.statusAt(h.clock.now()),
        PunishmentStatus.revoked,
      );
    });
  });

  group('banning', () {
    test('ban, check and unban', () {
      final h = Harness();
      expect(h.service.activeBan(steve.uuid), isNull);
      final ban = h.service.ban(mod, steve, reason: 'griefing').punishment!;
      expect(h.service.activeBan(steve.uuid)!.id, ban.id);
      expect(h.service.ban(mod, steve).refusal, Refusal.alreadyBanned);
      expect(h.service.unban(mod, steve.uuid)!.id, ban.id);
      expect(h.service.activeBan(steve.uuid), isNull);
      expect(h.service.unban(mod, steve.uuid), isNull);
    });

    test('a tempban ends by itself and history shows it as expired', () {
      final h = Harness();
      h.service.ban(mod, steve, duration: const Duration(days: 7));
      h.clock.advance(const Duration(days: 6));
      expect(h.service.activeBan(steve.uuid), isNotNull);
      h.clock.advance(const Duration(days: 1));
      expect(h.service.activeBan(steve.uuid), isNull);
      expect(
        h.service.history(steve.uuid).single.statusAt(h.clock.now()),
        PunishmentStatus.expired,
      );
    });

    test('bans and mutes are independent', () {
      final h = Harness();
      h.service.ban(mod, steve);
      expect(h.service.activeMute(steve.uuid), isNull);
      expect(h.service.mute(mod, steve).isIssued, isTrue);
      h.service.unban(mod, steve.uuid);
      expect(h.service.activeMute(steve.uuid), isNotNull);
    });
  });

  group('kicks', () {
    test('are history only', () {
      final h = Harness();
      final kick = h.service.kick(mod, steve, reason: 'afk').punishment!;
      expect(kick.type, PunishmentType.kick);
      expect(kick.isActiveAt(h.clock.now()), isFalse);
      expect(h.service.activePunishments(), isEmpty);
      expect(h.service.history(steve.uuid), hasLength(1));
    });
  });

  group('reasons', () {
    test('blank ones use the configured default', () {
      final h = Harness(
        config: const ModerationConfig(defaultReason: 'Breaking the rules'),
      );
      expect(
        h.service.warn(mod, steve).punishment!.reason,
        'Breaking the rules',
      );
      expect(
        h.service.warn(mod, steve, reason: '   \n ').punishment!.reason,
        'Breaking the rules',
      );
    });

    test('are one trimmed line cut to the maximum length', () {
      final h = Harness(config: const ModerationConfig(maxReasonLength: 30));
      expect(
        h.service
            .kick(mod, steve, reason: '  too\n many   spaces ')
            .punishment!
            .reason,
        'too many spaces',
      );
      final long = h.service
          .kick(mod, steve, reason: 'x' * 100)
          .punishment!
          .reason;
      expect(long, hasLength(30));
      expect(long.endsWith('...'), isTrue);
    });
  });

  group('protection', () {
    test('nobody punishes themselves', () {
      final h = Harness();
      const self = Target('uuid-mod', 'Mod');
      for (final result in [
        h.service.warn(mod, self),
        h.service.mute(mod, self),
        h.service.ban(mod, self),
        h.service.kick(mod, self),
      ]) {
        expect(result.refusal, Refusal.self);
      }
      expect(h.service.recent(), isEmpty);
    });

    test('protected players cannot be punished, except by the console', () {
      final h = Harness();
      h.service.setProtected(steve.uuid, true);
      expect(h.service.isProtected(steve.uuid), isTrue);
      expect(h.service.warn(mod, steve).refusal, Refusal.protected);
      expect(h.service.mute(mod, steve).refusal, Refusal.protected);
      expect(h.service.ban(mod, steve).refusal, Refusal.protected);
      expect(h.service.kick(mod, steve).refusal, Refusal.protected);
      expect(h.service.ban(console, steve).isIssued, isTrue);
      h.service.setProtected(steve.uuid, false);
      expect(h.service.warn(mod, steve).isIssued, isTrue);
    });

    test('protection is remembered across restarts', () {
      final h = Harness();
      h.service.setProtected(steve.uuid, true);
      h.docs.saveDirty();
      h.start();
      expect(h.service.isProtected(steve.uuid), isTrue);
      expect(h.service.isProtected(alex.uuid), isFalse);
    });
  });

  group('warnings', () {
    test('count towards escalation and expire', () {
      final h = Harness(
        config: const ModerationConfig(warnExpiry: '1d', escalationWarns: 0),
      );
      h.service.warn(mod, steve);
      h.service.warn(mod, steve);
      expect(h.service.activeWarns(steve.uuid), hasLength(2));
      h.clock.advance(const Duration(days: 1));
      expect(h.service.activeWarns(steve.uuid), isEmpty);
      expect(
        h.service.history(steve.uuid),
        hasLength(2),
        reason: 'expired warnings stay in history',
      );
    });

    test('warnExpiry perm keeps them', () {
      final h = Harness(
        config: const ModerationConfig(warnExpiry: 'perm', escalationWarns: 0),
      );
      final warning = h.service.warn(mod, steve).punishment!;
      expect(warning.expiresAt, isNull);
      h.clock.advance(const Duration(days: 3650));
      expect(h.service.activeWarns(steve.uuid), hasLength(1));
    });

    test('unwarn takes back the latest, or a given id', () {
      final h = Harness(config: const ModerationConfig(escalationWarns: 0));
      final first = h.service.warn(mod, steve).punishment!;
      h.service.warn(mod, steve);
      final third = h.service.warn(mod, steve).punishment!;
      expect(h.service.unwarn(mod, steve.uuid)!.id, third.id);
      expect(h.service.unwarn(mod, steve.uuid, id: first.id)!.id, first.id);
      expect(h.service.activeWarns(steve.uuid).map((w) => w.id), [2]);
      expect(
        h.service.unwarn(mod, steve.uuid, id: first.id),
        isNull,
        reason: 'already revoked',
      );
      expect(h.service.unwarn(mod, steve.uuid, id: 99), isNull);
      expect(h.service.unwarn(mod, alex.uuid), isNull);
    });

    test('unwarn does not touch other players or other punishment types', () {
      final h = Harness(config: const ModerationConfig(escalationWarns: 0));
      h.service.warn(mod, alex);
      final mute = h.service.mute(mod, steve).punishment!;
      expect(h.service.unwarn(mod, steve.uuid, id: mute.id), isNull);
      expect(h.service.unwarn(mod, steve.uuid, id: 1), isNull);
      expect(h.service.activeMute(steve.uuid), isNotNull);
    });
  });

  group('escalation', () {
    test('the third warning inside the window mutes', () {
      final h = Harness();
      expect(h.service.warn(mod, steve).escalation, isNull);
      expect(h.service.warn(mod, steve).escalation, isNull);
      final third = h.service.warn(mod, steve);
      final mute = third.escalation!;
      expect(mute.type, PunishmentType.mute);
      expect(mute.issuerUuid, autoId);
      expect(mute.isAutomatic, isTrue);
      expect(mute.length, const Duration(hours: 1));
      expect(mute.reason, 'Automatic: 3 warnings within 7d');
      expect(h.service.activeMute(steve.uuid)!.by, 'Auto-moderation');
    });

    test('warnings outside the window do not count', () {
      final h = Harness();
      h.service.warn(mod, steve);
      h.service.warn(mod, steve);
      h.clock.advance(const Duration(days: 8));
      expect(h.service.warn(mod, steve).escalation, isNull);
      expect(h.service.activeMute(steve.uuid), isNull);
      h.service.warn(mod, steve);
      expect(
        h.service.warn(mod, steve).escalation,
        isNotNull,
        reason: 'three inside the window again',
      );
    });

    test('the same warnings do not escalate twice', () {
      final h = Harness();
      for (var i = 0; i < 3; i++) {
        h.service.warn(mod, steve);
      }
      h.service.unmute(mod, steve.uuid);
      expect(
        h.service.warn(mod, steve).escalation,
        isNull,
        reason: 'only one warning since the last escalation',
      );
      h.service.warn(mod, steve);
      expect(h.service.warn(mod, steve).escalation, isNotNull);
    });

    test('a player who is already muted is left alone', () {
      final h = Harness();
      h.service.mute(mod, steve);
      for (var i = 0; i < 3; i++) {
        h.service.warn(mod, steve);
      }
      expect(
        h.service.history(steve.uuid).where((p) => p.isAutomatic),
        isEmpty,
      );
    });

    test('can tempban instead', () {
      final h = Harness(
        config: const ModerationConfig(
          escalationWarns: 2,
          escalationAction: 'tempban',
          escalationDuration: '3d',
        ),
      );
      h.service.warn(mod, steve);
      final ban = h.service.warn(mod, steve).escalation!;
      expect(ban.type, PunishmentType.ban);
      expect(ban.length, const Duration(days: 3));
      expect(h.service.activeBan(steve.uuid), isNotNull);
    });

    test('0 turns it off, and each player is counted separately', () {
      final off = Harness(config: const ModerationConfig(escalationWarns: 0));
      for (var i = 0; i < 10; i++) {
        expect(off.service.warn(mod, steve).escalation, isNull);
      }
      final h = Harness();
      h.service.warn(mod, steve);
      h.service.warn(mod, alex);
      h.service.warn(mod, steve);
      expect(h.service.warn(mod, alex).escalation, isNull);
    });

    test('revoked warnings do not count', () {
      final h = Harness();
      h.service.warn(mod, steve);
      h.service.warn(mod, steve);
      h.service.unwarn(mod, steve.uuid);
      expect(h.service.warn(mod, steve).escalation, isNull);
    });

    test(
      'a protected player can still be escalated when the console warns',
      () {
        final h = Harness();
        h.service.setProtected(steve.uuid, true);
        for (var i = 0; i < 2; i++) {
          h.service.warn(console, steve);
        }
        expect(h.service.warn(console, steve).escalation, isNotNull);
      },
    );
  });

  group('history and listings', () {
    test('history is newest first and only the players own', () {
      final h = Harness(config: const ModerationConfig(escalationWarns: 0));
      h.service.warn(mod, steve, reason: 'a');
      h.service.kick(mod, alex, reason: 'b');
      h.service.mute(mod, steve, reason: 'c');
      h.service.ban(mod, steve, reason: 'd');
      expect(h.service.history(steve.uuid).map((p) => p.reason), [
        'd',
        'c',
        'a',
      ]);
      expect(h.service.history(alex.uuid).map((p) => p.reason), ['b']);
      expect(h.service.history('nobody'), isEmpty);
      expect(h.service.recent().map((p) => p.id), [4, 3, 2, 1]);
    });

    test('feed the paginator with clamped page numbers', () {
      final h = Harness(config: const ModerationConfig(escalationWarns: 0));
      for (var i = 1; i <= 19; i++) {
        h.service.kick(mod, steve, reason: 'kick $i');
      }
      final pages = Paginator(
        h.service.history(steve.uuid),
        pageSize: h.service.config.pageSize,
      );
      expect(pages.pageCount, 3);
      expect(pages.page(1).items.first.reason, 'kick 19');
      expect(pages.page(3).items.map((p) => p.reason), [
        'kick 3',
        'kick 2',
        'kick 1',
      ]);
      expect(pages.page(0).number, 1);
      expect(pages.page(99).number, 3);
    });

    test('active listing has mutes and bans in force, newest first', () {
      final h = Harness();
      h.service.warn(mod, steve);
      h.service.ban(mod, steve, duration: const Duration(hours: 1));
      h.service.mute(mod, alex);
      h.service.kick(mod, alex);
      expect(h.service.activePunishments().map((p) => p.type), [
        PunishmentType.mute,
        PunishmentType.ban,
      ]);
      h.clock.advance(const Duration(hours: 2));
      expect(h.service.activePunishments().map((p) => p.type), [
        PunishmentType.mute,
      ]);
    });

    test('names for tab completion come from active punishments', () {
      final h = Harness(config: const ModerationConfig(escalationWarns: 0));
      h.service.mute(mod, steve, duration: const Duration(minutes: 1));
      h.service.mute(mod, alex);
      h.service.warn(mod, steve);
      expect(h.service.namesWith(PunishmentType.mute), ['Alex', 'Steve']);
      expect(h.service.namesWith(PunishmentType.warn), ['Steve']);
      expect(h.service.namesWith(PunishmentType.ban), isEmpty);
      h.clock.advance(const Duration(minutes: 2));
      expect(h.service.namesWith(PunishmentType.mute), ['Alex']);
    });

    test('players are found by name, any case', () {
      final h = Harness();
      expect(h.service.find('sTeVe')!.uuid, steve.uuid);
      expect(h.service.find('Nobody'), isNull);
      expect(h.service.knownNames, ['Alex', 'Mod', 'Steve']);
    });
  });

  group('sweeping', () {
    test('drops finished mutes and bans and reports them once', () {
      final h = Harness();
      h.service.mute(mod, steve, duration: const Duration(minutes: 10));
      h.service.ban(mod, alex, duration: const Duration(hours: 1));
      h.service.mute(mod, mod2, duration: null);
      expect(h.service.sweep(), isEmpty);
      h.clock.advance(const Duration(minutes: 30));
      expect(h.service.sweep().map((p) => p.targetName), ['Steve']);
      expect(h.service.sweep(), isEmpty);
      h.clock.advance(const Duration(hours: 1));
      expect(h.service.sweep().map((p) => p.targetName), ['Alex']);
      expect(h.service.activeMute(mod2.uuid), isNotNull);
    });

    test('also reports what a lookup already noticed', () {
      final h = Harness();
      h.service.mute(mod, steve, duration: const Duration(minutes: 1));
      h.clock.advance(const Duration(minutes: 2));
      expect(h.service.activeMute(steve.uuid), isNull);
      expect(h.service.sweep().map((p) => p.targetName), ['Steve']);
      expect(h.service.sweep(), isEmpty);
    });

    test('revoked punishments are not reported as expired', () {
      final h = Harness();
      h.service.mute(mod, steve, duration: const Duration(minutes: 1));
      h.service.unmute(mod, steve.uuid);
      h.clock.advance(const Duration(minutes: 2));
      expect(h.service.sweep(), isEmpty);
    });
  });

  group('persistence', () {
    test('is written right away, without waiting for the autosave', () {
      final h = Harness();
      h.service.ban(mod, steve, reason: 'griefing');
      expect(h.saved.records.single.reason, 'griefing');
      h.service.unban(mod, steve.uuid);
      expect(h.saved.records.single.revokedBy, 'Mod');
    });

    test('round trip keeps every field', () {
      final h = Harness();
      h.service.mute(
        mod,
        steve,
        duration: const Duration(hours: 2),
        reason: 'spam',
      );
      h.service.unmute(const Actor('uuid-admin', 'Admin'), steve.uuid);
      h.start();
      final record = h.service.history(steve.uuid).single;
      expect(record.id, 1);
      expect(record.type, PunishmentType.mute);
      expect(record.targetUuid, steve.uuid);
      expect(record.targetName, 'Steve');
      expect(record.issuerUuid, mod.uuid);
      expect(record.issuerName, 'Mod');
      expect(record.reason, 'spam');
      expect(record.issuedAt, DateTime.utc(2026, 3, 1, 12));
      expect(record.expiresAt, DateTime.utc(2026, 3, 1, 14));
      expect(record.revokedAt, DateTime.utc(2026, 3, 1, 12));
      expect(record.revokedBy, 'Admin');
    });

    test('the file has the documented shape', () {
      final h = Harness();
      h.service.ban(console, steve, reason: 'x');
      final json = jsonDecode(
        h.backend.files['moderation/punishments.json']!,
      ) as Map<String, dynamic>;
      final record = (json['records'] as List).single as Map<String, dynamic>;
      expect(record['type'], 'ban');
      expect(record['issuerUuid'], 'console');
      expect(record['targetUuid'], steve.uuid);
      expect(record['expiresAt'], isNull);
      expect(json['nextId'], 2);
    });

    test('ids keep counting after a reload', () {
      final h = Harness();
      expect(h.service.kick(mod, steve).punishment!.id, 1);
      expect(h.service.kick(mod, steve).punishment!.id, 2);
      h.start();
      expect(h.service.kick(mod, steve).punishment!.id, 3);
    });

    test('ids are never reused, even if the history was trimmed by hand', () {
      final h = Harness();
      h.service.kick(mod, steve);
      h.service.kick(mod, steve);
      final json = jsonDecode(
        h.backend.files['moderation/punishments.json']!,
      ) as Map<String, dynamic>;
      json['records'] = <Object?>[];
      h.backend.files['moderation/punishments.json'] = jsonEncode(json);
      h.start();
      expect(h.service.kick(mod, steve).punishment!.id, 3);
    });

    test('active mutes and bans are indexed again after a reload', () {
      final h = Harness();
      h.service.mute(mod, steve, duration: const Duration(hours: 1));
      h.service.ban(mod, alex);
      h.service.mute(mod, mod2, duration: const Duration(minutes: 1));
      h.service.unmute(mod, steve.uuid);
      h.clock.advance(const Duration(minutes: 5));
      h.start();
      expect(h.service.activeMute(steve.uuid), isNull, reason: 'revoked');
      expect(
        h.service.activeMute(mod2.uuid),
        isNull,
        reason: 'expired while down',
      );
      expect(h.service.activeBan(alex.uuid), isNotNull);
    });

    test('a corrupt history file is kept aside and replaced', () {
      final h = Harness();
      h.backend.files['moderation/punishments.json'] = '{not json';
      h.start();
      expect(h.service.recent(), isEmpty);
      expect(
        h.backend.files.keys.any(
          (k) => k.startsWith('moderation/punishments.json.corrupt-'),
        ),
        isTrue,
      );
      expect(h.service.kick(mod, steve).punishment!.id, 1);
    });
  });

  group('muted commands', () {
    test('are recognized however they are typed', () {
      final h = Harness();
      for (final line in [
        'msg Steve hi',
        '/msg Steve hi',
        'MSG',
        '  tell x',
        'minecraft:msg a b',
        '/me waves',
        'mail send x y',
      ]) {
        expect(h.service.mutedCommand(line), isNotNull, reason: line);
      }
      expect(h.service.mutedCommand('/msg Steve hi'), 'msg');
      expect(h.service.mutedCommand('minecraft:tell x'), 'tell');
    });

    test('other commands stay allowed', () {
      final h = Harness();
      for (final line in [
        'home',
        'warp spawn',
        'pay Steve 5',
        '',
        '/',
        'msgx',
      ]) {
        expect(h.service.mutedCommand(line), isNull, reason: line);
      }
    });

    test('follow the config', () {
      final h = Harness(
        config: const ModerationConfig(mutedCommands: ['Shout']),
      );
      expect(h.service.mutedCommand('shout hello'), 'shout');
      expect(h.service.mutedCommand('msg Steve'), isNull);
    });
  });

  group('vanish', () {
    test('is tracked in memory only', () {
      final h = Harness();
      expect(h.service.isVanished(mod.uuid), isFalse);
      h.service.setVanished(mod.uuid, true);
      expect(h.service.isVanished(mod.uuid), isTrue);
      expect(h.service.vanished, [mod.uuid]);
      h.service.setVanished(mod.uuid, false);
      expect(h.service.isVanished(mod.uuid), isFalse);
      h.service.setVanished(mod.uuid, true);
      h.start();
      expect(h.service.isVanished(mod.uuid), isFalse, reason: 'not persisted');
    });
  });

  group('config', () {
    test('defaults are valid', () {
      final checked = const ModerationConfig().checked();
      expect(checked.problems, isEmpty);
      expect(checked.config.defaultMuteLength, isNull);
      expect(checked.config.warnExpiryLength, const Duration(days: 30));
      expect(checked.config.escalationWindowLength, const Duration(days: 7));
      expect(checked.config.escalationLength, const Duration(hours: 1));
    });

    test('bad values are repaired and reported', () {
      final checked = const ModerationConfig(
        defaultReason: ' ',
        defaultMuteDuration: 'soon',
        warnExpiry: '5',
        escalationWarns: -3,
        escalationAction: 'explode',
        escalationDuration: '0m',
        sweepSeconds: 0,
        pageSize: 500,
        maxReasonLength: 1,
        mutedCommands: ['/MSG', ' ', 'Tell'],
      ).checked();
      final config = checked.config;
      expect(config.defaultReason, 'No reason given');
      expect(config.defaultMuteDuration, 'perm');
      expect(config.warnExpiry, '30d');
      expect(config.escalationWarns, 0);
      expect(config.escalationAction, 'mute');
      expect(config.escalationDuration, '1h');
      expect(config.sweepSeconds, 1);
      expect(config.pageSize, 50);
      expect(config.maxReasonLength, 20);
      expect(config.mutedCommands, ['msg', 'tell']);
      expect(checked.problems, hasLength(9));
    });

    test('missing keys use the defaults', () {
      final config = ModerationConfigMapper.fromJson('{"escalationWarns": 5}');
      expect(config.escalationWarns, 5);
      expect(config.warnExpiry, '30d');
      expect(config.mutedCommands, contains('msg'));
    });

    test('the default mute length applies to the command, not the service', () {
      final config = const ModerationConfig(defaultMuteDuration: '15m')
          .checked()
          .config;
      expect(config.defaultMuteLength, const Duration(minutes: 15));
    });
  });
}

const mod2 = Target('uuid-mod2', 'Mod2');
