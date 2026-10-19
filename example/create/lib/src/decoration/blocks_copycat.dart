// Behaviours of the copycat blocks: applying a material with a right click, orienting it, removing
// it with the wrench, and the properties a copycat takes from its material.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../api/placement.dart';
import '../common/direction.dart' as d;
import '../common/host_bridge.dart';
import '../common/pos.dart';
import 'behaviour_support.dart';
import 'block_entities.dart';
import 'blocks_misc.dart';
import 'copycat.dart';
import 'materials.dart';
import 'runtime.dart';





/// `CopycatPanelBlock.isAcceptedRegardless`: bars and trapdoors.
bool panelAcceptsRegardless(BState material) => isBarsMaterial(material) || isTrapdoorMaterial(material);

/// `CopycatBlock.getAcceptedBlockState` for the item [itemKey] (`null` when not accepted).
BState? acceptedStateOfItem(String itemKey, {required bool panel, d.Direction? face}) {
  final candidate = materialCandidateOfItem(itemKey);
  if (candidate == null) return null;
  return copycatAcceptedState(
    candidate,
    isAcceptedRegardless: panel ? panelAcceptsRegardless : (m) => false,
    valid: stateExists,
    face: face,
  );
}

/// `CopycatPanelBlock.prepareMaterial`: trapdoors take the panel's orientation.
BState preparePanelMaterial(BState panel, Player player, double cursorY, BState material, DecorationRuntime rt) {
  if (!isTrapdoorMaterial(material)) return material;
  final panelFacing = panel.dir('facing')!;
  var m = material;
  if (panelFacing == d.Direction.down) m = m.setValue('half', 'top');
  if (panelFacing.axis == d.Axis.y) {
    return m.setValue('facing', rt.horizontalDirection(player).serializedName).setFlag('open', false);
  }
  final clickedNearTop = cursorY > .5;
  return m
      .setFlag('open', true)
      .setValue('half', clickedNearTop ? 'top' : 'bottom')
      .setValue('facing', panelFacing.serializedName);
}

BlockBehavior copycatBehavior(DecorationRuntime rt, {required bool panel}) {
  CopycatBlockEntity? be(World world, Pos pos) =>
      rt.store.typed<CopycatBlockEntity>(world.getId(), pos.toBlockPos());

  return BlockBehavior(
    onPlaced: (server, e) async {
      if (!shouldFixPlacement(rt, e.block, e.oldStateId, e.player, e.pos.toPos())) return;
      // `setPlacedBy`: the item in the off hand becomes the material.
      final player = rt.playerOf(server, e.player);
      if (player == null) return;
      final inv = player.getInventory();
      final offhand = inv.getItemInHand(hand: Hand.left);
      if (offhand == null) return;
      final key = await offhand.getRegistryKey();
      if (key == 'minecraft:air') return;
      final nearest = rt.nearestLooking(player).first;
      final applied = acceptedStateOfItem(key, panel: panel, face: nearest);
      if (applied == null) return;
      final entity = be(e.targetWorld, e.pos.toPos()) ?? _ensureEntity(rt, e);
      if (entity == null || entity.hasCustomMaterial) return;
      entity.setMaterial(applied);
      entity.setConsumedItem(key);
      if (player.isCreative) return;
      await rt.shrinkHeld(player, Hand.left);
    },
    onUseWithItem: (server, e) async {
      final world = e.targetWorld;
      final pos = e.pos.toPos();
      final state = rt.stateOf(e.block, e.stateIndex);
      final key = await e.item.getRegistryKey();
      final player = e.player;
      // The placement helpers of panels and steps (`useItemOn`).
      if (!e.sneaking) {
        if (panel && key == copycatPanelKey) {
          final level = HostBlockGetter(world);
          final facing = state.dir('facing')!;
          final dirs = orderedByDistanceExceptAxis(
            pos,
            _hit(e),
            facing.axis,
            (dir) => level.canBeReplaced(pos.relative(dir)),
          );
          final offset = dirs.isEmpty
              ? PlacementOffset.fail
              : PlacementOffset.at(pos.relative(dirs.first), (s) => s.setValue('facing', facing.serializedName));
          await placeFromOffset(rt, world: world, player: player, hand: e.hand, itemKey: key, offset: offset);
          return BlockUseResult.success;
        }
        if (!panel && key == copycatStepKey) {
          final level = HostBlockGetter(world);
          final offset = poleOffset(
            level: level,
            state: state,
            pos: pos,
            hit: _hit(e),
            matches: (s) => s.key == copycatStepKey,
            axisOf: (s) => s.dir('facing')!.clockWise.axis,
            transformProperty: 'facing',
            range: rt.placementRange(),
          );
          final half = state['half']!;
          final withHalf = offset.success
              ? PlacementOffset.at(offset.pos, (s) => offset.transform(s).setValue('half', half))
              : offset;
          return placeFromOffset(rt, world: world, player: player, hand: e.hand, itemKey: key, offset: withHalf);
        }
      }
      // Applying a material.
      final face = dirOf(e.face);
      var material = acceptedStateOfItem(key, panel: panel, face: face);
      if (material != null && panel) {
        material = preparePanelMaterial(state, player, e.cursor.$2, material, rt);
      }
      if (material == null) return BlockUseResult.tryEmptyHand;
      final entity = be(world, pos);
      if (entity == null) return BlockUseResult.tryEmptyHand;
      if (entity.material.key == material.key) {
        if (!entity.cycleMaterial()) return BlockUseResult.tryEmptyHand;
        rt.playSound(world, pos, 'minecraft:entity.item_frame.add_item', volume: .75, pitch: .95);
        return BlockUseResult.success;
      }
      if (entity.hasCustomMaterial) return BlockUseResult.tryEmptyHand;
      entity.setMaterial(material);
      entity.setConsumedItem(key);
      rt.playSound(world, pos, rt.placeSoundOf(material.key), volume: 1, pitch: .75);
      if (player.isCreative) return BlockUseResult.success;
      await rt.shrinkHeld(player, e.hand);
      return BlockUseResult.success;
    },
    onPlayerWillDestroy: (server, e) async {
      // 26.3: the consumed item is dropped here, while the block entity still exists.
      final entity = be(e.targetWorld, e.pos.toPos());
      if (entity == null) return true;
      if (e.player.isCreative) {
        entity.setConsumedItem(null);
      } else {
        final item = entity.consumedItem;
        if (item != null) await rt.dropItem(e.targetWorld, e.pos.toPos(), item);
      }
      return true;
    },
    onCloneItem: (server, e) async {
      // `getCloneItemStack`: the copycat itself while it has no material, else the material's item.
      // (A null answer would mean "pick nothing", so the default stack goes back unchanged.)
      final entity = be(e.targetWorld, e.pos.toPos());
      if (entity == null || !entity.hasCustomMaterial) return e.item;
      return ItemStack.create(registryKey: itemOfBlock(entity.material.key), count: 1);
    },
    onFriction: (server, e) async {
      final entity = be(e.targetWorld, e.pos.toPos());
      final m = entity == null ? null : BlockRegistry.of(entity.material.key);
      return m?.slipperiness ?? 0.6;
    },
    onSpeedFactor: (server, e) async {
      final entity = be(e.targetWorld, e.pos.toPos());
      final m = entity == null ? null : BlockRegistry.of(entity.material.key);
      return m?.velocityMultiplier ?? 1.0;
    },
    onJumpFactor: (server, e) async {
      final entity = be(e.targetWorld, e.pos.toPos());
      final m = entity == null ? null : BlockRegistry.of(entity.material.key);
      return m?.jumpVelocityMultiplier ?? 1.0;
    },
    onLandedUpon: (server, e) async {
      // `fallOn` of the material: hay bales and honey soften a fall, beds halve it.
      final entity = be(e.targetWorld, e.pos.toPos());
      final key = entity?.material.key ?? '';
      if (key == 'minecraft:hay_block' || key == 'minecraft:honey_block') return 0.2;
      if (key.endsWith('_bed')) return 0.5;
      return e.damageMultiplier;
    },
    onUpdateShape: (server, e) async {
      final state = rt.stateOf(e.block, e.stateIndex);
      if (state.flag('waterlogged')) updateWater(e.targetWorld, e.pos.toPos(), state);
      return null;
    },
  );
}

CopycatBlockEntity? _ensureEntity(DecorationRuntime rt, CustomBlockPlacedEventData e) {
  final created = rt.store.createAt(e.targetWorld, e.pos, CopycatBlockEntity.type);
  return created is CopycatBlockEntity ? created : null;
}

(double, double, double) _hit(CustomBlockUseEventData e) =>
    (e.pos.x + e.cursor.$1, e.pos.y + e.cursor.$2, e.pos.z + e.cursor.$3);

/// `CopycatBlock.onWrenched`: takes the material off and gives the item back.
Future<bool> copycatRemoveMaterial(DecorationRuntime rt, World world, BlockPos blockPos, Player player) async {
  final entity = rt.store.typed<CopycatBlockEntity>(world.getId(), blockPos);
  if (entity == null || !entity.hasCustomMaterial) return false;
  final item = entity.consumedItem;
  if (!player.isCreative && item != null) {
    await rt.giveOrDrop(player, world, blockPos.toPos(), item);
  }
  // `levelEvent(PARTICLES_DESTROY_BLOCK)`: the break particles of the old material are client only.
  entity.setMaterial(const BState(copycatBaseKey));
  entity.setConsumedItem(null);
  return true;
}
