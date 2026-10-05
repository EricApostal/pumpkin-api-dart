import 'package:pumpkin_api/pumpkin_api.dart';

import 'protocol.dart';

/// Whether players without the mod are turned away. Off, so vanilla
/// clients can still join; `/bridge` and the mod features just don't work for
/// them.
const requireMod = false;

/// How long a client has to announce its channels before it counts as vanilla.
const registerTimeout = Duration(seconds: 2);

/// How long the client gets to answer the hello.
const handshakeTimeout = Duration(seconds: 8);

/// A plugin that implements the server side of a mod's protocol: it checks the mod in the
/// configuration phase (before the player joins) and then talks to it over
/// custom payloads.
final class ModBridgePlugin extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: 'modbridge',
    version: '1.0.0',
    description: 'Server backend for the ModBridge client mod.',
  );

  final _users = ModUsers();
  late final _ping = _channel(Protocol.pingChannel, Protocol.ping);
  var _tick = 0;

  TypedChannel<T> _channel<T>(String name, PayloadCodec<T> codec) =>
      TypedChannel<T>(name, codec);

  @override
  void onLoad(Context context) {
    context.runRepeating(1, (_) => _tick++);

    _handshake(context);
    _play(context);
    _commands(context);
    logger.info('ModBridge loaded (protocol ${Protocol.version}).');
  }

  // -- Configuration phase ----------------------------------------------------

  void _handshake(Context context) {
    context.onConfiguration((connection) async {
      // Mod loaders only let a client send channels the server announced.
      connection.announceChannels([Protocol.ackChannel]);

      // A client with the mod lists the mod's channels in its own
      // `minecraft:register`; a vanilla client sends none. Waiting for it
      // spares vanilla players the full handshake timeout.
      final registered = await connection.next(
        registerChannel,
        timeout: registerTimeout,
      );
      final hasMod =
          registered != null &&
          decodeChannelList(registered).contains(Protocol.helloChannel);

      Ack? ack;
      if (hasMod) {
        connection.sendTyped(
          Protocol.helloChannel,
          Protocol.hello,
          const Hello(Protocol.version, 'Pumpkin'),
        );
        ack = await connection.nextTyped(
          Protocol.ackChannel,
          Protocol.ack,
          timeout: handshakeTimeout,
        );
      }

      switch (judge(ack)) {
        case HandshakeOutcome.accepted:
          _users.accept(connection.uuid, ack!.modVersion);
          logger.info(
            '${connection.username} joins with ModBridge ${ack.modVersion} '
            '(client brand: ${connection.brand}).',
          );
          connection.release();
        case HandshakeOutcome.wrongProtocol:
          connection.disconnect(
            'ModBridge protocol mismatch: the server speaks '
            '${Protocol.version}, your mod ${ack!.protocol}. Update the mod.',
          );
        case HandshakeOutcome.noMod:
          if (requireMod) {
            connection.disconnect('This server needs the ModBridge client mod.');
          } else {
            logger.info('${connection.username} joins without ModBridge.');
            connection.release();
          }
      }
    });

    context.listen(Events.configurationEnd, (server, event) {
      if (!event.completed) _users.remove(event.uuid);
    });
  }

  // -- Play phase -------------------------------------------------------------

  void _play(Context context) {
    _ping.listen(context, (player, ping) {
      _pongChannel.send(player, Pong(ping.nonce, _tick));
    });
    context.listen(Events.playerJoin, (server, event) {
      final player = event.player;
      if (_users.has(player.asEntity().getUuid().asString)) {
        player.announceChannels([Protocol.pingChannel]);
      }
    });
    context.listen(Events.playerLeave, (server, event) {
      _users.remove(event.player.asEntity().getUuid().asString);
    });
  }

  late final _pongChannel = _channel(Protocol.pongChannel, Protocol.pong);
  late final _toastChannel = _channel(Protocol.toastChannel, Protocol.toast);

  // -- Commands ---------------------------------------------------------------

  void _commands(Context context) {
    context.command(
      'bridge',
      description: 'Talk to players that run the ModBridge mod',
      permission: 'modbridge:command.bridge',
      (c) => c
        ..sub(
          'info',
          description: 'Who runs the mod',
          runs: (ctx) {
            final players = ctx.server.getAllPlayers();
            final lines = <String>[];
            for (final player in players) {
              final uuid = player.asEntity().getUuid().asString;
              final version = _users.versionOf(uuid);
              lines.add(
                '${player.getName()}: ${version == null ? 'vanilla' : 'ModBridge $version'}',
              );
            }
            ctx.replyLines(['ModBridge players: ${_users.count}', ...lines]);
          },
        )
        ..sub(
          'toast',
          description: 'Show a toast on a player\'s screen',
          build: (s) => s.arg(
            'player',
            ArgumentTypes.player,
            build: (a) => a.arg(
              'message',
              ArgumentTypes.greedyString,
              runs: (ctx) {
                final target = ctx.targetPlayer('player');
                final uuid = target.asEntity().getUuid().asString;
                if (!_users.has(uuid)) {
                  ctx.fail('${target.getName()} does not run the ModBridge mod.');
                }
                _toastChannel.send(
                  target,
                  Toast('Message', ctx.string('message')),
                );
                ctx.reply('Toast sent to ${target.getName()}.');
              },
            ),
          ),
        ),
    );
    context.registerHelp('bridge');
  }
}
