// The server side of NeoForge's configuration-phase exchange, driven through a
// ConfigurationConnection (a plugin's view of one client in the configuration
// phase). Binding-free: tests run it against a fake transport.
//
// What it does, in the order NeoForge does it (docs/neoforge-protocol.md):
//
//   [full] pre-brand hold  (right after login, BEFORE the server's brand)
//     S->C minecraft:unregister, minecraft:register, neoforge:register (empty
//          query), ping
//     C->S minecraft:register, neoforge:register (what the client registered),
//          pong. A client that never answers the query is not NeoForge (policy).
//     negotiate the channels; host: set-connection-flavour(neoforge)
//     S->C neoforge:network, minecraft:register
//     release: the host sends the brand
//   start hold  (after the server's brand, before registries and tags)
//     [adhoc] S->C minecraft:register
//             C->S minecraft:register           -> is this a NeoForge client?
//     S->C neoforge:frozen_registry_sync_start, neoforge:frozen_registry*,
//          neoforge:frozen_registry_sync_completed
//     C->S neoforge:frozen_registry_sync_completed   (the proof)
//   finish hold (after registries and tags, right before finish-configuration)
//     S->C c:version / C->S c:version, S->C c:register / C->S c:register
//     S->C neoforge:config_file*, known data maps, enums, feature flags
//          (each with its reply)
import 'dart:async';
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:pumpkin_api/src/configuration_core.dart';
// ignore: implementation_imports
import 'package:pumpkin_api/src/packet_buffer.dart' show PacketException;

import 'client_info.dart';
import 'negotiation.dart';
import 'options.dart';
import 'payloads.dart';
import 'protocol.dart';
import 'spec.dart';

/// Where the handshake writes its log lines.
typedef HandshakeLog = void Function(String message);

/// A step failed in a way that ends the connection.
final class _Reject implements Exception {
  /// What the player sees.
  final String playerMessage;

  /// What the result and the log say.
  final String reason;

  const _Reject(this.playerMessage, this.reason);

  @override
  String toString() => reason;
}

/// Runs the NeoForge handshake for the connections of one registration.
///
/// [preBrand] is the handler of the pre-brand hold (only used by
/// [NeoForgeNegotiation.full]), [start] the handler of the start hold, [finish]
/// the handler of the finish hold; `NeoForgeServer.install` wires them to
/// `Context.onConfiguration`.
final class NeoForgeHandshake {
  final NeoForgeServerSpec spec;
  final NeoForgeServerOptions options;
  final HandshakeLog? log;

  /// Called once per client when its result is final.
  final void Function(NeoForgeClient client)? onResult;

  final Map<int, NeoForgeClient> _active = {};
  final Set<int> _reported = {};

  NeoForgeHandshake(
    this.spec, {
    this.options = const NeoForgeServerOptions(),
    this.log,
    this.onResult,
  });

  /// The clients whose connection is still in the configuration phase.
  Iterable<NeoForgeClient> get active => _active.values;

  /// The result of connection [id] while it is active.
  NeoForgeClient? operator [](int id) => _active[id];

  String _mods() => spec.mods.isEmpty
      ? 'none'
      : spec.mods.map((m) => '${m.displayName} ${m.version}').join(', ');

  String _text(String template, [String detail = '']) =>
      template.replaceAll('{mods}', _mods()).replaceAll('{detail}', detail);

  void _note(NeoForgeClient client, String message) {
    client.note(message);
    log?.call('${client.username}: $message');
  }

  void _report(NeoForgeClient client) {
    if (client.outcome == NeoForgeOutcome.pending) return;
    if (!_reported.add(client.connectionId)) return;
    try {
      onResult?.call(client);
    } catch (e, s) {
      log?.call('onResult callback failed: $e\n$s');
    }
  }

  // -------------------------------------------------------------------------
  // Start hold
  // -------------------------------------------------------------------------

  /// The client of connection [c]: created on first use, and forgotten when
  /// the connection ends.
  NeoForgeClient _track(ConfigurationConnection c) {
    final known = _active[c.id];
    if (known != null) return known;
    final client = NeoForgeClient(
      connectionId: c.id,
      uuid: c.uuid,
      username: c.username,
    );
    _active[c.id] = client;
    unawaited(
      c.done.then((completed) {
        _active.remove(c.id);
        if (client.outcome == NeoForgeOutcome.pending) {
          if (completed && client.isNeoForge) {
            // The client finished the configuration although the finish hold
            // never ran (the host does not fire it): the start hold was only
            // released after the acknowledgement, so the proof is there.
            _note(client, 'configuration finished without a finish hold');
            client.finish(NeoForgeOutcome.accepted);
          } else {
            client.finish(
              NeoForgeOutcome.disconnected,
              'the connection ended during the handshake',
            );
          }
          _report(client);
        }
        _reported.remove(c.id);
      }),
    );
    return client;
  }

  // -------------------------------------------------------------------------
  // Pre-brand hold (full)
  // -------------------------------------------------------------------------

  /// The handler of the pre-brand hold, which runs before the server's brand.
  /// For [NeoForgeNegotiation.full] it does the whole negotiation (query,
  /// channel negotiation, `neoforge:network`, the connection flavour) and
  /// releases; the start hold continues with the registry sync. With
  /// [NeoForgeNegotiation.adhoc] there is nothing to do before the brand and
  /// it releases at once.
  Future<void> preBrand(ConfigurationConnection c) async {
    if (options.negotiation != NeoForgeNegotiation.full) {
      c.release();
      return;
    }
    final client = _track(c);
    try {
      await _preBrand(c, client);
    } on _Reject catch (reject) {
      _rejectClient(c, client, reject);
    }
  }

  Future<void> _preBrand(ConfigurationConnection c, NeoForgeClient client) async {
    final messages = options.messages;

    // 1. What a NeoForge server opens with (neoforge-protocol.md section A,
    // rows 1-4): reset the registrations, announce what the server receives,
    // ask what the client registered (an empty query), and ping.
    c.send(
      NeoForgeChannels.minecraftUnregister,
      encodeRegisterChannels([
        NeoForgeChannels.minecraftRegister,
        NeoForgeChannels.minecraftUnregister,
      ]),
    );
    c.send(
      NeoForgeChannels.minecraftRegister,
      encodeRegisterChannels([
        ...NeoForgeChannels.serverConfigurationListening,
        ...spec.configurationChannelsToServer,
      ]),
    );
    c.send(
      NeoForgeChannels.moddedNetworkQuery,
      ModdedNetworkQuery.empty.encode(),
    );
    c.sendPacket(configurationPingPacketId, configurationPingBody);

    // 2. Does the client answer the query? A vanilla client ignores the
    // payloads (it still answers the ping), so it never does. The client
    // handles packets in order: when its pong is here the answer is, too.
    final pong = await c.nextPacket(
      configurationPongPacketId,
      timeout: options.announceTimeout,
    );
    final answer = await c.next(
      NeoForgeChannels.moddedNetworkQuery,
      timeout: pong != null ? options.preBrandGrace : Duration.zero,
    );
    client.brand = c.brand;
    if (answer == null) {
      _note(
        client,
        'no ${NeoForgeChannels.moddedNetworkQuery} answer '
        '(${pong == null ? 'no pong either, ' : ''}brand ${c.brand})',
      );
      return _notNeoForge(c, client);
    }
    final query = _decode(
      ModdedNetworkQuery.decode,
      answer,
      'neoforge:register',
    );
    client.query = query;
    _note(
      client,
      'client registered '
      '${query.components.values.fold<int>(0, (n, l) => n + l.length)} '
      'payload(s)',
    );

    // The client's own minecraft:register (the channels it can receive) comes
    // with the answer, in answer to the server's.
    final announcement = await c.next(
      NeoForgeChannels.minecraftRegister,
      timeout: options.queryTimeout,
    );
    if (announcement == null) {
      _note(client, 'the client sent no minecraft:register');
    } else {
      try {
        client.announcedChannels = decodeRegisterChannels(announcement);
      } on PacketException catch (e) {
        throw _Reject(
          _text(messages.badReply, 'minecraft:register: ${e.message}'),
          'malformed minecraft:register: ${e.message}',
        );
      }
      _note(
        client,
        'announced ${client.announcedChannels.length} channel(s), brand ${c.brand}',
      );
    }
    _requireRegistrySync(client);

    // 3. Negotiate the channels (rows 6 and 8).
    final setup = _negotiate(c, client, query);

    // 4. The client is a NeoForge connection from now on: the host writes the
    // NeoForge encodings in its play phase.
    try {
      c.setFlavour(ConnectionFlavour.neoforge);
    } on ConfigurationException catch (e) {
      throw _Reject(
        _text(messages.badReply, 'connection flavour: ${e.message}'),
        'the host refused to mark the connection as NeoForge: ${e.message}',
      );
    }
    client.flavour = ConnectionFlavour.neoforge;
    c.send(NeoForgeChannels.moddedNetwork, setup.encode());
    c.send(
      NeoForgeChannels.minecraftRegister,
      encodeRegisterChannels([
        ...NeoForgeChannels.builtin,
        ...?setup.channels[NetworkPhase.configuration]?.keys,
      ]),
    );

    // 5. The host sends the brand; the start hold continues.
    _note(client, 'pre-brand hold released');
    c.release();
  }

  /// Fails unless the client announced what the registry sync needs.
  void _requireRegistrySync(NeoForgeClient client) {
    if (spec.registries.isEmpty) return;
    final missing = NeoForgeChannels.registrySyncRequired
        .where((ch) => !client.announcedChannels.contains(ch))
        .toList();
    if (missing.isNotEmpty) {
      throw _Reject(
        _text(
          options.messages.noRegistrySync,
          'missing ${missing.join(', ')}',
        ),
        'the client does not announce ${missing.join(', ')}',
      );
    }
  }

  // -------------------------------------------------------------------------
  // Start hold
  // -------------------------------------------------------------------------

  /// The handler of the start hold. Always ends with the connection released
  /// or disconnected, except when it throws (the caller then fails closed).
  Future<void> start(ConfigurationConnection c) async {
    final known = _active[c.id];
    if (known != null && options.negotiation == NeoForgeNegotiation.full) {
      // The pre-brand hold did the negotiation; the brand is out.
      try {
        await _startAfterPreBrand(c, known);
      } on _Reject catch (reject) {
        _rejectClient(c, known, reject);
      }
      return;
    }
    final client = _track(c);
    if (options.negotiation == NeoForgeNegotiation.full) {
      // Nothing ran before the brand (the library was not installed with the
      // pre-brand stage), so the client is already classified as non-NeoForge
      // and the query cannot be sent in time: do the ad hoc exchange.
      _note(
        client,
        'the pre-brand hold did not run; falling back to the ad hoc exchange',
      );
    }
    try {
      await _start(c, client);
    } on _Reject catch (reject) {
      _rejectClient(c, client, reject);
    }
  }

  Future<void> _startAfterPreBrand(
    ConfigurationConnection c,
    NeoForgeClient client,
  ) async {
    if (client.outcome != NeoForgeOutcome.pending) {
      // Not NeoForge and let through by the policy: nothing more to do.
      c.release();
      return;
    }
    if (spec.registries.isNotEmpty) await _syncRegistries(c, client);
    _note(client, 'start hold released');
    c.release();
  }

  void _rejectClient(
    ConfigurationConnection c,
    NeoForgeClient client,
    _Reject reject,
  ) {
    _note(client, 'rejected: ${reject.reason}');
    client.finish(NeoForgeOutcome.rejected, reject.reason);
    _report(client);
    c.disconnect(reject.playerMessage);
  }

  /// The ad hoc exchange (after the brand, no query).
  Future<void> _start(ConfigurationConnection c, NeoForgeClient client) async {
    final messages = options.messages;

    // 1. Open: tell the client what the server receives.
    c.send(
      NeoForgeChannels.minecraftRegister,
      encodeRegisterChannels([
        ...NeoForgeChannels.serverConfigurationListening,
        ...spec.configurationChannelsToServer,
      ]),
    );

    // 2. Is this a NeoForge client? It says so by announcing the builtin
    // NeoForge channels (the answer to our register, or sent after the brand).
    final announcement = await c.next(
      NeoForgeChannels.minecraftRegister,
      timeout: options.announceTimeout,
    );
    client.brand = c.brand;
    if (announcement == null) {
      _note(
        client,
        'no minecraft:register within '
        '${options.announceTimeout.inMilliseconds} ms (brand ${c.brand})',
      );
      return _notNeoForge(c, client);
    }
    try {
      client.announcedChannels = decodeRegisterChannels(announcement);
    } on PacketException catch (e) {
      throw _Reject(
        _text(messages.badReply, 'minecraft:register: ${e.message}'),
        'malformed minecraft:register: ${e.message}',
      );
    }
    _note(
      client,
      'announced ${client.announcedChannels.length} channel(s), brand ${c.brand}',
    );
    if (!client.isNeoForge) return _notNeoForge(c, client);
    _requireRegistrySync(client);

    // 3. Registry synchronisation: the server dictates the ids.
    if (spec.registries.isNotEmpty) await _syncRegistries(c, client);

    _note(client, 'start hold released');
    c.release();
  }

  /// Negotiates the channels of the client's [query]; on failure tells the
  /// client why (its mismatch screen) and rejects it.
  ModdedNetworkSetup _negotiate(
    ConfigurationConnection c,
    NeoForgeClient client,
    ModdedNetworkQuery query,
  ) {
    final result = negotiateAll(spec.allChannels, query, modName: spec.modName);
    final setup = result.setup;
    if (setup == null) {
      // Let the client show its mismatch screen, then end the connection.
      c.send(
        NeoForgeChannels.moddedNetworkSetupFailed,
        ModdedNetworkSetupFailed(result.failures).encode(),
      );
      throw _Reject(
        _text(options.messages.negotiationFailed),
        'channel negotiation failed: ${result.failures.keys.join(', ')}',
      );
    }
    client.setup = setup;
    return setup;
  }

  /// The encoded registry snapshots are the same for every client: encode
  /// them once (NeoForge caches `RegistrySnapshot.binary` for the same reason).
  late final Uint8List _syncStartPayload = FrozenRegistrySyncStart(
    spec.registryKeys,
  ).encode();
  late final List<Uint8List> _registryPayloads = [
    for (final registry in spec.registries)
      FrozenRegistry(
        registry.key,
        RegistrySnapshot.ordered(registry.entries, aliases: registry.aliases),
      ).encode(),
  ];

  Future<void> _syncRegistries(
    ConfigurationConnection c,
    NeoForgeClient client,
  ) async {
    c.send(NeoForgeChannels.frozenRegistrySyncStart, _syncStartPayload);
    for (final payload in _registryPayloads) {
      c.send(NeoForgeChannels.frozenRegistry, payload);
    }
    c.send(NeoForgeChannels.frozenRegistrySyncCompleted, emptyPayload);
    client.syncedRegistries = spec.registryKeys;
    _note(client, 'sent ${spec.registries.length} registry snapshot(s)');

    final ack = await c.next(
      NeoForgeChannels.frozenRegistrySyncCompleted,
      timeout: options.syncTimeout,
    );
    if (ack == null) {
      throw _Reject(
        _text(options.messages.registrySyncTimeout),
        'no ${NeoForgeChannels.frozenRegistrySyncCompleted} acknowledgement '
        'within ${options.syncTimeout.inSeconds}s',
      );
    }
    client.registriesAcknowledged = true;
    _note(client, 'registry sync acknowledged');
  }

  void _notNeoForge(ConfigurationConnection c, NeoForgeClient client) {
    if (options.nonNeoForge == NonNeoForgePolicy.allow) {
      _note(client, 'not a NeoForge client; letting it through');
      client.finish(NeoForgeOutcome.notNeoForge);
      _report(client);
      c.release();
      return;
    }
    throw _Reject(
      _text(options.messages.notNeoForge),
      'not a NeoForge client (brand ${client.brand ?? 'unknown'})',
    );
  }

  // -------------------------------------------------------------------------
  // Finish hold
  // -------------------------------------------------------------------------

  /// The handler of the finish hold: the modded configuration tasks that run
  /// after the registries and tags.
  Future<void> finish(ConfigurationConnection c) async {
    final client = _active[c.id];
    if (client == null || client.outcome != NeoForgeOutcome.pending) {
      // Not a NeoForge client we accepted: nothing to do.
      c.release();
      return;
    }
    try {
      await _finish(c, client);
    } on _Reject catch (reject) {
      _rejectClient(c, client, reject);
    }
  }

  Future<void> _finish(ConfigurationConnection c, NeoForgeClient client) async {
    final announced = client.announcedChannels;
    final messages = options.messages;

    if (options.commonHandshake) {
      // CommonVersionTask
      final version = await _request(
        c,
        'c:version',
        NeoForgeChannels.commonVersion,
        CommonVersion.supported.encode(),
        NeoForgeChannels.commonVersion,
      );
      final versions = _decode(CommonVersion.decode, version, 'c:version');
      client.commonVersions = versions.versions;
      if (!versions.isAcceptable) {
        throw _Reject(
          messages.unsupportedCommonVersion,
          'the client supports common network versions '
          '${versions.versions}, not $commonNetworkVersion',
        );
      }
      // CommonRegisterTask: the play channels the server receives (none of
      // the plugin's payloads use the `c:` mechanism).
      final register = await _request(
        c,
        'c:register',
        NeoForgeChannels.commonRegister,
        CommonRegister(
          phase: NetworkPhase.play,
          channels: const <String>[],
        ).encode(),
        NeoForgeChannels.commonRegister,
      );
      final theirs = _decode(CommonRegister.decode, register, 'c:register');
      client.commonPlayChannels = theirs.channels;
      _note(client, 'c: handshake done (versions ${client.commonVersions})');
    }

    // SyncConfig: files, no answer. A client that was classified as NeoForge
    // before the brand (the full mode) expects the server's own config: without
    // it its synced config stays unloaded (neoforge-protocol.md, "The ordering
    // problem"). The ad hoc mode leaves the client to load the defaults.
    if (announced.contains(NeoForgeChannels.configFile)) {
      final files = {
        if (client.flavour == ConnectionFlavour.neoforge)
          for (final name in options.neoForgeConfigFiles) name: Uint8List(0),
        ...spec.configFiles,
      };
      for (final entry in files.entries) {
        c.send(
          NeoForgeChannels.configFile,
          ConfigFile(entry.key, entry.value).encode(),
        );
      }
    }

    // RegistryDataMapNegotiation
    if ((spec.dataMaps.isNotEmpty || options.alwaysNegotiateDataMaps) &&
        announced.contains(NeoForgeChannels.knownRegistryDataMaps)) {
      final known = <String, List<KnownDataMap>>{};
      for (final map in spec.dataMaps) {
        (known[map.registry] ??= []).add(
          KnownDataMap(map.id, mandatory: map.mandatory),
        );
      }
      final reply = await _request(
        c,
        'data map negotiation',
        NeoForgeChannels.knownRegistryDataMaps,
        KnownRegistryDataMaps(known).encode(),
        NeoForgeChannels.knownRegistryDataMapsReply,
      );
      client.clientDataMaps = _decode(
        KnownRegistryDataMapsReply.decode,
        reply,
        'known data maps reply',
      ).dataMaps;
      _note(client, 'data maps negotiated');
    }

    // CheckExtensibleEnums
    if ((spec.extensibleEnums.isNotEmpty || options.alwaysCheckEnums) &&
        announced.contains(NeoForgeChannels.extensibleEnumData)) {
      await _request(
        c,
        'extensible enum check',
        NeoForgeChannels.extensibleEnumData,
        ExtensibleEnumData(spec.extensibleEnums).encode(),
        NeoForgeChannels.extensibleEnumAck,
      );
      _note(client, 'extensible enums match');
    }

    // CheckFeatureFlags
    if ((spec.featureFlags.isNotEmpty || options.alwaysCheckFeatureFlags) &&
        announced.contains(NeoForgeChannels.featureFlags)) {
      await _request(
        c,
        'feature flag check',
        NeoForgeChannels.featureFlags,
        FeatureFlagData(spec.featureFlags).encode(),
        NeoForgeChannels.featureFlagsAck,
      );
      _note(client, 'feature flags match');
    }

    client.finish(NeoForgeOutcome.accepted);
    _report(client);
    _note(client, 'finish hold released');
    c.release();
  }

  /// Sends [payload] on [channel] and waits for the reply on [replyChannel].
  Future<Uint8List> _request(
    ConfigurationConnection c,
    String task,
    String channel,
    Uint8List payload,
    String replyChannel,
  ) async {
    c.send(channel, payload);
    final reply = await c.next(replyChannel, timeout: options.taskTimeout);
    if (reply == null) {
      throw _Reject(
        _text(options.messages.taskTimeout, task),
        'no answer to $task on $replyChannel within '
        '${options.taskTimeout.inSeconds}s',
      );
    }
    return reply;
  }

  T _decode<T>(T Function(List<int>) decode, Uint8List data, String what) {
    try {
      return decode(data);
    } on PacketException catch (e) {
      throw _Reject(
        _text(options.messages.badReply, '$what: ${e.message}'),
        'malformed $what: ${e.message}',
      );
    } on FormatException catch (e) {
      throw _Reject(
        _text(options.messages.badReply, '$what: ${e.message}'),
        'malformed $what: ${e.message}',
      );
    }
  }
}
