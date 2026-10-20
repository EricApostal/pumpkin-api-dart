// W3: the `/sable` selector grammar (`SubLevelArgumentType`), its modifiers and
// their resolution. Pure, so it runs on the VM.
import 'dart:math' as math;

import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late FakeLevel level;
  late FakeChunkHost host;
  late ServerSubLevelContainer container;

  setUp(() {
    level = FakeLevel();
    host = FakeChunkHost(level);
    container = ServerSubLevelContainer(
      level,
      host,
      3,
      4,
      SubLevelContainer.defaultOrigin,
      SubLevelContainer.defaultOrigin,
    );
    SubLevelContainer.register(container);
  });

  tearDown(() => SubLevelContainer.unregister(level));

  ServerSubLevel spawn(String name, Vector3d position) {
    final pose = Pose3d()..position().setFrom(position);
    final subLevel = container.allocateNewSubLevel(pose) as ServerSubLevel;
    subLevel.setName(name);
    return subLevel;
  }

  SubLevelTargetContext contextAt(Vector3d position) => SubLevelTargetContext(
    container: container,
    sourcePosition: position,
    random: math.Random(1),
  );

  group('parsing', () {
    test('@e selects every sub-level', () {
      spawn('a', Vector3d(0, 0, 0));
      spawn('b', Vector3d(10, 0, 0));

      final target = SubLevelArgumentType.subLevels.parse('@e');
      expect(target, isA<SubLevelTargetSelector>());
      expect((target as SubLevelTargetSelector).type, SubLevelSelectorType.all);
      expect(target.resolve(contextAt(Vector3d())), hasLength(2));
    });

    test('@n selects the nearest sub-level', () {
      final near = spawn('near', Vector3d(1, 0, 0));
      spawn('far', Vector3d(100, 0, 0));

      final resolved = SubLevelArgumentType.subLevels
          .parse('@n')
          .resolve(contextAt(Vector3d(0, 0, 0)));
      expect(resolved.single.uniqueId, near.uniqueId);
    });

    test('@l selects the most recently created sub-level', () {
      spawn('first', Vector3d(0, 0, 0));
      final latest = spawn('latest', Vector3d(5, 0, 0));

      final resolved = SubLevelArgumentType.subLevels
          .parse('@l')
          .resolve(contextAt(Vector3d()));
      expect(resolved.single.uniqueId, latest.uniqueId);
    });

    test('an unknown selector is rejected', () {
      expect(
        () => SubLevelArgumentType.subLevels.parse('@q'),
        throwsA(isA<SubLevelSelectorException>().having(
          (e) => e.error,
          'error',
          SubLevelSelectorError.invalidSelector,
        )),
      );
    });

    test('a malformed UUID is rejected', () {
      expect(
        () => SubLevelArgumentType.subLevels.parse('not-a-uuid'),
        throwsA(isA<SubLevelSelectorException>().having(
          (e) => e.error,
          'error',
          SubLevelSelectorError.invalidUuid,
        )),
      );
    });

    test('a UUID selects exactly that sub-level', () {
      final target = spawn('a', Vector3d(0, 0, 0));
      final resolved = SubLevelArgumentType.subLevels
          .parse(target.uniqueId)
          .resolve(contextAt(Vector3d()));
      expect(resolved.single.uniqueId, target.uniqueId);
    });

    test('an unknown UUID fails when resolved', () {
      final target = SubLevelArgumentType.subLevels.parse(
        '00000000-0000-0000-0000-000000000000',
      );
      expect(
        () => target.resolve(contextAt(Vector3d())),
        throwsA(isA<SubLevelSelectorException>()),
      );
    });

    test('a multiple selector is refused by singleSubLevel', () {
      expect(
        () => SubLevelArgumentType.singleSubLevel.parse('@e'),
        throwsA(isA<SubLevelSelectorException>().having(
          (e) => e.error,
          'error',
          SubLevelSelectorError.singleSubLevelRequired,
        )),
      );
    });

    test('@n is allowed for singleSubLevel', () {
      expect(
        SubLevelArgumentType.singleSubLevel.parse('@n'),
        isA<SubLevelTargetSelector>(),
      );
    });

    test('static_world is only allowed when declared', () {
      expect(
        () => SubLevelArgumentType.subLevels.parse('static_world'),
        throwsA(isA<SubLevelSelectorException>()),
      );
      expect(
        SubLevelArgumentType.subLevelsOrLevel.parse('static_world'),
        isA<SubLevelTargetNone>(),
      );
    });
  });

  group('modifiers', () {
    test('limit truncates after sorting', () {
      spawn('a', Vector3d(3, 0, 0));
      spawn('b', Vector3d(1, 0, 0));
      spawn('c', Vector3d(2, 0, 0));

      final resolved = SubLevelArgumentType.subLevels
          .parse('@e[sort=nearest,limit=2]')
          .resolve(contextAt(Vector3d(0, 0, 0)));

      expect(resolved.map((s) => s.name), ['b', 'c']);
    });

    test('sort=furthest reverses the order', () {
      spawn('a', Vector3d(3, 0, 0));
      spawn('b', Vector3d(1, 0, 0));

      final resolved = SubLevelArgumentType.subLevels
          .parse('@e[sort=furthest]')
          .resolve(contextAt(Vector3d(0, 0, 0)));
      expect(resolved.map((s) => s.name), ['a', 'b']);
    });

    test('name filters', () {
      spawn('ship', Vector3d(0, 0, 0));
      spawn('other', Vector3d(1, 0, 0));

      final resolved = SubLevelArgumentType.subLevels
          .parse('@e[name=ship]')
          .resolve(contextAt(Vector3d()));
      expect(resolved.map((s) => s.name), ['ship']);
    });

    test('a quoted name may contain commas', () {
      spawn('ship, the second', Vector3d(0, 0, 0));

      final resolved = SubLevelArgumentType.subLevels
          .parse('@e[name="ship, the second"]')
          .resolve(contextAt(Vector3d()));
      expect(resolved, hasLength(1));
    });

    test('a range filters on x', () {
      spawn('a', Vector3d(-2, 0, 0));
      spawn('b', Vector3d(5, 0, 0));

      final resolved = SubLevelArgumentType.subLevels
          .parse('@e[x=0..10]')
          .resolve(contextAt(Vector3d()));
      expect(resolved.map((s) => s.name), ['b']);
    });

    test('distance is compared squared', () {
      spawn('a', Vector3d(1, 0, 0));
      spawn('b', Vector3d(5, 0, 0));

      final resolved = SubLevelArgumentType.subLevels
          .parse('@e[distance=..2]')
          .resolve(contextAt(Vector3d(0, 0, 0)));
      expect(resolved.map((s) => s.name), ['a']);
    });

    test('dx filters on the offset', () {
      spawn('a', Vector3d(3, 0, 0));
      spawn('b', Vector3d(-3, 0, 0));

      final resolved = SubLevelArgumentType.subLevels
          .parse('@e[dx=5]')
          .resolve(contextAt(Vector3d()));
      expect(resolved.map((s) => s.name), ['a']);
    });

    test('an unknown property is rejected', () {
      expect(
        () => SubLevelArgumentType.subLevels.parse('@e[nope=1]'),
        throwsA(isA<SubLevelSelectorException>().having(
          (e) => e.error,
          'error',
          SubLevelSelectorError.unknownProperty,
        )),
      );
    });

    test('an unclosed selector is rejected', () {
      expect(
        () => SubLevelArgumentType.subLevels.parse('@e[limit=1'),
        throwsA(isA<SubLevelSelectorException>().having(
          (e) => e.error,
          'error',
          SubLevelSelectorError.unexpectedEndOfInput,
        )),
      );
    });

    test('a negative limit is rejected', () {
      expect(
        () => SubLevelArgumentType.subLevels.parse('@e[limit=-1]'),
        throwsA(isA<SubLevelSelectorException>()),
      );
    });

    test('an invalid sort mode is rejected', () {
      expect(
        () => SubLevelArgumentType.subLevels.parse('@e[sort=sideways]'),
        throwsA(isA<SubLevelSelectorException>().having(
          (e) => e.error,
          'error',
          SubLevelSelectorError.expectedSorting,
        )),
      );
    });

    test('a negative value for a positive-only property is rejected', () {
      expect(
        () => SubLevelArgumentType.subLevels.parse('@e[width=-1]'),
        throwsA(isA<SubLevelSelectorException>()),
      );
    });
  });

  group('DoubleRange', () {
    test('exactly matches one value', () {
      const range = DoubleRange.exactly(2.0);
      expect(range.matches(2.0), isTrue);
      expect(range.matches(2.1), isFalse);
    });

    test('open ends', () {
      const range = DoubleRange(null, 5.0);
      expect(range.matches(-100), isTrue);
      expect(range.matches(6), isFalse);
    });

    test('parses the `a..b` form', () {
      final range = DoubleRange.parse('1..3');
      expect(range.min, 1.0);
      expect(range.max, 3.0);
      expect(range.matches(2), isTrue);
      expect(range.matches(4), isFalse);
    });

    test('parses an open-ended form', () {
      expect(DoubleRange.parse('..3').min, isNull);
      expect(DoubleRange.parse('3..').max, isNull);
    });
  });
}
