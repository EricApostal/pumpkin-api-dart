// Vanilla binary NBT (the format of `.nbt` files and `get-block-entity-nbt`: a root tag with a
// name) on top of the network NBT model of `core/nbt.dart` (pure). Not compressed: gzip is the
// caller's business (the host's structure API reads and writes gzip itself).
import 'dart:typed_data';

import '../core/nbt.dart';

abstract final class BinaryNbt {
  /// Reads a root compound (or any tag) with its name. Returns `null` for a lone `TAG_End`.
  static ({String name, NbtValue root})? read(List<int> bytes) {
    if (bytes.isEmpty || bytes[0] == 0) return null;
    if (bytes.length < 3) throw const FormatException('Truncated NBT');
    final nameLength = (bytes[1] << 8) | bytes[2];
    if (bytes.length < 3 + nameLength) throw const FormatException('Truncated NBT name');
    final name = String.fromCharCodes(Uint8List.fromList(bytes.sublist(3, 3 + nameLength)));
    final network = Uint8List(bytes.length - 2 - nameLength)
      ..[0] = bytes[0]
      ..setRange(1, bytes.length - 2 - nameLength, bytes, 3 + nameLength);
    final root = NetworkNbt.decode(network);
    if (root == null) return null;
    return (name: name, root: root);
  }

  /// Writes [root] under [name] (usually empty).
  static Uint8List write(NbtValue root, {String name = ''}) {
    final network = NetworkNbt.encode(root);
    final nameBytes = Uint8List.fromList(name.codeUnits.every((c) => c < 128) ? name.codeUnits : _utf8(name));
    final out = BytesBuilder()
      ..addByte(network[0])
      ..addByte(nameBytes.length >> 8)
      ..addByte(nameBytes.length & 0xFF)
      ..add(nameBytes)
      ..add(network.sublist(1));
    return out.toBytes();
  }

  static List<int> _utf8(String s) {
    final out = <int>[];
    for (final r in s.runes) {
      if (r < 0x80) {
        out.add(r);
      } else if (r < 0x800) {
        out..add(0xC0 | (r >> 6))..add(0x80 | (r & 0x3F));
      } else if (r < 0x10000) {
        out..add(0xE0 | (r >> 12))..add(0x80 | ((r >> 6) & 0x3F))..add(0x80 | (r & 0x3F));
      } else {
        out..add(0xF0 | (r >> 18))..add(0x80 | ((r >> 12) & 0x3F))..add(0x80 | ((r >> 6) & 0x3F))..add(0x80 | (r & 0x3F));
      }
    }
    return out;
  }
}
