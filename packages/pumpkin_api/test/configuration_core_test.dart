import 'dart:async';
import 'dart:typed_data';

import 'package:pumpkin_api/src/configuration_core.dart';
import 'package:pumpkin_api/src/packet_buffer.dart';
import 'package:test/test.dart';

class FakeTransport implements ConfigurationTransport {
  final List<String> calls = [];
  final List<(int, String, Uint8List)> sent = [];
  final List<(int, int, Uint8List)> packets = [];
  ConfigurationException? failWith;

  @override
  void sendPayload(int connectionId, String channel, Uint8List data) {
    if (failWith != null) throw failWith!;
    calls.add('send $connectionId $channel');
    sent.add((connectionId, channel, data));
  }

  @override
  void sendPacket(int connectionId, int packetId, Uint8List payload) {
    if (failWith != null) throw failWith!;
    calls.add('packet $connectionId $packetId');
    packets.add((connectionId, packetId, payload));
  }

  @override
  void release(int connectionId) {
    if (failWith != null) throw failWith!;
    calls.add('release $connectionId');
  }

  @override
  void setFlavour(int connectionId, ConnectionFlavour flavour) {
    if (failWith != null) throw failWith!;
    calls.add('flavour $connectionId ${flavour.name}');
  }

  @override
  void disconnect(int connectionId, String reason) {
    if (failWith != null) throw failWith!;
    calls.add('disconnect $connectionId $reason');
  }
}

Uint8List bytes(List<int> v) => Uint8List.fromList(v);

const hello = 'mymod:hello';
const ack = 'mymod:ack';
const short = Duration(milliseconds: 20);

void main() {
  late FakeTransport transport;
  late ConfigurationSessions sessions;

  ConfigurationConnection start({
    int id = 1,
    Duration? holdTimeout = const Duration(seconds: 30),
    bool Function(ConfigurationConnection)? where,
  }) => sessions.start(
    id: id,
    uuid: '00112233-4455-6677-8899-aabbccddeeff',
    username: 'Steve',
    protocolVersion: 774,
    holdTimeout: holdTimeout,
    where: where,
  )!;

  setUp(() {
    transport = FakeTransport();
    sessions = ConfigurationSessions(transport);
  });

  group('start and hold', () {
    test('holds with the default timeout', () {
      final c = start();
      expect(c.holdRequested, isTrue);
      expect(c.holdTimeoutSeconds, 30);
      expect(c.isHeld, isTrue);
      expect(c.id, 1);
      expect(c.username, 'Steve');
      expect(c.protocolVersion, 774);
      expect(c.brand, isNull);
    });

    test('no holdTimeout means no hold', () {
      final c = start(holdTimeout: null);
      expect(c.holdRequested, isFalse);
      expect(c.holdTimeoutSeconds, 0);
      expect(c.isHeld, isFalse);
    });

    test('rounds the timeout up to whole seconds, at least one', () {
      expect(
        start(holdTimeout: const Duration(milliseconds: 1)).holdTimeoutSeconds,
        1,
      );
      expect(
        start(holdTimeout: const Duration(milliseconds: 1001))
            .holdTimeoutSeconds,
        2,
      );
      expect(
        start(holdTimeout: const Duration(minutes: 1)).holdTimeoutSeconds,
        60,
      );
    });

    test('where can decline a client', () {
      final c = sessions.start(
        id: 5,
        uuid: 'u',
        username: 'Alex',
        protocolVersion: 1,
        where: (c) => c.username == 'Steve',
        holdTimeout: const Duration(seconds: 5),
      );
      expect(c, isNull);
      expect(sessions.length, 0);
    });

    test(
      'where can hold with its own timeout, which wins over holdTimeout',
      () {
        final c = start(
          holdTimeout: const Duration(seconds: 30),
          where: (c) {
            c.hold(timeout: const Duration(seconds: 7));
            return true;
          },
        );
        expect(c.holdTimeoutSeconds, 7);
      },
    );

    test('an exception in where propagates and tracks nothing', () {
      expect(
        () => start(where: (_) => throw StateError('bad filter')),
        throwsStateError,
      );
      expect(sessions.length, 0);
    });

    test('hold is only allowed while the start event is handled', () {
      final c = start(holdTimeout: null);
      expect(() => c.hold(), throwsStateError);
    });

    test('hold rejects a non-positive timeout', () {
      expect(
        () => start(
          holdTimeout: null,
          where: (c) {
            c.hold(timeout: Duration.zero);
            return true;
          },
        ),
        throwsArgumentError,
      );
    });
  });

  group('send', () {
    test('goes through the transport', () async {
      final c = start();
      c.send(hello, [1, 2, 3]);
      c.sendString(hello, 'hi');
      c.sendTyped(hello, PayloadCodecs.string, 'x');
      expect(transport.calls, [
        'send 1 $hello',
        'send 1 $hello',
        'send 1 $hello',
      ]);
      expect(transport.sent[0].$3, [1, 2, 3]);
      expect(transport.sent[1].$3, [104, 105]);
      expect(transport.sent[2].$3, [1, 120]);
    });

    test('rejects bad channel names', () {
      final c = start();
      expect(() => c.send('nonamespace', []), throwsArgumentError);
      expect(() => c.send('a:b:c', []), throwsArgumentError);
      expect(() => c.send(':b', []), throwsArgumentError);
    });

    test('throws once the connection ended', () {
      final c = start();
      sessions.end(id: 1, completed: true);
      expect(
        () => c.send(hello, []),
        throwsA(isA<ConnectionClosedException>()),
      );
    });

    test('surfaces server errors', () {
      final c = start();
      transport.failWith = const ConfigurationException('not configuring');
      expect(
        () => c.send(hello, []),
        throwsA(
          isA<ConfigurationException>().having(
            (e) => e.message,
            'message',
            'not configuring',
          ),
        ),
      );
    });
  });

  group('next', () {
    test('returns a payload that arrived before the call', () async {
      final c = start();
      sessions.payload(id: 1, channel: ack, data: [1]);
      sessions.payload(id: 1, channel: ack, data: [2]);
      expect(await c.next(ack), [1]);
      expect(await c.next(ack), [2]);
    });

    test('completes when the payload arrives', () async {
      final c = start();
      final future = c.next(ack);
      var done = false;
      unawaited(future.then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      sessions.payload(id: 1, channel: ack, data: [9]);
      expect(await future, [9]);
    });

    test('hands payloads to waiters in order', () async {
      final c = start();
      final first = c.next(ack);
      final second = c.next(ack);
      sessions.payload(id: 1, channel: ack, data: [1]);
      sessions.payload(id: 1, channel: ack, data: [2]);
      expect(await first, [1]);
      expect(await second, [2]);
    });

    test('channels are independent', () async {
      final c = start();
      sessions.payload(id: 1, channel: 'mymod:other', data: [7]);
      final future = c.next(ack, timeout: short);
      expect(await future, isNull);
      expect(await c.next('mymod:other'), [7]);
    });

    test('times out with null', () async {
      final c = start();
      final watch = Stopwatch()..start();
      expect(await c.next(ack, timeout: short), isNull);
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(15));
      // A late payload is queued for the next call, not lost.
      sessions.payload(id: 1, channel: ack, data: [5]);
      expect(await c.next(ack), [5]);
    });

    test('a zero timeout only polls the queue', () async {
      final c = start();
      expect(await c.next(ack, timeout: Duration.zero), isNull);
      sessions.payload(id: 1, channel: ack, data: [1]);
      expect(await c.next(ack, timeout: Duration.zero), [1]);
    });

    test('a timed out waiter does not swallow the next payload', () async {
      final c = start();
      expect(await c.next(ack, timeout: short), isNull);
      final again = c.next(ack);
      sessions.payload(id: 1, channel: ack, data: [3]);
      expect(await again, [3]);
    });

    test('without a timeout it waits until the connection ends', () async {
      final c = start();
      final future = c.next(ack, timeout: null);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      sessions.end(id: 1, completed: false);
      await expectLater(future, throwsA(isA<ConnectionClosedException>()));
    });

    test('pending calls fail when the connection ends', () async {
      final c = start();
      final a = c.next(ack);
      final b = c.next('mymod:other', timeout: const Duration(seconds: 30));
      sessions.end(id: 1, completed: false);
      await expectLater(a, throwsA(isA<ConnectionClosedException>()));
      await expectLater(b, throwsA(isA<ConnectionClosedException>()));
    });

    test('calls after the end fail, queued payloads are discarded', () async {
      final c = start();
      sessions.payload(id: 1, channel: ack, data: [1]);
      sessions.end(id: 1, completed: true);
      await expectLater(c.next(ack), throwsA(isA<ConnectionClosedException>()));
    });

    test(
      'an abandoned future does not raise an uncaught error on end',
      () async {
        final errors = <Object>[];
        await runZonedGuarded(() async {
          final c = start();
          c.next(ack); // never awaited
          sessions.end(id: 1, completed: false);
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }, (e, s) => errors.add(e));
        expect(errors, isEmpty);
      },
    );

    test('keeps at most maxQueuedPayloadsPerChannel', () async {
      final c = start();
      for (var i = 0; i < maxQueuedPayloadsPerChannel + 5; i++) {
        sessions.payload(id: 1, channel: ack, data: [i]);
      }
      expect(c.droppedPayloads, 5);
      for (var i = 0; i < maxQueuedPayloadsPerChannel; i++) {
        expect(await c.next(ack), [i]);
      }
      expect(await c.next(ack, timeout: Duration.zero), isNull);
    });

    test('validates the channel name', () {
      final c = start();
      expect(() => c.next('bad'), throwsArgumentError);
    });

    test('nextTyped decodes, and surfaces malformed payloads', () async {
      final c = start();
      sessions.payload(id: 1, channel: ack, data: [2, 0x68, 0x69]);
      expect(await c.nextTyped(ack, PayloadCodecs.string), 'hi');
      expect(
        await c.nextTyped(ack, PayloadCodecs.string, timeout: short),
        isNull,
      );
      sessions.payload(id: 1, channel: ack, data: [9, 1]);
      await expectLater(
        c.nextTyped(ack, PayloadCodecs.string),
        throwsA(isA<PacketUnderflowException>()),
      );
    });

    test('payloads update the brand', () {
      final c = start();
      sessions.payload(id: 1, channel: ack, data: [], brand: 'neoforge');
      expect(c.brand, 'neoforge');
      sessions.payload(id: 1, channel: ack, data: []);
      expect(c.brand, 'neoforge');
    });
  });

  group('release and disconnect', () {
    test('release calls the server once', () {
      final c = start();
      c.release();
      c.release();
      expect(transport.calls, ['release 1']);
      expect(c.isReleased, isTrue);
      expect(c.isHeld, isFalse);
    });

    test('release is a no-op for a connection that was not held', () {
      final c = start(holdTimeout: null);
      c.release();
      expect(transport.calls, isEmpty);
    });

    test('release after the end throws', () {
      final c = start();
      sessions.end(id: 1, completed: false);
      expect(() => c.release(), throwsA(isA<ConnectionClosedException>()));
    });

    test('payloads can still be awaited after release', () async {
      final c = start();
      c.release();
      sessions.payload(id: 1, channel: ack, data: [1]);
      expect(await c.next(ack), [1]);
    });

    test('disconnect tells the server and fails pending calls', () async {
      final c = start();
      final pending = c.next(ack, timeout: const Duration(seconds: 30));
      c.disconnect('bye');
      expect(transport.calls, ['disconnect 1 bye']);
      expect(c.isClosed, isTrue);
      expect(c.completed, isFalse);
      await expectLater(pending, throwsA(isA<ConnectionClosedException>()));
      await expectLater(c.done, completion(isFalse));
    });

    test('disconnect is idempotent', () {
      final c = start();
      c.disconnect('bye');
      c.disconnect('bye again');
      expect(transport.calls, ['disconnect 1 bye']);
    });

    test('disconnect closes locally even if the server errors', () {
      final c = start();
      transport.failWith = const ConfigurationException('gone');
      expect(() => c.disconnect('bye'), throwsA(isA<ConfigurationException>()));
      expect(c.isClosed, isTrue);
    });

    test('the end event after a disconnect is harmless', () {
      final c = start();
      c.disconnect('bye');
      expect(sessions.end(id: 1, completed: false), same(c));
      expect(c.completed, isFalse);
    });
  });

  group('done', () {
    test('completes with whether the client finished', () async {
      final a = start(id: 1);
      final b = start(id: 2);
      sessions.end(id: 1, completed: true);
      sessions.end(id: 2, completed: false);
      expect(await a.done, isTrue);
      expect(await b.done, isFalse);
      expect(a.completed, isTrue);
      expect(a.isClosed, isTrue);
    });
  });

  group('sessions', () {
    test('ignore events of unknown connections', () {
      expect(sessions.payload(id: 99, channel: ack, data: []), isNull);
      expect(sessions.end(id: 99, completed: true), isNull);
    });

    test('forget connections that ended', () {
      start();
      expect(sessions.length, 1);
      sessions.end(id: 1, completed: true);
      expect(sessions.length, 0);
      expect(sessions[1], isNull);
    });

    test('a reused id replaces a stale connection', () async {
      final old = start();
      final pending = old.next(ack);
      final fresh = start();
      expect(sessions[1], same(fresh));
      await expectLater(pending, throwsA(isA<ConnectionClosedException>()));
    });

    test('connections do not share payloads', () async {
      final a = start(id: 1);
      final b = start(id: 2);
      sessions.payload(id: 2, channel: ack, data: [2]);
      expect(await a.next(ack, timeout: short), isNull);
      expect(await b.next(ack), [2]);
    });

    test('closeAll disconnects held connections only', () async {
      final held = start(id: 1);
      final free = start(id: 2, holdTimeout: null);
      final released = start(id: 3)..release();
      transport.calls.clear();
      final pending = held.next(ack, timeout: const Duration(seconds: 30));
      sessions.closeAll('reloading');
      expect(transport.calls, ['disconnect 1 reloading']);
      expect(sessions.length, 0);
      expect(free.isClosed, isTrue);
      expect(released.isClosed, isTrue);
      await expectLater(pending, throwsA(isA<ConnectionClosedException>()));
    });

    test('closeAll survives server errors', () {
      start();
      transport.failWith = const ConfigurationException('gone');
      expect(() => sessions.closeAll('x'), returnsNormally);
    });
  });

  group('runConnectionHandler', () {
    late List<String> errors;

    setUp(() => errors = []);

    Future<void> run(
      ConfigurationConnection c,
      ConfigurationHandler handler, {
      bool releaseOnReturn = false,
    }) => runConnectionHandler(
      c,
      handler,
      onError: errors.add,
      releaseOnReturn: releaseOnReturn,
      failureMessage: 'handshake failed',
    );

    test('a successful handshake', () async {
      final c = start();
      final finished = run(c, (c) async {
        c.send(hello, [1]);
        final reply = await c.next(ack, timeout: const Duration(seconds: 5));
        if (reply == null) {
          c.disconnect('mod required');
          return;
        }
        c.release();
      });
      await Future<void>.delayed(Duration.zero);
      sessions.payload(id: 1, channel: ack, data: [1]);
      await finished;
      expect(transport.calls, ['send 1 $hello', 'release 1']);
      expect(errors, isEmpty);
    });

    test('a client without the mod times out and is disconnected', () async {
      final c = start();
      await run(c, (c) async {
        c.send(hello, [1]);
        final reply = await c.next(ack, timeout: short);
        if (reply == null) {
          c.disconnect('mod required');
          return;
        }
        c.release();
      });
      expect(transport.calls, ['send 1 $hello', 'disconnect 1 mod required']);
      expect(errors, isEmpty);
    });

    test(
      'an exception while holding disconnects with the generic message',
      () async {
        final c = start();
        await run(c, (c) async {
          await Future<void>.delayed(Duration.zero);
          throw StateError('secret detail');
        });
        expect(transport.calls, ['disconnect 1 handshake failed']);
        expect(errors, hasLength(1));
        expect(errors.single, contains('secret detail'));
        expect(transport.calls.join(), isNot(contains('secret')));
      },
    );

    test('a synchronous exception is handled too', () async {
      final c = start();
      await run(c, (c) => throw StateError('boom'));
      expect(transport.calls, ['disconnect 1 handshake failed']);
    });

    test('returning without a decision disconnects (fail closed)', () async {
      final c = start();
      await run(c, (c) async {});
      expect(transport.calls, ['disconnect 1 handshake failed']);
      expect(errors.single, contains('without releasing'));
    });

    test('releaseOnReturn releases on a normal return', () async {
      final c = start();
      await run(c, (c) async {}, releaseOnReturn: true);
      expect(transport.calls, ['release 1']);
      expect(errors, isEmpty);
    });

    test('releaseOnReturn still disconnects after an exception', () async {
      final c = start();
      await run(c, (c) => throw StateError('x'), releaseOnReturn: true);
      expect(transport.calls, ['disconnect 1 handshake failed']);
    });

    test('an exception without a hold does not disconnect', () async {
      final c = start(holdTimeout: null);
      await run(c, (c) => throw StateError('x'));
      expect(transport.calls, isEmpty);
      expect(errors, hasLength(1));
    });

    test('the client leaving is not an error', () async {
      final c = start();
      final finished = run(c, (c) async {
        await c.next(ack, timeout: const Duration(seconds: 30));
      });
      await Future<void>.delayed(Duration.zero);
      sessions.end(id: 1, completed: false);
      await finished;
      expect(errors, isEmpty);
      expect(transport.calls, isEmpty);
    });

    test('a handler that already disconnected is left alone', () async {
      final c = start();
      await run(c, (c) async => c.disconnect('no'));
      expect(transport.calls, ['disconnect 1 no']);
      expect(errors, isEmpty);
    });

    test('failing to disconnect is reported, not thrown', () async {
      final c = start();
      transport.failWith = const ConfigurationException('gone');
      await run(c, (c) => throw StateError('x'));
      expect(errors, hasLength(2));
      expect(errors.last, contains('gone'));
    });
  });
}
