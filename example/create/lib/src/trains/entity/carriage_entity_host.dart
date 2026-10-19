// What the pure carriage entity logic needs from the entity of the host (pure interfaces).
//
// `CarriageContraptionEntity` (Java: a `OrientedContraptionEntity`) is split in two: the train
// logic in `carriage_contraption_entity.dart` and the entity itself, which the contraptions
// module (or the plugin entity adapter in `carriage_entity_adapter.dart`) provides through
// [CarriageEntityHost]. [CarriagePassenger] is an entity riding the carriage.
import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../util/ctag.dart';
import 'carriage_contraption.dart';
import 'carriage_contraption_entity.dart';
import 'carriage_sync_data.dart';
import 'contraption_data.dart';
import 'train_level.dart';

/// An entity riding a carriage entity (player or mob).
abstract interface class CarriagePassenger {
  String get uuid;

  /// `instanceof Player`.
  bool get isPlayer;

  /// `player.isSpectator()`.
  bool get isSpectator;

  Vec3 get position;

  /// The dimension (world id) the passenger is in.
  String get dimension;

  /// `passenger.saveAsPassenger(output)`: the entity data, `null` when the entity does not save
  /// itself (players).
  CTag? saveAsPassenger();

  /// `passenger.discard()`.
  void discard();

  /// `passenger.stopRiding()` (and for players `getPersistentData().remove("ContraptionDismountLocation")`).
  void stopRiding();

  /// `sp.teleportTo(level, x, y, z, ..., true)` followed by `setPortalCooldown()`.
  void teleportThroughPortal(String dimension, Vec3 location);
}

/// The entity of a carriage as the train logic sees it.
abstract interface class CarriageEntityHost {
  /// `entity.getId()`.
  int get entityId;

  /// `entity.isAlive()`.
  bool get isAlive;

  /// `entity.tickCount`.
  int get tickCount;

  /// `entity.discard()`.
  void discard();

  /// `entity.setPos(pos)` (and the rotation set on the logic entity, see [CarriageContraptionEntity.yaw]).
  void moveTo(Vec3 position, double yaw, double pitch);

  /// `entity.getPassengers()`.
  List<CarriagePassenger> getPassengers();

  /// `entity.getIndirectPassengers()`.
  Iterable<CarriagePassenger> getIndirectPassengers();

  /// `entity.getControllingPlayer()`: the uuid of the player controlling the contraption.
  String? getControllingPlayer();

  /// The online player with [uuid] (`server.getPlayerList().getPlayer(uuid)`).
  CarriagePassenger? findPlayer(String uuid);

  /// `EntityType.loadEntityRecursive(tag, level, ...)` at [position] followed by
  /// `tryAddFreshEntityWithPassengers`.
  CarriagePassenger? loadPassenger(CTag tag, Vec3 position);

  /// `addSittingPassenger(passenger, seat)`.
  void addSittingPassenger(CarriagePassenger passenger, int seat);

  /// `alignPassenger(passenger)`.
  void alignPassenger(CarriagePassenger passenger);

  /// `isStalled()`: a movement actor of the contraption stalled it.
  bool isStalled();

  /// `tickActors()`: ticks the movement behaviours of the contraption.
  void tickActors();

  /// `canInteractWithBlock(player, pos, distance)`.
  bool canInteractWithBlock(String playerUuid, Vec3 position, double distance);

  /// `saveAsPassenger(entity)`: the saved entity (contraption included), with the passengers.
  CTag? saveAsPassenger();

  /// `entityData.set(CARRIAGE_DATA, data)`: pushes the sync data to the clients.
  void setCarriageData(CarriageSyncData data);

  /// `entityData.set(SCHEDULED, value)`.
  void setScheduled(bool scheduled);

  /// `entityData.set(TRACK_GRAPH, Optional.ofNullable(id))`.
  void setTrackGraph(String? graphId);

  /// `setBlock(localPos, info)`: replaces a block of the contraption and tells the clients
  /// (`ContraptionBlockChangedPacket`).
  void blockChanged(Pos localPos, ContraptionBlockInfo info);

  /// `entity.disassemble()`.
  void disassemble();

  /// `getInitialOrientation()`.
  Direction getInitialOrientation();

  /// `level().gameEvent(this, GameEvent.RESONATE_8, position())`.
  void resonate();
}

/// Creates carriage entities in a level; provided by the contraptions module (or by the plugin
/// entity adapter of this module). Installed in [CarriageEntities.factory].
abstract interface class CarriageEntityFactory {
  /// `CarriageContraptionEntity.create(level, contraption)`: a new entity carrying [contraption]
  /// (not added to the level yet).
  CarriageContraptionEntity create(TrainLevel level, CarriageContraption contraption);

  /// `EntityType.create(serialisedEntity, level)` at [position]: re-creates the entity from its
  /// saved form and adds it to the level. `null` when the data does not make a carriage entity.
  CarriageContraptionEntity? spawnFromSaved(TrainLevel level, CTag serialisedEntity, Vec3? position);
}

abstract final class CarriageEntities {
  static CarriageEntityFactory? factory;
}
