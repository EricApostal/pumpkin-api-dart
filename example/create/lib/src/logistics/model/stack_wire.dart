// Conversions between [LStack] and the network encoding of item stacks and of Create's package
// data components (pure). The wire form of a component patch lists the components that differ
// from the item's defaults; [LStack.comps] keeps exactly that (name -> base64 value, `!` for a
// removed component). The four package components are logical in an [LStack] (see
// `package.dart`) and wire encoded here.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../protocol/item_stack.dart';
import 'orders.dart';
import 'package.dart';
import 'stack.dart';

/// The value of a removed component in [LStack.comps].
const String removedComponent = '!';

/// What is known about items beyond their key: filled whenever a host stack is read, seeded with
/// the manifest. Used when a stack is rebuilt from the wire.
class StackInfo {
  final Map<String, int> _maxStack = {};
  final Map<String, bool> _damageable = {};

  void learn(String key, int maxStack, bool damageable) {
    _maxStack[key] = maxStack;
    _damageable[key] = damageable;
  }

  int maxStackOf(String key) => _maxStack[key] ?? (PackageStyles.styleOf(key) != null ? 1 : 64);
  bool damageableOf(String key) => _damageable[key] ?? false;
}

/// Encodes and decodes stacks. [componentIdOf] / [componentNameOf] map component names
/// (`minecraft:damage`, `create:filter_items`) to the numeric registry ids of the wire.
final class StackWire {
  final ItemIdResolver items;
  final int? Function(String name) componentIdOf;
  final String? Function(int id) componentNameOf;
  final StackInfo info;

  StackWire({required this.items, required this.componentIdOf, required this.componentNameOf, StackInfo? info})
    : info = info ?? StackInfo();

  // -- stack <-> ItemStackData ----------------------------------------------------------------

  /// The wire stack of [s]. Components that have no registry id are left out.
  ItemStackData toData(LStack s) {
    if (s.isEmpty) return ItemStackData.empty;
    final id = items.idOf(s.key);
    if (id == null) return ItemStackData.empty;
    return ItemStackData(id, s.count, patchOf(s));
  }

  /// The component patch of [s] with the package components in wire form.
  ItemComponentPatch patchOf(LStack s) {
    if (s.comps.isEmpty) return ItemComponentPatch.empty;
    final added = <(int, Uint8List)>[];
    final removed = <int>[];
    for (final e in s.comps.entries) {
      final cid = componentIdOf(e.key);
      if (cid == null) continue;
      if (e.value == removedComponent) {
        removed.add(cid);
        continue;
      }
      final logical = base64Decode(e.value);
      final wire = PackageComponents.logical.contains(e.key) ? logicalToWire(e.key, logical) : Uint8List.fromList(logical);
      if (wire != null) added.add((cid, wire));
    }
    return ItemComponentPatch(added: added, removed: removed);
  }

  /// The stack of [d]; `empty` for an empty or unknown item. Unreadable package components are dropped.
  LStack fromData(ItemStackData d) {
    if (d.isEmpty) return LStack.empty;
    final key = items.keyOf(d.itemId);
    if (key == null) return LStack.empty;
    var s = LStack(key, d.count, maxStack: info.maxStackOf(key), damageable: info.damageableOf(key));
    final comps = <String, String>{};
    for (final (cid, bytes) in d.patch.added) {
      final name = componentNameOf(cid);
      if (name == null) continue;
      List<int>? value = bytes;
      if (PackageComponents.logical.contains(name)) value = wireToLogical(name, bytes);
      if (value != null) comps[name] = base64Encode(value);
    }
    for (final cid in d.patch.removed) {
      final name = componentNameOf(cid);
      if (name != null) comps[name] = removedComponent;
    }
    if (comps.isEmpty) return s;
    s = LStack(key, d.count,
        maxStack: s.maxStack, damageable: s.damageable, comps: Map.fromEntries(comps.entries.toList()..sort((a, b) => a.key.compareTo(b.key))));
    return s;
  }

  /// `ItemStack.OPTIONAL_STREAM_CODEC`.
  void writeStack(PacketWriter w, LStack s) => toData(s).write(w);

  LStack readStack(PacketReader r) => fromData(ItemStackData.read(r));

  /// A stack whose patch could not be read keeps item and count: reads like [readStack] but
  /// falls back for the components this process cannot delimit.
  LStack readStackLenient(PacketReader r) {
    final count = r.readVarInt();
    if (count <= 0) return LStack.empty;
    final id = r.readVarInt();
    final key = items.keyOf(id);
    final ItemComponentPatch patch;
    try {
      patch = ItemComponentPatch.read(r);
    } on UnsupportedComponentException {
      rethrow;
    }
    return fromData(ItemStackData(id, count, patch)).copyOrEmpty(key);
  }

  // -- logical <-> wire of the package components -----------------------------------------------

  /// The network encoding of the logical package component [name]; `null` if it cannot be encoded.
  Uint8List? logicalToWire(String name, List<int> logical) {
    try {
      switch (name) {
        case PackageComponents.address:
          return PacketBuffer.encode((w) => w.writeString(utf8.decode(logical)));
        case PackageComponents.contents:
          final inv = PackageItem.getContents(LStack('x', 1, comps: {PackageComponents.contents: base64Encode(logical)}));
          return PacketBuffer.encode((w) => writeContents(w, inv.stacks));
        case PackageComponents.orderData:
          final data = PackageOrderDataMapper.fromJson(utf8.decode(logical));
          return PacketBuffer.encode((w) => writeOrderData(w, data));
        case PackageComponents.orderContext:
          final ctx = PackageOrderWithCraftsMapper.fromJson(utf8.decode(logical));
          return PacketBuffer.encode((w) => writeOrderWithCrafts(w, ctx));
      }
    } on Object {
      return null;
    }
    return null;
  }

  /// The logical form of the network encoded package component [name]; `null` if unreadable.
  List<int>? wireToLogical(String name, List<int> wire) {
    try {
      switch (name) {
        case PackageComponents.address:
          return utf8.encode(PacketBuffer.decode(wire, (r) => r.readString()));
        case PackageComponents.contents:
          final slots = PacketBuffer.decode(wire, readContents);
          return utf8.encode(jsonEncode([for (final s in slots) s.isEmpty ? null : s.toMap()]));
        case PackageComponents.orderData:
          return utf8.encode(PacketBuffer.decode(wire, readOrderData).toJson());
        case PackageComponents.orderContext:
          return utf8.encode(PacketBuffer.decode(wire, readOrderWithCrafts).toJson());
      }
    } on Object {
      return null;
    }
    return null;
  }

  // -- ItemContainerContents / orders ----------------------------------------------------------

  /// `ItemContainerContents.STREAM_CODEC`: a list of optional `(item id, count, patch)`.
  void writeContents(PacketWriter w, List<LStack> slots) {
    w.writeVarInt(slots.length);
    for (final s in slots) {
      final data = toData(s);
      if (data.isEmpty) {
        w.writeBool(false);
        continue;
      }
      w.writeBool(true);
      w.writeVarInt(data.itemId);
      w.writeVarInt(data.count);
      data.patch.write(w);
    }
  }

  List<LStack> readContents(PacketReader r) {
    final n = r.readVarInt();
    final out = <LStack>[];
    for (var i = 0; i < n; i++) {
      if (!r.readBool()) {
        out.add(LStack.empty);
        continue;
      }
      final id = r.readVarInt();
      final count = r.readVarInt();
      out.add(fromData(ItemStackData(id, count, ItemComponentPatch.read(r))));
    }
    return out;
  }

  /// `PackageOrder.STREAM_CODEC`.
  void writeOrder(PacketWriter w, List<BigStack> stacks) {
    w.writeVarInt(stacks.length);
    for (final b in stacks) {
      writeStack(w, b.stack);
      w.writeVarInt(b.count);
    }
  }

  List<BigStack> readOrder(PacketReader r) {
    final n = r.readVarInt();
    return [for (var i = 0; i < n; i++) BigStack(readStack(r), 0)..count = r.readVarInt()];
  }

  /// `PackageOrderWithCrafts.STREAM_CODEC`.
  void writeOrderWithCrafts(PacketWriter w, PackageOrderWithCrafts o) {
    writeOrder(w, o.orderedStacks.stacks);
    w.writeVarInt(o.orderedCrafts.length);
    for (final c in o.orderedCrafts) {
      writeOrder(w, c.pattern.stacks);
      w.writeVarInt(c.count);
    }
  }

  PackageOrderWithCrafts readOrderWithCrafts(PacketReader r) {
    final stacks = readOrder(r);
    final n = r.readVarInt();
    final crafts = <CraftingEntry>[];
    for (var i = 0; i < n; i++) {
      final pattern = readOrder(r);
      crafts.add(CraftingEntry(PackageOrder(pattern), r.readVarInt()));
    }
    return PackageOrderWithCrafts(PackageOrder(stacks), crafts);
  }

  /// `PackageOrderData.STREAM_CODEC`.
  void writeOrderData(PacketWriter w, PackageOrderData d) {
    w.writeInt(d.orderId);
    w.writeInt(d.linkIndex);
    w.writeBool(d.isFinalLink);
    w.writeInt(d.fragmentIndex);
    w.writeBool(d.isFinal);
    final c = d.orderContext;
    w.writeBool(c != null);
    if (c != null) writeOrderWithCrafts(w, c);
  }

  PackageOrderData readOrderData(PacketReader r) {
    final orderId = r.readInt();
    final linkIndex = r.readInt();
    final isFinalLink = r.readBool();
    final fragmentIndex = r.readInt();
    final isFinal = r.readBool();
    final context = r.readBool() ? readOrderWithCrafts(r) : null;
    return PackageOrderData(orderId, linkIndex, isFinalLink, fragmentIndex, isFinal, context);
  }
}

extension on LStack {
  LStack copyOrEmpty(String? key) => key == null ? LStack.empty : this;
}
