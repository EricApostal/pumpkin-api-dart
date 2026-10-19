// The wand of symmetry on the host: `SymmetryWandItem` (use / useOn), `SymmetryHandler`
// (placing and breaking mirrored copies), `ConfigureSymmetryWandPacket` and the effect packet.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart';
import '../../core/module.dart';
import '../host/env.dart';
import '../host/inventory_util.dart';
import '../host/stack_data.dart';
import '../model/block_state_ops.dart';
import '../model/dir.dart';
import 'mirror.dart';

final class SymmetryHost {
  final EquipmentEnv env;

  SymmetryHost(this.env);

  void install(CreateContext ctx) {
    ctx.host.intercept(Events.itemUseFirst, _onUseFirst);
    ctx.host.intercept(Events.playerUseItem, _onUseItem);
    ctx.listen(Events.blockPlace, _onBlockPlace);
    ctx.listen(Events.blockBreak, _onBlockBreak);
    env.bus.onServerbound('create:configure_symmetry_wand', _onConfigure);
  }

  // -- SymmetryWandItem ---------------------------------------------------------------

  /// `useOn`: place or move the mirror at the block in front of the clicked face.
  Future<ItemUseFirstEventData> _onUseFirst(Server server, ItemUseFirstEventData e) async {
    if (await stackKey(e.stack) != EqItems.wandOfSymmetry) return e;
    final player = e.player;
    player.setCooldown(EqItems.wandOfSymmetry, 5);
    final wand = player.getInventory().getItemInHand(hand: e.hand);
    if (wand == null) return e;
    StackData.checkWand(wand);
    // Shift opens the GUI on the client.
    if (player.asEntity().isSneaking()) return e.copyWith(useResult: ItemUseFirstResult.success);
    if (!e.hand.isMain) return e.copyWith(useResult: ItemUseFirstResult.success);

    final clicked = e.blockPos.p3.rel(e.face.dir);
    final pos3d = (clicked.$1.toDouble(), clicked.$2.toDouble(), clicked.$3.toDouble());
    final previous = StackData.wandMirror(wand);
    StackData.setFlag(wand, 'create:symmetry_wand_enable', true);
    final facing = Dir.fromYRot(player.getYaw());
    final SymmetryMirror result;
    if (previous is EmptyMirror) {
      result = PlaneMirror(pos3d)
        ..setOrientation(SymmetryWandPlacement.planeOrientationFor(facing))
        ..enable = true;
    } else {
      previous.setPosition(pos3d);
      if (previous is PlaneMirror) previous.setOrientation(SymmetryWandPlacement.planeOrientationFor(facing));
      if (previous is CrossPlaneMirror) {
        previous.setOrientation(SymmetryWandPlacement.crossOrientationFor(player.asEntity().getHeadYaw()));
      }
      result = previous;
    }
    StackData.setWandMirror(wand, result);
    await player.getInventory().setItemInHand(hand: e.hand, item: wand);
    return e.copyWith(useResult: ItemUseFirstResult.success);
  }

  /// `use`: a click in the air clears the mirror (disables the wand); shift opens the GUI.
  Future<PlayerUseItemEventData> _onUseItem(Server server, PlayerUseItemEventData e) async {
    if (e.clickedPos != null) return e;
    if (await stackKey(e.item) != EqItems.wandOfSymmetry) return e;
    final player = e.player;
    final wand = player.getInventory().getItemInHand(hand: e.hand);
    if (wand == null) return e;
    StackData.checkWand(wand);
    if (!player.asEntity().isSneaking()) {
      StackData.setFlag(wand, 'create:symmetry_wand_enable', false);
      await player.getInventory().setItemInHand(hand: e.hand, item: wand);
    }
    return e;
  }

  /// `ConfigureSymmetryWandPacket`: the GUI sends the new mirror.
  void _onConfigure(Player player, Map<String, Object?> f) {
    final hand = (f['hand'] as bool? ?? true) ? Hand.right : Hand.left;
    final m = f['mirror'] as Map<String, Object?>;
    final pos = m['position'] as (double, double, double);
    final mirror = SymmetryMirror.create(
      m['orientationIndex'] as int,
      pos,
      m['typeName'] as String,
      m['enable'] as bool? ?? true,
    );
    unawaited(() async {
      final stack = player.getInventory().getItemInHand(hand: hand);
      if (stack == null || await stack.getRegistryKey() != EqItems.wandOfSymmetry) return;
      StackData.setWandMirror(stack, mirror);
      await player.getInventory().setItemInHand(hand: hand, item: stack);
    }());
  }

  // -- SymmetryHandler ------------------------------------------------------------------

  Future<List<ItemStack>> _hotbarWands(Player player) async {
    final inv = player.getInventory().asInventory();
    final out = <ItemStack>[];
    for (var i = 0; i < 9; i++) {
      final s = inv.getItem(slot: i);
      if (s != null && await s.getRegistryKey() == EqItems.wandOfSymmetry) out.add(s);
    }
    return out;
  }

  /// `onBlockPlaced`: every enabled wand in the hotbar places mirrored copies. The event
  /// fires before the block exists, so the work runs a tick later.
  void _onBlockPlace(Server server, BlockPlaceEventData e) {
    if (e.cancelled) return;
    final player = e.player;
    final uuid = player.getId().asString;
    final pos = e.blockPos.p3;
    final key = e.blockPlaced;
    final world = player.getWorld();
    final worldName = world.getName();
    server.runLater(1, (s) async {
      final w = s.getWorldByName(name: worldName);
      final p = s.getPlayerByUuid(id: Uuids.parse(uuid));
      if (w == null || p == null) return;
      final stateId = w.getBlockStateId(pos: pos.blockPos);
      final state = BlockStates.info(stateId);
      if (state == null || state.key != key) return;
      for (final wand in await _hotbarWands(p)) {
        await apply(w, wand, p, pos, BState(state.key, state.properties));
      }
    });
  }

  void _onBlockBreak(Server server, BlockBreakEventData e) {
    if (e.cancelled) return;
    final player = e.player;
    if (player == null) return;
    final pos = e.blockPos.p3;
    final uuid = player.getId().asString;
    final worldName = player.getWorld().getName();
    final og = BlockStates.info(player.getWorld().getBlockStateId(pos: pos.blockPos));
    if (og == null) return;
    server.runLater(1, (s) async {
      final w = s.getWorldByName(name: worldName);
      final p = s.getPlayerByUuid(id: Uuids.parse(uuid));
      if (w == null || p == null) return;
      for (final wand in await _hotbarWands(p)) {
        await remove(w, wand, p, pos, og.key);
      }
    });
  }

  /// `SymmetryWandItem.apply`: place the mirrored copies of the block just placed at [pos].
  Future<void> apply(World world, ItemStack wand, Player player, P3 pos, BState block) async {
    StackData.checkWand(wand);
    if (!StackData.wandEnabled(wand)) return;
    // `BlockItem.BY_BLOCK.containsKey(block)`: the block must have an item.
    if (ItemRegistries.host.idOf(block.block) == null && !_vanillaItemExists(block.block)) return;

    final symmetry = StackData.wandMirror(wand);
    final mirrorPos = symmetry.position;
    final d = len3(mirrorPos.$1 - pos.$1, mirrorPos.$2 - pos.$2, mirrorPos.$3 - pos.$3);
    if (d > env.settings.maxSymmetryWandRange) return;

    final blocks = <P3, BState>{pos: block};
    symmetry.process(blocks);
    final targets = <P3>[pos];
    final creative = player.isCreative;
    for (final entry in blocks.entries) {
      final position = entry.key;
      if (position == pos) continue;
      var state = entry.value;
      final bp = position.blockPos;
      if (!world.isLoaded(pos: bp)) continue;
      final id = BlockStates.withProperties(state.block, state.props);
      if (id == null) continue;
      if (creative) {
        await world.setBlockState(pos: bp, state: id, updateFlags: BlockUpdateFlags.normal);
        targets.add(position);
        continue;
      }
      final toReplace = world.getBlockState(pos: bp);
      if (!toReplace.replaceable) continue;
      if (toReplace.hardness < 0) continue;
      var placeId = id;
      if (await BlockHelper.findAndRemoveInInventory(placeId, player, 1) == 0) continue;
      // `world.setBlock(position, fluid.createLegacyBlock(), UPDATE_KNOWN_SHAPE)` then the block.
      await world.setBlockState(pos: bp, state: placeId, updateFlags: BlockUpdateFlags.normal);
      targets.add(position);
      state = state;
    }
    _sendEffect(world, mirrorPos, targets);
  }

  /// `SymmetryWandItem.remove`.
  Future<void> remove(World world, ItemStack wand, Player player, P3 pos, String ogBlockKey) async {
    StackData.checkWand(wand);
    if (!StackData.wandEnabled(wand)) return;
    final symmetry = StackData.wandMirror(wand);
    final mirrorPos = symmetry.position;
    final dist = len3(mirrorPos.$1 - pos.$1, mirrorPos.$2 - pos.$2, mirrorPos.$3 - pos.$3);
    if (dist > env.settings.maxSymmetryWandRange) return;

    final air = BState('minecraft:air');
    final blocks = <P3, BState>{pos: air};
    symmetry.process(blocks);
    final targets = <P3>[pos];
    final creative = player.isCreative;
    final tool = player.getInventory().getItemInHand(hand: Hand.right);
    for (final position in blocks.keys) {
      final bp = position.blockPos;
      if (position == pos) continue;
      final state = BlockStates.info(world.getBlockStateId(pos: bp));
      if (state == null) continue;
      if (!creative && state.key != ogBlockKey) continue;
      if (state.key == 'minecraft:air') continue;
      targets.add(position);
      List<ItemStack> drops = const [];
      if (!creative) drops = await world.getBlockDrops(pos: bp, tool: tool);
      await world.destroyBlock(pos: bp, drop: false, player: null, withParticles: true);
      if (!creative) {
        // `Block.dropResources(blockstate, world, pos, ...)` drops at the *original* pos (as Java).
        for (final stack in drops) {
          await world.dropItem((pos.$1 + .5, pos.$2 + .5, pos.$3 + .5), stack);
        }
        if (tool != null && await tool.getCount() > 0) await hurtHeld(player, Hand.right, 1);
      }
    }
    _sendEffect(world, mirrorPos, targets);
  }

  bool _vanillaItemExists(String key) => VanillaIds.items.idOf(key) != null;

  /// `SymmetryEffectPacket` to the clients tracking the mirror and the player.
  void _sendEffect(World world, V3 mirrorPos, List<P3> targets) {
    final to = (mirrorPos.$1.floor(), mirrorPos.$2.floor(), mirrorPos.$3.floor());
    env.bus.sendToTracking('create:symmetry_effect', world, to.blockPos, {'mirror': to, 'positions': targets});
  }
}
