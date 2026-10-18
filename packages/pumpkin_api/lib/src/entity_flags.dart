import 'bindings.g.dart' as generated;
import 'bindings.g.dart';
import 'host_result.dart';

/// A boolean flag of an entity (`entity-flags.wit`). Nothing costs anything
/// until a plugin sets one. Needs [Permissions.entityFlags].
enum EntityFlag {
  /// No fire or lava damage and no burning.
  fireImmune('fire-immune'),

  /// Slime blocks and beds do not bounce the entity after a fall.
  noFallBounce('no-fall-bounce'),

  /// Projectiles pass through the entities that ride this entity. The opposite
  /// of vanilla; most plugins want [projectilesHitRiders] instead.
  ignoreRidersHit('ignore-riders-hit'),

  /// Projectiles fired by a rider of this entity (or of a vehicle stack on it)
  /// can hit the other riders. Vanilla skips riders that share the shooter's
  /// vehicle; contraptions need this.
  projectilesHitRiders('projectiles-hit-riders'),

  /// Mobs riding this entity attack from their own box, not from a box that
  /// includes this vehicle.
  ignoreVehicleBox('ignore-vehicle-box'),

  /// Fires `Events.entityFluidMovement` after the entity moved in water or
  /// lava.
  fluidMovementEvents('fluid-movement-events'),

  /// Mobs never pick the entity as a target (for fake players).
  ignoredByMobs('ignored-by-mobs');

  const EntityFlag(this.wireName);

  /// The key in the WIT.
  final String wireName;
}

/// Flags and overrides of entities.
extension EntityFlagsApi on Entity {
  /// Sets [flag]. Throws a [HostException] on failure.
  void setFlag(EntityFlag flag, bool value) => unwrapHost(
    generated.entityFlags.setFlag(entity: this, key: flag.wireName, value: value),
    'Setting ${flag.wireName}',
  );

  /// Whether [flag] is set.
  bool hasFlag(EntityFlag flag) => unwrapHost(
    generated.entityFlags.getFlag(entity: this, key: flag.wireName),
    'Reading ${flag.wireName}',
  );

  /// Replaces the width and height of the entity in every pose (the eye height
  /// scales with the height); `null` goes back to the normal dimensions. It
  /// lasts until cleared, and `Events.entitySize` can still change the result.
  /// Bedrock clients get the size, Java clients keep their own idea of the box.
  void overrideSize((double, double)? size) => unwrapHost(
    generated.entityFlags.setSizeOverride(entity: this, size: size),
    'Overriding the entity size',
  );

  /// Forces the pose of the entity: every pose change ends up as this pose until
  /// cleared (`null`). The pose change event still fires and can cancel a
  /// change.
  void overridePose(EntityPose? pose) => unwrapHost(
    generated.entityFlags.setPoseOverride(entity: this, pose: pose),
    'Overriding the entity pose',
  );
}

/// Flags and overrides of players, fake players included.
extension PlayerFlagsApi on Player {
  /// Sets [flag]. Throws a [HostException] on failure.
  void setPlayerFlag(EntityFlag flag, bool value) => unwrapHost(
    generated.entityFlags.setPlayerFlag(player: this, key: flag.wireName, value: value),
    'Setting ${flag.wireName}',
  );

  /// Whether [flag] is set.
  bool hasPlayerFlag(EntityFlag flag) => unwrapHost(
    generated.entityFlags.getPlayerFlag(player: this, key: flag.wireName),
    'Reading ${flag.wireName}',
  );

  /// Sets how far the box that picks up items reaches around the bounding box
  /// of the player on the x, y and z axis (vanilla: `(1.0, 0.5, 1.0)`); `null`
  /// goes back to vanilla.
  void overridePickupBox((double, double, double)? reach) => unwrapHost(
    generated.entityFlags.setPickupBoxOverride(player: this, reach: reach),
    'Overriding the pickup box',
  );
}

/// Opt-in item entity updates.
extension ItemEntityTickingApi on Context {
  /// Makes the item entities of [itemKey] (like `minecraft:stick`) fire
  /// `Events.entityItemUpdate` every [interval] ticks, 0 stops it. Applies to
  /// every plugin that listens. Returns false when no item has the key.
  bool tickItemEntities(String itemKey, {required int interval}) =>
      generated.entityFlags.setItemEntityTicking(itemKey: itemKey, interval: interval);
}
