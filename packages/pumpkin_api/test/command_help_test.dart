import 'package:pumpkin_api/src/command_help.dart';
import 'package:test/test.dart';

SpecNode _home() {
  final root = SpecNode('home', SpecKind.root, description: 'Go home')
    ..runnable = true;
  final name = SpecNode('name', SpecKind.argument, optional: true)
    ..runnable = true;
  root.add(name);
  final set = SpecNode('set', SpecKind.literal, description: 'Save a home');
  root.add(set);
  set.add(SpecNode('name', SpecKind.argument)..runnable = true);
  return root;
}

void main() {
  group('usage', () {
    test('folds optional arguments into the parent line', () {
      expect(usageLines(_home()), ['/home [name]', '/home set <name>']);
    });

    test('a required argument is not folded', () {
      final root = SpecNode('x', SpecKind.root)..runnable = true;
      root.add(SpecNode('a', SpecKind.argument)..runnable = true);
      expect(usageLines(root), ['/x', '/x <a>']);
    });

    test('from limits the lines to a subtree', () {
      final root = _home();
      final set = root.children.last;
      expect(usageLines(root, from: set), ['/home set <name>']);
      // An optional argument stands for its parent.
      expect(usageLines(root, from: root.children.first), [
        '/home [name]',
        '/home set <name>',
      ]);
    });

    test('a path is described by its last command or subcommand', () {
      final root = SpecNode('x', SpecKind.root, description: 'Root')
        ..runnable = true;
      root.add(SpecNode('quiet', SpecKind.literal)..runnable = true);
      expect(commandPaths(root).map((p) => p.description), ['Root', null]);
    });

    test('labels', () {
      final root = SpecNode('mode', SpecKind.root);
      root.add(
        SpecNode('m', SpecKind.argument, label: 'a|b')..runnable = true,
      );
      expect(usageLines(root), ['/mode <a|b>']);
    });

    test('UsageException message', () {
      expect(UsageException(['/a']).message, 'Usage: /a');
      expect(
        UsageException(['/a', '/a b'], 'Bad').message,
        'Bad\nUsage:\n  /a\n  /a b',
      );
      expect(UsageException(['/a']), isA<CommandException>());
    });
  });

  group('help', () {
    test('lists lines with descriptions, sorted, filtered by permission', () {
      final registry = CommandRegistry();
      final warp = SpecNode(
        'warp',
        SpecKind.root,
        description: 'Warp',
        permission: 'p:warp',
      )..runnable = true;
      final set = SpecNode(
        'set',
        SpecKind.literal,
        description: 'Create',
        permission: 'p:set',
      )..runnable = true;
      warp.add(set);
      registry
        ..add(warp)
        ..add(_home());
      expect(helpLines(registry), [
        '/home [name] - Go home',
        '/home set <name> - Save a home',
        '/warp - Warp',
        '/warp set - Create',
      ]);
      expect(
        helpLines(registry, canUse: (p) => !p.contains('p:set')),
        isNot(contains('/warp set - Create')),
      );
      expect(helpLines(registry, command: '/warp'), [
        '/warp - Warp',
        '/warp set - Create',
      ]);
      expect(helpLines(registry, hidden: {'home'}).length, 2);
    });

    test('registry replaces by name and finds aliases', () {
      final registry = CommandRegistry();
      final a = SpecNode('a', SpecKind.root, aliases: ['b']);
      registry
        ..add(a)
        ..add(SpecNode('a', SpecKind.root));
      expect(registry.roots.length, 1);
      expect(registry.find('b'), isNull);
      registry.add(a);
      expect(registry.find('/b'), a);
    });
  });

  group('suggestions and choices', () {
    test('filterSuggestions', () {
      expect(filterSuggestions(['Bob', 'alice', 'bob', 'Bobby'], 'b'), [
        'Bob',
        'bob',
        'Bobby',
      ]);
      expect(filterSuggestions(['x'], ''), ['x']);
      expect(filterSuggestions(['x'], 'y'), isEmpty);
    });

    test('matchChoice', () {
      expect(matchChoice('RED', ['red', 'blue']), 'red');
      expect(
        () => matchChoice('green', ['red', 'blue']),
        throwsA(
          isA<CommandException>().having(
            (e) => e.message,
            'message',
            'Unknown option "green". Choose one of: red, blue.',
          ),
        ),
      );
    });
  });

  group('duration', () {
    test('parses units', () {
      expect(parseDuration('10s'), const Duration(seconds: 10));
      expect(parseDuration('5m'), const Duration(minutes: 5));
      expect(parseDuration('1h'), const Duration(hours: 1));
      expect(parseDuration('2d'), const Duration(days: 2));
      expect(parseDuration('1w'), const Duration(days: 7));
      expect(parseDuration('250ms'), const Duration(milliseconds: 250));
      expect(
        parseDuration('1h30m5s'),
        const Duration(hours: 1, minutes: 30, seconds: 5),
      );
      expect(parseDuration(' 1H '), const Duration(hours: 1));
      expect(parseDuration('45'), const Duration(seconds: 45));
    });

    test('rejects garbage', () {
      for (final bad in ['', 's', '1x', '-5', '1.5h', 'abc', '10s5', '5 m']) {
        expect(parseDuration(bad), isNull, reason: bad);
      }
      expect(() => parseDurationOrThrow('nope'), throwsA(isA<CommandException>()));
    });

    test('formatDuration', () {
      expect(formatDuration(Duration.zero), '0s');
      expect(formatDuration(const Duration(milliseconds: 1)), '0.1s');
      expect(formatDuration(const Duration(milliseconds: 1500)), '1.5s');
      expect(formatDuration(const Duration(seconds: 3)), '3s');
      expect(formatDuration(const Duration(milliseconds: 10001)), '11s');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 30, seconds: 5)),
        '1h 30m 5s',
      );
      expect(formatDuration(const Duration(days: 1)), '1d');
    });
  });
}
