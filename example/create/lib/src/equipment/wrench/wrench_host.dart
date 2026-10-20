// Host side of the wrench: `WrenchItem.useOn`, `WrenchEventHandler` (other wrench-tagged
// items acting on Create blocks), `WrenchItem.wrenchInstaKillsMinecarts`, and the default
// `IWrenchable` rotate / dismantle used by `WrenchRegistry`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart';
import '../../api/wrenchable.dart';
import '../../core/module.dart';
import '../../manifest/manifest.dart';
import '../host/env.dart';
import '../host/inventory_util.dart';
import 'wrench_rotation.dart';

final class WrenchHost {
  final EquipmentEnv env;
  final Map<String, FacingKind> _facingKinds = {};
  final Set<String> _horizontalAxisBlocks = {};

  WrenchHost(this.env);

  WrenchRegistry get registry => env.wrench;

  /// Value lists of the `facing` property of each Create block (from the manifest).
  FacingKind _facingKindOf(String blockKey) {
    if (_facingKinds.isEmpty) {
      for (final b in kBlocks) {
        List<String>? values;
        for (final p in b.properties) {
          if (p.name == 'facing') values = p.values;
          if (p.name == 'axis' && WrenchRotation.axisIsHorizontalOnly(p.values)) _horizontalAxisBlocks.add('create:${b.key}');
        }
        _facingKinds['create:${b.key}'] = WrenchRotation.facingKindOf(values);
      }
    }
    return _facingKinds[blockKey] ?? FacingKind.none;
  }

  void install(CreateContext ctx) {
    registry.installDefaults(rotate: _rotate, dismantle: _dismantle);
    ctx.host.intercept(Events.itemUseFirst, _onUseFirst);
    ctx.listen(Events.playerInteractEntity, _onAttackEntity);
  }

  // -- Events --------------------------------------------------------------------

  Future<ItemUseFirstEventData> _onUseFirst(Server server, ItemUseFirstEventData e) async {
    final key = await stackKey(e.stack);
    if (key.isEmpty) return e;
    final isCreateWrench = key == EqItems.wrench;
    if (!isCreateWrench && !Tags.item(key, 'c:tools/wrench')) return e;

    final player = e.player;
    // `player.mayBuild()`
    if (player.isAdventure || player.isSpectator) return e;

    final world = player.getWorld();
    final state = world.getBlockState(pos: e.blockPos);
    final blockKey = state.blockName;
    final handler = registry.of(blockKey);
    final sneaking = player.asEntity().isSneaking();

    if (handler == null) {
      // WrenchItem.useOn on a non IWrenchable block: shift + `create:wrench_pickup` picks it up.
      if (isCreateWrench && sneaking && Tags.blockState(state.id, 'create:wrench_pickup')) {
        final ctxw = _context(player, world, e, state, key);
        final r = await _dismantle(ctxw);
        return e.copyWith(useResult: _toUseResult(r));
      }
      return e;
    }
    final c = _context(player, world, e, state, key);
    final result = sneaking ? await handler.onSneakWrenched(c) : await handler.onWrenched(c);
    return e.copyWith(useResult: _toUseResult(result));
  }

  WrenchContext _context(Player player, World world, ItemUseFirstEventData e, BlockState state, String itemKey) =>
      WrenchContext(
        registry: registry,
        player: player,
        world: world,
        pos: e.blockPos,
        face: e.face,
        blockKey: state.blockName,
        stateId: state.id,
        properties: {for (final (k, v) in state.properties) k: v},
        hand: e.hand,
        stack: e.stack,
        cursor: _cursor(player, e.blockPos, e.face),
      );

  /// `UseOnContext.getClickLocation()` inside the block: where the player's look ray crosses the
  /// clicked face. 0..1 per axis, the block centre when the ray does not cross it.
  (double, double, double) _cursor(Player player, BlockPos pos, BlockDirection face) {
    const centre = (0.5, 0.5, 0.5);
    final normal = switch (face) {
      BlockDirection.down => (0.0, -1.0, 0.0),
      BlockDirection.up => (0.0, 1.0, 0.0),
      BlockDirection.north => (0.0, 0.0, -1.0),
      BlockDirection.south => (0.0, 0.0, 1.0),
      BlockDirection.west => (-1.0, 0.0, 0.0),
      BlockDirection.east => (1.0, 0.0, 0.0),
    };
    final eye = player.asEntity().getEyePosition();
    final yaw = player.getYaw() * math.pi / 180;
    final pitch = player.getPitch() * math.pi / 180;
    final look = (
      -math.sin(yaw) * math.cos(pitch),
      -math.sin(pitch),
      math.cos(yaw) * math.cos(pitch),
    );
    final denominator = look.$1 * normal.$1 + look.$2 * normal.$2 + look.$3 * normal.$3;
    if (denominator.abs() < 1e-6) return centre;
    // The face plane sits half a block out from the block's centre along the normal.
    final planeX = pos.x + centre.$1 + normal.$1 * 0.5;
    final planeY = pos.y + centre.$2 + normal.$2 * 0.5;
    final planeZ = pos.z + centre.$3 + normal.$3 * 0.5;
    final t = ((planeX - eye.$1) * normal.$1 +
            (planeY - eye.$2) * normal.$2 +
            (planeZ - eye.$3) * normal.$3) /
        denominator;
    final hitX = (eye.$1 + look.$1 * t - pos.x).clamp(0.0, 1.0);
    final hitY = (eye.$2 + look.$2 * t - pos.y).clamp(0.0, 1.0);
    final hitZ = (eye.$3 + look.$3 * t - pos.z).clamp(0.0, 1.0);
    return (hitX, hitY, hitZ);
  }

  ItemUseFirstResult _toUseResult(WrenchResult r) => switch (r) {
    WrenchResult.success => ItemUseFirstResult.success,
    WrenchResult.pass => ItemUseFirstResult.pass,
    WrenchResult.fail => ItemUseFirstResult.consume,
  };

  /// `WrenchItem.wrenchInstaKillsMinecarts`: attacking a minecart with the Create wrench in
  /// survival kills it (hurt with 100 damage).
  Future<void> _onAttackEntity(Server server, PlayerInteractEntityEventData e) async {
    if (e.action != EntityInteractionAction.attack) return;
    final player = e.player;
    if (player.isCreative) return;
    final held = player.getInventory().getItemInHand(hand: Hand.right);
    if (await stackKey(held) != EqItems.wrench) return;
    final world = player.getWorld();
    final target = world.getEntityById(id: e.entityId);
    if (target == null) return;
    final type = target.getType();
    if (type == null || !type.wireName.contains('minecart')) return;
    final living = target.asLiving();
    if (living != null) {
      await living.damage(amount: 100, damageType: DamageType.playerAttack);
    } else {
      target.remove();
    }
  }

  // -- IWrenchable defaults ---------------------------------------------------------

  Future<WrenchResult> _rotate(WrenchContext c, CallbackWrenchable? custom) async {
    int? rotated;
    final hook = custom?.rotatedState;
    if (hook != null) {
      rotated = hook(c);
    } else {
      rotated = rotatedStateId(c);
    }
    if (rotated == null) return WrenchResult.pass;
    final updater = custom?.updateAfterWrenched;
    if (updater != null) rotated = updater(c, rotated);
    final before = c.stateId;
    await switchToBlockState(c.world, c.pos, rotated);
    if (c.world.getBlockStateId(pos: c.pos) != before) {
      env.playSoundAtBlock(c.world, c.pos.p3, 'wrench_rotate', pitch: 0.5 + env.rng.nextDouble());
    }
    return WrenchResult.success;
  }

  /// `getRotatedBlockState`: the state id of the block rotated about the clicked face.
  int? rotatedStateId(WrenchContext c) {
    final face = c.face.dir;
    final props = WrenchRotation.rotated(
      c.properties,
      face,
      facing: _facingKindOf(c.blockKey),
      axisHorizontalOnly: _horizontalAxisBlocks.contains(c.blockKey),
    );
    if (identical(props, c.properties)) return c.stateId;
    return BlockStates.withProperties(c.blockKey, props) ?? c.stateId;
  }

  Future<void> switchToBlockState(World world, BlockPos pos, int newStateId) {
    final switcher = registry.stateSwitcher;
    if (switcher != null) return switcher(world, pos, newStateId);
    return world.setBlockState(pos: pos, state: newStateId, updateFlags: BlockUpdateFlags.normal);
  }

  Future<WrenchResult> _dismantle(WrenchContext c) async {
    final player = c.player;
    // `BreakBlockEvent` is raised by the host when the block is broken as the player.
    await BlockHelper.destroyBlockAs(c.world, c.pos.p3, player, c.stack, 1.0, (stack) async {
      await giveToPlayer(player, c.world, stack);
    });
    env.playSoundAtBlock(c.world, c.pos.p3, 'wrench_remove', pitch: 0.5 + env.rng.nextDouble() * 0.5);
    return WrenchResult.success;
  }
}
