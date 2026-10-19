// The handheld worldshaper on the host: `ZapperItem` / `WorldshaperItem` (use, swap, cooldown,
// beam packets), `ZapperInteractionHandler` (left click selects the block),
// `ConfigureWorldshaperPacket`, and the [ShaperWorld] over a host world.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart';
import '../../core/module.dart';
import '../../core/nbt.dart';
import '../data/equipment_components.dart';
import '../host/env.dart';
import '../host/stack_data.dart';
import '../model/dir.dart';
import '../model/vec.dart' as vec;
import 'shaper_model.dart';

/// A host world seen by the shaper tools. States are global state ids.
final class HostShaperWorld implements ShaperWorld {
  final World world;
  final int airId;

  HostShaperWorld(this.world, this.airId);

  @override
  ShaperCell cell(P3 pos) {
    final s = world.getBlockState(pos: pos.blockPos);
    return ShaperCell(
      state: s.id,
      block: s.blockName,
      replaceable: s.replaceable,
      unbreakable: s.hardness < 0,
      liquid: s.isLiquid,
      hasSolidSide: (d) => switch (d) {
        Dir.down => s.downSideSolid,
        Dir.up => s.upSideSolid,
        Dir.north => s.northSideSolid,
        Dir.south => s.southSideSolid,
        Dir.west => s.westSideSolid,
        Dir.east => s.eastSideSolid,
      },
    );
  }

  Future<void> _set(P3 pos, int state) => world.setBlockState(
    pos: pos.blockPos,
    state: state,
    updateFlags: BlockUpdateFlags.normal,
  );

  @override
  Future<void> setAir(P3 pos) => _set(pos, airId);

  @override
  Future<void> place(P3 pos, Object? painted, ShaperBlockData? data) async {
    await _set(pos, (painted as int?) ?? airId);
    // `ZapperItem.setBlockEntityData`: the stored `shaper_block_data` is loaded into the new
    // block entity (only safe-nbt blocks ever stored one).
    if (data is NbtValue && data.kind == NbtKind.compound) {
      try {
        world.setBlockEntityNbt(pos: pos.blockPos, nbtData: BinaryNbt.write(data));
      } on Object {
        // a block without a block entity ignores it
      }
    }
  }

  @override
  Future<void> setState(P3 pos, Object state) => _set(pos, state as int);

  /// `state.getFluidState().createLegacyBlock()`: the fluid block (water / lava) of the
  /// block at [pos], or air.
  @override
  Object fluidLegacyState(P3 pos) {
    final f = world.getFluidState(pos: pos.blockPos);
    if (f == null) return airId;
    final id = BlockStates.withProperties(f.fluid, {
      'level': f.isSource ? '0' : '${(8 - f.level).clamp(1, 7)}',
    });
    return id ?? airId;
  }
}

final class ZapperHost {
  final EquipmentEnv env;
  final Map<String, int> _selectedAtTick = {};
  int _tick = 0;

  ZapperHost(this.env);

  static const int zappingRange = 128;
  static const int cooldownDelay = 2;

  void install(CreateContext ctx) {
    ctx.host.intercept(Events.itemUseFirst, _onUseFirst);
    ctx.host.intercept(Events.playerUseItem, _onUseItem);
    ctx.host.intercept(Events.canAttackBlock, _onCanAttackBlock);
    ctx.host.intercept(Events.playerInteract, _onInteract);
    ctx.listen(Events.worldTick, (server, e) => _tick = e.tick);
    env.bus.onServerbound('create:configure_worldshaper', _onConfigure);
    // `LeftClickPacket` -> `CommonEvents.leftClickEmpty`: the client left-clicked in the air.
    env.bus.onServerbound('create:left_click', _onLeftClick);
  }

  // -- Items ----------------------------------------------------------------------------

  /// `ZapperItem.useOn`: shift opens the GUI (client side), everything else falls to `use`.
  Future<ItemUseFirstEventData> _onUseFirst(
    Server server,
    ItemUseFirstEventData e,
  ) async {
    if (await stackKey(e.stack) != EqItems.worldshaper) return e;
    if (e.player.asEntity().isSneaking())
      return e.copyWith(useResult: ItemUseFirstResult.success);
    return e;
  }

  Future<PlayerUseItemEventData> _onUseItem(
    Server server,
    PlayerUseItemEventData e,
  ) async {
    if (await stackKey(e.item) != EqItems.worldshaper) return e;
    final player = e.player;
    if (player.asEntity().isSneaking()) return e.cancel();
    final hand = e.hand;
    final stack = player.getInventory().getItemInHand(hand: hand);
    if (stack == null) return e.cancel();

    if (await _shouldSwap(player, stack, hand)) return e.cancel();

    // validateUsage
    final msg = _validateUsage(stack);
    if (msg != null) {
      env.playSoundAtBlock(
        player.getWorld(),
        player.getPosition().toBlockPos().p3,
        'deny',
      );
      player.actionBar('&c$msg');
      return e.cancel();
    }

    final stateId = StackData.blockUsed(stack);
    var stateToUse = stateId ?? (BlockStates.defaultOf('minecraft:air') ?? 0);
    stateToUse = BlockHelper.setZeroAge(stateToUse);

    final world = player.getWorld();
    final eye = player.eyePosition;
    final look = player.lookDirection;
    final end = eye + look * zappingRange.toDouble();
    final hit = world.rayTraceBlock(start: eye, end: end, includeFluids: false);
    if (hit == null || world.getBlockState(pos: hit.pos).isAir) {
      await _applyCooldown(player, stack, hand, cooldownDelay);
      return e.cancel();
    }

    final ok = await _activate(world, player, stack, stateToUse, hit);
    if (ok) {
      await _applyCooldown(player, stack, hand, cooldownDelay);
      _sendBeam(player, hand, hit.hitPos);
    }
    return e.cancel();
  }

  String? _validateUsage(ItemStack stack) {
    if (StackData.brushParams(stack) == null)
      return 'Shift-right-click to set the shape of the brush';
    final tool = StackData.tool(stack);
    final withoutBlock = !tool.requiresSelectedBlock;
    if (!withoutBlock && StackData.blockUsed(stack) == null)
      return 'Left-click a block to set the block to use';
    return null;
  }

  /// `WorldshaperItem.activate`.
  Future<bool> _activate(
    World world,
    Player player,
    ItemStack stack,
    int stateToUse,
    RayTraceBlockResult hit,
  ) async {
    final brush = StackData.brush(stack).brush;
    final params = StackData.brushParams(stack)!;
    final option = StackData.placement(stack);
    final tool = StackData.tool(stack);
    final pattern = StackData.pattern(stack);
    brush.set(params.$1, params.$2, params.$3);
    final face = hit.face.dir;
    final look = player.lookDirection;
    final off = brush.getOffset(look, face, option);
    final target = hit.pos.p3.plus(off);
    final shaper = HostShaperWorld(
      world,
      BlockStates.defaultOf('minecraft:air') ?? 0,
    );
    final affected = <P3>[];
    brush.addToGlobalPositions(shaper, target, face, affected, tool);
    PlacementPatterns.apply(affected, pattern, () => env.rng.nextBool());
    await brush
        .redirectTool(tool)
        .run(shaper, affected, face, stateToUse, StackData.blockData(stack));
    return true;
  }

  Future<void> _applyCooldown(
    Player player,
    ItemStack item,
    Hand hand,
    int cooldown,
  ) async {
    if (cooldown <= 0) return;
    final other = player.getInventory().getItemInHand(hand: hand.other);
    final gunInOtherHand =
        other != null && await other.getRegistryKey() == EqItems.worldshaper;
    player.setCooldown(
      EqItems.worldshaper,
      gunInOtherHand ? cooldown * 2 ~/ 3 : cooldown,
    );
  }

  /// `ShootableGadgetItemMethods.shouldSwap`: with a gadget in each hand the main hand passes
  /// to the off hand every other use.
  Future<bool> _shouldSwap(Player player, ItemStack item, Hand hand) async {
    final isSwap = StackData.has(item, EquipmentComponents.shaperSwap);
    final mainHand = hand.isMain;
    final inv = player.getInventory();
    final otherStack = inv.getItemInHand(hand: hand.other);
    final gunInOtherHand =
        otherStack != null &&
        await otherStack.getRegistryKey() == EqItems.worldshaper;
    if (mainHand && isSwap && gunInOtherHand) return true;
    if (mainHand && !isSwap && gunInOtherHand)
      StackData.setFlag(item, EquipmentComponents.shaperSwap, true);
    if (!mainHand && isSwap)
      StackData.remove(item, EquipmentComponents.shaperSwap);
    if (!mainHand && gunInOtherHand) {
      final main = inv.getItemInHand(hand: Hand.right);
      if (main != null) StackData.remove(main, EquipmentComponents.shaperSwap);
    }
    return false;
  }

  void _sendBeam(Player player, Hand hand, V3 target) {
    final eye = player.eyePosition;
    final barrel = vec.gunBarrelVec(
      eyePos: eye,
      yRotDeg: player.getYaw(),
      xRotDeg: player.getPitch(),
      mainHand: hand.isMain,
      rightArmMain: true,
      rightHandForward: (.35, -0.1, 1),
    );
    final world = player.getWorld();
    final pos = barrel.toBlockPos();
    // `sendToClientsTrackingEntity(player, packet(self=false))` + `sendToClient(player, packet(self=true))`
    final others = env.bus.playersTracking(world.getId(), pos.p3);
    final uuid = player.getId().asString;
    env.bus.sendClientboundAll(
      'create:beam_effect',
      [
        for (final p in others)
          if (p.getId().asString != uuid) p,
      ],
      {
        'location': barrel,
        'hand': hand.isMain,
        'self': false,
        'target': target,
      },
    );
    env.bus.sendClientbound('create:beam_effect', player, {
      'location': barrel,
      'hand': hand.isMain,
      'self': true,
      'target': target,
    });
  }

  // -- Left click selects the block -------------------------------------------------------

  /// `CommonEvents.leftClickEmpty`: a zapper in the main hand selects the looked-at block.
  void _onLeftClick(Player player, Map<String, Object?> fields) {
    unawaited(() async {
      final held = player.getInventory().getItemInHand(hand: Hand.right);
      if (held == null || await held.getRegistryKey() != EqItems.worldshaper)
        return;
      await trySelect(held, player);
    }());
  }

  Future<CanAttackBlockEventData> _onCanAttackBlock(
    Server server,
    CanAttackBlockEventData e,
  ) async {
    if (await stackKey(e.stack) != EqItems.worldshaper) return e;
    final player = e.player;
    final uuid = player.getId().asString;
    if (_selectedAtTick[uuid] == _tick) return e.cancel();
    if (await trySelect(e.stack, player)) {
      _selectedAtTick[uuid] = _tick;
      final held = player.getInventory().getItemInHand(hand: Hand.right);
      if (held != null)
        await player.getInventory().setItemInHand(hand: Hand.right, item: held);
      return e.cancel();
    }
    return e;
  }

  Future<PlayerInteractEventData> _onInteract(
    Server server,
    PlayerInteractEventData e,
  ) async {
    if (e.action != InteractAction.leftClickAir &&
        e.action != InteractAction.leftClickBlock)
      return e;
    final player = e.player;
    final held = player.getInventory().getItemInHand(hand: Hand.right);
    if (held == null || await held.getRegistryKey() != EqItems.worldshaper)
      return e;
    final uuid = player.getId().asString;
    if (_selectedAtTick[uuid] == _tick) return e.cancel();
    if (await trySelect(held, player)) {
      _selectedAtTick[uuid] = _tick;
      return e.cancel();
    }
    return e;
  }

  /// `ZapperInteractionHandler.trySelect`: stores the looked-at block (and its data) in the zapper.
  Future<bool> trySelect(ItemStack stack, Player player) async {
    if (player.asEntity().isSneaking()) return false;
    final world = player.getWorld();
    final eye = player.eyePosition;
    final end = eye + player.lookDirection * zappingRange.toDouble();
    final hit = world.rayTraceBlock(start: eye, end: end, includeFluids: false);
    if (hit == null) return false;
    final bs = world.getBlockState(pos: hit.pos);
    final info = BlockStates.info(bs.id);
    if (info == null) return false;
    // `BlockHelper.getRequiredItem(newState).isEmpty()`
    final requiredItem = BlockHelper.getRequiredItem(bs.id);
    if (bs.isAir ||
        (VanillaIds.items.idOf(requiredItem) == null &&
            ItemRegistries.host.idOf(requiredItem) == null)) {
      return false;
    }
    final hasBlockEntity = bs.blockEntityType != 0 && bs.blockEntityType != -1;
    if (hasBlockEntity && !Tags.blockState(bs.id, 'create:safe_nbt'))
      return false;
    final p = info.properties;
    if (p['half'] == 'upper' || p['half'] == 'lower')
      return false; // DOUBLE_BLOCK_HALF
    if (p.containsKey('attached')) return false;
    if (p.containsKey('hanging')) return false;
    if (p.containsKey('part') && (p['part'] == 'head' || p['part'] == 'foot'))
      return false; // BED_PART

    var newId = bs.id;
    if (p.containsKey('shape') &&
        const {
          'straight',
          'inner_left',
          'inner_right',
          'outer_left',
          'outer_right',
        }.contains(p['shape'])) {
      newId = BlockStates.setValue(newId, 'shape', 'straight');
    }
    if (p.containsKey('persistent'))
      newId = BlockStates.setValue(newId, 'persistent', 'true');
    if (p.containsKey('waterlogged'))
      newId = BlockStates.setValue(newId, 'waterlogged', 'false');

    NbtValue? data;
    if (hasBlockEntity) {
      final raw = world.getBlockEntityNbt(pos: hit.pos);
      if (raw != null) {
        try {
          final n = BinaryNbt.read(raw)?.root;
          if (n != null && n.kind == NbtKind.compound) {
            final m = Map<String, NbtValue>.of(n.asCompound)
              ..remove('x')
              ..remove('y')
              ..remove('z')
              ..remove('id');
            data = NbtValue.compound(m);
          }
        } on Object {
          data = null;
        }
      }
    }
    final currentUsed = StackData.blockUsed(stack);
    final currentData = StackData.blockData(stack);
    if (currentUsed == newId && _sameNbt(currentData, data)) return false;
    StackData.setVarInt(stack, EquipmentComponents.shaperBlockUsed, newId);
    if (data == null) {
      StackData.remove(stack, EquipmentComponents.shaperBlockData);
    } else {
      stack.setCustomComponent(
        EquipmentComponents.shaperBlockData,
        EquipmentWire.nbt(data),
      );
    }
    env.playSoundAtBlock(
      world,
      player.getPosition().toBlockPos().p3,
      'confirm',
    );
    return true;
  }

  bool _sameNbt(NbtValue? a, NbtValue? b) {
    if (a == null || b == null) return a == b;
    return NetworkNbt.encode(a).toString() == NetworkNbt.encode(b).toString();
  }

  // -- Configure packet -------------------------------------------------------------------

  void _onConfigure(Player player, Map<String, Object?> f) {
    final hand = (f['hand'] as bool? ?? true) ? Hand.right : Hand.left;
    final pattern = _ordinal(PlacementPatterns.values, f['pattern'] as int);
    final brush = _ordinal(TerrainBrushes.values, f['brush'] as int);
    final tool = _ordinal(TerrainTools.values, f['tool'] as int);
    final placement = _ordinal(PlacementOptions.values, f['placement'] as int);
    final px = f['brushParamX'] as int,
        py = f['brushParamY'] as int,
        pz = f['brushParamZ'] as int;
    unawaited(() async {
      final stack = player.getInventory().getItemInHand(hand: hand);
      if (stack == null || await stack.getRegistryKey() != EqItems.worldshaper)
        return;
      StackData.configureWorldshaper(
        stack,
        pattern: pattern,
        brush: brush,
        px: px,
        py: py,
        pz: pz,
        tool: tool,
        placement: placement,
      );
      await player.getInventory().setItemInHand(hand: hand, item: stack);
    }());
  }

  T _ordinal<T>(List<T> values, int i) => values[i.clamp(0, values.length - 1)];
}
