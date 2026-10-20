// `DeployerHandler`: what the deployer's fake player does when it activates — use an item on a
// block or entity, place a block, attack, or break a block. Ported from
// `content/kinetics/deployer/DeployerHandler.java`; the host fake player performs the vanilla
// interactions, so the port delegates the actual item/block/entity handling to it instead of
// reimplementing `useItemOn`, `useOn` and `mineBlock`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../common/stack.dart';
import '../crafter/machine_support.dart' show giveToPlayerStack;
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../transport/transport_behaviours.dart';
import 'deployer_types.dart';

/// Buckets and the fluid they place (`BucketItem.content`).
const Map<String, String> _bucketFluids = {
  'minecraft:water_bucket': 'minecraft:water',
  'minecraft:lava_bucket': 'minecraft:lava',
  'minecraft:milk_bucket': 'minecraft:milk',
  'minecraft:powder_snow_bucket': 'minecraft:powder_snow',
  'minecraft:axolotl_bucket': 'minecraft:water',
  'minecraft:cod_bucket': 'minecraft:water',
  'minecraft:salmon_bucket': 'minecraft:water',
  'minecraft:tropical_fish_bucket': 'minecraft:water',
  'minecraft:pufferfish_bucket': 'minecraft:water',
  'minecraft:tadpole_bucket': 'minecraft:water',
};

/// `DeployerHandler`.
abstract final class DeployerHandler {
  /// `DeployerHandler.shouldActivate`: false when activating would just use the item on itself
  /// (the block it would place), fill an already filled bucket, or process an item on a belt
  /// below a downward deployer.
  static bool shouldActivate(
    PStack held,
    World world,
    Pos targetPos,
    Direction? facing,
  ) {
    if (held.isEmpty) {
      // An empty hand always activates.
    } else {
      final target = world.getBlock(pos: targetPos.toBlockPos());
      if (target.name == held.key) return false;

      final fluid = _bucketFluids[held.key];
      if (fluid != null) {
        final state = world.getFluidState(pos: targetPos.toBlockPos());
        if (state != null && state.fluid == fluid) return false;
      }
    }

    if (held.isNotEmpty && facing == Direction.down) {
      final rt = ProcessingRuntime.instance;
      final worldId = rt.worlds.touch(world);
      final be = rt.store.at(worldId, targetPos.toBlockPos());
      if (be?.getBehaviour<TransportedItemStackHandlerBehaviour>() != null) {
        return false;
      }
    }
    return true;
  }

  /// `DeployerHandler.activate`: moves the fake player and performs the interaction.
  ///
  /// Returns the block the deployer is still breaking (`blockBreakingProgress`), or `null` when
  /// nothing is being broken. [breakingPos] is the block being broken by an earlier activation.
  static Future<Pos?> activate(
    Player player,
    World world,
    Vec3 vec,
    Pos clickedPos,
    Vec3 extensionVector,
    DeployerMode mode, {
    Pos? breakingPos,
    (double, double)? look,
  }) async {
    final rayOrigin = vec + extensionVector * (3 / 2 + 1 / 64);
    final rayTarget = vec + extensionVector * (5 / 2 - 1 / 64);
    final rotation = look ?? rotationFromVector(extensionVector);
    FakePlayerActions(player).moveTo(
      world,
      rayOrigin,
      yaw: rotation.$1,
      pitch: rotation.$2,
    );

    // Entities inside the clicked block (`getEntitiesOfClass` without contraptions).
    final entities = world
        .entitiesIn(Cuboid.corners(clickedPos, clickedPos))
        .where((e) => !_isContraptionEntity(e.entityTypeKey))
        .toList();
    if (entities.isNotEmpty) {
      final random = ProcessingRuntime.instance.random;
      final snapshot = entities[random.nextInt(entities.length)];
      final entity = world.getEntityById(id: snapshot.id);
      if (entity != null) {
        // `if (success) return`: a refused use falls through to the block; an attack always
        // counts (`player.attack` sets success in Java too).
        var success = mode == DeployerMode.punch;
        try {
          if (mode == DeployerMode.use) {
            try {
              await player.interact(entity);
              success = true;
            } on Object {
              // a refused interaction falls through to the block
            }
          } else {
            await player.attack(entity);
            // `entity.captureDrops(...)` then `placeItemBackInInventory`: the host spawns the
            // loot as item entities, so the ones lying where the entity died are collected.
            await _collectDrops(player, world, snapshot.position);
          }
        } finally {
          entity.dispose();
        }
        if (success) return null;
      }
    }

    final hit = world.rayTraceBlock(
      start: rayOrigin,
      end: rayTarget,
      includeFluids: false,
    );
    final face = hit == null
        ? Direction.nearest(
            extensionVector.$1,
            extensionVector.$2,
            extensionVector.$3,
          ).opposite
        : hit.face.toDirection();
    final cursor = hit == null
        ? (0.5, 0.5, 0.5)
        : (
            (hit.hitPos.$1 - clickedPos.$1).clamp(0.0, 1.0),
            (hit.hitPos.$2 - clickedPos.$2).clamp(0.0, 1.0),
            (hit.hitPos.$3 - clickedPos.$3).clamp(0.0, 1.0),
          );

    if (mode == DeployerMode.punch) {
      // `mayInteract` (spawn protection, claim mods) has no host binding; the events the host
      // fires around the break are the protection hook that is available.
      final clicked = clickedPos.toBlockPos();
      if (breakingPos != null) {
        final progress = await player.continueBreaking();
        return switch (progress) {
          BreakProgressInProgress() => breakingPos,
          _ => null,
        };
      }
      final state = world.getBlockState(pos: clicked);
      if (state.outlineShapes.isEmpty) return null;

      // `clickedState.attack(...)` then `if (stack.isEmpty()) return;`: an empty hand swings at
      // the block but never makes progress. The host has no attack-only call, so the swing is
      // dropped rather than turned into a break.
      final held = player.getItemInHand(hand: Hand.right);
      final heldEmpty = held == null;
      held?.dispose();
      if (heldEmpty) return null;

      // The host's break packets carry the block attack (hit sound and particles) and the
      // crack overlay of the progress; `continueBreaking` advances both.
      final progress = await player.startBreaking(clicked, face.toHost());
      return switch (progress) {
        BreakProgressInProgress() => clickedPos,
        _ => null,
      };
    }

    // Right click: the fake player performs the block use, the item use and the placement.
    var changed = false;
    try {
      changed = await player.useItemOnBlock(
        clickedPos.toBlockPos(),
        face.toHost(),
        cursor: cursor,
      );
    } on Object {
      // out of reach or refused
    }
    if (!changed) {
      try {
        await player.useHeldItem();
      } on Object {
        // an item without a use
      }
    }
    return null;
  }

  /// `capturedDrops.forEach(e -> player.getInventory().placeItemBackInInventory(...))`: takes
  /// the dropped items around [position] into the deployer's inventory.
  static Future<void> _collectDrops(
    Player player,
    World world,
    (double, double, double) position,
  ) async {
    final box = Cuboid.around(
      (position.$1.floorToDouble(), position.$2.floorToDouble(), position.$3.floorToDouble()),
      2,
    );
    final drops = world.itemsIn(box);
    if (drops.isEmpty) return;
    for (final drop in drops) {
      final stack = drop.getStack();
      final value = await HostStacks.read(stack);
      stack.dispose();
      if (value.isEmpty) {
        drop.dispose();
        continue;
      }
      drop.discard();
      drop.dispose();
      await giveToPlayerStack(player, world, value);
    }
  }

  /// `!(e instanceof AbstractContraptionEntity)`: a deployer never uses an item on a contraption
  /// entity (the carriage, gantry and stationary contraptions of this mod).
  static bool _isContraptionEntity(String entityTypeKey) => switch (entityTypeKey) {
    'create:contraption' ||
    'create:stationary_contraption' ||
    'create:gantry_contraption' ||
    'create:carriage_contraption' ||
    'create:orientable_contraption' ||
    'create:mounted_contraption' => true,
    _ => false,
  };

  /// The look along [v] for a contraption actor (`DeployerMovementBehaviour.activate`):
  /// `yawFromVector(v)` and `pitchFromVector(v) - 90` (the pitch an entity needs to look along
  /// the vector, where `pitchFromVector` measures from the up axis).
  static (double, double) rotationFromVector(Vec3 v) {
    final yaw = math.atan2(-v.$1, v.$3) * 180 / math.pi;
    final length = v.length;
    final pitch = length == 0 ? 0.0 : -math.asin(v.$2 / length) * 180 / math.pi;
    return (yaw, pitch);
  }
}
