// Item stacks of the turtle model, and the inventory algorithms of CC:
// Tweaked's `InventoryUtil`. Binding-free: the plugin converts host stacks to
// and from [TurtleStack] at the edge (`plugin/turtle_items.dart`).
import 'dart:typed_data';

/// What the model needs to know about items it does not own.
abstract interface class ItemInfo {
  /// The most items one stack of [item] holds (`getMaxStackSize`).
  int maxStack(String item);
}

/// A vanilla data component of a stack: the id of its type (the host's
/// `data-component` ordinal) and the bytes of its network encoding.
final class StackComponent {
  final int type;
  final Uint8List value;

  const StackComponent(this.type, this.value);

  bool sameAs(StackComponent other) => type == other.type && _sameBytes(value, other.value);
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// An item stack: an item, a count, and the components that differ from the
/// item's defaults.
final class TurtleStack {
  /// `minecraft:cobblestone`.
  final String item;
  int count;

  /// The vanilla components of the stack (network encoding).
  final List<StackComponent> components;

  /// CC: Tweaked's own components (`computercraft:computer_id`, ...) by key
  /// (network encoding), which the host keeps apart from the vanilla ones.
  final Map<String, Uint8List> custom;

  /// Derived from the components when the stack is read from the host
  /// (`isDamaged()` and "has enchantments or attribute modifiers"): turtle
  /// tools refuse damaged or enchanted items. Not part of the identity.
  final bool damaged;
  final bool enchanted;

  TurtleStack(
    this.item,
    this.count, {
    List<StackComponent>? components,
    Map<String, Uint8List>? custom,
    this.damaged = false,
    this.enchanted = false,
  }) : components = components ?? <StackComponent>[],
       custom = custom ?? <String, Uint8List>{};

  bool get isEmpty => count <= 0;

  TurtleStack copy({int? count}) => TurtleStack(
    item,
    count ?? this.count,
    components: List.of(components),
    custom: Map.of(custom),
    damaged: damaged,
    enchanted: enchanted,
  );

  /// `ItemStack.isSameItemSameComponents`.
  bool sameItem(TurtleStack other) {
    if (item != other.item) return false;
    if (components.length != other.components.length || custom.length != other.custom.length) return false;
    for (final component in components) {
      final match = other.components.where((c) => c.type == component.type);
      if (match.isEmpty || !match.first.sameAs(component)) return false;
    }
    for (final entry in custom.entries) {
      final value = other.custom[entry.key];
      if (value == null || !_sameBytes(value, entry.value)) return false;
    }
    return true;
  }

  /// Equal item, components and count (change detection).
  bool sameStack(TurtleStack other) => count == other.count && sameItem(other);

  @override
  String toString() => '$count x $item';
}

/// Whether two slots hold the same thing (both empty counts).
bool sameSlot(TurtleStack? a, TurtleStack? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.sameStack(b);
}

/// A fixed size list of optional stacks: a turtle's 16 slots.
final class Slots {
  final List<TurtleStack?> items;
  final ItemInfo info;

  Slots(int size, this.info) : items = List<TurtleStack?>.filled(size, null);

  int get length => items.length;

  TurtleStack? operator [](int slot) => items[slot];

  void operator []=(int slot, TurtleStack? value) => items[slot] = value == null || value.isEmpty ? null : value;

  /// The slot's stack, or an empty slot as null.
  TurtleStack? get(int slot) => items[slot];

  /// `Container.removeItem(slot, count)`: takes up to [count] items.
  TurtleStack? remove(int slot, int count) {
    final stack = items[slot];
    if (stack == null || count <= 0) return null;
    final taken = stack.count <= count ? stack.count : count;
    final result = stack.copy(count: taken);
    stack.count -= taken;
    if (stack.count <= 0) items[slot] = null;
    return result;
  }

  /// How many items of [stack] fit into the whole inventory (for checks that
  /// must not change anything).
  int roomFor(TurtleStack stack) {
    final max = info.maxStack(stack.item);
    var room = 0;
    for (final current in items) {
      if (current == null) {
        room += max;
      } else if (current.count < max && current.sameItem(stack)) {
        room += max - current.count;
      }
    }
    return room;
  }

  /// `InventoryUtil.storeItemsIntoSlot`: puts [stack] into [slot] only. Returns
  /// what did not fit (null if all of it did). [stack] is not changed.
  TurtleStack? storeIntoSlot(TurtleStack stack, int slot) => _store(stack.copy(), slot, 1);

  /// `InventoryUtil.storeItemsFromOffset`: tries every slot starting at
  /// [offset] and wrapping around. Returns the remainder (null if all fit).
  TurtleStack? storeFromOffset(TurtleStack stack, int offset) => _store(stack.copy(), offset, items.length);

  TurtleStack? _store(TurtleStack stack, int offset, int slotCount) {
    final max = info.maxStack(stack.item);
    if (max <= 0) return stack;
    for (var i = 0; i < slotCount; i++) {
      var slot = i + offset;
      if (slot >= items.length) slot -= items.length;
      final current = items[slot];
      if (current == null) {
        if (stack.count <= max) {
          items[slot] = stack;
          return null;
        }
        items[slot] = stack.copy(count: max);
        stack.count -= max;
      } else {
        final currentMax = info.maxStack(current.item);
        if (current.count >= (currentMax < max ? currentMax : max)) continue;
        if (!current.sameItem(stack)) continue;
        final room = max - current.count;
        final toMove = stack.count < room ? stack.count : room;
        current.count += toMove;
        stack.count -= toMove;
        if (stack.count <= 0) return null;
      }
    }
    return stack.count <= 0 ? null : stack;
  }
}

/// A copy of [source] with the same stacks, for "would it fit" checks.
Slots cloneSlots(Slots source) {
  final copy = Slots(source.length, source.info);
  for (var i = 0; i < source.length; i++) {
    copy.items[i] = source.items[i]?.copy();
  }
  return copy;
}
