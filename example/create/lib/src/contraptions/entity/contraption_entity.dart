// `AbstractContraptionEntity` (pure logic): the entity that carries a contraption. It drives the
// actors of the structure, seats passengers, handles interaction and stalls, and places the blocks
// back into the world on disassembly. The entity itself (a host plugin entity) is reached through
// [ContraptionEntityHost]; the subclasses decide how the structure moves and rotates
// (`ControlledContraptionEntity`, `OrientedContraptionEntity`).
import 'dart:async';
import 'dart:math' as math;

import '../../api/block_state.dart';
import '../../common/common.dart';
import '../../core/nbt.dart' show NbtValue;
import '../core/collision.dart' show Matrix3d;
import '../core/contraption.dart';
import '../core/level.dart';
import '../core/movement.dart';
import '../core/nbt_map.dart';
import '../core/structure_info.dart';
import '../core/structure_transform.dart';
import '../storage/storage_manager.dart';

/// A passenger of a contraption (`Entity` of the host), as the entity logic sees it.
abstract interface class ContraptionPassengerRef
    implements ContraptionPassenger {
  @override
  String get uuid;
  int get entityId;
  bool get isPlayer;
  bool get isTamableAnimal;
  bool get isPassenger;
  double get vehicleAttachmentPointY;

  /// The Dart contraption entity behind this passenger, `null` for a plain entity.
  Object? get contraptionEntity;

  /// The vehicle of this passenger, `null` when it is not riding one.
  ContraptionPassengerRef? get vehicle;

  void setInSittingPose(bool sitting);
  void teleportTo(Vec3 position);

  /// `passenger.getPersistentData()`.
  NbtValue? getPersistentData(String key);
  void setPersistentData(String key, NbtValue? value);

  /// The id of the world the passenger is in.
  String get worldId;

  /// The host entity behind this passenger, when the ref holds a live handle (only inside the
  /// callback that received it). Prefer [worldId] and [entityId].
  Object? get hostEntity;
}

/// An entity near a contraption, as the collision code sees it.
abstract interface class ContraptionCollisionEntity implements CollidingEntity {
  int get entityId;

  @override
  int get id => entityId;

  @override
  String get uuid;

  @override
  String get typeKey;

  @override
  bool get isLiving;

  @override
  Object get hostEntity;
  bool get isAlive;
  bool get isPlayer;
  bool get isSpectator;
  bool get isItemEntity;
  bool get isMinecart;
  bool get isHangingEntity;
  bool get isSeatEntity;
  bool get isProjectile;
  bool get noPhysics;
  bool get isPassenger;
  bool get isSuppressingBounce;
  bool get onGround;
  double get maxUpStep;
  Vec3 get position;
  Aabb get boundingBox;
  Vec3 get deltaMovement;
  void setDeltaMovement(Vec3 motion);
  void setPosition(Vec3 position);

  /// `Entity#collide`: the part of [movement] the world lets the entity travel, so a pushed
  /// entity stops at a wall instead of being placed inside it. The fallback lets it through.
  Vec3 collideMovement(Vec3 movement) => movement;

  void teleport(Vec3 position);
  void setOnGround(bool onGround);
  void setFallDistance(double distance);
  void setVelocitySync();
  void setAboveGroundTickCountZero();
  void playSoundAt(String sound, {double volume = 1, double pitch = 1});
  void damageRunOver(double amount);
  List<ContraptionCollisionEntity> get selfAndPassengers;

  /// The Dart contraption entity behind this entity, `null` for a plain entity.
  AbstractContraptionEntity? get contraptionEntity;

  /// `getPersistentData().contains/remove("ContraptionGrounded")`.
  bool get contraptionGrounded;
  void clearContraptionGrounded();
}

/// The host entity of a contraption, with the level operations the entity logic needs.
abstract interface class ContraptionEntityHost {
  int get entityId;
  String get uuid;
  bool get isAlive;
  bool get isRemoved;
  bool get stalled;
  Vec3 get position;
  Vec3 get prevPosition;
  Aabb get boundingBox;
  void setBoundingBox(Aabb box);
  Vec3 get deltaMovement;
  void setDeltaMovement(Vec3 motion);
  void setPosition(Vec3 position);
  void teleport(Vec3 position);
  List<ContraptionPassengerRef> get passengers;
  bool hasPassenger(ContraptionPassengerRef passenger);
  void addPassenger(ContraptionPassengerRef passenger, {bool force = true});
  void removePassenger(ContraptionPassengerRef passenger);
  void ejectPassengers();
  void setPassengerPosition(ContraptionPassengerRef passenger, Vec3 position);
  void teleportEntity(ContraptionPassengerRef passenger, Vec3 position);
  Object? get vehicle;

  /// The vehicle as a passenger reference, `null` without one.
  ContraptionPassengerRef? get vehiclePassenger;

  Vec3 get vehiclePosition;
  Vec3 get vehiclePrevPosition;
  Vec3 get vehicleDeltaMovement;
  bool get vehicleIsMinecart;
  void setVehicleDeltaMovement(Vec3 motion);

  /// The `IControlContraption` block entity at [pos], `null` for anything else.
  Object? controllerAt(Pos pos);
  void setRotation(double yaw, double pitch);
  void setOnGround(bool onGround);
  double get maxUpStep;
  void playSound(String sound, Vec3 at, {double volume = 1, double pitch = 1});
  void sendPayload(String channel, Map<String, Object?> fields);
  void setStalled(bool stalled);
  String? get controllingPlayer;
  void setControllingPlayer(String? uuid);
  NbtValue? getPersistentData(String key);
  void setPersistentData(String key, NbtValue? value);
  ContraptionLevel get level;

  /// `world.getEntity(id)` as a collision entity.
  ContraptionCollisionEntity? collisionEntityById(int id);

  /// `ContraptionBlockChangedPacket`.
  void sendBlockChanged(Pos localPos, BState state);

  /// `MountedStorageSyncPacket`.
  void sendStorageSync(StorageSync sync);

  /// `ContraptionSeatMappingPacket`.
  void sendSeatMapping(Map<String, int> mapping, {int? dismountedId});

  /// `ContraptionStallPacket`.
  void sendStall(double angle);

  /// `ControlsStopControllingPacket` to the player that was driving the contraption.
  void sendControlsAbort(String playerUuid);

  /// `ContraptionDisassemblyPacket`.
  void sendDisassembly(StructureTransform transform);

  /// The entities in [box] that a contraption can collide with.
  List<ContraptionCollisionEntity> entitiesNear(Aabb box);

  /// Wraps a host entity as a passenger, `null` when it is not one.
  ContraptionPassengerRef? passengerFromHost(Object handle);

  /// `entity.discard()`.
  void remove();
}

/// `AbstractContraptionEntity.ContraptionRotationState`.
class ContraptionRotationState {
  double xRotation = 0;
  double yRotation = 0;
  double zRotation = 0;
  double secondYRotation = 0;

  Matrix3d? _matrix;

  static final ContraptionRotationState none = ContraptionRotationState();

  /// `asMatrix()`.
  Matrix3d asMatrix() {
    final cached = _matrix;
    if (cached != null) return cached;
    final matrix = Matrix3d.identity();
    if (xRotation != 0)
      matrix.multiply(Matrix3d()..asXRotation(_rad(-xRotation)));
    if (yRotation != 0)
      matrix.multiply(Matrix3d()..asYRotation(_rad(-yRotation)));
    if (zRotation != 0)
      matrix.multiply(Matrix3d()..asZRotation(_rad(-zRotation)));
    _matrix = matrix;
    return matrix;
  }

  bool get hasVerticalRotation => xRotation != 0 || zRotation != 0;

  double get yawOffset => secondYRotation;

  static double _rad(double degrees) => degrees * math.pi / 180;
}

/// Hooks the storage / actor modules install.
abstract final class ContraptionEntityHooks {
  /// `MountedStorageManager.handlePlayerStorageInteraction(contraption, player, localPos)`; the
  /// host opens the menu (`MountedItemStorage.handleInteraction`) and reports whether it did.
  static Future<bool> Function(
    Contraption contraption,
    InteractingPlayer player,
    Pos localPos,
  )?
  openStorage;

  /// `SeatBlock.getLeashed(level, player)` (a leashed mob follows its owner onto a seat).
  static ContraptionPassengerRef? Function(
    ContraptionLevel level,
    InteractingPlayer player,
  )?
  leashedMob;
}

/// `AbstractContraptionEntity`.
abstract class AbstractContraptionEntity implements ContraptionEntityHandle {
  final ContraptionEntityHost host;

  Contraption? _contraption;

  bool initialized = false;
  bool prevPosInvalid = true;
  bool skipActorStop = false;

  /// Ticks a removed contraption still shows its blocks (the client rebuild window).
  int staleTicks = 3;

  /// The colliding entities and how many ticks ago they last touched the contraption.
  final Map<int, int> collidingEntities = {};

  Vec3 _prevPosition;

  AbstractContraptionEntity(this.host) : _prevPosition = host.position;

  Contraption? get contraption => _contraption;

  /// `setContraption`.
  void setContraption(Contraption? contraption) {
    _contraption = contraption;
    if (contraption == null) return;
    contraption.onEntityCreated(this);
  }

  /// `supportsTerrainCollision`.
  bool get supportsTerrainCollision =>
      contraption is TranslatingContraptionLike && !isElevatorContraption;

  /// Whether the contraption is an elevator (no terrain collision for the collider).
  bool get isElevatorContraption => false;

  /// `collisionEnabled`.
  bool get collisionEnabled => true;

  /// `contraptionInitialize`.
  void contraptionInitialize() {
    final c = contraption;
    if (c == null) return;
    c.onEntityInitialize(host.level, this);
    initialized = true;
  }

  /// `registerColliding(entity)`.
  void registerColliding(ContraptionCollisionEntity entity) {
    collidingEntities[entity.entityId] = 0;
  }

  // -- ContraptionEntityHandle ---------------------------------------------------------------

  @override
  int get entityId => host.entityId;

  @override
  String get uuid => host.uuid;

  @override
  bool get isAlive => host.isAlive;

  @override
  Aabb get boundingBox => host.boundingBox;

  @override
  Vec3 get position => host.position;

  @override
  List<Object> get passengers => host.passengers;

  @override
  void setBlock(Pos localPos, StructureBlockInfo newInfo) {
    final c = contraption;
    if (c == null) return;
    c.blocks[localPos] = newInfo;
    host.sendBlockChanged(localPos, newInfo.state);
  }

  @override
  void sendStorageSync(StorageSync sync) => host.sendStorageSync(sync);

  @override
  void onContraptionStalled() => host.sendStall(getStalledAngle());

  // -- Passengers -----------------------------------------------------------------------------

  /// `addSittingPassenger(passenger, seatIndex)`.
  @override
  void addSittingPassenger(Object passenger, int seatIndex) {
    final c = contraption;
    if (c == null) return;
    final ref = passenger is ContraptionPassengerRef
        ? passenger
        : host.passengerFromHost(passenger);
    if (ref == null) return;
    final seats = c.getSeats();
    if (seatIndex < 0 || seatIndex >= seats.length) return;
    final seatPos = seats[seatIndex];

    for (final entity in host.passengers) {
      final seatOf = c.getSeatOf(entity.uuid);
      if (seatOf != null && seatOf == seatPos) {
        if (entity.isPlayer) return;
        if (!ref.isPlayer) return;
        host.removePassenger(entity);
      }
    }

    host.addPassenger(ref, force: true);
    if (ref.isTamableAnimal) ref.setInSittingPose(true);
    c.getSeatMapping()[ref.uuid] = seatIndex;

    host.sendSeatMapping(c.getSeatMapping());
  }

  /// `removePassenger(passenger)`.
  void removePassenger(ContraptionPassengerRef passenger) {
    final transformed = getPassengerPosition(passenger, 1);
    final c = contraption;
    host.removePassenger(passenger);
    if (c == null) return;
    if (passenger.isTamableAnimal) passenger.setInSittingPose(false);
    if (transformed != null) {
      passenger.setPersistentData(
        'ContraptionDismountLocation',
        writeVec(transformed),
      );
    }
    c.getSeatMapping().remove(passenger.uuid);
    host.sendSeatMapping(c.getSeatMapping(), dismountedId: passenger.entityId);
  }

  /// `positionRider(passenger, callback)`.
  void positionRider(ContraptionPassengerRef passenger) {
    if (!host.hasPassenger(passenger)) return;
    final transformed = getPassengerPosition(passenger, 1);
    if (transformed == null) return;
    final offset = passenger.contraptionEntity != null ? 0.0 : -1 / 8.0;
    host.setPassengerPosition(passenger, transformed + (0, offset, 0));
  }

  /// `getPassengerPosition(passenger, partialTicks)`.
  Vec3? getPassengerPosition(Object passenger, double partialTicks) {
    final c = contraption;
    if (c == null) return null;

    final uuid = passenger is ContraptionPassengerRef
        ? passenger.uuid
        : (passenger is AbstractContraptionEntity ? passenger.uuid : null);
    if (uuid == null) return null;

    if (passenger is ContraptionPassengerRef &&
        passenger.contraptionEntity is AbstractContraptionEntity) {
      final localPos = c.getBearingPosOf(uuid);
      if (localPos != null) {
        return toGlobalVector(VecHelper.getCenterOf(localPos), partialTicks) +
            VecHelper.centerOfOrigin -
            (0.5, 1.0, 0.5);
      }
    }

    final seat = c.getSeatOf(uuid);
    if (seat == null) return null;
    final ySize = host.boundingBox.ySize;
    final attachment = passenger is ContraptionPassengerRef
        ? passenger.vehicleAttachmentPointY
        : 0.0;
    final transformed = toGlobalVector(
      seat.toVec3() + (0.5, -attachment + ySize + 0.125, 0.5),
      partialTicks,
    );
    return transformed + VecHelper.centerOfOrigin - (0.5, ySize, 0.5);
  }

  /// `canAddPassenger(passenger)`.
  bool canAddPassenger(ContraptionPassengerRef passenger) {
    if (passenger.contraptionEntity != null) return true;
    final c = contraption;
    if (c == null) return false;
    return c.getSeatMapping().length < c.getSeats().length;
  }

  /// `getControllingPlayer()`.
  String? get controllingPlayer => host.controllingPlayer;

  /// `setControllingPlayer`.
  void setControllingPlayer(String? uuid) => host.setControllingPlayer(uuid);

  /// `startControlling`.
  bool startControlling(Pos controlsLocalPos, InteractingPlayer player) =>
      false;

  /// `control`.
  bool control(
    Pos controlsLocalPos,
    List<int> heldControls,
    InteractingPlayer player,
  ) => true;

  /// `stopControlling`.
  void stopControlling(Pos controlsLocalPos) {
    final controlling = host.controllingPlayer;
    if (controlling != null) host.sendControlsAbort(controlling);
    host.setControllingPlayer(null);
  }

  @override
  void sendPayload(String channel, Map<String, Object?> fields) =>
      host.sendPayload(channel, fields);

  // -- Interaction ----------------------------------------------------------------------------

  /// `handlePlayerInteraction(player, localPos, side, hand)`: true when the click was handled.
  Future<bool> handlePlayerInteraction(
    InteractingPlayer player,
    Pos localPos,
    Direction side,
    bool mainHand,
  ) async {
    final c = contraption;
    if (c == null) return false;
    final indexOfSeat = c.getSeats().indexOf(localPos);

    if (indexOfSeat == -1 || player.holdsWrench) {
      final interactor = c.getInteractors()[localPos];
      if (interactor != null) {
        final result = await interactor.handlePlayerInteraction(
          player,
          localPos,
          c,
        );
        return result;
      }
      final open = ContraptionEntityHooks.openStorage;
      return open != null && await open(c, player, localPos);
    }

    if (player.isPassenger) return false;

    // Eject a potential existing passenger.
    ContraptionPassengerRef? toDismount;
    for (final entry in c.getSeatMapping().entries) {
      if (entry.value != indexOfSeat) continue;
      for (final entity in host.passengers) {
        if (entry.key != entity.uuid) continue;
        if (entity.isPlayer) return false;
        toDismount = entity;
      }
    }

    if (toDismount != null) {
      final transformed = getPassengerPosition(toDismount, 1);
      host.removePassenger(toDismount);
      if (transformed != null) host.teleportEntity(toDismount, transformed);
    }

    final leashed = ContraptionEntityHooks.leashedMob?.call(host.level, player);
    final rider =
        leashed ??
        (player.hostPlayer is ContraptionPassengerRef
            ? player.hostPlayer as ContraptionPassengerRef
            : null);
    if (rider != null) addSittingPassenger(rider, indexOfSeat);
    return true;
  }

  /// `canInteractWithBlock(player, localPos, distance)`.
  bool canInteractWithBlock(
    InteractingPlayer player,
    Vec3 localPos,
    double distance,
  ) {
    final pos = posContaining(toGlobalVector(localPos, 0));
    return player.canInteractWith(pos, distance);
  }

  // -- Transforms -----------------------------------------------------------------------------

  /// `toGlobalVector(localVec, partialTicks)`.
  Vec3 toGlobalVector(
    Vec3 localVec,
    double partialTicks, {
    bool prevAnchor = false,
  }) {
    final anchor = prevAnchor ? getPrevAnchorVec() : getAnchorVec();
    final rotationOffset = VecHelper.centerOfOrigin;
    var vec = localVec - rotationOffset;
    vec = applyRotation(vec, partialTicks);
    return vec + rotationOffset + anchor;
  }

  /// `toLocalVector(globalVec, partialTicks)`.
  Vec3 toLocalVector(
    Vec3 globalVec,
    double partialTicks, {
    bool prevAnchor = false,
  }) {
    final anchor = prevAnchor ? getPrevAnchorVec() : getAnchorVec();
    final rotationOffset = VecHelper.centerOfOrigin;
    var vec = globalVec - anchor - rotationOffset;
    vec = reverseRotation(vec, partialTicks);
    return vec + rotationOffset;
  }

  /// `applyRotation(localPos, partialTicks)`.
  Vec3 applyRotation(Vec3 localPos, double partialTicks);

  /// `reverseRotation(localPos, partialTicks)`.
  Vec3 reverseRotation(Vec3 localPos, double partialTicks);

  /// `getAnchorVec()`.
  Vec3 getAnchorVec() => host.position;

  /// `getPrevAnchorVec()`.
  Vec3 getPrevAnchorVec() => prevPosInvalid ? host.position : _prevPosition;

  /// `getYawOffset()`.
  double get yawOffset => 0;

  /// `getContactPointMotion(globalContactPoint)`.
  Vec3 getContactPointMotion(Vec3 globalContactPoint) {
    if (prevPosInvalid) return vec3Zero;
    final contactPoint = toGlobalVector(
      toLocalVector(globalContactPoint, 0, prevAnchor: true),
      1,
      prevAnchor: true,
    );
    final contraptionLocalMovement = contactPoint - globalContactPoint;
    final contraptionAnchorMovement = host.position - getPrevAnchorVec();
    return contraptionLocalMovement + contraptionAnchorMovement;
  }

  /// `setPos(x, y, z)`.
  void setPos(Vec3 pos) {
    host.setPosition(pos);
    final box = contraption?.bounds;
    if (box == null) return;
    host.setBoundingBox(box.moveBy(getAnchorVec()));
  }

  /// `yawFromVector`.
  static double yawFromVector(Vec3 vec) =>
      (3 * math.pi / 2 + math.atan2(vec.$3, vec.$1)) / math.pi * 180;

  /// `pitchFromVector`.
  static double pitchFromVector(Vec3 vec) =>
      math.acos(vec.$2.clamp(-1.0, 1.0)) / math.pi * 180;

  // -- Ticking --------------------------------------------------------------------------------

  /// `tick()`.
  Future<void> tick() async {
    final c = contraption;
    if (c == null) {
      host.remove();
      return;
    }

    collidingEntities.removeWhere((id, ticks) => ticks + 1 > 3);
    for (final key in collidingEntities.keys.toList()) {
      collidingEntities[key] = collidingEntities[key]! + 1;
    }

    _prevPosition = host.position;
    prevPosInvalid = false;

    if (!initialized) contraptionInitialize();

    c.tickStorage(this);
    await tickContraption();

    for (final passenger in host.passengers) {
      if (passenger.isPlayer) continue;
      positionRider(passenger);
    }
  }

  /// `tickContraption()`.
  Future<void> tickContraption();

  /// `tickActors()`.
  Future<void> tickActors() async {
    final c = contraption;
    if (c == null) return;
    final stalledPreviously = c.stalled;
    c.stalled = false;

    skipActorStop = true;
    for (final context in c.getActors()) {
      final info = c.blocks[context.localPos];
      if (info == null) continue;
      final actor = MovementBehaviours.of(info.state, host.level);
      if (actor == null) continue;

      final oldMotion = context.motion;
      final actorPosition = toGlobalVector(
        VecHelper.getCenterOf(info.pos) + actor.getActiveAreaOffset(context),
        1,
      );
      final gridPosition = posContaining(actorPosition);
      final newPosVisited =
          !context.stall &&
          shouldActorTrigger(context, info, actor, actorPosition, gridPosition);

      context.rotation = (v) => applyRotation(v, 1);
      context.position = actorPosition;
      if (!isActorActive(context, actor) && !actor.mustTickWhileDisabled())
        continue;

      if (newPosVisited && !context.stall) {
        await actor.visitNewPosition(context, gridPosition);
        if (!host.isAlive) break;
        context.firstMovement = false;
      }
      if (oldMotion != context.motion) {
        await actor.onSpeedChanged(context, oldMotion, context.motion);
        if (!host.isAlive) break;
      }
      await actor.tick(context);
      if (!host.isAlive) break;
      c.stalled |= context.stall;
    }

    if (!host.isAlive) {
      c.stopMoving();
      return;
    }
    skipActorStop = false;

    for (final passenger in host.passengers) {
      if (!c.stabilizedSubContraptions.containsKey(passenger.uuid)) continue;
      final sub = passenger.contraptionEntity;
      if (sub is AbstractContraptionEntity &&
          sub.contraption?.stalled == true) {
        c.stalled = true;
        break;
      }
    }

    if (!stalledPreviously && c.stalled) onContraptionStalled();
    host.setStalled(c.stalled);
  }

  /// `refreshPSIs()`.
  Future<void> refreshPSIs() async {
    final c = contraption;
    if (c == null) return;
    for (final context in c.getActors()) {
      final info = c.blocks[context.localPos];
      if (info == null) continue;
      final actor = MovementBehaviours.of(info.state, host.level);
      if (actor == null || !isActorActive(context, actor)) continue;
      final position = context.position;
      if (position != null) await actor.refreshAtNewPosition(context);
    }
  }

  /// `isActorActive`.
  bool isActorActive(MovementContext context, MovementBehaviour actor) =>
      actor.isActive(context);

  /// `shouldActorTrigger`.
  bool shouldActorTrigger(
    MovementContext context,
    StructureBlockInfo blockInfo,
    MovementBehaviour actor,
    Vec3 actorPosition,
    Pos gridPosition,
  ) {
    final previousPosition = context.position;
    if (previousPosition == null) return false;

    context.motion = actorPosition - previousPosition;
    final speedOverride = actorMotionSpeedOverride;
    if (speedOverride != null && context.motion != vec3Zero) {
      context.motion = context.motion.normalized * speedOverride.abs();
    }

    context.relativeMotion = reverseRotation(context.motion, 1);

    final ignoreMotionForFirstMovement = actor.ignoresMotionForFirstMovement;
    return posContaining(previousPosition) != gridPosition ||
        ((context.relativeMotion.length > 0 || ignoreMotionForFirstMovement) &&
            context.firstMovement);
  }

  /// The speed the train carriage replaces the actor motion with (`train.speedBeforeStall`).
  double? get actorMotionSpeedOverride => null;

  /// `move(x, y, z)`.
  void move(Vec3 delta) => setPos(host.position + delta);

  /// `getPrevPositionVec()`.
  Vec3 getPrevPositionVec() => prevPosInvalid ? host.position : _prevPosition;

  /// `getRotationState()`.
  ContraptionRotationState getRotationState();

  /// `isStalled()`.
  bool get isStalled => host.stalled;

  // -- Persistence ----------------------------------------------------------------------------

  /// `writeAdditional(compound, registries, spawnPacket)`.
  void writeAdditional(NbtMap compound, {bool spawnPacket = false}) {
    final c = contraption;
    if (c != null)
      compound.putCompound('Contraption', c.writeNbt(spawnPacket: spawnPacket));
    compound.putBool('Stalled', isStalled);
    compound.putBool('Initialized', initialized);
  }

  /// `readAdditional(compound, spawnData)`.
  void readAdditional(NbtMap compound, {bool spawnData = false}) {
    if (compound.isEmpty) return;
    initialized = compound.getBool('Initialized');
    final c = Contraption.fromNbt(
      host.level,
      compound.getCompound('Contraption'),
      spawnData: spawnData,
    );
    _contraption = c;
    c.entity = this;
    host.setStalled(compound.getBool('Stalled'));
  }

  // -- Disassembly ----------------------------------------------------------------------------

  /// `disassemble()`.
  Future<void> disassemble() async {
    final c = contraption;
    if (!host.isAlive || c == null) return;

    final transform = makeStructureTransform();

    c.stopMoving();
    host.sendDisassembly(transform);

    await c.addBlocksToWorld(host.level, transform);
    await c.addPassengersToWorld(host.level, transform, host.passengers);

    for (final passenger in host.passengers) {
      final sub = passenger.contraptionEntity;
      if (sub is! AbstractContraptionEntity) continue;
      final face = c.stabilizedSubContraptions[passenger.uuid];
      if (face == null) continue;
      final transformed = transform.applyPos(face.connectedPos);
      sub.setPos(transformed.toVec3());
      await sub.disassemble();
    }

    skipActorStop = true;
    // `ejectPassengers()` goes through `removePassenger` in Java, which tells the clients about
    // every seat that is freed.
    for (final passenger in host.passengers.toList()) {
      removePassenger(passenger);
    }
    host.remove();
    host.ejectPassengers();
    moveCollidedEntitiesOnDisassembly(transform);
    host.playSound('create:contraption_disassemble', host.position);
  }

  void moveCollidedEntitiesOnDisassembly(StructureTransform transform) {
    for (final id in collidingEntities.keys.toList()) {
      final entity = host.collisionEntityById(id);
      if (entity == null) continue;
      final localVec = toLocalVector(entity.position, 0);
      final transformed = transform.applyVec(localVec);
      entity.teleport(transformed + (0, 1 / 16, 0));
    }
  }

  /// `remove()`: stops the actors unless the entity is being disassembled.
  void remove() {
    final c = contraption;
    if (!host.isRemoved && c != null && !skipActorStop) c.stopMoving();
    host.remove();
  }

  /// `makeStructureTransform()`.
  StructureTransform makeStructureTransform();

  /// `getStalledAngle()`.
  double getStalledAngle();

  /// `handleStallInformation(x, y, z, angle)`.
  void handleStallInformation(double x, double y, double z, double angle);

  /// `isReadyForRender`.
  bool get isReadyForRender => initialized;

  /// `isAliveOrStale`.
  bool get isAliveOrStale => host.isAlive;

  /// `isPrevPosInvalid`.
  bool get isPrevPosInvalid => prevPosInvalid;

  /// `canCollideWith(entity)`.
  bool canCollideWith(ContraptionCollisionEntity e) {
    if (e.isSpectator) return false;
    if (e.noPhysics) return false;
    if (e.isHangingEntity) return false;
    if (e.isMinecart) return !isMountedContraption;
    if (e.isSeatEntity || e.isProjectile) return false;
    if (e.isPassenger) return false;
    return true;
  }

  /// `hasExactlyOnePlayerPassenger()` is always false for contraptions.
  bool get hasExactlyOnePlayerPassenger => false;

  /// Whether the contraption is a mounted (minecart) contraption (`MountedContraption`).
  bool get isMountedContraption => contraption is MountedContraptionLike;
}

/// Marker for the mounted contraption kind (the mounted module's contraption implements it).
abstract interface class MountedContraptionLike {}

/// Marker for the translating contraption kind (pistons, elevators, gantries).
abstract interface class TranslatingContraptionLike {}
