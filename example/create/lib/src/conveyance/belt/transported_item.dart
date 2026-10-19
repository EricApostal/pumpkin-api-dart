// `TransportedItemStack` (pure): an item on a belt, depot or ejector, with its position along
// the belt, its sideways offset, its rotation and the processing state.
import 'dart:math' as math;

import '../../common/direction.dart';
import '../../manifest/manifest.dart';
import '../items/item_data.dart';

final math.Random _random = math.Random();

Set<String>? _uprightTag;
Set<String>? _notUprightTag;

Set<String> _tagItems(String id) {
  final out = <String>{};
  for (final t in tagDefs) {
    if (t.category == 'item' && t.id == id) {
      for (final e in t.entries) {
        if (!e.isTag) out.add(e.id);
      }
    }
  }
  return out;
}

/// Items that are fluid containers (`TransferUtil.hasFluidHandler`): the buckets.
bool _isFluidHandlerItem(String key) =>
    key == 'minecraft:bucket' ||
    (key.startsWith('minecraft:') && key.endsWith('_bucket') && !key.contains('powder_snow'));

/// Overrides of [isItemUpright] (modules add items that should stand on belts).
final Set<String> extraUprightItems = {};

/// `BeltHelper.isItemUpright(stack)`: `(fluid handler || #create:upright_on_belt) &&
/// !#create:not_upright_on_belt`. (Java's `forceDisableUpright` is the negated tag test.)
bool isItemUpright(ItemValue stack) {
  final key = stack.key;
  _uprightTag ??= _tagItems('create:upright_on_belt');
  _notUprightTag ??= _tagItems('create:not_upright_on_belt');
  final useUpright = _uprightTag!.contains(key) || extraUprightItems.contains(key);
  final forceDisable = _notUprightTag!.contains(key);
  return (_isFluidHandlerItem(key) || useUpright) && !forceDisable;
}

/// An item being carried.
class TransportedItemStack implements Comparable<TransportedItemStack> {
  ItemValue stack;
  double beltPosition = 0;
  double sideOffset = 0;
  int angle = 0;
  int insertedAt = 0;
  Direction insertedFrom = Direction.up;
  bool locked = false;
  bool lockedExternally = false;
  double prevBeltPosition = 0;
  double prevSideOffset = 0;

  /// The id of the fan processing type that is processing the item (`FanProcessingType`),
  /// `null` when none.
  String? processedBy;
  int processingTime = 0;

  TransportedItemStack(this.stack, {math.Random? random}) {
    final r = random ?? _random;
    final centered = isItemUpright(stack);
    angle = centered ? 180 : r.nextInt(360);
    if (isPackageKey(stack.key)) angle = r.nextInt(4) * 90 + r.nextInt(20) - 10;
    sideOffset = prevSideOffset = targetSideOffset;
    insertedFrom = Direction.up;
  }

  /// A stack with every field given (for reading and tests).
  TransportedItemStack.raw(this.stack);

  /// `getTargetSideOffset()`.
  double get targetSideOffset => (angle - 180) / (360 * 3.0);

  /// `compareTo`: the stack further along sorts first.
  @override
  int compareTo(TransportedItemStack other) =>
      beltPosition < other.beltPosition ? 1 : (beltPosition > other.beltPosition ? -1 : 0);

  /// `getSimilar()`: a copy with a new random angle.
  TransportedItemStack getSimilar({math.Random? random}) {
    final copy = TransportedItemStack(stack, random: random)
      ..beltPosition = beltPosition
      ..insertedAt = insertedAt
      ..insertedFrom = insertedFrom
      ..prevBeltPosition = prevBeltPosition
      ..prevSideOffset = prevSideOffset
      ..processedBy = processedBy
      ..processingTime = processingTime;
    return copy;
  }

  /// `copy()`: also keeps the angle and the side offset.
  TransportedItemStack copy() {
    final c = getSimilar();
    c.angle = angle;
    c.sideOffset = sideOffset;
    return c;
  }

  /// `clearFanProcessingData()`.
  void clearFanProcessingData() {
    processedBy = null;
    processingTime = 0;
  }

  @override
  String toString() => 'Transported($stack at ${beltPosition.toStringAsFixed(3)})';
}
