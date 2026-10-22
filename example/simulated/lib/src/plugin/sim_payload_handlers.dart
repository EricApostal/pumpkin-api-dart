// What the server does with the serverbound Simulated payloads.
//
// The codecs live in `network/` and are pure; this file is the host-side half
// that the codecs deliberately do not have: look the block entity (or entity)
// up, check the player may act on it, and apply the change. It is the port of
// every `handle(ServerPacketContext)` in `network/packets/**`.
//
// Payloads whose block is not ported yet are listed in
// `docs/PHASE_7B_GAPS.md`; the codecs still negotiate, the server ignores them.
//
// Host: this file uses `pumpkin_api`.
//
// Java: dev.simulated_team.simulated.network.packets.*#handle
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show removeBlock, setBlockState, stateExists;
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/host_bridge.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/core/block_entity.dart' show BlockEntityStore;
import 'package:create/src/core/network.dart' show CreateNetwork;
import 'package:create/src/core/payload.dart' show ClientboundChannel;
import 'package:create/src/core/registry.dart' show CreateRegistry;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart' show SubLevelHelper, Vector3d;

import '../config/sim_config_service.dart';
import '../content/blocks/physics_assembler/physics_assembler_block_entity.dart';
import '../content/blocks/spring/spring_block_entity.dart';
import '../content/blocks/spring/spring_placement.dart';
import '../content/blocks/steering_wheel/steering_wheel_block_entity.dart';
import '../content/blocks/throttle_lever/throttle_lever_block_entity.dart';
import '../content/entities/honey_glue/honey_glue_entity.dart';
import '../content/entities/honey_glue/honey_glue_logic.dart'
    show HoneyGlueVolumeLogic, honeyGlueSpawnData;
import '../content/entities/honey_glue/honey_glue_packet_logic.dart';
import '../host/simulated_host.dart';
import '../index/sim_blocks.dart';
import '../network/payloads/assembly_packets.dart';
import '../network/payloads/control_packets.dart';
import '../network/payloads/honey_glue_packets.dart';
import '../network/payloads/placement_packets.dart';
import '../network/sim_handled.dart';
import '../network/sim_packet.dart';
import '../network/sim_payloads.dart';
import '../util/hold_interaction.dart';

/// The serverbound handlers of the mod.
///
/// The channels are registered through Create's payload registry
/// (`CreateRegistry.serverbound`), and `CreateNetwork` dispatches them: decode,
/// then [dispatch]. The channels this class does not handle stay declared-only
/// (`SimulatedAddon`), so a client still negotiates them.
final class SimPayloadHandlers {
  SimPayloadHandlers({
    required this.blockEntities,
    required this.log,
  });

  /// The plugin's block entity store.
  final BlockEntityStore blockEntities;

  final Logger log;

  /// The clientbound `simulated:honey_glue_sync` channel, attached to the host by
  /// `CreateNetwork.install`; `null` before the plugin is loaded.
  ClientboundChannel<SimPacket, Player>? _glueSync;

  /// The plugin context, for the sends that need the online players. The
  /// `Server` handle is taken per send (`Context.getServer`), never stored.
  Context? _context;

  /// Registers the handled serverbound channels on [registry] (version `0.1`,
  /// required, like every Veil channel of the mod) and installs the dispatcher.
  ///
  /// `SimPacketManager.init` registers every channel with a handler; this is the
  /// subset whose block entity or entity is ported. `simulated:honey_glue_sync`
  /// is registered as a clientbound channel so the resize of a live volume has a
  /// send site (`HoneyGlueEntity.syncBounds`).
  void install(CreateRegistry registry, Context context) {
    // The list is the single source of truth: every id in it is registered with
    // a handler or a sender, and `SimulatedAddon` declares exactly the others.
    for (final id in SimHandledPayloads.serverboundIds) {
      final codec = SimPayloads.byId[id];
      if (codec == null) {
        throw StateError('`$id` is in SimHandledPayloads but has no codec');
      }
      registry.serverbound<SimPacket>(
        id,
        _wire(codec),
        (player, packet) => dispatch(player, packet),
        version: SimChannel.version,
      );
    }
    _glueSync = registry.clientbound<SimPacket>(
      HoneyGlueSyncBoundsPacket.type,
      _wire(HoneyGlueSyncBoundsPacket.codec),
      version: SimChannel.version,
    );
    _context = context;

    CreateNetwork(registry.payloads, log.child('network')).install(context);
  }

  /// A `SimPacketCodec` as the host's `PayloadCodec`.
  static PayloadCodec<T> _wire<T extends SimPacket>(SimPacketCodec<T> codec) =>
      PayloadCodec<T>.of(encode: codec.encode, decode: codec.decode);

  /// Runs the handler of [packet]. Public so the differential can drive a
  /// payload without a client.
  Future<void> dispatch(Player player, SimPacket packet) async {
    switch (packet) {
      case AssemblePacket():
        await _assemble(player, packet);
      case ThrottleLeverSignalPacket():
        _throttleLever(player, packet);
      case SteeringWheelPacket():
        _steeringWheel(player, packet);
      case PlaceSpringPacket():
        await _placeSpring(player, packet);
      case HoneyGlueSpawnPacket():
        await _spawnHoneyGlue(player, packet);
      case HoneyGlueChangeBoundsPacket():
        await _changeHoneyGlueBounds(player, packet);
      default:
        // Every other serverbound payload belongs to content that is not
        // ported yet (see docs/PHASE_7B_GAPS.md); the channel still negotiates.
        return;
    }
  }

  /// `AssemblePacket.handle`: right-clicked assembler.
  ///
  /// TODO(parity): `SimStats.INTERACT_WITH_ASSEMBLER.awardTo(player)`; the
  /// package has no statistic table.
  Future<void> _assemble(Player player, AssemblePacket packet) async {
    final worldId = player.getWorld().getId();
    final assembler = blockEntities.typed<PhysicsAssemblerBlockEntity>(worldId, packet.pos.toBlockPos());
    await assembler?.assembleOrDisassemble();
  }

  /// `ThrottleLeverSignalPacket.handle`: the lever moved, within reach.
  void _throttleLever(Player player, ThrottleLeverSignalPacket packet) {
    final worldId = player.getWorld().getId();
    final lever = blockEntities.typed<ThrottleLeverBlockEntity>(worldId, packet.pos.toBlockPos());
    if (lever == null) return;
    // `BlockHoldInteraction.inInteractionRange(player, Vec3.atCenterOf(pos), 1)`.
    if (!_inReach(player, worldId, packet.pos, reachBuffer: 1)) return;
    lever.setSignal(packet.signal);
  }

  /// `SteeringWheelPacket.handle`: the wheel was turned or released.
  void _steeringWheel(Player player, SteeringWheelPacket packet) {
    final worldId = player.getWorld().getId();
    final wheel = blockEntities.typed<SteeringWheelBlockEntity>(worldId, packet.pos.toBlockPos());
    if (wheel == null) return;

    // `be.targetAngleToUpdate = this.targetAngle();` — the field the tick reads,
    // not `updateTargetAngle` (which would clamp and sequence it). Then
    // `startHolding()` / `stopHolding()`, which set `held` and notify.
    wheel.logic.targetAngleToUpdate = packet.targetAngle;
    wheel.setHeld(!packet.shouldStop);
    // TODO(parity): `SimStats.INTERACT_WITH_STEERING_WHEEL` and
    // `SimAdvancements.UNPOWERED_STEERING`; neither table is ported.
  }

  /// `PlaceSpringPacket.handle`: place the two ends of a spring.
  Future<void> _placeSpring(Player player, PlaceSpringPacket packet) async {
    final world = player.getWorld();
    final worldId = world.getId();
    final parentRelative = packet.parentPos.relative(packet.parentFacing);
    final childRelative = packet.childPos.relative(packet.childFacing);

    final hand = packet.hand == 0 ? Hand.right : Hand.left;
    final inventory = player.getInventory();
    final spring = inventory.getItemInHand(hand: hand);
    if (spring == null) return;

    final holdingSpring = await spring.matches(_springItemKey);
    if (!holdingSpring) {
      spring.dispose();
      return;
    }

    final level = SimulatedHost.instance?.levelOf(worldId);
    final distanceSquared = level == null
        ? _plainDistanceSquared(parentRelative, childRelative)
        : SubLevelHelper.distanceSquaredWithSubLevels(
            level,
            HoldInteractionRange.blockCenter(parentRelative),
            HoldInteractionRange.blockCenter(childRelative),
          );
    if (!SpringPlacement.canPlace(holdingSpring: true, distanceSquared: distanceSquared)) {
      spring.dispose();
      return;
    }

    final controller = await _addSpring(world, parentRelative, childRelative, packet.parentFacing, controller: true);
    final partner = await _addSpring(world, childRelative, parentRelative, packet.childFacing, controller: false);

    if (controller == null || partner == null) {
      await removeBlock(world, parentRelative);
      await removeBlock(world, childRelative);
      spring.dispose();
      return;
    }

    // `player.awardStat(Stats.ITEM_USED.get(spring.getItem()))` is not ported:
    // the package has no statistic table (see docs/PHASE_7B_GAPS.md).
    final distance = SpringPlacement.desiredLength(distanceSquared);
    controller.logic.desiredLength = distance;
    partner.logic.desiredLength = distance;
    controller.sendData();
    partner.sendData();

    if (player.isCreative) {
      spring.dispose();
      return;
    }
    final count = await spring.getCount();
    if (count <= 1) {
      await inventory.setItemInHand(hand: hand, item: null);
    } else {
      await spring.setCount(count: count - 1);
      await inventory.setItemInHand(hand: hand, item: spring);
    }
  }

  /// `PlaceSpringPacket.addSpring`: the spring block and its entity.
  Future<SpringBlockEntity?> _addSpring(
    World world,
    Pos placedPos,
    Pos childPos,
    Direction facing, {
    required bool controller,
  }) async {
    final state = BState(SimBlockKeys.spring).setDir('facing', facing);
    if (!stateExists(state)) return null;
    await setBlockState(world, placedPos, state);

    final created = blockEntities.createAt(world, placedPos.toBlockPos(), SpringBlockEntity.type);
    if (created is! SpringBlockEntity) return null;

    created.logic.isController = controller;
    final subLevel = SimulatedHost.instance?.containingSubLevel(world.getId(), childPos);
    created.setPartnerPos(childPos, subLevel?.uniqueIdOrNull);
    created.sendData();
    return created;
  }

  /// `HoneyGlueSpawnPacket.handle`: spawn a volume over the dragged corners.
  Future<void> _spawnHoneyGlue(Player player, HoneyGlueSpawnPacket packet) async {
    final hand = await _honeyGlueHand(player);
    if (hand == null) return;

    final bounds = packet.bounds;
    final maxRange = SimConfigService.serverConfig.assembly.honeyGlueRange;
    if (HoneyGluePacketLogic.onSpawn(bounds, maxRange: maxRange) != HoneyGlueAction.spawn) return;

    final world = player.getWorld();
    final position = HoneyGlueVolumeLogic.positionForBounds(bounds);
    // `HoneyGlueEntity.setBounds(newBounds)` + `addFreshEntity`: the box is the
    // entity's spawn data (`writeSpawnData`), the client's only source of it and
    // the thing it draws. Without it a NeoForge client keeps the entity, draws
    // nothing and discards it on its first tick.
    final entity = await world.spawnPlugin(
      honeyGlueEntityKey,
      position,
      spawnData: honeyGlueSpawnData(bounds, position),
    );
    honeyGlueTrackerOf(world.getId()).put(HoneyGlue(entity.getId(), bounds));
    entity.dispose();

    // TODO(parity): `level.playSound(HONEY_ADDED)` + `ITEM_FRAME_ADD_ITEM` and
    // `SimAdvancements.NOT_GONNA_SUGARCOAT_IT.awardTo(player)`. `SimSoundIds` is
    // filled by nobody yet (see docs/PHASE_7B_GAPS.md, host gap 4) and the
    // package has no advancement table.
    //
    // `honeyGlueItem.hurtAndBreak(1, level, player, ...)`: the host API has no
    // item durability, so a stack of one is consumed and a larger stack loses a
    // count instead of a point of durability.
    if (player.isCreative) return;
    final inventory = player.getInventory();
    final stack = inventory.getItemInHand(hand: hand);
    if (stack == null) return;
    final count = await stack.getCount();
    if (count <= 1) {
      await inventory.setItemInHand(hand: hand, item: null);
    } else {
      await stack.setCount(count: count - 1);
      await inventory.setItemInHand(hand: hand, item: stack);
    }
  }

  /// `HoneyGlueChangeBoundsPacket.handle`: resize, or kill a volume that is no
  /// longer a legal box.
  Future<void> _changeHoneyGlueBounds(Player player, HoneyGlueChangeBoundsPacket packet) async {
    final uuid = Uuids.tryParse(packet.honeyGlue);
    if (uuid == null) return;

    final world = player.getWorld();
    final entity = world.getEntityByUuid(id: uuid);
    if (entity == null) return;

    final tracker = honeyGlueTrackerOf(world.getId());
    final glue = entity.pluginTypeKey == honeyGlueEntityKey ? tracker.byId(entity.getId()) : null;
    if (glue == null) {
      entity.dispose();
      return;
    }

    final maxRange = SimConfigService.serverConfig.assembly.honeyGlueRange;
    switch (HoneyGluePacketLogic.onChangeBounds(packet.bounds, maxRange: maxRange)) {
      case HoneyGlueAction.resize:
        glue.setBounds(packet.bounds);
        tracker.put(glue);
        // `HoneyGlueEntity.setBoundsAndSync(bounds, player)`: every client that
        // tracks the volume gets the new box, and the one that caused it ignores
        // the update because it already applied the resize locally.
        await _syncHoneyGlueBounds(
          player,
          entity.getId(),
          glue.box,
          world.getId(),
        );
      case HoneyGlueAction.discard:
        tracker.remove(glue.id);
        entity.remove();
      case HoneyGlueAction.spawn:
      case HoneyGlueAction.ignore:
        break;
    }
    entity.dispose();
  }

  /// `HoneyGlueEntity.syncBounds(player)`: `simulated:honey_glue_sync` to the
  /// players that can see the volume.
  ///
  /// Java sends to the entity's tracked players (`VeilPacketManager.tracking`);
  /// the host API has no such query, so the recipients are the online players in
  /// the same world within the entity type's tracking range (10 chunks).
  Future<void> _syncHoneyGlueBounds(
    Player player,
    int entityId,
    Aabb bounds,
    String worldId,
  ) async {
    final channel = _glueSync;
    final context = _context;
    if (channel == null || context == null) return;
    final server = context.getServer();
    final center = bounds.center;
    final recipients = server.playersNear(
      center,
      honeyGlueEntityType.trackingRange * 16.0,
      worldName: worldId,
    );
    if (recipients.isEmpty) {
      server.dispose();
      return;
    }
    try {
      await channel.sendAll(
        recipients,
        HoneyGlueSyncBoundsPacket(bounds, entityId, player.getId().asString),
      );
    } on Object catch (error) {
      log.warn('Could not sync the bounds of honey glue $entityId: $error');
    } finally {
      // The handles came from `Server.getAllPlayers`, so the plugin owns them.
      for (final recipient in recipients) {
        try {
          recipient.dispose();
        } on Object {
          // already invalid
        }
      }
      server.dispose();
    }
  }

  /// `HoneyGlueSpawnPacket.getHoneyGlueHand`: the main hand first.
  Future<Hand?> _honeyGlueHand(Player player) async {
    final inventory = player.getInventory();
    for (final hand in const [Hand.right, Hand.left]) {
      final stack = inventory.getItemInHand(hand: hand);
      if (stack == null) continue;
      final matches = await stack.matches(_honeyGlueItemKey);
      if (matches) return hand;
      stack.dispose();
    }
    return null;
  }

  /// `BlockHoldInteraction.inInteractionRange(player, centre, buffer)`.
  ///
  /// `Player` is not a `LivingEntity` in the host API, so the attribute is read
  /// through `asEntity().asLiving()`; a player that is not one keeps the vanilla
  /// default of 4.5 blocks.
  bool _inReach(Player player, String worldId, Pos pos, {double reachBuffer = 0}) {
    final entity = player.asEntity();
    final eye = entity.getEyePosition();
    final living = entity.asLiving();
    final range = living == null ? 4.5 : living.getAttributeValue(attr: Attribute.blockInteractionRange);
    living?.dispose();
    entity.dispose();
    return HoldInteractionRange.within(
      eye: Vector3d(eye.$1, eye.$2, eye.$3),
      target: HoldInteractionRange.blockCenter(pos),
      range: range,
      level: SimulatedHost.instance?.levelOf(worldId),
      reachBuffer: reachBuffer,
    );
  }

  static const String _springItemKey = 'simulated:spring';
  static const String _honeyGlueItemKey = 'simulated:honey_glue';
}

/// The squared distance between two block centres, for a world without a sable
/// level (a test host).
double _plainDistanceSquared(Pos a, Pos b) {
  final dx = a.$1 - b.$1, dy = a.$2 - b.$2, dz = a.$3 - b.$3;
  return (dx * dx + dy * dy + dz * dz).toDouble();
}
