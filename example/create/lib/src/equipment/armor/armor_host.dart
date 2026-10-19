// Armor behaviour (server side): diving helmet and boots, netherite diving set, cardboard
// armor stealth, the armor attributes the host cannot register on items, and the goggles
// predicate. Ports `DivingHelmetItem`, `DivingBootsItem`, `NetheriteDivingHandler`,
// `CardboardArmorHandler`, `GogglesItem` and `AllArmorMaterials`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/equipment.dart';
import '../../core/module.dart';
import '../host/env.dart';
import 'backtank_host.dart';

/// Armor stats of one piece: the attribute values `ArmorMaterial.createAttributes` gives.
final class ArmorStats {
  final EquipmentSlot slot;
  final double armor;
  final double toughness;
  final double knockbackResistance;
  const ArmorStats(this.slot, this.armor, {this.toughness = 0, this.knockbackResistance = 0});
}

/// `AllArmorMaterials.COPPER` / `CARDBOARD` and vanilla netherite for the netherite diving gear.
const Map<String, ArmorStats> armorTable = {
  'create:copper_diving_helmet': ArmorStats(EquipmentSlot.head, 2),
  'create:copper_diving_boots': ArmorStats(EquipmentSlot.feet, 1),
  'create:copper_backtank': ArmorStats(EquipmentSlot.chest, 4),
  'create:netherite_diving_helmet': ArmorStats(EquipmentSlot.head, 3, toughness: 3, knockbackResistance: 0.1),
  'create:netherite_diving_boots': ArmorStats(EquipmentSlot.feet, 3, toughness: 3, knockbackResistance: 0.1),
  'create:netherite_backtank': ArmorStats(EquipmentSlot.chest, 8, toughness: 3, knockbackResistance: 0.1),
  'create:cardboard_helmet': ArmorStats(EquipmentSlot.head, 1),
  'create:cardboard_chestplate': ArmorStats(EquipmentSlot.chest, 1),
  'create:cardboard_leggings': ArmorStats(EquipmentSlot.legs, 1),
  'create:cardboard_boots': ArmorStats(EquipmentSlot.feet, 1),
};

/// What a player wears / holds, kept from `livingEquipmentChange` so per-tick handlers do
/// not need host calls while nothing relevant is equipped.
final class WornGear {
  String head = '', chest = '', legs = '', feet = '', main = '', off = '';
  bool chestHasAir = false;

  bool get cardboardSet =>
      EqItems.isCardboardArmor(head) &&
      EqItems.isCardboardArmor(chest) &&
      EqItems.isCardboardArmor(legs) &&
      EqItems.isCardboardArmor(feet);

  void set(String slot, String key) {
    switch (slot) {
      case 'head':
        head = key;
      case 'chest':
        chest = key;
      case 'legs':
        legs = key;
      case 'feet':
        feet = key;
      case 'mainhand':
        main = key;
      case 'offhand':
        off = key;
    }
  }
}

Entity? findEntity(Server server, int id) {
  for (final w in server.getAllWorlds()) {
    final e = w.getEntityById(id: id);
    if (e != null) return e;
  }
  return null;
}

final class ArmorHost implements GogglesApi, CardboardArmorApi {
  final EquipmentEnv env;
  final BacktankHost backtanks;
  final Map<String, WornGear> gear = {};
  final List<Future<bool> Function(Player)> _gogglePredicates = [];

  ArmorHost(this.env, this.backtanks);

  WornGear gearOf(String uuid) => gear.putIfAbsent(uuid, WornGear.new);

  void install(CreateContext ctx) {
    ctx.listen(Events.playerJoin, _onJoin);
    ctx.listen(Events.playerLeave, (server, e) => gear.remove(e.player.getId().asString));
    ctx.listen(Events.livingEquipmentChange, _onEquipmentChange);
    ctx.host.intercept(Events.livingBreathe, _onBreathe);
    ctx.listen(Events.playerTick, _onPlayerTick);
    ctx.host.intercept(Events.entityFluidMovement, _onFluidMovement);
    ctx.host.intercept(Events.livingVisibility, _onVisibility);
    ctx.host.intercept(Events.entitySize, _onSize);
    ctx.host.intercept(Events.entityTarget, _onTarget);
    ctx.listen(Events.playerToggleSneak, _onSneak);
    _gogglePredicates.add((p) async => await stackKey(p.getInventory().getHelmet()) == EqItems.goggles);
  }

  // -- GogglesApi ---------------------------------------------------------------------

  @override
  Future<bool> isWearingGoggles(Player player) async {
    for (final p in _gogglePredicates) {
      if (await p(player)) return true;
    }
    return false;
  }

  @override
  void addIsWearingPredicate(Future<bool> Function(Player player) predicate) => _gogglePredicates.add(predicate);

  // -- Worn gear + attributes ---------------------------------------------------------

  Future<void> _onJoin(Server server, PlayerJoinEventData e) async {
    final player = e.player;
    final g = gearOf(player.getId().asString);
    final inv = player.getInventory();
    g.head = await stackKey(inv.getHelmet());
    g.chest = await stackKey(inv.getChestplate());
    g.legs = await stackKey(inv.getLeggings());
    g.feet = await stackKey(inv.getBoots());
    g.main = await stackKey(inv.getItemInHand(hand: Hand.right));
    g.off = await stackKey(inv.getItemInHand(hand: Hand.left));
    final living = player.asEntity().asLiving();
    if (living != null) {
      for (final slot in [EquipmentSlot.head, EquipmentSlot.chest, EquipmentSlot.legs, EquipmentSlot.feet]) {
        _applyArmor(living, slot, switch (slot) {
          EquipmentSlot.head => g.head,
          EquipmentSlot.chest => g.chest,
          EquipmentSlot.legs => g.legs,
          _ => g.feet,
        });
      }
      final chest = living.getEquipment(slot: EquipmentSlot.chest);
      g.chestHasAir = chest != null && await backtanks.hasAirRemaining(chest);
      await _refreshNetherite(player.asEntity(), g);
    }
  }

  void _applyArmor(LivingEntity living, EquipmentSlot slot, String key) {
    final id = 'create:armor_${slot.wireName}';
    for (final attr in const [Attribute.armor, Attribute.armorToughness, Attribute.knockbackResistance]) {
      living.removeAttributeModifier(attr: attr, id: id);
    }
    final stats = armorTable[key];
    if (stats == null || stats.slot != slot) return;
    if (stats.armor != 0) {
      living.addAttributeModifier(
        attr: Attribute.armor,
        modifier: AttributeModifier(id: id, amount: stats.armor, operation: ModifierOperation.add),
      );
    }
    if (stats.toughness != 0) {
      living.addAttributeModifier(
        attr: Attribute.armorToughness,
        modifier: AttributeModifier(id: id, amount: stats.toughness, operation: ModifierOperation.add),
      );
    }
    if (stats.knockbackResistance != 0) {
      living.addAttributeModifier(
        attr: Attribute.knockbackResistance,
        modifier: AttributeModifier(id: id, amount: stats.knockbackResistance, operation: ModifierOperation.add),
      );
    }
  }

  Future<void> _onEquipmentChange(Server server, LivingEquipmentChangeEventData e) async {
    final entity = findEntity(server, e.entityId);
    if (entity == null) return;
    final key = await stackKey(e.newStack);
    final living = entity.asLiving();
    final uuid = entity.getUuid().asString;
    final g = gearOf(uuid);
    g.set(e.slot, key);
    if (living != null) {
      switch (e.slot) {
        case 'head':
          _applyArmor(living, EquipmentSlot.head, key);
        case 'chest':
          _applyArmor(living, EquipmentSlot.chest, key);
          g.chestHasAir = EqItems.isBacktank(key) && await backtanks.hasAirRemaining(e.newStack);
        case 'legs':
          _applyArmor(living, EquipmentSlot.legs, key);
        case 'feet':
          _applyArmor(living, EquipmentSlot.feet, key);
          // Netherite boots swim in lava: ask for the fluid movement events.
          try {
            entity.setFlag(EntityFlag.fluidMovementEvents, key == EqItems.netheriteDivingBoots);
          } on Object {
            // permission `entity-flags` missing: lava walking is off
          }
      }
    }
    if (const {'head', 'chest', 'legs', 'feet'}.contains(e.slot)) await _refreshNetherite(entity, g);
  }

  /// `NetheriteDivingHandler`: the full netherite set (diving helmet, netherite backtank with
  /// air, netherite legs and boots) makes the wearer fire immune.
  Future<void> _refreshNetherite(Entity entity, WornGear g) async {
    final living = entity.asLiving();
    if (living == null) return;
    var full = EqItems.isNetheriteArmor(g.head) &&
        EqItems.isNetheriteArmor(g.chest) &&
        g.chestHasAir &&
        await _isNetheriteArmor(living.getEquipment(slot: EquipmentSlot.legs)) &&
        await _isNetheriteArmor(living.getEquipment(slot: EquipmentSlot.feet));
    if (g.head != EqItems.netheriteDivingHelmet) full = false;
    try {
      entity.setFlag(EntityFlag.fireImmune, full);
    } on Object {
      // permission `entity-flags` missing
    }
  }

  /// `isNetheriteArmor`: an equippable in a humanoid armor slot with damage resistance.
  Future<bool> _isNetheriteArmor(ItemStack? stack) async {
    if (stack == null) return false;
    var equippable = false;
    var resistant = false;
    for (final c in await stack.getComponents()) {
      if (c.component == DataComponent.equippable) equippable = true;
      if (c.component == DataComponent.damageResistant) resistant = true;
    }
    if (equippable && resistant) return true;
    final key = await stack.getRegistryKey();
    return key.startsWith('minecraft:netherite_') && const ['_helmet', '_chestplate', '_leggings', '_boots'].any(key.endsWith);
  }

  // -- Diving helmet ------------------------------------------------------------------

  /// `DivingHelmetItem.breatheUnderwater`: a worn helmet and a backtank with air let the
  /// wearer breathe; one unit of air is used per second.
  Future<LivingBreatheEventData> _onBreathe(Server server, LivingBreatheEventData e) async {
    if (!e.submerged) return e;
    final entity = findEntity(server, e.entityId);
    if (entity == null) return e;
    final g = gear[entity.getUuid().asString];
    if (g == null || !EqItems.isDivingHelmet(g.head)) return e;
    final living = entity.asLiving();
    if (living == null) return e;
    final tanks = await backtanks.getAllWithAir(living);
    if (tanks.isEmpty) return e;
    final world = entity.getWorld();
    if (world.getWorldAge() % 20 == 0) {
      final player = server.getPlayerByUuid(id: entity.getUuid());
      await backtanks.consumeAir(living, tanks.first, 1, player: player);
      if (player != null) {
        await env.award(player, 'diving_suit');
      }
    }
    // setCanBreathe(true); setRefillAirAmount(getMaxAirSupply()): refill to the maximum.
    final max = entity.getMaxAir();
    return e.copyWith(airChange: max - e.air);
  }

  // -- Per tick -----------------------------------------------------------------------

  Future<void> _onPlayerTick(Server server, PlayerTickEventData e) async {
    final player = e.player;
    final g = gear[player.getId().asString];
    if (g == null) return;
    if (EqItems.isDivingBoots(g.feet)) await _divingBootsTick(player);
    // Lava diving with the netherite set consumes air like water breathing.
    if (g.head == EqItems.netheriteDivingHelmet && g.chest == EqItems.netheriteBacktank) {
      final entity = player.asEntity();
      if (entity.isInLava() && player.getWorld().getWorldAge() % 20 == 0) {
        final living = entity.asLiving();
        if (living != null) {
          final tanks = await backtanks.getAllWithAir(living);
          if (tanks.isNotEmpty) {
            await backtanks.consumeAir(living, tanks.first, 1, player: player);
            await env.award(player, 'diving_suit_lava');
          }
        }
      }
    }
  }

  /// `DivingBootsItem.accelerateDescentUnderwater`: heavy boots sink faster and move faster
  /// on the bottom. The jump input (`entity.jumping`) is not available on the server, so the
  /// jump boost is not reproduced; the horizontal boost uses the horizontal speed as input.
  Future<void> _divingBootsTick(Player player) async {
    final entity = player.asEntity();
    if (!entity.isInWater()) return;
    if (entity.getPose() == EntityPose.swimming) return;
    if (player.getAbilities().flying) return;
    final (vx, vy, vz) = entity.getVelocity();
    var mx = vx, my = vy, mz = vz;
    my -= 0.05 * 1.0000000149011612; // `-0.05f`
    final horizontal = (mx * mx + mz * mz);
    if (horizontal > 1.0e-4 && horizontal < 0.145 * 0.145 && !entity.isSneaking()) {
      const multiplier = 1.2999999523162842; // `1.3f`
      mx *= multiplier;
      mz *= multiplier;
    }
    player.setVelocity(velocity: (mx, my, mz));
  }

  /// `DivingBootsItem.getMovementMultiplier` applied by `LavaSwimmingMixin` for netherite boots.
  Future<EntityFluidMovementEventData> _onFluidMovement(Server server, EntityFluidMovementEventData e) async {
    if (e.fluid != 'minecraft:lava') return e;
    final entity = findEntity(server, e.entityId);
    if (entity == null) return e;
    final g = gear[entity.getUuid().asString];
    if (g == null || g.feet != EqItems.netheriteDivingBoots) return e;
    final (vx, vy, vz) = e.velocity;
    final onGround = entity.isOnGround();
    double vMult = vy < 0 ? (2.5 - vy.abs() * 2 < 0 ? 0 : 2.5 - vy.abs() * 2) : 1;
    double hMult;
    if (!onGround) {
      if (vy > 0) vMult = 1.3;
      hMult = 1.75;
    } else {
      hMult = entity.isSprinting() ? 1.85 : 1.75;
    }
    return e.copyWith(velocity: (vx * hMult, vy * vMult, vz * hMult));
  }

  // -- Cardboard armor ----------------------------------------------------------------

  @override
  Future<bool> testForStealth(Entity? entity) async {
    if (entity == null) return false;
    final g = gear[entity.getUuid().asString];
    if (g == null || !g.cardboardSet) return false;
    if (entity.getPose() != EntityPose.crouching) return false;
    final player = _playerOf(entity);
    if (player != null && player.getAbilities().flying) return false;
    return true;
  }

  /// The online player behind [entity] (the payload bus keeps the roster alive).
  Player? _playerOf(Entity entity) {
    final uuid = entity.getUuid().asString;
    for (final p in env.bus.roster.players) {
      if (p.getId().asString == uuid) return p;
    }
    return null;
  }

  /// `playersStealthWhenWearingCardboard`.
  Future<LivingVisibilityEventData> _onVisibility(Server server, LivingVisibilityEventData e) async {
    final entity = findEntity(server, e.entityId);
    if (entity == null) return e;
    if (!await testForStealth(entity)) return e;
    return e.copyWith(multiplier: 0);
  }

  /// `playerHitboxChangesWhenHidingAsBox`: a hiding player is a 0.6 x 0.8 box.
  Future<EntitySizeEventData> _onSize(Server server, EntitySizeEventData e) async {
    if (e.pose != 'crouching') return e;
    final entity = findEntity(server, e.entityId);
    if (entity == null) return e;
    if (!await testForStealth(entity)) return e;
    final living = entity.asLiving();
    final scale = living == null ? 1.0 : living.getAttributeValue(attr: Attribute.scale);
    final player = server.getPlayerByUuid(id: entity.getUuid());
    if (player != null) unawaited(env.award(player, 'cardboard_armor'));
    return e.copyWith(width: 0.6 * scale, height: 0.8 * scale, eyeHeight: 0.6 * scale);
  }

  /// `mobsMayLoseTargetWhenItIsWearingCardboard`: mobs cannot pick a hiding player as target.
  Future<EntityTargetEventData> _onTarget(Server server, EntityTargetEventData e) async {
    final id = e.targetId;
    if (id == null) return e;
    final target = findEntity(server, id);
    if (target == null || !await testForStealth(target)) return e;
    return e.cancel();
  }

  /// A mob that already targets a player who starts hiding forgets them.
  Future<void> _onSneak(Server server, PlayerToggleSneakEventData e) async {
    final player = e.player;
    final g = gear[player.getId().asString];
    if (g == null || !g.cardboardSet || !e.isSneaking) return;
    final entity = player.asEntity();
    final myId = entity.getId();
    for (final other in entity.getNearbyEntities(x: 32, y: 16, z: 32)) {
      final mob = other.asMob();
      if (mob == null) continue;
      final target = mob.getTarget();
      if (target != null && target.getId() == myId) mob.setTarget(target: null);
    }
  }
}
