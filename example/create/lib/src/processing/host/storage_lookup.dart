// Finds item and fluid storage next to a machine (host side): the plugin machines through
// [ItemStorageProvider] / [FluidStorageProvider], everything else (vanilla containers and
// plugin inventories) through the host's item handler, as asynchronous transfers.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/block_entity.dart';
import '../../core/pos.dart';
import '../common/capabilities.dart';
import '../common/stack.dart';
import '../common/storage.dart';
import 'stack_host.dart';

/// `Capabilities.ItemHandler.BLOCK` / `FluidHandler.BLOCK` lookups. Provided as a service by
/// the processing module (`ctx.services.require<StorageLookup>()`).
final class StorageLookup {
  final BlockEntityStore store;

  StorageLookup(this.store);

  /// The plugin machine storage at [pos] seen from [side] (`null` if the block entity does not
  /// offer any). Synchronous: plugin machines are plain Dart objects.
  ItemStorage? pluginItemStorage(String worldId, BlockPos pos, {String? side}) {
    final be = store.at(worldId, pos);
    return be is ItemStorageProvider ? (be as ItemStorageProvider).itemStorage(side) : null;
  }

  FluidStorage? pluginFluidStorage(String worldId, BlockPos pos, {String? side}) {
    final be = store.at(worldId, pos);
    return be is FluidStorageProvider ? (be as FluidStorageProvider).fluidStorage(side) : null;
  }

  /// Whether the block at [pos] has any item storage, plugin or host.
  bool hasItemStorage(World world, String worldId, BlockPos pos, {String? side}) {
    if (pluginItemStorage(worldId, pos, side: side) != null) return true;
    final h = ItemHandlers.at(world, pos, side: _side(side));
    return h != null;
  }

  /// Inserts [stack] into the host container at [pos] (a chest, a hopper, ...). Returns the
  /// remainder. Plugin machines are not host containers: use [pluginItemStorage] first.
  Future<PStack> hostInsert(World world, BlockPos pos, PStack stack, {String? side, bool simulate = false}) async {
    if (stack.isEmpty) return PStack.empty;
    final handler = ItemHandlers.at(world, pos, side: _side(side));
    if (handler == null) return stack;
    final hostStack = await HostStacks.write(stack);
    if (hostStack == null) return PStack.empty;
    final rest = await handler.insertStack(hostStack, simulate: simulate);
    return HostStacks.read(rest);
  }

  /// Extracts up to [amount] items matching [test] from the host container at [pos].
  Future<PStack> hostExtract(
    World world,
    BlockPos pos,
    int amount, {
    String? side,
    bool Function(PStack stack)? test,
    bool simulate = false,
  }) async {
    final handler = ItemHandlers.at(world, pos, side: _side(side));
    if (handler == null) return PStack.empty;
    for (var slot = 0; slot < handler.slotCount(); slot++) {
      final peek = handler.getStack(slot: slot);
      if (peek == null) continue;
      if (test != null && !test(await HostStacks.read(peek))) continue;
      final taken = handler.take(slot, amount, simulate: simulate);
      if (taken != null) return HostStacks.read(taken);
    }
    return PStack.empty;
  }

  /// The stacks of the host container at [pos] (copies), empty if there is none.
  Future<List<PStack>> hostContents(World world, BlockPos pos, {String? side}) async {
    final handler = ItemHandlers.at(world, pos, side: _side(side));
    if (handler == null) return const [];
    return [for (final s in handler.stacks) await HostStacks.read(s)];
  }

  static BlockDirection? _side(String? side) {
    if (side == null) return null;
    for (final d in BlockDirection.values) {
      if (d.name == side) return d;
    }
    return null;
  }
}

/// The key of [pos] for maps (`packPos`).
int posKey(BlockPos p) => packPos(p.x, p.y, p.z);
