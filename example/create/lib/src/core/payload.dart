// Payload channel descriptors (pure). The host glue is in `network.dart`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api_core.dart';

/// The id of the channel [path]: `create:<path>`, or [path] itself when it has a
/// namespace (`catnip:...`, `ponder:...`).
String payloadId(String path, {String namespace = 'create'}) => path.contains(':') ? path : '$namespace:$path';

/// Thrown when a channel is registered twice.
final class DuplicateChannelException implements Exception {
  final String id;

  const DuplicateChannelException(this.id);

  @override
  String toString() => 'DuplicateChannelException: payload channel `$id` is registered twice';
}

/// How a channel reaches the other side; implemented by the network glue.
typedef PayloadTransport<C> = Future<void> Function(C player, String channel, List<int> data);

/// A server-to-client channel. [C] is the type that identifies a player (the
/// host's `Player`).
final class ClientboundChannel<T, C> {
  final String id;
  final PayloadCodec<T> codec;
  final String version;
  final bool optional;

  PayloadTransport<C>? _transport;

  ClientboundChannel(this.id, this.codec, {this.version = '1', this.optional = false});

  /// Set by the network glue when the plugin is loaded.
  void attach(PayloadTransport<C> transport) => _transport = transport;

  /// Sends [value] to [player]. Throws a [StateError] before the plugin is loaded.
  Future<void> send(C player, T value) {
    final transport = _transport ?? (throw StateError('Channel $id is not attached to the network yet'));
    return transport(player, id, codec.encode(value));
  }

  /// Sends [value] to every player of [players] (encoded once).
  Future<void> sendAll(Iterable<C> players, T value) async {
    final transport = _transport ?? (throw StateError('Channel $id is not attached to the network yet'));
    final bytes = codec.encode(value);
    for (final player in players) {
      await transport(player, id, bytes);
    }
  }
}

/// A client-to-server channel with its handler.
final class ServerboundChannel<T, C> {
  final String id;
  final PayloadCodec<T> codec;
  final String version;
  final bool optional;
  final FutureOr<void> Function(C player, T value) handler;

  const ServerboundChannel(this.id, this.codec, this.handler, {this.version = '1', this.optional = false});

  /// Decodes [data] and calls the handler. A payload that does not decode throws
  /// the codec's exception, the caller logs and drops it.
  FutureOr<void> dispatch(C player, List<int> data) => handler(player, codec.decode(data));
}

/// All channels, in registration order.
final class PayloadRegistry<C> {
  final Map<String, ServerboundChannel<Object?, C>> _serverbound = {};
  final Map<String, ClientboundChannel<Object?, C>> _clientbound = {};
  final List<String> _order = [];

  /// Declares a client-to-server channel.
  ServerboundChannel<T, C> serverbound<T>(
    String path,
    PayloadCodec<T> codec,
    FutureOr<void> Function(C player, T value) handler, {
    String version = '1',
    bool optional = false,
  }) {
    final id = payloadId(path);
    _claim(id);
    final channel = ServerboundChannel<T, C>(id, codec, handler, version: version, optional: optional);
    _serverbound[id] = ServerboundChannel<Object?, C>(
      id,
      PayloadCodec<Object?>.of(encode: (v) => codec.encode(v as T), decode: (b) => codec.decode(b)),
      (player, value) => handler(player, value as T),
      version: version,
      optional: optional,
    );
    return channel;
  }

  /// Declares a server-to-client channel.
  ClientboundChannel<T, C> clientbound<T>(
    String path,
    PayloadCodec<T> codec, {
    String version = '1',
    bool optional = false,
  }) {
    final id = payloadId(path);
    _claim(id);
    final channel = ClientboundChannel<T, C>(id, codec, version: version, optional: optional);
    _clientbound[id] = channel as ClientboundChannel<Object?, C>;
    return channel;
  }

  void _claim(String id) {
    if (_serverbound.containsKey(id) || _clientbound.containsKey(id)) throw DuplicateChannelException(id);
    _order.add(id);
  }

  /// The handler channel for [id], or `null`.
  ServerboundChannel<Object?, C>? serverboundFor(String id) => _serverbound[id];

  /// Ids of all channels in registration order.
  List<String> get ids => List.unmodifiable(_order);

  /// Ids of the client-to-server channels.
  Iterable<String> get serverboundIds => _serverbound.keys;

  /// The server-to-client channels.
  Iterable<ClientboundChannel<Object?, C>> get clientboundChannels => _clientbound.values;

  /// What the NeoForge declaration needs for each channel, in registration order.
  List<DeclaredPayload> get declared => [
    for (final id in _order)
      if (_serverbound[id] case final s?)
        DeclaredPayload(id, s.version, serverbound: true, optional: s.optional)
      else if (_clientbound[id] case final c?)
        DeclaredPayload(id, c.version, serverbound: false, optional: c.optional),
  ];
}

/// A channel as declared to the NeoForge handshake.
final class DeclaredPayload {
  final String id;
  final String version;

  /// `true` flows client to server, `false` server to client.
  final bool serverbound;
  final bool optional;

  const DeclaredPayload(this.id, this.version, {required this.serverbound, required this.optional});

  @override
  String toString() => '$id v$version ${serverbound ? 'C2S' : 'S2C'}${optional ? ' optional' : ''}';
}
