// The host side of a carriage contraption: the train's `CarriageContraption` (pure) wrapped
// around the contraption the contraptions module owns, the entity that carries it, and the
// factory the trains module creates its carriages with.
//
// Java: `content/trains/entity/CarriageContraptionEntity` (an `OrientedContraptionEntity` whose
// contraption is a `CarriageContraption`) and `CarriageContraption` itself. The train logic lives
// in `trains/entity/carriage_contraption_entity.dart` and `trains/entity/carriage_contraption.dart`
// (pure); this file only bridges them to the contraption structure and the plugin entity.
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/trains.dart'
    show
        CarriageContraptionAssembly,
        ConductorSeatLookup,
        ScheduleCarriagePassenger;
import '../../common/binary_nbt.dart';
import '../../common/common.dart';
import '../../common/nbt_convert.dart';
import '../../common/vec_helper.dart';
import '../../core/nbt.dart';
import '../../trains/entity/carriage_contraption.dart';
import '../../trains/entity/carriage_contraption_entity.dart';
import '../../trains/entity/carriage_entity_host.dart';
import '../../trains/entity/carriage_storage.dart';
import '../../trains/entity/carriage_sync_data.dart';
import '../../trains/entity/contraption_data.dart';
import '../../trains/entity/train_level.dart';
import '../../trains/util/ctag.dart';
import '../actors/host_interacting_player.dart';
import '../core/contraption.dart';
import '../core/level.dart';
import '../core/nbt_map.dart';
import '../core/structure_info.dart';
import '../storage/train_cargo_manager.dart';
import 'contraption_entity.dart';
import 'contraption_synced_data.dart' show ContraptionSyncedData;
import 'host_contraption_entities.dart';
import 'oriented_contraption_entity.dart';

/// `AllContraptionTypes.CARRIAGE`.
const String carriageContraptionTypeId = 'create:carriage';

/// `AllEntityTypes.CARRIAGE_CONTRAPTION`.
const String carriageContraptionEntityKey = 'create:carriage_contraption';

/// The contraption of one carriage: a [Contraption] that also keeps the train specific part
/// ([train]) and starts with a [TrainCargoManager], which the train takes over after assembly.
final class HostCarriageContraption extends Contraption {
  final CarriageContraption train;

  /// The level the contraption was assembled in or read from; the pure train part needs it for
  /// `startMoving` / `onEntityInitialize`.
  ContraptionLevel? level;

  late final HostCarriageContraptionData dataView;

  HostCarriageContraption(Direction assemblyDirection)
    : train = CarriageContraption(assemblyDirection) {
    dataView = HostCarriageContraptionData(this);
    train.data = dataView;
    // `CarriageContraption`'s constructor: `storage = new TrainCargoManager()`.
    storage = TrainCargoManager();
  }

  @override
  String get typeId => carriageContraptionTypeId;

  /// `getAssemblyDirection()`.
  Direction get assemblyDirection => train.assemblyDirection;

  /// `assemble`: the structure search is synchronous, and so is the carriage check.
  bool assembleSync(ContraptionLevel level, Pos pos) {
    this.level = level;
    disassembled = false;
    if (!searchMovedStructure(level, pos, null)) return false;
    return train.checkAssembly();
  }

  @override
  Future<bool> assemble(ContraptionLevel level, Pos pos) async =>
      assembleSync(level, pos);

  /// `CarriageContraption.isAnchoringBlockAt`: the anchor of a carriage is its own bogey, which is
  /// part of the structure. The base class would skip it and capture nothing.
  @override
  bool isAnchoringBlockAt(Pos pos) => train.isAnchoringBlockAt(pos);

  /// `CarriageContraption.capture`: counts bogeys, conductors and controls before the block is
  /// captured by the base class.
  @override
  CapturedBlock capture(ContraptionLevel level, Pos pos) {
    train.capture(level.stateAt(pos), pos);
    return super.capture(level, pos);
  }

  @override
  NbtMap writeNbt({bool spawnPacket = false}) {
    final nbt = super.writeNbt(spawnPacket: spawnPacket);
    final tag = CTag.fromNbt(nbt.toValue());
    train.writeNBT(tag);
    for (final entry in tag.entries.entries) {
      nbt.map[entry.key] = entry.value;
    }
    return nbt;
  }

  @override
  void readNbt(ContraptionLevel level, NbtMap nbt, {bool spawnData = false}) {
    this.level = level;
    super.readNbt(level, nbt, spawnData: spawnData);
    train.readNBT(CTag.fromNbt(nbt.toValue()));
  }
}

/// The [ContraptionData] view of a [HostCarriageContraption] (Java: the contraption itself).
final class HostCarriageContraptionData implements ContraptionData {
  HostCarriageContraptionData(this.contraption);

  final HostCarriageContraption contraption;

  late final Map<Pos, ContraptionBlockInfo> _blocks = _CarriageBlocksView(
    contraption,
  );

  @override
  Map<Pos, ContraptionBlockInfo> getBlocks() => _blocks;

  @override
  Pos get anchor => contraption.anchor;

  @override
  Pos toLocalPos(Pos pos) => contraption.toLocalPos(pos);

  @override
  List<Pos> getSeats() => contraption.getSeats();

  @override
  Map<String, int> getSeatMapping() => contraption.getSeatMapping();

  @override
  Pos? getSeatOf(String passengerUuid) => contraption.getSeatOf(passengerUuid);

  @override
  void cancelActorStalls() => contraption.cancelActorStalls();

  @override
  void startMoving(TrainLevel level) {
    final contraptionLevel = contraption.level;
    if (contraptionLevel != null) contraption.startMoving(contraptionLevel);
  }

  @override
  void onEntityInitialize(TrainLevel level, Object entity) {
    final contraptionLevel = contraption.level;
    if (contraptionLevel == null) return;
    final host = entity is CarriageContraptionEntity ? entity.host : null;
    final handle = host is HostCarriageEntity ? host.worldEntity : null;
    if (handle == null) return;
    contraption.onEntityInitialize(contraptionLevel, handle);
  }

  @override
  void setPortalHiding(
    bool Function(Pos localPos) hiddenInPortal,
    bool Function() collidersHidden,
  ) {
    contraption.hiddenInPortalTest = hiddenInPortal;
    contraption.simplifiedCollidersHidden = collidersHidden;
  }

  @override
  CarriageStorage? takeStorage() {
    final taken = contraption.takeStorage();
    if (taken is! CarriageStorage) return null;
    return taken as CarriageStorage;
  }

  @override
  void returnStorage(CarriageStorage storage) =>
      contraption.returnStorageForDisassembly(storage);

  /// `contraption.removeBlocksFromWorld(level, BlockPos.ZERO)`: the station calls this through
  /// [ContraptionData] before it creates the train.
  @override
  Future<void> removeBlocksFromWorld() async {
    final level = contraption.level;
    if (level == null) return;
    await contraption.removeBlocksFromWorld(level, posZero);
  }

  @override
  void expandBoundsAroundAxis(Axis axis) =>
      contraption.expandBoundsAroundAxis(axis);
}

/// The live `getBlocks()` map of the contraption, in the train code's block info type.
final class _CarriageBlocksView extends MapBase<Pos, ContraptionBlockInfo> {
  _CarriageBlocksView(this.contraption);

  final HostCarriageContraption contraption;

  Map<Pos, StructureBlockInfo> get _blocks => contraption.blocks;

  @override
  ContraptionBlockInfo? operator [](Object? key) {
    final info = _blocks[key];
    if (info == null) return null;
    return ContraptionBlockInfo(
      info.state,
      info.nbt == null ? null : CTag.fromNbt(info.nbt!.toValue()),
    );
  }

  @override
  void operator []=(Pos key, ContraptionBlockInfo value) {
    _blocks[key] = StructureBlockInfo(
      key,
      value.state,
      value.nbt == null ? null : NbtMap.of(value.nbt!.toNbt()),
    );
  }

  @override
  void clear() => _blocks.clear();

  @override
  Iterable<Pos> get keys => _blocks.keys;

  @override
  ContraptionBlockInfo? remove(Object? key) {
    final info = _blocks.remove(key);
    if (info == null) return null;
    return ContraptionBlockInfo(
      info.state,
      info.nbt == null ? null : CTag.fromNbt(info.nbt!.toValue()),
    );
  }

  @override
  int get length => _blocks.length;
}

/// The entity that shows a carriage: the core oriented contraption entity plus the train logic
/// of [CarriageContraptionEntity].
final class HostCarriageContraptionEntity extends OrientedContraptionEntity {
  HostCarriageContraptionEntity(super.host);

  /// The pure train side; set right after construction.
  CarriageContraptionEntity? train;

  /// The synced values the train side sets. All four are pushed to the clients tracking the entity
  /// as `SynchedEntityData` entries (`ContraptionSyncedData`): [lastCarriageData] as `CARRIAGE_DATA`
  /// (`HostCarriageEntity.setCarriageData`), [scheduled] as `SCHEDULED` and [trackGraph] as
  /// `TRACK_GRAPH` (`setScheduled`/`setTrackGraph`).
  CarriageSyncData? lastCarriageData;
  bool scheduled = false;
  String? trackGraph;

  int _ticks = 0;

  /// `Entity.tickCount`.
  int get tickCount => _ticks;

  /// `setPos(pos)` with the rotation the carriage has.
  void moveToTrain(Vec3 position, double yaw, double pitch) {
    this.yaw = yaw;
    this.pitch = pitch;
    setPos(position);
  }

  @override
  Future<void> tick() async {
    await super.tick();
    _ticks++;
    train?.tick();
  }

  @override
  Future<void> tickContraption() async {
    if (nonDamageTicks > 0) nonDamageTicks--;
    final train = this.train;
    if (train == null) {
      await super.tickContraption();
      return;
    }
    train.tickContraption();
  }

  @override
  void writeAdditional(NbtMap compound, {bool spawnPacket = false}) {
    super.writeAdditional(compound, spawnPacket: spawnPacket);
    final tag = CTag.fromNbt(compound.toValue());
    train?.writeAdditional(tag, spawnPacket);
    for (final entry in tag.entries.entries) {
      compound.map[entry.key] = entry.value;
    }
  }

  @override
  void readAdditional(NbtMap compound, {bool spawnData = false}) {
    super.readAdditional(compound, spawnData: spawnData);
    final contraption = this.contraption;
    if (contraption is HostCarriageContraption) {
      train?.contraption = contraption.train;
      contraption.train.data = contraption.dataView;
    }
    train?.readAdditional(CTag.fromNbt(compound.toValue()), spawnData);
  }
}

/// The [CarriageEntityHost] of a [HostCarriageContraptionEntity].
final class HostCarriageEntity implements CarriageEntityHost {
  HostCarriageEntity({
    required this.worldEntity,
    required this.world,
    required this.level,
    required this.host,
  });

  final HostCarriageContraptionEntity worldEntity;
  final World world;
  final TrainLevel level;
  final ContraptionHost host;

  String get _worldId => world.getId();

  AbstractContraptionEntity? _entityById(int id) => host.entityById(_worldId, id);

  @override
  int get entityId => worldEntity.host.entityId;

  @override
  bool get isAlive => worldEntity.host.isAlive;

  @override
  int get tickCount => worldEntity.tickCount;

  @override
  void discard() => worldEntity.remove();

  @override
  void moveTo(Vec3 position, double yaw, double pitch) =>
      worldEntity.moveToTrain(position, yaw, pitch);

  @override
  List<CarriagePassenger> getPassengers() =>
      [for (final p in worldEntity.host.passengers) _asPassenger(p)];

  @override
  Iterable<CarriagePassenger> getIndirectPassengers() sync* {
    for (final passenger in worldEntity.host.passengers) {
      final wrapped = _asPassenger(passenger);
      yield wrapped;
      yield* _childrenOf(wrapped);
    }
  }

  Iterable<CarriagePassenger> _childrenOf(CarriagePassenger passenger) sync* {
    if (passenger is! HostCarriagePassenger) return;
    for (final child in passenger.childPassengers()) {
      yield child;
      yield* _childrenOf(child);
    }
  }

  CarriagePassenger _asPassenger(ContraptionPassengerRef ref) {
    if (ref is CarriagePassenger) return ref as CarriagePassenger;
    return HostCarriagePassenger(
      world,
      ref.entityId,
      ref.uuid,
      _entityById,
      (dimension) => host.worldOf(dimension),
    );
  }

  @override
  String? getControllingPlayer() => worldEntity.host.controllingPlayer;

  @override
  CarriagePassenger? findPlayer(String uuid) {
    for (final player in ContraptionHost.bus?.roster.players ??
        const <Player>[]) {
      if (player.getId().asString != uuid) continue;
      final handle = player.asEntity();
      try {
        return HostCarriagePassenger(
          world,
          handle.getId(),
          uuid,
          _entityById,
          (dimension) => host.worldOf(dimension),
        );
      } finally {
        handle.dispose();
      }
    }
    return null;
  }

  /// `EntityType.create(tag, level)` at [position]: the spawn is a host call, so the passenger
  /// is returned once the entity exists.
  @override
  Future<CarriagePassenger?> loadPassenger(CTag tag, Vec3 position) async {
    if (!tag.contains('id')) return null;
    final Entity? spawned;
    try {
      spawned = await world.spawnEntityFromNbt(
        nbt: BinaryNbt.write(tag.toNbt()),
        pos: position,
      );
    } on Object {
      return null;
    }
    if (spawned == null) return null;
    try {
      return HostCarriagePassenger(
        world,
        spawned.getId(),
        spawned.getUuid().toString(),
        _entityById,
        (dimension) => host.worldOf(dimension),
      );
    } finally {
      spawned.dispose();
    }
  }

  @override
  void addSittingPassenger(CarriagePassenger passenger, int seat) {
    final ref = passenger is ContraptionPassengerRef
        ? passenger
        : (passenger is HostCarriagePassenger
              ? passenger as ContraptionPassengerRef
              : null);
    if (ref == null) return;
    worldEntity.addSittingPassenger(ref, seat);
  }

  /// `AbstractContraptionEntity.alignPassenger`: turn the rider towards the motion.
  @override
  void alignPassenger(CarriagePassenger passenger) {
    if (passenger is! HostCarriagePassenger) return;
    final entity = passenger.resolve();
    if (entity == null) return;
    try {
      if (entity.asLiving() == null) return;
      final motion = worldEntity.getContactPointMotion(entity.getEyePosition());
      if (motion.$1.abs() < 1e-4 &&
          motion.$2.abs() < 1e-4 &&
          motion.$3.abs() < 1e-4) {
        return;
      }
      final target = AngleHelper.deg(-math.atan2(motion.$1, motion.$3));
      final angle = AngleHelper.angleLerp(0.4, entity.getYaw(), target);
      entity.setRotation(yaw: angle, pitch: entity.getPitch());
    } finally {
      entity.dispose();
    }
  }

  @override
  bool isStalled() => worldEntity.isStalled;

  @override
  void tickActors() => unawaited(worldEntity.tickActors());

  /// `player.isWithinBlockInteractionRange(pos, distance)`: the host's interacting player
  /// reports that as true, so a player that was found can always reach the controls.
  @override
  bool canInteractWithBlock(String playerUuid, Vec3 position, double distance) {
    final player = _player(playerUuid);
    if (player == null) return false;
    return worldEntity.canInteractWithBlock(
      HostInteractingPlayer(player),
      position,
      distance,
    );
  }

  Player? _player(String uuid) {
    for (final player in ContraptionHost.bus?.roster.players ??
        const <Player>[]) {
      if (player.getId().asString == uuid) return player;
    }
    return null;
  }

  /// The saved entity: the contraption (with the train part) plus the train binding, in the
  /// shape `spawnFromSaved` reads back. The host has no entity serialiser of its own.
  @override
  CTag? saveAsPassenger() {
    final nbt = NbtMap();
    worldEntity.writeAdditional(nbt);
    nbt.putString('id', carriageContraptionEntityKey);
    nbt.putVec('Pos', worldEntity.position);
    return CTag.fromNbt(nbt.toValue());
  }

  /// `entityData.set(CARRIAGE_DATA, data)`: the entry is pushed to the clients tracking the
  /// entity as a metadata update (`Entity.setSyncedEntry`), which is what
  /// `CarriageContraptionEntity.onSyncedDataUpdated` reads on the client.
  @override
  void setCarriageData(CarriageSyncData data) {
    worldEntity.lastCarriageData = data;
    final host = worldEntity.host;
    if (host is! HostContraptionEntity) return;
    final entry = CarriageSyncDataSerializer.encodeEntry(data);
    if (entry == null) return;
    host.handle?.setSyncedEntry(
      CarriageSyncDataSerializer.carriageDataIndex,
      entry,
    );
  }

  /// `entityData.set(SCHEDULED, value)`: the client's `hasSchedule()` gates the conductor hats and
  /// the blaze burner schedule display, so a train's schedule has to reach the client.
  @override
  void setScheduled(bool scheduled) {
    if (worldEntity.scheduled == scheduled) return;
    worldEntity.scheduled = scheduled;
    worldEntity.host.setSyncedEntry(
      ContraptionSyncedData.scheduledIndex,
      ContraptionSyncedData.booleanEntry(scheduled),
    );
  }

  /// `entityData.set(TRACK_GRAPH, Optional.ofNullable(id))`: the client resolves the id in its own
  /// `RAILWAYS.trackNetworks` and marks the carriage derailed when it is empty
  /// (`CarriageContraptionEntity.updateTrackGraph`), so without the entry every carriage looks
  /// derailed.
  @override
  void setTrackGraph(String? graphId) {
    if (worldEntity.trackGraph == graphId) return;
    worldEntity.trackGraph = graphId;
    final entry = ContraptionSyncedData.optionalUuidEntry(graphId);
    if (entry == null) return;
    worldEntity.host.setSyncedEntry(
      ContraptionSyncedData.trackGraphIndex,
      entry,
    );
  }

  @override
  void blockChanged(Pos localPos, ContraptionBlockInfo info) =>
      worldEntity.host.sendBlockChanged(localPos, info.state);

  @override
  void disassemble() => unawaited(worldEntity.disassemble());

  @override
  Direction getInitialOrientation() => worldEntity.getInitialOrientation();

  /// `level.gameEvent(this, RESONATE_8, position())`: the host exposes no server game event API.
  @override
  void resonate() {}
}

/// A passenger of a carriage, held as a world and an entity id (host handles are only valid
/// inside the callback that received them).
final class HostCarriagePassenger
    implements CarriagePassenger, ContraptionPassengerRef {
  HostCarriagePassenger(
    this.world,
    this.entityId,
    this.uuid,
    this._entityById,
    this._worldOf,
  );

  final World world;
  final AbstractContraptionEntity? Function(int id) _entityById;
  final World? Function(String dimension) _worldOf;

  @override
  final int entityId;

  @override
  final String uuid;

  Vec3 _lastPosition = vec3Zero;

  /// The host entity for one use, `null` when it is gone. The caller must [Entity.dispose] it.
  Entity? resolve() => world.getEntityById(id: entityId);

  T? _with<T>(T Function(Entity entity) body) {
    final entity = resolve();
    if (entity == null) return null;
    try {
      return body(entity);
    } finally {
      entity.dispose();
    }
  }

  @override
  bool get isPlayer =>
      _with((e) => hostEntityTypeKey(e) == 'minecraft:player') ?? false;

  @override
  bool get isTamableAnimal =>
      _with(
        (e) => const {
          'minecraft:wolf',
          'minecraft:cat',
          'minecraft:ocelot',
          'minecraft:parrot',
        }.contains(hostEntityTypeKey(e)),
      ) ??
      false;

  @override
  bool get isPassenger =>
      _with((e) {
        final vehicle = e.getVehicle();
        if (vehicle == null) return false;
        vehicle.dispose();
        return true;
      }) ??
      false;

  @override
  double get vehicleAttachmentPointY => 0;

  @override
  Object? get contraptionEntity => _entityById(entityId);

  @override
  ContraptionPassengerRef? get vehicle => _with<ContraptionPassengerRef?>((e) {
    final vehicle = e.getVehicle();
    if (vehicle == null) return null;
    try {
      return HostCarriagePassenger(
        world,
        vehicle.getId(),
        vehicle.getUuid().toString(),
        _entityById,
        _worldOf,
      );
    } finally {
      vehicle.dispose();
    }
  });

  /// The direct passengers of this entity, for `getIndirectPassengers`.
  List<CarriagePassenger> childPassengers() => _with<List<CarriagePassenger>>((e) {
        final out = <CarriagePassenger>[];
        for (final child in e.getPassengers()) {
          try {
            out.add(
              HostCarriagePassenger(
                world,
                child.getId(),
                child.getUuid().toString(),
                _entityById,
                _worldOf,
              ),
            );
          } finally {
            child.dispose();
          }
        }
        return out;
      }) ??
      const [];

  @override
  void setInSittingPose(bool sitting) {
    // The host does not expose `TamableAnimal.setInSittingPose`; the pose is cosmetic.
  }

  @override
  void teleportTo(Vec3 position) {
    final entity = resolve();
    if (entity == null) return;
    unawaited(
      entity
          .teleport(pos: position, worldRef: world)
          .whenComplete(entity.dispose),
    );
  }

  @override
  NbtValue? getPersistentData(String key) => _with<NbtValue?>((e) {
    final tree = e.getCustomData(namespace: 'create', key: key);
    return tree == null ? null : treeToValue(tree);
  });

  @override
  void setPersistentData(String key, NbtValue? value) => _with((e) {
    if (value == null) {
      e.removeCustomData(namespace: 'create', key: key);
    } else {
      e.setCustomData(
        namespace: 'create',
        key: key,
        value: valueToTree(value),
      );
    }
    return null;
  });

  /// No live host entity: a handle is only valid inside the callback that received it.
  @override
  Object? get hostEntity => null;

  @override
  String get worldId => world.getId();

  // -- CarriagePassenger ----------------------------------------------------------------------

  /// The host exposes no spectator query; a spectator still passes the seat checks elsewhere.
  @override
  bool get isSpectator => false;

  @override
  Vec3 get position =>
      _with((e) => e.getPosition()) ?? _lastPosition;

  /// `entity.level().dimension()`: compared with `CarriageContraptionEntity.dimension`
  /// (`TrainLevel.dimension`) when a player is carried through a portal, so it is the dimension
  /// key, not the world's folder name.
  @override
  String get dimension => world.getDimension();

  /// `passenger.saveAsPassenger(output)`. The host has no entity serialiser: players never save
  /// themselves (Java returns `null` for them too) and a mob cannot be written out, so it is left
  /// in the world instead of travelling with the carriage through a portal.
  @override
  CTag? saveAsPassenger() => null;

  @override
  void discard() {
    final entity = resolve();
    if (entity == null) return;
    try {
      entity.remove();
    } finally {
      entity.dispose();
    }
  }

  @override
  void stopRiding() {
    _with((e) {
      unawaited(e.setVehicle(vehicle: null));
      return null;
    });
    if (isPlayer) setPersistentData('ContraptionDismountLocation', null);
  }

  @override
  void teleportThroughPortal(String dimension, Vec3 location) {
    final target = _worldOf(dimension);
    final entity = resolve();
    if (target == null || entity == null) return;
    try {
      _lastPosition = location;
      unawaited(entity.teleport(pos: location, worldRef: target));
      entity.portalCooldown = 300;
    } finally {
      entity.dispose();
    }
  }
}

/// Creates carriage entities for the trains module.
final class HostCarriageEntityFactory implements CarriageEntityFactory {
  HostCarriageEntityFactory(this.host);

  final ContraptionHost host;

  @override
  CarriageContraptionEntity create(
    TrainLevel level,
    CarriageContraption contraption,
  ) {
    final data = contraption.data;
    final structure = data is HostCarriageContraptionData
        ? data.contraption
        : null;
    if (structure == null) {
      throw StateError(
        'A carriage contraption must be assembled by the contraptions module',
      );
    }
    final built = _build(level, structure, contraption, vec3Zero);
    return built;
  }

  @override
  CarriageContraptionEntity? spawnFromSaved(
    TrainLevel level,
    CTag serialisedEntity,
    Vec3? position,
  ) {
    final worldId = level.dimension;
    final world = host.worldOf(worldId);
    final contraptionLevel = host.levelOfOrNull(worldId);
    if (world == null || contraptionLevel == null) return null;
    final nbt = NbtMap.of(serialisedEntity.toNbt());
    if (!nbt.contains('Contraption')) return null;

    // `EntityType.create`: a fresh entity of the registered type, then `readAdditional` rebuilds
    // the contraption from the saved compound.
    final empty = HostCarriageContraption(Direction.north);
    final entity = _hostEntity(world, worldId, contraptionLevel);
    final hostEntity = HostCarriageEntity(
      worldEntity: entity,
      world: world,
      level: level,
      host: host,
    );
    final pure = CarriageContraptionEntity(
      hostEntity,
      level,
      position ?? vec3Zero,
      contraption: empty.train,
    );
    entity.train = pure;
    entity.setContraption(empty);
    entity.readAdditional(nbt);

    final rebuilt = entity.contraption;
    if (rebuilt is! HostCarriageContraption) return null;
    pure.contraption = rebuilt.train;

    if (position != null) entity.moveToTrain(position, entity.yaw, entity.pitch);
    host.spawn(worldId, entity);
    return pure;
  }

  /// The entity and the pure train side, wired to each other.
  CarriageContraptionEntity _build(
    TrainLevel level,
    HostCarriageContraption structure,
    CarriageContraption train,
    Vec3 position,
  ) {
    final worldId = level.dimension;
    final world = host.worldOf(worldId);
    final contraptionLevel = host.levelOfOrNull(worldId);
    if (world == null || contraptionLevel == null) {
      throw StateError('The world of carriage ${level.dimension} is not loaded');
    }
    final entity = _hostEntity(world, worldId, contraptionLevel);
    final hostEntity = HostCarriageEntity(
      worldEntity: entity,
      world: world,
      level: level,
      host: host,
    );
    final pure = CarriageContraptionEntity(
      hostEntity,
      level,
      position,
      contraption: train,
    );
    entity.train = pure;
    entity.setContraption(structure);
    // `create`: the carriage faces across its assembly direction.
    entity.configure(structure, train.assemblyDirection.clockWise);
    return pure;
  }

  HostCarriageContraptionEntity _hostEntity(
    World world,
    String worldId,
    ContraptionLevel contraptionLevel,
  ) {
    final contraptionHost = HostContraptionEntity(
      world,
      contraptionLevel as HostContraptionLevel,
      vec3Zero,
      (id) => host.entityById(worldId, id),
    );
    final entity = HostCarriageContraptionEntity(contraptionHost);
    contraptionHost.attachEntity(entity);
    return entity;
  }
}

/// Builds the contraption of a carriage for the station (`CarriageContraptionAssembly`).
final class HostCarriageContraptionAssembly
    implements CarriageContraptionAssembly {
  HostCarriageContraptionAssembly(this.host);

  final ContraptionHost host;

  @override
  CarriageContraption? assemble(
    String worldId,
    TrainLevel level,
    Pos anchor,
    Direction assemblyDirection,
  ) {
    final contraptionLevel = host.levelOfOrNull(worldId);
    if (contraptionLevel == null) return null;
    final contraption = HostCarriageContraption(assemblyDirection);
    if (!contraption.assembleSync(contraptionLevel, anchor)) return null;
    return contraption.train;
  }
}

/// `ScheduleItemEntityInteraction.interactWithConductor`'s first half: what the clicked entity
/// rides (`entity.getRootVehicle() instanceof CarriageContraptionEntity`).
///
/// The schedule area looks this up as a service (`ConductorSeatLookup`); without it a conductor
/// can neither be handed a schedule nor give one back.
final class HostConductorSeatLookup implements ConductorSeatLookup {
  HostConductorSeatLookup(this.host);

  final ContraptionHost host;

  @override
  ScheduleCarriagePassenger? passengerOf(String worldId, int entityId) {
    final world = host.worldOf(worldId);
    if (world == null) return null;
    final handle = world.getEntityById(id: entityId);
    if (handle == null) return null;
    final bool living;
    final String uuid;
    try {
      living = handle.isLiving();
      uuid = handle.getUuid().toString();
    } finally {
      handle.dispose();
    }

    final rootId = _rootVehicleId(world, entityId);
    if (rootId == null) return null;
    final root = host.entityById(worldId, rootId);
    if (root is! HostCarriageContraptionEntity) return null;
    final train = root.train;
    if (train == null) return null;
    final contraption = train.contraption;
    if (contraption == null) return null;

    final seatPos = contraption.data.getSeatOf(uuid);
    return ScheduleCarriagePassenger(
      train: train.getCarriage()?.train,
      seated: seatPos != null,
      conductorSeat:
          seatPos != null && contraption.conductorSeats[seatPos] != null,
      isCarriageContraption: true,
      living: living,
    );
  }

  /// `entity.getRootVehicle().getId()`: the vehicle of the vehicle of ... until one has none.
  int? _rootVehicleId(World world, int entityId) {
    Entity? current = world.getEntityById(id: entityId);
    if (current == null) return null;
    try {
      while (true) {
        final vehicle = current!.getVehicle();
        if (vehicle == null) return current.getId();
        current.dispose();
        current = vehicle;
      }
    } finally {
      current?.dispose();
    }
  }
}
