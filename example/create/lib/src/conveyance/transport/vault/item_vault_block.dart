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
    // `ItemVaultBlock.getStateForPlacement`: continue the axis of the vault we are placed on,
    // otherwise face the player's horizontal direction. Sneaking skips the first rule.
    final rt = ConveyanceRuntime.i;
    final click = rt.clickFor(e.player, pos);
    Axis? preferred;
    if (click != null && !click.sneaking) {
      final placedOn = rt.stateAt(worldId, pos.relative(click.face.opposite));
      if (isVaultState(placedOn)) preferred = placedOn.axisOf('axis');
    }
    final player = rt.playerOf(server, e.player);
    preferred ??= player == null
        ? null
        : Direction.fromYRot(player.getYaw()).axis;
    if (preferred != null)
      state = state.setValue('axis', preferred.serializedName);
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
  if (!c.face.toDirection().isVertical) {
    // `IWrenchable.getRotatedBlockState`: only a vertical click rotates `HORIZONTAL_AXIS`; a
    // horizontal click leaves the vault as it is (the click is still consumed).
    return WrenchResult.success;
  }
  final be = ConveyanceRuntime.i.typedAt<ItemVaultBlockEntity>(worldId, pos);
  if (be != null) {
    ConnectivityHandler.splitMulti(vaultMultiWorld(worldId), be);
    be.removeController(true);
  }
  // Java clears `LARGE` and then runs the default wrench rotation, which turns `HORIZONTAL_AXIS`
  // a quarter turn about the vertical click axis: x <-> z.
  final axis = state.axisOf('axis') ?? Axis.x;
  await writeState(
    world,
    pos,
    state
        .setFlag('large', false)
        .setValue('axis', axis == Axis.x ? 'z' : 'x'),
  );
  return WrenchResult.success;
}
