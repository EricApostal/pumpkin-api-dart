// The potato cannon on the host: `PotatoCannonItem.use` (ammo search, volley, cooldown,
// packets) and the flight of `PotatoProjectileEntity` (a plugin entity that the plugin moves
// every tick: gravity, drag, block and entity hits, hit actions).
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/damage.dart';
import '../../api/util.dart';
import '../../contraptions/core/entity_type_keys.dart' show reportedEntityTypeKey;
import '../../core/module.dart';
import '../../core/nbt.dart';
import '../../manifest/manifest.dart';
import '../../protocol/host_item_stack.dart';
import '../armor/armor_host.dart' show findEntity;
import '../armor/backtank_host.dart';
import '../host/env.dart';
import '../host/inventory_util.dart';
import '../host/stack_data.dart';
import '../model/dir.dart';
import '../model/vec.dart';
import '../data/equipment_components.dart';
import 'potato_model.dart';

const String potatoEntityKey = 'create:potato_projectile';

/// One live projectile (the plugin keeps the state, the host entity is only the body).
final class _Projectile {
  final PotatoFlight flight;
  final String itemKey;
  final double recoveryChance;
  final String? ownerUuid;
  final String worldName;
  int? stuckEntityId;
  _Projectile(this.flight, this.itemKey, this.recoveryChance, this.ownerUuid, this.worldName);
}

final class PotatoHost {
  final EquipmentEnv env;
  final BacktankHost backtanks;
  late final PotatoTypes types;
  final Map<int, _Projectile> _live = {};

  PotatoHost(this.env, this.backtanks) {
    types = PotatoTypes([for (final t in kPotatoProjectileTypes) PotatoType.fromJson(t.key, t.rawJson)]);
  }

  static const int maxAge = 20 * 60;

  void install(CreateContext ctx) {
    ctx.host.intercept(Events.playerUseItem, _onUse);
    ctx.listen(Events.entityTick, _onEntityTick);
    try {
      ctx.host.tickPluginEntities(potatoEntityKey, interval: 1);
    } on Object catch (e) {
      env.log.warn('potato projectiles are not ticked: $e');
    }
    ctx.listen(Events.entityRemove, (server, e) => _live.remove(e.entityId));
  }

  PotatoType? typeForItem(String itemKey) => types.forItem(itemKey, inTag: (tag, key) => Tags.item(key, tag));

  // -- PotatoCannonItem.use ----------------------------------------------------------------

  Future<PlayerUseItemEventData> _onUse(Server server, PlayerUseItemEventData e) async {
    if (await stackKey(e.item) != EqItems.potatoCannon) return e;
    final player = e.player;
    final hand = e.hand;
    final inv = player.getInventory();
    final held = inv.getItemInHand(hand: hand);
    if (held == null) return e;
    if (await _shouldSwap(player, held, hand)) return e.cancel();

    final ammo = await _findAmmo(player);
    if (ammo == null) return e;
    final (ammoStack, ammoKey, type, ammoSlot) = ammo;

    final world = player.getWorld();
    final eye = player.eyePosition;
    final yaw = player.getYaw(), pitch = player.getPitch();
    final look = player.lookDirection;
    final mainHand = hand.isMain;
    final barrel = PotatoMath.barrel(eyePos: eye, yRotDeg: yaw, xRotDeg: pitch, mainHand: mainHand, rightArmMain: true);
    final correction = PotatoMath.correction(
      eyePos: eye,
      yRotDeg: yaw,
      xRotDeg: pitch,
      mainHand: mainHand,
      rightArmMain: true,
    );
    final volley = PotatoMath.volley(type: type, lookVec: look, correction: correction, nextFloat: env.rng.nextDouble);
    final recovery = PotatoMath.recoveryChance(await customEnchantLevel(held, 'create:potato_recovery'));

    for (final shot in volley.shots) {
      await _spawnProjectile(world, player, barrel, shot.motion, type, ammoKey, shot.keepsRecovery ? recovery : 0);
    }

    if (!player.isCreative) {
      if (ammoSlot >= 0) await shrinkSlot(inv.asInventory(), ammoSlot, 1);
    }
    final living = player.asEntity().asLiving();
    final free =
        living != null && await backtanks.canAbsorbDamage(living, env.settings.maxPotatoCannonShots, player: player);
    if (!free) await hurtHeld(player, hand, 1);
    await _applyCooldown(player, hand, type.reloadTicks);
    await _sendPackets(player, world, barrel, look.vnorm, ammoStack, hand, volley.soundPitch);
    return e.cancel();
  }

  /// `getAmmo`: `player.getProjectile(cannon)`: the off hand, then the main hand, then the inventory in slot
  /// order; creative players without ammo get an arrow, which is no ammo.
  Future<(ItemStack, String, PotatoType, int)?> _findAmmo(Player player) async {
    final inv = player.getInventory();
    for (final hand in const [Hand.left, Hand.right]) {
      final s = inv.getItemInHand(hand: hand);
      if (s == null) continue;
      final key = await s.getRegistryKey();
      if (key == EqItems.potatoCannon) continue;
      final t = typeForItem(key);
      if (t != null) return (s, key, t, hand.isMain ? inv.getSelectedSlot() : 40);
    }
    final storage = inv.asInventory();
    for (var i = 0; i < storage.getSize(); i++) {
      final s = storage.getItem(slot: i);
      if (s == null) continue;
      final key = await s.getRegistryKey();
      final t = typeForItem(key);
      if (t != null) return (s, key, t, i);
    }
    return null;
  }

  Future<bool> _shouldSwap(Player player, ItemStack item, Hand hand) async {
    final isSwap = StackData.has(item, EquipmentComponents.shaperSwap);
    final mainHand = hand.isMain;
    final inv = player.getInventory();
    final otherStack = inv.getItemInHand(hand: hand.other);
    final gunInOtherHand = otherStack != null && await otherStack.getRegistryKey() == EqItems.potatoCannon;
    if (mainHand && isSwap && gunInOtherHand) return true;
    if (mainHand && !isSwap && gunInOtherHand) StackData.setFlag(item, EquipmentComponents.shaperSwap, true);
    if (!mainHand && isSwap) StackData.remove(item, EquipmentComponents.shaperSwap);
    if (!mainHand && gunInOtherHand) {
      final main = inv.getItemInHand(hand: Hand.right);
      if (main != null) StackData.remove(main, EquipmentComponents.shaperSwap);
    }
    return false;
  }

  Future<void> _applyCooldown(Player player, Hand hand, int cooldown) async {
    if (cooldown <= 0) return;
    final other = player.getInventory().getItemInHand(hand: hand.other);
    final gunInOtherHand = other != null && await other.getRegistryKey() == EqItems.potatoCannon;
    player.setCooldown(EqItems.potatoCannon, gunInOtherHand ? cooldown * 2 ~/ 3 : cooldown);
  }

  Future<void> _sendPackets(
    Player player,
    World world,
    V3 barrel,
    V3 motion,
    ItemStack ammo,
    Hand hand,
    double soundPitch,
  ) async {
    final data = await HostItemStacks.fromHost(ammo, env.itemIds);
    Map<String, Object?> fields(bool self) => {
      'location': barrel,
      'motion': motion,
      'item': data,
      'hand': hand.isMain,
      'pitch': soundPitch,
      'self': self,
    };
    final others = env.bus.playersTracking(world.getId(), barrel.toBlockPos().p3);
    final uuid = player.getId().asString;
    env.bus.sendClientboundAll('create:potato_cannon', [
      for (final p in others)
        if (p.getId().asString != uuid) p,
    ], fields(false));
    env.bus.sendClientbound('create:potato_cannon', player, fields(true));
  }

  // -- Projectile entity -------------------------------------------------------------------

  Future<void> _spawnProjectile(
    World world,
    Player owner,
    V3 pos,
    V3 motion,
    PotatoType type,
    String itemKey,
    double recoveryChance,
  ) async {
    final spawnData = NetworkNbt.encode(
      NbtValue.compound({
        'Item': NbtValue.compound({'id': NbtValue.string(itemKey), 'count': const NbtValue.int32(1)}),
        'AdditionalDamage': const NbtValue.float(1),
        'AdditionalKnockback': const NbtValue.float(0),
        'Recovery': NbtValue.float(recoveryChance),
      }),
    );
    final entity = await world.spawnPlugin(potatoEntityKey, pos, spawnData: spawnData);
    final flight = PotatoFlight(pos, motion, type);
    _live[entity.getId()] = _Projectile(flight, itemKey, recoveryChance, owner.getId().asString, world.getName());
    entity.setVelocity(velocity: motion);
  }

  Future<void> _onEntityTick(Server server, EntityTickEventData e) async {
    if (reportedEntityTypeKey(e.entityType) != potatoEntityKey) return;
    final proj = _live[e.entityId];
    final entity = findEntity(server, e.entityId);
    if (entity == null) {
      _live.remove(e.entityId);
      return;
    }
    if (proj == null) {
      // A projectile from a previous run (saved entity): it has no state, drop it.
      entity.remove();
      return;
    }
    final world = entity.getWorld();
    proj.flight.tickCount++;
    if (proj.flight.tickCount > maxAge) {
      _kill(entity, e.entityId);
      return;
    }
    final stuckId = proj.stuckEntityId;
    if (stuckId != null) {
      final stuck = world.getEntityById(id: stuckId);
      if (stuck == null || stuck.isLiving() && stuck.asLiving()!.isDead()) {
        _kill(entity, e.entityId);
        return;
      }
      final next = proj.flight.stepStuck(stuck.getPosition());
      if (next == null) {
        _pop(world, proj.flight.pos);
        _kill(entity, e.entityId);
      } else {
        proj.flight.pos = next;
        entity.setPositionRotationDelta(pos: next, yaw: entity.getYaw(), pitch: entity.getPitch(), velocity: vzero);
      }
      return;
    }

    final start = proj.flight.pos;
    final step = proj.flight.stepFree();
    final end = start.vplus(step);

    // Nearest hit along the segment: entity (not itself) or block.
    final blockHit = world.rayTraceBlock(start: start, end: end, includeFluids: false);
    final blockDist = blockHit == null ? double.infinity : start.vdist(blockHit.hitPos);
    RayTraceEntityResult? entityHit;
    for (final r in world.rayTraceEntities(start: start, end: end)) {
      final id = r.entity.getId();
      if (id == e.entityId) continue;
      // `if (tickCount < 10 && target.tickCount < 10) return;`: projectiles of the same volley
      // pass through each other while both are fresh.
      final other = _live[id];
      if (other != null && proj.flight.tickCount < 10 && other.flight.tickCount < 10) continue;
      if (r.entity.isItem()) continue;
      if (entityHit == null || r.distance < entityHit.distance) entityHit = r;
    }
    if (entityHit != null && entityHit.distance <= blockDist) {
      await _onHitEntity(server, world, entity, proj, entityHit);
      return;
    }
    if (blockHit != null) {
      await _onHitBlock(server, world, entity, proj, blockHit);
      return;
    }
    proj.flight.pos = end;
    final (yaw, pitch) = _rotationOf(step);
    entity.setPositionRotationDelta(pos: end, yaw: yaw, pitch: pitch, velocity: proj.flight.motion);
  }

  (double, double) _rotationOf(V3 d) {
    final h = math.sqrt(d.$1 * d.$1 + d.$3 * d.$3);
    final yaw = math.atan2(-d.$1, d.$3) * 180 / math.pi;
    final pitch = -math.atan2(d.$2, h) * 180 / math.pi;
    return (yaw, pitch);
  }

  void _kill(Entity entity, int id) {
    _live.remove(id);
    entity.remove();
  }

  void _pop(World world, V3 pos) {
    env.playSoundAtBlock(world, pos.toBlockPos().p3, 'potato_hit');
  }

  /// `onHitBlock`.
  Future<void> _onHitBlock(Server server, World world, Entity entity, _Projectile proj, RayTraceBlockResult hit) async {
    final type = proj.flight.type;
    _pop(world, hit.hitPos);
    final handled = await _blockHitAction(world, type.onBlockHit, hit);
    if (!handled) {
      await _dropOrRecover(world, proj, hit.hitPos);
    }
    _kill(entity, entity.getId());
  }

  Future<void> _dropOrRecover(World world, _Projectile proj, V3 at) async {
    if (env.rng.nextDouble() <= proj.recoveryChance) {
      final stack = ItemStack.create(registryKey: proj.itemKey, count: 1);
      await world.dropItem(at, stack);
    } else {
      final drop = proj.flight.type.dropStack;
      if (drop != null) await world.dropItem(at, ItemStack.create(registryKey: drop, count: 1));
    }
  }

  Future<bool> _blockHitAction(World world, PotatoBlockHitAction? action, RayTraceBlockResult hit) async {
    if (action == null) return false;
    final hitPos = hit.pos;
    if (!world.isLoaded(pos: hitPos)) return true;
    final face = hit.face.dir;
    switch (action) {
      case PlantCrop(:final cropBlock):
        if (face != Dir.up) return false;
        final place = hitPos.p3.rel(face).blockPos;
        if (!world.getBlockState(pos: place).replaceable) return false;
        // `SpecialPlantable.canPlacePlantAtPosition`: crops need farmland below.
        final below = world.getBlockState(pos: place.p3.down1.blockPos);
        if (namespacedBlockKey(below.blockName) == 'minecraft:farmland') {
          final id = BlockStates.defaultOf(cropBlock);
          if (id != null) await world.setBlockState(pos: place, state: id, updateFlags: BlockUpdateFlags.normal);
        }
        return true;
      case PlaceBlockOnGround(:final block):
        final place = hitPos.p3.rel(face).blockPos;
        if (!world.getBlockState(pos: place).replaceable) return false;
        final id = BlockStates.defaultOf(block);
        if (id == null) return false;
        var target = place;
        if (face != Dir.up) {
          // The Java action spawns a falling block; drop it down to the first solid support instead.
          var y = place.y;
          while (y > world.getMinY() + 1) {
            final under = world.getBlockState(
              pos: BlockPos(x: place.x, y: y - 1, z: place.z),
            );
            if (!under.replaceable) break;
            y--;
          }
          target = BlockPos(x: place.x, y: y, z: place.z);
        }
        await world.setBlockState(pos: target, state: id, updateFlags: BlockUpdateFlags.normal);
        return true;
    }
  }

  /// `onHitEntity`.
  Future<void> _onHitEntity(
    Server server,
    World world,
    Entity entity,
    _Projectile proj,
    RayTraceEntityResult hit,
  ) async {
    final type = proj.flight.type;
    final target = hit.entity;
    final living = target.asLiving();
    final targetId = target.getId();
    final targetType = target.getType();
    if (living != null && living.isDead()) return;

    // Two projectiles colliding: the advancement when different types hit each other, and the
    // target projectile is destroyed (`PotatoProjectileEntity.hurtServer`).
    final otherProj = _live[targetId];
    if (otherProj != null) {
      if (proj.flight.tickCount < 10 && otherProj.flight.tickCount < 10) return;
      if (otherProj.flight.type != type) {
        for (final uuid in [proj.ownerUuid, otherProj.ownerUuid]) {
          if (uuid == null) continue;
          final p = server.getPlayerByUuid(id: Uuids.parse(uuid));
          if (p != null) await env.award(p, 'potato_cannon_collide');
        }
      }
      _kill(target, targetId);
    }
    _pop(world, hit.hitPos);
    if (type.preEntityHit != null) {
      // `if (type.preEntityHit(stack, ray)) return;`: a consuming pre-hit action stops the hit.
      final consumed = await _entityHitAction(server, world, proj, target, living, type.preEntityHit!);
      if (consumed) return;
    }
    final isEnderman = targetType == EntityType.enderman;
    final damage = PotatoMath.damage(type, 1);
    final knockback = PotatoMath.knockback(type, 0);
    final owner = proj.ownerUuid == null ? null : server.getPlayerByUuid(id: Uuids.parse(proj.ownerUuid!));

    if (living != null) {
      await CreateDamage.potatoCannon.hurt(living, damage);
    } else {
      // Non living targets (item frames, minecarts) take no damage through the host API.
    }
    if (isEnderman) return;
    var consumed = false;
    if (type.onEntityHit != null) {
      consumed = await _entityHitAction(server, world, proj, target, living, type.onEntityHit!);
    }
    if (!consumed) {
      await _dropOrRecover(world, proj, hit.hitPos);
    }
    if (living == null) {
      _kill(entity, entity.getId());
      return;
    }
    if (knockback > 0) {
      final k = knockbackVelocity(
        strength: knockback,
        projectileMotion: proj.flight.motion,
        current: target.getVelocity(),
        onGround: target.isOnGround(),
        knockbackResistance: living.getAttributeValue(attr: Attribute.knockbackResistance),
      );
      if (k != null) {
        target.setVelocity(velocity: k);
      }
    }
    if (owner != null) {
      final killedMob = living.isDead() && target.isMob();
      final otherPlayer = targetType == EntityType.player && target.getUuid().asString != proj.ownerUuid;
      if (killedMob || otherPlayer) await env.award(owner, 'potato_cannon');
    }
    if (type.sticky && !living.isDead()) {
      proj.flight.stickTo(target.getPosition());
      // Re-base the offset on the hit position, `position() - target.position()`.
      proj.flight.stuckOffset = proj.flight.pos.vminus(target.getPosition());
      proj.stuckEntityId = targetId;
      entity.setPositionRotationDelta(
        pos: proj.flight.pos,
        yaw: entity.getYaw(),
        pitch: entity.getPitch(),
        velocity: vzero,
      );
    } else {
      _kill(entity, entity.getId());
    }
  }

  /// Runs a hit action; returns true when it consumed the item (no drop / recovery).
  Future<bool> _entityHitAction(
    Server server,
    World world,
    _Projectile proj,
    Entity target,
    LivingEntity? living,
    PotatoEntityHitAction action,
  ) async {
    switch (action) {
      case SetOnFire(:final ticks):
        target.setFireTicks(ticks: ticks);
        return false;
      case PotionEffectAction():
        final player = server.getPlayerByUuid(id: target.getUuid());
        if (living != null && player != null) {
          final t = StatusEffectType.fromWireName(action.effect.replaceFirst('minecraft:', '').replaceAll('_', '-'));
          if (t != null) {
            await player.addEffect(
              effect: StatusEffectInstance(
                effectType: t,
                duration: action.ticks,
                amplifier: action.level - 1,
                ambient: false,
                showParticles: true,
                showIcon: true,
              ),
            );
          }
        }
        return !action.recoverable;
      case FoodEffectsAction():
        final player = server.getPlayerByUuid(id: target.getUuid());
        if (living != null && player != null) {
          for (final fe in action.effects) {
            if (env.rng.nextDouble() < fe.probability) await _applyFoodEffect(player, fe.effect);
          }
        }
        return !action.recoverable;
      case ChorusTeleport(:final teleportDiameter):
        if (living == null) return false;
        return _chorusTeleport(world, target, teleportDiameter);
      case CureZombieVillager():
        // Needs `ZombieVillager.mobInteract` with a fake player holding a golden apple; the
        // effects of the golden apple are applied to other targets as in Java.
        final player = server.getPlayerByUuid(id: target.getUuid());
        if (player != null) {
          await _applyFoodEffect(player, {'id': 'minecraft:regeneration', 'duration': 100, 'amplifier': 1});
          await _applyFoodEffect(player, {'id': 'minecraft:absorption', 'duration': 2400, 'amplifier': 0});
        }
        return false;
      case SuspiciousStewAction():
        // The stew effects live in a vanilla component of the ammo stack; not readable here.
        return false;
    }
  }

  Future<void> _applyFoodEffect(Player player, Map<String, Object?> effect) async {
    final id = (effect['id'] as String).replaceFirst('minecraft:', '').replaceAll('_', '-');
    final t = StatusEffectType.fromWireName(id);
    if (t == null) return;
    await player.addEffect(
      effect: StatusEffectInstance(
        effectType: t,
        duration: (effect['duration'] as num?)?.toInt() ?? 600,
        amplifier: (effect['amplifier'] as num?)?.toInt() ?? 0,
        ambient: effect['ambient'] as bool? ?? false,
        showParticles: effect['show_particles'] as bool? ?? true,
        showIcon: effect['show_icon'] as bool? ?? true,
      ),
    );
  }

  /// `ChorusTeleport`: up to 16 random spots within the diameter; the first with room is used.
  Future<bool> _chorusTeleport(World world, Entity target, double diameter) async {
    final (ex, ey, ez) = target.getPosition();
    for (var i = 0; i < 16; i++) {
      final tx = ex + (env.rng.nextDouble() - 0.5) * diameter;
      final ty = (ey + (env.rng.nextInt(diameter.toInt()) - (diameter / 2).toInt())).clamp(
        0.0,
        world.getMinY() + 384 - 1.0,
      );
      final tz = ez + (env.rng.nextDouble() - 0.5) * diameter;
      final feet = BlockPos(x: tx.floor(), y: ty.floor(), z: tz.floor());
      if (!world.isLoaded(pos: feet)) continue;
      final here = world.getBlockState(pos: feet);
      final above = world.getBlockState(pos: feet.p3.up1.blockPos);
      final below = world.getBlockState(pos: feet.p3.down1.blockPos);
      if (here.isSolid || above.isSolid || !below.isSolid) continue;
      await target.teleport(pos: (tx, ty, tz), worldRef: world);
      target.setVelocity(velocity: vzero);
      env.playSound(world, (ex, ey, ez), 'chorus_teleport');
      return true;
    }
    return false;
  }
}
