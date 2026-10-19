// `NBTProcessors.process` for schematic block entity data (pure): a schematic must not place a
// sign or clipboard whose text carries a click event (clicking it would run the embedded command).
// Create's `SchematicProcessor` and `BlockHelper.prepareBlockEntityData` run the same check when a
// schematic is loaded and when a block is placed.
import 'dart:convert';

import '../common/binary_nbt.dart';
import '../core/nbt.dart';
import '../equipment/clipboard/clipboard_nbt.dart' show hasClickEvent;

/// The block entity data after `NBTProcessors.process(..., survival)`, or `null` when the data
/// must be dropped.
///
/// Only the processors that can apply to `create:safe_nbt` blocks are ported: signs
/// (`minecraft:all_signs`, a message with a click event or an item in the sign data) and
/// clipboards (`create:clipboard`, an entry text with a click event). Everything else keeps its
/// data; `prepareBlockEntityData` has already dropped the blocks that are neither safe nor have a
/// writer.
List<int>? processSchematicNbt(
  List<int> data, {
  required bool isSign,
  required bool isClipboard,
}) {
  if (!isSign && !isClipboard) return data;
  final ({String name, NbtValue root})? parsed;
  try {
    parsed = BinaryNbt.read(data);
  } on FormatException {
    // A codec that cannot read the data leaves it alone (like the Java processors).
    return data;
  }
  if (parsed == null || parsed.root.kind != NbtKind.compound) return data;
  final root = parsed.root.asCompound;
  if (isSign) return _processSign(root) ? data : null;
  return _processClipboard(root) ? data : null;
}

/// `NBTProcessors.signProcessor`: false when the sign must lose its data.
bool _processSign(Map<String, NbtValue> root) {
  // "Amendments" compat: the sign data contains item stacks.
  if (root.containsKey('front_item') || root.containsKey('back_item')) {
    return false;
  }
  for (final key in const ['front_text', 'back_text']) {
    final text = root[key];
    // `data.getCompound(key)` is empty for a missing or non-compound value: the sign is dropped.
    if (text == null || text.kind != NbtKind.compound) return false;
    final messages = text.asCompound['messages'];
    if (messages == null || messages.kind != NbtKind.list) continue;
    for (final m in messages.value as List<NbtValue>) {
      if (_textHasClickEvent(m)) return false;
    }
  }
  return true;
}

/// `CreateNBTProcessors.clipboardProcessor`: false when a page entry's text has a click event.
bool _processClipboard(Map<String, NbtValue> root) {
  final components = root['components'];
  if (components == null || components.kind != NbtKind.compound) return true;
  final content = components.asCompound['create:clipboard_content'];
  if (content == null || content.kind != NbtKind.compound) return true;
  final pages = content.asCompound['pages'];
  if (pages == null || pages.kind != NbtKind.list) return true;
  for (final page in pages.value as List<NbtValue>) {
    if (page.kind != NbtKind.list) continue;
    for (final entry in page.value as List<NbtValue>) {
      if (entry.kind != NbtKind.compound) continue;
      final text = entry.asCompound['text'];
      if (text != null && _textHasClickEvent(text)) return false;
    }
  }
  return true;
}

/// A text component as NBT (a compound) or as the JSON string a sign message carries.
bool _textHasClickEvent(NbtValue v) {
  if (v.kind == NbtKind.string) return _jsonHasClickEvent(v.value as String);
  return hasClickEvent(v);
}

bool _jsonHasClickEvent(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return false;
  }
  return _hasClickEventJson(decoded);
}

bool _hasClickEventJson(Object? v) {
  if (v is Map) {
    for (final e in v.entries) {
      if (e.key == 'click_event' || e.key == 'clickEvent') return true;
      if (_hasClickEventJson(e.value)) return true;
    }
    return false;
  }
  if (v is List) return v.any(_hasClickEventJson);
  return false;
}
