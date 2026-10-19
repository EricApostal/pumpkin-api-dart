// The payload handlers of contraptions: interaction, client motion, train collision and the
// collider lock request. The clientbound packets (stall, disassembly, block changed, seat
// mapping, relocation, storage sync) are sent by the host entity through `ContraptionEntityHost`;
// the helpers here are for modules that send them directly (the trains module sends
// `ContraptionRelocationPacket`).
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart' show PayloadBus;
import '../../common/common.dart';
import '../../core/module.dart';
import '../core/movement.dart';
import 'host_contraption_entities.dart';

/// `ContraptionInteractionPacket`, `ClientMotionPacket`, `TrainCollisionPacket` and
/// `ContraptionColliderLockPacket.ContraptionColliderLockPacketRequest`.
abstract final class ContraptionPackets {
  /// Registers the serverbound handlers on the payload bus.
  static void install(CreateContext ctx, ContraptionHost host) {
    final bus = ctx.services.find<PayloadBus>();
    if (bus == null) return;

    bus.onServerbound('create:contraption_interact', (player, fields) {
      unawaited(_onInteraction(bus, host, player, fields));
    });

    bus.onServerbound('create:client_motion', (player, fields) {
      _onClientMotion(bus, player, fields);
    });

    bus.onServerbound('create:train_collision', (player, fields) {
      unawaited(_onTrainCollision(host, player, fields));
    });

    bus.onServerbound('create:contraption_collider_lock_request', (
      player,
      fields,
    ) {
      _onColliderLockRequest(bus, player, fields);
    });
  }

  /// `ContraptionColliderLockPacketRequest.handle`: tells the clients tracking the sender which
  /// height offset the sender's player has on the contraption, so they can save it from clipping.
  static void _onColliderLockRequest(
    PayloadBus bus,
    Player player,
    Map<String, Object?> fields,
  ) {
    final contraption = fields['contraption'] as int;
    final offset = (fields['offset'] as num).toDouble();

    final entity = player.asEntity();
    final position = entity.position;
    bus.sendToTrackingAt(
      'create:contraption_collider_lock',
      player.getWorld().getId(),
      (position.$1.floor(), position.$2.floor(), position.$3.floor()),
      {'contraption': contraption, 'offset': offset, 'sender': entity.getId()},
    );
  }

  static Future<void> _onInteraction(
    PayloadBus bus,
    ContraptionHost host,
    Player player,
    Map<String, Object?> fields,
  ) async {
    final target = fields['target'] as int;
    final localPos = fields['localPos'] as (int, int, int);
    final faceOrdinal = fields['face'] as int;
    final hand = fields['hand'] as bool? ?? true;

    final world = player.getWorld();
    final worldId = world.getId();
    final entity = host.entityById(worldId, target);
    if (entity == null) return;

    final hostEntity = entity.host;
    final bb = hostEntity.boundingBox;
    final boundsExtra = math.max(bb.xSize, bb.ySize);
    final distance = 4.5 + 10 + boundsExtra;
    final playerPosition = player.asEntity().position;
    if ((playerPosition - hostEntity.position).lengthSquared >
        distance * distance)
      return;

    final interacting = await HostInteractingPlayer.of(player);
    if (await entity.handlePlayerInteraction(
      interacting,
      localPos,
      Direction.values[faceOrdinal.clamp(0, 5)],
      hand,
    )) {
      // The swing animation is client-side; the host does not expose it.
    }
  }

  static void _onClientMotion(
    PayloadBus bus,
    Player player,
    Map<String, Object?> fields,
  ) {
    final motion = fields['motion'] as (double, double, double);
    final onGround = fields['onGround'] as bool;
    final limbSwing = (fields['limbSwing'] as num).toDouble();

    final entity = player.asEntity();
    entity.setVelocity(velocity: motion);
    entity.setOnGround(onGround: onGround);
    if (onGround) {
      entity.setFallDistance(distance: 0);
    }

    final world = entity.getWorld();
    bus.sendToTrackingAt(
      'create:limbswing_update',
      world.getId(),
      (
        entity.position.$1.floor(),
        entity.position.$2.floor(),
        entity.position.$3.floor(),
      ),
      {
        'entityId': entity.getId(),
        'position': entity.position,
        'limbSwing': limbSwing,
      },
    );
  }

  static Future<void> _onTrainCollision(
    ContraptionHost host,
    Player player,
    Map<String, Object?> fields,
  ) async {
    final damage = fields['damage'] as int;
    final id = fields['contraptionEntityId'] as int;

    final world = player.getWorld();
    final entity = host.entityById(world.getId(), id);
    if (entity == null) return;

    await player.damageByKey(
      damageTypeKey: 'create:run_over',
      amount: damage.toDouble(),
    );
    world.playCustomSound(
      soundName: 'minecraft:entity.player.attack.crit',
      category: SoundCategory.neutral,
      pos: entity.host.position,
      volume: 1,
      pitch: 0.75,
    );
  }

  /// `ContraptionRelocationPacket`: tells the clients to reset the relocation timer of the entity.
  static void sendRelocation(
    PayloadBus bus,
    String worldId,
    Pos pos,
    int entityId,
  ) {
    bus.sendToTrackingAt('create:contraption_relocation', worldId, pos, {
      'entityId': entityId,
    });
  }
}

/// The `InteractingPlayer` of a host [Player].
final class HostInteractingPlayer implements InteractingPlayer {
  final Player player;
  final bool holdsWrenchValue;

  HostInteractingPlayer(this.player, {required this.holdsWrenchValue});

  /// Reads the held item of the main hand (`create:wrench`).
  static Future<HostInteractingPlayer> of(Player player) async {
    var wrench = false;
    final stack = player.getInventoryItem(slot: player.getSelectedSlot());
    if (stack != null) {
      try {
        wrench = await stack.getRegistryKey() == 'create:wrench';
      } finally {
        stack.dispose();
      }
    }
    return HostInteractingPlayer(player, holdsWrenchValue: wrench);
  }

  @override
  String get uuid => player.getId().asString;

  @override
  bool get isSneaking {
    final entity = player.asEntity();
    return entity.isSneaking();
  }

  @override
  bool get isCreative => player.getGamemode() == GameMode.creative;

  @override
  bool get isPassenger => player.asEntity().getVehicle() != null;

  @override
  bool get holdsWrench => holdsWrenchValue;

  @override
  bool canInteractWith(Pos pos, double distance) => true;

  @override
  void playSound(String sound, double pitch, {double volume = 0.3}) {
    player.playCustomSoundAt(
      pos: player.asEntity().position,
      soundName: sound,
      category: SoundCategory.players,
      volume: volume,
      pitch: pitch,
    );
  }

  @override
  Object get hostPlayer => player;
}
