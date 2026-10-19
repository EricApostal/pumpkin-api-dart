// `RedstoneLinkNetworkHandler.Frequency` (pure): the item (and dye colour) a redstone
// link slot holds. Two frequencies are equal when item and colour are, like Java
// (`item == item && color == color`); a stack's other components do not matter.
import '../../common/common.dart';

/// One frequency item. [item] is the registry key (`minecraft:redstone`), `null` for
/// the empty frequency.
final class Frequency {
  /// The empty frequency (no item in the slot).
  static const Frequency empty = Frequency._(null, -1);

  /// The item key, `null` when empty.
  final String? item;

  /// The `minecraft:dyed_color` rgb of the stack, -1 if it has none.
  final int color;

  const Frequency._(this.item, this.color);

  /// `Frequency.of(stack)`: [item] null or `minecraft:air` is empty.
  factory Frequency.of(String? item, {int color = -1}) {
    if (item == null || item == 'minecraft:air') return empty;
    return Frequency._(item, color);
  }

  bool get isEmpty => item == null;

  @override
  bool operator ==(Object other) => other is Frequency && other.item == item && other.color == color;

  @override
  int get hashCode => ((item?.hashCode ?? 0) * 31) ^ color;

  @override
  String toString() => isEmpty ? 'Frequency.empty' : 'Frequency($item${color == -1 ? '' : ', #${color.toRadixString(16)}'})';
}

/// The network key of a link: the two frequencies (`Couple<Frequency>`).
typedef NetworkKey = Couple<Frequency>;

/// A network key made of two empty frequencies.
NetworkKey emptyNetworkKey() => Couple<Frequency>(Frequency.empty, Frequency.empty);
