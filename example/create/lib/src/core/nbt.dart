// Network NBT (pure): a small value model plus the codec of Minecraft's
// "network NBT" (1.20.2+: the root tag has no name). Used by payloads that carry
// NBT (contraptions, schematics, update tags). Converting to the host's
// `NbtCompound` is in `nbt_bridge.dart`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

enum NbtKind { end, byte, short, int, long, float, double, byteArray, string, list, compound, intArray, longArray }

/// One NBT value. [value] is an `int` (byte, short, int, long), a `double`
/// (float, double), a `String`, a `List<int>` (arrays), a `List<NbtValue>`
/// (list) or a `Map<String, NbtValue>` (compound).
final class NbtValue {
  final NbtKind kind;
  final Object value;

  const NbtValue._(this.kind, this.value);

  const NbtValue.byte(int v) : this._(NbtKind.byte, v);
  const NbtValue.short(int v) : this._(NbtKind.short, v);
  const NbtValue.int32(int v) : this._(NbtKind.int, v);
  const NbtValue.long(int v) : this._(NbtKind.long, v);
  const NbtValue.float(double v) : this._(NbtKind.float, v);
  const NbtValue.double64(double v) : this._(NbtKind.double, v);
  const NbtValue.string(String v) : this._(NbtKind.string, v);
  const NbtValue.byteArray(List<int> v) : this._(NbtKind.byteArray, v);
  const NbtValue.intArray(List<int> v) : this._(NbtKind.intArray, v);
  const NbtValue.longArray(List<int> v) : this._(NbtKind.longArray, v);
  const NbtValue.list(List<NbtValue> v) : this._(NbtKind.list, v);
  const NbtValue.compound(Map<String, NbtValue> v) : this._(NbtKind.compound, v);

  /// An empty compound.
  factory NbtValue.emptyCompound() => NbtValue.compound(<String, NbtValue>{});

  Map<String, NbtValue> get asCompound => value as Map<String, NbtValue>;

  @override
  String toString() => 'Nbt(${kind.name}: $value)';
}

/// Reading and writing network NBT.
abstract final class NetworkNbt {
  static const int _maxDepth = 512;

  /// Reads a nameless root tag. A lone `TAG_End` (0) reads as `null`.
  static NbtValue? read(PacketReader r) {
    final id = r.readUnsignedByte();
    if (id == 0) return null;
    return _readPayload(r, id, 0);
  }

  /// Writes [root] (a compound) as a nameless root tag; `null` writes `TAG_End`.
  static void write(PacketWriter w, NbtValue? root) {
    if (root == null) {
      w.writeByte(0);
      return;
    }
    w.writeByte(root.kind.index);
    _writePayload(w, root);
  }

  static Uint8List encode(NbtValue? root) => PacketBuffer.encode((w) => write(w, root));

  static NbtValue? decode(List<int> bytes) => PacketBuffer.decode(bytes, read);

  static NbtValue _readPayload(PacketReader r, int id, int depth) {
    if (depth > _maxDepth) throw const PacketException('NBT is nested too deeply');
    switch (id) {
      case 1:
        return NbtValue.byte(r.readByte());
      case 2:
        return NbtValue.short(r.readShort());
      case 3:
        return NbtValue.int32(r.readInt());
      case 4:
        return NbtValue.long(r.readLong());
      case 5:
        return NbtValue.float(r.readFloat());
      case 6:
        return NbtValue.double64(r.readDouble());
      case 7:
        return NbtValue.byteArray([for (var i = 0, n = r.readInt(); i < n; i++) r.readByte()]);
      case 8:
        return NbtValue.string(_readString(r));
      case 9:
        final elementId = r.readUnsignedByte();
        final count = r.readInt();
        if (count > 0 && elementId == 0) throw const PacketException('NBT list of TAG_End');
        return NbtValue.list([for (var i = 0; i < count; i++) _readPayload(r, elementId, depth + 1)]);
      case 10:
        final map = <String, NbtValue>{};
        while (true) {
          final child = r.readUnsignedByte();
          if (child == 0) break;
          final key = _readString(r);
          map[key] = _readPayload(r, child, depth + 1);
        }
        return NbtValue.compound(map);
      case 11:
        return NbtValue.intArray([for (var i = 0, n = r.readInt(); i < n; i++) r.readInt()]);
      case 12:
        return NbtValue.longArray([for (var i = 0, n = r.readInt(); i < n; i++) r.readLong()]);
      default:
        throw PacketException('Unknown NBT tag id $id');
    }
  }

  static String _readString(PacketReader r) {
    final length = r.readUnsignedShort();
    try {
      return utf8.decode(r.readBytes(length));
    } on FormatException catch (e) {
      throw PacketException('NBT string is not valid UTF-8: ${e.message}');
    }
  }

  static void _writeString(PacketWriter w, String s) {
    final bytes = utf8.encode(s);
    if (bytes.length > 0xFFFF) throw const PacketException('NBT string is longer than 65535 bytes');
    w.writeShort(bytes.length > 0x7FFF ? bytes.length - 0x10000 : bytes.length);
    w.writeBytes(bytes);
  }

  static void _writePayload(PacketWriter w, NbtValue v) {
    switch (v.kind) {
      case NbtKind.end:
        break;
      case NbtKind.byte:
        w.writeByte(v.value as int);
      case NbtKind.short:
        w.writeShort(v.value as int);
      case NbtKind.int:
        w.writeInt(v.value as int);
      case NbtKind.long:
        w.writeLong(v.value as int);
      case NbtKind.float:
        w.writeFloat(v.value as double);
      case NbtKind.double:
        w.writeDouble(v.value as double);
      case NbtKind.byteArray:
        final a = v.value as List<int>;
        w.writeInt(a.length);
        a.forEach(w.writeByte);
      case NbtKind.string:
        _writeString(w, v.value as String);
      case NbtKind.list:
        final items = v.value as List<NbtValue>;
        w.writeByte(items.isEmpty ? 0 : items.first.kind.index);
        w.writeInt(items.length);
        for (final item in items) {
          if (item.kind != items.first.kind) throw const PacketException('NBT list with mixed element types');
          _writePayload(w, item);
        }
      case NbtKind.compound:
        for (final e in (v.value as Map<String, NbtValue>).entries) {
          w.writeByte(e.value.kind.index);
          _writeString(w, e.key);
          _writePayload(w, e.value);
        }
        w.writeByte(0);
      case NbtKind.intArray:
        final a = v.value as List<int>;
        w.writeInt(a.length);
        a.forEach(w.writeInt);
      case NbtKind.longArray:
        final a = v.value as List<int>;
        w.writeInt(a.length);
        a.forEach(w.writeLong);
    }
  }
}
