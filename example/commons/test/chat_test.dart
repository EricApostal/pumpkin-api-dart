import 'package:commons/src/chat/format.dart';
import 'package:commons/src/chat/model.dart';
import 'package:commons/src/chat/service.dart';
import 'package:commons/src/chat/spam.dart';
import 'package:commons/src/chat/welcome.dart';
import 'package:commons/src/core/api.dart';
import 'package:commons/src/core/clock.dart';
import 'package:commons/src/core/storage.dart';
import 'package:test/test.dart';

String joined(List<ChatSpan> spans) => spans.map((s) => s.legacy).join('|');

void main() {
  group('activeCodes', () {
    test('keeps the last color and the formats after it', () {
      expect(activeCodes(''), '');
      expect(activeCodes('plain'), '');
      expect(activeCodes('&aHello'), '&a');
      expect(activeCodes('&a&lHello &cworld'), '&c');
      expect(activeCodes('&c&l&oHello'), '&c&l&o');
      expect(activeCodes('&lHi'), '&l');
    });

    test('reset clears, escaped ampersands and unknown codes are text', () {
      expect(activeCodes('&a&rx'), '');
      expect(activeCodes('&&aHi'), '');
      expect(activeCodes('&a&&b'), '&a');
      expect(activeCodes('Fish & chips &'), '');
      expect(activeCodes('§e§lHi'), '&e&l');
      expect(activeCodes('&AHi'), '&a');
    });
  });

  test('cleanText removes section signs and control characters', () {
    expect(cleanText('  §chi\n there\u0000 '), 'chi  there');
    expect(escapeLegacy('a&b§c'), 'a&&bc');
  });

  group('mentions', () {
    const online = ['Steve', 'Alex_2'];

    test('finds names ignoring case and spells them as the player does', () {
      final mentions = findMentions('hey @steve and @ALEX_2!', online);
      expect([for (final m in mentions) m.name], ['Steve', 'Alex_2']);
      expect(mentions.first.start, 4);
      expect(mentions.first.end, 10);
    });

    test('ignores unknown names, e-mail addresses and partial names', () {
      expect(findMentions('@nobody', online), isEmpty);
      expect(findMentions('mail me@steve.com', online), isEmpty);
      expect(findMentions('@Stevenson', online), isEmpty);
      expect(findMentions('steve', online), isEmpty);
      expect(findMentions('@', online), isEmpty);
      expect(findMentions('(@Steve)', online), hasLength(1));
    });
  });

  group('messageSpans', () {
    test('escapes formatting unless colors are allowed', () {
      expect(joined(messageSpans('&cred §4x', allowColor: false)), '&&cred 4x');
      expect(joined(messageSpans('&cred', allowColor: true)), '&cred');
    });

    test('highlights mentions and continues the style after them', () {
      final spans = messageSpans(
        '&aHi @steve, welcome',
        allowColor: true,
        mentionable: ['Steve'],
      );
      expect(
        [for (final s in spans) s.legacy],
        ['&aHi ', '&e&l@Steve', '&a, welcome'],
      );
      expect([for (final s in spans) s.mention], [null, 'Steve', null]);
    });

    test('a lone ampersand before a mention stays literal', () {
      final spans = messageSpans(
        'AT&@Steve',
        allowColor: true,
        mentionable: ['Steve'],
      );
      expect([for (final s in spans) s.legacy], ['AT&', '&e&l@Steve']);
    });

    test('starts with the base codes', () {
      expect(joined(messageSpans('hi', allowColor: false, base: '&f')), '&fhi');
    });
  });

  group('ChatTemplate', () {
    const admin = RankStyle(
      permission: 'p',
      prefix: '&c[Admin] ',
      suffix: ' &7*',
      color: '&c',
    );

    test('renders the default layout', () {
      final spans = ChatTemplate(const ChatConfig().format)
          .render(rank: admin, playerName: 'Steve', message: 'hello');
      expect(joined(spans), '&c[Admin] |&cSteve| &7*|&8: &f|&fhello');
      expect(spans[1].slot, ChatSlot.name);
    });

    test('empty prefix and suffix produce no pieces', () {
      final spans = ChatTemplate('{prefix}{name}{suffix}: {message}').render(
        rank: const RankStyle(color: '&7'),
        playerName: 'Steve',
        message: 'hi',
      );
      expect(joined(spans), '&7Steve|: |hi');
    });

    test('the template color carries into the message', () {
      final spans = ChatTemplate('&e[{name}] &o{message}')
          .render(rank: const RankStyle(), playerName: 'Steve', message: 'hey');
      expect(joined(spans), '&e[|&e&fSteve|] &o|&e&ohey');
    });

    test('names and messages cannot inject formatting', () {
      final spans = ChatTemplate('{name}: {message}').render(
        rank: const RankStyle(color: '&a'),
        playerName: 'Ev&cil',
        message: '&4&lBOOM §',
      );
      expect(joined(spans), '&aEv&&cil|: |&&4&&lBOOM ');
    });

    test('mentions become their own spans', () {
      final spans = ChatTemplate('{name}: {message}').render(
        rank: const RankStyle(),
        playerName: 'A',
        message: 'yo @Steve',
        mentionable: ['Steve'],
      );
      expect(spans.where((s) => s.mention != null).single.mention, 'Steve');
    });

    test('unknown placeholders stay as text', () {
      final spans = ChatTemplate('{x}{message}')
          .render(rank: const RankStyle(), playerName: 'A', message: 'm');
      expect(joined(spans), '{x}|m');
    });
  });

  group('selectRank', () {
    const ranks = [
      RankStyle(permission: 'a', prefix: 'A'),
      RankStyle(permission: 'b', prefix: 'B'),
    ];
    const fallback = RankStyle(prefix: 'default');

    test('the first match wins', () {
      expect(selectRank(ranks, fallback, (p) => true).prefix, 'A');
      expect(selectRank(ranks, fallback, (p) => p == 'b').prefix, 'B');
    });

    test('falls back, and an empty permission matches everybody', () {
      expect(selectRank(ranks, fallback, (p) => false).prefix, 'default');
      expect(
        selectRank(
          [const RankStyle(prefix: 'all'), ...ranks],
          fallback,
          (p) => false,
        ).prefix,
        'all',
      );
    });
  });

  group('SpamGuard', () {
    late FakeClock clock;
    SpamGuard guard([SpamConfig config = const SpamConfig()]) =>
        SpamGuard(clock, config);

    setUp(() => clock = FakeClock());

    void pass(Duration by) => clock.advance(by);

    test('the cooldown refuses messages that come too fast', () {
      final g = guard();
      expect(g.check('a', 'one').allowed, isTrue);
      pass(const Duration(milliseconds: 400));
      final verdict = g.check('a', 'two');
      expect(verdict.reason, SpamReason.tooFast);
      expect(verdict.wait, const Duration(milliseconds: 600));
      expect(g.check('b', 'two').allowed, isTrue);
      pass(const Duration(milliseconds: 600));
      expect(g.check('a', 'two').allowed, isTrue);
    });

    test('refused messages are not recorded', () {
      final g = guard();
      g.check('a', 'one');
      for (var i = 0; i < 20; i++) {
        pass(const Duration(milliseconds: 10));
        g.check('a', 'spam$i');
      }
      pass(const Duration(seconds: 1));
      expect(g.check('a', 'fine').allowed, isTrue);
    });

    test('at most N messages per window', () {
      final g = guard(
        const SpamConfig(cooldownMillis: 0, maxMessages: 3, windowSeconds: 10),
      );
      for (var i = 0; i < 3; i++) {
        expect(g.check('a', 'm$i').allowed, isTrue);
        pass(const Duration(seconds: 2));
      }
      // Sent at 0, 2, 4 seconds; now 6.
      final verdict = g.check('a', 'm3');
      expect(verdict.reason, SpamReason.tooMany);
      expect(verdict.wait, const Duration(seconds: 4));
      pass(const Duration(seconds: 4));
      expect(g.check('a', 'm3').allowed, isTrue);
    });

    test('repeating is refused for longer than the window', () {
      final g = guard(
        const SpamConfig(
          cooldownMillis: 0,
          windowSeconds: 5,
          repeatSeconds: 30,
        ),
      );
      expect(g.check('a', 'Hello there!').allowed, isTrue);
      pass(const Duration(seconds: 10));
      final verdict = g.check('a', 'hello THERE');
      expect(verdict.reason, SpamReason.repeated);
      expect(verdict.wait, const Duration(seconds: 20));
      expect(g.check('a', 'something else').allowed, isTrue);
      pass(const Duration(seconds: 1));
      expect(g.check('a', 'hello there').allowed, isTrue);
    });

    test('repeats are allowed again after the repeat time', () {
      final g = guard(const SpamConfig(cooldownMillis: 0, repeatSeconds: 30));
      g.check('a', 'gg');
      pass(const Duration(seconds: 30));
      expect(g.check('a', 'gg').allowed, isTrue);
    });

    test('disabled lets everything through, forget resets a player', () {
      final off = guard(const SpamConfig(enabled: false));
      expect(off.check('a', 'x').allowed, isTrue);
      expect(off.check('a', 'x').allowed, isTrue);

      final g = guard();
      g.check('a', 'x');
      expect(g.check('a', 'y').allowed, isFalse);
      g.forget('a');
      expect(g.check('a', 'y').allowed, isTrue);
    });

    test('messages without letters are compared as they are', () {
      expect(normalizeMessage('Hello, World!'), 'helloworld');
      expect(normalizeMessage('??'), '??');
      expect(normalizeMessage('Ünï 42'), 'ünï42');
    });
  });

  group('ChatService', () {
    late MemoryBackend backend;
    late FakeClock clock;

    (ChatService, Documents) open() {
      final docs = Documents(backend, clock: clock);
      final doc = docs.open<IgnoreData>(
        'chat/ignores.json',
        decode: IgnoreDataMapper.fromJson,
        encode: (v) => v.toJson(),
        create: IgnoreData.new,
      );
      return (ChatService(doc, clock, const ChatConfig()), docs);
    }

    setUp(() {
      backend = MemoryBackend();
      clock = FakeClock();
    });

    test('ignoring is one-directional, idempotent and persisted', () {
      final (chat, docs) = open();
      expect(chat.setIgnoring('a', 'b', ignoring: true), isTrue);
      expect(chat.setIgnoring('a', 'b', ignoring: true), isFalse);
      expect(chat.isIgnoring('a', 'b'), isTrue);
      expect(chat.isIgnoring('b', 'a'), isFalse);
      expect(chat.canSee(viewer: 'a', sender: 'b'), isFalse);
      expect(chat.canSee(viewer: 'b', sender: 'a'), isTrue);
      expect(chat.canSee(viewer: 'a', sender: 'b', exempt: true), isTrue);
      chat.setIgnoring('a', 'c', ignoring: true);
      expect(chat.ignoredBy('a'), ['b', 'c']);

      docs.saveDirty();
      final (again, _) = open();
      expect(again.ignoredBy('a'), ['b', 'c']);

      expect(again.setIgnoring('a', 'b', ignoring: false), isTrue);
      expect(again.setIgnoring('a', 'b', ignoring: false), isFalse);
      expect(again.ignoredBy('a'), ['c']);
      again.setIgnoring('a', 'c', ignoring: false);
      expect(again.ignoredBy('a'), isEmpty);
    });

    test('reply partners are remembered for both sides', () {
      final (chat, _) = open();
      expect(chat.conversations.lastPartner('a'), isNull);
      chat.conversations.record('a', 'b');
      expect(chat.conversations.lastPartner('a'), 'b');
      expect(chat.conversations.lastPartner('b'), 'a');

      chat.conversations.record('c', 'a');
      expect(chat.conversations.lastPartner('a'), 'c');
      expect(chat.conversations.lastPartner('b'), 'a');
    });

    test('a one way message leaves the other side alone', () {
      final (chat, _) = open();
      chat.conversations.record('b', 'x');
      chat.conversations.recordOneWay('a', 'b');
      expect(chat.conversations.lastPartner('a'), 'b');
      expect(chat.conversations.lastPartner('b'), 'x');
    });

    test('leaving clears the session state', () {
      final (chat, _) = open();
      chat.conversations.record('a', 'b');
      chat.setSpying('a');
      chat.spam.check('a', 'x');
      chat.playerLeft('a');

      expect(chat.conversations.lastPartner('a'), isNull);
      expect(chat.conversations.lastPartner('b'), 'a');
      expect(chat.isSpying('a'), isFalse);
      expect(chat.spam.check('a', 'x').allowed, isTrue);
    });

    test('spying toggles', () {
      final (chat, _) = open();
      expect(chat.setSpying('a'), isTrue);
      expect(chat.spies, {'a'});
      expect(chat.setSpying('a'), isFalse);
      expect(chat.setSpying('a', on: false), isFalse);
      expect(chat.setSpying('a', on: true), isTrue);
      expect(chat.setSpying('a', on: true), isTrue);
    });
  });

  group('WelcomeSummary', () {
    test('only includes what the installed services report', () {
      final nothing = WelcomeSummary.collect('u');
      expect(nothing.balance, isNull);
      expect(nothing.unreadMail, isNull);
      expect(nothing.dailyAvailable, isNull);

      final summary = WelcomeSummary.collect(
        'u',
        economy: _Economy(),
        mail: _Mail(),
        rewards: _Rewards(),
      );
      expect(summary.balance, '1250 coins');
      expect(summary.unreadMail, 3);
      expect(summary.dailyAvailable, isTrue);

      final partial = WelcomeSummary.collect('v', mail: _Mail());
      expect(partial.unreadMail, 0);
      expect(partial.balance, isNull);
    });
  });

  test('the default config round trips and reads partial files', () {
    final config = ChatConfigMapper.fromJson(const ChatConfig().toJson());
    expect(config.ranks.first.permission, 'commons:chat.rank.admin');
    expect(config.spam.maxMessages, 5);

    final partial = ChatConfigMapper.fromJson(
      '{"format": "{name}: {message}", "spam": {"maxMessages": 2}}',
    );
    expect(partial.format, '{name}: {message}');
    expect(partial.spam.maxMessages, 2);
    expect(partial.spam.cooldownMillis, 1000);
    expect(partial.welcome.enabled, isTrue);
  });
}

class _Economy implements Economy {
  @override
  int balance(String uuid) => uuid == 'u' ? 1250 : 0;
  @override
  String format(int amount) => '$amount coins';
  @override
  bool canAfford(String uuid, int amount) => false;
  @override
  String get currencyName => 'coins';
  @override
  Transaction deposit(String uuid, int amount, {String? reason}) =>
      throw UnimplementedError();
  @override
  Transaction transfer(String from, String to, int amount, {String? reason}) =>
      throw UnimplementedError();
  @override
  Transaction withdraw(String uuid, int amount, {String? reason}) =>
      throw UnimplementedError();
}

class _Mail implements MailApi {
  @override
  int unreadCount(String uuid) => uuid == 'u' ? 3 : 0;
}

class _Rewards implements RewardsApi {
  @override
  bool canClaimDaily(String uuid) => true;
}
