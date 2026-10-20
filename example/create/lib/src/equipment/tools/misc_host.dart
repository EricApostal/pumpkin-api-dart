// Small equipment items on the host: the extendo grip (reach, wear, knockback, long range
// attacks), the sand paper (polishing, scraping, wax removal), the cardboard sword, the
// builder's tea and the tree fertilizer.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/equipment.dart';
import '../../api/util.dart';
import '../../core/module.dart';
import '../../protocol/item_stack.dart';
import '../armor/armor_host.dart';
import '../armor/backtank_host.dart';
import '../data/equipment_components.dart';
import '../host/env.dart';
import '../host/inventory_util.dart';
import '../host/stack_data.dart';
import '../model/knockback.dart';
import 'copper_stages.dart';

final class MiscItemsHost implements ExtendoGripApi, SandPaperApi {
  final EquipmentEnv env;
  final ArmorHost armor;
  final BacktankHost backtanks;

  MiscItemsHost(this.env, this.armor, this.backtanks);

  // -- shared ----------------------------------------------------------------------------

  int _tick = 0;

  void install(CreateContext ctx) {
    ctx.onWorldTick((t) => _tick = t.tick);
    ctx.listen(Events.playerItemHeld, _onItemHeld);
    ctx.listen(Events.blockBreak, _onBlockBreak);
    ctx.listen(Events.blockPlace, _onBlockPlace);
    ctx.listen(Events.playerJoin, (server, e) => unawaited(_refreshReach(e.player)));
    ctx.listen(Events.playerLeave, (server, e) => _reach.remove(e.player.getId().asString));
    ctx.listen(Events.livingEquipmentChange, _onEquipmentChange);
    ctx.host.intercept(Events.entityKnockbackByEntity, _onKnockback);
    ctx.listen(Events.entityDamageByEntity, _onDamageByEntity);
    env.bus.onServerbound('create:extendo_interact', _onExtendoInteract);

    // sand paper
    ctx.host.intercept(Events.itemUseFirst, _onUseFirst);
    ctx.host.intercept(Events.playerUseItem, _onUseItem);
    ctx.listen(Events.itemUseTick, _onUseTick);
    ctx.listen(Events.playerTick, _onPlayerTick);

    // cardboard sword
    ctx.host.intercept(Events.playerInteract, _onInteract);
    ctx.host.intercept(Events.playerInteractEntity, _onInteractEntity);
  }

  // ===================================================================================
  // Extendo grip
  // ===================================================================================

  static const singleRangeId = 'create:single_range_attribute_modifier';
  static const doubleRangeId = 'create:double_range_attribute_modifier';

  /// 0 none, 1 single, 2 dual: what the reach attribute currently holds per player.
  final Map<String, int> _reach = {};

  Future<void> _onItemHeld(Server server, PlayerItemHeldEventData e) async {
    final player = e.player;
    final g = armor.gearOf(player.getId().asString);
    final stack = player.getInventory().asInventory().getItem(slot: e.newSlot);
    g.main = await stackKey(stack);
    await _refreshReach(player, mainOverride: g.main);
  }

  Future<void> _onEquipmentChange(Server server, LivingEquipmentChangeEventData e) async {
    if (e.slot != 'mainhand' && e.slot != 'offhand') return;
    final entity = findEntity(server, e.entityId);
    if (entity == null) return;
    final player = server.getPlayerByUuid(id: entity.getUuid());
    if (player == null) return;
    // ArmorHost updated the gear map first (registered earlier).
    await _refreshReach(player);
  }

  /// `holdingExtendoGripIncreasesRange`: +3 block reach with one grip, +5 with two.
  Future<void> _refreshReach(Player player, {String? mainOverride}) async {
    final uuid = player.getId().asString;
    final g = armor.gearOf(uuid);
    final inv = player.getInventory();
    final main = mainOverride ?? g.main.ifEmpty(await stackKey(inv.getItemInHand(hand: Hand.right)));
    final off = g.off.ifEmpty(await stackKey(inv.getItemInHand(hand: Hand.left)));
    final inMain = main == EqItems.extendoGrip, inOff = off == EqItems.extendoGrip;
    final dual = inMain && inOff;
    final single = (inMain != inOff) && !dual;
    final wanted = dual ? 2 : (single ? 1 : 0);
    final had = _reach[uuid] ?? 0;
    if (wanted == had) return;
    final living = player.asEntity().asLiving();
    if (living == null) return;
    if (had == 1) living.removeAttributeModifier(attr: Attribute.blockInteractionRange, id: singleRangeId);
    if (had == 2) living.removeAttributeModifier(attr: Attribute.blockInteractionRange, id: doubleRangeId);
    if (wanted == 1) {
      living.addAttributeModifier(
        attr: Attribute.blockInteractionRange,
        modifier: AttributeModifier(id: singleRangeId, amount: 3, operation: ModifierOperation.add),
      );
      await env.award(player, 'extendo_grip');
    } else if (wanted == 2) {
      living.addAttributeModifier(
        attr: Attribute.blockInteractionRange,
        modifier: AttributeModifier(id: doubleRangeId, amount: 5, operation: ModifierOperation.add),
      );
      await env.award(player, 'extendo_grip_dual');
    }
    _reach[uuid] = wanted;
  }

  @override
  Future<bool> isHoldingExtendoGrip(Player player) async {
    final inv = player.getInventory();
    return await stackKey(inv.getItemInHand(hand: Hand.left)) == EqItems.extendoGrip ||
        await stackKey(inv.getItemInHand(hand: Hand.right)) == EqItems.extendoGrip;
  }

  /// `findAndDamageExtendoGrip`: a grip in the main (else off) hand wears out unless a
  /// backtank pays for the action.
  Future<void> _damageExtendoGrip(Player player) async {
    final inv = player.getInventory();
    var hand = Hand.right;
    var grip = inv.getItemInHand(hand: hand);
    if (grip == null || await grip.getRegistryKey() != EqItems.extendoGrip) {
      hand = Hand.left;
      grip = inv.getItemInHand(hand: hand);
      if (grip == null || await grip.getRegistryKey() != EqItems.extendoGrip) return;
    }
    final living = player.asEntity().asLiving();
    if (living != null && await backtanks.canAbsorbDamage(living, env.settings.maxExtendoGripActions, player: player)) {
      return;
    }
    if (player.isCreative) return;
    await hurtHeld(player, hand, 1);
  }

  Future<void> _onBlockBreak(Server server, BlockBreakEventData e) async {
    final player = e.player;
    if (player == null) return;
    await _damageExtendoGrip(player);
  }

  Future<void> _onBlockPlace(Server server, BlockPlaceEventData e) async => _damageExtendoGrip(e.player);

  Future<void> _onDamageByEntity(Server server, EntityDamageByEntityEventData e) async {
    final damager = findEntity(server, e.damagerId);
    if (damager == null) return;
    final player = server.getPlayerByUuid(id: damager.getUuid());
    if (player != null) await _damageExtendoGrip(player);
  }

  /// `attacksByExtendoGripHaveMoreKnockback`: +2 strength.
  Future<EntityKnockbackByEntityEventData> _onKnockback(Server server, EntityKnockbackByEntityEventData e) async {
    final hitBy = findEntity(server, e.hitById);
    if (hitBy == null) return e;
    final player = server.getPlayerByUuid(id: hitBy.getUuid());
    if (player == null || !await isHoldingExtendoGrip(player)) return e;
    return e.copyWith(force: e.force + 2);
  }

  /// `ExtendoGripInteractionPacket`: attacks (and interactions) beyond the server's 6 block limit.
  void _onExtendoInteract(Player player, Map<String, Object?> f) {
    final targetId = f['target'] as int;
    final hand = f['hand'] as bool?;
    unawaited(() async {
      if (!await isHoldingExtendoGrip(player)) return;
      final world = player.getWorld();
      final target = world.getEntityById(id: targetId);
      if (target == null) return;
      final living = player.asEntity().asLiving();
      var range = living?.getAttributeValue(attr: Attribute.blockInteractionRange) ?? 4.5;
      final eye = player.eyePosition;
      final targetEye = target.getPosition() + (0.0, target.getEyeHeight(), 0.0);
      final block = world.rayTraceBlock(start: eye, end: targetEye, includeFluids: false);
      final hasLineOfSight = block == null || eye.distanceTo(block.hitPos) >= eye.distanceTo(targetEye) - 0.01;
      if (!hasLineOfSight) range -= 3;
      final d = eye.distanceSquaredTo(target.getPosition());
      if (d > range * range) return;
      if (hand == null) {
        // `sender.attack(entity)`: a plain hit with the player's attack damage.
        final tl = target.asLiving();
        if (tl != null && living != null) {
          await tl.damage(amount: living.getAttributeValue(attr: Attribute.attackDamage), damageType: DamageType.playerAttack);
        }
      }
      // Interactions (`interactOn`) cannot be forwarded through the host API.
    }());
  }

  // ===================================================================================
  // Sand paper
  // ===================================================================================

  final Map<String, String> _polishing = {'create:rose_quartz': 'create:polished_rose_quartz'};

  @override
  void addPolishingRecipe(String inputKey, String outputKey) => _polishing[inputKey] = outputKey;

  @override
  String? polishResult(String inputKey) => _polishing[inputKey];

  /// Per player: tick when the polishing started and the last `itemUseTick`.
  final Map<String, (int, int)> _polishUse = {};

  Future<ItemUseFirstEventData> _onUseFirst(Server server, ItemUseFirstEventData e) async {
    final key = await stackKey(e.stack);
    if (!EqItems.isSandPaper(key)) return e;
    final player = e.player;
    final world = player.getWorld();
    final bs = world.getBlockState(pos: e.blockPos);
    int? newId;
    final scraped = CopperStages.previousOxidizedStage(bs.blockName);
    if (scraped != null) {
      newId = _withPropertiesOf(scraped, bs.id);
    } else {
      final unwaxed = CopperStages.unwaxed(bs.blockName);
      if (unwaxed != null) {
        newId = _withPropertiesOf(unwaxed, bs.id);
      }
    }
    if (newId == null) return e;
    env.playSoundAtBlock(world, e.blockPos.p3, 'sanding_long', pitch: 1 + (env.rng.nextDouble() * 0.5 - 1) / 5);
    await world.setBlockState(pos: e.blockPos, state: newId, updateFlags: BlockUpdateFlags.normal);
    await hurtHeld(player, e.hand, 1);
    return e.copyWith(useResult: ItemUseFirstResult.success);
  }

  int? _withPropertiesOf(String newKey, int fromState) {
    final base = BlockStates.defaultOf(newKey);
    if (base == null) return null;
    return BlockStates.copyProperties(fromState, base);
  }

  Future<PlayerUseItemEventData> _onUseItem(Server server, PlayerUseItemEventData e) async {
    final key = await stackKey(e.item);
    if (!EqItems.isSandPaper(key)) return e;
    final player = e.player;
    final inv = player.getInventory();
    final paper = inv.getItemInHand(hand: e.hand);
    if (paper == null) return e;
    final uuid = player.getId().asString;
    if (StackData.has(paper, EquipmentComponents.sandPaperPolishing)) {
      _polishUse[uuid] = (_tick, _tick);
      return e;
    }
    // The item in the other hand
    final otherHand = e.hand.other;
    final other = inv.getItemInHand(hand: otherHand);
    if (other != null) {
      final otherKey = await other.getRegistryKey();
      if (polishResult(otherKey) != null) {
        await _startPolishing(player, paper, e.hand, other, otherHand);
        return e;
      }
    }
    // A polishable item entity next to the looked-at point
    final world = player.getWorld();
    final eye = player.eyePosition;
    final hit = world.rayTraceBlock(start: eye, end: eye + player.lookDirection * 4.5, includeFluids: false);
    final center = hit?.hitPos ?? (eye + player.lookDirection * 4.5);
    final box = world.getItemEntitiesInBox(
      min: (center.$1 - 1, center.$2 - 1, center.$3 - 1),
      max: (center.$1 + 1, center.$2 + 1, center.$3 + 1),
    );
    for (final item in box) {
      final entity = item.asEntity();
      if (entity.getPosition().distanceTo(player.getPosition()) > 3) continue;
      final stack = item.getStack();
      final itemKey = await stack.getRegistryKey();
      if (polishResult(itemKey) == null) continue;
      final count = await stack.getCount();
      await _setPolishing(paper, itemKey);
      if (count <= 1) {
        item.discard();
      } else {
        await stack.setCount(count: count - 1);
        await item.setStack(stack: stack);
      }
      await inv.setItemInHand(hand: e.hand, item: paper);
      _polishUse[uuid] = (_tick, _tick);
      return e;
    }
    return e;
  }

  Future<void> _startPolishing(Player player, ItemStack paper, Hand paperHand, ItemStack other, Hand otherHand) async {
    final key = await other.getRegistryKey();
    final count = await other.getCount();
    await _setPolishing(paper, key);
    final inv = player.getInventory();
    if (count <= 1) {
      await inv.setItemInHand(hand: otherHand, item: null);
    } else {
      await other.setCount(count: count - 1);
    }
    await inv.setItemInHand(hand: paperHand, item: paper);
    _polishUse[player.getId().asString] = (_tick, _tick);
  }

  Future<void> _setPolishing(ItemStack paper, String itemKey) async {
    final data = ItemStackData.of(itemKey, env.itemIds);
    paper.setCustomComponent(EquipmentComponents.sandPaperPolishing, data.encode());
  }

  ItemStackData? _polishedItem(ItemStack paper) {
    final raw = StackData.raw(paper, EquipmentComponents.sandPaperPolishing);
    if (raw == null) return null;
    try {
      final d = ItemStackData.decode(raw);
      return d.isEmpty ? null : d;
    } on Object {
      return null;
    }
  }

  /// Every tick of use; the use ends after 32 ticks (`getUseDuration`).
  ///
  /// The host never fires this for sand paper: it starts a use only for an item with a
  /// `minecraft:consumable` or `minecraft:blocks_attacks` component
  /// (`pumpkin-core/src/net/java/play/use_item.rs:113-131` through `ItemStack::get_max_use_time`,
  /// `pumpkin-data/src/item_stack/mod.rs:428`), and the sand paper has neither, so `item_use_time`
  /// stays 0 and `pumpkin-core/src/entity/living.rs:3643` never reaches the `ItemUseTickEvent`
  /// it fires. Polishing therefore ends through [_onPlayerTick] once the (never arriving) ticks
  /// stop, which returns the item unpolished.
  ///
  /// Declaring the item `minecraft:consumable` would start the use, but the host consumes one item
  /// of the stack when a use finishes, and Java's non-edible `SandPaperItem.finishUsingItem` only
  /// hurts the paper. What the host needs is `use-duration: option<u32>` on
  /// `item-registry`'s `item-definition` (Java `getUseDuration`, 32 here) for
  /// `ItemStack::get_max_use_time` to count down without a component, plus `use-animation:
  /// option<consume-animation>` (Java `UseAnimation.EAT`) and a finish that does not shrink the
  /// stack.
  Future<void> _onUseTick(Server server, ItemUseTickEventData e) async {
    final key = await stackKey(e.stack);
    if (key == EqItems.buildersTea) {
      // `BuildersTeaItem.finishUsingItem`: the last tick of the 42-tick drink leaves a glass
      // bottle. The item's haste is not here: it is the `on_consume_effects` of its
      // `minecraft:consumable` component, which the host applies itself.
      if (e.remainingTicks <= 1) await _leaveGlassBottle(server, e.player);
      return;
    }
    if (!EqItems.isSandPaper(key)) return;
    final player = e.player;
    final uuid = player.getId().asString;
    final started = _polishUse[uuid]?.$1 ?? _tick;
    _polishUse[uuid] = (started, _tick);
    if (e.remainingTicks <= 1) await _finishPolishing(player);
  }

  /// A release is noticed by the missing use ticks: the polished item goes back to the player.
  Future<void> _onPlayerTick(Server server, PlayerTickEventData e) async {
    final uuid = e.player.getId().asString;
    final use = _polishUse[uuid];
    if (use == null) return;
    if (_tick - use.$2 > 3 && _tick - use.$1 > 5) {
      _polishUse.remove(uuid);
      await _releasePolishing(e.player);
    }
  }

  Future<(ItemStack, Hand)?> _heldPaperWithPolish(Player player) async {
    final inv = player.getInventory();
    for (final hand in const [Hand.right, Hand.left]) {
      final s = inv.getItemInHand(hand: hand);
      if (s != null && EqItems.isSandPaper(await s.getRegistryKey()) && StackData.has(s, EquipmentComponents.sandPaperPolishing)) {
        return (s, hand);
      }
    }
    return null;
  }

  /// `finishUsingItem`.
  Future<void> _finishPolishing(Player player) async {
    _polishUse.remove(player.getId().asString);
    final held = await _heldPaperWithPolish(player);
    if (held == null) return;
    final (paper, hand) = held;
    final data = _polishedItem(paper);
    StackData.remove(paper, EquipmentComponents.sandPaperPolishing);
    final world = player.getWorld();
    if (data != null) {
      final inKey = env.itemIds.keyOf(data.itemId);
      final outKey = inKey == null ? null : polishResult(inKey);
      final result = ItemStack.create(registryKey: outKey ?? inKey ?? 'minecraft:air', count: 1);
      if (outKey != null || inKey != null) await giveToPlayer(player, world, result);
    }
    await hurtHeld(player, hand, 1);
    final inv = player.getInventory();
    final still = inv.getItemInHand(hand: hand);
    if (still != null) await inv.setItemInHand(hand: hand, item: still);
  }

  /// `releaseUsing`: the polished item returns to the inventory.
  Future<void> _releasePolishing(Player player) async {
    final held = await _heldPaperWithPolish(player);
    if (held == null) return;
    final (paper, hand) = held;
    final data = _polishedItem(paper);
    StackData.remove(paper, EquipmentComponents.sandPaperPolishing);
    if (data != null) {
      final k = env.itemIds.keyOf(data.itemId);
      if (k != null) await giveToPlayer(player, player.getWorld(), ItemStack.create(registryKey: k, count: 1));
    }
    await player.getInventory().setItemInHand(hand: hand, item: paper);
  }

  // ===================================================================================
  // Cardboard sword
  // ===================================================================================

  /// `cardboardSwordsMakeNoiseOnClick`.
  Future<PlayerInteractEventData> _onInteract(Server server, PlayerInteractEventData e) async {
    if (e.action != InteractAction.leftClickBlock) return e;
    final held = e.player.getInventory().getItemInHand(hand: Hand.right);
    if (held == null || await held.getRegistryKey() != EqItems.cardboardSword) return e;
    final pos = e.clickedPos;
    if (pos != null) env.playSoundAtBlock(e.player.getWorld(), pos.p3, 'cardboard_sword', volume: 0.5, pitch: 1.85);
    return e;
  }

  /// `cardboardSwordsCannotHurtYou`: the hit only knocks the target back.
  Future<PlayerInteractEntityEventData> _onInteractEntity(Server server, PlayerInteractEntityEventData e) async {
    if (e.action != EntityInteractionAction.attack) return e;
    final attacker = e.player;
    final stack = attacker.getInventory().getItemInHand(hand: Hand.right);
    if (stack == null || await stack.getRegistryKey() != EqItems.cardboardSword) return e;
    final world = attacker.getWorld();
    final target = world.getEntityById(id: e.entityId);
    final living = target?.asLiving();
    if (target == null || living == null) return e;
    // A plugin entity (a Create seat, a contraption) has no `EntityType`, `getType()` is null.
    final targetType = target.getType();
    final targetKey =
        target.getPluginTypeKey() ??
        (targetType == null
            ? null
            : 'minecraft:${targetType.wireName.replaceAll('-', '_')}');
    if (targetKey != null && Tags.entityType(targetKey, 'minecraft:arthropod')) return e;

    env.playSound(world, attacker.getPosition(), 'cardboard_sword', volume: 0.75, pitch: 1.85);
    final attackerLiving = attacker.asEntity().asLiving();
    var strength = (attackerLiving?.getAttributeValue(attr: Attribute.attackKnockback) ?? 0) + 2;
    strength += (await stack.enchantmentLevel(Enchantment.knockback)).toDouble();
    if (attacker.asEntity().isSprinting()) strength += 1;
    if (strength <= 0) return e.cancel();
    final yRot = attacker.getYaw();
    await _knockback(target, living, strength, yRot);
    final targetPlayer = server.getPlayerByUuid(id: target.getUuid());
    if (targetPlayer != null) {
      env.bus.sendClientbound('create:knockback', targetPlayer, {'yRot': yRot, 'strength': strength});
    }
    // The attacker slows down
    final v = attacker.asEntity().getVelocity();
    attacker.setVelocity(velocity: (v.$1 * 0.6, v.$2, v.$3 * 0.6));
    attacker.asEntity().setSprinting(sprinting: false);
    // `CardboardSwordItem` also slows the target (`SLOWNESS`, 60 ticks, amplifier 9, ambient
    // without particles, for the `MISC` and `CREATURE` `MobCategory` and never for a player).
    // That cannot be ported: `world.wit`'s `living-entity` (658-698) has no effect function, and
    // `player.wit:1010`'s `add-effect` is the only one the host exposes, so a mob target cannot be
    // given a status effect. It needs `living-entity.add-effect: func(effect:
    // status-effect-instance)` (with `remove-effect`/`has-effect`/`get-effect`, as on `player`)
    // backed by `LivingEntity::add_effect`; the gate would be the target's `MobCategory`, which
    // the host does not expose either (`Entity::get_type` drops it).
    return e.cancel();
  }

  /// `CardboardSwordItem.knockback(target, strength, yRot)`.
  Future<void> _knockback(Entity target, LivingEntity living, double strength, double yRot) async {
    if (target.getVehicle() != null) await target.setVehicle(vehicle: null);
    final rad = yRot * math.pi / 180;
    final v = knockbackResult(
      strength: strength * 0.5,
      x: math.sin(rad),
      z: -math.cos(rad),
      current: target.getVelocity(),
      onGround: target.isOnGround(),
      knockbackResistance: living.getAttributeValue(attr: Attribute.knockbackResistance),
    );
    if (v != null) target.setVelocity(velocity: v);
  }

  // ===================================================================================
  // Builder's tea
  // ===================================================================================

  /// `BuildersTeaItem.finishUsingItem`: the bottle a drunk tea leaves behind.
  ///
  /// Java returns it from `finishUsingItem` when the stack ran out, so a single tea is replaced by
  /// the bottle in the hand and the bottle of a larger stack goes to the inventory. One tick later,
  /// because the host consumes the tea itself right after this tick; creative players get nothing.
  Future<void> _leaveGlassBottle(Server server, Player player) async {
    if (player.isCreative) return;
    final uuid = player.getId().asString;
    server.runLater(1, (s) async {
      final p = s.getPlayerByUuid(id: Uuids.parse(uuid));
      if (p == null) return;
      final bottle = ItemStack.create(registryKey: 'minecraft:glass_bottle', count: 1);
      final held = p.getInventory().getItemInHand(hand: Hand.right);
      if (held == null) {
        await p.getInventory().setItemInHand(hand: Hand.right, item: bottle);
      } else {
        await giveToPlayer(p, p.getWorld(), bottle);
      }
    });
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
