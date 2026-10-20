// `DepotBehaviour` (server behaviour): the item on a depot, the items waiting to go on it, the
// processing output buffer, inserting from belts and funnels, the machine above (a
// `BeltProcessingBehaviour`) and the belt funnel that pulls the results out.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart';
import '../../../common/direction.dart';
import '../../../common/host_bridge.dart';
import '../../../common/pos.dart';
import '../../../core/block_entity.dart';
import '../../../processing/transport/transport_behaviours.dart' as pt;
import '../../behaviours/belt_interfaces.dart';
import '../../behaviours/processing_bridge.dart'
    show copyBack, fromProcessing, toProcessing;
import '../../belt/transported_item.dart';
import '../../items/inventory.dart';
import '../../items/item_codec.dart';
import '../../items/item_data.dart';
import '../../runtime.dart';
import '../funnel/funnel_block_entity.dart';
import '../transport_inventory_api.dart';
import '../transport_support.dart';

/// `DepotBehaviour`.
class DepotBehaviour extends BlockEntityBehaviour {
  static const String behaviourId = 'depot';

  @override
  String get id => behaviourId;

  TransportedItemStack? heldItem;
  List<TransportedItemStack> incoming = [];
  late final ListInventory processingOutputBuffer;

  late int Function() maxStackSize;
  bool Function() canAcceptItems = () => true;
  bool Function(Direction) canFunnelsPullFrom = (_) => true;
  void Function(ItemValue) onHeldInserted = (_) {};
  bool Function(ItemValue) acceptedItems = (_) => true;
  bool allowMerge = false;

  DepotBehaviour() {
    maxStackSize = _defaultMaxStackSize;
    processingOutputBuffer = ListInventory(
      8,
      onChanged: (_) {
        owner.markDirty();
        owner.sendData();
      },
    );
  }

  ConveyanceRuntime get rt => ConveyanceRuntime.i;

  /// `maxStackSize`: the default reads the held item's own limit (64 while empty).
  int _defaultMaxStackSize() => heldItem?.stack.maxStack ?? 64;

  BState stateAt(Pos p) => rt.stateAt(owner.worldId, p);

  void enableMerging() => allowMerge = true;

  DepotBehaviour withCallback(void Function(ItemValue) changeListener) {
    onHeldInserted = changeListener;
    return this;
  }

  DepotBehaviour onlyAccepts(bool Function(ItemValue) filter) {
    acceptedItems = filter;
    return this;
  }

  bool canMergeItems() => allowMerge;

  // -- Sub-behaviours --------------------------------------------------------------------------

  void addSubBehaviours() {
    owner.addBehaviour(
      pt.DirectBeltInputBehaviour()
        ..allowingBeltFunnels()
        ..considerOccupiedWhen(
          (side) => isOccupied(Direction.byName(side) ?? Direction.up),
        )
        ..setInsertionHandler(
          (inserted, side, simulate) => pStackOf(
            tryInsertingFromSide(
              fromProcessing(inserted),
              Direction.byName(side) ?? Direction.up,
              simulate,
            ).stack,
          ),
        ),
    );
    owner.addBehaviour(
      pt.TransportedItemStackHandlerBehaviour(applyToAllItems),
    );
  }

  // -- Tick ------------------------------------------------------------------------------------

  @override
  Future<void> tick() async {
    super.tick();
    final world = owner.world;

    for (final ts in List.of(incoming)) {
      if (!_tickStack(ts)) continue;
      if (world == null) continue;
      if (heldItem == null) {
        heldItem = ts;
      } else {
        if (!heldItem!.stack.canAmountsStack(ts.stack)) {
          rt.fire(
            'Dropping the depot overflow',
            () => dropItemAt(world, owner.pos.toPos(), ts.stack),
          );
        } else {
          heldItem!.stack = heldItem!.stack.grow(ts.stack.count);
        }
      }
      incoming.remove(ts);
      owner.markDirty();
      owner.sendData();
    }

    final held = heldItem;
    if (held == null) return;
    if (!_tickStack(held)) return;
    if (world == null) return;
    if (await _handleBeltFunnelOutput()) return;

    final machine = rt
        .beAt(owner.worldId, owner.pos.toPos().aboveBy(2))
        ?.getBehaviour<pt.BeltProcessingBehaviour>();
    if (machine == null) return;

    final above = owner.pos.toPos().above;
    final funnelAbove =
        isFunnelState(stateAt(above)) || isBeltFunnelState(stateAt(above));
    final blocked = pt.BeltProcessingBehaviour.isBlocked(
      isFunnelAbove: funnelAbove,
      hasCollisionAbove: !HostBlockGetter(world).collisionShapeEmpty(above),
    );
    if (!held.locked && blocked) return;

    final previous = held.stack;
    final wasLocked = held.locked;
    final result = wasLocked
        ? machine.handleHeldItem(toProcessing(held), _processingHandler)
        : machine.handleReceivedItem(toProcessing(held), _processingHandler);

    if (heldItem == null || result == pt.ProcessingResult.remove) {
      heldItem = null;
      owner.sendData();
      return;
    }

    held.locked = result == pt.ProcessingResult.hold;
    if (held.locked != wasLocked || held.stack != previous) owner.sendData();
  }

  bool _tickStack(TransportedItemStack held) {
    held.prevBeltPosition = held.beltPosition;
    held.prevSideOffset = held.sideOffset;
    final diff = .5 - held.beltPosition;
    if (diff > 1 / 512) {
      if (diff > 1 / 32 && !isItemUpright(held.stack)) held.angle += 1;
      held.beltPosition += diff / 4;
    }
    return diff < 1 / 16;
  }

  Future<bool> _handleBeltFunnelOutput() async {
    final above = owner.pos.toPos().above;
    final funnelState = stateAt(above);
    final facing = funnelFacing(funnelState);
    if (facing == null || !canFunnelsPullFrom(facing.opposite)) return false;
    final funnel = rt.typedAt<FunnelBlockEntity>(owner.worldId, above);
    if (funnel == null) return false;

    for (var slot = 0; slot < processingOutputBuffer.slots; slot++) {
      final previous = processingOutputBuffer.getStack(slot);
      if (previous.isEmpty) continue;
      // `DirectBeltInputBehaviour.tryExportingToBeltFunnel(stack, null, false)`: `null` means
      // the funnel above cannot take the item at all (not a pulling belt funnel, or no entity).
      final after = await funnel.tryExportingToBeltFunnel(
        previous,
        null,
        simulate: false,
      );
      if (after == null) return false;
      if (after.count != previous.count) {
        processingOutputBuffer.setStack(slot, after);
        owner.markDirty();
        owner.sendData();
        return true;
      }
    }

    final held = heldItem;
    if (held == null) return false;
    final previous = held.stack;
    final after = await funnel.tryExportingToBeltFunnel(
      previous,
      null,
      simulate: false,
    );
    if (after == null) return false;
    if (after.count != previous.count) {
      if (after.isEmpty) {
        heldItem = null;
      } else {
        held.stack = after;
      }
      owner.markDirty();
      owner.sendData();
      return true;
    }
    return false;
  }

  // -- Insertion -------------------------------------------------------------------------------

  bool isOccupied(Direction side) {
    if (getHeldItemStack().isNotEmpty && !canMergeItems()) return true;
    if (!isOutputEmpty() && !canMergeItems()) return true;
    if (!canAcceptItems()) return true;
    return false;
  }

  TransportedItemStack tryInsertingFromSide(
    TransportedItemStack transported,
    Direction side,
    bool simulate,
  ) {
    final size = transported.stack.count;
    if (isOccupied(side)) return transported;
    final copy = transported.copy()
      ..beltPosition = side.isVertical ? .5 : 0
      ..insertedFrom = side
      ..prevSideOffset = transported.sideOffset
      ..prevBeltPosition = side.isVertical ? .5 : 0;
    final remainder = insert(copy, simulate);
    if (remainder.count != size) owner.markDirty();
    copy.stack = remainder;
    return copy;
  }

  ItemValue insert(TransportedItemStack transported, bool simulate) {
    final stack = transported.stack;
    if (!canAcceptItems()) return stack;
    if (!acceptedItems(stack)) return stack;

    if (canMergeItems()) {
      final remainingSpace = getRemainingSpace();
      if (remainingSpace <= 0) return stack;
      final held = heldItem;
      if (held != null && !held.stack.canAmountsStack(stack)) return stack;

      if (remainingSpace < stack.count) {
        final returned = stack.withCount(stack.count - remainingSpace);
        if (!simulate) {
          final copy = transported.copy();
          copy.stack = stack.withCount(remainingSpace);
          if (heldItem != null) {
            incoming.add(copy);
          } else {
            heldItem = copy;
          }
        }
        return returned;
      }
      if (!simulate) {
        if (heldItem != null) {
          incoming.add(transported);
        } else {
          heldItem = transported;
        }
      }
      return ItemValue.empty;
    }

    final maxCount = stack.maxStack;
    final stackTooLarge = maxCount < stack.count;
    final returned = stackTooLarge
        ? stack.withCount(stack.count - maxCount)
        : ItemValue.empty;
    if (simulate) return returned;

    if (isEmpty()) {
      final world = owner.world;
      if (world != null) {
        final horizontal = transported.insertedFrom.isHorizontal;
        rt.playCreateSound(
          world,
          owner.pos.toPos(),
          horizontal ? 'depot_slide' : 'depot_plop',
        );
      }
    }

    if (stackTooLarge) {
      final copy = transported.copy();
      copy.stack = stack.withCount(maxCount);
      heldItem = copy;
    } else {
      heldItem = transported;
    }
    onHeldInserted(heldItem!.stack);
    owner.markDirty();
    return returned;
  }

  // -- Accessors -------------------------------------------------------------------------------

  ItemValue getHeldItemStack() => heldItem?.stack ?? ItemValue.empty;

  void setHeldItem(TransportedItemStack held) => heldItem = held;

  void setCenteredHeldItem(TransportedItemStack held) {
    heldItem = held;
    held.beltPosition = .5;
    held.prevBeltPosition = .5;
  }

  void removeHeldItem() => heldItem = null;

  int getPresentStackSize() {
    var cumulative = getHeldItemStack().count;
    for (var slot = 0; slot < processingOutputBuffer.slots; slot++) {
      cumulative += processingOutputBuffer.getStack(slot).count;
    }
    return cumulative;
  }

  int getRemainingSpace() {
    var cumulative = getPresentStackSize();
    for (final ts in incoming) {
      cumulative += ts.stack.count;
    }
    final fromGetter = math.min(
      maxStackSize() == 0 ? 64 : maxStackSize(),
      getHeldItemStack().maxStack,
    );
    return fromGetter - cumulative;
  }

  bool isEmpty() => heldItem == null && isOutputEmpty();

  bool isOutputEmpty() {
    for (var i = 0; i < processingOutputBuffer.slots; i++) {
      if (processingOutputBuffer.getStack(i).isNotEmpty) return false;
    }
    return true;
  }

  bool isItemValid(ItemValue stack) => acceptedItems(stack);

  // -- Processing bridge -----------------------------------------------------------------------

  void applyToAllItems(
    double maxDistanceFromCentre,
    pt.TransportedResult? Function(pt.TransportedItemStack) process,
  ) {
    final held = heldItem;
    if (held == null) return;
    if (.5 - held.beltPosition > maxDistanceFromCentre) return;

    final processing = toProcessing(held);
    final stackBefore = processing.stack;
    final result = process(processing);
    if (result == null || result.didntChangeFrom(stackBefore)) return;

    copyBack(processing, held);
    _applyProcessingResult(result);
  }

  /// Applies the result of an explicit `handleProcessingOnItem` call to the held item (a depot has
  /// a single item, so identity is not needed).
  void applyProcessingResult(
    pt.TransportedResult result,
    pt.TransportedItemStack item,
  ) {
    final held = heldItem;
    if (held == null) return;
    copyBack(item, held);
    if (result.doesNothing) {
      owner.markDirty();
      owner.sendData();
      return;
    }
    _applyProcessingResult(result);
  }

  void _applyProcessingResult(pt.TransportedResult result) {
    heldItem = null;
    if (result.hasHeldOutput)
      setCenteredHeldItem(fromProcessing(result.heldOutput));
    for (final added in result.outputs) {
      if (getHeldItemStack().isEmpty) {
        setCenteredHeldItem(fromProcessing(added));
        continue;
      }
      final remainder = _insertIntoBuffer(itemValueOf(added.stack));
      final world = owner.world;
      if (remainder.isNotEmpty && world != null) {
        rt.fire(
          'Dropping the depot output',
          () => dropItemAt(world, owner.pos.toPos(), remainder, dy: 1),
        );
      }
    }
    owner.markDirty();
    owner.sendData();
  }

  /// The pure (`ItemValue`) view of [applyToAllItems], used by belts and chutes above the depot.
  void applyToAllItemsPure(
    double maxDistanceFromCentre,
    ItemProcessor process,
  ) {
    final held = heldItem;
    if (held == null) return;
    if (.5 - held.beltPosition > maxDistanceFromCentre) return;

    final before = held.stack;
    final result = process(held);
    if (result == null || result.didntChangeFrom(before)) return;

    heldItem = null;
    if (result.hasHeldOutput) setCenteredHeldItem(result.heldOutput!);
    for (final added in result.outputs!) {
      if (getHeldItemStack().isEmpty) {
        setCenteredHeldItem(added);
        continue;
      }
      final remainder = _insertIntoBuffer(added.stack);
      final world = owner.world;
      if (remainder.isNotEmpty && world != null) {
        rt.fire(
          'Dropping the depot output',
          () => dropItemAt(world, owner.pos.toPos(), remainder, dy: 1),
        );
      }
    }
    owner.markDirty();
    owner.sendData();
  }

  ItemValue _insertIntoBuffer(ItemValue stack) {
    var rest = stack;
    for (
      var slot = 0;
      slot < processingOutputBuffer.slots && rest.isNotEmpty;
      slot++
    ) {
      rest = processingOutputBuffer.insert(slot, rest);
    }
    return rest;
  }

  late final _DepotProcessingHandler _processingHandler =
      _DepotProcessingHandler(this);

  // -- Persistence -----------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    final held = heldItem;
    if (held != null)
      tag.putCompound(
        'HeldItem',
        _writeTransported(held, clientPacket: clientPacket),
      );
    // `processingOutputBuffer.serializeNBT`: `{Size, Items:[{Slot, ...}]}` under `OutputBuffer`.
    tag.putCompound(
      'OutputBuffer',
      NbtCompound()
        ..putInt('Size', processingOutputBuffer.slots)
        ..putList('Items', [
          for (var i = 0; i < processingOutputBuffer.slots; i++)
            if (processingOutputBuffer.getStack(i).isNotEmpty)
              (ItemCodec.toTag(
                    processingOutputBuffer.getStack(i),
                    clientPacket: clientPacket,
                  )
                ..putInt('Slot', i)),
        ]),
    );
    if (canMergeItems() && incoming.isNotEmpty) {
      tag.putList('Incoming', [
        for (final t in incoming)
          _writeTransported(t, clientPacket: clientPacket),
      ]);
    }
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    heldItem = null;
    final held = tag.getCompound('HeldItem');
    if (held != null) heldItem = _readTransported(held);
    processingOutputBuffer.clear();
    final outputs = tag.getCompound('OutputBuffer');
    for (final e in outputs?.getList('Items') ?? const <Object>[]) {
      if (e is! NbtCompound) continue;
      final slot = e.getInt('Slot') ?? -1;
      if (slot < 0 || slot >= processingOutputBuffer.slots) continue;
      processingOutputBuffer.setStack(slot, ItemCodec.fromAnyNbt(e));
    }
    incoming = [];
    if (canMergeItems()) {
      for (final e in tag.getList('Incoming') ?? const <Object>[]) {
        if (e is NbtCompound) incoming.add(_readTransported(e));
      }
    }
  }

  NbtCompound _writeTransported(
    TransportedItemStack t, {
    required bool clientPacket,
  }) {
    final item = ItemCodec.toTag(t.stack, clientPacket: clientPacket);
    if (!clientPacket) {
      // The contraption's mounted storage reads `Item` as a vanilla stack.
      item
        ..putString('id', t.stack.isEmpty ? 'minecraft:air' : t.stack.key)
        ..putInt('count', t.stack.count);
    }
    final nbt = NbtCompound()
      ..putCompound('Item', item)
      ..putFloat('Pos', t.beltPosition)
      ..putFloat('PrevPos', t.prevBeltPosition)
      ..putFloat('Offset', t.sideOffset)
      ..putFloat('PrevOffset', t.prevSideOffset)
      ..putInt('InSegment', t.insertedAt)
      ..putInt('Angle', t.angle)
      ..putInt('InDirection', t.insertedFrom.data3d);
    // `TransportedItemStack.serializeNBT`: a held depot item keeps its processing state and its
    // locks, otherwise a locked item comes back unlocked after a reload.
    if (t.processedBy != null) {
      nbt
        ..putString('FanProcessingType', t.processedBy!)
        ..putInt('FanProcessingTime', t.processingTime);
    }
    if (t.locked) nbt.putBool('Locked', true);
    if (t.lockedExternally) nbt.putBool('LockedExternally', true);
    return nbt;
  }

  TransportedItemStack _readTransported(NbtCompound tag) {
    final t = TransportedItemStack(
      ItemCodec.fromAnyNbt(tag.getCompound('Item')),
    );
    t.beltPosition = tag.getDouble('Pos') ?? 0;
    t.prevBeltPosition = tag.getDouble('PrevPos') ?? 0;
    t.sideOffset = tag.getDouble('Offset') ?? 0;
    t.prevSideOffset = tag.getDouble('PrevOffset') ?? 0;
    t.insertedAt = tag.getInt('InSegment') ?? 0;
    t.angle = tag.getInt('Angle') ?? 0;
    t.insertedFrom = Direction.from3DDataValue(tag.getInt('InDirection') ?? 0);
    t.locked = tag.getBool('Locked') ?? false;
    t.lockedExternally = tag.getBool('LockedExternally') ?? false;
    final fan = tag.getString('FanProcessingType');
    if (fan != null) {
      t.processedBy = fan;
      t.processingTime = tag.getInt('FanProcessingTime') ?? 0;
    }
    return t;
  }

  @override
  void onRemoved() {
    final world = owner.world;
    if (world == null) return;
    final pos = owner.pos.toPos();
    for (var slot = 0; slot < processingOutputBuffer.slots; slot++) {
      final stack = processingOutputBuffer.getStack(slot);
      if (stack.isNotEmpty)
        rt.fire(
          'Dropping the depot output',
          () => dropItemAt(world, pos, stack),
        );
    }
    for (final t in incoming) {
      if (t.stack.isNotEmpty)
        rt.fire(
          'Dropping the depot input',
          () => dropItemAt(world, pos, t.stack),
        );
    }
    final held = getHeldItemStack();
    if (held.isNotEmpty)
      rt.fire('Dropping the depot item', () => dropItemAt(world, pos, held));
    processingOutputBuffer.clear();
    incoming.clear();
    heldItem = null;
  }
}

/// The processing `TransportedItemStackHandler` a machine above the depot sees.
final class _DepotProcessingHandler implements pt.TransportedItemStackHandler {
  final DepotBehaviour behaviour;

  _DepotProcessingHandler(this.behaviour);

  @override
  void handleCenteredProcessingOnAllItems(
    double maxDistanceFromCenter,
    pt.TransportedResult? Function(pt.TransportedItemStack) process,
  ) => behaviour.applyToAllItems(maxDistanceFromCenter, process);

  @override
  void handleProcessingOnAllItems(
    pt.TransportedResult? Function(pt.TransportedItemStack) process,
  ) => handleCenteredProcessingOnAllItems(.51, process);

  @override
  void handleProcessingOnItem(
    pt.TransportedItemStack item,
    pt.TransportedResult result,
  ) => behaviour.applyProcessingResult(result, item);

  @override
  (double, double, double) worldPositionOf(
    pt.TransportedItemStack transported,
  ) {
    final p = behaviour.owner.pos;
    return (p.x + .5, p.y + .5, p.z + .5);
  }
}
