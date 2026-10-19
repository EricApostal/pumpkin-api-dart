// The item stack value of the logistics module (pure): item key, count and the data
// components that make two stacks different. The host `ItemStack` is a resource that cannot be
// stored; everything the module keeps (package contents, queued packages, filters, orders)
// is an [LStack]. `host/stack_io.dart` converts both ways.
import 'dart:convert';

import 'package:dart_mappable/dart_mappable.dart';

part 'stack.mapper.dart';

const String airKey = 'minecraft:air';

/// An item stack: `ItemStack` of Java as a value. Components are kept by name (`minecraft:damage`,
/// `create:filter_items`, ...) with their network encoding base64-encoded, sorted by name so that
/// [sameItemSameComponents] is a plain comparison.
@MappableClass()
class LStack with LStackMappable {
  /// The item registry key (`minecraft:iron_ingot`, `create:cardboard_package_12x12`).
  final String key;
  final int count;

  /// `getMaxStackSize()`.
  final int maxStack;

  /// `isDamageableItem()`: a stack with durability does not stack.
  final bool damageable;

  /// Component name -> base64 of the component value. Never contains the damage-free defaults.
  final Map<String, String> comps;

  const LStack(this.key, this.count, {this.maxStack = 64, this.damageable = false, this.comps = const {}});

  static const LStack empty = LStack(airKey, 0);

  /// A single item of [key] with no components.
  factory LStack.of(String key, [int count = 1, int maxStack = 64]) => LStack(key, count, maxStack: maxStack);

  /// `isEmpty()`.
  bool get isEmpty => count <= 0 || key == airKey;
  bool get isNotEmpty => !isEmpty;

  /// `isStackable()`.
  bool get stackable => maxStack > 1 && !damageable;

  /// `copyWithCount`.
  LStack withCount(int n) => n <= 0 ? LStack.empty : LStack(key, n, maxStack: maxStack, damageable: damageable, comps: comps);

  /// `copy()` with a different component (null removes it).
  LStack withComp(String name, List<int>? bytes) {
    final next = Map<String, String>.of(comps);
    if (bytes == null) {
      next.remove(name);
    } else {
      next[name] = base64Encode(bytes);
    }
    return LStack(key, count,
        maxStack: maxStack, damageable: damageable, comps: Map.fromEntries(next.entries.toList()..sort((a, b) => a.key.compareTo(b.key))));
  }

  /// The bytes of component [name], `null` if the stack has none.
  List<int>? compBytes(String name) {
    final v = comps[name];
    return v == null ? null : base64Decode(v);
  }

  bool hasComp(String name) => comps.containsKey(name);

  /// `ItemStack.isSameItem`.
  bool sameItem(LStack o) => key == o.key;

  /// `ItemStack.isSameItemSameComponents` (two empty stacks are the same).
  bool sameItemSameComponents(LStack o) {
    if (isEmpty || o.isEmpty) return isEmpty && o.isEmpty;
    if (key != o.key || comps.length != o.comps.length) return false;
    for (final e in comps.entries) {
      if (o.comps[e.key] != e.value) return false;
    }
    return true;
  }

  /// A key for hash maps that groups the stacks [sameItemSameComponents] considers equal.
  String get identity {
    if (isEmpty) return airKey;
    if (comps.isEmpty) return key;
    final b = StringBuffer(key);
    for (final e in comps.entries) {
      b
        ..write('|')
        ..write(e.key)
        ..write('=')
        ..write(e.value);
    }
    return b.toString();
  }

  @override
  String toString() => isEmpty ? 'empty' : '$key x$count';
}

/// `BigItemStack`: a stack and a count that can exceed the stack size ([inf] means "infinite").
/// Mutable like the Java class (summaries and orders update [count] in place). Serialised with
/// the keys of `BigItemStack.CODEC` (`item_stack`, `count`).
@MappableClass()
class BigStack with BigStackMappable {
  /// `BigItemStack.INF`.
  static const int inf = 1000000000;

  LStack itemStack;
  int count;

  BigStack(this.itemStack, [this.count = 1]);

  /// The stack (`BigItemStack.stack`).
  LStack get stack => itemStack;
  set stack(LStack value) => itemStack = value;

  bool get isInfinite => count >= inf;

  /// A new wrapper around the same stack with the same count.
  BigStack copy() => BigStack(itemStack, count);

  /// `BigItemStack.comparator`: larger counts first.
  static int compareByCount(BigStack a, BigStack b) => b.count.compareTo(a.count);

  /// `BigItemStack.duplicateWrappers`.
  static List<BigStack> duplicate(List<BigStack> list) => [for (final b in list) BigStack(b.itemStack, b.count)];

  @override
  bool operator ==(Object other) =>
      other is BigStack && itemStack.sameItemSameComponents(other.itemStack) && count == other.count;

  @override
  int get hashCode => Object.hash(itemStack.identity, count);

  @override
  String toString() => '(${itemStack.key} x$count)';
}
