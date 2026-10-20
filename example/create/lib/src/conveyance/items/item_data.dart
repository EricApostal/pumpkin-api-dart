// Item stacks as plain values (pure): what belts, depots, chutes, funnels, tunnels and chain
// conveyors carry. The host's `ItemStack` is a resource that can only be read asynchronously
// and has no copy, so the logic works on [ItemValue] and the host glue (`item_codec.dart`)
// converts at the edges.

import 'dart:convert';

import '../../core/nbt.dart';
import 'glob.dart';

/// `ItemHelper.ExtractionCountMode`.
enum ExtractionCountMode { exactly, upTo }

/// The empty item.
const String airKey = 'minecraft:air';

/// Prefix of the component names that hold the plugin's own (`custom:create:*`) components in
/// [ItemValue.comps]; the codec form of such a component uses the plain wire name.
const String customComponentPrefix = 'custom:';

/// An item stack: item, count, and the data components that make it different from another
/// stack of the same item (wire name and bytes, sorted by name). Immutable; the Java
/// mutators (`shrink`, `grow`, `split`, `copyWithCount`) become `with*` / `split`.
final class ItemValue {
  final String key;
  final int count;

  /// `getMaxStackSize()` of the item with its components.
  final int maxStack;

  /// `isDamageableItem()`: damageable items never stack.
  final bool damageable;
  final List<(String, List<int>)> comps;

  /// The `components` compound of a Java save, kept as it was read. Java persists components in
  /// the codec form (`ItemStack.CODEC`), which the plugin cannot turn into the network bytes of
  /// [comps] (it only encodes), so it keeps the codec form of the whole compound instead of
  /// losing it and writes it back unchanged. It is a persistence detail, not part of the
  /// identity of a stack: [sameItemSameComponents] compares [comps] only.
  final NbtValue? rawComponents;

  const ItemValue(
    this.key,
    this.count, {
    this.maxStack = 64,
    this.damageable = false,
    this.comps = const [],
    this.rawComponents,
  });

  /// `ItemStack.EMPTY`.
  static const ItemValue empty = ItemValue(airKey, 0);

  bool get isEmpty => count <= 0 || key == airKey;
  bool get isNotEmpty => !isEmpty;

  /// `ItemStack.isStackable()`.
  bool get stackable => maxStack > 1 && !damageable;

  /// `copyWithCount(n)`; an empty result is [empty].
  ItemValue withCount(int n) => n <= 0
      ? empty
      : ItemValue(key, n, maxStack: maxStack, damageable: damageable, comps: comps, rawComponents: rawComponents);

  ItemValue grow(int n) => withCount(count + n);
  ItemValue shrink(int n) => withCount(count - n);

  /// `ItemStack.split(amount)`: (taken, remainder).
  (ItemValue, ItemValue) split(int amount) {
    final taken = amount < count ? amount : count;
    return (withCount(taken), withCount(count - taken));
  }

  /// `ItemStack.isSameItem` (ignores components).
  bool sameItem(ItemValue o) => key == o.key;

  /// `ItemStack.isSameItemSameComponents`.
  bool sameItemSameComponents(ItemValue o) {
    if (isEmpty || o.isEmpty) return isEmpty && o.isEmpty;
    if (key != o.key || comps.length != o.comps.length) return false;
    for (var i = 0; i < comps.length; i++) {
      if (comps[i].$1 != o.comps[i].$1) return false;
      final a = comps[i].$2, b = o.comps[i].$2;
      if (a.length != b.length) return false;
      for (var j = 0; j < a.length; j++) {
        if (a[j] != b[j]) return false;
      }
    }
    return true;
  }

  /// `ItemStack.matches`: same item, components and count (two empties match).
  bool matches(ItemValue o) => (isEmpty && o.isEmpty) || (sameItemSameComponents(o) && count == o.count);

  /// `ItemHelper.canItemStackAmountsStack`.
  bool canAmountsStack(ItemValue o) => sameItemSameComponents(o) && count + o.count <= maxStack;

  /// The raw bytes of the component [name], or `null`.
  List<int>? component(String name) {
    for (final c in comps) {
      if (c.$1 == name) return c.$2;
    }
    return null;
  }

  /// A copy with the component [name] set (or removed with `null`). The codec form of that one
  /// component is dropped: the plugin cannot write [bytes] (network encoding) into it.
  ItemValue withComponent(String name, List<int>? bytes) {
    final list = [
      for (final c in comps)
        if (c.$1 != name) c,
      if (bytes != null) (name, List<int>.of(bytes)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return ItemValue(key, count, maxStack: maxStack, damageable: damageable, comps: list, rawComponents: _withoutRawComponent(name));
  }

  /// [rawComponents] without the codec value of component [name] (`custom:` prefixed names are
  /// the plugin's own; their codec key is the wire name).
  NbtValue? _withoutRawComponent(String name) {
    final raw = rawComponents;
    if (raw == null || raw.kind != NbtKind.compound) return null;
    final key = name.startsWith(customComponentPrefix) ? name.substring(customComponentPrefix.length) : name;
    return NbtValue.compound(Map<String, NbtValue>.of(raw.asCompound)..remove(key));
  }

  @override
  String toString() => isEmpty ? 'empty' : '$key x$count';

  @override
  bool operator ==(Object other) => other is ItemValue && matches(other);

  @override
  int get hashCode => isEmpty ? 0 : Object.hash(key, count, comps.length);
}

/// `PackageItem.isPackage`: the cardboard and rare package items.
bool isPackageKey(String key) {
  if (!key.startsWith('create:')) return false;
  final path = key.substring('create:'.length);
  return path.startsWith('cardboard_package_') || (path.startsWith('rare_') && path.endsWith('_package'));
}

/// `ItemStack.getMaxStackSize()` for stacks built from a key alone (the host knows the real
/// value; [ItemCodec] reads it). Create's own non-stackable items.
int defaultMaxStack(String key) => isPackageKey(key) ? 1 : 64;

/// A list of stacks as `ItemHelper.addToList` merges them: [stack] is merged into the stacks
/// of [stacks] with the same item and components, the rest is appended.
void addToList(ItemValue stack, List<ItemValue> stacks) {
  var left = stack;
  for (var i = 0; i < stacks.length && left.isNotEmpty; i++) {
    final s = stacks[i];
    if (!left.sameItemSameComponents(s)) continue;
    final transferred = (s.maxStack - s.count).clamp(0, left.count);
    stacks[i] = s.grow(transferred);
    left = left.shrink(transferred);
  }
  if (left.isNotEmpty) stacks.add(left);
}

/// `ItemHelper.multipliedOutput`: [out] repeated [inCount] times, split into stacks.
List<ItemValue> multipliedOutput(ItemValue input, ItemValue out) {
  final stacks = <ItemValue>[];
  var result = out.withCount(input.count * out.count);
  while (result.count > result.maxStack) {
    final (taken, rest) = result.split(result.maxStack);
    stacks.add(taken);
    result = rest;
  }
  stacks.add(result);
  return stacks;
}

/// `PackageItem.matchAddress(boxAddress, address)`: blank matches blank, `*` matches anything,
/// otherwise equal or either one a glob of the other.
bool matchPackageAddress(String boxAddress, String address) {
  if (address.trim().isEmpty) return boxAddress.trim().isEmpty;
  if (address == '*' || boxAddress == '*') return true;
  if (address == boxAddress) return true;
  return globMatches(boxAddress, address) || globMatches(address, boxAddress);
}

/// The wire name under which `create:package_address` is held in [ItemValue.comps].
const String packageAddressComponent = 'custom:create:package_address';

/// `PackageItem.getAddress(box)`: the address component (a VarInt length and UTF-8 text), blank
/// when there is none. A package that came from a Java save carries the address in the preserved
/// codec form instead (`create:package_address` is a plain string there), which is read too.
String packageAddressOf(ItemValue box) {
  final bytes = box.component(packageAddressComponent);
  if (bytes == null) {
    final raw = box.rawComponents;
    if (raw != null && raw.kind == NbtKind.compound) {
      final value = raw.asCompound['create:package_address'];
      if (value != null && value.kind == NbtKind.string) return value.value as String;
    }
    return '';
  }
  if (bytes.isEmpty) return '';
  var length = 0, shift = 0, i = 0;
  while (i < bytes.length) {
    final b = bytes[i++];
    length |= (b & 0x7F) << shift;
    if (b & 0x80 == 0) break;
    shift += 7;
  }
  if (i + length > bytes.length) return '';
  return utf8.decode(bytes.sublist(i, i + length), allowMalformed: true);
}

/// The component bytes of a package address (`ByteBufCodecs.STRING_UTF8`).
List<int> encodePackageAddress(String address) {
  final text = utf8.encode(address);
  final out = <int>[];
  var n = text.length;
  while (n >= 0x80) {
    out.add((n & 0x7F) | 0x80);
    n >>= 7;
  }
  out.add(n);
  return [...out, ...text];
}

/// `PackageItem.matchAddress(box, address)`.
bool matchPackage(ItemValue box, String address) => matchPackageAddress(packageAddressOf(box), address);
