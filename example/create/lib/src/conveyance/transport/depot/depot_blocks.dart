// The depot and weighted ejector blocks: placement, shapes, the item interaction
// (`SharedDepotBlockMethods`), the comparator output and the ejector's signal/friction/landing
// behaviour. The item state lives in `depot_block_entity.dart` / `depot_behaviour.dart`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart';
import '../../../api/wrenchable.dart';
import '../../../common/direction.dart';
import '../../../common/host_bridge.dart';
import '../../../core/block_entity.dart';
import '../../../core/module.dart';
import '../../../core/registry.dart';
import '../../belt/transported_item.dart';
import '../../items/item_codec.dart';
import '../../runtime.dart';
import '../../shapes.dart';
import '../transport_inventory.dart';
import '../transport_support.dart';
import 'depot_behaviour.dart';
import 'depot_block_entity.dart';
import 'ejector_block_entity.dart';

/// Phase 1: the depot and the weighted ejector.
void registerDepot(CreateRegistry registry) {
  final depotShape = BlockShape.boxes(casing13px.get(Direction.up));
  final depot = manifestBlock(
    'depot',
    blockEntityType: 'create:depot',
    collisionShape: depotShape,
    selectionShape: depotShape,
    behavior: _depotBehavior(),
    placement: const [PlacementRule.inWater('waterlogged')],
  );
  final ejector = manifestBlock(
    'weighted_ejector',
    blockEntityType: 'create:weighted_ejector',
    collisionShape: depotShape,
    selectionShape: depotShape,
    behavior: _ejectorBehavior(),
    placement: const [
      // `EjectorBlock extends HorizontalKineticBlock`: `getHorizontalDirection().getOpposite()`.
      PlacementRule.horizontalFacing('facing', opposite: true),
      PlacementRule.inWater('waterlogged'),
    ],
  );
  for (final block in [depot, ejector]) {
    registry.block(block);
    transportBlocks[block.key] = block;
  }
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: 'create:depot',
      validBlocks: const ['create:depot'],
      create: DepotBlockEntity.new,
      tickInterval: 1,
    ),
  );
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: 'create:weighted_ejector',
      validBlocks: const ['create:weighted_ejector'],
      create: EjectorBlockEntity.new,
      tickInterval: 1,
    ),
  );
}

/// Phase 2: the item hooks of the depot area.
///
/// `EjectorItem.useOn` (`EjectorItem.java:26-31`): a sneaking player does not place the weighted
/// ejector, because the item answers the click with `SUCCESS`. The host has no item-behaviour hook,
/// so `useOn` runs from `itemUseFirst`, which fires before the block handles the click and before
/// the item is used or placed — the hook the other items use for their `useOn`
/// (`equipment/zapper/zapper_host.dart:108-116`).
void installDepotItemHooks(CreateContext ctx) {
  ctx.host.intercept(Events.itemUseFirst, (server, e) async {
    if (e.useResult != ItemUseFirstResult.pass) return e;
    if (await e.stack.getRegistryKey() != 'create:weighted_ejector') return e;
    if (!e.player.asEntity().isSneaking()) return e;
    return e.copyWith(useResult: ItemUseFirstResult.success);
  });
}

/// Phase 3: the wrench action of the depot.
void registerDepotWrench(WrenchRegistry wrench) {
  wrench.registerDefault(const ['create:depot']);
}

BlockBehavior _depotBehavior() => BlockBehavior(
  onUseWithItem: (server, e) => _depotUse(e),
  onUseWithoutItem: (server, e) => _depotUse(e),
  onLandedUpon: (server, e) => _depotLanded(e),
  onComparatorOutput: (server, e) => _depotComparator(e),
);

BlockBehavior _ejectorBehavior() => BlockBehavior(
  // `EjectorItem.place`: after the weighted ejector is placed, ask the client to flush its target
  // selection (`EjectorTargetHandler.flushSettings`), which then sends `create:place_ejector`.
  onPlaced: (server, e) {
    final player = ConveyanceRuntime.i.playerOf(server, e.player);
    if (player == null) return;
    try {
      ConveyanceRuntime.i.bus?.sendClientbound(
        'create:s_place_ejector',
        player,
        {'pos': (e.pos.x, e.pos.y, e.pos.z)},
      );
    } finally {
      player.dispose();
    }
  },
  onUseWithItem: (server, e) => _depotUse(e),
  onUseWithoutItem: (server, e) => _depotUse(e),
  onLandedUpon: (server, e) => _ejectorLanded(e),
  onComparatorOutput: (server, e) => _depotComparator(e),
  onNeighborUpdate: (server, e) {
    final be = ConveyanceRuntime.i.typedAt<EjectorBlockEntity>(
      e.targetWorld.getId(),
      e.pos.toPos(),
    );
    if (be != null) ConveyanceRuntime.i.fire('Ejector signal', be.updateSignal);
  },
  onFriction: (server, e) {
    final be = ConveyanceRuntime.i.typedAt<EjectorBlockEntity>(
      e.targetWorld.getId(),
      e.pos.toPos(),
    );
    return be?.isLaunching ?? false ? 1.0 : 0.6;
  },
);

/// `SharedDepotBlockMethods.onUse`: take the held item / output buffer out, or put the held stack
/// on the depot.
Future<BlockUseResult> _depotUse(CustomBlockUseEventData e) async {
  if (e.face.toDirection() != Direction.up) return BlockUseResult.tryEmptyHand;
  final world = e.targetWorld;
  final worldId = world.getId();
  final pos = e.pos.toPos();
  final be = ConveyanceRuntime.i.typedAt<DepotBlockEntity>(worldId, pos);
  final ejector = ConveyanceRuntime.i.typedAt<EjectorBlockEntity>(worldId, pos);
  final behaviour = be?.depotBehaviour ?? ejector?.depotBehaviour;
  if (behaviour == null) return BlockUseResult.tryEmptyHand;
  if (!behaviour.canAcceptItems()) return BlockUseResult.success;

  final held = await ItemCodec.read(e.withItem ? e.item : null);
  final wasEmptyHanded = held.isEmpty;
  final shouldntPlaceItem = held.key == 'create:mechanical_arm';

  final main = behaviour.getHeldItemStack();
  if (main.isNotEmpty) {
    await giveToPlayer(e.player, main);
    behaviour.removeHeldItem();
    playSoundAt(world, pos, Sound.entityItemPickup, volume: .2, pitch: 1);
  }
  for (var slot = 0; slot < behaviour.processingOutputBuffer.slots; slot++) {
    final extracted = behaviour.processingOutputBuffer.extract(slot, 64);
    if (extracted.isNotEmpty) await giveToPlayer(e.player, extracted);
  }

  if (!wasEmptyHanded && !shouldntPlaceItem) {
    final transported = TransportedItemStack(held)
      ..insertedFrom = Direction.fromYRot(e.player.getYaw())
      ..prevBeltPosition = .25
      ..beltPosition = .25;
    behaviour.setHeldItem(transported);
    await e.player.getInventory().setItemInHand(hand: e.hand, item: null);
    ConveyanceRuntime.i.playCreateSound(world, pos, 'depot_slide');
  }

  be?.markDirty();
  be?.sendData();
  ejector?.markDirty();
  ejector?.sendData();
  return BlockUseResult.success;
}

/// `SharedDepotBlockMethods.onLanded`: a dropped item that lands on the depot goes onto it.
Future<double> _depotLanded(CustomBlockLandedEventData e) async {
  final world = e.targetWorld;
  final entity = world.getEntityById(id: e.entityId);
  final item = entity?.asItem();
  if (item == null) return 1.0;
  final stack = await ItemCodec.read(item.getStack());
  if (stack.isEmpty) return 1.0;

  final be = ConveyanceRuntime.i.typedAt<DepotBlockEntity>(
    world.getId(),
    e.pos.toPos(),
  );
  if (be == null) return 1.0;
  final remainder = await be.handleInsertion(
    TransportedItemStack(stack),
    Direction.down,
    simulate: false,
  );
  if (remainder.isEmpty) {
    item.discard();
  } else if (remainder.count < stack.count) {
    final host = await ItemCodec.write(remainder);
    if (host != null) await item.setStack(stack: host);
  }
  return 1.0;
}

/// `EjectorBlock.fallOn` for a living entity: launch it (items go through `_depotLanded`).
Future<double> _ejectorLanded(CustomBlockLandedEventData e) async {
  final world = e.targetWorld;
  final entity = world.getEntityById(id: e.entityId);
  if (entity == null) return 1.0;
  if (entity.asItem() != null) {
    return _depotLanded(e);
  }
  final be = ConveyanceRuntime.i.typedAt<EjectorBlockEntity>(
    world.getId(),
    e.pos.toPos(),
  );
  if (be == null) return 1.0;
  if (be.isRetracting) return 1.0;
  if (be.isPowered) return 1.0;
  if (be.launcher.getHorizontalDistance() == 0) return 1.0;
  be.activate();
  be.markDirty();
  be.sendData();
  return 1.0;
}

/// `SharedDepotBlockMethods.getComparatorInputOverride`.
FutureOr<int?> _depotComparator(CustomBlockComparatorOutputEventData e) {
  final worldId = e.targetWorld.getId();
  final pos = e.pos.toPos();
  final be = ConveyanceRuntime.i.typedAt<DepotBlockEntity>(worldId, pos);
  final ejector = ConveyanceRuntime.i.typedAt<EjectorBlockEntity>(worldId, pos);
  return _comparatorOf(be?.depotBehaviour ?? ejector?.depotBehaviour);
}

int _comparatorOf(DepotBehaviour? behaviour) {
  if (behaviour == null) return 0;
  final present = behaviour.getPresentStackSize();
  final max = behaviour.maxStackSize();
  final fraction = present / (max == 0 ? 64 : max);
  return ((fraction * 14).floor() + (fraction > 0 ? 1 : 0)).clamp(0, 15);
}
