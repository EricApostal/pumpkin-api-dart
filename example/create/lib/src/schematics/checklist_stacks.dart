// The network encodings of the printed checklist: the `written_book_content` component of a
// written book and the `create:clipboard_content` component of a clipboard (pure).
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../core/byte_buf.dart';
import '../core/nbt.dart';
import 'material_checklist.dart';

/// A text component as network NBT: `{"text": "", "extra": [{text, color}, ...]}`.
NbtValue textComponent(List<StyledPart> parts) => NbtValue.compound({
  'text': const NbtValue.string(''),
  'extra': NbtValue.list([
    for (final p in parts)
      NbtValue.compound({
        'text': NbtValue.string(p.text),
        if (p.color != null) 'color': NbtValue.string(p.color!.id),
      }),
  ]),
});

/// `minecraft:written_book_content` ("Material Checklist" by "Schematicannon"): title (blue),
/// author, generation 0, the pages, resolved.
Uint8List writtenBookContent(MaterialChecklist checklist) {
  final pages = checklist.bookPages();
  return PacketBuffer.encode((w) {
    w.writeString('§9Material Checklist'); // ChatFormatting.BLUE + "Material Checklist"
    w.writeBool(false);
    w.writeString('Schematicannon');
    w.writeVarInt(0);
    w.writeVarInt(pages.length);
    for (final page in pages) {
      final parts = [for (final e in page.entries) ...e];
      w.writeNbt(textComponent(parts));
      w.writeBool(false);
    }
    w.writeBool(true);
  });
}

/// The `custom_name` of both: the translated "Material Checklist", blue and not italic.
NbtValue checklistName() => NbtValue.compound({
  'text': const NbtValue.string('Material Checklist'),
  'color': const NbtValue.string('blue'),
  'italic': const NbtValue.byte(0),
});

/// `create:clipboard_content` of a written clipboard: type `WRITTEN`, the pages, read only, page 0.
/// [itemId] resolves an item key to its registry id for the icons.
Uint8List clipboardContent(MaterialChecklist checklist, int? Function(String itemKey) itemId) {
  final pages = checklist.clipboardPages();
  return PacketBuffer.encode((w) {
    w.writeVarInt(1); // ClipboardType.WRITTEN
    w.writeVarInt(pages.length);
    for (final page in pages) {
      w.writeVarInt(page.length);
      for (final line in page) {
        w.writeBool(line.checked);
        w.writeNbt(textComponent(line.parts));
        final id = line.icon == null ? null : itemId(line.icon!);
        if (id == null) {
          w.writeVarInt(0); // empty stack
        } else {
          w.writeVarInt(1);
          w.writeVarInt(id);
          w.writeVarInt(0); // added components
          w.writeVarInt(0); // removed components
        }
        w.writeInt(line.iconAmount);
      }
    }
    w.writeBool(true); // read only
    w.writeVarInt(0); // previously opened page
    w.writeBool(false); // no copied values
  });
}
