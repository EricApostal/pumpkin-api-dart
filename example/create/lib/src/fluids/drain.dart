// `ItemDrainBlockEntity` (host side): takes items from belts, hoppers and the
// player's hand, empties them into its 1500 mB tank and lets the item move on.
// The emptying itself is the pure `GenericItemEmptying`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../common/direction.dart';
import '../common/nbt_convert.dart';
import '../common/pos.dart';
import '../conveyance/items/stack_bridge.dart' show fromPStack, toPStack;
import '../conveyance/transport/funnel/funnel_block_entity.dart'
    show FunnelBlockEntity;
import '../core/block_entity.dart';
import '../processing/common/stack.dart';
import '../processing/host/stack_host.dart';
import '../processing/transport/transport_behaviours.dart';
import 'fluid_host.dart';
import 'fluid_runtime.dart';
import 'fluid_stack.dart';
import 'fluid_storage.dart';
import 'generic_item_fluid.dart';
import 'nbt_util.dart';

/// `ItemDrainBlockEntity`.
class ItemDrainBlockEntity extends CreateBlockEntity
    implements FluidCapable, SidedFluidCapable {
  /// `FILLING_TIME`.
  static const int fillingTime = 20;

  late final SmartFluidTank tank;
  late final DirectBeltInputBehaviour beltInput;

  /// The item being emptied (`heldItem`).
  TransportedItemStack? heldItem;

  /// `processingTicks`.
  int processingTicks = 0;

  /// `internalTank.allowInsertion()` / `forbidInsertion()`.
  bool _allowInsertion = false;

  /// The item handlers of the horizontal sides (`ItemDrainItemHandler`).
  late final Map<Direction, ItemDrainItemHandler> itemHandlers = {
    for (final d in Direction.horizontals) d: ItemDrainItemHandler(this, d),
  };

  ItemDrainBlockEntity(super.worldId, super.pos) {
    tank = SmartFluidTank(
      1500,
      (_) => sendData(),
      validator: (_) => _allowInsertion,
    );
    beltInput = addBehaviour(DirectBeltInputBehaviour())
      ..allowingBeltFunnels()
      ..setInsertionHandler(_tryInsertingFromSide);
  }

  GenericItemEmptying get emptying => GenericItemEmptying(
    FluidsRuntime.instance.rules,
    FluidsRuntime.instance.recipes,
  );

  /// Fills the tank while insertion is allowed (the processing and the player's
  /// use); returns whether all of [fluid] was accepted.
  bool insertFluid(FStack fluid, {required bool simulate}) {
    _allowInsertion = true;
    final accepted = tank.fill(fluid, simulate: simulate);
    _allowInsertion = false;
    return accepted == fluid.amount;
  }

  @override
  FluidStorage? get fluidHandler => tank;

  /// `ItemDrainBlockEntity.registerCapabilities`: no handler from above.
  @override
  FluidStorage? fluidHandlerAt(Direction? side) =>
      side == Direction.up ? null : tank;

  PStack get heldItemStack => heldItem?.stack ?? PStack.empty;

  static FluidItemSpec _item(PStack stack) => stack.isEmpty
      ? FluidItemSpec.empty
      : FluidItemSpec(stack.key, stack.count, stack.comps);

  static PStack _stack(FluidItemSpec item) => item.isEmpty
      ? PStack.empty
      : PStack(item.key, item.count, comps: item.comps);

  /// `tryInsertingFromSide`.
  PStack _tryInsertingFromSide(
    TransportedItemStack transported,
    String side,
    bool simulate,
  ) {
    var inserted = transported.stack;
    var returned = PStack.empty;

    if (heldItemStack.isNotEmpty) return inserted;

    if (inserted.count > 1 && emptying.canItemBeEmptied(_item(inserted))) {
      returned = inserted.withCount(inserted.count - 1);
      inserted = inserted.withCount(1);
    }

    if (simulate) return returned;

    final copy = transported.copy();
    copy.stack = inserted;
    final d = Direction.byName(side);
    copy.beltPosition = d != null && d.axis == Axis.y ? .5 : 0;
    copy.prevSideOffset = copy.sideOffset;
    copy.prevBeltPosition = copy.beltPosition;
    setHeldItem(copy, side);
    sendData();
    return returned;
  }

  /// `setHeldItem(heldItem, insertedFrom)`.
  void setHeldItem(TransportedItemStack item, String side) {
    item.insertedFrom = side;
    heldItem = item;
  }

  @override
  void tick() {
    super.tick();
    final held = heldItem;
    if (held == null) {
      processingTicks = 0;
      return;
    }

    if (processingTicks > 0) {
      held.prevBeltPosition = .5;
      final wasAtBeginning = processingTicks == fillingTime;
      processingTicks--;
      if (!_continueProcessing()) {
        processingTicks = 0;
        sendData();
        return;
      }
      if (wasAtBeginning != (processingTicks == fillingTime)) sendData();
      return;
    }

    held.prevBeltPosition = held.beltPosition;
    held.prevSideOffset = held.sideOffset;
    held.beltPosition += 1 / 8;

    if (held.beltPosition > 1) {
      held.beltPosition = 1;
      unawaited(_export(held));
      return;
    }

    if (held.prevBeltPosition < .5 && held.beltPosition >= .5) {
      if (!emptying.canItemBeEmptied(_item(held.stack))) return;
      held.beltPosition = .5;
      processingTicks = fillingTime;
      sendData();
    }
  }

  /// `DirectBeltInputBehaviour.tryExportingToBeltFunnel(stack, side, simulate)`: the belt funnel
  /// above the drain takes the item before the belt on the output side does.
  Future<PStack?> _tryExportingToBeltFunnel(
    PStack stack,
    Direction? side, {
    required bool simulate,
  }) async {
    final above = BlockPos(x: this.pos.x, y: this.pos.y + 1, z: this.pos.z);
    final funnel = store.at(worldId, above);
    if (funnel is! FunnelBlockEntity) return null;
    final result = await funnel.tryExportingToBeltFunnel(
      fromPStack(stack),
      side,
      simulate: simulate,
    );
    return result == null ? null : toPStack(result);
  }

  /// The part of `tick()` that hands the item to the belt or drops it.
  Future<void> _export(TransportedItemStack held) async {
    final side = Direction.byName(held.insertedFrom) ?? Direction.up;

    // `ItemDrainBlockEntity.tick`: a pulling belt funnel above the drain gets the item first.
    // `null` means there is no belt funnel above; an unchanged stack means it refused the item.
    final funnelResult = await _tryExportingToBeltFunnel(
      held.stack,
      side.opposite,
      simulate: false,
    );
    if (funnelResult != null) {
      if (funnelResult.count != held.stack.count) {
        if (funnelResult.isEmpty) {
          heldItem = null;
        } else {
          held.stack = funnelResult;
        }
        sendData();
        return;
      }
      if (funnelResult.isNotEmpty) return;
    }

    final next = (this.pos.x, this.pos.y, this.pos.z).relative(side);
    final be = store.at(worldId, BlockPos(x: next.$1, y: next.$2, z: next.$3));
    final input = be?.getBehaviour<DirectBeltInputBehaviour>();
    if (input != null) {
      if (!input.canInsertFromSide(side.serializedName)) return;
      final returned = input.handleInsertion(held, side.serializedName, false);
      if (returned.isEmpty) {
        // `ItemDrainBlockEntity.tick`: a drain feeding another drain awards CHAINED_DRAIN.
        if (be is ItemDrainBlockEntity) {
          FluidsRuntime.instance.award(worldId, (
            this.pos.x,
            this.pos.y,
            this.pos.z,
          ), 'chained_drain');
        }
        heldItem = null;
        sendData();
        return;
      }
      if (returned.count != held.stack.count) {
        held.stack = returned;
        sendData();
      }
      return;
    }

    // No belt: eject the item into the world unless the next block is a solid wall
    // (`BlockHelper.hasBlockSolidSide`).
    final level = FluidsRuntime.instance.levelOf(worldId);
    if (level != null && level.isFaceSturdy(next, side.opposite)) return;
    final ejected = held.stack;
    heldItem = null;
    sendData();
    unawaited(_eject(ejected, next, side));
  }

  Future<void> _eject(PStack stack, (int, int, int) at, Direction side) async {
    final w = world;
    if (w == null) return;
    final item = await HostStacks.write(stack);
    if (item == null) return;
    await w.dropItem((
      at.$1 + .5 + side.stepX * .75,
      at.$2 + .5,
      at.$3 + .5 + side.stepZ * .75,
    ), item);
  }

  /// `continueProcessing()`.
  bool _continueProcessing() {
    final held = heldItem;
    if (held == null) return false;
    if (processingTicks < 5) return true;
    if (!emptying.canItemBeEmptied(_item(held.stack))) return false;

    final (fluid, _, _) = emptying.emptyItem(_item(held.stack), simulate: true);

    if (processingTicks > 5) {
      _allowInsertion = true;
      final fits = tank.fill(fluid, simulate: true) == fluid.amount;
      _allowInsertion = false;
      if (!fits) {
        processingTicks = fillingTime;
        return true;
      }
      return true;
    }

    final (resultFluid, remainder, _) = emptying.emptyItem(
      _item(held.stack),
      simulate: false,
    );
    FluidsRuntime.instance.award(worldId, (
      this.pos.x,
      this.pos.y,
      this.pos.z,
    ), 'drain');

    if (remainder.isEmpty) {
      heldItem = null;
    } else {
      held.stack = _stack(remainder);
    }
    _allowInsertion = true;
    tank.fill(resultFluid, simulate: false);
    _allowInsertion = false;
    sendData();
    return true;
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    heldItem = null;
    processingTicks = tag.getInt('ProcessingTicks') ?? 0;
    final held = tag.getCompound('HeldItem');
    if (held != null) heldItem = TransportedStackNbt.read(held, StackNbt.read);
    final fluid = tag.getCompound('Tank');
    if (fluid != null) tank.rawSet(readFluidTankNbt(valueOfCompound(fluid)));
    // `SmartFluidTankBehaviour` writes one `TankSegment` per tank under `Tanks`.
    final tanks = tag.getList('Tanks');
    if (tanks != null && tanks.isNotEmpty) {
      final first = tanks.first;
      if (first is NbtCompound) {
        tank.rawSet(readTankSegmentNbt(valueOfCompound(first)));
      }
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('ProcessingTicks', processingTicks);
    final held = heldItem;
    if (held != null)
      tag.putCompound(
        'HeldItem',
        TransportedStackNbt.write(held, StackNbt.write),
      );
    // `SmartFluidTankBehaviour.write`: a single tank under `Tanks`, each entry a
    // `{TankContent, Level}` segment (the legacy `Tank` key is still read).
    tag.putList('Tanks', [
      compoundOf(tankSegmentNbt(tank.fluid, tank.tankCapacity(0))),
    ]);
  }
}

/// `ItemDrainItemHandler`: the one slot item view of the drain seen from [side]
/// (`ItemDrainItemHandler.java:18-100`; `ItemDrainBlockEntity.registerCapabilities` offers it
/// for the horizontal sides only, with the custom insert / extract semantics below).
///
/// **Host gap**: the handler is not attached as a block capability, so hoppers, belts and
/// funnels cannot feed the drain. The host can give a plugin block entity a *fixed* inventory
/// (`PluginInventories.register`, `item-handler.wit`) and nothing else: such a slot takes a
/// whole stack, while this handler accepts one item of an emptyable stack and hands the rest
/// back (`insertItem`), and its extract removes the item being processed. Attaching a fixed
/// inventory would silently change those semantics rather than port them, so the drain keeps
/// the handler for its own code (the belt insertion goes through
/// [ItemDrainBlockEntity.tryInsertingFromSide]) and the item side of the drain stays
/// player-only until the host can carry a custom handler.
final class ItemDrainItemHandler {
  final ItemDrainBlockEntity blockEntity;
  final Direction side;

  const ItemDrainItemHandler(this.blockEntity, this.side);

  /// `getSlots()`.
  int get slots => 1;

  /// `getStackInSlot(slot)`.
  PStack getStackInSlot(int slot) => blockEntity.heldItemStack;

  /// `insertItem(slot, stack, simulate)`: the remainder.
  PStack insertItem(int slot, PStack stack, {required bool simulate}) {
    if (blockEntity.heldItemStack.isNotEmpty) return stack;

    var inserted = stack;
    PStack returned;
    if (inserted.count > 1 &&
        blockEntity.emptying.canItemBeEmptied(
          FluidItemSpec(inserted.key, inserted.count, inserted.comps),
        )) {
      returned = inserted.withCount(inserted.count - 1);
      inserted = inserted.withCount(1);
    } else {
      // `ItemHelper.limitCountToMaxStackSize`.
      final max = inserted.maxCount;
      if (inserted.count > max) {
        returned = inserted.withCount(inserted.count - max);
        inserted = inserted.withCount(max);
      } else {
        returned = PStack.empty;
      }
    }

    if (!simulate) {
      blockEntity.setHeldItem(
        TransportedItemStack(inserted),
        side.opposite.serializedName,
      );
      blockEntity.sendData();
    }
    return returned;
  }

  /// `extractItem(slot, amount, simulate)`.
  PStack extractItem(int slot, int amount, {required bool simulate}) {
    final held = blockEntity.heldItem;
    if (held == null || amount <= 0) return PStack.empty;
    final extracted = held.stack.withCount(
      amount < held.stack.count ? amount : held.stack.count,
    );
    if (!simulate) {
      final left = held.stack.count - extracted.count;
      if (left <= 0) {
        blockEntity.heldItem = null;
      } else {
        held.stack = held.stack.withCount(left);
      }
      blockEntity.sendData();
    }
    return extracted;
  }

  /// `getSlotLimit(slot)`.
  int getSlotLimit(int slot) => 64;

  /// `isItemValid(slot, stack)`.
  bool isItemValid(int slot, PStack stack) => true;
}
