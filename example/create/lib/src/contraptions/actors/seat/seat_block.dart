// `SeatBlock`: a seat in one of the 16 dye colours. Right-clicking sits a player (or the leashed
// mob) down, a dye recolours it, and falling onto it bounces or seats the entity.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/block_state.dart';
import '../../../api/blocks.dart' show manifestBlock, setBlockState;
import '../../../common/common.dart';
import '../../../common/host_bridge.dart';
import '../../../core/blocks.dart';
import '../actor_shapes.dart';
import 'seat_entity.dart';

/// `AllShapes.SEAT` (selection) and `SEAT_COLLISION`.
final List<BlockBox> _seatShape = [actorBox(0, 0, 0, 16, 8, 16)];
final List<BlockBox> _seatCollision = [actorBox(0, 0, 0, 16, 6, 16)];

/// `SeatBlock` of the dye colour [color].
CreateBlock buildSeatBlock(String color) {
  final key = '${color}_seat';
  return manifestBlock(
    key,
    placement: const [PlacementRule.inWater('waterlogged')],
    collisionShape: BlockShape.boxes(_seatCollision),
    selectionShape: BlockShape.boxes(_seatShape),
    behavior: BlockBehavior(
      onUse: (server, e) => _use(color, server, e),
      onLandedUpon: (server, e) => _landedUpon(color, server, e),
      isPathfindable: (server, e) => false,
    ),
  );
}

/// `useItemOn` / `useWithoutItem`.
Future<BlockUseResult> _use(
  String color,
  Server server,
  CustomBlockUseEventData e,
) async {
  final player = e.player;
  if (player.asEntity().isSneaking() || player.isFakePlayer)
    return BlockUseResult.pass;

  final world = e.targetWorld;
  final pos = e.pos.toPos();

  final heldKey = e.withItem ? await e.item.getRegistryKey() : 'minecraft:air';
  final dye = _dyeColorOf(heldKey);
  if (dye != null && dye != color) {
    final current = world.getBlockState(pos: e.pos).propertyMap;
    await setBlockState(world, pos, BState('create:${dye}_seat', current));
    return BlockUseResult.success;
  }

  final seatId = SeatEntities.seatAt(world.getId(), pos);
  if (seatId != null) {
    final seat = world.getEntityById(id: seatId);
    if (seat != null) {
      final passengers = seat.passengers;
      if (passengers.isNotEmpty && passengers.first.type == EntityType.player)
        return BlockUseResult.pass;
      await seat.ejectPassengers();
      await player.asEntity().setVehicle(vehicle: seat);
      return BlockUseResult.success;
    }
    SeatEntities.removeSeat(world.getId(), pos);
  }

  await sitDown(world, pos, player.asEntity());
  return BlockUseResult.success;
}

/// `fallOn`: the damage is halved; a mob that can be seated sits down instead of bouncing.
Future<double> _landedUpon(
  String color,
  Server server,
  CustomBlockLandedEventData e,
) async {
  final world = e.targetWorld;
  final pos = e.pos.toPos();
  final entity = world.getEntityById(id: e.entityId);
  final damageMultiplier = e.damageMultiplier * 0.5;
  if (entity == null) return damageMultiplier;

  final isPlayer = entity.type == EntityType.player;
  if (isPlayer || !canBePickedUp(entity) || isSeatOccupied(world, pos)) {
    // Bounce like vanilla's `fallOn` does for an entity that suppresses its bounce.
    final v = entity.velocity;
    if (v.$2 < 0) {
      final factor = entity.asLiving() != null ? 1.0 : 0.8;
      entity.velocity = (v.$1, -v.$2 * 0.66 * factor, v.$3);
    }
    return damageMultiplier;
  }

  await sitDown(world, pos, entity);
  return damageMultiplier;
}

/// `DyeColor.getColor(stack)`.
String? _dyeColorOf(String itemKey) {
  if (!itemKey.startsWith('minecraft:') || !itemKey.endsWith('_dye'))
    return null;
  final color = itemKey.substring(
    'minecraft:'.length,
    itemKey.length - '_dye'.length,
  );
  return dyeColors.contains(color) ? color : null;
}
