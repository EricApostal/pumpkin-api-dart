// A port of NeoForge's `NetworkComponentNegotiator`: given the payload
// channels each side registered, decide which are used and why a mismatch is
// one. Binding-free.
import 'nbt_text.dart';
import 'payloads.dart';
import 'protocol.dart';

/// The outcome of [negotiate] for one protocol.
final class NegotiationResult {
  /// The channels both sides will use: id -> version.
  final Map<String, String> channels;

  final bool success;

  /// Per channel id, why it failed (empty on success). These are the
  /// components the client shows on its mismatch screen.
  final Map<String, NbtText> failureReasons;

  const NegotiationResult(this.channels, this.success, this.failureReasons);
}

const String _keyPrefix = 'neoforge.network.negotiation.failure';

/// Negotiates one protocol like `NetworkComponentNegotiator.negotiate`.
///
/// * An optional channel that the other side does not have is dropped.
/// * A channel only one side has, which is not optional, fails.
/// * A channel both have must agree on the flow and the version.
///
/// [modName] maps a channel namespace to the display name of the mod that
/// owns it (null or empty if unknown), as `ModList` does on NeoForge.
NegotiationResult negotiate(
  List<QueryComponent> server,
  List<QueryComponent> client, {
  String? Function(String namespace)? modName,
}) {
  var serverList = [...server];
  var clientList = [...client];

  // Optional channels the other side lacks are switched off.
  final serverIds = {for (final c in serverList) c.id};
  clientList = [
    for (final c in clientList)
      if (!(c.optional && !serverIds.contains(c.id))) c,
  ];
  final clientIds = {for (final c in clientList) c.id};
  serverList = [
    for (final c in serverList)
      if (!(c.optional && !clientIds.contains(c.id))) c,
  ];

  final serverById = {for (final c in serverList) c.id: c};
  final clientById = {for (final c in clientList) c.id: c};
  final matched = {
    for (final id in serverById.keys)
      if (clientById.containsKey(id)) id,
  };

  NbtText forMod(String id, NbtText reason) {
    final namespace = id.substring(0, id.indexOf(':'));
    final name = modName?.call(namespace) ?? '';
    return name.isEmpty
        ? reason
        : NbtText.translatable('$_keyPrefix.mod', [
            NbtText.literal(name),
            reason,
          ]);
  }

  // Channels only the client has (and needs).
  final onlyClient = [
    for (final id in clientById.keys)
      if (!matched.contains(id)) id,
  ];
  if (onlyClient.isNotEmpty) {
    return NegotiationResult(const {}, false, {
      for (final id in onlyClient)
        id: forMod(
          id,
          const NbtText.translatable('$_keyPrefix.missing.client.server'),
        ),
    });
  }
  // Channels only the server has (and needs).
  final onlyServer = [
    for (final id in serverById.keys)
      if (!matched.contains(id)) id,
  ];
  if (onlyServer.isNotEmpty) {
    return NegotiationResult(const {}, false, {
      for (final id in onlyServer)
        id: forMod(
          id,
          const NbtText.translatable('$_keyPrefix.missing.server.client'),
        ),
    });
  }

  final channels = <String, String>{};
  final failures = <String, NbtText>{};
  for (final id in matched) {
    final s = serverById[id]!;
    final c = clientById[id]!;
    final fromServer = _validate(s, c, 'client');
    if (fromServer != null) {
      failures[id] = forMod(id, fromServer);
      continue;
    }
    final fromClient = _validate(c, s, 'server');
    if (fromClient != null) {
      failures[id] = forMod(id, fromClient);
      continue;
    }
    channels[id] = s.version;
  }
  if (failures.isEmpty) return NegotiationResult(channels, true, const {});
  return NegotiationResult(const {}, false, failures);
}

/// `validateComponent(left, right, requestingSide)`; null means compatible.
NbtText? _validate(
  QueryComponent left,
  QueryComponent right,
  String requestingSide,
) {
  final leftFlow = left.flow;
  if (leftFlow != null) {
    final rightFlow = right.flow;
    if (rightFlow == null) {
      return NbtText.translatable('$_keyPrefix.flow.$requestingSide.missing', [
        NbtText.literal(_flowName(leftFlow)),
      ]);
    } else if (leftFlow != rightFlow) {
      return NbtText.translatable('$_keyPrefix.flow.$requestingSide.mismatch', [
        NbtText.literal(_flowName(leftFlow)),
        NbtText.literal(_flowName(rightFlow)),
      ]);
    }
  }
  if (left.version != right.version) {
    final String clientVersion;
    final String serverVersion;
    if (requestingSide == 'client') {
      clientVersion = right.version;
      serverVersion = left.version;
    } else {
      clientVersion = left.version;
      serverVersion = right.version;
    }
    return NbtText.translatable('$_keyPrefix.version.mismatch', [
      NbtText.literal(clientVersion),
      NbtText.literal(serverVersion),
    ]);
  }
  return null;
}

// PacketFlow.toString() is the enum constant name in upper case.
String _flowName(PacketFlow flow) => flow.name.toUpperCase();

/// Negotiates all protocols and builds the `neoforge:network` payload.
/// [serverChannels] and [clientQuery] are per protocol.
({ModdedNetworkSetup? setup, Map<String, NbtText> failures}) negotiateAll(
  Map<NetworkPhase, List<QueryComponent>> serverChannels,
  ModdedNetworkQuery clientQuery, {
  String? Function(String namespace)? modName,
}) {
  final channels = <NetworkPhase, Map<String, String>>{};
  final failures = <String, NbtText>{};
  // NeoForge negotiates exactly the protocols it has registrations for:
  // configuration and play.
  for (final phase in [NetworkPhase.configuration, NetworkPhase.play]) {
    final result = negotiate(
      serverChannels[phase] ?? const [],
      clientQuery.components[phase] ?? const [],
      modName: modName,
    );
    if (!result.success) {
      failures.addAll(result.failureReasons);
      continue;
    }
    channels[phase] = result.channels;
  }
  if (failures.isNotEmpty) return (setup: null, failures: failures);
  return (setup: ModdedNetworkSetup(channels), failures: const {});
}
