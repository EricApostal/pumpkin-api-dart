// `ItemVaultBlock`: the vault's placement (axis and multiblock), the comparator output and the
// wrench (split on a vertical face, rotate the axis otherwise).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart';
import '../../../api/wrenchable.dart';
import '../../../common/direction.dart';
import '../../../common/host_bridge.dart';
import '../../../common/pos.dart';
import '../../../core/block_entity.dart';
import '../../../core/registry.dart';
import '../../../fluids/connectivity.dart';
import '../../items/inventory.dart';
import '../../runtime.dart';
import '../transport_support.dart';
import 'item_vault_block_entity.dart';

/// Phase 1: the item vault block and its block entity.
void registerVault(CreateRegistry registry) {
  final block = manifestBlock(
    'item_vault',
    blockEntityType: 'create:item_vault',
    behavior: _vaultBehavior(),
  );
  registry.block(block);
  transportBlocks[block.key] = block;
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: 'create:item_vault',
      validBlocks: const ['create:item_vault'],
      create: ItemVaultBlockEntity.new,
      tickInterval: 1,
    ),
  );
}

/// Phase 3: the wrench action of the vault.
void registerVaultWrench(WrenchRegistry wrench) {
  wrench.register(
    'create:item_vault',
    const CallbackWrenchable(onWrenchedOverride: _wrenchVault),
  );
}

BlockBehavior _vaultBehavior() => BlockBehavior(
  onPlaced: (server, e) async {
    final world = e.targetWorld;
    final worldId = world.getId();
    final pos = e.pos.toPos();
    var state = transportState(e.block, e.stateIndex);
    // The placement context is not passed to this event; keep the axis of a neighbouring vault.
    for (final d in [
      Direction.down,
      Direction.north,
      Direction.south,
      Direction.east,
      Direction.west,
    ]) {
      final neighbour = ConveyanceRuntime.i.stateAt(worldId, pos.relative(d));
      if (isVaultState(neighbour)) {
        final axis = neighbour.axisOf('axis');
        if (axis != null) {
          state = state.setValue('axis', axis.serializedName);
          break;
        }
      }
    }
    if (state != transportState(e.block, e.stateIndex))
      await writeState(world, pos, state);
    ConveyanceRuntime.i
        .typedAt<ItemVaultBlockEntity>(worldId, pos)
        ?.updateConnectivity();
  },
  onComparatorOutput: (server, e) async {
    final be = ConveyanceRuntime.i.typedAt<ItemVaultBlockEntity>(
      e.targetWorld.getId(),
      e.pos.toPos(),
    );
    if (be == null) return 0;
    final controller = be.isController
        ? be
        : ConveyanceRuntime.i.typedAt<ItemVaultBlockEntity>(
            be.worldId,
            be.controller,
          );
    final inv = controller?.itemInventory(null);
    if (inv == null) return 0;
    return await redstoneFromInventory(inv);
  },
);

Future<WrenchResult> _wrenchVault(WrenchContext c) async {
  final world = c.world;
  final worldId = world.getId();
  final pos = c.pos.toPos();
  final state = ConveyanceRuntime.i.stateAt(worldId, pos);
  if (c.face.toDirection().isVertical) {
    final be = ConveyanceRuntime.i.typedAt<ItemVaultBlockEntity>(worldId, pos);
    if (be != null) {
      ConnectivityHandler.splitMulti(vaultMultiWorld(worldId), be);
      be.removeController(true);
    }
    await writeState(world, pos, state.setFlag('large', false));
    return WrenchResult.success;
  }
  final axis = state.axisOf('axis') ?? Axis.x;
  await writeState(
    world,
    pos,
    state.setValue('axis', axis == Axis.x ? 'z' : 'x'),
  );
  return WrenchResult.success;
}
