// Reading and writing the book on a lectern (`LecternDisplayTarget`): the network format of
// `minecraft:written_book_content` and `minecraft:writable_book_content` (26.3), with the page
// components as network NBT.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/nbt.dart';
import 'display_core.dart';

/// JSON text component -> network NBT (strings stay strings, objects become compounds, lists of
/// components become lists of compounds).
NbtValue jsonToNbt(Object? json) {
  if (json is String) return NbtValue.string(json);
  if (json is bool) return NbtValue.byte(json ? 1 : 0);
  if (json is int) return NbtValue.int32(json);
  if (json is double) return NbtValue.double64(json);
  if (json is Map) {
    return NbtValue.compound({for (final e in json.entries) '${e.key}': jsonToNbt(e.value)});
  }
  if (json is List) {
    final items = [for (final e in json) jsonToNbt(e)];
    // NBT lists are homogeneous: a mixed list wraps its strings in compounds.
    final allCompound = items.every((i) => i.kind == NbtKind.compound);
    final allString = items.every((i) => i.kind == NbtKind.string);
    if (allCompound || allString || items.isEmpty) return NbtValue.list(items);
    return NbtValue.list([
      for (final i in items) i.kind == NbtKind.compound ? i : NbtValue.compound({'text': i}),
    ]);
  }
  return NbtValue.string('');
}

/// Network NBT -> JSON text component.
Object? nbtToJson(NbtValue? v) {
  if (v == null) return '';
  switch (v.kind) {
    case NbtKind.string:
      return v.value as String;
    case NbtKind.compound:
      return {for (final e in (v.value as Map<String, NbtValue>).entries) e.key: nbtToJson(e.value)};
    case NbtKind.list:
      return [for (final e in v.value as List<NbtValue>) nbtToJson(e)];
    case NbtKind.byte || NbtKind.short || NbtKind.int || NbtKind.long:
      return v.value as int;
    case NbtKind.float || NbtKind.double:
      return v.value as double;
    default:
      return '';
  }
}

void _writeFilterableString(PacketWriter w, String s) {
  w.writeString(s);
  w.writeBool(false);
}

String _readFilterableString(PacketReader r) {
  final raw = r.readString();
  if (r.readBool()) r.readString();
  return raw;
}

/// The page list of a `written_book_content` value.
List<Object?> decodeWrittenPages(List<int> bytes) => PacketBuffer.decode(bytes, (r) {
  _readFilterableString(r); // title
  r.readString(); // author
  r.readVarInt(); // generation
  final n = r.readVarInt();
  final pages = <Object?>[];
  for (var i = 0; i < n; i++) {
    pages.add(nbtToJson(NetworkNbt.read(r)));
    if (r.readBool()) NetworkNbt.read(r); // filtered
  }
  r.readBool(); // resolved
  return pages;
}, allowTrailing: true);

/// A `written_book_content` value.
Uint8List encodeWrittenBook({
  required String title,
  required String author,
  required int generation,
  required List<Object?> pagesJson,
}) => PacketBuffer.encode((w) {
  _writeFilterableString(w, title);
  w.writeString(author);
  w.writeVarInt(generation);
  w.writeVarInt(pagesJson.length);
  for (final p in pagesJson) {
    NetworkNbt.write(w, jsonToNbt(p));
    w.writeBool(false);
  }
  w.writeBool(true);
});

/// The text pages of a `writable_book_content` value.
List<String> decodeWritablePages(List<int> bytes) => PacketBuffer.decode(bytes, (r) {
  final n = r.readVarInt();
  return [for (var i = 0; i < n; i++) _readFilterableString(r)];
}, allowTrailing: true);

Future<ItemStack?> _bookOf(World world, BlockPos pos) async {
  final be = world.getBlockEntity(pos: pos);
  if (be is! BlockEntityTypeLecternBlockEntity) return null;
  final stack = be.value.getContainer().getStack(slot: 0);
  if (stack == null || await stack.getCount() <= 0) return null;
  return stack;
}

Future<List<int>?> _component(ItemStack stack, DataComponent which) async {
  for (final c in await stack.getComponents()) {
    if (c.component == which) return c.value;
  }
  return null;
}

/// The book on the lectern at [pos], or `null`.
Future<LecternBookView?> readLecternBook(World world, BlockPos pos) async {
  final stack = await _bookOf(world, pos);
  if (stack == null) return null;
  final key = await stack.getRegistryKey();
  if (key == 'minecraft:writable_book') {
    final bytes = await _component(stack, DataComponent.writableBookContent);
    final pages = bytes == null ? <String>[] : decodeWritablePages(bytes);
    return LecternBookView(writable: true, pages: pages);
  }
  if (key != 'minecraft:written_book') return null;
  final bytes = await _component(stack, DataComponent.writtenBookContent);
  return LecternBookView(writable: false, pages: bytes == null ? const [] : decodeWrittenPages(bytes));
}

/// Writes [pagesJson] to the book on the lectern at [pos]; a writable book is signed first
/// ("Printed Book" by "Data Gatherer").
Future<void> writeLecternPages(World world, BlockPos pos, List<Object?> pagesJson) async {
  final be = world.getBlockEntity(pos: pos);
  if (be is! BlockEntityTypeLecternBlockEntity) return;
  final container = be.value.getContainer();
  final stack = await _bookOf(world, pos);
  if (stack == null) return;
  final key = await stack.getRegistryKey();
  ItemStack target = stack;
  var title = 'Printed Book';
  var author = 'Data Gatherer';
  var generation = 0;
  if (key == 'minecraft:writable_book') {
    target = ItemStack.create(registryKey: 'minecraft:written_book', count: 1);
  } else if (key != 'minecraft:written_book') {
    return;
  } else {
    // keep the title and author of a written book
    final bytes = await _component(stack, DataComponent.writtenBookContent);
    if (bytes != null) {
      final meta = PacketBuffer.decode(bytes, (r) => (_readFilterableString(r), r.readString(), r.readVarInt()), allowTrailing: true);
      title = meta.$1;
      author = meta.$2;
      generation = meta.$3;
    }
  }
  await target.setComponent(
    component: DataComponent.writtenBookContent,
    value: encodeWrittenBook(title: title, author: author, generation: generation, pagesJson: pagesJson),
  );
  await container.setStack(slot: 0, stack: target);
}
