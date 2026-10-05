// What a plugin has to do in the play phase for a client that the full
// handshake classified as NeoForge: the behaviours that are not encodings (the
// host writes those) but things the NeoForge client expects from a NeoForge
// server. See docs/neoforge-play-codecs.md ("Behaviour that changes without a
// wire change").
import 'package:pumpkin_api/pumpkin_api.dart';

import 'client_info.dart';
import 'play_core.dart';
import 'spec.dart';

/// Sends the play-phase extras to flagged connections. Created by
/// [NeoForgeServer.installPlay].
final class NeoForgePlay {
  final NeoForgeClient? Function(String uuid) _clientOf;
  final bool recipeContent;
  final GlidingFlightOptions? gliding;
  final int? _attributeId;
  final Logger _log = Logger('neoforge');

  /// Per player (uuid) what the client was last told: whether a glider is
  /// worn. Absent: nothing was sent (a new entity on the client).
  final Map<String, bool> _glider = {};

  NeoForgePlay(
    NeoForgeServerSpec spec,
    this._clientOf, {
    this.recipeContent = true,
    this.gliding = const GlidingFlightOptions(),
  }) : _attributeId = gliding == null
           ? null
           : glidingFlightAttributeId(spec, gliding);

  /// Whether the connection of [uuid] was marked as NeoForge.
  bool _flagged(String uuid) {
    final client = _clientOf(uuid);
    return client != null && client.isFlagged && client.isAccepted;
  }

  /// Registers the listeners and the check task on [context].
  Subscription install(Context context) {
    final options = gliding;
    final attributeId = _attributeId;
    if (options != null && attributeId == null) {
      _log.warn(
        'Cannot tell the registry id of $glidingFlightAttribute (the spec '
        'syncs minecraft:attribute without it): elytra will not work for '
        'NeoForge clients. Add NeoForge\'s attributes to the spec or pass '
        'GlidingFlightOptions.attributeId.',
      );
    }
    final subscriptions = <void Function()>[
      context.listen(Events.playerJoin, (server, event) {
        final uuid = event.player.getId().asString;
        _glider.remove(uuid);
        if (!_flagged(uuid)) return;
        if (recipeContent) {
          _send(
            event.player,
            () => event.player.asJava()?.sendCustomPayload(
              channel: recipeContentChannel,
              data: emptyRecipeContent,
            ),
          );
        }
      }).cancel,
      // The client creates a new player entity, whose attributes are fresh.
      context.listen(Events.playerRespawn, (server, event) {
        _glider.remove(event.player.getId().asString);
      }).cancel,
      context.listen(Events.playerChangeWorld, (server, event) {
        _glider.remove(event.player.getId().asString);
      }).cancel,
      context.listen(Events.playerLeave, (server, event) {
        _glider.remove(event.player.getId().asString);
      }).cancel,
      if (options != null && attributeId != null)
        context.every(options.interval, (server) {
          for (final player in server.getAllPlayers()) {
            _checkGlider(player, options, attributeId);
          }
        }).cancel,
    ];
    return Subscription(() {
      for (final cancel in subscriptions) {
        cancel();
      }
      _glider.clear();
    });
  }

  void _checkGlider(
    Player player,
    GlidingFlightOptions options,
    int attributeId,
  ) {
    final uuid = player.getId().asString;
    if (!_flagged(uuid)) return;
    final chest = player.getInventory().getChestplate();
    final wearing =
        chest != null && options.gliderItems.contains(chest.getRegistryKey());
    if (_glider[uuid] == wearing) return;
    _send(player, () {
      player.asJava()?.sendPacket(
        packet: JavaPacketsClientboundPacketCUpdateAttributes(
          JavaPacketsCUpdateAttributes(
            entityId: player.asEntity().getId(),
            properties: [
              Property(
                id: attributeId,
                value: 0,
                modifiers: [
                  if (wearing)
                    const JavaPacketsAttributeModifier(
                      id: gliderModifierId,
                      amount: 1,
                      operation: 0, // ADD_VALUE
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    });
    _glider[uuid] = wearing;
  }

  void _send(Player player, void Function() send) {
    try {
      send();
    } catch (e, s) {
      _log.error('Could not send to ${player.getName()}: $e\n$s');
    }
  }
}
