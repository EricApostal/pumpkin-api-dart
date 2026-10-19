// The `create:linked_controller_items` data component (pure): an
// `ItemContainerContents` of the 12 frequency items of a linked controller (two per
// button). Network format (26.3):
//
//   contents := varint size (<= 256), then size x ( bool present, [template] )
//   template := varint item id, varint count, component patch
//
// Trailing empty slots are not written (`ItemContainerContents.fromItems`).
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../protocol/item_stack.dart' show ItemComponentPatch, ItemComponents, ItemIdResolver;
import '../../common/common.dart';
import 'frequency.dart';

/// One slot: an item with a count and a component patch (`ItemStackTemplate`).
final class ItemTemplate {
  final int itemId;
  final int count;
  final ItemComponentPatch patch;

  const ItemTemplate(this.itemId, [this.count = 1, this.patch = ItemComponentPatch.empty]);

  @override
  bool operator ==(Object other) =>
      other is ItemTemplate && other.itemId == itemId && other.count == count && other.patch == patch;

  @override
  int get hashCode => Object.hash(itemId, count, patch);

  @override
  String toString() => 'ItemTemplate($itemId x$count)';
}

/// The registered id of `minecraft:dyed_color`, `null` outside a server.
int? get dyedColorComponentId => VanillaIds.dataComponentTypes.idOf('minecraft:dyed_color');

/// Teaches the wire layer to skip over `minecraft:dyed_color` (one int).
void registerDyedColorComponent() {
  void copy(PacketReader r, PacketWriter w) => w.writeInt(r.readInt());
  ItemComponents.registerVanilla('minecraft:dyed_color', copy);
}

/// The contents of the 12 slot container.
final class ControllerItems {
  static const int slotCount = 12;

  /// Slots up to the last non empty one.
  final List<ItemTemplate?> slots;

  ControllerItems(List<ItemTemplate?> slots) : slots = List.unmodifiable(slots);

  static final ControllerItems empty = ControllerItems(const []);

  ItemTemplate? slot(int i) => i >= 0 && i < slots.length ? slots[i] : null;

  /// Decodes the component value. Returns [empty] for bytes that cannot be read (unknown
  /// item components inside); [error] receives the reason.
  static ControllerItems decode(List<int> bytes, {void Function(Object error)? error}) {
    try {
      return PacketBuffer.decode(bytes, (r) {
        final size = r.readVarInt();
        if (size < 0 || size > 256) throw PacketException('ItemContainerContents of $size slots');
        final list = <ItemTemplate?>[];
        for (var i = 0; i < size; i++) {
          if (!r.readBool()) {
            list.add(null);
            continue;
          }
          final id = r.readVarInt();
          final count = r.readVarInt();
          list.add(ItemTemplate(id, count, ItemComponentPatch.read(r)));
        }
        return ControllerItems(list);
      });
    } on Object catch (e) {
      error?.call(e);
      return empty;
    }
  }

  /// Encodes the component value.
  Uint8List encode() {
    var last = slots.length - 1;
    while (last >= 0 && slots[last] == null) {
      last--;
    }
    return PacketBuffer.encode((w) {
      w.writeVarInt(last + 1);
      for (var i = 0; i <= last; i++) {
        final t = slots[i];
        w.writeBool(t != null);
        if (t == null) continue;
        w.writeVarInt(t.itemId);
        w.writeVarInt(t.count);
        t.patch.write(w);
      }
    });
  }

  /// A copy with slot [i] replaced (`setStackInSlot`).
  ControllerItems withSlot(int i, ItemTemplate? template) {
    final list = <ItemTemplate?>[
      for (var k = 0; k < slotCount; k++) slot(k),
      ...slots.skip(slotCount),
    ];
    list[i] = template;
    return ControllerItems(list);
  }

  /// `Frequency.of(stack)` of slot [i].
  Frequency frequencyAt(int i, ItemIdResolver ids) {
    final t = slot(i);
    if (t == null || t.count <= 0) return Frequency.empty;
    final key = ids.keyOf(t.itemId);
    if (key == null) return Frequency.empty;
    return Frequency.of(key, color: _colorOf(t.patch));
  }

  /// `LinkedControllerItem.toFrequency(controller, button)`.
  NetworkKey toFrequency(int button, ItemIdResolver ids) =>
      Couple<Frequency>(frequencyAt(button * 2, ids), frequencyAt(button * 2 + 1, ids));

  static int _colorOf(ItemComponentPatch patch) {
    final dyed = dyedColorComponentId;
    if (dyed == null) return -1;
    for (final (id, bytes) in patch.added) {
      if (id == dyed && bytes.length >= 4) {
        return ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]).toSigned(32);
      }
    }
    return -1;
  }

  /// The template of a frequency (`f.getStack().copy()`), `null` for the empty one or an
  /// item the registry does not know.
  static ItemTemplate? templateOf(Frequency f, ItemIdResolver ids) {
    final key = f.item;
    if (key == null) return null;
    final id = ids.idOf(key);
    if (id == null) return null;
    final dyed = dyedColorComponentId;
    if (f.color == -1 || dyed == null) return ItemTemplate(id);
    final bytes = PacketBuffer.encode((w) => w.writeInt(f.color));
    return ItemTemplate(id, 1, ItemComponentPatch(added: [(dyed, bytes)]));
  }
}
