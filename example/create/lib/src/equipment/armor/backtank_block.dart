// The placed backtank: `BacktankBlock` and `BacktankBlockEntity` (it fills with air while its
// shaft turns), wearing it by right-click, placing the worn item as a block.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/equipment.dart';
import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../data/equipment_components.dart';
import '../host/env.dart';
import '../host/runtime.dart';
import '../host/stack_data.dart';
import '../model/dir.dart';
import 'backtank_math.dart';

const String backtankBlockEntityType = 'create:backtank';

/// `BacktankBlockEntity`.
final class BacktankBlockEntity extends CreateBlockEntity {
  BacktankBlockEntity(super.worldId, super.pos);

  int airLevel = 0;
  int airLevelTimer = 0;
  int capacityEnchantLevel = 0;
  String? customName;
  bool _awarded = false;

  EquipmentRuntime get _rt => EquipmentRuntime.instance;

  int get maxAir => _rt.backtanks.maxAirFor(capacityEnchantLevel);

  /// `getComparatorOutput`.
  int get comparatorOutput => BacktankMath.fractionToRedstoneLevel(airLevel / maxAir);

  void setAirLevel(int air) {
    airLevel = air;
    sendData();
  }

  @override
  void tick() {
    super.tick();
    final speed = _rt.env.ctx.services.find<KineticSpeedLookup>()?.speedAt(worldId, (pos.x, pos.y, pos.z)) ?? 0;
    if (speed == 0) return;
    if (!_awarded) {
      _awarded = true;
      _awardNearby();
    }
    final w = world;
    if (w == null) return;
    // `state.getValue(WATERLOGGED)`: no air is pumped under water
    final state = w.getBlockState(pos: pos);
    for (final (k, v) in state.properties) {
      if (k == 'waterlogged' && v == 'true') return;
    }
    if (airLevelTimer > 0) {
      airLevelTimer--;
      return;
    }
    final max = maxAir;
    if (airLevel == max) return;
    final prevComparator = comparatorOutput;
    final abs = speed.abs();
    final increment = BacktankMath.refillIncrement(abs);
    airLevel = airLevel + increment > max ? max : airLevel + increment;
    if (comparatorOutput != prevComparator) unawaited(w.updateComparators(pos: pos));
    if (airLevel == max) {
      sendData();
    } else {
      markDirty();
    }
    airLevelTimer = BacktankMath.refillTimer(abs);
  }

  /// `SmartBlockEntity.award(AllAdvancements.BACKTANK)`: players near the turning tank.
  void _awardNearby() {
    final env = _rt.env;
    for (final p in env.bus.roster.players) {
      try {
        final w = p.getWorld();
        final same = w.getId() == worldId;
        w.dispose();
        if (!same) continue;
        final (x, y, z) = p.getPosition();
        final dx = x - (pos.x + 0.5), dy = y - (pos.y + 0.5), dz = z - (pos.z + 0.5);
        if (dx * dx + dy * dy + dz * dz > 10 * 10) continue;
        unawaited(env.award(p, 'backtank'));
      } on Object {
        // a handle that went invalid: the player left
      }
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('Air', airLevel);
    tag.putInt('Timer', airLevelTimer);
    tag.putInt('CapacityEnchantment', capacityEnchantLevel);
    final name = customName;
    if (name != null) tag.putString('CustomName', '{"text":${_jsonString(name)}}');
    tag.putCompound('Components', NbtCompound());
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    airLevel = tag.getInt('Air') ?? 0;
    airLevelTimer = tag.getInt('Timer') ?? 0;
    capacityEnchantLevel = tag.getInt('CapacityEnchantment') ?? 0;
    final n = tag.getString('CustomName');
    customName = n == null ? null : _plainOfJson(n);
  }
}

String _jsonString(String s) {
  final b = StringBuffer('"');
  for (final c in s.runes) {
    switch (c) {
      case 0x22:
        b.write(r'\"');
      case 0x5C:
        b.write(r'\\');
      case 0x0A:
        b.write(r'\n');
      default:
        b.writeCharCode(c);
    }
  }
  b.write('"');
  return b.toString();
}

String? _plainOfJson(String json) {
  final m = RegExp(r'"text"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(json);
  if (m == null) return json.startsWith('"') ? json.replaceAll('"', '') : json;
  return m.group(1)!.replaceAll(r'\"', '"').replaceAll(r'\\', r'\').replaceAll(r'\n', '\n');
}

/// Behaviour of the backtank blocks and of the worn item acting like a block item.
final class BacktankBlockHost {
  final EquipmentEnv env;

  BacktankBlockHost(this.env);

  static const blockKeys = ['create:copper_backtank', 'create:netherite_backtank'];

  BacktankBlockEntity? _be(World world, BlockPos pos) =>
      env.ctx.blockEntities.typed<BacktankBlockEntity>(world.getId(), pos);

  /// The worn backtank used on a block places the block (`BacktankItem.useOn`).
  void install(CreateContext ctx) {
    ctx.host.intercept(Events.itemUseFirst, (server, e) async {
      final key = await stackKey(e.stack);
      if (!EqItems.isBacktank(key)) return e;
      final placed = await placeFromItem(server, e.player, e.stack, e.hand, e.blockPos, e.face);
      return placed ? e.copyWith(useResult: ItemUseFirstResult.success) : e;
    });
  }

  /// Behaviour of the block.
  BlockBehavior behavior() => BlockBehavior(
    onPlaced: _onPlaced,
    onUse: _onUse,
    onComparatorOutput: (server, e) {
      final be = _be(e.targetWorld, e.pos);
      return be?.comparatorOutput ?? 0;
    },
  );

  /// `setPlacedBy`: air, capacity and name from the placed item (the player's hand).
  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final uuid = e.player;
    if (uuid == null || e.moved) return;
    final player = server.getPlayerByUuid(id: uuid);
    if (player == null) return;
    final be = _be(e.targetWorld, e.pos);
    if (be == null) return;
    for (final hand in const [Hand.right, Hand.left]) {
      final held = player.getInventory().getItemInHand(hand: hand);
      if (held == null) continue;
      final key = await held.getRegistryKey();
      if (!EqItems.isBacktank(key) &&
          key != EqItems.copperBacktankPlaceable &&
          key != EqItems.netheriteBacktankPlaceable) {
        continue;
      }
      await applyItemData(be, held);
      break;
    }
  }

  /// Copies the data of a backtank item onto its entity.
  Future<void> applyItemData(BacktankBlockEntity be, ItemStack held) async {
    be.capacityEnchantLevel = await customEnchantLevel(held, 'create:capacity');
    be.setAirLevel(StackData.backtankAir(held));
    final name = await held.getCustomName();
    if (name != null) {
      be.customName = name.getText();
    }
  }

  /// `useItemOn`: an empty chest slot lets the player wear the placed backtank.
  Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
    final player = e.player;
    if (player.asEntity().isSneaking()) return BlockUseResult.tryEmptyHand;
    final inv = player.getInventory();
    final main = inv.getItemInHand(hand: Hand.right);
    if (main != null) {
      final key = await main.getRegistryKey();
      // `instanceof BlockItem`: an item with a block of the same name
      if (BlockRegistry.resolveState(key) != null) return BlockUseResult.tryEmptyHand;
    }
    if (inv.getChestplate() != null) return BlockUseResult.tryEmptyHand;
    final be = _be(e.targetWorld, e.pos);
    final stack = await cloneItem(e.block, be);
    await inv.setChestplate(item: stack);
    final world = e.targetWorld;
    world.playSound(
      sound: Sound.entityItemPickup,
      category: SoundCategory.players,
      pos: (e.pos.x + .5, e.pos.y + .5, e.pos.z + .5),
      volume: .75,
      pitch: 1,
    );
    await world.destroyBlock(pos: e.pos, drop: false, player: null, withParticles: true);
    return BlockUseResult.success;
  }

  /// `getCloneItemStack`: the wearable item with the air, capacity enchantment and name.
  Future<ItemStack> cloneItem(String blockKey, BacktankBlockEntity? be) async {
    final stack = ItemStack.create(registryKey: blockKey, count: 1);
    stack.setCustomComponent(EquipmentComponents.backtankAir, EquipmentWire.varInt(be?.airLevel ?? 0));
    final level = be?.capacityEnchantLevel ?? 0;
    if (level > 0) await stack.addCustomEnchantment(enchantmentId: 'create:capacity', level: level);
    final name = be?.customName;
    if (name != null) await stack.setCustomName(name: TextComponent.text(plain: name));
    return stack;
  }

  // -- The worn item used on a block (BacktankItem.useOn -> blockItem.useOn) ----------------------

  /// Places the backtank block where the worn item was used. Returns true when placed.
  Future<bool> placeFromItem(
    Server server,
    Player player,
    ItemStack held,
    Hand hand,
    BlockPos clicked,
    BlockDirection face,
  ) async {
    final key = await held.getRegistryKey();
    final world = player.getWorld();
    var target = clicked;
    final clickedState = world.getBlockState(pos: clicked);
    if (!clickedState.replaceable) target = clicked.p3.rel(face.dir).blockPos;
    final targetState = world.getBlockState(pos: target);
    if (!targetState.replaceable && !targetState.isAir) return false;
    final facing = Dir.fromYRot(player.getYaw()).opposite;
    final water = world.getFluidState(pos: target);
    final waterlogged = water != null && water.fluid == 'minecraft:water' && water.isSource;
    final stateId = BlockRegistry.resolveState(key, {'facing': facing.name, 'waterlogged': '$waterlogged'});
    if (stateId == null) return false;
    await world.setBlockState(pos: target, state: stateId, updateFlags: BlockUpdateFlags.normal);
    var be = _be(world, target);
    be ??= env.ctx.blockEntities.createAt(world, target, backtankBlockEntityType) as BacktankBlockEntity?;
    if (be != null) await applyItemData(be, held);
    env.playSoundAtBlock(world, target.p3, 'confirm', volume: 0);
    if (!player.isCreative) {
      final inv = player.getInventory();
      await inv.setItemInHand(hand: hand, item: null);
    }
    return true;
  }
}
