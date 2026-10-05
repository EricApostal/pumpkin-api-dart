// What the handshake learned about one connecting client. Binding-free.
// ignore: implementation_imports
import 'package:pumpkin_api/src/configuration_core.dart' show ConnectionFlavour;

import 'identifier.dart';
import 'payloads.dart';
import 'protocol.dart';

/// How the handshake with a client ended.
enum NeoForgeOutcome {
  /// Still running.
  pending,

  /// A NeoForge client that took part in the exchange and acknowledged the
  /// registry sync.
  accepted,

  /// Not a NeoForge client (vanilla, Fabric, ...) and the policy lets it
  /// through.
  notNeoForge,

  /// Disconnected by the server: not NeoForge (policy), incompatible, or
  /// it did not answer in time. See [NeoForgeClient.failureReason].
  rejected,

  /// The client left (or its connection ended) before the handshake was done.
  disconnected,
}

/// The result of the handshake for one connection: who it is, what the
/// client announced and registered, and how it ended.
final class NeoForgeClient {
  /// The server's connection id (only valid for this connection).
  final int connectionId;
  final String uuid;
  final String username;

  NeoForgeOutcome _outcome = NeoForgeOutcome.pending;
  String? _failureReason;

  /// The client brand (`neoforge`, `vanilla`, `fabric`, ...) once known.
  String? brand;

  /// The channels the client announced it can receive (`minecraft:register`).
  List<String> announcedChannels = const [];

  /// What the client registered, per protocol (the `neoforge:register`
  /// answer). Null unless the negotiation was [NeoForgeNegotiation.full] and
  /// the client answered the query.
  ModdedNetworkQuery? query;

  /// The channels that were negotiated (`neoforge:network`), if any.
  ModdedNetworkSetup? setup;

  /// The flavour the library gave the connection: [ConnectionFlavour.neoforge]
  /// once the client answered the query and the host was told (full mode),
  /// [ConnectionFlavour.vanilla] otherwise.
  ConnectionFlavour flavour = ConnectionFlavour.vanilla;

  /// The registries that were sent, and whether the client acknowledged them.
  List<String> syncedRegistries = const [];
  bool registriesAcknowledged = false;

  /// The common network versions the client supports (`c:version`).
  List<int> commonVersions = const [];

  /// The play channels the client can receive (`c:register`).
  List<String> commonPlayChannels = const [];

  /// The data maps the client has, per registry.
  Map<String, List<String>> clientDataMaps = const {};

  /// A log of what happened, oldest first.
  final List<String> events = [];

  NeoForgeClient({
    required this.connectionId,
    required this.uuid,
    required this.username,
  });

  NeoForgeOutcome get outcome => _outcome;

  /// Why the client was rejected, if it was.
  String? get failureReason => _failureReason;

  /// Whether the client is a NeoForge client: it answered the query (full
  /// mode) or announced the builtin NeoForge channels.
  bool get isNeoForge =>
      query != null ||
      (announcedChannels.contains(NeoForgeChannels.moddedNetworkQuery) &&
          announcedChannels.contains(NeoForgeChannels.moddedNetwork));

  /// Whether the host treats this connection as a NeoForge one (its play
  /// phase writes NeoForge encodings, and the client expects a few NeoForge
  /// play payloads and attributes): full mode, and the client answered.
  bool get isFlagged => flavour == ConnectionFlavour.neoforge;

  /// Whether the exchange succeeded.
  bool get isAccepted => _outcome == NeoForgeOutcome.accepted;

  /// The namespaces of the payload channels the client registered or
  /// announced, other than NeoForge's own: these are the client's mods that
  /// have networking. (A mod without payloads leaves no trace.)
  Set<String> get modNamespaces {
    final result = <String>{};
    void add(String id) {
      final ns = namespaceOf(id);
      if (ns != 'minecraft' && ns != 'neoforge' && ns != 'c') result.add(ns);
    }

    for (final channel in announcedChannels) {
      add(channel);
    }
    for (final components
        in query?.components.values ?? const <List<QueryComponent>>[]) {
      for (final component in components) {
        add(component.id);
      }
    }
    return result;
  }

  void _log(String message) => events.add(message);

  /// Records [message] in [events] (used by the handshake).
  void note(String message) => _log(message);

  void finish(NeoForgeOutcome outcome, [String? reason]) {
    if (_outcome != NeoForgeOutcome.pending) return;
    _outcome = outcome;
    _failureReason = reason;
    _log('outcome: ${outcome.name}${reason == null ? '' : ' ($reason)'}');
  }

  @override
  String toString() =>
      'NeoForgeClient($username, ${_outcome.name}'
      '${brand == null ? '' : ', brand $brand'}'
      '${_failureReason == null ? '' : ', $_failureReason'})';
}
