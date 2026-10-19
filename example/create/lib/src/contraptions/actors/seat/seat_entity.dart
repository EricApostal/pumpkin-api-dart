// `SeatEntity`: the invisible entity a seat block spawns for its rider. It has no saved data and
// removes itself when the seat block is gone.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../common/common.dart';
import '../../../common/host_bridge.dart';

/// `create:seat`.
const String seatEntityKey = 'create:seat';

/// `AllEntityTypes.SEAT` as the registry spec (`SeatEntity.build`: 0.25 x 0.35).
const EntityTypeSpec seatEntityType = EntityTypeSpec(
  key: seatEntityKey,
  category: EntityCategory.misc,
  width: 0.25,
  height: 0.35,
  eyeHeight: 0.2975,
  trackingRange: 5,
  updateInterval: 2147483647,
  trackDeltas: false,
  fireImmune: true,
  saveable: false,
  collidable: false,
  pushable: false,
);

/// The spawned seats by world and block position, so the block can find and remove its seat.
abstract final class SeatEntities {
  static final Map<String, Map<Pos, int>> _byWorld = {};

  static Map<Pos, int> of(String worldId) =>
      _byWorld.putIfAbsent(worldId, () => {});

  static int? seatAt(String worldId, Pos pos) => _byWorld[worldId]?[pos];

  static void forgetWorld(String worldId) => _byWorld.remove(worldId);

  static void clear() => _byWorld.clear();

  static void removeSeat(String worldId, Pos pos) =>
      _byWorld[worldId]?.remove(pos);
}

/// `SeatBlock.sitDown`: spawns the seat entity and mounts [entity] on it.
Future<void> sitDown(World world, Pos pos, Entity entity) async {
  final seat = await world.spawnPlugin(seatEntityKey, (
    pos.$1 + .5,
    pos.$2.toDouble(),
    pos.$3 + .5,
  ));
  try {
    SeatEntities.of(world.getId())[pos] = seat.id;
    // `SeatEntity.positionRider`: 1/16 above the seat.
    seat.setPassengerSeat(entity, 0, 1 / 16, 0);
    await entity.setVehicle(vehicle: seat);
  } finally {
    seat.dispose();
  }
}

/// `SeatBlock.isSeatOccupied`.
bool isSeatOccupied(World world, Pos pos) =>
    SeatEntities.seatAt(world.getId(), pos) != null;

/// `SeatBlock.canBePickedUp`: a living entity that is not a player or a shulker. The
/// `logistics.seatHostileMobs` setting needs the entity category, which the host does not expose
/// for vanilla entity types.
bool canBePickedUp(Entity entity) {
  if (entity.type == EntityType.player) return false;
  if (entity.type == EntityType.shulker) return false;
  return entity.asLiving() != null;
}

/// `SeatEntity.tick`: the seat goes away when the block under it is no longer a seat.
void tickSeat(World world, String worldId, Pos pos, int entityId) {
  final block = world.getBlock(pos: pos.toBlockPos());
  if (isSeatBlock(block.name)) return;
  world.getEntityById(id: entityId)?.remove();
  SeatEntities.removeSeat(worldId, pos);
}

/// `SeatBlock` of the decoration-free set: every `create:<color>_seat`.
bool isSeatBlock(String blockKey) =>
    blockKey.startsWith('create:') &&
    blockKey.endsWith('_seat') &&
    blockKey != 'create:seat';
