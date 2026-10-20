// What the minecart coupling code needs from a minecart entity, and the host implementation over a
// plugin `Entity`/`World`. Java works on `AbstractMinecart`; the host only exposes entities by id,
// so every operation looks the entity up again (no host resources are stored across ticks).
//
// Java: `content/contraptions/minecart/{MinecartSim2020,CouplingPhysics,MinecartController}`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter;
import '../../common/common.dart';
import '../../core/block_entity.dart';
import '../blocks/actuator_contract.dart';

/// `RailShape` as the rail state stores it.
enum RailShape {
  northSouth('north_south'),
  eastWest('east_west'),
  ascendingEast('ascending_east'),
  ascendingWest('ascending_west'),
  ascendingNorth('ascending_north'),
  ascendingSouth('ascending_south'),
  southEast('south_east'),
  southWest('south_west'),
  northWest('north_west'),
  northEast('north_east');

  const RailShape(this.serializedName);

  final String serializedName;

  static RailShape? byName(String? name) {
    for (final s in values) {
      if (s.serializedName == name) return s;
    }
    return null;
  }
}

/// A minecart as the coupling code sees it (`AbstractMinecart`).
abstract interface class MinecartAccess {
  int get id;
  String get uuid;
  bool get isAlive;

  Vec3 get position;
  Vec3 get velocity;
  void setVelocity(Vec3 velocity);

  double get yaw;
  double get pitch;
  void setRotation(double yaw, double pitch);

  /// `isVehicle()`: the cart has passengers.
  bool get isVehicle;

  /// `cart instanceof Minecart`: a plain rideable cart.
  bool get isPlainCart;

  /// `cart instanceof MinecartFurnace`.
  bool get isFurnaceCart;

  /// Any vanilla minecart variant (`AbstractMinecart`).
  bool get isAnyMinecart;

  /// `cart.move(MoverType.SELF, delta)`.
  void move(Vec3 delta);

  /// `cart.setPos`.
  void setPosition(Vec3 position);

  /// `cart.getCurrentBlockPosOrRailBelow()`.
  Pos? get railPos;

  /// The rail shape under the cart, `null` when it is not on a rail.
  RailShape? get railShape;

  /// `cart.getBehavior().getMaxSpeed(level)`.
  double get maxSpeed;

  /// `cart.isInWater()`.
  bool get isInWater;

  /// `Mth.equal(furnace.push.x, 0) && Mth.equal(furnace.push.z, 0)`: a furnace cart that is
  /// actively pushing cannot be corrected by the coupling.
  bool get furnacePushIsZero;

  /// `cart.setHurtDir(-getHurtDir()); cart.setHurtTime(10); cart.setDamage(50)`: an activator
  /// rail destroys the cart it just released.
  void markActivatorRailHit();

  /// The first passenger if it is a contraption entity (`AbstractContraptionEntity`), `null` for
  /// any other passenger (a player riding a plain cart).
  Object? get firstPassengerContraption;

  /// `cart.ejectPassengers()`.
  void ejectPassengers();

  /// `world` the cart is in.
  World get world;
}

/// Looks a cart up by id or uuid in a world.
abstract interface class MinecartWorld {
  /// `World.getId()`.
  String get worldId;

  MinecartAccess? byId(int id);

  MinecartAccess? byUuid(String uuid);

  /// `world.getBlockState(pos)` as a state.
  BState stateAt(Pos pos);

  /// The current game tick.
  int get tick;
}

/// The host implementation: `World.getEntityById`/`getEntityByUuid` + a plugin `Entity`.
final class HostMinecartWorld implements MinecartWorld {
  final World world;
  final BlockEntityStore store;

  HostMinecartWorld(this.world, this.store);

  @override
  String get worldId => world.getId();

  @override
  int get tick => world.getWorldAge();

  @override
  BState stateAt(Pos pos) => HostBlockGetter.stateOfId(
    world.getBlockStateId(
      pos: BlockPos(x: pos.$1, y: pos.$2, z: pos.$3),
    ),
  );

  @override
  MinecartAccess? byId(int id) {
    final entity = world.getEntityById(id: id);
    if (entity == null) return null;
    return HostMinecartAccess(this, entity.getId());
  }

  @override
  MinecartAccess? byUuid(String uuid) {
    for (final entity in world.getEntities()) {
      if (entity.getUuid().toString() == uuid)
        return HostMinecartAccess(this, entity.getId());
    }
    return null;
  }
}

/// A cart in the host world. The entity is looked up for every operation.
final class HostMinecartAccess implements MinecartAccess {
  final HostMinecartWorld level;
  final int _id;

  HostMinecartAccess(this.level, this._id);

  Entity? get _entity => level.world.getEntityById(id: _id);

  @override
  int get id => _id;

  @override
  String get uuid => _entity?.getUuid().toString() ?? '';

  @override
  bool get isAlive => _entity != null;

  @override
  World get world => level.world;

  @override
  Vec3 get position => _entity?.getPosition() ?? vec3Zero;

  @override
  Vec3 get velocity => _entity?.getVelocity() ?? vec3Zero;

  @override
  void setVelocity(Vec3 velocity) => _entity?.setVelocity(velocity: velocity);

  @override
  double get yaw => _entity?.getYaw() ?? 0;

  @override
  double get pitch => _entity?.getPitch() ?? 0;

  @override
  void setRotation(double yaw, double pitch) =>
      _entity?.setRotation(yaw: yaw, pitch: pitch);

  @override
  bool get isVehicle => (_entity?.getPassengers().isNotEmpty ?? false);

  @override
  bool get isPlainCart => _entity?.getType() == EntityType.minecart;

  @override
  bool get isFurnaceCart => _entity?.getType() == EntityType.furnaceMinecart;

  @override
  bool get isAnyMinecart => switch (_entity?.getType()) {
    EntityType.minecart ||
    EntityType.furnaceMinecart ||
    EntityType.chestMinecart ||
    EntityType.hopperMinecart ||
    EntityType.commandBlockMinecart => true,
    _ => false,
  };

  @override
  void move(Vec3 delta) =>
      _entity?.moveBy((delta.$1, delta.$2, delta.$3), collide: true);

  @override
  void setPosition(Vec3 position) {
    final entity = _entity;
    if (entity == null) return;
    entity.setPositionRotationDelta(
      pos: position,
      yaw: entity.getYaw(),
      pitch: entity.getPitch(),
      velocity: entity.getVelocity(),
    );
  }

  @override
  Pos? get railPos {
    final p = position;
    final block = (p.$1.floor(), p.$2.floor(), p.$3.floor());
    if (_isRail(block.below)) return block.below;
    if (_isRail(block)) return block;
    return null;
  }

  bool _isRail(Pos pos) => isRailState(level.stateAt(pos));

  @override
  RailShape? get railShape {
    final pos = railPos;
    if (pos == null) return null;
    final state = level.stateAt(pos);
    if (!isRailState(state)) return null;
    return RailShape.byName(state['shape']);
  }

  @override
  bool get isInWater => _entity?.isInWater() ?? false;

  /// `AbstractMinecart#getBehavior().getMaxSpeed(level)`: 0.4 (0.2 in water), and a furnace cart
  /// takes half of that (three quarters in water).
  @override
  double get maxSpeed {
    final base = isInWater ? 0.2 : 0.4;
    if (!isFurnaceCart) return base;
    return base * (isInWater ? 0.75 : 0.5);
  }

  /// The host does not expose `MinecartFurnace.push`; a cart that is not being pushed is the
  /// common case and the one the coupling may correct.
  @override
  bool get furnacePushIsZero => true;

  @override
  void markActivatorRailHit() {
    final living = _entity?.asLiving();
    if (living == null) return;
    // The host has no hurt time/damage fields on the cart, so the kill the activator rail applies
    // (`setDamage(50)`) is dealt as damage instead.
    unawaited(living.damageWith('minecraft:generic', 50));
  }

  @override
  Object? get firstPassengerContraption {
    final entity = _entity;
    if (entity == null) return null;
    final passengers = entity.getPassengers();
    if (passengers.isEmpty) return null;
    // Only a contraption entity counts; a player riding a plain cart must not be ejected.
    return ActuatorHosts.entities?.entityById(level.worldId, passengers.first.getId());
  }

  @override
  void ejectPassengers() => _entity?.ejectPassengers();
}

/// Whether [state] is a rail block: the `minecraft:rails` block tag (`create:cart_assembler` and
/// `create:controller_rail` are tagged with it, like the vanilla rails).
bool isRailState(BState state) =>
    state.key == 'minecraft:rail' ||
    state.key == 'minecraft:powered_rail' ||
    state.key == 'minecraft:detector_rail' ||
    state.key == 'minecraft:activator_rail' ||
    state.key == 'create:controller_rail' ||
    state.key == 'create:cart_assembler';

/// `MinecartSim2020.getRailVec`.
Vec3 railVec(RailShape shape) => switch (shape) {
  RailShape.ascendingNorth ||
  RailShape.ascendingSouth ||
  RailShape.northSouth => const (0.0, 0.0, 1.0),
  RailShape.ascendingEast ||
  RailShape.ascendingWest ||
  RailShape.eastWest => const (1.0, 0.0, 0.0),
  RailShape.northEast ||
  RailShape.southWest => const (1.0, 0.0, 1.0).normalized,
  RailShape.northWest ||
  RailShape.southEast => const (1.0, 0.0, -1.0).normalized,
};

/// `VecHelper.intersectSphere(cart, axis, center, radius)`: the first point on the line through
/// [cart] along [axis] at [radius] from [center], `null` when the line misses the sphere.
Vec3? intersectSphere(Vec3 cart, Vec3 axis, Vec3 center, double radius) {
  final toCenter = center - cart;
  final a = axis.lengthSquared;
  if (a == 0) return null;
  final b = 2 * toCenter.dot(axis);
  final c = toCenter.lengthSquared - radius * radius;
  final discriminant = b * b - 4 * a * c;
  if (discriminant < 0) return null;
  final root = math.sqrt(discriminant);
  final t1 = (-b - root) / (2 * a);
  final t2 = (-b + root) / (2 * a);
  final t = t1.abs() < t2.abs() ? t1 : t2;
  return cart + axis * t;
}
