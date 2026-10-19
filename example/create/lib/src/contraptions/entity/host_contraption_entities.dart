// The host side of contraptions: a `ContraptionLevel` over a `World`, the host entity of a
// contraption (a plugin entity), the factory the actuators use and the tick of the live entities.
//
// The pure structure and entity logic lives in `core/` and `entity/`; this is the only file that
// touches `package:pumpkin_api`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter, stateIdOf;
import '../../api/payloads.dart' show PayloadBus;
import '../../common/binary_nbt.dart';
import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../../common/nbt_convert.dart';
import '../../core/block_entity.dart';
import '../../core/nbt.dart';
import '../../core/worlds.dart';
import '../core/contraption.dart';
import '../core/contraption_type.dart';
import '../core/level.dart';
import '../core/nbt_map.dart';
import '../core/structure_info.dart';
import '../core/structure_transform.dart';
import '../bearing/bearing_contraptions.dart' show StabilizedContraption;
import '../blocks/actuator_contract.dart';
import '../entity/contraption_entity.dart';
import '../entity/contraption_handler.dart';
import '../entity/controlled_contraption_entity.dart';
import '../entity/i_control_contraption.dart';
import '../entity/oriented_contraption_entity.dart';
import '../gantry/gantry_contraption_entity.dart';
import '../storage/storage_manager.dart';

/// Hooks the actuator, glue, seat and minecart modules install on the host adapter.
abstract final class ContraptionHostHooks {
  /// `isActuatorRunning(pos)` of the block entity at [pos] (a bearing, clockwork bearing, pulley).
  static bool Function(String worldId, Pos pos)? isActuatorRunning;

  /// `WindmillBearingBlockEntity.disassembleForMovement()`.
  static void Function(String worldId, Pos pos)? disassembleWindmillBearing;

  /// `ChainConveyorBlockEntity.notifyConnectedToValidate()`.
  static void Function(String worldId, Pos pos)? notifyChainConveyor;

  /// `SeatBlock.sitDown(world, pos, passenger)`.
  static bool Function(String worldId, Pos pos, Entity passenger)? sitPassenger;

  /// The entity type key of a contraption (`create:gantry_contraption` for a gantry).
  static String Function(AbstractContraptionEntity entity)? entityTypeOf;

  /// Called after a contraption entity was spawned.
  static void Function(AbstractContraptionEntity entity)? spawned;
}

/// A [ContraptionLevel] over a host [World].
final class HostContraptionLevel extends ContraptionLevel {
  final World world;
  final BlockEntityStore blockEntities;
  final HostBlockGetter _getter;

  @override
  final ContraptionSettings settings;

  HostContraptionLevel(this.world, this.blockEntities, this.settings)
    : _getter = HostBlockGetter(world);

  @override
  String get worldId => world.getId();

  @override
  BState stateAt(Pos p) => _getter.stateAt(p);

  @override
  bool isLoaded(Pos p) => _getter.isLoaded(p);

  @override
  bool isFaceSturdy(Pos p, Direction face) => _getter.isFaceSturdy(p, face);

  @override
  List<BlockBox> collisionBoxes(Pos p) => _getter.collisionBoxes(p);

  @override
  bool supportShapeEmpty(Pos p) => _getter.supportShapeEmpty(p);

  @override
  bool canBeReplaced(Pos p) => _getter.canBeReplaced(p);

  @override
  bool hasTag(Pos p, String tag) => _getter.hasTag(p, tag);

  @override
  bool isWater(Pos p) => _getter.isWater(p);

  @override
  bool isOutsideBuildHeight(Pos p) =>
      p.$2 < world.getMinY() || p.$2 >= world.getMinY() + 384;

  @override
  int get minY => world.getMinY();

  @override
  CapturedBlockEntity? blockEntityAt(Pos p) {
    // Plugin block entities keep their data in the Dart store, not in the host NBT.
    final plugin = blockEntities.at(worldId, p.toBlockPos());
    if (plugin != null && !plugin.removed) {
      final saved = NbtCompound()..putString('id', plugin.typeKey);
      plugin.write(saved, clientPacket: false);
      final client = NbtCompound()..putString('id', plugin.typeKey);
      plugin.write(client, clientPacket: true);
      return CapturedBlockEntity(
        plugin.typeKey,
        NbtMap.of(valueOfCompound(saved)),
        NbtMap.of(valueOfCompound(client)),
      );
    }

    final bytes = world.getBlockEntityNbt(pos: p.toBlockPos());
    if (bytes == null || bytes.isEmpty) return null;
    final parsed = BinaryNbt.read(bytes);
    if (parsed == null || parsed.root.kind != NbtKind.compound) return null;
    final saved = NbtMap.of(parsed.root).copy();
    final typeKey = saved.getString('id');
    if (typeKey.isEmpty) return null;
    // The host does not expose `getUpdateTag`; the full saved data is the closest equivalent.
    return CapturedBlockEntity(typeKey, saved, saved.copy());
  }

  @override
  PushReaction pushReaction(BState state) {
    final st = _stateOf(state);
    if (st == null) return PushReaction.normal;
    return switch (st.pistonBehavior) {
      WorldPistonBehavior.normal => PushReaction.normal,
      WorldPistonBehavior.destroy => PushReaction.destroy,
      WorldPistonBehavior.block => PushReaction.block,
      WorldPistonBehavior.ignore => PushReaction.ignore,
      WorldPistonBehavior.pushOnly => PushReaction.pushOnly,
    };
  }

  @override
  bool isUnbreakable(BState state) => (_stateOf(state)?.hardness ?? 0) == -1;

  @override
  bool stateHasTag(BState state, String tag) {
    final id = stateIdOf(state);
    return id != null && BlockStates.isTag(id, tag);
  }

  @override
  bool stateCollisionEmpty(BState state) =>
      (_stateOf(state)?.collisionShapes ?? const []).isEmpty;

  @override
  bool stateReplaceable(BState state) => _stateOf(state)?.replaceable ?? false;

  @override
  List<BlockBox> stateCollisionBoxes(BState state) {
    final st = _stateOf(state);
    if (st == null) return const [];
    return [
      for (final b in st.collisionShapes)
        BlockBox(b.min.$1, b.min.$2, b.min.$3, b.max.$1, b.max.$2, b.max.$3),
    ];
  }

  @override
  double stateFriction(BState state) => 0.6;

  BlockState? _stateOf(BState state) {
    final id = stateIdOf(state);
    return id == null ? null : BlockRegistry.stateFromId(id);
  }

  // -- Glue, seats and minecarts ---------------------------------------------------------------

  @override
  List<GlueRef> gluesIn(Aabb area) {
    final refs = <GlueRef>[];
    for (final snapshot in _snapshots(area)) {
      final entity = world.getEntityById(id: snapshot.id);
      if (entity == null) continue;
      if (entity.getPluginTypeKey() != 'create:super_glue') continue;
      final bb = entity.getBoundingBox();
      refs.add(
        GlueRef(
          snapshot.id,
          Aabb(
            bb.min.$1,
            bb.min.$2,
            bb.min.$3,
            bb.max.$1,
            bb.max.$2,
            bb.max.$3,
          ),
        ),
      );
    }
    return refs;
  }

  @override
  void discardGlue(GlueRef glue) {
    final entity = world.getEntityById(id: glue.id);
    if (entity == null) return;
    entity.remove();
  }

  @override
  Object? seatPassengerAt(Pos pos) {
    final area = Aabb.ofBlock(pos);
    for (final snapshot in _snapshots(area)) {
      final entity = world.getEntityById(id: snapshot.id);
      if (entity == null) continue;
      if (entity.getPluginTypeKey() != 'create:seat') continue;
      final passengers = entity.getPassengers();
      if (passengers.isEmpty) return null;
      return passengers.first;
    }
    return null;
  }

  @override
  List<MinecartRef> minecartsAt(Pos pos) {
    final refs = <MinecartRef>[];
    final area = Aabb.ofBlock(pos);
    for (final snapshot in _snapshots(area)) {
      final entity = world.getEntityById(id: snapshot.id);
      if (entity == null) continue;
      final type = _entityTypeName(entity);
      if (!_isMinecartType(type)) continue;
      final p = entity.position;
      refs.add(
        MinecartRef(
          snapshot.id,
          entity.getUuid().toString(),
          type,
          type == 'minecraft:minecart' ||
              type == 'minecraft:chest_minecart' ||
              type == 'minecraft:furnace_minecart',
          p,
        ),
      );
    }
    return refs;
  }

  @override
  void moveMinecart(MinecartRef cart, Vec3 position) {
    final entity = world.getEntityById(id: cart.id);
    if (entity == null) return;
    unawaited(entity.teleport(pos: position, worldRef: world));
  }

  @override
  void scheduleBlockTick(Pos pos, String blockKey) {
    world.scheduleBlockTick(
      pos: pos.toBlockPos(),
      delayTicks: 1,
      priority: TickPriority.normal,
    );
  }

  @override
  void disassembleWindmillBearing(Pos pos) =>
      ContraptionHostHooks.disassembleWindmillBearing?.call(world.getId(), pos);

  @override
  void notifyChainConveyor(Pos pos) =>
      ContraptionHostHooks.notifyChainConveyor?.call(world.getId(), pos);

  @override
  bool isActuatorRunning(Pos pos) =>
      ContraptionHostHooks.isActuatorRunning?.call(world.getId(), pos) ?? false;

  @override
  bool isConnected(Pos a, Pos b) => super.isConnected(a, b);

  // -- Writes ---------------------------------------------------------------------------------

  @override
  Future<void> placeBlock(Pos pos, BState state) async {
    final id = stateIdOf(state);
    if (id == null) return;
    await world.setBlockState(
      pos: pos.toBlockPos(),
      state: id,
      updateFlags: BlockUpdateFlags.moved,
    );
  }

  @override
  Future<void> destroyBlockAt(Pos pos, {bool drop = false}) async {
    await world.breakBlock(pos.toBlockPos(), drop: drop);
  }

  @override
  Future<void> removeBlockEntityAt(Pos pos) async {
    // Placing air removes the block entity; `removeBlocksFromWorld` writes air right after.
  }

  @override
  Future<void> restoreBlockEntity(Pos pos, NbtMap nbt) async {
    final bytes = BinaryNbt.write(nbt.toValue());
    world.setBlockEntityNbt(pos: pos.toBlockPos(), nbtData: bytes);
  }

  @override
  void sendBlockUpdate(Pos pos, BState oldState, BState newState) {
    final oldId = stateIdOf(oldState);
    final newId = stateIdOf(newState);
    if (oldId == null || newId == null) return;
    unawaited(
      world.notifyBlockChange(
        pos.toBlockPos(),
        oldState: oldId,
        newState: newId,
        flags: BlockUpdateFlags.moved,
      ),
    );
  }

  @override
  void blockBreakParticles(Pos pos, BState state) {
    // The host's `breakBlock` sends the particles; a block that cannot be placed has no state id.
  }

  @override
  void dropBlockItems(BState state, Pos pos) {
    final item = ItemStack.create(registryKey: state.key, count: 1);
    unawaited(world.dropItem(pos.center, item));
  }

  @override
  void addGlue(Aabb box) {
    unawaited(world.spawnPlugin('create:super_glue', box.center));
  }

  @override
  void updateNeighbours(Pos pos, BState state) {
    unawaited(world.updateShapeAround(pos: pos.toBlockPos()));
  }

  @override
  void playDisassembleSound(Pos pos) {
    world.playCustomSound(
      soundName: 'create:contraption_disassemble',
      category: SoundCategory.blocks,
      pos: pos.center,
      volume: 1,
      pitch: 1,
    );
  }

  @override
  bool sitPassenger(Pos seatPos, Object passenger) {
    final handle = passenger is HostPassengerRef ? passenger.handle : passenger;
    if (handle is! Entity) return false;
    return ContraptionHostHooks.sitPassenger?.call(
          world.getId(),
          seatPos,
          handle,
        ) ??
        false;
  }

  List<EntitySnapshot> _snapshots(Aabb area) => world.getEntitiesInBox(
    min: (area.minX, area.minY, area.minZ),
    max: (area.maxX, area.maxY, area.maxZ),
    filter: const EntityFilterAll(),
  );

  static String _entityTypeName(Entity entity) {
    final key = entity.getPluginTypeKey();
    if (key != null) return key;
    return entity.getType().wireName;
  }

  static bool _isMinecartType(String type) => const {
    'minecraft:minecart',
    'minecraft:chest_minecart',
    'minecraft:furnace_minecart',
    'minecraft:hopper_minecart',
    'minecraft:command_block_minecart',
  }.contains(type);
}

/// A passenger of a contraption, wrapping a host [Entity].
final class HostPassengerRef implements ContraptionPassengerRef {
  final Entity handle;
  final AbstractContraptionEntity? Function(int id) entityById;

  HostPassengerRef(this.handle, this.entityById);

  @override
  String get uuid => handle.getUuid().toString();

  @override
  int get entityId => handle.getId();

  @override
  bool get isPlayer => _typeName == 'minecraft:player';

  @override
  bool get isTamableAnimal => const {
    'minecraft:wolf',
    'minecraft:cat',
    'minecraft:ocelot',
    'minecraft:parrot',
  }.contains(_typeName);

  @override
  bool get isPassenger => handle.getVehicle() != null;

  @override
  double get vehicleAttachmentPointY => 0;

  @override
  Object? get contraptionEntity => entityById(entityId);

  @override
  ContraptionPassengerRef? get vehicle {
    final v = handle.getVehicle();
    return v == null ? null : HostPassengerRef(v, entityById);
  }

  @override
  void setInSittingPose(bool sitting) {
    // The host does not expose `TamableAnimal.setInSittingPose`; the pose is cosmetic.
  }

  @override
  void teleportTo(Vec3 position) =>
      unawaited(handle.teleport(pos: position, worldRef: handle.getWorld()));

  @override
  NbtValue? getPersistentData(String key) {
    final tree = handle.getCustomData(namespace: 'create', key: key);
    return tree == null ? null : treeToValue(tree);
  }

  @override
  void setPersistentData(String key, NbtValue? value) {
    if (value == null) {
      handle.removeCustomData(namespace: 'create', key: key);
    } else {
      handle.setCustomData(
        namespace: 'create',
        key: key,
        value: valueToTree(value),
      );
    }
  }

  @override
  Object get hostEntity => handle;

  String get _typeName {
    final key = handle.getPluginTypeKey();
    return key ?? handle.getType().wireName;
  }
}

/// A colliding entity, wrapping a host [Entity].
final class HostCollisionEntity implements ContraptionCollisionEntity {
  final Entity handle;
  final AbstractContraptionEntity? Function(int id) entityById;

  HostCollisionEntity(this.handle, this.entityById);

  @override
  int get entityId => handle.getId();

  @override
  int get id => entityId;

  @override
  String get typeKey => _typeName;

  @override
  bool get isLiving => handle.asLiving() != null;

  @override
  Object get hostEntity => handle;

  @override
  String get uuid => handle.getUuid().toString();

  @override
  bool get isAlive => true;

  @override
  bool get isPlayer => _typeName == 'minecraft:player';

  @override
  bool get isSpectator => false;

  @override
  bool get isItemEntity => _typeName == 'minecraft:item';

  @override
  bool get isMinecart => _isMinecartType(_typeName);

  @override
  bool get isHangingEntity => const {
    'minecraft:painting',
    'minecraft:item_frame',
    'minecraft:glow_item_frame',
    'minecraft:leash_knot',
  }.contains(_typeName);

  @override
  bool get isSeatEntity => handle.getPluginTypeKey() == 'create:seat';

  @override
  bool get isProjectile => const {
    'minecraft:arrow',
    'minecraft:spectral_arrow',
    'minecraft:trident',
    'minecraft:snowball',
    'minecraft:egg',
    'minecraft:ender_pearl',
    'minecraft:experience_bottle',
    'minecraft:potion',
    'minecraft:firework_rocket',
    'minecraft:fireball',
    'minecraft:small_fireball',
    'minecraft:dragon_fireball',
    'minecraft:wither_skull',
    'minecraft:llama_spit',
    'minecraft:shulker_bullet',
    'minecraft:fishing_bobber',
    'minecraft:wind_charge',
    'minecraft:breeze_wind_charge',
  }.contains(_typeName);

  @override
  bool get noPhysics => false;

  @override
  bool get isPassenger => handle.getVehicle() != null;

  @override
  bool get isSuppressingBounce => false;

  @override
  bool get onGround => handle.isOnGround();

  @override
  double get maxUpStep => 0.6;

  @override
  Vec3 get position => handle.position;

  @override
  Aabb get boundingBox {
    final bb = handle.getBoundingBox();
    return Aabb(
      bb.min.$1,
      bb.min.$2,
      bb.min.$3,
      bb.max.$1,
      bb.max.$2,
      bb.max.$3,
    );
  }

  @override
  Vec3 get deltaMovement => handle.velocity;

  @override
  void setDeltaMovement(Vec3 motion) => handle.setVelocity(velocity: motion);

  @override
  void setPosition(Vec3 position) => handle.setPositionRotationDelta(
    pos: position,
    yaw: handle.getYaw(),
    pitch: handle.getPitch(),
    velocity: handle.velocity,
  );

  @override
  void teleport(Vec3 position) => setPosition(position);

  @override
  void setOnGround(bool onGround) => handle.setOnGround(onGround: onGround);

  @override
  void setFallDistance(double distance) =>
      handle.setFallDistance(distance: distance);

  @override
  void setVelocitySync() {}

  @override
  void setAboveGroundTickCountZero() {}

  @override
  void playSoundAt(String sound, {double volume = 1, double pitch = 1}) {
    handle.getWorld().playCustomSound(
      soundName: sound,
      category: SoundCategory.neutral,
      pos: position,
      volume: volume,
      pitch: pitch,
    );
  }

  @override
  void damageRunOver(double amount) {
    final living = handle.asLiving();
    if (living == null) return;
    unawaited(
      living.damageByKey(damageTypeKey: 'create:run_over', amount: amount),
    );
  }

  @override
  List<ContraptionCollisionEntity> get selfAndPassengers => [this];

  @override
  bool get contraptionGrounded =>
      handle.getCustomData(namespace: 'create', key: 'contraption_grounded') !=
      null;

  @override
  void clearContraptionGrounded() {
    handle.removeCustomData(namespace: 'create', key: 'contraption_grounded');
  }

  @override
  AbstractContraptionEntity? get contraptionEntity => entityById(entityId);

  String get _typeName {
    final key = handle.getPluginTypeKey();
    return key ?? handle.getType().wireName;
  }

  static bool _isMinecartType(String type) => const {
    'minecraft:minecart',
    'minecraft:chest_minecart',
    'minecraft:furnace_minecart',
    'minecraft:hopper_minecart',
    'minecraft:command_block_minecart',
  }.contains(type);
}

/// The host entity of a contraption.
final class HostContraptionEntity implements ContraptionEntityHost {
  final World world;
  final HostContraptionLevel level;
  final AbstractContraptionEntity? Function(int id) _entityById;

  Entity? _handle;
  AbstractContraptionEntity? _entity;
  int _entityId = 0;
  String _uuid = '00000000-0000-0000-0000-000000000000';
  Vec3 _position;
  Vec3 _prevPosition;
  Vec3 _deltaMovement = vec3Zero;
  Aabb _boundingBox = const Aabb(0, 0, 0, 1, 1, 1);
  double _yaw = 0;
  double _pitch = 0;
  bool _removed = false;
  bool _stalled = false;
  String? _controllingPlayer;
  final Map<String, NbtValue> _persistentData = {};

  HostContraptionEntity(this.world, this.level, Vec3 position, this._entityById)
    : _position = position,
      _prevPosition = position;

  /// The host entity, once spawned.
  Entity? get handle => _handle;

  /// The Dart entity that drives this host, set by the factory.
  AbstractContraptionEntity? get attachedEntity => _entity;

  void attachEntity(AbstractContraptionEntity entity) => _entity = entity;

  void attachHandle(Entity handle) {
    _handle = handle;
    _entityId = handle.getId();
    _uuid = handle.getUuid().toString();
    _applyTransform();
  }

  @override
  int get entityId => _entityId;

  @override
  String get uuid => _uuid;

  @override
  bool get isAlive => !_removed && _handle != null;

  @override
  bool get isRemoved => _removed;

  @override
  bool get stalled => _stalled;

  @override
  Vec3 get position => _position;

  @override
  Vec3 get prevPosition => _prevPosition;

  @override
  Aabb get boundingBox => _boundingBox;

  @override
  void setBoundingBox(Aabb box) {
    _boundingBox = box;
    _handle?.resize(box.xSize, box.ySize);
  }

  @override
  Vec3 get deltaMovement => _deltaMovement;

  @override
  void setDeltaMovement(Vec3 motion) => _deltaMovement = motion;

  @override
  void setPosition(Vec3 position) {
    _prevPosition = _position;
    _position = position;
    _applyTransform();
  }

  @override
  void teleport(Vec3 position) {
    _prevPosition = _position;
    _position = position;
    final handle = _handle;
    if (handle == null) return;
    unawaited(handle.teleport(pos: position, worldRef: world));
  }

  @override
  List<ContraptionPassengerRef> get passengers => [
    for (final p in _handle?.getPassengers() ?? const <Entity>[])
      HostPassengerRef(p, _entityById),
  ];

  @override
  bool hasPassenger(ContraptionPassengerRef passenger) =>
      passengers.any((p) => p.entityId == passenger.entityId);

  @override
  void addPassenger(ContraptionPassengerRef passenger, {bool force = true}) {
    final handle = _handle;
    if (handle == null || passenger is! HostPassengerRef) return;
    unawaited(handle.addPassenger(passenger: passenger.handle));
  }

  @override
  void removePassenger(ContraptionPassengerRef passenger) {
    final handle = _handle;
    if (handle == null || passenger is! HostPassengerRef) return;
    unawaited(handle.removePassenger(passenger: passenger.handle));
  }

  @override
  void ejectPassengers() => unawaited(_handle?.ejectPassengers());

  @override
  void setPassengerPosition(ContraptionPassengerRef passenger, Vec3 position) {
    if (passenger is! HostPassengerRef) return;
    _handle?.setPassengerOffset(
      passenger: passenger.handle,
      x: position.$1,
      y: position.$2,
      z: position.$3,
    );
  }

  @override
  void teleportEntity(ContraptionPassengerRef passenger, Vec3 position) {
    if (passenger is HostPassengerRef)
      unawaited(passenger.handle.teleport(pos: position, worldRef: world));
  }

  @override
  Object? get vehicle => _handle?.getVehicle();

  @override
  ContraptionPassengerRef? get vehiclePassenger {
    final v = _handle?.getVehicle();
    return v == null ? null : HostPassengerRef(v, _entityById);
  }

  @override
  Vec3 get vehiclePosition => _handle?.getVehicle()?.position ?? _position;

  @override
  Vec3 get vehiclePrevPosition => vehiclePosition;

  @override
  Vec3 get vehicleDeltaMovement => _handle?.getVehicle()?.velocity ?? vec3Zero;

  @override
  bool get vehicleIsMinecart {
    final v = _handle?.getVehicle();
    if (v == null) return false;
    final key = v.getPluginTypeKey() ?? v.getType().wireName;
    return HostCollisionEntity._isMinecartType(key);
  }

  @override
  void setVehicleDeltaMovement(Vec3 motion) =>
      _handle?.getVehicle()?.setVelocity(velocity: motion);

  @override
  Object? controllerAt(Pos pos) {
    final be = level.blockEntities.at(level.worldId, pos.toBlockPos());
    return be is IControlContraption ? be : null;
  }

  @override
  void setRotation(double yaw, double pitch) {
    _yaw = yaw;
    _pitch = pitch;
    _applyTransform();
  }

  @override
  void setOnGround(bool onGround) => _handle?.setOnGround(onGround: onGround);

  @override
  double get maxUpStep => 0.6;

  @override
  void playSound(String sound, Vec3 at, {double volume = 1, double pitch = 1}) {
    world.playCustomSound(
      soundName: sound,
      category: SoundCategory.blocks,
      pos: at,
      volume: volume,
      pitch: pitch,
    );
  }

  @override
  void sendPayload(String channel, Map<String, Object?> fields) {
    final bus = ContraptionHost.bus;
    if (bus == null) return;
    bus.sendToTrackingAt(channel, level.worldId, (
      _position.$1.floor(),
      _position.$2.floor(),
      _position.$3.floor(),
    ), fields);
  }

  @override
  void sendControlsAbort(String playerUuid) {
    final bus = ContraptionHost.bus;
    if (bus == null) return;
    for (final player in bus.roster.players) {
      if (player.getId().asString != playerUuid) continue;
      bus.sendClientbound('create:controls_abort', player, const {});
      return;
    }
  }

  @override
  void sendBlockChanged(Pos localPos, BState state) {
    final id = stateIdOf(state);
    if (id == null) return;
    sendPayload('create:contraption_block_changed', {
      'entityId': _entityId,
      'localPos': localPos,
      'newState': id,
    });
  }

  @override
  void sendStorageSync(StorageSync sync) {
    sendPayload('create:mounted_storage_sync', {
      'contraptionId': _entityId,
      'items': {
        for (final e in sync.items.entries) e.key: e.value.encode().toValue(),
      },
      'fluids': {
        for (final e in sync.fluids.entries) e.key: e.value.encode().toValue(),
      },
    });
  }

  @override
  void sendSeatMapping(Map<String, int> mapping, {int? dismountedId}) {
    sendPayload('create:contraption_seat_mapping', {
      'entityId': _entityId,
      'mapping': mapping,
      'dismountedId': dismountedId ?? -1,
    });
  }

  @override
  void sendStall(double angle) {
    sendPayload('create:contraption_stall', {
      'entityId': _entityId,
      'x': _position.$1,
      'y': _position.$2,
      'z': _position.$3,
      'angle': angle,
    });
  }

  @override
  void sendDisassembly(StructureTransform transform) {
    sendPayload('create:contraption_disassemble', {
      'entityId': _entityId,
      'transform': transform.toWire(),
    });
  }

  @override
  void setStalled(bool stalled) => _stalled = stalled;

  @override
  String? get controllingPlayer => _controllingPlayer;

  @override
  void setControllingPlayer(String? uuid) => _controllingPlayer = uuid;

  @override
  NbtValue? getPersistentData(String key) => _persistentData[key];

  @override
  void setPersistentData(String key, NbtValue? value) {
    if (value == null) {
      _persistentData.remove(key);
    } else {
      _persistentData[key] = value;
    }
  }

  @override
  ContraptionCollisionEntity? collisionEntityById(int id) {
    final entity = world.getEntityById(id: id);
    return entity == null ? null : HostCollisionEntity(entity, _entityById);
  }

  @override
  ContraptionPassengerRef? passengerFromHost(Object handle) {
    if (handle is! Entity) return null;
    return HostPassengerRef(handle, _entityById);
  }

  @override
  List<ContraptionCollisionEntity> entitiesNear(Aabb box) {
    final out = <ContraptionCollisionEntity>[];
    for (final snapshot in world.getEntitiesInBox(
      min: (box.minX, box.minY, box.minZ),
      max: (box.maxX, box.maxY, box.maxZ),
      filter: const EntityFilterAll(),
    )) {
      if (snapshot.id == _entityId) continue;
      final entity = world.getEntityById(id: snapshot.id);
      if (entity == null) continue;
      out.add(HostCollisionEntity(entity, _entityById));
    }
    return out;
  }

  @override
  void remove() {
    _removed = true;
    _handle?.remove();
  }

  void _applyTransform() {
    final handle = _handle;
    if (handle == null) return;
    handle.setPositionRotationDelta(
      pos: _position,
      yaw: _yaw,
      pitch: _pitch,
      velocity: _deltaMovement,
    );
  }
}

/// The contraptions host: the factory of the actuators and the live entities of each world.
final class ContraptionHost {
  static PayloadBus? bus;

  final Worlds worlds;
  final BlockEntityStore blockEntities;
  final ContraptionSettings settings;
  final Logger log;

  /// world id -> entity id -> the contraption entity.
  final Map<String, Map<int, AbstractContraptionEntity>> entities = {};

  ContraptionHost({
    required this.worlds,
    required this.blockEntities,
    required this.settings,
    required this.log,
  });

  /// The world with [worldId], `null` when it is not loaded.
  World? worldOf(String worldId) => worlds.byId(worldId);

  /// `ContraptionLevel` of [worldId]; throws when the world is not loaded.
  ContraptionLevel levelOf(String worldId) =>
      levelOfOrNull(worldId) ?? (throw StateError('Unknown world $worldId'));

  /// `ContraptionLevel` of [worldId], `null` when the world is not loaded.
  ContraptionLevel? levelOfOrNull(String worldId) {
    final world = worldOf(worldId);
    if (world == null) return null;
    return HostContraptionLevel(world, blockEntities, settings);
  }

  AbstractContraptionEntity? entityById(String worldId, int id) {
    final fromHost = ContraptionHandler.entityById(worldId, id);
    if (fromHost != null) return fromHost;
    return entities[worldId]?[id];
  }

  /// `world.getEntity(id)` without knowing the world (`MountedStorageSyncPacket.handle`).
  AbstractContraptionEntity? entityByIdAnyWorld(int id) {
    for (final worldId in entities.keys) {
      final found = entityById(worldId, id);
      if (found != null) return found;
    }
    return ContraptionHandler.entityByIdAnyWorld(id);
  }

  ControlledContraptionEntity createControlled(
    String worldId,
    Pos controllerPos,
    Contraption contraption,
  ) {
    final world =
        worldOf(worldId) ?? (throw StateError('Unknown world $worldId'));
    final level = HostContraptionLevel(world, blockEntities, settings);
    final host = HostContraptionEntity(
      world,
      level,
      controllerPos.center,
      (id) => entityById(worldId, id),
    );
    final entity = ControlledContraptionEntity(host);
    host.attachEntity(entity);
    entity.controllerPos = controllerPos;
    entity.setContraption(contraption);
    return entity;
  }

  OrientedContraptionEntity createOriented(
    String worldId,
    Contraption contraption,
    Direction facing,
  ) {
    final world =
        worldOf(worldId) ?? (throw StateError('Unknown world $worldId'));
    final level = HostContraptionLevel(world, blockEntities, settings);
    final host = HostContraptionEntity(
      world,
      level,
      vec3Zero,
      (id) => entityById(worldId, id),
    );
    final entity = OrientedContraptionEntity(host);
    host.attachEntity(entity);
    entity.configure(contraption, facing);
    return entity;
  }

  AbstractContraptionEntity createGantry(
    String worldId,
    Contraption contraption,
    Direction movementAxis,
  ) {
    final world =
        worldOf(worldId) ?? (throw StateError('Unknown world $worldId'));
    final level = HostContraptionLevel(world, blockEntities, settings);
    final host = HostContraptionEntity(
      world,
      level,
      vec3Zero,
      (id) => entityById(worldId, id),
    );
    final entity = GantryContraptionEntity.create(
      host,
      contraption,
      movementAxis,
    );
    host.attachEntity(entity);
    return entity;
  }

  /// `level.addFreshEntity(entity)`.
  void spawn(String worldId, AbstractContraptionEntity entity) {
    final world = worldOf(worldId);
    if (world == null) return;
    unawaited(_spawn(worldId, world, entity));
  }

  Future<void> _spawn(
    String worldId,
    World world,
    AbstractContraptionEntity entity,
  ) async {
    final host = entity.host;
    if (host is! HostContraptionEntity) return;
    final typeKey =
        ContraptionHostHooks.entityTypeOf?.call(entity) ??
        (entity is ControlledContraptionEntity
            ? 'create:stationary_contraption'
            : entity is GantryContraptionEntity
            ? 'create:gantry_contraption'
            : 'create:contraption');

    final data = NbtMap();
    entity.writeAdditional(data, spawnPacket: true);
    final spawnData = BinaryNbt.write(data.toValue());

    final spawned = await world.spawnPlugin(
      typeKey,
      host.position,
      spawnData: spawnData,
    );
    host.attachHandle(spawned);
    entity.setPos(host.position);

    entities.putIfAbsent(worldId, () => {})[host.entityId] = entity;
    ContraptionHandler.addSpawnedContraptionsToCollisionList(worldId, entity);
    ContraptionHostHooks.spawned?.call(entity);
    await _createSubContraptions(worldId, entity);
  }

  /// `Contraption.onEntityCreated`: the stabilized sub-contraptions of bearings.
  Future<void> _createSubContraptions(
    String worldId,
    AbstractContraptionEntity parent,
  ) async {
    final c = parent.contraption;
    if (c == null || c.pendingSubContraptions.isEmpty) return;
    final type = ContraptionTypes.byId('create:stabilized');
    if (type == null) return;
    final world = worldOf(worldId);
    if (world == null) return;
    final level = levelOf(worldId);

    for (final face in c.pendingSubContraptions) {
      final sub = type.create();
      // `new StabilizedContraption(facing)` of the bearing that leaves it behind.
      if (sub is StabilizedContraption) sub.facing = face.face;
      try {
        if (!await sub.assemble(level, face.pos)) continue;
      } on AssemblyException {
        continue;
      }
      await sub.removeBlocksFromWorld(level, posZero);
      final oriented = createOriented(worldId, sub, face.face);
      final connected = face.connectedPos;
      oriented.setPos((
        connected.$1 + 0.5,
        connected.$2.toDouble(),
        connected.$3 + 0.5,
      ));
      await _spawn(worldId, world, oriented);
      c.stabilizedSubContraptions[oriented.uuid] = BlockFace(
        c.toLocalPos(face.pos),
        face.face,
      );
    }
  }

  /// Ticks every contraption of [worldId] (`ContraptionHandler.tick`).
  Future<void> tick(String worldId) async {
    final map = entities[worldId];
    if (map == null) return;
    for (final entry in map.entries.toList()) {
      final entity = entry.value;
      if (!entity.host.isAlive) {
        map.remove(entry.key);
        continue;
      }
      await entity.tick();
    }
    ContraptionHandler.tick(worldId);
  }

  void forgetWorld(String worldId) {
    entities.remove(worldId);
    ContraptionHandler.forgetWorld(worldId);
  }

  void clear() {
    entities.clear();
    ContraptionHandler.clear();
    bus = null;
  }
}

/// The `GlueEntityHost` of `actuator_contract.dart`: the super glue entities of a world.
final class HostGlueEntityHost implements GlueEntityHost {
  final ContraptionHost host;

  HostGlueEntityHost(this.host);

  World? _world(String worldId) => host.worldOf(worldId);

  @override
  void spawn(String worldId, Aabb box) {
    final world = _world(worldId);
    if (world == null) return;
    unawaited(world.spawnPlugin('create:super_glue', box.center));
  }

  @override
  void discard(String worldId, int entityId) {
    final entity = _world(worldId)?.getEntityById(id: entityId);
    entity?.remove();
  }

  @override
  List<GlueRef> gluesIn(String worldId, Aabb box) {
    final level = host.levelOfOrNull(worldId);
    return level is HostContraptionLevel ? level.gluesIn(box) : const [];
  }

  @override
  GlueRef? glueById(String worldId, int entityId) {
    final world = _world(worldId);
    if (world == null) return null;
    final entity = world.getEntityById(id: entityId);
    if (entity == null || entity.getPluginTypeKey() != 'create:super_glue') {
      return null;
    }
    final bb = entity.getBoundingBox();
    return GlueRef(
      entityId,
      Aabb(bb.min.$1, bb.min.$2, bb.min.$3, bb.max.$1, bb.max.$2, bb.max.$3),
    );
  }
}

/// The `ContraptionEntityFactory` of `actuator_contract.dart`, over a [ContraptionHost].
final class HostContraptionEntityFactory implements ContraptionEntityFactory {
  final ContraptionHost host;

  HostContraptionEntityFactory(this.host);

  @override
  ControlledContraptionEntity createControlled(
    String worldId,
    Pos controllerPos,
    Contraption contraption,
  ) => host.createControlled(worldId, controllerPos, contraption);

  @override
  AbstractContraptionEntity createOriented(
    String worldId,
    Contraption contraption,
    Direction facing,
  ) => host.createOriented(worldId, contraption, facing);

  @override
  AbstractContraptionEntity createGantry(
    String worldId,
    Contraption contraption,
    Direction movementAxis,
  ) => host.createGantry(worldId, contraption, movementAxis);

  @override
  void spawn(String worldId, AbstractContraptionEntity entity) =>
      host.spawn(worldId, entity);

  @override
  AbstractContraptionEntity? entityById(String worldId, int id) =>
      host.entityById(worldId, id);
}
