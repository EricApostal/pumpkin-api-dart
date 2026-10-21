// Reading what a server *declared* from the outside.
//
// The `NeoForge` handshake has no "tell me your channels" message: the server sends an empty
// `neoforge:register` query, the client answers with its own registrations, and the server replies
// either with `neoforge:network` (the channels both sides have, and the version each is used at) or
// with `neoforge:modded_network_setup_failed` (per channel, why not). That makes a declaration
// readable from a client that answers with a *known* set:
//
//  * every channel in `neoforge:network` is one the server declared with the same flow and version
//    as the answer, so a server that negotiates the whole answer declared at least that;
//  * every channel in the refusal is one the server has and the answer did not (or the reverse),
//    which is what names a declaration that is *wider* than the mod's.
//
// Both are configuration-phase payloads, so only the recording proxy sees them — the client's own
// trace starts at the play phase. `MctraceProxy.decoded` writes them as `kind: payload` lines with
// the channel and the raw bytes, which is what this file reads.

import 'dart:convert';
import 'dart:typed_data';

import 'package:create/src/core/nbt.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../pumpkin_trace.dart';

/// One configuration-phase payload of a proxy trace.
final class HandshakePayload {
  const HandshakePayload(this.channel, this.data);

  final String channel;
  final Uint8List data;
}

/// Every configuration-phase payload of [trace], oldest first.
///
/// The proxy's decoded lines use `kind: payload` for both a configuration payload and a play-phase
/// `custom_payload`; a configuration channel is what `neoforge:` and `minecraft:`/`c:` are, so the
/// filter is by channel rather than by packet id (which means nothing across two servers).
List<HandshakePayload> handshakePayloads(PumpkinTrace? trace) {
  if (trace == null) return const [];
  return [
    for (final packet in trace.packets)
      if (packet.rawKind == 'payload' &&
          packet.channel != null &&
          packet.data != null)
        HandshakePayload(packet.channel!, packet.data!),
  ];
}

/// The channel each side negotiated, from the last `neoforge:network` of [trace].
///
/// The payload is `VAR_INT protocols { VAR_INT protocol, VAR_INT count { STRING id, STRING id,
/// STRING version } }` — the id is repeated inside each value because it is a `NetworkChannel`
/// map, and the second string is the version actually chosen.
///
/// Returns null when the server never accepted a negotiation (a refusal, or no handshake at all).
Map<String, String>? negotiatedChannels(PumpkinTrace? trace) {
  final payloads = handshakePayloads(
    trace,
  ).where((payload) => payload.channel == 'neoforge:network');
  if (payloads.isEmpty) return null;
  final data = payloads.last.data;
  final reader = PacketReader(data);
  final channels = <String, String>{};
  for (var protocol = reader.readVarInt(); protocol > 0; protocol--) {
    reader.readVarInt(); // the ConnectionProtocol ordinal
    for (var count = reader.readVarInt(); count > 0; count--) {
      final id = reader.readString(maxLength: 32767);
      reader.readString(maxLength: 32767); // the id inside the NetworkChannel value
      channels[id] = reader.readString(maxLength: 32767);
    }
  }
  reader.expectEnd();
  return channels;
}

/// The channel ids a `neoforge:modded_network_setup_failed` refusal names, with its reason.
///
/// The payload is `VAR_INT count { STRING id, text component }`, and the component is network NBT —
/// the same reader a payload uses, so the reason can be shown without a second codec. The ids are
/// what a test names: a channel that is in the refusal is one the two sides disagree about.
Map<String, String> refusedChannels(PumpkinTrace? trace) {
  final payloads = handshakePayloads(
    trace,
  ).where((payload) => payload.channel == 'neoforge:modded_network_setup_failed');
  if (payloads.isEmpty) return const {};
  final data = payloads.last.data;
  final reader = PacketReader(data);
  final refused = <String, String>{};
  for (var count = reader.readVarInt(); count > 0; count--) {
    final id = reader.readString(maxLength: 32767);
    final reason = NetworkNbt.read(reader);
    refused[id] = reason == null ? '<no reason>' : _describe(reason);
  }
  return refused;
}

/// A refusal reason, as the key it carries (the client translates it, a test cannot).
String _describe(NbtValue value) {
  if (value.kind == NbtKind.string) return value.value as String;
  if (value.kind != NbtKind.compound) return '$value';
  final compound = value.asCompound;
  final key = compound['translate']?.value;
  if (key is String) {
    final withArgs = compound['with'];
    if (withArgs == null || withArgs.kind != NbtKind.list) return key;
    final args = [
      for (final argument in withArgs.value as List<NbtValue>)
        if (argument.kind == NbtKind.string) argument.value as String,
    ];
    return args.isEmpty ? key : '$key(${args.join(', ')})';
  }
  final text = compound['text']?.value;
  return text is String ? text : jsonEncode(compound.keys.toList());
}
