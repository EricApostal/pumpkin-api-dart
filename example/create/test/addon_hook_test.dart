// The pure half of Create's addon hook: a package can put its channels into a
// declaration without a codec or a handler here, and the registry keeps them in
// registration order, rejects a duplicate id and does not pretend to dispatch
// them.
//
// The host half (`createAddonNeoForgeDeclaration`) needs `pumpkin_api`, so the
// addon packages' own tests and `compat_negotiation_test.dart` cover it.
import 'dart:typed_data';

import 'package:create/src/core/addon.dart';
import 'package:create/src/core/payload.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show PayloadCodec;
import 'package:test/test.dart';

final class _Player {
  const _Player();
}

const _foreign = DeclaredPayload('othermod:sync', '0.1', serverbound: false, optional: false);

/// A second consumer, written here and nowhere else: what an addon outside this
/// repository writes to join a Create server. Create names nothing of it.
final class _SecondAddon extends CreateAddon {
  const _SecondAddon();

  @override
  String get modId => 'othermod';

  @override
  String get version => '0.2.0';

  @override
  String get displayName => 'Other Mod';

  @override
  Iterable<DeclaredPayload> get channels => const [
    DeclaredPayload('othermod:sync', '0.2', serverbound: true, optional: true),
    DeclaredPayload('othermod:state', '0.2', serverbound: false, optional: false),
  ];
}

/// An addon that handles its own channel and keeps the declared-only ones.
final class _HandlingAddon extends CreateAddon {
  const _HandlingAddon();

  @override
  String get modId => 'handledmod';

  @override
  String get version => '1.4.0';

  @override
  Iterable<DeclaredPayload> get channels => const [
    DeclaredPayload('handledmod:extra', '1.4', serverbound: false, optional: false),
  ];

  @override
  void contribute<C>(PayloadRegistry<C> payloads) {
    super.contribute(payloads);
    payloads.serverbound<int>(
      'handledmod:ping',
      PayloadCodec<int>.of(encode: (v) => Uint8List.fromList([v]), decode: (b) => b.first),
      (p, v) {},
      version: '1.4',
    );
  }
}

void main() {
  group('declared-only channels', () {
    test('appear in the declaration, in registration order', () {
      final payloads = PayloadRegistry<_Player>();
      payloads.serverbound<int>('create:one', PayloadCodec<int>.of(encode: (v) => Uint8List.fromList([v]), decode: (b) => b.first), (p, v) {});
      payloads.declare(_foreign);
      payloads.clientbound<int>('create:two', PayloadCodec<int>.of(encode: (v) => Uint8List.fromList([v]), decode: (b) => b.first));

      expect([for (final p in payloads.declared) p.id], ['create:one', 'othermod:sync', 'create:two']);
      final foreign = payloads.declared[1];
      expect(foreign.version, '0.1');
      expect(foreign.serverbound, isFalse);
      expect(foreign.optional, isFalse);
    });

    test('are neither dispatched nor sent: nothing handles them here', () {
      final payloads = PayloadRegistry<_Player>();
      payloads.declare(_foreign);
      expect(payloads.serverboundFor('othermod:sync'), isNull);
      expect(payloads.serverboundIds, isEmpty);
      expect(payloads.clientboundChannels, isEmpty);
    });

    test('a duplicate id is rejected, in either order', () {
      final payloads = PayloadRegistry<_Player>();
      payloads.declare(_foreign);
      expect(() => payloads.declare(_foreign), throwsA(isA<DuplicateChannelException>()));
      expect(
        () => payloads.clientbound<int>('othermod:sync', PayloadCodec<int>.of(encode: (v) => Uint8List.fromList([v]), decode: (b) => b.first)),
        throwsA(isA<DuplicateChannelException>()),
      );
    });

    test('declareAll keeps the table order', () {
      final payloads = PayloadRegistry<_Player>();
      payloads.declareAll(const [
        DeclaredPayload('a:one', '1', serverbound: true, optional: false),
        DeclaredPayload('a:two', '1', serverbound: false, optional: true),
      ]);
      expect([for (final p in payloads.declared) p.id], ['a:one', 'a:two']);
      expect(payloads.declared.last.optional, isTrue);
    });
  });

  group('the generic hook', () {
    test('a second consumer adds its channels without Create naming it', () {
      // The registry already holds Create's channels; the addon only knows
      // `CreateAddon`, never the other way round.
      final payloads = PayloadRegistry<_Player>();
      payloads.serverbound<int>('create:one', PayloadCodec<int>.of(encode: (v) => Uint8List.fromList([v]), decode: (b) => b.first), (p, v) {});

      const _SecondAddon().contribute(payloads);

      expect([for (final p in payloads.declared) p.id], ['create:one', 'othermod:sync', 'othermod:state']);
      final added = payloads.declared.skip(1).toList();
      expect(added[0].version, '0.2');
      expect(added[0].serverbound, isTrue);
      expect(added[0].optional, isTrue);
      expect(added[1].serverbound, isFalse);
      // Declared, not handled: Create dispatches nothing of another mod.
      expect(payloads.serverboundFor('othermod:sync'), isNull);
      expect(payloads.serverboundIds, ['create:one']);
    });

    test('a handling addon keeps its declared-only channels and its handler', () {
      final payloads = PayloadRegistry<_Player>();
      const _HandlingAddon().contribute(payloads);

      expect([for (final p in payloads.declared) p.id], ['handledmod:extra', 'handledmod:ping']);
      expect(payloads.serverboundFor('handledmod:ping'), isNotNull);
      expect(payloads.declared.last.version, '1.4');
    });

    test('two addons contribute to one registry in their own order', () {
      final payloads = PayloadRegistry<_Player>();
      const _SecondAddon().contribute(payloads);
      const _HandlingAddon().contribute(payloads);

      expect(
        [for (final p in payloads.declared) p.id],
        ['othermod:sync', 'othermod:state', 'handledmod:extra', 'handledmod:ping'],
      );
    });

    test('an addon that repeats another mod channel is rejected', () {
      final payloads = PayloadRegistry<_Player>();
      const _SecondAddon().contribute(payloads);
      expect(() => const _SecondAddon().contribute(payloads), throwsA(isA<DuplicateChannelException>()));
    });
  });
}
