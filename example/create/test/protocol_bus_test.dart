import 'dart:async';

import 'package:create/src/core/payload.dart';
import 'package:create/src/manifest/manifest.dart';
import 'package:create/src/protocol/codec_compiler.dart';
import 'package:create/src/protocol/payload_hub.dart';
import 'package:test/test.dart';

final class _Player {
  final String name;

  _Player(this.name);
}

void main() {
  late List<String> logs;
  late int now;
  late PayloadHub<_Player> hub;

  setUp(() {
    logs = [];
    now = 0;
    hub = PayloadHub<_Player>(
      schemas: PayloadSchemas.manifest,
      sink: (level, m) => logs.add('${level.name}: $m'),
      describePlayer: (p) => p.name,
      maxServerboundBytes: 64,
      rateLimitedLog: RateLimitedLog((level, m) => logs.add('${level.name}: $m'), nowMillis: () => now),
    );
  });

  group('registration', () {
    test('all 119 channels are declared exactly like the manifest', () {
      final registry = PayloadRegistry<_Player>();
      registerPayloadChannels<_Player>(registry, hub);
      final declared = registry.declared;
      expect(declared.length, 119);
      expect(declared.where((d) => d.serverbound).length, 67);
      expect(declared.where((d) => !d.serverbound).length, 52);
      // 66 + 48 from AllPackets, 3 catnip, 2 ponder.
      bool createNs(DeclaredPayload d) => d.id.startsWith('create:');
      expect(declared.where((d) => createNs(d) && d.serverbound).length, 66);
      expect(declared.where((d) => createNs(d) && !d.serverbound).length, 48);
      expect(declared.where((d) => d.id.startsWith('catnip:')).length, 3);
      expect(declared.where((d) => d.id.startsWith('ponder:')).length, 2);
      expect(declared.every((d) => d.version == '1' && !d.optional), isTrue);
      expect([for (final d in declared) d.id], [for (final p in networkPayloads) p.id]);
      for (final p in networkPayloads) {
        final d = declared.firstWhere((d) => d.id == p.id);
        expect(d.serverbound, p.direction == NetDirection.serverbound, reason: p.id);
        expect(registry.serverboundFor(p.id) != null, d.serverbound);
      }
      expect(registry.clientboundChannels.length, 52);
    });

    test('registering twice is rejected', () {
      final registry = PayloadRegistry<_Player>();
      registerPayloadChannels<_Player>(registry, hub);
      expect(() => registerPayloadChannels<_Player>(registry, hub), throwsA(isA<DuplicateChannelException>()));
    });
  });

  group('serverbound dispatch', () {
    late PayloadRegistry<_Player> registry;
    const id = 'create:trigger_ejector';

    setUp(() {
      registry = PayloadRegistry<_Player>();
      registerPayloadChannels<_Player>(registry, hub);
    });

    Future<void> receive(String id, List<int> data) async =>
        registry.serverboundFor(id)!.dispatch(_Player('alex'), data);

    test('a valid payload reaches the handler with field names', () async {
      Map<String, Object?>? got;
      _Player? who;
      hub.onServerbound(id, (p, f) {
        who = p;
        got = f;
      });
      await receive(id, hub.encode(id, {'pos': (1, 2, 3)}));
      expect(got, {'pos': (1, 2, 3)});
      expect(who!.name, 'alex');
    });

    test('a throwing handler does not escape and the others still run', () async {
      var second = 0;
      hub.onServerbound(id, (p, f) => throw StateError('boom'));
      hub.onServerbound(id, (p, f) => second++);
      await receive(id, hub.encode(id, {'pos': (1, 2, 3)}));
      expect(second, 1);
      expect(logs.single, contains('boom'));
    });

    test('an async failing handler is contained', () async {
      hub.onServerbound(id, (p, f) async => throw StateError('late'));
      await receive(id, hub.encode(id, {'pos': (1, 2, 3)}));
      await Future<void>.delayed(Duration.zero);
      expect(logs.single, contains('late'));
    });

    test('malformed and oversized payloads are dropped, logging is rate limited', () async {
      var calls = 0;
      hub.onServerbound(id, (p, f) => calls++);
      for (var i = 0; i < 10; i++) {
        await receive(id, [1, 2]);
      }
      await receive(id, List.filled(100, 0)); // oversized
      expect(calls, 0);
      expect(logs.length, 3, reason: 'at most 3 per window per payload id');
      now = 20000;
      await receive(id, [1]);
      expect(logs.any((l) => l.contains('suppressed')), isTrue);
      expect(logs.length, 5);
    });

    test('payloads without a handler are ignored', () async {
      await receive(id, hub.encode(id, {'pos': (1, 2, 3)}));
      expect(logs.where((l) => l.startsWith('warn') || l.startsWith('error')), isEmpty);
    });

    test('onServerbound validates ids and direction', () {
      expect(() => hub.onServerbound('create:nope', (p, f) {}), throwsArgumentError);
      expect(() => hub.onServerbound('create:remove_te', (p, f) {}), throwsArgumentError);
    });
  });

  group('clientbound encoding', () {
    test('valid fields encode, invalid ones are logged and not sent', () {
      expect(hub.encodeClientbound('create:remove_te', {'pos': (1, 2, 3)}), isNotNull);
      expect(hub.encodeClientbound('create:remove_te', {}), isNull);
      expect(hub.encodeClientbound('create:trigger_ejector', {'pos': (1, 2, 3)}), isNull, reason: 'serverbound');
      expect(hub.encodeClientbound('create:unknown', {}), isNull);
      expect(logs.length, 3);
    });

    test('decode / encode helpers round trip', () {
      final bytes = hub.encode('create:funnel_flap', {'pos': (5, 6, 7), 'inwards': true});
      expect(hub.decode('create:funnel_flap', bytes), {'pos': (5, 6, 7), 'inwards': true});
    });
  });
}
