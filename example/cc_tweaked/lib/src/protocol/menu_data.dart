// The extra data of CC's computer menus, and the item stack encoding it needs.
//
// A computer's menu is opened with `neoforge:advanced_open_screen`
// (messages.dart), whose `extraData` is a `ComputerContainerData`:
//
//     VarInt  family ordinal (normal 0, advanced 1, command 2)
//     TerminalState
//     ItemStack (optional form: VarInt count, 0 = empty; item id as VarInt;
//                component patch)
//     VarInt  uploadMaxSize
//
// A component patch is `VarInt added`, `VarInt removed`, then for each added
// component its type id (VarInt, from the synchronised
// `minecraft:data_component_type` registry) and its value in the type's
// stream codec, then the type id of each removed component.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart' show NbtText;

import 'messages.dart';
import 'terminal_state.dart';

/// One added data component of an item stack: a type id and its encoded value.
final class ComponentEntry {
  final int typeId;
  final Uint8List value;

  const ComponentEntry(this.typeId, this.value);

  /// A component whose value is a single VarInt (`computer_id`, `fuel`).
  factory ComponentEntry.varInt(int typeId, int value) =>
      ComponentEntry(typeId, PacketBuffer.encode((w) => w.writeVarInt(value)));

  /// A component whose value is a VarLong (`storage_capacity`).
  factory ComponentEntry.varLong(int typeId, int value) =>
      ComponentEntry(typeId, PacketBuffer.encode((w) => w.writeVarLong(value)));

  /// `terminal_size`: width and height as VarInts.
  factory ComponentEntry.size(int typeId, int width, int height) => ComponentEntry(
    typeId,
    PacketBuffer.encode((w) => w..writeVarInt(width)..writeVarInt(height)),
  );

  /// A text component (`custom_name`), as network NBT.
  factory ComponentEntry.text(int typeId, NbtText text) =>
      ComponentEntry(typeId, text.encode());
}

/// An item stack as it goes over the wire.
final class WireItemStack {
  /// The numeric id in the synchronised `minecraft:item` registry.
  final int itemId;
  final int count;
  final List<ComponentEntry> components;

  const WireItemStack(this.itemId, {this.count = 1, this.components = const []});

  /// Writes a stack, or the empty stack for null (`OPTIONAL_STREAM_CODEC`).
  static void writeOptional(PacketWriter writer, WireItemStack? stack) {
    if (stack == null || stack.count <= 0) {
      writer.writeVarInt(0);
      return;
    }
    writer
      ..writeVarInt(stack.count)
      ..writeVarInt(stack.itemId)
      ..writeVarInt(stack.components.length)
      ..writeVarInt(0);
    for (final component in stack.components) {
      writer
        ..writeVarInt(component.typeId)
        ..writeBytes(component.value);
    }
  }
}

/// `ComputerContainerData`: what the client needs to build a computer menu.
final class ComputerContainerData {
  final WireFamily family;
  final TerminalState terminal;
  final WireItemStack? displayStack;
  final int uploadMaxSize;

  const ComputerContainerData({
    required this.family,
    required this.terminal,
    this.displayStack,
    this.uploadMaxSize = 512 * 1024,
  });

  Uint8List encode() => PacketBuffer.encode((w) {
    w.writeVarInt(family.index);
    terminal.write(w);
    WireItemStack.writeOptional(w, displayStack);
    w.writeVarInt(uploadMaxSize);
  });
}
