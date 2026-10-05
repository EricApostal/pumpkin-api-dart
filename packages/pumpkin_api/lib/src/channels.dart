import 'dart:convert';

import 'bindings.g.dart';
import 'events.dart';
import 'events.g.dart';
import 'infra_core.dart';
import 'logger.dart';
import 'packet_buffer.dart';
import 'uuid_ext.dart';

/// Plain data about a player, safe to keep after the callback returns.
final class ChannelPlayer {
  /// The player's UUID in canonical form.
  final String uuid;

  /// The player's name when the data was recorded.
  final String name;

  const ChannelPlayer(this.uuid, this.name);

  @override
  String toString() => '$name ($uuid)';
}

/// Called with data a client sent on a [PluginChannel]. [player] is only
/// valid until the handler first yields.
typedef ChannelHandler = void Function(Player player, List<int> data);

/// A custom payload (plugin message) channel for talking to client mods,
/// like `myplugin:main`. The name must be `namespace:path`.
///
/// ```dart
/// final channel = PluginChannel('myplugin:hello');
///
/// void onLoad(Context context) {
///   channel.listen(context, (player, data) {
///     player.sendMessage(...);
///     channel.send(player, utf8.encode('pong'));
///   });
/// }
/// ```
final class PluginChannel {
  /// The channel name, `namespace:path`.
  final String name;

  final List<ChannelHandler> _handlers = [];
  final Map<String, ChannelPlayer> _registered = {};
  bool _attached = false;

  /// Throws [ArgumentError] unless [name] looks like `namespace:path`.
  PluginChannel(this.name) {
    final parts = name.split(':');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      throw ArgumentError.value(name, 'name', 'must be "namespace:path"');
    }
  }

  /// Players that told the server they understand this channel, as plain
  /// data. Only players who registered after [listen] was called are known.
  List<ChannelPlayer> get registeredPlayers =>
      List.unmodifiable(_registered.values);

  /// Whether [player] registered this channel.
  bool isRegistered(Player player) =>
      _registered.containsKey(player.getId().asString);

  /// Sends [data] to [player]'s client on this channel. Only Java players
  /// have custom payloads; throws [UnsupportedError] for Bedrock players.
  void send(Player player, List<int> data) {
    final java = player.asJava();
    if (java == null) {
      throw UnsupportedError('Custom payloads need a Java Edition player');
    }
    try {
      java.sendCustomPayload(channel: name, data: data);
    } finally {
      java.dispose();
    }
  }

  /// Sends [text] as UTF-8.
  void sendString(Player player, String text) =>
      send(player, utf8.encode(text));

  /// Sends [value] encoded as JSON text.
  void sendJson(Player player, Object? value) =>
      sendString(player, jsonEncode(value));

  /// Calls [handler] for data clients send on this channel. The first call
  /// registers the server events (needs the load-time [context]); the plugin
  /// can listen several times. Cancel the returned subscription to stop.
  Subscription listen(Context context, ChannelHandler handler) {
    _attach(context);
    _handlers.add(handler);
    return Subscription(() => _handlers.remove(handler));
  }

  void _attach(Context context) {
    if (_attached) return;
    _attached = true;
    context.listen(Events.playerCustomPayload, (server, event) {
      if (event.channel != name) return;
      for (final handler in List.of(_handlers)) {
        handler(event.player, event.data);
      }
    });
    context.listen(Events.playerRegisterChannel, (server, event) {
      if (event.channel != name || event.cancelled) return;
      final uuid = event.player.getId().asString;
      _registered[uuid] = ChannelPlayer(uuid, event.player.getName());
    });
    context.listen(Events.playerUnregisterChannel, (server, event) {
      if (event.channel != name) return;
      _registered.remove(event.player.getId().asString);
    });
    context.listen(Events.playerLeave, (server, event) {
      _registered.remove(event.player.getId().asString);
    });
  }
}

/// A [PluginChannel] whose payloads are values of type [T], converted by a
/// [PayloadCodec]. Payloads that do not decode (a client sent garbage) are
/// logged and dropped instead of reaching the handler.
///
/// ```dart
/// final ping = TypedChannel<int>(
///   'myplugin:ping',
///   PayloadCodec<int>.buffer(
///     write: (w, nonce) => w.writeVarInt(nonce),
///     read: (r) => r.readVarInt(),
///   ),
/// );
///
/// ping.listen(context, (player, nonce) => ping.send(player, nonce));
/// ```
final class TypedChannel<T> {
  /// The underlying channel with the raw bytes.
  final PluginChannel raw;

  /// Converts between [T] and the payload bytes.
  final PayloadCodec<T> codec;

  /// Throws [ArgumentError] unless [name] looks like `namespace:path`.
  TypedChannel(String name, this.codec) : raw = PluginChannel(name);

  /// The channel name, `namespace:path`.
  String get name => raw.name;

  /// See [PluginChannel.registeredPlayers].
  List<ChannelPlayer> get registeredPlayers => raw.registeredPlayers;

  /// See [PluginChannel.isRegistered].
  bool isRegistered(Player player) => raw.isRegistered(player);

  /// Sends [value] to [player]. Throws [UnsupportedError] for Bedrock players.
  void send(Player player, T value) => raw.send(player, codec.encode(value));

  /// Calls [handler] with the values clients send, see [PluginChannel.listen].
  /// [onInvalid] is told about payloads that failed to decode (by default
  /// they are logged as warnings).
  Subscription listen(
    Context context,
    void Function(Player player, T value) handler, {
    void Function(Player player, Object error)? onInvalid,
  }) {
    return raw.listen(context, (player, data) {
      final T value;
      try {
        value = codec.decode(data);
      } catch (e) {
        if (onInvalid != null) {
          onInvalid(player, e);
        } else {
          logger.warn('Invalid payload on $name from ${player.getName()}: $e');
        }
        return;
      }
      handler(player, value);
    });
  }
}

extension PlayerChannelAnnouncement on Player {
  /// Tells this player's client which custom payload channels the server
  /// receives (a `minecraft:register` payload), see [encodeChannelList].
  /// Do it when the player joins, before the mod has to send on them.
  void announceChannels(Iterable<String> channels) {
    final java = asJava();
    if (java == null) return;
    try {
      java.sendCustomPayload(
        channel: registerChannel,
        data: encodeChannelList(channels),
      );
    } finally {
      java.dispose();
    }
  }
}
