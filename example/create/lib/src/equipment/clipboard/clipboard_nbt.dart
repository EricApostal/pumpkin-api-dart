// `ClipboardContent.CODEC` / `ClipboardEntry.CODEC` written as NBT (what the update tag of a
// placed clipboard carries under `components`) and the pure entry logic of
// `ClipboardValueSettingsHandler`. Pure.
import '../../core/nbt.dart';
import '../data/equipment_components.dart';

/// The codec NBT of a clipboard entry; [keyOf] resolves the icon's item id to its key.
NbtValue entryToCodecNbt(ClipboardEntryData e, String? Function(int itemId) keyOf) {
  final iconKey = e.icon.isEmpty ? null : keyOf(e.icon.itemId);
  return NbtValue.compound({
    'checked': NbtValue.byte(e.checked ? 1 : 0),
    'text': e.text,
    'icon': iconKey == null
        ? NbtValue.emptyCompound()
        : NbtValue.compound({'id': NbtValue.string(iconKey), 'count': NbtValue.int32(e.icon.count)}),
    'item_amount': NbtValue.int32(e.itemAmount),
  });
}

/// The codec NBT of the content.
NbtValue contentToCodecNbt(ClipboardContentData c, String? Function(int itemId) keyOf) {
  return NbtValue.compound({
    'type': NbtValue.string(c.type.serializedName),
    'pages': NbtValue.list([
      for (final page in c.pages) NbtValue.list([for (final e in page) entryToCodecNbt(e, keyOf)]),
    ]),
    'read_only': NbtValue.byte(c.readOnly ? 1 : 0),
    'previously_opened_page': NbtValue.int32(c.previouslyOpenedPage),
    if (c.copiedValues != null) 'copied_values': c.copiedValues!,
  });
}

/// `ClipboardEditPacket.clipboardProcessor`: content with a click event in any text is dropped
/// (a clipboard must not run commands).
ClipboardContentData? processClipboard(ClipboardContentData? content) {
  if (content == null) return null;
  for (final page in content.pages) {
    for (final entry in page) {
      if (hasClickEvent(entry.text)) return null;
    }
  }
  return content;
}

/// `NBTProcessors.textComponentHasClickEvent`: a `click_event` / `clickEvent` anywhere in the tree.
bool hasClickEvent(NbtValue v) {
  switch (v.kind) {
    case NbtKind.compound:
      for (final e in v.asCompound.entries) {
        if (e.key == 'click_event' || e.key == 'clickEvent') return true;
        if (hasClickEvent(e.value)) return true;
      }
      return false;
    case NbtKind.list:
      return (v.value as List<NbtValue>).any(hasClickEvent);
    default:
      return false;
  }
}

/// The copy of the entries of a clipboard block into the clipboard item
/// (`ClipboardValueSettingsHandler.interact` for a `ClipboardBlockEntity` target): entries whose
/// text the item does not have yet are appended into the first page with at most 11 entries.
List<List<ClipboardEntryData>> mergeClipboardPages(
  List<List<ClipboardEntryData>> into,
  List<List<ClipboardEntryData>> from,
) {
  final pages = [for (final p in into) List<ClipboardEntryData>.of(p)];
  final toAdd = <ClipboardEntryData>[];
  for (final page in from) {
    for (final entry in page) {
      final text = entry.plainText;
      var exists = false;
      for (final pageTo in pages) {
        for (final existing in pageTo) {
          if (existing.plainText == text) exists = true;
        }
      }
      if (!exists) toAdd.add(ClipboardEntryData(checked: entry.checked, text: entry.text));
    }
  }
  for (final entry in toAdd) {
    List<ClipboardEntryData>? page;
    for (final free in pages) {
      if (free.length > 11) continue;
      page = free;
      break;
    }
    if (page == null) {
      page = <ClipboardEntryData>[];
      pages.add(page);
    }
    page.add(entry);
  }
  return pages;
}
