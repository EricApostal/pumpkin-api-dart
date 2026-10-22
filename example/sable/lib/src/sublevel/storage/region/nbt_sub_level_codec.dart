// The payload codec of Sable's storage files: gzip-compressed NBT.
//
// Java writes every `.slvls`/`.slvlr` payload with `NbtIo.writeCompressed`
// (`SubLevelStorageFile.COMPRESS_DATA`, `SubLevelStorageFile.java:29,316-348`)
// and reads it with `NbtIo.readCompressed`, so this is the only codec that can
// read an existing Sable world — and the only one Java can read back.
// `JsonSubLevelCodec` stays for tests and for fresh throwaway worlds; it is not
// what the plugin installs.
//
// The port's model keeps tags as `Map<String, Object?>`; the tag *type* is
// inferred here, so the Java types must be reproduced by the shape of the value:
//
// | Dart value                     | NBT tag      |
// |--------------------------------|--------------|
// | `bool`                         | byte (1/0)   |
// | `int` inside 32 bits           | int          |
// | `int` outside 32 bits          | long         |
// | `double`                       | double       |
// | `String`                       | string       |
// | `List<int>` / `Uint64List`     | int array / long array |
// | `Uint8List`                    | byte array   |
// | `List`                         | list         |
// | `Map<String, Object?>`         | compound     |
//
// Decoding keeps that table in reverse, and preserves all `int64` values
// (longs come back as `Uint64List`-style int lists) so a re-encoded tag has the
// same types as the tag it was decoded from — with one exception: a bare byte
// decodes to a Dart `int` and therefore re-encodes as an int. Sable's payload has
// exactly one byte-valued key, the plot tag's `isLightOn` (which the Java
// `ServerLevelPlot.save` writes at the wrong level, see the audit), and the port
// never writes a byte except for a `bool`.
//
// Pure: no host imports.
import 'dart:convert';
import 'dart:typed_data';

import '../../util/gzip.dart';
import 'sub_level_storage_file.dart';

/// The NBT tag ids, as `Tag.TAG_*` in the Java code.
abstract final class NbtTagId {
  static const int end = 0;
  static const int byte = 1;
  static const int short = 2;
  static const int int_ = 3;
  static const int long = 4;
  static const int float = 5;
  static const int double_ = 6;
  static const int byteArray = 7;
  static const int string = 8;
  static const int list = 9;
  static const int compound = 10;
  static const int intArray = 11;
  static const int longArray = 12;
}

/// A tag name, as `DataOutput.writeUTF`: a 16-bit length and modified UTF-8.
/// The keys of a Sable payload are ASCII, and [utf8] writes the same bytes.
void _writeString(BytesBuilder out, String value) {
  final bytes = utf8.encode(value);
  if (bytes.length > 0xFFFF) {
    throw ArgumentError('NBT string is longer than 65535 bytes: $value');
  }
  out.addByte((bytes.length >> 8) & 0xFF);
  out.addByte(bytes.length & 0xFF);
  out.add(bytes);
}

/// Writes [tag] as an unnamed NBT root compound (what `NbtIo.write` produces).
Uint8List writeNbt(Map<String, Object?> tag) {
  final out = BytesBuilder(copy: false);
  out.addByte(NbtTagId.compound);
  _writeString(out, '');
  _writeCompoundBody(out, tag);
  return out.takeBytes();
}

/// Reads an unnamed NBT root compound (what `NbtIo.read` accepts).
Map<String, Object?> readNbt(Uint8List bytes) {
  final reader = _NbtReader(bytes);
  final type = reader.readTagId();
  if (type != NbtTagId.compound) {
    throw FormatException('NBT root is tag type $type, expected a compound');
  }
  reader.readUtf();
  final value = reader.readPayload(NbtTagId.compound);
  if (value is! Map<String, Object?>) {
    throw const FormatException('NBT root compound did not decode to a compound');
  }
  return value;
}

void _writeCompoundBody(BytesBuilder out, Map<String, Object?> tag) {
  for (final entry in tag.entries) {
    final value = entry.value;
    if (value == null) continue; // A compound has no null tags in NBT.
    out.addByte(_tagIdOf(value, entry.key));
    _writeString(out, entry.key);
    _writePayload(out, value);
  }
  out.addByte(NbtTagId.end);
}

int _tagIdOf(Object value, String key) => switch (value) {
  bool() => NbtTagId.byte,
  int() when value >= -0x80000000 && value <= 0x7FFFFFFF => NbtTagId.int_,
  int() => NbtTagId.long,
  double() => NbtTagId.double_,
  String() => NbtTagId.string,
  Uint8List() => NbtTagId.byteArray,
  Uint64List() || Int64List() => NbtTagId.longArray,
  List() when value is List<int> => _intArrayTagId(value),
  List() => NbtTagId.list,
  Map() => NbtTagId.compound,
  _ => throw ArgumentError('Cannot write $key as NBT: unsupported ${value.runtimeType}'),
};

/// An int array is an NBT long array when any value does not fit in 32 bits.
/// Java's `BitSet.toLongArray` (the occupancy grid) and the heightmaps depend on
/// the value, so this is what keeps a re-encoded tag's types stable.
int _intArrayTagId(List<int> values) => values.any(_needsLong) ? NbtTagId.longArray : NbtTagId.intArray;

bool _needsLong(int value) => value < -0x80000000 || value > 0x7FFFFFFF;

void _writePayload(BytesBuilder out, Object value) {
  switch (value) {
    case bool():
      out.addByte(value ? 1 : 0);
    case int():
      if (value >= -0x80000000 && value <= 0x7FFFFFFF) {
        _writeInt32(out, value);
      } else {
        _writeInt64(out, value);
      }
    case double():
      final data = ByteData(8)..setFloat64(0, value, Endian.big);
      out.add(data.buffer.asUint8List());
    case String():
      _writeString(out, value);
    case Uint8List():
      _writeInt32(out, value.length);
      out.add(value);
    case Uint64List():
      _writeInt32(out, value.length);
      for (final element in value) {
        _writeInt64(out, element);
      }
    case Int64List():
      _writeInt32(out, value.length);
      for (final element in value) {
        _writeInt64(out, element);
      }
    case List<int>():
      _writeInt32(out, value.length);
      if (_intArrayTagId(value) == NbtTagId.longArray) {
        for (final element in value) {
          _writeInt64(out, element);
        }
      } else {
        for (final element in value) {
          _writeInt32(out, element);
        }
      }
    case List():
      _writeList(out, value);
    case Map():
      _writeCompoundBody(out, Map<String, Object?>.from(value));
    default:
      throw ArgumentError('Cannot write NBT payload of type ${value.runtimeType}');
  }
}

void _writeList(BytesBuilder out, List<Object?> list) {
  var elementType = NbtTagId.end;
  for (final element in list) {
    if (element == null) continue;
    elementType = _tagIdOf(element, 'list element');
    break;
  }
  out.addByte(elementType);
  _writeInt32(out, list.length);
  for (final element in list) {
    if (element == null) {
      throw ArgumentError('Cannot write a null element into an NBT list');
    }
    _writePayload(out, element);
  }
}

void _writeInt32(BytesBuilder out, int value) {
  out.addByte((value >> 24) & 0xFF);
  out.addByte((value >> 16) & 0xFF);
  out.addByte((value >> 8) & 0xFF);
  out.addByte(value & 0xFF);
}

void _writeInt64(BytesBuilder out, int value) {
  _writeInt32(out, value >> 32);
  _writeInt32(out, value & 0xFFFFFFFF);
}

/// The reader, mirroring `DataInput`.
final class _NbtReader {
  _NbtReader(this.bytes);

  final Uint8List bytes;
  int at = 0;

  int readTagId() {
    if (at >= bytes.length) {
      throw const FormatException('NBT stream ended before a tag type');
    }
    return bytes[at++];
  }

  String readUtf() {
    final length = readUint16();
    if (at + length > bytes.length) {
      throw const FormatException('NBT string runs past the end of the stream');
    }
    final value = utf8.decode(Uint8List.sublistView(bytes, at, at + length));
    at += length;
    return value;
  }

  int readUint16() {
    _require(2);
    final value = (bytes[at] << 8) | bytes[at + 1];
    at += 2;
    return value;
  }

  /// A signed 32-bit int, like `DataInput.readInt`.
  int readInt32() {
    _require(4);
    final value =
        (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3];
    at += 4;
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  int readInt64() {
    _require(8);
    final value = ByteData.sublistView(bytes, at, at + 8).getInt64(0, Endian.big);
    at += 8;
    return value;
  }

  double readFloat32() {
    _require(4);
    final value = ByteData.sublistView(bytes, at, at + 4).getFloat32(0, Endian.big);
    at += 4;
    return value;
  }

  double readFloat64() {
    _require(8);
    final value = ByteData.sublistView(bytes, at, at + 8).getFloat64(0, Endian.big);
    at += 8;
    return value;
  }

  void _require(int count) {
    if (at + count > bytes.length) {
      throw const FormatException('NBT stream ended in the middle of a tag');
    }
  }

  Object readPayload(int type) {
    switch (type) {
      case NbtTagId.byte:
        _require(1);
        final value = bytes[at++];
        return value >= 0x80 ? value - 0x100 : value;
      case NbtTagId.short:
        final value = readUint16();
        return value >= 0x8000 ? value - 0x10000 : value;
      case NbtTagId.int_:
        return readInt32();
      case NbtTagId.long:
        return readInt64();
      case NbtTagId.float:
        return readFloat32();
      case NbtTagId.double_:
        return readFloat64();
      case NbtTagId.byteArray:
        final length = readInt32();
        if (length < 0) throw const FormatException('NBT byte array has a negative length');
        _require(length);
        final value = Uint8List.sublistView(bytes, at, at + length);
        at += length;
        return value;
      case NbtTagId.string:
        return readUtf();
      case NbtTagId.list:
        return _readList();
      case NbtTagId.compound:
        return _readCompound();
      case NbtTagId.intArray:
        final length = readInt32();
        if (length < 0) throw const FormatException('NBT int array has a negative length');
        return [for (var i = 0; i < length; i++) readInt32()];
      case NbtTagId.longArray:
        final length = readInt32();
        if (length < 0) throw const FormatException('NBT long array has a negative length');
        final value = Uint64List(length);
        for (var i = 0; i < length; i++) {
          value[i] = readInt64();
        }
        return value;
      default:
        throw FormatException('Unknown NBT tag type $type');
    }
  }

  List<Object?> _readList() {
    final elementType = readTagId();
    final length = readInt32();
    if (length < 0) throw const FormatException('NBT list has a negative length');
    if (elementType == NbtTagId.end) {
      // An empty list is written with the end marker; a non-empty one may not.
      if (length != 0) {
        throw FormatException('NBT list of length $length has no element type');
      }
      return <Object?>[];
    }
    return [for (var i = 0; i < length; i++) readPayload(elementType)];
  }

  Map<String, Object?> _readCompound() {
    final result = <String, Object?>{};
    while (true) {
      final type = readTagId();
      if (type == NbtTagId.end) return result;
      final name = readUtf();
      result[name] = readPayload(type);
    }
  }
}

/// The codec Sable's storage files use: gzip-compressed NBT.
final class NbtSubLevelCodec implements SubLevelCodec {
  /// With [compress] left null the codec follows
  /// `SubLevelStorageFile.compressData` (Java's `COMPRESS_DATA`), so flipping
  /// that global switches the payload format the way it does in the mod.
  NbtSubLevelCodec({this.compress});

  /// Whether payloads are gzip-compressed; null means "follow
  /// `SubLevelStorageFile.compressData`".
  final bool? compress;

  /// Whether payloads are written compressed right now.
  bool get isCompressing => compress ?? SubLevelStorageFile.compressData;

  @override
  Uint8List encode(Map<String, Object?> tag) {
    final nbt = writeNbt(tag);
    return isCompressing ? gzipEncode(nbt) : nbt;
  }

  @override
  Map<String, Object?> decode(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      return readNbt(gzipDecode(bytes));
    }
    if (isCompressing) {
      throw const FormatException(
        'Sub-level payload is not gzip-compressed, but Sable writes every payload with '
        'NbtIo.writeCompressed (COMPRESS_DATA = true)',
      );
    }
    return readNbt(bytes);
  }
}