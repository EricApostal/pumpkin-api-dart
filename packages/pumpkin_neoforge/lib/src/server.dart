// The plugin-facing glue: installs the handshake into a plugin's context and
// keeps the per-client results. The logic itself is in handshake.dart.
import 'dart:collection';

import 'package:pumpkin_api/pumpkin_api.dart';

import 'client_info.dart';
import 'handshake.dart';
import 'options.dart';
import 'play.dart';
import 'play_core.dart';
import 'spec.dart';

/// How many finished results [NeoForgeServer] keeps (the oldest are dropped).
const int maxRetainedClients = 512;

/// A NeoForge server for a plugin.
///
/// ```dart
/// final server = NeoForgeServer(spec);
///
/// @override
/// void onLoad(Context context) {
///   server.install(context);
///   server.onClient((client) {
///     logger.info('${client.username}: ${client.outcome.name}');
///   });
/// }
/// ```
///
/// [install] registers `Context.onConfiguration` with both hold points and runs
/// the exchange described in docs/neoforge-protocol.md for every client; a
/// client that fails it is disconnected with a clear reason.
final class NeoForgeServer {
  final NeoForgeServerSpec spec;
  final NeoForgeServerOptions options;

  final Logger _log = Logger('neoforge');
  final LinkedHashMap<String, NeoForgeClient> _byUuid = LinkedHashMap();
  final List<void Function(NeoForgeClient client)> _listeners = [];
  late final NeoForgeHandshake _handshake;

  NeoForgeServer(this.spec, {this.options = const NeoForgeServerOptions()}) {
    _handshake = NeoForgeHandshake(
      spec,
      options: options,
      log: (message) => _log.info(message),
      onResult: _onResult,
    );
  }

  /// Registers the handshake on [context] (the context `onLoad` receives).
  /// Cancel the returned subscription to stop; clients that are held at that
  /// moment are disconnected.
  ///
  /// With [NeoForgeNegotiation.full] it registers the pre-brand hold too (the
  /// negotiation has to arrive before the server's brand), and captures raw
  /// packets for the ping/pong. Install it from **one** plugin only: a second
  /// NeoForge handshake would answer the same client again (see the README).
  Subscription install(Context context) {
    final full = options.negotiation == NeoForgeNegotiation.full;
    return context.onConfiguration(
      _handshake.start,
      onPreBrand: full ? _handshake.preBrand : null,
      preBrandHoldTimeout: options.preBrandHoldTimeout,
      capturePackets: full,
      holdTimeout: options.holdTimeout,
      onFinish: _handshake.finish,
      finishHoldTimeout: options.finishHoldTimeout,
      failureMessage: 'Failed to complete the NeoForge handshake.',
    );
  }

  /// Installs what a connection that the full handshake marked as NeoForge
  /// needs in the play phase (see [NeoForgePlay]): an empty
  /// `neoforge:recipe_content` on join ([recipeContent]) and, unless
  /// [glidingFlight] is null, the `neoforge:gliding_flight` attribute that
  /// lets the client start an elytra glide. Only players whose connection
  /// was marked are touched, so it is harmless in the ad hoc mode.
  Subscription installPlay(
    Context context, {
    bool recipeContent = true,
    GlidingFlightOptions? glidingFlight = const GlidingFlightOptions(),
  }) => NeoForgePlay(
    spec,
    clientOf,
    recipeContent: recipeContent,
    gliding: glidingFlight,
  ).install(context);

  void _onResult(NeoForgeClient client) {
    _byUuid.remove(client.uuid);
    _byUuid[client.uuid] = client;
    while (_byUuid.length > maxRetainedClients) {
      _byUuid.remove(_byUuid.keys.first);
    }
    switch (client.outcome) {
      case NeoForgeOutcome.accepted:
        _log.info(
          '${client.username} joined with NeoForge '
          '(${client.syncedRegistries.length} registries synced)',
        );
      case NeoForgeOutcome.rejected:
        _log.warn('${client.username} was refused: ${client.failureReason}');
      case NeoForgeOutcome.notNeoForge:
        _log.info(
          '${client.username} is not a NeoForge client (brand ${client.brand})',
        );
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

  /// Calls [listener] whenever the handshake with a client is decided
  /// (accepted, refused, not NeoForge, or the client left). Returns a
  /// function that removes the listener.
  void Function() onClient(void Function(NeoForgeClient client) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// The result for the player with [uuid] (canonical form), if any.
  NeoForgeClient? clientOf(String uuid) => _byUuid[uuid];

  /// The retained results, oldest first.
  Iterable<NeoForgeClient> get clients => _byUuid.values;

  /// Drops the retained result of [uuid] (for example when the player quits).
  NeoForgeClient? forget(String uuid) => _byUuid.remove(uuid);
}
