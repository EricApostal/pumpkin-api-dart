// The negotiation a server with Create and the Create-family addons makes: every
// plugin declares its own mod through Create's generic addon hook
// (`package:create/src/core/addon.dart`), the host merges the declarations into
// the one `neoforge:register` answer (`Aggregate::build` in
// `crates/pumpkin-core/src/net/neoforge/declaration.rs`), and this test runs that
// negotiation the way the server does it.
//
// The client is the real one: a Create client with Sable, Simulated, Aeronautics
// and Offroad, whose channel set is read from the committed port inventory
// (`docs/aero-port-manifest.json`, produced by a different code path than the
// tables below). A channel that is missing, has another flow or another version
// fails here — the same reason the client's mismatch screen would show.
import 'dart:convert';
import 'dart:io';

import 'package:aeronautics/aeronautics.dart' show aeronauticsChannels;
import 'package:create/src/core/payload.dart';
import 'package:create/src/protocol/codec_compiler.dart';
import 'package:create/src/protocol/payload_hub.dart';
import 'package:offroad/offroad.dart' show offroadChannels;
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart';
import 'package:sable/sable.dart' show sableChannels;
import 'package:simulated/simulated.dart' show simChannels;
import 'package:test/test.dart';

final class _Player {
  const _Player();
}

/// The Create payloads the plugin declares (`registerPayloadChannels`, which
/// `ProtocolModule.register` calls), in declaration form.
List<DeclaredPayload> _createPayloads() {
  final payloads = PayloadRegistry<_Player>();
  final hub = PayloadHub<_Player>(
    schemas: PayloadSchemas.manifest,
    sink: (level, message) {},
    describePlayer: (p) => 'player',
  );
  registerPayloadChannels<_Player>(payloads, hub);
  return payloads.declared;
}

/// The addons' channels: one table per package, each owned by the package that
/// registers the channels.
List<DeclaredPayload> _addonPayloads() => [
  ...sableChannels,
  ...simChannels,
  ...aeronauticsChannels,
  ...offroadChannels,
];

/// The client's channels, read from the committed manifest instead of from the
/// tables the declarations use.
List<QueryComponent> _manifestQuery() {
  final decoded = jsonDecode(File('../../docs/aero-port-manifest.json').readAsStringSync()) as Map<String, Object?>;
  return [
    for (final entry in (decoded['channels']! as List<Object?>).cast<Map<String, Object?>>())
      _query(
        entry['id']! as String,
        entry['version']! as String,
        switch (entry['flow']) {
          'clientbound' => PacketFlow.clientbound,
          'serverbound' => PacketFlow.serverbound,
          _ => null,
        },
        entry['optional']! as bool,
      ),
  ];
}

QueryComponent _query(String id, String version, PacketFlow? flow, bool optional) =>
    QueryComponent(id: id, version: version, flow: flow, optional: optional);

QueryComponent _declared(DeclaredPayload payload) => _query(
  payload.id,
  payload.version,
  payload.serverbound ? PacketFlow.serverbound : PacketFlow.clientbound,
  payload.optional,
);

/// The mod name the negotiation shows for a namespace (the mismatch screen).
String? _modName(String namespace) => switch (namespace) {
  'create' => 'Create',
  'sable' => 'Sable',
  'simulated' => 'Simulated',
  'aeronautics' => 'Aeronautics',
  'offroad' => 'Offroad',
  _ => null,
};

/// What the server declares: NeoForge's own registrations, Create's channels and
/// every addon's, merged like `Aggregate::build` does.
Map<NetworkPhase, List<QueryComponent>> _serverChannels({bool withAddons = true}) => {
  for (final phase in [NetworkPhase.configuration, NetworkPhase.play])
    phase: [
      ...?neoForgeOwnRegistrations[phase],
      if (phase == NetworkPhase.play) ...[
        for (final payload in _createPayloads()) _declared(payload),
        if (withAddons) for (final payload in _addonPayloads()) _declared(payload),
      ],
    ],
};

void main() {
  final serverChannels = _serverChannels();

  // What a client that has Create 6.0.11 and the four mods answers.
  final clientQuery = ModdedNetworkQuery({
    NetworkPhase.configuration: [...?neoForgeOwnRegistrations[NetworkPhase.configuration]],
    NetworkPhase.play: [
      ...?neoForgeOwnRegistrations[NetworkPhase.play],
      for (final payload in _createPayloads()) _declared(payload),
      ..._manifestQuery(),
    ],
  });

  group('Create alone declares only Create', () {
    test('every channel is in Create, Catnip or Ponder', () {
      for (final payload in _createPayloads()) {
        final namespace = payload.id.split(':').first;
        expect(
          namespace,
          anyOf('create', 'catnip', 'ponder'),
          reason: '${payload.id} is not Create content',
        );
      }
    });

    test('a server without the addons refuses the family client', () {
      final result = negotiateAll(_serverChannels(withAddons: false), clientQuery, modName: _modName);
      expect(result.setup, isNull);
      // The addons' channels are the only thing missing.
      expect(result.failures.keys.toSet(), {for (final payload in _addonPayloads()) payload.id});
    });
  });

  group('the merged declaration negotiates with the real client set', () {
    final result = negotiateAll(serverChannels, clientQuery, modName: _modName);

    test('no channel fails', () {
      expect(result.failures, isEmpty);
      expect(result.setup, isNotNull);
    });

    test('every addon channel is in the negotiated play set', () {
      final play = result.setup!.channels[NetworkPhase.play]!;
      for (final payload in _addonPayloads()) {
        expect(play[payload.id], payload.version, reason: payload.id);
      }
      expect(play, hasLength(_addonPayloads().length + _createPayloads().length + 9));
    });

    test('the negotiated play set is what the server declared', () {
      final play = result.setup!.channels[NetworkPhase.play]!;
      final declared = {
        for (final c in serverChannels[NetworkPhase.play]!) c.id: c.version,
      };
      expect(play, declared);
    });
  });

  group('the addon tables are the client channel set', () {
    test('the four tables are the 56 channels of docs/aero-port-manifest.json', () {
      final addons = _addonPayloads();
      expect(addons, hasLength(56));
      expect(addons.map((c) => c.id).toSet(), hasLength(56));

      final manifestChannels =
          ((jsonDecode(File('../../docs/aero-port-manifest.json').readAsStringSync())
                      as Map<String, Object?>)['channels']!
                  as List<Object?>)
              .cast<Map<String, Object?>>();
      final manifest = {for (final entry in manifestChannels) entry['id']! as String: entry};
      expect(addons.map((c) => c.id).toSet(), manifest.keys.toSet());
      for (final payload in addons) {
        final entry = manifest[payload.id]!;
        expect(payload.version, entry['version'], reason: payload.id);
        expect(payload.serverbound, entry['flow'] == 'serverbound', reason: payload.id);
        expect(payload.optional, entry['optional'], reason: payload.id);
        expect(entry['phase'], 'play', reason: payload.id);
      }
    });

    test('each mod carries its own registrar version', () {
      for (final payload in _addonPayloads()) {
        final expected = payload.id.startsWith('sable:') ? '1' : '0.1';
        expect(payload.version, expected, reason: payload.id);
      }
    });
  });

  group('the negotiation still refuses a client that differs', () {
    test('a missing addon channel fails with its id', () {
      final client = ModdedNetworkQuery({
        for (final phase in [NetworkPhase.configuration, NetworkPhase.play])
          phase: [
            for (final c in serverChannels[phase]!)
              if (c.id != 'sable:change_bounds_sublevel') c,
          ],
      });
      final failed = negotiateAll(serverChannels, client, modName: _modName);
      expect(failed.setup, isNull);
      expect(failed.failures.keys, ['sable:change_bounds_sublevel']);
    });

    test('another version fails with the version reason', () {
      final client = ModdedNetworkQuery({
        for (final phase in [NetworkPhase.configuration, NetworkPhase.play])
          phase: [
            for (final c in serverChannels[phase]!)
              if (c.id == 'simulated:assemble') _query(c.id, '0.2', c.flow, c.optional) else c,
          ],
      });
      // Name only Create's namespace, so the reason is the bare version
      // mismatch with both versions as its arguments.
      final failed = negotiateAll(serverChannels, client, modName: (ns) => ns == 'create' ? 'Create' : null);
      expect(failed.setup, isNull);
      final reason = failed.failures['simulated:assemble']!;
      expect(reason.textOrKey, endsWith('version.mismatch'));
      expect(reason.args.map((arg) => arg.textOrKey), ['0.2', '0.1']);
    });
  });
}
