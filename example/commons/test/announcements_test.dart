import 'dart:math';

import 'package:commons/src/announcements/model.dart';
import 'package:commons/src/announcements/service.dart';
import 'package:commons/src/core/clock.dart';
import 'package:test/test.dart';

Announcement entry(
  String text, {
  String? permission,
  String? world,
  AnnouncementMode mode = AnnouncementMode.chat,
}) =>
    Announcement(text: text, permission: permission, world: world, mode: mode);

void main() {
  group('Rotation', () {
    test('goes through the entries in order and wraps', () {
      final rotation = Rotation();
      expect(
        [for (var i = 0; i < 7; i++) rotation.next(3, shuffle: false)],
        [0, 1, 2, 0, 1, 2, 0],
      );
    });

    test('skips entries that are not eligible and continues after them', () {
      final rotation = Rotation();
      bool eligible(int i) => i != 1;
      expect(
        [
          for (var i = 0; i < 4; i++)
            rotation.next(3, shuffle: false, eligible: eligible),
        ],
        [0, 2, 0, 2],
      );
    });

    test('reports nothing when no entry is eligible and keeps its place', () {
      final rotation = Rotation();
      expect(rotation.next(3, shuffle: false), 0);
      expect(rotation.next(3, shuffle: false, eligible: (_) => false), isNull);
      expect(rotation.next(3, shuffle: true, eligible: (_) => false), isNull);
      expect(rotation.next(3, shuffle: false), 1);
      expect(rotation.next(0, shuffle: false), isNull);
      expect(rotation.next(0, shuffle: true), isNull);
    });

    test('shuffled never repeats the previous entry and uses them all', () {
      final rotation = Rotation(random: Random(7));
      final picks = [
        for (var i = 0; i < 200; i++) rotation.next(4, shuffle: true)!,
      ];
      for (var i = 1; i < picks.length; i++) {
        expect(picks[i], isNot(picks[i - 1]));
      }
      expect(picks.toSet(), {0, 1, 2, 3});
    });

    test('shuffled repeats only when it is the one entry left', () {
      final rotation = Rotation(random: Random(1));
      expect(rotation.next(1, shuffle: true), 0);
      expect(rotation.next(1, shuffle: true), 0);
      bool onlyTwo(int i) => i == 2;
      expect(rotation.next(5, shuffle: true, eligible: onlyTwo), 2);
      expect(rotation.next(5, shuffle: true, eligible: onlyTwo), 2);
    });

    test('shuffled respects eligibility', () {
      final rotation = Rotation(random: Random(3));
      for (var i = 0; i < 50; i++) {
        expect(
          rotation.next(5, shuffle: true, eligible: (n) => n.isOdd),
          anyOf(1, 3),
        );
      }
    });

    test('reset starts from the beginning', () {
      final rotation = Rotation();
      rotation.next(3, shuffle: false);
      rotation.next(3, shuffle: false);
      rotation.reset();
      expect(rotation.next(3, shuffle: false), 0);
    });
  });

  group('visibility', () {
    Future<bool> allow(String node) async => node == 'vip';

    test('permission and world filters', () async {
      Future<bool> visible(
        Announcement a, {
        String world = 'minecraft:overworld',
      }) => isVisibleTo(a, hasPermission: allow, worldName: world);

      expect(await visible(entry('x')), isTrue);
      expect(await visible(entry('x', permission: '')), isTrue);
      expect(await visible(entry('x', permission: 'vip')), isTrue);
      expect(await visible(entry('x', permission: 'admin')), isFalse);
      expect(await visible(entry('x', world: 'overworld')), isTrue);
      expect(await visible(entry('x', world: 'Minecraft:Overworld')), isTrue);
      expect(await visible(entry('x', world: 'the_nether')), isFalse);
      expect(
        await visible(
          entry('x', world: 'the_nether'),
          world: 'minecraft:the_nether',
        ),
        isTrue,
      );
      expect(
        await visible(entry('x', permission: 'vip', world: 'the_end')),
        isFalse,
      );
    });

    test('normalizeWorld', () {
      expect(normalizeWorld(' minecraft:Overworld '), 'overworld');
      expect(normalizeWorld('my:world'), 'my:world');
    });
  });

  test('formatClock shifts and pads', () {
    final time = DateTime.utc(2026, 3, 1, 23, 5);
    expect(formatClock(time, 0), '23:05');
    expect(formatClock(time, 120), '01:05');
    expect(formatClock(time, -330), '17:35');
    expect(formatClock(DateTime.utc(2026, 1, 1, 9, 7), 0), '09:07');
  });

  group('configProblems', () {
    test('the default configuration is fine', () {
      expect(configProblems(const AnnouncementsConfig()), isEmpty);
    });

    test('names each problem', () {
      final problems = configProblems(
        AnnouncementsConfig(
          intervalSeconds: 1,
          displaySeconds: 0,
          bossBarColor: 'orange',
          messages: [
            const Announcement(text: ' '),
            const Announcement(
              text: 'a',
              mode: AnnouncementMode.bossbar,
              command: '/x',
            ),
            const Announcement(text: 'b', command: '/x', url: 'https://x.y'),
            const Announcement(text: 'c', url: 'ftp://x'),
          ],
        ),
      );
      expect(problems, [
        'intervalSeconds should be at least 5.',
        'displaySeconds should be at least 1.',
        contains('bossBarColor "orange"'),
        'Message 1 has no text.',
        'Message 2: click actions only work in chat mode.',
        'Message 3 has both command and url, only the command is used.',
        'Message 4: url must start with http:// or https://.',
      ]);
    });
  });

  group('AnnouncementService', () {
    late FakeClock clock;
    const config = AnnouncementsConfig(
      intervalSeconds: 60,
      messages: [
        Announcement(text: 'a'),
        Announcement(text: 'b'),
      ],
    );

    AnnouncementService service([AnnouncementsConfig c = config]) =>
        AnnouncementService(clock, c);

    Future<bool> everyone(Announcement a) async => true;

    setUp(() => clock = FakeClock());

    test('announces once per interval, in order', () async {
      final s = service();
      expect(await s.poll(hasAudience: everyone), isNull);
      clock.advance(const Duration(seconds: 59));
      expect(await s.poll(hasAudience: everyone), isNull);
      clock.advance(const Duration(seconds: 1));
      expect((await s.poll(hasAudience: everyone))!.text, 'a');
      expect(await s.poll(hasAudience: everyone), isNull);
      clock.advance(const Duration(seconds: 60));
      expect((await s.poll(hasAudience: everyone))!.text, 'b');
      clock.advance(const Duration(seconds: 60));
      expect((await s.poll(hasAudience: everyone))!.text, 'a');
    });

    test(
      'skips entries nobody can see, and uses up a turn with no audience',
      () async {
        final s = service();
        clock.advance(const Duration(seconds: 60));
        expect(
          (await s.poll(hasAudience: (a) async => a.text == 'b'))!.text,
          'b',
        );
        clock.advance(const Duration(seconds: 60));
        expect(await s.poll(hasAudience: (a) async => false), isNull);
        clock.advance(const Duration(seconds: 59));
        expect(await s.poll(hasAudience: everyone), isNull);
        clock.advance(const Duration(seconds: 1));
        expect((await s.poll(hasAudience: everyone))!.text, 'a');
      },
    );

    test('does nothing when disabled or empty', () async {
      clock.advance(const Duration(hours: 1));
      expect(
        await service(config.copyWith(enabled: false))
            .poll(hasAudience: everyone),
        isNull,
      );
      final empty = service(const AnnouncementsConfig(messages: []));
      expect(await empty.poll(hasAudience: everyone), isNull);
      expect(await empty.next(hasAudience: everyone), isNull);
    });

    test('next shows one now and restarts the timer', () async {
      final s = service();
      clock.advance(const Duration(seconds: 50));
      expect((await s.next(hasAudience: everyone))!.text, 'a');
      clock.advance(const Duration(seconds: 59));
      expect(await s.poll(hasAudience: everyone), isNull);
      clock.advance(const Duration(seconds: 1));
      expect((await s.poll(hasAudience: everyone))!.text, 'b');
    });

    test('next works while disabled', () async {
      final s = service(config.copyWith(enabled: false));
      expect((await s.next(hasAudience: everyone))!.text, 'a');
    });

    test('a new configuration starts the rotation over', () async {
      final s = service();
      clock.advance(const Duration(seconds: 60));
      (await s.poll(hasAudience: everyone));

      s.config = const AnnouncementsConfig(
        intervalSeconds: 10,
        messages: [
          Announcement(text: 'x'),
          Announcement(text: 'y'),
        ],
      );
      expect(await s.poll(hasAudience: everyone), isNull);
      clock.advance(const Duration(seconds: 10));
      expect((await s.poll(hasAudience: everyone))!.text, 'x');
    });

    test('random order never repeats immediately', () async {
      final s = AnnouncementService(
        clock,
        const AnnouncementsConfig(
          intervalSeconds: 5,
          random: true,
          messages: [
            Announcement(text: 'a'),
            Announcement(text: 'b'),
            Announcement(text: 'c'),
          ],
        ),
        random: Random(5),
      );
      String? last;
      for (var i = 0; i < 100; i++) {
        clock.advance(const Duration(seconds: 5));
        final text = (await s.poll(hasAudience: everyone))!.text;
        expect(text, isNot(last));
        last = text;
      }
    });
  });

  group('config file', () {
    test('round trips, with modes as names', () {
      final config = AnnouncementsConfigMapper.fromJson(
        const AnnouncementsConfig().toJson(),
      );
      expect(config.messages, hasLength(4));
      expect(config.messages[1].command, '/daily');
      expect(config.messages[2].mode, AnnouncementMode.bossbar);
      expect(config.toJson(), contains('"mode":"bossbar"'));
    });

    test('missing keys use the defaults', () {
      final config = AnnouncementsConfigMapper.fromJson(
        '{"intervalSeconds": 30, "random": true, '
        '"messages": [{"text": "hi", "mode": "title", "subtitle": "there"}]}',
      );
      expect(config.interval, const Duration(seconds: 30));
      expect(config.random, isTrue);
      expect(config.displayTime, const Duration(seconds: 10));
      expect(config.messages.single.mode, AnnouncementMode.title);
      expect(config.messages.single.subtitle, 'there');
      expect(config.messages.single.permission, isNull);
    });

    test('an unknown mode is an error, so a reload keeps the old config', () {
      expect(
        () => AnnouncementsConfigMapper.fromJson(
          '{"messages": [{"text": "hi", "mode": "popup"}]}',
        ),
        throwsA(anything),
      );
    });
  });
}
