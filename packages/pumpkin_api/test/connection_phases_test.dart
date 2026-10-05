// Packets, the finish hold point and the login phase of configuration_core.dart.
import 'dart:async';
import 'dart:typed_data';

import 'package:pumpkin_api/src/configuration_core.dart';
import 'package:test/test.dart';

class FakeConfigTransport implements ConfigurationTransport {
  final List<String> calls = [];
  final List<Uint8List> packetBodies = [];
  ConfigurationException? failFlavour;

  @override
  void sendPayload(int connectionId, String channel, Uint8List data) =>
      calls.add('send $connectionId $channel');

  @override
  void sendPacket(int connectionId, int packetId, Uint8List payload) {
    calls.add('packet $connectionId $packetId');
    packetBodies.add(payload);
  }

  @override
  void release(int connectionId) => calls.add('release $connectionId');

  @override
  void setFlavour(int connectionId, ConnectionFlavour flavour) {
    if (failFlavour != null) throw failFlavour!;
    calls.add('flavour $connectionId ${flavour.name}');
  }

  @override
  void disconnect(int connectionId, String reason) =>
      calls.add('disconnect $connectionId $reason');
}

class FakeLoginTransport implements LoginTransport {
  final List<String> calls = [];
  final List<(int, int, String, Uint8List)> queries = [];
  ConfigurationException? failQuery;

  @override
  void sendQuery(
    int connectionId,
    int queryId,
    String channel,
    Uint8List data,
  ) {
    if (failQuery != null) throw failQuery!;
    calls.add('query $connectionId $queryId $channel');
    queries.add((connectionId, queryId, channel, data));
  }

  @override
  void release(int connectionId) => calls.add('release $connectionId');

  @override
  void disconnect(int connectionId, String reason) =>
      calls.add('disconnect $connectionId $reason');
}

const short = Duration(milliseconds: 20);

void main() {
  group('configuration packets', () {
    late FakeConfigTransport transport;
    late ConfigurationSessions sessions;
    late ConfigurationConnection c;

    setUp(() {
      transport = FakeConfigTransport();
      sessions = ConfigurationSessions(transport);
      c = sessions.start(
        id: 1,
        uuid: 'u',
        username: 'Steve',
        protocolVersion: 774,
        holdTimeout: const Duration(seconds: 30),
      )!;
    });

    test('sendPacket goes through the transport', () {
      c.sendPacket(0x0e, [1, 2]);
      expect(transport.calls, ['packet 1 14']);
      expect(transport.packetBodies.single, [1, 2]);
    });

    test('sendPacket after the end throws', () {
      sessions.end(id: 1, completed: true);
      expect(
        () => c.sendPacket(1, []),
        throwsA(isA<ConnectionClosedException>()),
      );
    });

    test('onPacket sees every packet and can cancel', () {
      final seen = <(int, Uint8List)>[];
      bool onPacket(ConfigurationConnection conn, int id, Uint8List body) {
        seen.add((id, body));
        return id == 7;
      }

      expect(
        sessions.packet(id: 1, packetId: 2, payload: [9], onPacket: onPacket),
        isFalse,
      );
      expect(
        sessions.packet(id: 1, packetId: 7, payload: [8], onPacket: onPacket),
        isTrue,
      );
      expect(seen.map((e) => e.$1), [2, 7]);
      expect(seen.map((e) => e.$2.toList()), [
        [9],
        [8],
      ]);
    });

    test('unknown or closed connections are never cancelled', () {
      expect(
        sessions.packet(
          id: 99,
          packetId: 7,
          payload: [],
          onPacket: (_, _, _) => true,
        ),
        isFalse,
      );
      sessions.end(id: 1, completed: false);
      expect(
        sessions.packet(
          id: 1,
          packetId: 7,
          payload: [],
          onPacket: (_, _, _) => true,
        ),
        isFalse,
      );
    });

    test('an exception in onPacket propagates (the wiring logs it)', () {
      expect(
        () => sessions.packet(
          id: 1,
          packetId: 7,
          payload: [],
          onPacket: (_, _, _) => throw StateError('x'),
        ),
        throwsStateError,
      );
    });

    test(
      'captured packets can be awaited, also when they came first',
      () async {
        sessions.packet(id: 1, packetId: 3, payload: [1], capture: true);
        expect(await c.nextPacket(3), [1]);
        final later = c.nextPacket(3);
        sessions.packet(id: 1, packetId: 3, payload: [2], capture: true);
        expect(await later, [2]);
      },
    );

    test('packets are only queued when captured', () async {
      sessions.packet(id: 1, packetId: 3, payload: [1]);
      expect(await c.nextPacket(3, timeout: short), isNull);
    });

    test(
      'nextPacket times out with null and fails when the connection ends',
      () async {
        expect(await c.nextPacket(5, timeout: short), isNull);
        final pending = c.nextPacket(5, timeout: const Duration(seconds: 30));
        sessions.end(id: 1, completed: false);
        await expectLater(pending, throwsA(isA<ConnectionClosedException>()));
        await expectLater(
          c.nextPacket(5),
          throwsA(isA<ConnectionClosedException>()),
        );
      },
    );

    test('packet ids and channels are separate keys', () async {
      sessions.packet(id: 1, packetId: 2, payload: [1], capture: true);
      sessions.payload(id: 1, channel: 'a:b', data: [2]);
      expect(await c.next('a:b'), [2]);
      expect(await c.nextPacket(2), [1]);
    });
  });

  group('finish hold point', () {
    late FakeConfigTransport transport;
    late ConfigurationSessions sessions;

    setUp(() {
      transport = FakeConfigTransport();
      sessions = ConfigurationSessions(transport);
    });

    ConfigurationConnection start({Duration? holdTimeout}) => sessions.start(
      id: 1,
      uuid: 'u',
      username: 'Steve',
      protocolVersion: 774,
      holdTimeout: holdTimeout,
    )!;

    test('holds again after the start hold was released', () {
      final c = start(holdTimeout: const Duration(seconds: 30));
      expect(c.holdEpoch, 1);
      c.release();
      expect(c.isHeld, isFalse);

      final f = sessions.finish(
        id: 1,
        holdTimeout: const Duration(seconds: 12),
      );
      expect(f, same(c));
      expect(c.holdRequested, isTrue);
      expect(c.holdTimeoutSeconds, 12);
      expect(c.isHeld, isTrue);
      expect(c.isReleased, isFalse);
      expect(c.holdEpoch, 2);

      c.release();
      expect(c.isHeld, isFalse);
      expect(c.isReleased, isTrue);
      expect(transport.calls, ['release 1', 'release 1']);
    });

    test('works without a start hold', () {
      final c = start();
      expect(c.holdEpoch, 0);
      sessions.finish(id: 1, holdTimeout: const Duration(seconds: 5));
      expect(c.holdEpoch, 1);
      expect(c.isHeld, isTrue);
    });

    test('no hold timeout means no hold at finish', () {
      final c = start();
      sessions.finish(id: 1);
      expect(c.holdRequested, isFalse);
      expect(c.isHeld, isFalse);
    });

    test('unknown and closed connections are ignored', () {
      expect(sessions.finish(id: 5, holdTimeout: short), isNull);
      start();
      sessions.end(id: 1, completed: false);
      expect(sessions.finish(id: 1, holdTimeout: short), isNull);
    });

    test('hold is rejected outside the event', () {
      final c = start();
      sessions.finish(id: 1);
      expect(() => c.hold(), throwsStateError);
    });

    test('closeAll disconnects a connection held at finish', () {
      final c = start(holdTimeout: const Duration(seconds: 30));
      c.release();
      sessions.finish(id: 1, holdTimeout: const Duration(seconds: 30));
      transport.calls.clear();
      sessions.closeAll('reload');
      expect(transport.calls, ['disconnect 1 reload']);
    });

    group('handlers of the two hold points', () {
      late List<String> errors;
      setUp(() => errors = []);

      Future<void> run(
        ConfigurationConnection c,
        ConfigurationHandler handler,
      ) => runConnectionHandler(
        c,
        handler,
        onError: errors.add,
        failureMessage: 'failed',
      );

      test(
        'the first handler returning does not touch the finish hold',
        () async {
          final c = start(holdTimeout: const Duration(seconds: 30));
          final gate = Completer<void>();
          final first = run(c, (c) async {
            await gate.future;
            // Returns without releasing: but by then the start hold was
            // released by someone else and the finish hold belongs to the
            // other handler.
          });
          c.release();
          sessions.finish(id: 1, holdTimeout: const Duration(seconds: 30));
          gate.complete();
          await first;
          expect(c.isHeld, isTrue);
          expect(transport.calls, ['release 1']);
          expect(errors, isEmpty);
        },
      );

      test('the finish handler fails closed on its own hold', () async {
        final c = start(holdTimeout: const Duration(seconds: 30));
        c.release();
        sessions.finish(id: 1, holdTimeout: const Duration(seconds: 30));
        await run(c, (c) => throw StateError('loader failed'));
        expect(transport.calls, ['release 1', 'disconnect 1 failed']);
        expect(errors.single, contains('loader failed'));
      });

      test(
        'a start handler without a hold leaves the finish hold alone',
        () async {
          final c = start();
          final gate = Completer<void>();
          final first = run(c, (c) => gate.future);
          sessions.finish(id: 1, holdTimeout: const Duration(seconds: 30));
          gate.complete();
          await first;
          expect(c.isHeld, isTrue);
          expect(transport.calls, isEmpty);
        },
      );

      test('a full loader-style handshake over both hold points', () async {
        final c = start(holdTimeout: const Duration(seconds: 30));
        final startDone = run(c, (c) async {
          c.send('minecraft:register', [1]);
          final reply = await c.nextPacket(0x02, timeout: short);
          if (reply == null) return c.disconnect('mod required');
          c.release();
        });
        sessions.packet(id: 1, packetId: 0x02, payload: [1], capture: true);
        await startDone;
        expect(c.isHeld, isFalse);

        sessions.finish(id: 1, holdTimeout: const Duration(seconds: 30));
        final finishDone = run(c, (c) async {
          c.sendPacket(0x0e, [7]);
          final done = await c.nextPacket(0x0f, timeout: short);
          if (done == null) return c.disconnect('loader step failed');
          c.release();
        });
        sessions.packet(id: 1, packetId: 0x0f, payload: [], capture: true);
        await finishDone;
        expect(transport.calls, [
          'send 1 minecraft:register',
          'release 1',
          'packet 1 14',
          'release 1',
        ]);
        expect(errors, isEmpty);
      });
    });
  });

  group('pre-brand hold point', () {
    late FakeConfigTransport transport;
    late ConfigurationSessions sessions;
    final errors = <String>[];

    ConfigurationConnection? preBrand({
      bool Function(ConfigurationConnection)? where,
      Duration? holdTimeout = const Duration(seconds: 30),
    }) => sessions.preBrand(
      id: 1,
      uuid: 'u',
      username: 'Steve',
      protocolVersion: 774,
      where: where,
      holdTimeout: holdTimeout,
    );

    ConfigurationConnection? start({
      bool Function(ConfigurationConnection)? where,
      Duration? holdTimeout = const Duration(seconds: 30),
    }) => sessions.start(
      id: 1,
      uuid: 'u',
      username: 'Steve',
      protocolVersion: 774,
      where: where,
      holdTimeout: holdTimeout,
    );

    setUp(() {
      transport = FakeConfigTransport();
      sessions = ConfigurationSessions(transport);
      errors.clear();
    });

    test('the pre-brand hold is requested, then the start hold of the same '
        'connection', () {
      final c = preBrand()!;
      expect(c.stage, ConfigurationStage.preBrand);
      expect(c.holdRequested, isTrue);
      expect(c.isHeld, isTrue);
      expect(c.holdEpoch, 1);

      c.release();
      expect(transport.calls, ['release 1']);
      expect(c.isHeld, isFalse);
      expect(c.isReleased, isTrue);

      final same = start()!;
      expect(identical(same, c), isTrue);
      expect(c.stage, ConfigurationStage.start);
      expect(c.isHeld, isTrue);
      expect(c.isReleased, isFalse);
      expect(c.holdEpoch, 2);

      c.release();
      expect(transport.calls, ['release 1', 'release 1']);
    });

    test('queued payloads carry over from the pre-brand to the start stage',
        () async {
      final c = preBrand()!;
      sessions.payload(id: 1, channel: 'a:b', data: [7], brand: 'neoforge');
      c.release();
      start();
      expect(c.brand, 'neoforge');
      expect(await c.next('a:b', timeout: Duration.zero), [7]);
    });

    test('the start stage without a hold timeout does not hold', () {
      final c = preBrand()!;
      c.release();
      final same = start(holdTimeout: null)!;
      expect(same.holdRequested, isFalse);
      expect(same.isHeld, isFalse);
      expect(same.holdEpoch, 1);
    });

    test('without a pre-brand event start behaves as before', () {
      final c = start()!;
      expect(c.stage, ConfigurationStage.start);
      expect(c.holdRequested, isTrue);
      expect(c.holdEpoch, 1);
    });

    test('where is asked once, at the pre-brand event', () {
      var asked = 0;
      final c = preBrand(
        where: (c) {
          asked++;
          return true;
        },
      )!;
      c.release();
      start(
        where: (c) {
          asked++;
          return true;
        },
      );
      expect(asked, 1);
    });

    test('a client where declined at the pre-brand is not handled at the '
        'start either', () {
      expect(preBrand(where: (c) => false), isNull);
      expect(start(), isNull);
      expect(sessions.length, 0);
      // The end of that connection forgets the decision: id 1 is new again.
      sessions.end(id: 1, completed: false);
      expect(start(), isNotNull);
    });

    test('where can request the pre-brand hold of this client', () {
      final c = preBrand(
        where: (c) {
          c.hold(timeout: const Duration(seconds: 9));
          return true;
        },
        holdTimeout: null,
      )!;
      expect(c.holdRequested, isTrue);
      expect(c.holdTimeoutSeconds, 9);
    });

    test('a pre-brand handler that outlives its hold is not blamed for the '
        'start hold', () async {
      final c = preBrand()!;
      final finishUp = Completer<void>();
      final running = runConnectionHandler<ConfigurationConnection>(
        c,
        (c) async {
          c.release();
          await finishUp.future;
        },
        onError: errors.add,
      );
      await Future<void>.delayed(Duration.zero);
      start(); // the start hold begins while the handler is still running
      finishUp.complete();
      await running;
      expect(transport.calls, ['release 1']);
      expect(c.isHeld, isTrue, reason: 'the start hold is untouched');
      expect(errors, isEmpty);
    });

    test('a pre-brand handler that returns without releasing fails closed',
        () async {
      final c = preBrand()!;
      await runConnectionHandler<ConfigurationConnection>(
        c,
        (c) async {},
        onError: errors.add,
      );
      expect(transport.calls.single, startsWith('disconnect 1 '));
      expect(errors.single, contains('without releasing'));
    });

    test('the finish stage follows the start stage', () {
      final c = preBrand()!;
      c.release();
      start()!.release();
      final finish = sessions.finish(
        id: 1,
        holdTimeout: const Duration(seconds: 30),
      )!;
      expect(identical(finish, c), isTrue);
      expect(c.stage, ConfigurationStage.finish);
      expect(c.holdEpoch, 3);
    });

    test('closeAll disconnects a connection held at the pre-brand', () {
      final c = preBrand()!;
      sessions.closeAll('reload');
      expect(transport.calls, ['disconnect 1 reload']);
      expect(c.isClosed, isTrue);
    });

    group('setFlavour', () {
      test('goes through the transport and is remembered', () {
        final c = preBrand()!;
        expect(c.flavour, ConnectionFlavour.vanilla);
        c.setFlavour(ConnectionFlavour.neoforge);
        expect(transport.calls, ['flavour 1 neoforge']);
        expect(c.flavour, ConnectionFlavour.neoforge);
      });

      test('the host refusing throws and keeps the flavour', () {
        final c = preBrand()!;
        transport.failFlavour = const ConfigurationException('too late');
        expect(
          () => c.setFlavour(ConnectionFlavour.neoforge),
          throwsA(isA<ConfigurationException>()),
        );
        expect(c.flavour, ConnectionFlavour.vanilla);
      });

      test('a closed connection throws', () {
        final c = preBrand()!;
        sessions.end(id: 1, completed: false);
        expect(
          () => c.setFlavour(ConnectionFlavour.neoforge),
          throwsA(isA<ConnectionClosedException>()),
        );
      });
    });
  });

  group('login', () {
    late FakeLoginTransport transport;
    late LoginSessions sessions;

    setUp(() {
      transport = FakeLoginTransport();
      sessions = LoginSessions(transport);
    });

    LoginConnection start({
      int id = 1,
      bool Function(LoginConnection)? where,
      Duration holdTimeout = const Duration(seconds: 30),
    }) => sessions.start(
      id: id,
      uuid: '00112233-4455-6677-8899-aabbccddeeff',
      username: 'Steve',
      protocolVersion: 774,
      holdTimeout: holdTimeout,
      where: where,
    )!;

    test('is held with the timeout', () {
      final l = start(holdTimeout: const Duration(milliseconds: 1500));
      expect(l.holdRequested, isTrue);
      expect(l.holdTimeoutSeconds, 2);
      expect(l.isHeld, isTrue);
      expect(l.username, 'Steve');
      expect(l.protocolVersion, 774);
    });

    test('where can decline', () {
      expect(
        sessions.start(
          id: 1,
          uuid: 'u',
          username: 'Alex',
          protocolVersion: 1,
          holdTimeout: short,
          where: (l) => false,
        ),
        isNull,
      );
      expect(sessions.length, 0);
    });

    test('query sends with a high id and completes with the answer', () async {
      final l = start();
      final future = l.query('mymod:hello', [1, 2]);
      expect(transport.queries, hasLength(1));
      final (connectionId, queryId, channel, data) = transport.queries.single;
      expect(connectionId, 1);
      expect(queryId, greaterThanOrEqualTo(loginQueryIdBase));
      expect(channel, 'mymod:hello');
      expect(data, [1, 2]);
      expect(sessions.answer(id: 1, queryId: queryId, data: [9]), isTrue);
      expect(await future, [9]);
    });

    test('query ids are unique', () async {
      final l = start();
      final a = l.query('a:b', [], timeout: short);
      final b = l.query('a:b', [], timeout: short);
      expect(transport.queries[0].$2, isNot(transport.queries[1].$2));
      await Future.wait([a, b]);
    });

    test('an explicit query id is used', () async {
      final l = start();
      final future = l.query('a:b', [], queryId: 4, timeout: short);
      expect(transport.queries.single.$2, 4);
      sessions.answer(id: 1, queryId: 4, data: [1]);
      expect(await future, [1]);
    });

    test(
      'an answer without data means the client did not understand',
      () async {
        final l = start();
        final future = l.query('a:b', []);
        sessions.answer(id: 1, queryId: transport.queries.single.$2);
        expect(await future, isNull);
      },
    );

    test('times out with null, a late answer is ignored', () async {
      final l = start();
      final future = l.query('a:b', [], timeout: short);
      expect(await future, isNull);
      expect(
        sessions.answer(id: 1, queryId: transport.queries.single.$2, data: [1]),
        isFalse,
      );
    });

    test('answers are matched by query id', () async {
      final l = start();
      final a = l.query('a:one', []);
      final b = l.query('a:two', []);
      final idA = transport.queries[0].$2;
      final idB = transport.queries[1].$2;
      sessions.answer(id: 1, queryId: idB, data: [2]);
      sessions.answer(id: 1, queryId: idA, data: [1]);
      expect(await a, [1]);
      expect(await b, [2]);
    });

    test('answers of other connections do not leak', () async {
      final a = start(id: 1);
      start(id: 2);
      final future = a.query('a:b', [], timeout: short);
      expect(
        sessions.answer(id: 2, queryId: transport.queries.single.$2, data: [1]),
        isFalse,
      );
      expect(await future, isNull);
    });

    test('a refused query throws and leaves no waiter behind', () async {
      final l = start();
      transport.failQuery = const ConfigurationException('id in use');
      await expectLater(
        l.query('a:b', [], queryId: 3),
        throwsA(isA<ConfigurationException>()),
      );
      transport.failQuery = null;
      expect(sessions.answer(id: 1, queryId: 3, data: [1]), isFalse);
    });

    test('validates the channel name', () {
      final l = start();
      expect(l.query('bad', []), throwsArgumentError);
    });

    test('release finishes the connection', () async {
      final l = start();
      final pending = l.query('a:b', [], timeout: const Duration(seconds: 30));
      l.release();
      expect(transport.calls.last, 'release 1');
      expect(l.isClosed, isTrue);
      expect(l.completed, isTrue);
      expect(l.isReleased, isTrue);
      await expectLater(pending, throwsA(isA<ConnectionClosedException>()));
      await expectLater(l.done, completion(isTrue));
      await expectLater(
        l.query('a:b', []),
        throwsA(isA<ConnectionClosedException>()),
      );
    });

    test('disconnect fails pending queries', () async {
      final l = start();
      final pending = l.query('a:b', [], timeout: const Duration(seconds: 30));
      l.disconnect('bye');
      expect(transport.calls.last, 'disconnect 1 bye');
      await expectLater(pending, throwsA(isA<ConnectionClosedException>()));
      await expectLater(l.done, completion(isFalse));
    });

    test('expire fails pending queries and forgets the connection', () async {
      final l = start();
      final pending = l.query('a:b', [], timeout: const Duration(seconds: 30));
      sessions.expire(l);
      expect(sessions.length, 0);
      await expectLater(pending, throwsA(isA<ConnectionClosedException>()));
    });

    test('expire ignores a replaced connection', () {
      final old = start();
      final fresh = start();
      sessions.expire(old);
      expect(sessions[1], same(fresh));
      expect(fresh.isClosed, isFalse);
    });

    test('closeAll disconnects held logins', () async {
      final l = start();
      final pending = l.query('a:b', [], timeout: const Duration(seconds: 30));
      sessions.closeAll('reloading');
      expect(transport.calls.last, 'disconnect 1 reloading');
      await expectLater(pending, throwsA(isA<ConnectionClosedException>()));
    });

    group('handler', () {
      late List<String> errors;
      setUp(() => errors = []);

      Future<void> run(LoginConnection l, LoginHandler handler) =>
          runConnectionHandler(
            l,
            handler,
            onError: errors.add,
            failureMessage: 'failed',
          );

      test('a successful handshake', () async {
        final l = start();
        final finished = run(l, (l) async {
          final answer = await l.query('mymod:hello', [1]);
          if (answer == null) return l.disconnect('mod required');
          l.release();
        });
        await Future<void>.delayed(Duration.zero);
        sessions.answer(id: 1, queryId: transport.queries.single.$2, data: [1]);
        await finished;
        expect(transport.calls.last, 'release 1');
        expect(errors, isEmpty);
      });

      test('a client without the mod is disconnected', () async {
        final l = start();
        final finished = run(l, (l) async {
          final answer = await l.query('mymod:hello', [1]);
          if (answer == null) return l.disconnect('mod required');
          l.release();
        });
        await Future<void>.delayed(Duration.zero);
        // Vanilla answers "I don't understand" (no data).
        sessions.answer(id: 1, queryId: transport.queries.single.$2);
        await finished;
        expect(transport.calls.last, 'disconnect 1 mod required');
        expect(errors, isEmpty);
      });

      test(
        'a throwing handler fails closed with the generic message',
        () async {
          final l = start();
          await run(l, (l) async {
            await Future<void>.delayed(Duration.zero);
            throw StateError('secret');
          });
          expect(transport.calls.last, 'disconnect 1 failed');
          expect(errors.single, contains('secret'));
          expect(transport.calls.join(), isNot(contains('secret')));
        },
      );

      test('returning without a decision disconnects', () async {
        final l = start();
        await run(l, (l) async {});
        expect(transport.calls.last, 'disconnect 1 failed');
        expect(errors.single, contains('without releasing'));
      });

      test('releaseOnReturn releases', () async {
        final l = start();
        await runConnectionHandler(
          l,
          (l) async {},
          onError: errors.add,
          releaseOnReturn: true,
        );
        expect(transport.calls.last, 'release 1');
        expect(errors, isEmpty);
      });

      test('the client vanishing (expiry) is not an error', () async {
        final l = start();
        final finished = run(l, (l) async {
          await l.query('a:b', [], timeout: const Duration(seconds: 30));
        });
        await Future<void>.delayed(Duration.zero);
        sessions.expire(l);
        await finished;
        expect(errors, isEmpty);
        expect(transport.calls, ['query 1 ${transport.queries.single.$2} a:b']);
      });
    });
  });

  test('allocated login query ids stay in the high range', () {
    for (var i = 0; i < 100; i++) {
      final id = allocateLoginQueryId();
      expect(id, inInclusiveRange(loginQueryIdBase, 0x7FFFFFFF));
    }
  });
}
