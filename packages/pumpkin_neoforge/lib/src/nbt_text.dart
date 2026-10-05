// The tiny part of network NBT that text components need. Binding-free.
//
// NeoForge's `neoforge:modded_network_setup_failed` carries `Component`s, which
// vanilla writes as *network NBT* (`ComponentSerialization.
// TRUSTED_CONTEXT_FREE_STREAM_CODEC`): the tag type byte, then the tag
// payload, with no root name. A plain text component is a string tag; a
// translatable one is a compound `{translate, with}`.
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:pumpkin_api/src/packet_buffer.dart';

const int _tagEnd = 0;
const int _tagString = 8;
const int _tagList = 9;
const int _tagCompound = 10;

/// A text component, as much as the negotiation needs: literal text, or a
/// translation key with arguments (the client translates it).
final class NbtText {
  final String? _literal;
  final String? _key;
  final List<NbtText> _args;

  /// A literal text component.
  const NbtText.literal(String text)
    : _literal = text,
      _key = null,
      _args = const [];

  /// A translatable component; the client looks [key] up in its language.
  const NbtText.translatable(String key, [List<NbtText> args = const []])
    : _literal = null,
      _key = key,
      _args = args;

  /// Whether this is a literal component.
  bool get isLiteral => _literal != null;

  /// The text of a literal component, or the translation key.
  String get textOrKey => _literal ?? _key!;

  /// The arguments of a translatable component.
  List<NbtText> get args => _args;

  /// The component as network NBT bytes.
  Uint8List encode() => PacketBuffer.encode(write);

  /// Writes the component as network NBT.
  void write(PacketWriter writer) {
    final literal = _literal;
    if (literal != null) {
      // A component without style or children is a bare string tag.
      writer.writeByte(_tagString);
      _writeNbtString(writer, literal);
      return;
    }
    writer.writeByte(_tagCompound);
    _writeNamed(
      writer,
      _tagString,
      'translate',
      (w) => _writeNbtString(w, _key!),
    );
    if (_args.isNotEmpty) {
      _writeNamed(writer, _tagList, 'with', (w) {
        // Lists are homogeneous: every argument is a compound.
        w.writeByte(_tagCompound);
        w.writeInt(_args.length);
        for (final arg in _args) {
          arg._writeCompoundPayload(w);
        }
      });
    }
    writer.writeByte(_tagEnd);
  }

  void _writeCompoundPayload(PacketWriter writer) {
    final literal = _literal;
    if (literal != null) {
      _writeNamed(
        writer,
        _tagString,
        'text',
        (w) => _writeNbtString(w, literal),
      );
    } else {
      _writeNamed(
        writer,
        _tagString,
        'translate',
        (w) => _writeNbtString(w, _key!),
      );
      if (_args.isNotEmpty) {
        _writeNamed(writer, _tagList, 'with', (w) {
          w.writeByte(_tagCompound);
          w.writeInt(_args.length);
          for (final arg in _args) {
            arg._writeCompoundPayload(w);
          }
        });
      }
    }
    writer.writeByte(_tagEnd);
  }

  /// Reads a component written by [write], or any plain string tag or
  /// `{text}` / `{translate, with}` compound. Other tags throw a
  /// [PacketException].
  static NbtText read(PacketReader reader) {
    final type = reader.readUnsignedByte();
    return _readPayload(reader, type);
  }

  /// Like [read], from bytes (trailing bytes are an error).
  static NbtText decode(List<int> data) => PacketBuffer.decode(data, read);

  static NbtText _readPayload(PacketReader reader, int type) {
    if (type == _tagString) return NbtText.literal(_readNbtString(reader));
    if (type != _tagCompound) {
      throw PacketException(
        'Unsupported NBT tag type $type in a text component',
      );
    }
    String? text;
    String? key;
    var args = <NbtText>[];
    while (true) {
      final entryType = reader.readUnsignedByte();
      if (entryType == _tagEnd) break;
      final name = _readNbtString(reader);
      if (name == 'text' && entryType == _tagString) {
        text = _readNbtString(reader);
      } else if (name == 'translate' && entryType == _tagString) {
        key = _readNbtString(reader);
      } else if (name == 'with' && entryType == _tagList) {
        final elementType = reader.readUnsignedByte();
        final count = reader.readInt();
        if (count < 0 || count > 256) {
          throw PacketException('Text component with $count arguments');
        }
        args = [
          for (var i = 0; i < count; i++) _readPayload(reader, elementType),
        ];
      } else {
        throw PacketException('Unsupported text component field "$name"');
      }
    }
    if (text != null) return NbtText.literal(text);
    if (key != null) return NbtText.translatable(key, args);
    throw const PacketException('Text component without text or translate');
  }

  /// A readable rendering for logs: literal text as is, a translatable
  /// component as `key(arg, ...)`.
  @override
  String toString() => isLiteral
      ? _literal!
      : _args.isEmpty
      ? _key!
      : '$_key(${_args.join(', ')})';

  @override
  bool operator ==(Object other) =>
      other is NbtText &&
      other._literal == _literal &&
      other._key == _key &&
      _listEquals(other._args, _args);

  @override
  int get hashCode => Object.hash(_literal, _key, Object.hashAll(_args));
}

bool _listEquals(List<NbtText> a, List<NbtText> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _writeNamed(
  PacketWriter writer,
  int type,
  String name,
  void Function(PacketWriter writer) writePayload,
) {
  writer.writeByte(type);
  _writeNbtString(writer, name);
  writePayload(writer);
}

/// Java's "modified UTF-8" (what `DataOutput.writeUTF` and NBT use): a 16-bit
/// byte length, NUL as two bytes, supplementary characters as two 3-byte
/// surrogates.
Uint8List encodeModifiedUtf8(String text) {
  final out = <int>[];
  for (final unit in text.codeUnits) {
    if (unit != 0 && unit < 0x80) {
      out.add(unit);
    } else if (unit < 0x800) {
      out
        ..add(0xC0 | (unit >> 6))
        ..add(0x80 | (unit & 0x3F));
    } else {
      out
        ..add(0xE0 | (unit >> 12))
        ..add(0x80 | ((unit >> 6) & 0x3F))
        ..add(0x80 | (unit & 0x3F));
    }
  }
  return Uint8List.fromList(out);
}

/// The inverse of [encodeModifiedUtf8].
String decodeModifiedUtf8(List<int> bytes) {
  final units = <int>[];
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b < 0x80) {
      units.add(b);
      i += 1;
    } else if (b & 0xE0 == 0xC0 && i + 1 < bytes.length) {
      units.add(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
      i += 2;
    } else if (b & 0xF0 == 0xE0 && i + 2 < bytes.length) {
      units.add(
        ((b & 0x0F) << 12) |
            ((bytes[i + 1] & 0x3F) << 6) |
            (bytes[i + 2] & 0x3F),
      );
      i += 3;
    } else {
      throw const PacketException('Malformed modified UTF-8 in NBT string');
    }
  }
  return String.fromCharCodes(units);
}

void _writeNbtString(PacketWriter writer, String text) {
  final bytes = encodeModifiedUtf8(text);
  if (bytes.length > 0xFFFF) {
    throw PacketException('NBT string of ${bytes.length} bytes is too long');
  }
  writer.writeShort(bytes.length);
  writer.writeBytes(bytes);
}

String _readNbtString(PacketReader reader) {
  final length = reader.readUnsignedShort();
  return decodeModifiedUtf8(reader.readBytes(length));
}
