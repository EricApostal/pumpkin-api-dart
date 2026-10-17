// The NeoForge handshake of this plugin: `pumpkin_neoforge`'s
// `NeoForgeHandshake` wired to `Context.onConfiguration` exactly like
// `NeoForgeServer.install` does it, with one extra step in the finish hold: the
// `registry_data` packets of CC's datapack registries.
//
// Why a copy of `NeoForgeServer` instead of using it: its `onFinish` handler is
// the handshake's own, and a second `onConfiguration` registration with an
// `onFinish` would race it for the one finish hold (the host has a single hold
// per connection and any `release()` ends it; the NeoForge tasks take a round
// trip each, so whoever releases first would send "finish configuration" before
// they are done). Doing the send inside the same handler, before the
// handshake's own tasks, keeps one hold and a fixed order:
//
//     start hold    neoforge:frozen_registry*          (ids of blocks, items, ...)
//     (host)        registry_data for the vanilla datapack registries, update_tags
//     finish hold   registry_data computercraft:turtle_upgrade, ...:pocket_upgrade
//                   c:version, c:register, neoforge:config_file
//     (host)        finish_configuration
//
// Where in the configuration the datapack registries go does not matter to the
// client: `ClientConfigurationPacketListenerImpl.handleRegistryData` only
// collects the entries (`RegistryDataCollector.appendContents`), and they are
// decoded together when the configuration finishes
// (`collectGameRegistries`, after the `neoforge:frozen_registry` ids are
// applied). They have to arrive before `finish_configuration`; the finish hold is
// the latest place that guarantees it.
import 'dart:collection';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge.dart';

import '../protocol/datapack_registries.dart';

/// Called once per client in the finish hold, with the connection.
typedef FinishExtra = void Function(ConfigurationConnection connection);

/// A NeoForge server for the plugin: the library's handshake plus the
/// datapack registries.
final class CcNeoForgeServer {
  static const int _maxRetainedClients = 512;

  final NeoForgeServerSpec spec;
  final NeoForgeServerOptions options;
  final CcDatapackRegistries datapackRegistries;

  final Logger _log = Logger('neoforge');
  final LinkedHashMap<String, NeoForgeClient> _byUuid = LinkedHashMap();
  final List<void Function(NeoForgeClient client)> _listeners = [];
  late final NeoForgeHandshake _handshake;

  CcNeoForgeServer(this.spec, this.datapackRegistries, {this.options = const NeoForgeServerOptions()}) {
    _handshake = NeoForgeHandshake(
      spec,
      options: options,
      log: (message) => _log.info(message),
      onResult: _onResult,
    );
  }

  /// Registers the handshake on [context] (`Context.onConfiguration` with the
  /// pre-brand, start and finish holds of the library's full negotiation).
  Subscription install(Context context) {
    final full = options.negotiation == NeoForgeNegotiation.full;
    return context.onConfiguration(
      _handshake.start,
      onPreBrand: full ? _handshake.preBrand : null,
      preBrandHoldTimeout: options.preBrandHoldTimeout,
      capturePackets: full,
      holdTimeout: options.holdTimeout,
      onFinish: _finish,
      finishHoldTimeout: options.finishHoldTimeout,
      failureMessage: 'Failed to complete the NeoForge handshake.',
    );
  }

  /// `NeoForgeServer.installPlay`: the play-phase extras of a NeoForge
  /// connection (the elytra attribute, `neoforge:recipe_content`).
  Subscription installPlay(
    Context context, {
    bool recipeContent = true,
    GlidingFlightOptions? glidingFlight = const GlidingFlightOptions(),
  }) => NeoForgePlay(spec, clientOf, recipeContent: recipeContent, gliding: glidingFlight).install(context);

  /// The finish hold: the datapack registries first, then the library's tasks.
  Future<void> _finish(ConfigurationConnection c) async {
    final client = _handshake[c.id];
    if (client != null && client.outcome == NeoForgeOutcome.pending && client.isNeoForge) {
      _sendDatapackRegistries(c, client);
    }
    await _handshake.finish(c);
  }

  void _sendDatapackRegistries(ConfigurationConnection c, NeoForgeClient client) {
    try {
      for (final registry in datapackRegistries.all) {
        c.sendPacket(configRegistryDataPacketId, registry.toPacket());
      }
      final note =
          'sent registry_data: ${datapackRegistries.turtleUpgrades.entries.length} turtle upgrades, '
          '${datapackRegistries.pocketUpgrades.entries.length} pocket upgrades';
      client.note(note);
      _log.info('${client.username}: $note');
    } on ConfigurationException catch (e) {
      // Includes a client that left (`ConnectionClosedException`): the
      // handshake notices that on its own.
      _log.warn('${client.username}: could not send the datapack registries: ${e.message}');
    } catch (e, s) {
      // The creative tab variants are not worth a disconnect: log and go on.
      _log.error('${client.username}: building the datapack registries failed: $e\n$s');
    }
  }

  void _onResult(NeoForgeClient client) {
    _byUuid.remove(client.uuid);
    _byUuid[client.uuid] = client;
    while (_byUuid.length > _maxRetainedClients) {
      _byUuid.remove(_byUuid.keys.first);
    }
    switch (client.outcome) {
      case NeoForgeOutcome.accepted:
        _log.info('${client.username} joined with NeoForge (${client.syncedRegistries.length} registries synced)');
      case NeoForgeOutcome.rejected:
        _log.warn('${client.username} was refused: ${client.failureReason}');
      case NeoForgeOutcome.notNeoForge:
        _log.info('${client.username} is not a NeoForge client (brand ${client.brand})');
      case NeoForgeOutcome.disconnected || NeoForgeOutcome.pending:
        break;
    }
    for (final listener in List.of(_listeners)) {
      try {
        listener(client);
      } catch (e, s) {
        _log.error('NeoForge listener failed: $e\n$s');
      }
    }
  }

  /// Calls [listener] whenever the handshake with a client is decided.
  void Function() onClient(void Function(NeoForgeClient client) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// The result for the player with [uuid] (canonical form), if any.
  NeoForgeClient? clientOf(String uuid) => _byUuid[uuid];
}
