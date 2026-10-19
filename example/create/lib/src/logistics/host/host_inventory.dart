// The host's item handlers as [ItemInv] (`CreateItemHandler.of(handler)`).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../model/inventory.dart';
import '../model/stack.dart';
import 'stack_io.dart';

/// An [ItemHandler] of the host (one side of a container) seen as an [ItemInv].
final class HostInv implements ItemInv, StackedInserter {
  final ItemHandler handler;
  final StackIo io;

  HostInv(this.handler, this.io);

  @override
  int get slots => handler.slotCount();

  @override
  Future<LStack> stackAt(int slot) => io.read(handler.getStack(slot: slot));

  @override
  Future<int> slotLimit(int slot) async => handler.getSlotLimit(slot: slot);

  @override
  Future<bool> isValid(int slot, LStack stack) async {
    final hs = await io.write(stack);
    if (hs == null) return false;
    return handler.isItemValid(slot: slot, stack: hs);
  }

  @override
  Future<LStack> extract(int slot, int amount, {bool simulate = false}) async {
    if (amount <= 0) return LStack.empty;
    final taken = handler.extract(slot: slot, amount: amount.clamp(0, 255), simulate: simulate);
    return io.read(taken);
  }

  @override
  Future<LStack> insert(int slot, LStack stack, {bool simulate = false}) async {
    final hs = await io.write(stack);
    if (hs == null) return LStack.empty;
    final rest = await handler.insert(slot: slot, stack: hs, simulate: simulate);
    return io.read(rest);
  }

  @override
  Future<LStack> insertAnywhere(LStack stack, {bool simulate = false}) async {
    final hs = await io.write(stack);
    if (hs == null) return LStack.empty;
    final rest = await handler.insert(slot: null, stack: hs, simulate: simulate);
    return io.read(rest);
  }
}

/// Finds the inventory at [pos] seen from [side] (`null` side: all slots).
HostInv? hostInvAt(World world, BlockPos pos, StackIo io, {BlockDirection? side}) {
  final h = ItemHandlers.at(world, pos, side: side);
  return h == null ? null : HostInv(h, io);
}
