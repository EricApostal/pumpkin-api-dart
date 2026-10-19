// The block entity behaviours of the conveyance contract (host side): what a machine adds to
// its block entity to process items on the belt / depot below it
// ([BeltProcessingBehaviour]), what a belt, depot or basin adds to take items directly
// ([DirectBeltInputBehaviour]) and what a belt segment or depot adds to be processed
// ([TransportedItemStackHandlerBehaviour]).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/block_entity.dart';
import '../common/stack.dart';
import 'transported_stack.dart';

export 'transported_stack.dart';

/// `BeltProcessingBehaviour`: processing of items on belts or depots below the block entity
/// (two spaces below it). Example: the mechanical press.
class BeltProcessingBehaviour extends BlockEntityBehaviour {
  static const String type = 'belt_processing';

  @override
  String get id => type;

  BeltProcessingCallback _onItemEnter = (s, i) => ProcessingResult.pass;
  BeltProcessingCallback _continueProcessing = (s, i) => ProcessingResult.pass;

  /// `whenItemEnters`.
  BeltProcessingBehaviour whenItemEnters(BeltProcessingCallback callback) {
    _onItemEnter = callback;
    return this;
  }

  /// `whileItemHeld`.
  BeltProcessingBehaviour whileItemHeld(BeltProcessingCallback callback) {
    _continueProcessing = callback;
    return this;
  }

  /// `handleReceivedItem`.
  ProcessingResult handleReceivedItem(
    TransportedItemStack stack,
    TransportedItemStackHandler inventory,
  ) => _onItemEnter(stack, inventory);

  /// `handleHeldItem`.
  ProcessingResult handleHeldItem(
    TransportedItemStack stack,
    TransportedItemStackHandler inventory,
  ) => _continueProcessing(stack, inventory);

  /// `isBlocked(world, processingSpace)`: something with a collision shape sits right above
  /// the processing space (funnels do not count). [isFunnel] / [hasCollision] answer for the
  /// block at the position above.
  static bool isBlocked({
    required bool isFunnelAbove,
    required bool hasCollisionAbove,
  }) {
    if (isFunnelAbove) return false;
    return hasCollisionAbove;
  }
}

/// `TransportedItemStackHandlerBehaviour`: added by belts and depots; machines above them find
/// it through `store.at(...)`'s `getBehaviour<TransportedItemStackHandlerBehaviour>()`.
class TransportedItemStackHandlerBehaviour extends BlockEntityBehaviour
    implements TransportedItemStackHandler {
  static const String type = 'transported_item_stack_handler';

  @override
  String get id => type;

  /// `ProcessingCallback.applyToAllItems`.
  final void Function(
    double maxDistanceFromCenter,
    TransportedResult? Function(TransportedItemStack) process,
  )
  processingCallback;
  (double, double, double) Function(TransportedItemStack transported)?
  positionGetter;

  TransportedItemStackHandlerBehaviour(
    this.processingCallback, {
    this.positionGetter,
  });

  /// `withStackPlacement`.
  TransportedItemStackHandlerBehaviour withStackPlacement(
    (double, double, double) Function(TransportedItemStack) f,
  ) {
    positionGetter = f;
    return this;
  }

  @override
  void handleCenteredProcessingOnAllItems(
    double maxDistanceFromCenter,
    TransportedResult? Function(TransportedItemStack) process,
  ) => processingCallback(maxDistanceFromCenter, process);

  @override
  void handleProcessingOnAllItems(
    TransportedResult? Function(TransportedItemStack) process,
  ) => handleCenteredProcessingOnAllItems(.51, process);

  @override
  void handleProcessingOnItem(
    TransportedItemStack item,
    TransportedResult result,
  ) => handleCenteredProcessingOnAllItems(
    .51,
    (t) => identical(t, item) ? result : null,
  );

  @override
  (double, double, double) worldPositionOf(TransportedItemStack transported) {
    final g = positionGetter;
    if (g != null) return g(transported);
    final p = owner.pos;
    return (p.x + .5, p.y + .5, p.z + .5);
  }
}

/// `DirectBeltInputBehaviour`: block entities belts can hand items to directly, in a backup
/// friendly manner (basin, saw, depot).
class DirectBeltInputBehaviour extends BlockEntityBehaviour {
  static const String type = 'direct_belt_input';

  @override
  String get id => type;

  /// `InsertionCallback`: returns the remainder.
  PStack Function(TransportedItemStack inserted, String side, bool simulate)?
  _tryInsert;
  bool Function(String side) _canInsert = (side) => true;
  bool Function(String side) _isOccupied = (side) => false;
  bool Function() _supportsBeltFunnels = () => false;

  /// Used when no insertion handler was set: tries to insert [inserted] on [side] into the
  /// default storage of the owner. Set by the owner (basin: its input inventory).
  PStack Function(TransportedItemStack inserted, String side, bool simulate)?
  defaultInsertion;

  DirectBeltInputBehaviour allowingBeltFunnelsWhen(bool Function() pred) {
    _supportsBeltFunnels = pred;
    return this;
  }

  DirectBeltInputBehaviour allowingBeltFunnels() {
    _supportsBeltFunnels = () => true;
    return this;
  }

  DirectBeltInputBehaviour onlyInsertWhen(bool Function(String side) pred) {
    _canInsert = pred;
    return this;
  }

  DirectBeltInputBehaviour considerOccupiedWhen(
    bool Function(String side) pred,
  ) {
    _isOccupied = pred;
    return this;
  }

  DirectBeltInputBehaviour setInsertionHandler(
    PStack Function(TransportedItemStack inserted, String side, bool simulate)
    callback,
  ) {
    _tryInsert = callback;
    return this;
  }

  bool canInsertFromSide(String side) => _canInsert(side);

  bool isOccupied(String side) => _isOccupied(side);

  bool get supportsBeltFunnels => _supportsBeltFunnels();

  /// `handleInsertion(transported, side, simulate)`: the remainder.
  PStack handleInsertion(
    TransportedItemStack transported,
    String side,
    bool simulate,
  ) {
    final h = _tryInsert ?? defaultInsertion;
    if (h == null) return transported.stack;
    return h(transported, side, simulate);
  }

  /// `handleInsertion(stack, side, simulate)`.
  PStack handleInsertionOfStack(PStack stack, String side, bool simulate) =>
      handleInsertion(TransportedItemStack(stack), side, simulate);
}

/// Persistence of [TransportedItemStack]s (`serializeNBT` / `read`): the field names Create's
/// client reads from a belt's update tag.
abstract final class TransportedStackNbt {
  static NbtCompound write(
    TransportedItemStack t,
    NbtCompound Function(PStack) stackNbt,
  ) {
    final nbt = NbtCompound()
      ..putCompound('Item', stackNbt(t.stack))
      ..putFloat('Pos', t.beltPosition)
      ..putFloat('PrevPos', t.prevBeltPosition)
      ..putFloat('Offset', t.sideOffset)
      ..putFloat('PrevOffset', t.prevSideOffset)
      ..putInt('InSegment', t.insertedAt)
      ..putInt('Angle', t.angle)
      ..putInt(
        'InDirection',
        t.insertedFromIndex < 0 ? 1 : t.insertedFromIndex,
      );
    if (t.processedBy != null) {
      nbt
        ..putString('FanProcessingType', t.processedBy!)
        ..putInt('FanProcessingTime', t.processingTime);
    }
    if (t.locked) nbt.putBool('Locked', true);
    if (t.lockedExternally) nbt.putBool('LockedExternally', true);
    return nbt;
  }

  static TransportedItemStack read(
    NbtCompound nbt,
    PStack Function(NbtCompound?) stackFromNbt,
  ) {
    final t = TransportedItemStack(stackFromNbt(nbt.getCompound('Item')));
    t.beltPosition = nbt.getDouble('Pos') ?? 0;
    t.prevBeltPosition = nbt.getDouble('PrevPos') ?? 0;
    t.sideOffset = nbt.getDouble('Offset') ?? 0;
    t.prevSideOffset = nbt.getDouble('PrevOffset') ?? 0;
    t.insertedAt = nbt.getInt('InSegment') ?? 0;
    t.angle = nbt.getInt('Angle') ?? 0;
    // `TransportedItemStack.read`: `Direction.from3DDataValue(getIntOr("InDirection", 0))`, so an
    // absent value falls back to `down`.
    t.insertedFrom = TransportedItemStack.directionByIndex(
      nbt.getInt('InDirection') ?? 0,
    );
    t.locked = nbt.getBool('Locked') ?? false;
    t.lockedExternally = nbt.getBool('LockedExternally') ?? false;
    final fan = nbt.getString('FanProcessingType');
    if (fan != null) {
      t.processedBy = fan;
      t.processingTime = nbt.getInt('FanProcessingTime') ?? 0;
    }
    return t;
  }
}
