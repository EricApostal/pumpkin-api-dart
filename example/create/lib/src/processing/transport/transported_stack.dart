// `TransportedItemStack` and `TransportedResult` (pure): the unit belts and depots move,
// and what the machines above them answer. Belts, depots, funnels and chutes are owned by
// the conveyance side of the mod; the processing machines (press, saw, deployer, fan, crusher)
// only see these types.
import 'dart:math';

import '../common/stack.dart';

/// `Direction.get3DDataValue` order: down, up, north, south, west, east.
const List<String> _directionNames = ['down', 'up', 'north', 'south', 'west', 'east'];

/// `TransportedItemStack`.
class TransportedItemStack implements Comparable<TransportedItemStack> {
  static final Random _random = Random();

  PStack stack;
  double beltPosition = 0;
  double sideOffset = 0;
  int angle = 0;
  int insertedAt = 0;

  /// `Direction` name the item entered from (`up` by default).
  String insertedFrom = 'up';
  bool locked = false;
  bool lockedExternally = false;

  double prevBeltPosition = 0;
  double prevSideOffset = 0;

  /// The key of the `FanProcessingType` that is processing the item (`create:splashing`), and
  /// how long it already did.
  String? processedBy;
  int processingTime = 0;

  /// Creates the transported form of [stack]. [upright] is `BeltHelper.isItemUpright` (the
  /// item stands on the belt, angle 180); [package] marks `PackageItem`s (random quarter turn).
  TransportedItemStack(this.stack, {bool upright = false, bool package = false, Random? random}) {
    final r = random ?? _random;
    angle = upright ? 180 : r.nextInt(360);
    if (package) angle = r.nextInt(4) * 90 + r.nextInt(20) - 10;
    sideOffset = prevSideOffset = targetSideOffset;
  }

  /// `getTargetSideOffset`.
  double get targetSideOffset => (angle - 180) / (360 * 3);

  @override
  int compareTo(TransportedItemStack o) => beltPosition < o.beltPosition ? 1 : (beltPosition > o.beltPosition ? -1 : 0);

  /// `getSimilar`: a copy with a new random angle.
  TransportedItemStack getSimilar() {
    final c = TransportedItemStack(stack);
    c.beltPosition = beltPosition;
    c.insertedAt = insertedAt;
    c.insertedFrom = insertedFrom;
    c.prevBeltPosition = prevBeltPosition;
    c.prevSideOffset = prevSideOffset;
    c.processedBy = processedBy;
    c.processingTime = processingTime;
    return c;
  }

  /// `copy`.
  TransportedItemStack copy() {
    final c = getSimilar();
    c.angle = angle;
    c.sideOffset = sideOffset;
    return c;
  }

  /// `insertedFrom.get3DDataValue()`.
  int get insertedFromIndex => _directionNames.indexOf(insertedFrom);

  static String directionByIndex(int i) => _directionNames[i.clamp(0, 5)];

  @override
  String toString() => 'Transported($stack at ${beltPosition.toStringAsFixed(2)})';
}

/// `TransportedItemStackHandlerBehaviour.TransportedResult`.
final class TransportedResult {
  final List<TransportedItemStack>? _outputs;
  final TransportedItemStack? _heldOutput;

  const TransportedResult._(this._outputs, this._heldOutput);

  static const TransportedResult _doNothing = TransportedResult._(null, null);
  static const TransportedResult _removeItem = TransportedResult._([], null);

  /// `doNothing()`.
  static TransportedResult doNothing() => _doNothing;

  /// `removeItem()`.
  static TransportedResult removeItem() => _removeItem;

  /// `convertTo(output)`.
  static TransportedResult convertTo(TransportedItemStack output) => TransportedResult._([output], null);

  /// `convertTo(outputs)`.
  static TransportedResult convertToAll(List<TransportedItemStack> outputs) => TransportedResult._(outputs, null);

  /// `convertToAndLeaveHeld`.
  static TransportedResult convertToAndLeaveHeld(List<TransportedItemStack> outputs, TransportedItemStack held) =>
      TransportedResult._(outputs, held);

  /// `doesNothing()`.
  bool get doesNothing => _outputs == null;

  /// `didntChangeFrom(stackBefore)`.
  bool didntChangeFrom(PStack stackBefore) =>
      doesNothing || _outputs!.length == 1 && _outputs[0].stack == stackBefore && !hasHeldOutput;

  List<TransportedItemStack> get outputs {
    final o = _outputs;
    if (o == null) throw StateError('Do not call outputs on a Result that doesNothing.');
    return o;
  }

  bool get hasHeldOutput => _heldOutput != null;

  TransportedItemStack get heldOutput {
    final h = _heldOutput;
    if (h == null) throw StateError('Do not call heldOutput on a Result with hasHeldOutput == false.');
    return h;
  }
}

/// `BeltProcessingBehaviour.ProcessingResult`.
enum ProcessingResult { pass, hold, remove }

/// `TransportedItemStackHandlerBehaviour`: the view a machine gets of the belt segment or depot
/// below it. Implemented by belts and depots.
abstract interface class TransportedItemStackHandler {
  /// `handleCenteredProcessingOnAllItems(maxDistanceFromCenter, processFunction)`: calls
  /// [process] for every item within [maxDistanceFromCenter] of the center of the space; a
  /// `null` answer or `doNothing` leaves the item, anything else replaces it.
  void handleCenteredProcessingOnAllItems(double maxDistanceFromCenter, TransportedResult? Function(TransportedItemStack) process);

  /// `handleProcessingOnAllItems`: centered, 0.51.
  void handleProcessingOnAllItems(TransportedResult? Function(TransportedItemStack) process) =>
      handleCenteredProcessingOnAllItems(.51, process);

  /// `handleProcessingOnItem(item, result)`.
  void handleProcessingOnItem(TransportedItemStack item, TransportedResult result) =>
      handleCenteredProcessingOnAllItems(.51, (t) => identical(t, item) ? result : null);

  /// `getWorldPositionOf(transported)`.
  (double, double, double) worldPositionOf(TransportedItemStack transported);
}

/// `BeltProcessingBehaviour.ProcessingCallback`.
typedef BeltProcessingCallback = ProcessingResult Function(TransportedItemStack stack, TransportedItemStackHandler inventory);
