// The server side handshake against a scripted client and a fake transport.
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:pumpkin_api/src/configuration_core.dart'
    show ConfigurationException, ConnectionFlavour;
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart';
import 'package:test/test.dart';

import 'support/rig.dart';

const _fast = NeoForgeServerOptions(
  announceTimeout: Duration(milliseconds: 120),
  queryTimeout: Duration(milliseconds: 120),
  syncTimeout: Duration(milliseconds: 150),
  taskTimeout: Duration(milliseconds: 150),
);

NeoForgeServerSpec _spec({
  List<PayloadChannelSpec> channels = const [],
  List<DataMapSpec> dataMaps = const [],
  List<EnumEntry> enums = const [],
  List<String> flags = const [],
}) => NeoForgeServerSpec.vanillaPlus(
  mods: const [
    NeoForgeModInfo(id: 'testmod', version: '1.2.3', displayName: 'Test Mod'),
  ],
  additions: {
    'minecraft:item': ['testmod:gem', 'testmod:gem_block', 'testmod:rod'],
    'minecraft:block': ['testmod:gem_block'],
  },
  channels: channels,
  dataMaps: dataMaps,
  extensibleEnums: enums,
  featureFlags: flags,
);

Rig _rig({NeoForgeServerOptions options = _fast, NeoForgeServerSpec? spec}) =>
    Rig(spec ?? _spec(), options: options)..begin();

void main() {
  group('adhoc handshake (default)', () {
    test('happy path: the exact messages, in order', () async {
      final rig = _rig();
      ScriptedClient(rig);

      await rig.runStart();

      // Server -> client, in the order of docs/neoforge-protocol.md.
      expect(rig.transport.channels, [
        'minecraft:register',
        'neoforge:frozen_registry_sync_start',
        'neoforge:frozen_registry',
        'neoforge:frozen_registry',
        'neoforge:frozen_registry_sync_completed',
      ]);
      expect(rig.transport.releases, 1);
      expect(rig.transport.disconnectReason, isNull);

      // The channels the server announces: the builtin ones plus what it
      // receives.
      expect(
        decodeRegisterChannels(rig.transport.all('minecraft:register').single),
        containsAll([
          'neoforge:register',
          'neoforge:network',
          'c:version',
          'c:register',
          'neoforge:frozen_registry_sync_completed',
          'neoforge:known_registry_data_maps_reply',
          'neoforge:extensible_enum_ack',
          'neoforge:feature_flags_ack',
        ]),
      );

      final start = FrozenRegistrySyncStart.decode(
        rig.transport.all('neoforge:frozen_registry_sync_start').single,
      );
      expect(start.registries, ['minecraft:item', 'minecraft:block']);

      final registries = [
        for (final data in rig.transport.all('neoforge:frozen_registry'))
          FrozenRegistry.decode(data),
      ];
      final item = registries[0];
      expect(item.registry, 'minecraft:item');
      // vanilla ids unchanged, modded entries appended
      expect(item.snapshot.ids[0], 'minecraft:air');
      expect(item.snapshot.isContiguous, isTrue);
      final vanillaItems = VanillaRegistries.require('minecraft:item');
      expect(item.snapshot.ids.length, vanillaItems.length + 3);
      expect(item.snapshot.ids[vanillaItems.length], 'testmod:gem');
      expect(item.snapshot.ids[vanillaItems.length + 2], 'testmod:rod');
      expect(registries[1].registry, 'minecraft:block');
      expect(registries[1].snapshot.orderedEntries.last, 'testmod:gem_block');

      expect(
        rig.transport.all('neoforge:frozen_registry_sync_completed').single,
        isEmpty,
      );
      expect(
        rig.results,
        isEmpty,
        reason: 'not decided before the finish hold',
      );
    });

    test('finish hold: c: handshake, then accepted', () async {
      final rig = _rig();
      final client = ScriptedClient(rig);
      await rig.runStart();
      rig.transport.sent.clear();

      await rig.runFinish();

      expect(rig.transport.channels, ['c:version', 'c:register']);
      expect(CommonVersion.decode(rig.transport.last('c:version')).versions, [
        1,
      ]);
      final register = CommonRegister.decode(rig.transport.last('c:register'));
      expect(register.phase, NetworkPhase.play);
      expect(register.version, 1);
      expect(register.channels, isEmpty);

      expect(rig.transport.releases, 2);
      expect(rig.results, hasLength(1));
      final result = rig.results.single;
      expect(result.outcome, NeoForgeOutcome.accepted);
      expect(result.isNeoForge, isTrue);
      expect(result.brand, 'neoforge');
      expect(result.registriesAcknowledged, isTrue);
      expect(result.syncedRegistries, ['minecraft:item', 'minecraft:block']);
      expect(result.commonVersions, [1]);
      expect(result.commonPlayChannels, ['neoforge:recipe_content']);
      expect(result.announcedChannels, client.announce);
      expect(result.events, isNotEmpty);
    });

    test('a reply that arrives before the server asks is not lost', () async {
      final rig = _rig();
      final client = ScriptedClient(rig)..ackSync = false;
      // The client announces and acknowledges in advance.
      client.announceNow();
      rig.clientSends(NeoForgeChannels.frozenRegistrySyncCompleted, const []);
      await rig.runStart();
      expect(rig.transport.releases, 1);
      expect(rig.transport.disconnectReason, isNull);
    });

    test(
      'vanilla client: no announcement -> refused with the mod list',
      () async {
        final rig = _rig();
        ScriptedClient(rig).announce = null;

        await rig.runStart();

        expect(rig.transport.disconnectReason, contains('requires NeoForge'));
        expect(rig.transport.disconnectReason, contains('Test Mod 1.2.3'));
        expect(rig.transport.channels, ['minecraft:register']);
        expect(rig.results.single.outcome, NeoForgeOutcome.rejected);
        expect(
          rig.results.single.failureReason,
          contains('not a NeoForge client'),
        );
      },
    );

    test('a client of another loader is refused too', () async {
      final rig = _rig();
      ScriptedClient(rig)
        ..announce = ['fabric:custom', 'c:version']
        ..brand = 'fabric';
      await rig.runStart();
      expect(rig.transport.disconnectReason, contains('NeoForge'));
      expect(rig.results.single.brand, 'fabric');
    });

    test('policy allow lets non-NeoForge clients through', () async {
      final rig = _rig(
        options: const NeoForgeServerOptions(
          announceTimeout: Duration(milliseconds: 80),
          nonNeoForge: NonNeoForgePolicy.allow,
        ),
      );
      ScriptedClient(rig).announce = null;
      await rig.runStart();
      expect(rig.transport.disconnectReason, isNull);
      expect(rig.transport.releases, 1);
      expect(rig.transport.channels, ['minecraft:register']);
      expect(rig.results.single.outcome, NeoForgeOutcome.notNeoForge);

      // and the finish hold does nothing for it
      await rig.runFinish();
      expect(rig.transport.releases, 2);
      expect(rig.transport.channels, ['minecraft:register']);
    });

    test('client without the sync channels is refused', () async {
      final rig = _rig();
      ScriptedClient(rig).announce = NeoForgeChannels.builtin;
      await rig.runStart();
      expect(rig.transport.disconnectReason, contains('cannot synchronise'));
      expect(
        rig.results.single.failureReason,
        contains('neoforge:frozen_registry'),
      );
      expect(rig.transport.channels, ['minecraft:register']);
    });

    test('no acknowledgement of the sync: refused, never released', () async {
      final rig = _rig();
      ScriptedClient(rig).ackSync = false;
      await rig.runStart();
      expect(rig.transport.disconnectReason, contains('did not accept'));
      expect(rig.transport.releases, 0);
      expect(rig.results.single.registriesAcknowledged, isFalse);
      expect(rig.results.single.outcome, NeoForgeOutcome.rejected);
    });

    test('client that leaves during the sync', () async {
      final rig = _rig();
      ScriptedClient(rig).ackSync = false;
      final run = rig.runStart();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      rig.clientLeaves();
      await run;
      await Future<void>.delayed(Duration.zero);
      expect(rig.transport.disconnectReason, isNull);
      expect(rig.results.single.outcome, NeoForgeOutcome.disconnected);
    });

    test('malformed minecraft:register is refused, not a crash', () async {
      final rig = _rig();
      ScriptedClient(rig).announce = null;
      rig.clientSends('minecraft:register', [0x41, 0x42, 0x00]); // "AB"
      await rig.runStart();
      // invalid names are ignored like NeoForge does -> not NeoForge
      expect(rig.transport.disconnectReason, contains('requires NeoForge'));
    });

    test('a client that finishes without a finish hold is accepted', () async {
      final rig = _rig();
      ScriptedClient(rig);
      await rig.runStart();
      rig.sessions.end(id: 1, completed: true);
      await Future<void>.delayed(Duration.zero);
      expect(rig.results.single.outcome, NeoForgeOutcome.accepted);
      expect(rig.results.single.registriesAcknowledged, isTrue);
    });

    test('each client is reported once', () async {
      final rig = _rig();
      ScriptedClient(rig);
      await rig.runStart();
      await rig.runFinish();
      rig.sessions.end(id: 1, completed: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(rig.results, hasLength(1));
    });
  });

  group('finish hold tasks', () {
    test('a bad c:version reply is refused', () async {
      final rig = _rig();
      final client = ScriptedClient(rig)..commonVersions = [7];
      await rig.runStart();
      await rig.runFinish();
      expect(
        rig.transport.disconnectReason,
        contains('Unsupported common network version'),
      );
      expect(client.rig.results.single.outcome, NeoForgeOutcome.rejected);
    });

    test('a malformed c:version reply is refused', () async {
      final rig = _rig();
      ScriptedClient(rig).answerCommon = false;
      await rig.runStart();
      rig.clientSends('c:version', [0x05]); // claims 5 versions, has none
      await rig.runFinish();
      expect(rig.transport.disconnectReason, contains('failed'));
    });

    test('no c: reply -> timeout message names the step', () async {
      final rig = _rig();
      ScriptedClient(rig).answerCommon = false;
      await rig.runStart();
      await rig.runFinish();
      expect(rig.transport.disconnectReason, contains('c:version'));
    });

    test(
      'data maps, enums and feature flags are checked when configured',
      () async {
        final rig = _rig(
          spec: _spec(
            dataMaps: [
              DataMapSpec(
                registry: 'minecraft:item',
                id: 'testmod:tiers',
                mandatory: true,
              ),
            ],
            enums: const [
              EnumEntry(
                'net.minecraft.world.item.Rarity',
                EnumNetworkCheck.bidirectional,
              ),
            ],
            flags: ['testmod:experimental'],
          ),
        );
        final client = ScriptedClient(rig)
          ..dataMaps = {
            'minecraft:item': ['testmod:tiers'],
          };
        await rig.runStart();
        rig.transport.sent.clear();
        await rig.runFinish();

        expect(rig.transport.channels, [
          'c:version',
          'c:register',
          'neoforge:known_registry_data_maps',
          'neoforge:extensible_enum_data',
          'neoforge:feature_flags',
        ]);
        final known = KnownRegistryDataMaps.decode(
          rig.transport.last('neoforge:known_registry_data_maps'),
        );
        expect(known.dataMaps['minecraft:item']!.single.mandatory, isTrue);
        expect(
          FeatureFlagData.decode(rig.transport.last('neoforge:feature_flags'))
              .flags,
          ['testmod:experimental'],
        );
        expect(client.rig.results.single.clientDataMaps, {
          'minecraft:item': ['testmod:tiers'],
        });
        expect(client.rig.results.single.outcome, NeoForgeOutcome.accepted);
      },
    );

    test('an unanswered feature flag check is refused', () async {
      final rig = _rig(spec: _spec(flags: ['testmod:experimental']));
      ScriptedClient(rig).answerTasks = false;
      await rig.runStart();
      await rig.runFinish();
      expect(rig.transport.disconnectReason, contains('feature flag check'));
    });

    test(
      'config files are sent only to clients that announced the channel',
      () async {
        final spec = NeoForgeServerSpec.vanillaPlus(
          additions: {
            'minecraft:item': ['testmod:gem'],
          },
          configFiles: {
            'testmod-server.toml': Uint8List.fromList([1, 2, 3]),
          },
        );
        final rig = Rig(spec, options: _fast)..begin();
        ScriptedClient(rig);
        await rig.runStart();
        await rig.runFinish();
        final file = ConfigFile.decode(
          rig.transport.last('neoforge:config_file'),
        );
        expect(file.fileName, 'testmod-server.toml');
        expect(file.contents, [1, 2, 3]);
      },
    );

    test('commonHandshake can be switched off', () async {
      final rig = _rig(
        options: const NeoForgeServerOptions(
          announceTimeout: Duration(milliseconds: 100),
          commonHandshake: false,
        ),
      );
      ScriptedClient(rig);
      await rig.runStart();
      rig.transport.sent.clear();
      await rig.runFinish();
      expect(rig.transport.sent, isEmpty);
      expect(rig.results.single.outcome, NeoForgeOutcome.accepted);
    });
  });

  group('full handshake (pre-brand hold, then start hold)', () {
    const fullOptions = NeoForgeServerOptions(
      negotiation: NeoForgeNegotiation.full,
      announceTimeout: Duration(milliseconds: 150),
      queryTimeout: Duration(milliseconds: 150),
      preBrandGrace: Duration(milliseconds: 100),
      syncTimeout: Duration(milliseconds: 150),
    );

    Rig fullRig({NeoForgeServerSpec? spec, NeoForgeServerOptions? options}) =>
        Rig(spec ?? _spec(), options: options ?? fullOptions)
          ..begin(preBrand: true);

    /// The pre-brand hold, then the brand and the start hold.
    Future<void> runBoth(Rig rig) async {
      await rig.runPreBrand();
      if (rig.transport.disconnectReason != null) return;
      rig.toStart();
      await rig.runStart();
    }

    test('before the brand: query, negotiation, flavour, network', () async {
      final rig = fullRig();
      ScriptedClient(rig);
      await rig.runPreBrand();

      expect(rig.transport.channels, [
        'minecraft:unregister',
        'minecraft:register',
        'neoforge:register',
        'neoforge:network',
        'minecraft:register',
      ]);
      // the ping goes out right after the query: id 5, one int
      expect(rig.transport.packets.single.$1, 5);
      expect(rig.transport.packets.single.$2, [0, 0, 0, 0]);
      expect(rig.transport.events, [
        'send minecraft:unregister',
        'send minecraft:register',
        'send neoforge:register',
        'packet 5',
        'flavour neoforge',
        'send neoforge:network',
        'send minecraft:register',
        'release',
      ], reason: 'the flavour is set before the release, after the answer');
      // the server's query is empty
      expect(rig.transport.all('neoforge:register').single, [0]);
      expect(
        decodeRegisterChannels(
          rig.transport.all('minecraft:unregister').single,
        ),
        unorderedEquals(['minecraft:register', 'minecraft:unregister']),
      );
      final setup = ModdedNetworkSetup.decode(
        rig.transport.last('neoforge:network'),
      );
      expect(
        setup.channels[NetworkPhase.configuration]!.keys,
        contains('neoforge:frozen_registry'),
      );
      expect(
        setup.channels[NetworkPhase.play]!['neoforge:recipe_content'],
        '1',
      );
      // announced again with the negotiated configuration channels
      expect(
        decodeRegisterChannels(rig.transport.all('minecraft:register').last),
        containsAll([
          'neoforge:network',
          'neoforge:frozen_registry_sync_completed',
        ]),
      );
      expect(rig.transport.flavours, [ConnectionFlavour.neoforge]);
      expect(rig.transport.releases, 1);
      expect(rig.conn.flavour, ConnectionFlavour.neoforge);
      expect(rig.handshake[1]!.isFlagged, isTrue);
      expect(rig.handshake[1]!.query, isNotNull);
      expect(rig.results, isEmpty, reason: 'not decided yet');
    });

    test('the start hold then does the registry sync', () async {
      final rig = fullRig();
      ScriptedClient(rig);
      await rig.runPreBrand();
      rig.transport.sent.clear();
      rig.transport.packets.clear();
      rig.toStart();
      await rig.runStart();

      expect(rig.transport.channels, [
        'neoforge:frozen_registry_sync_start',
        'neoforge:frozen_registry',
        'neoforge:frozen_registry',
        'neoforge:frozen_registry_sync_completed',
      ]);
      expect(rig.transport.releases, 2);
      await rig.runFinish();
      final result = rig.results.single;
      expect(result.query, isNotNull);
      expect(result.setup, isNotNull);
      expect(result.isFlagged, isTrue);
      expect(result.outcome, NeoForgeOutcome.accepted);
    });

    test('the finish hold sends the empty server config', () async {
      final rig = fullRig();
      ScriptedClient(rig);
      await runBoth(rig);
      rig.transport.sent.clear();
      await rig.runFinish();
      final file = ConfigFile.decode(rig.transport.last('neoforge:config_file'));
      expect(file.fileName, 'neoforge-server.toml');
      expect(file.contents, isEmpty);
    });

    test('the server config file names can be chosen', () async {
      final rig = fullRig(
        options: const NeoForgeServerOptions(
          negotiation: NeoForgeNegotiation.full,
          preBrandGrace: Duration(milliseconds: 100),
          neoForgeConfigFiles: ['neoforge-synced.toml'],
        ),
      );
      ScriptedClient(rig);
      await runBoth(rig);
      rig.transport.sent.clear();
      await rig.runFinish();
      final names = [
        for (final d in rig.transport.all('neoforge:config_file'))
          ConfigFile.decode(d).fileName,
      ];
      expect(names, ['neoforge-synced.toml']);
    });

    test('the server config can be switched off', () async {
      final off = fullRig(
        options: const NeoForgeServerOptions(
          negotiation: NeoForgeNegotiation.full,
          preBrandGrace: Duration(milliseconds: 100),
          neoForgeConfigFiles: [],
        ),
      );
      ScriptedClient(off);
      await runBoth(off);
      off.transport.sent.clear();
      await off.runFinish();
      expect(off.transport.channels, isNot(contains('neoforge:config_file')));
    });

    test('the ad hoc mode sends no config file and keeps the flavour', () async {
      final rig = _rig();
      ScriptedClient(rig);
      await rig.runStart();
      rig.transport.sent.clear();
      await rig.runFinish();
      expect(rig.transport.channels, isNot(contains('neoforge:config_file')));
      expect(rig.transport.flavours, isEmpty);
      expect(rig.results.single.isFlagged, isFalse);
    });

    test('a mod channel both sides have is negotiated', () async {
      final spec = _spec(
        channels: [
          PayloadChannelSpec(
            id: 'testmod:hello',
            version: '2',
            phases: {NetworkPhase.play},
            flow: PacketFlow.clientbound,
          ),
        ],
      );
      final rig = fullRig(spec: spec);
      ScriptedClient(rig).registrations = {
        for (final e in neoForgeOwnRegistrations.entries)
          e.key: [
            ...e.value,
            if (e.key == NetworkPhase.play)
              QueryComponent(
                id: 'testmod:hello',
                version: '2',
                flow: PacketFlow.clientbound,
              ),
          ],
      };
      await rig.runPreBrand();
      final setup = ModdedNetworkSetup.decode(
        rig.transport.last('neoforge:network'),
      );
      expect(setup.channels[NetworkPhase.play]!['testmod:hello'], '2');
      expect(rig.results, isEmpty);
    });

    test(
      'a version mismatch sends the failure reasons, then disconnects',
      () async {
        final spec = _spec(
          channels: [PayloadChannelSpec(id: 'testmod:hello', version: '2')],
        );
        final rig = fullRig(spec: spec);
        ScriptedClient(rig).registrations = {
          NetworkPhase.play: [
            ...neoForgeOwnRegistrations[NetworkPhase.play]!,
            QueryComponent(id: 'testmod:hello', version: '1'),
          ],
          NetworkPhase.configuration:
              neoForgeOwnRegistrations[NetworkPhase.configuration]!,
        };
        await rig.runPreBrand();
        final failed = ModdedNetworkSetupFailed.decode(
          rig.transport.last('neoforge:modded_network_setup_failed'),
        );
        final reason = failed.reasons['testmod:hello']!;
        expect(reason.textOrKey, 'neoforge.network.negotiation.failure.mod');
        expect(reason.args.first.textOrKey, 'Test Mod');
        expect(
          reason.args.last.textOrKey,
          'neoforge.network.negotiation.failure.version.mismatch',
        );
        expect(rig.transport.disconnectReason, contains('Incompatible mods'));
        expect(rig.transport.channels, isNot(contains('neoforge:network')));
        expect(rig.transport.flavours, isEmpty);
        expect(rig.results.single.outcome, NeoForgeOutcome.rejected);
      },
    );

    test('a required client channel the server lacks fails', () async {
      final rig = fullRig();
      ScriptedClient(rig).registrations = {
        NetworkPhase.play: [QueryComponent(id: 'othermod:net', version: '1')],
      };
      await rig.runPreBrand();
      final failed = ModdedNetworkSetupFailed.decode(
        rig.transport.last('neoforge:modded_network_setup_failed'),
      );
      expect(failed.reasons.keys, ['othermod:net']);
      expect(
        failed.reasons['othermod:net']!.textOrKey,
        'neoforge.network.negotiation.failure.missing.client.server',
      );
      expect(rig.transport.flavours, isEmpty);
    });

    group('a client that does not answer the query (vanilla)', () {
      test('is refused by default, and stays vanilla', () async {
        final rig = fullRig();
        ScriptedClient(rig)
          ..announce = null
          ..answerQuery = false;
        await rig.runPreBrand();
        expect(rig.transport.disconnectReason, contains('requires NeoForge'));
        expect(rig.transport.flavours, isEmpty);
        expect(rig.transport.releases, 0);
        expect(rig.transport.channels, isNot(contains('neoforge:network')));
        expect(rig.results.single.outcome, NeoForgeOutcome.rejected);
      });

      test('is recognised by its pong, long before the timeout', () async {
        final rig = fullRig(
          options: const NeoForgeServerOptions(
            negotiation: NeoForgeNegotiation.full,
            nonNeoForge: NonNeoForgePolicy.allow,
            announceTimeout: Duration(seconds: 30),
            preBrandGrace: Duration(milliseconds: 50),
          ),
        );
        ScriptedClient(rig)
          ..announce = null
          ..answerQuery = false;
        final watch = Stopwatch()..start();
        await rig.runPreBrand();
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      });

      test('is let through by the allow policy: released, vanilla, no sync',
          () async {
        final rig = fullRig(
          options: const NeoForgeServerOptions(
            negotiation: NeoForgeNegotiation.full,
            nonNeoForge: NonNeoForgePolicy.allow,
            announceTimeout: Duration(milliseconds: 150),
            preBrandGrace: Duration(milliseconds: 50),
          ),
        );
        ScriptedClient(rig)
          ..announce = null
          ..answerQuery = false;
        await runBoth(rig);
        expect(rig.transport.disconnectReason, isNull);
        expect(rig.transport.flavours, isEmpty, reason: 'must stay vanilla');
        expect(rig.transport.releases, 2, reason: 'pre-brand and start');
        expect(
          rig.transport.channels,
          [
            'minecraft:unregister',
            'minecraft:register',
            'neoforge:register',
          ],
          reason: 'no registry sync for a vanilla client',
        );
        expect(rig.results.single.outcome, NeoForgeOutcome.notNeoForge);
        expect(rig.results.single.isFlagged, isFalse);
        await rig.runFinish();
        expect(rig.transport.releases, 3);
      });

      test('without a pong either it is the timeout that decides', () async {
        final rig = fullRig(
          options: const NeoForgeServerOptions(
            negotiation: NeoForgeNegotiation.full,
            nonNeoForge: NonNeoForgePolicy.allow,
            announceTimeout: Duration(milliseconds: 80),
          ),
        );
        ScriptedClient(rig)
          ..announce = null
          ..answerQuery = false
          ..answerPing = false;
        await rig.runPreBrand();
        expect(rig.transport.releases, 1);
        expect(rig.results.single.outcome, NeoForgeOutcome.notNeoForge);
      });
    });

    test('an answer that arrived before the pong is found even if the pong '
        'is missing', () async {
      final rig = fullRig();
      ScriptedClient(rig).answerPing = false;
      await rig.runPreBrand();
      expect(rig.transport.flavours, [ConnectionFlavour.neoforge]);
    });

    test('a malformed query answer is refused', () async {
      final rig = fullRig();
      final client = ScriptedClient(rig)..answerQuery = false;
      client.announceNow();
      rig.clientSends('neoforge:register', [0x09]);
      await rig.runPreBrand();
      expect(rig.transport.disconnectReason, contains('failed'));
      expect(rig.transport.flavours, isEmpty);
    });

    test('a client that does not announce the sync channels is refused',
        () async {
      final rig = fullRig();
      ScriptedClient(rig).announce = ['minecraft:register'];
      await rig.runPreBrand();
      expect(rig.transport.disconnectReason, contains('registries'));
      expect(rig.transport.flavours, isEmpty);
    });

    test('the host refusing the flavour rejects the client', () async {
      final rig = fullRig();
      ScriptedClient(rig);
      rig.transport.failFlavour = const ConfigurationException('too late');
      await rig.runPreBrand();
      expect(rig.transport.disconnectReason, isNotNull);
      expect(rig.transport.channels, isNot(contains('neoforge:network')));
      expect(rig.transport.releases, 0);
    });

    test('the registry sync is not acknowledged: refused at the start hold',
        () async {
      final rig = fullRig();
      ScriptedClient(rig).ackSync = false;
      await runBoth(rig);
      expect(rig.transport.disconnectReason, contains('registries'));
    });

    test('without the pre-brand stage it falls back to the ad hoc exchange',
        () async {
      // The start handler of a registration that has no pre-brand handler.
      final rig = Rig(_spec(), options: fullOptions)..begin();
      ScriptedClient(rig);
      await rig.runStart();
      expect(rig.transport.channels, isNot(contains('neoforge:register')));
      expect(rig.transport.flavours, isEmpty);
      expect(rig.transport.releases, 1);
      expect(rig.handshake[1]!.events.join(), contains('did not run'));
    });

    test('the adhoc mode releases a pre-brand hold at once', () async {
      final rig = Rig(_spec(), options: _fast)..begin(preBrand: true);
      await rig.runPreBrand();
      expect(rig.transport.sent, isEmpty);
      expect(rig.transport.releases, 1);
    });
  });

  group('negotiation (NetworkComponentNegotiator port)', () {
    QueryComponent c(
      String id,
      String v, {
      PacketFlow? flow,
      bool optional = false,
    }) => QueryComponent(id: id, version: v, flow: flow, optional: optional);

    test('optional channels missing on the other side are dropped', () {
      final r = negotiate([c('a:x', '1', optional: true)], []);
      expect(r.success, isTrue);
      expect(r.channels, isEmpty);
      final r2 = negotiate([], [c('a:x', '1', optional: true)]);
      expect(r2.success, isTrue);
    });

    test('required channel missing', () {
      final r = negotiate([c('a:x', '1')], []);
      expect(r.success, isFalse);
      expect(
        r.failureReasons['a:x']!.textOrKey,
        endsWith('missing.server.client'),
      );
    });

    test('flow and version mismatches', () {
      expect(
        negotiate(
          [c('a:x', '1', flow: PacketFlow.clientbound)],
          [c('a:x', '1')],
        ).failureReasons['a:x']!.textOrKey,
        endsWith('flow.client.missing'),
      );
      expect(
        negotiate(
          [c('a:x', '1', flow: PacketFlow.clientbound)],
          [c('a:x', '1', flow: PacketFlow.serverbound)],
        ).failureReasons['a:x']!.textOrKey,
        endsWith('flow.client.mismatch'),
      );
      final v = negotiate([c('a:x', '2')], [c('a:x', '1')]);
      expect(v.success, isFalse);
      expect(v.failureReasons['a:x']!.args.map((a) => a.textOrKey), ['1', '2']);
    });

    test('equal channels pass with the server version', () {
      final r = negotiate([c('a:x', '3')], [c('a:x', '3')]);
      expect(r.channels, {'a:x': '3'});
    });
  });
}
