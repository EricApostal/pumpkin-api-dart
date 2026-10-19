// `SchematicExport` / `SchematicAndQuillItem` (pure): the NBT changes Create applies to a
// structure saved from the world before it is written as a schematic file.
//
// A Java client reads the file with `NbtIo.read` (gzip), so the helpers work on the gzip bytes
// the host's structure API returns. `gunzip` is the pure inflate of the data pack reader; the
// writer uses stored deflate blocks, which every gzip reader accepts.
import 'dart:typed_data';

import '../common/binary_nbt.dart';
import '../common/bounds.dart';
import '../core/nbt.dart';
import '../data/pack_format.dart' show gunzip;

/// `SchematicAndQuillItem.replaceStructureVoidWithAir`: a structure void in the palette becomes
/// air so the client does not place an invisible block.
void replaceStructureVoidWithAir(Map<String, NbtValue> root) {
  final palette = root['palette'];
  if (palette == null || palette.kind != NbtKind.list) return;
  for (final entry in palette.value as List<NbtValue>) {
    if (entry.kind != NbtKind.compound) continue;
    final name = entry.asCompound['Name'];
    if (name != null &&
        name.kind == NbtKind.string &&
        name.value == 'minecraft:structure_void') {
      entry.asCompound['Name'] = const NbtValue.string('minecraft:air');
    }
  }
}

/// `SchematicAndQuillItem.clampGlueBoxes`: glue boxes that stick out of the exported area are
/// cropped to it. The saved glue entities are removed and replaced by [croppedGlueBoxes] (world
/// coordinates, as `SuperGlueEntity.collectCropped` returns them).
void clampGlueBoxes(
  Map<String, NbtValue> root,
  Aabb area,
  List<Aabb> croppedGlueBoxes,
) {
  final existing = root['entities'];
  final list = existing != null && existing.kind == NbtKind.list
      ? List<NbtValue>.of(existing.value as List<NbtValue>)
      : <NbtValue>[];
  list.removeWhere(_isGlueEntity);
  for (final box in croppedGlueBoxes) {
    // `SuperGlueEntity.resetPositionToBB`: the entity sits at the box centre, on its minimum Y.
    final cx = (box.minX + box.maxX) / 2;
    final cy = box.minY;
    final cz = (box.minZ + box.maxZ) / 2;
    final rel = (cx - area.minX, cy - area.minY, cz - area.minZ);
    final blockPos = (rel.$1.floor(), rel.$2.floor(), rel.$3.floor());
    list.add(
      NbtValue.compound({
        'pos': _doubleList([rel.$1, rel.$2, rel.$3]),
        'blockPos': NbtValue.list([
          NbtValue.int32(blockPos.$1),
          NbtValue.int32(blockPos.$2),
          NbtValue.int32(blockPos.$3),
        ]),
        'nbt': NbtValue.compound({
          'id': const NbtValue.string('create:super_glue'),
          // `SuperGlueEntity.writeAdditional` stores the box relative to the entity position.
          'From': _doubleList([box.minX - cx, box.minY - cy, box.minZ - cz]),
          'To': _doubleList([box.maxX - cx, box.maxY - cy, box.maxZ - cz]),
          'Pos': _doubleList([cx, cy, cz]),
        }),
      }),
    );
  }
  root['entities'] = NbtValue.list(list);
}

/// The gzip bytes of a structure saved from the world with the schematic export changes applied.
/// Unreadable input is returned unchanged, like `SchematicExport` keeps the template it saved.
Uint8List prepareSchematicExport(
  List<int> savedBytes, {
  required Aabb area,
  List<Aabb> croppedGlueBoxes = const [],
}) {
  final NbtValue root;
  final String name;
  try {
    final parsed = BinaryNbt.read(gunzip(Uint8List.fromList(savedBytes)));
    if (parsed == null || parsed.root.kind != NbtKind.compound) {
      return Uint8List.fromList(savedBytes);
    }
    root = NbtValue.compound({...parsed.root.asCompound});
    name = parsed.name;
  } on Object {
    return Uint8List.fromList(savedBytes);
  }
  replaceStructureVoidWithAir(root.asCompound);
  clampGlueBoxes(root.asCompound, area, croppedGlueBoxes);
  return gzipCompress(BinaryNbt.write(root, name: name));
}

/// A gzip stream around [data], using stored (uncompressed) deflate blocks. The pure reader of
/// `pack_format.dart` only inflates, and the plugin has no `dart:io`; the Java client only needs a
/// valid gzip stream.
Uint8List gzipCompress(List<int> data) {
  final out = BytesBuilder();
  // Magic, deflate, no flags, no modification time, no extra flags, unknown OS.
  out.add(const [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff]);
  var pos = 0;
  do {
    final remaining = data.length - pos;
    final len = remaining > 0xffff ? 0xffff : remaining;
    final last = pos + len >= data.length;
    out
      ..addByte(last ? 1 : 0)
      ..addByte(len & 0xff)
      ..addByte((len >> 8) & 0xff)
      ..addByte((~len) & 0xff)
      ..addByte(((~len) >> 8) & 0xff)
      ..add(data.sublist(pos, pos + len));
    pos += len;
  } while (pos < data.length);
  final crc = _crc32(data);
  out
    ..addByte(crc & 0xff)
    ..addByte((crc >> 8) & 0xff)
    ..addByte((crc >> 16) & 0xff)
    ..addByte((crc >> 24) & 0xff)
    ..addByte(data.length & 0xff)
    ..addByte((data.length >> 8) & 0xff)
    ..addByte((data.length >> 16) & 0xff)
    ..addByte((data.length >> 24) & 0xff);
  return out.toBytes();
}

bool _isGlueEntity(NbtValue e) {
  if (e.kind != NbtKind.compound) return false;
  final nbt = e.asCompound['nbt'];
  if (nbt == null || nbt.kind != NbtKind.compound) return false;
  final id = nbt.asCompound['id'];
  return id != null &&
      id.kind == NbtKind.string &&
      id.value == 'create:super_glue';
}

NbtValue _doubleList(List<double> values) =>
    NbtValue.list([for (final v in values) NbtValue.double64(v)]);

Uint32List? _crcTable;

int _crc32(List<int> data) {
  final table = _crcTable ??= () {
    final t = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
      }
      t[n] = c;
    }
    return t;
  }();
  var c = 0xffffffff;
  for (final b in data) {
    c = table[(c ^ b) & 0xff] ^ (c >> 8);
  }
  return (c ^ 0xffffffff) & 0xffffffff;
}
