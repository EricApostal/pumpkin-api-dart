import 'dart:async';

import 'package:commons/src/core/clock.dart';
import 'package:commons/src/core/lock.dart';
import 'package:commons/src/core/players.dart';
import 'package:commons/src/core/services.dart';
import 'package:commons/src/core/storage.dart';
import 'package:test/test.dart';

void main() {
  group('Documents', () {
    test('creates, saves lazily and reloads', () {
      final backend = MemoryBackend();
      final docs = Documents(backend);
      final doc = docs.open<PlayerRecords>(
        'p.json',
        decode: PlayerRecordsMapper.fromJson,
        encode: (v) => v.toJson(),
        create: PlayerRecords.new,
      );
      expect(doc.isDirty, isTrue);
      docs.saveDirty();
      expect(backend.files['p.json'], isNotNull);
      expect(docs.dirtyCount, 0);
    });

    test('keeps a copy of a corrupt file', () {
      final backend = MemoryBackend()..files['p.json'] = '{nope';
      final warnings = <String>[];
      final docs = Documents(backend, clock: FakeClock(), warn: warnings.add);
      final doc = docs.open<PlayerRecords>(
        'p.json',
        decode: PlayerRecordsMapper.fromJson,
        encode: (v) => v.toJson(),
        create: PlayerRecords.new,
      );
      expect(doc.value.players, isEmpty);
      expect(
        backend.files.keys.where((k) => k.startsWith('p.json.corrupt-')),
        hasLength(1),
      );
      expect(warnings, hasLength(1));
    });
  });

  group('PlayerDirectory', () {
    test('finds players by name, also after a rename', () {
      final clock = FakeClock();
      final backend = MemoryBackend();
      final first = Documents(backend, clock: clock);
      var dir = PlayerDirectory(first, clock);
      expect(dir.touch('u1', 'Steve'), isTrue);
      clock.advance(const Duration(hours: 1));
      expect(dir.touch('u1', 'Steve'), isFalse);
      expect(dir.byName('sTeVe')?.uuid, 'u1');
      dir.touch('u1', 'Alex');
      expect(dir.byName('steve'), isNull);
      expect(dir.nameOf('u1'), 'Alex');

      // Survives a restart.
      first.saveDirty();
      dir = PlayerDirectory(Documents(backend, clock: clock), clock);
      expect(dir.names, ['Alex']);
    });
  });

  test('Services require/provide', () {
    final services = Services()..provide<String>('x');
    expect(services.require<String>(), 'x');
    expect(services.find<int>(), isNull);
    expect(() => services.require<int>(), throwsStateError);
    expect(() => services.provide<String>('y'), throwsStateError);
  });

  group('KeyedLock', () {
    test('runs actions of one key one after another', () async {
      final lock = KeyedLock();
      final log = <String>[];
      final gate = Completer<void>();
      final first = lock.run('a', () async {
        log.add('first start');
        await gate.future;
        log.add('first end');
      });
      final second = lock.run('a', () async => log.add('second'));
      final other = lock.run('b', () async => log.add('other'));
      await other;
      expect(log, ['first start', 'other']);
      gate.complete();
      await Future.wait([first, second]);
      expect(log, ['first start', 'other', 'first end', 'second']);
    });

    test('a failing action does not block the next one', () async {
      final lock = KeyedLock();
      await expectLater(
        lock.run('a', () async => throw StateError('no')),
        throwsStateError,
      );
      expect(await lock.run('a', () async => 7), 7);
    });
  });
}
