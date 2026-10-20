// The item hatch block and its block entity (`ItemHatchBlock`, `ItemHatchBlockEntity`): deposits
// the player's items into the inventory behind it, filtered by its filter slot.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;
import '../../conveyance/transport/hatch/item_hatch_logic.dart';
import '../model/package.dart';
import '../port/conveyance_items.dart';
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart';
import '../filter/filtering_behaviour.dart';
import '../host/host_inventory.dart';
import '../host/lg_block_entity.dart';
import '../host/link_keys.dart';
import '../host/lvl.dart';
import '../host/player_items.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import '../model/inventory.dart';
import '../model/stack.dart';

/// `ItemHatchBlockEntity`: only the filter slot.
class ItemHatchBlockEntity extends LgBlockEntity {
  static const String type = 'create:item_hatch';

  late FilteringBehaviour filtering;

  final Map<String, dynamic> _state = {};

  ItemHatchBlockEntity(super.worldId, super.pos) {
    filtering = addBehaviour(FilteringBehaviour());
  }

  @override
  Map<String, dynamic> get state => _state;

  @override
  void readState(Map<String, dynamic> map) {
    _state
      ..clear()
      ..addAll(map);
  }

  @override
  Map<String, dynamic> stateToMap() => {
    'Filter': filtering.filterItem.isEmpty
        ? null
        : filtering.filterItem.toJson(),
  };

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    // The behaviour reads the Java `Filter` key; the JSON is only the fallback for old saves.
    if (!tag.containsKey('Filter')) {
      final saved = state['Filter'];
      if (saved is String) filtering.setFilter(LStackMapper.fromJson(saved));
    }
  }

  @override
  void onRemoved() {
    filtering.setFilter(LStack.empty);
    super.onRemoved();
  }
}

/// `ItemHatchBlock`.
CreateBlock itemHatchBlock() => CreateBlock(
  key: 'create:item_hatch',
  properties: [
    horizontalFacingProperty,
    CreateProps.open,
    CreateProps.waterlogged,
  ],
  hardness: 3,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'netherite_block',
  blockEntityType: ItemHatchBlockEntity.type,
  placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
  behavior: BlockBehavior(onUse: _onUse, onScheduledTick: _onScheduledTick),
);

Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
  final be = Lg.i.store.typed<ItemHatchBlockEntity>(
    e.targetWorld.getId(),
    e.pos,
  );
  if (be == null) return BlockUseResult.pass;
  if (!e.withItem) return BlockUseResult.pass;

  final info = BlockStates.info(e.targetWorld.getBlockStateId(pos: e.pos));
  final facing =
      Direction.byName(info?.properties['facing'] ?? 'north') ??
      Direction.north;
  final world = e.targetWorld;
  final targetPos = e.pos.toPos().relative(facing);
  final targetInv = inventoryAt(
    e.targetWorld.getId(),
    targetPos,
    Lg.i.io,
  );
  if (targetInv == null) return BlockUseResult.pass;

  final inventory = playerInventory(e.player);
  final depositInHand = !e.sneaking;
  if (!depositInHand) {
    // A sneaking use with a wrench belongs to the wrench, not to the hatch.
    final held = await Lg.i.read(e.item);
    if (held.key == 'create:wrench') {
      inventory.dispose();
      return BlockUseResult.tryEmptyHand;
    }
  }
  final selected = e.player.getSelectedSlot();
  var anyInserted = false;

  for (var slot = 0; slot < inventory.getSize(); slot++) {
    if (!hatchConsidersSlot(
      slot,
      depositItemInHand: depositInHand,
      selectedSlot: selected,
    )) {
      continue;
    }

    final hostStack = inventory.getItem(slot: slot);
    if (hostStack == null) continue;
    final stack = await Lg.i.read(hostStack);
    if (stack.isEmpty) continue;

    // `Item.canFitInsideContainerItems()`: shulker boxes stay in the inventory.
    // `PackageItem` overrides the rule, so a box always fits.
    if (!PackageItem.isPackage(stack) && !canFitInsideContainerItems(toItemValue(stack, Lg.i.wire))) {
      continue;
    }

    if (be.filtering.filterItem.isNotEmpty && !be.filtering.test(stack))
      continue;

    final remainder = await insertStacked(targetInv, stack, simulate: true);
    if (remainder.count == stack.count) continue;

    final toInsert = stack.withCount(stack.count - remainder.count);
    final removed = await inventory.removeItem(slot: slot);
    final rest = removed == null ? LStack.empty : await Lg.i.read(removed);
    final leftover = await insertStacked(targetInv, toInsert);
    anyInserted = true;
    if (leftover.isNotEmpty) {
      // Edge case: the handler accepted less than the simulation promised.
      final host = await Lg.i.write(rest.withCount(leftover.count));
      if (host != null) await inventory.setItem(slot: slot, item: host);
    } else if (rest.count > toInsert.count) {
      final host = await Lg.i.write(
        rest.withCount(rest.count - toInsert.count),
      );
      if (host != null) await inventory.setItem(slot: slot, item: host);
    }
  }

  if (!anyInserted) {
    inventory.dispose();
    return BlockUseResult.success;
  }

  await Lvl(world).setProps(e.pos.toPos(), {'open': 'true'}, neighbors: true);
  world.scheduleBlockTick(
    pos: e.pos,
    delayTicks: 10,
    priority: TickPriority.normal,
  );
  inventory.dispose();
  return BlockUseResult.success;
}

Future<void> _onScheduledTick(Server server, CustomBlockTickEventData e) async {
  final stateId = e.targetWorld.getBlockStateId(pos: e.pos);
  final info = BlockStates.info(stateId);
  if (info?.properties['open'] != 'true') return;
  await e.targetWorld.setBlockState(
    pos: e.pos,
    state: BlockStates.setValues(stateId, {'open': 'false'}),
    updateFlags: BlockUpdateFlags.clientsOnly,
  );
}

/// The `item_hatch` part.
final class ItemHatchPart extends LogisticsPart {
  @override
  String get name => 'itemhatch';

  @override
  void register(CreateRegistry registry) {
    registry.block(itemHatchBlock());
    registry.blockEntityType(
      const BlockEntityTypeSpec(
        key: ItemHatchBlockEntity.type,
        validBlocks: ['create:item_hatch'],
        create: ItemHatchBlockEntity.new,
        tickInterval: 1,
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, LgRuntime rt) {
    unawaited(Future<void>.value());
  }
}
