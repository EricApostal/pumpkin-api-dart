import 'dart:convert';

import 'bindings.g.dart';
import 'events.dart';
import 'events.g.dart';
import 'infra_core.dart';
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
  void sendString(Player player, String text) => send(player, utf8.encode(text));

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
