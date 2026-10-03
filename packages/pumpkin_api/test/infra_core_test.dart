import 'dart:async';
import 'dart:convert';

import 'package:pumpkin_api/src/infra_core.dart';
import 'package:test/test.dart';

void main() {
  group('DisposableBag', () {
    test('runs newest first and survives failures', () {
      final order = <int>[];
      final errors = <String>[];
      final bag = DisposableBag(onError: errors.add);
      bag.addCallback(() => order.add(1));
      bag.addCallback(() => throw StateError('boom'));
      bag.addCallback(() => order.add(3));
      bag.dispose();
      expect(order, [3, 1]);
      expect(errors, hasLength(1));
      expect(bag.isEmpty, isTrue);
      bag.dispose();
      expect(order, [3, 1]);
    });

    test('cancelled callbacks do not run', () {
      var ran = false;
      final bag = DisposableBag();
      bag.addCallback(() => ran = true).cancel();
      bag.dispose();
      expect(ran, isFalse);
    });

    test('adds Disposables and Subscriptions', () {
      var n = 0;
      final bag = DisposableBag();
      final s = bag.add(Subscription(() => n++));
      bag.dispose();
      expect(n, 1);
      expect(s.isCancelled, isTrue);
    });
  });

  group('UnloadHooks', () {
    test('sync hooks run in reverse, guarded', () {
      final hooks = UnloadHooks();
      final order = <String>[];
      final errors = <String>[];
      hooks.add(() => order.add('a'));
      hooks.add(() => throw 'x');
      hooks.add(() => order.add('c'));
      expect(hooks.run(errors.add), isNull);
      expect(order, ['c', 'a']);
      expect(errors, hasLength(1));
      expect(hooks.length, 0);
    });

    test('async hooks are awaited in sequence', () async {
      final hooks = UnloadHooks();
      final order = <String>[];
      hooks.add(() => order.add('first-added'));
      hooks.add(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        order.add('async');
        throw 'late failure';
      });
      hooks.add(() => order.add('last-added'));
      final errors = <String>[];
      final result = hooks.run(errors.add);
      expect(result, isA<Future>());
      await result;
      expect(order, ['last-added', 'async', 'first-added']);
      expect(errors, hasLength(1));
    });

    test('removed hooks do not run', () {
      final hooks = UnloadHooks();
      var ran = false;
      hooks.add(() => ran = true).cancel();
      hooks.run((_) {});
      expect(ran, isFalse);
    });
  });

  group('IpcHandlerRegistry', () {
    List<int> env(String type, Object? data) => encodeEnvelope(type, data);

    test('dispatches by type and encodes the reply', () {
      final r = IpcHandlerRegistry();
      r.register('add', (sender, data) => {'sum': (data as List).fold<int>(0, (a, b) => a + (b as int)), 'from': sender});
      final reply = r.handle('p', env('add', [1, 2, 3]));
      expect(jsonDecode(utf8.decode(reply)), {'sum': 6, 'from': 'p'});
    });

    test('unknown type is rejected, non-envelope is bad payload', () {
      final r = IpcHandlerRegistry();
      expect(() => r.handle('p', env('nope', null)),
          throwsA(isA<IpcException>().having((e) => e.reason, 'reason', IpcFailure.rejected)));
      expect(() => r.handle('p', utf8.encode('not json')),
          throwsA(isA<IpcException>().having((e) => e.reason, 'reason', IpcFailure.badPayload)));
    });

    test('fallback gets unhandled messages', () {
      final r = IpcHandlerRegistry()..fallback = (s, b) => [b.length];
      expect(r.handle('p', [1, 2, 3]), [3]);
      expect(r.handle('p', env('x', null)), hasLength(1));
    });

    test('duplicate registration throws, unregister frees it', () {
      final r = IpcHandlerRegistry();
      final sub = r.register('t', (_, _) => null);
      expect(() => r.register('t', (_, _) => null), throwsStateError);
      sub.cancel();
      expect(r.hasHandlers, isFalse);
      r.register('t', (_, _) => null);
    });

    test('handler exceptions propagate', () {
      final r = IpcHandlerRegistry()..register('t', (_, _) => throw ArgumentError('bad'));
      expect(() => r.handle('p', env('t', null)), throwsArgumentError);
    });
  });

  test('json payloads', () {
    expect(decodeJsonPayload(const []), isNull);
    expect(decodeJsonPayload(encodeJsonPayload({'a': 1})), {'a': 1});
    expect(() => decodeJsonPayload(utf8.encode('{')), throwsA(isA<IpcException>()));
    expect(() => encodeJsonPayload(Object()), throwsA(isA<IpcException>()));
  });
}
