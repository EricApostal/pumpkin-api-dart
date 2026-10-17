// A generic, binding-free JSON to network NBT converter, for the entries of
// datapack registries (`minecraft:registry_data`).
//
// How a real server produces such an entry (`RegistrySynchronization` /
// `RegistryDataLoader` in Minecraft 26.x): it loads the JSON file with the
// registry's *codec*, and when a client joins it encodes the decoded object
// again with the registry's *network codec* through `NbtOps`. The client then
// decodes that NBT with the same network codec, again through `NbtOps`. This
// converter skips the decode/encode on the server (the plugin has no codecs)
// and turns the JSON into the NBT the encode would have produced, as far as
// the shape goes:
//
// * JSON object -> compound, array -> list, string -> string, `true`/`false`
//   -> byte 1/0 (what `NbtOps.createBoolean` writes; `Codec.BOOL` reads any
//   numeric tag back, `DynamicOps.getBooleanValue` goes through
//   `getNumberValue`).
// * numbers: `NbtOps` keeps the type the *codec* writes (`Codec.INT` an int
//   tag, `Codec.FLOAT` a float tag, `Codec.DOUBLE` a double tag), and every
//   numeric codec reads any numeric tag back (`NbtOps.getNumberValue` accepts
//   every `NumericTag`: byte, short, int, long, float, double). A JSON file has
//   no type, so: an integer literal becomes an int tag (a long when it does not
//   fit), a literal with a fraction or exponent a double tag, unless a hint says
//   what the codec uses ([NumberHints]; CC's `damageMultiplier` is a
//   `Codec.FLOAT`). Wrong guesses are harmless for reading, they only differ
//   from what a Java server would send.
// * optional fields that equal their default are left out by the real
//   encoder; here they are written exactly as the file has them. Both decode
//   the same (an absent `optionalFieldOf` is its default).
// * lists: since 26.1 (1.21.5) a list may hold tags of different types; the
//   wire form of such a list is a list of compounds with every non-compound
//   element wrapped as `{"": element}` (`ListTag.write`). Lists of one type
//   are written as they are.
// * `null` values in an object are dropped (NBT has no null); in an array
//   they are an error.
//
// The network form of an NBT tag (`NbtIo.writeAnyTag`, 1.20.2+): the tag type
// byte, then the payload, with **no root name**. Strings are Java "modified
// UTF-8" with an unsigned short length.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

/// The NBT type a JSON number is written as.
enum NbtNumber { byte, short, int, long, float, double }

/// Tells which numeric tag a JSON number at a path should use. [path] holds
/// the object keys from the root to the number (array positions are not part
/// of it). Return `null` to use the default (int or double by the literal).
typedef NumberHints = NbtNumber? Function(List<String> path);

/// Why a JSON value cannot become NBT.
final class JsonNbtException extends FormatException {
  const JsonNbtException(super.message);
}

/// Converts JSON values (`dart:convert` results) to network NBT.
abstract final class JsonNbt {
  /// The network NBT bytes of [json] (an object for a registry entry).
  static Uint8List encode(Object? json, {NumberHints? hints}) {
    final tag = _convert(json, const [], hints);
    return PacketBuffer.encode((w) {
      w.writeByte(tag.id);
      tag.write(w);
    });
  }

  /// Like [encode], for a compound (the root of a registry entry must be one).
  static Uint8List encodeCompound(Map<String, Object?> json, {NumberHints? hints}) =>
      encode(json, hints: hints);
}

// -- Tags -----------------------------------------------------------------------

const int _end = 0;
const int _byte = 1;
const int _short = 2;
const int _int = 3;
const int _long = 4;
const int _float = 5;
const int _double = 6;
const int _string = 8;
const int _list = 9;
const int _compound = 10;

sealed class _Tag {
  const _Tag();

  int get id;

  void write(PacketWriter w);
}

final class _Number extends _Tag {
  @override
  final int id;
  final num value;

  const _Number(this.id, this.value);

  @override
  void write(PacketWriter w) {
    switch (id) {
      case _byte:
        w.writeByte(value.toInt());
      case _short:
        w.writeShort(value.toInt());
      case _int:
        w.writeInt(value.toInt());
      case _long:
        w.writeLong(value.toInt());
      case _float:
        w.writeFloat(value.toDouble());
      case _double:
        w.writeDouble(value.toDouble());
    }
  }
}

final class _Text extends _Tag {
  final String value;

  const _Text(this.value);

  @override
  int get id => _string;

  @override
  void write(PacketWriter w) => _writeModifiedUtf8(w, value);
}

final class _ListTag extends _Tag {
  final List<_Tag> elements;

  const _ListTag(this.elements);

  @override
  int get id => _list;

  @override
  void write(PacketWriter w) {
    if (elements.isEmpty) {
      w.writeByte(_end);
      w.writeInt(0);
      return;
    }
    final first = elements.first.id;
    final uniform = elements.every((e) => e.id == first);
    if (uniform) {
      w.writeByte(first);
      w.writeInt(elements.length);
      for (final element in elements) {
        element.write(w);
      }
      return;
    }
    // Mixed types: every element becomes a compound (`{"": element}` unless it
    // already is one).
    w.writeByte(_compound);
    w.writeInt(elements.length);
    for (final element in elements) {
      if (element is _CompoundTag) {
        element.write(w);
      } else {
        w.writeByte(element.id);
        _writeModifiedUtf8(w, '');
        element.write(w);
        w.writeByte(_end);
      }
    }
  }
}

final class _CompoundTag extends _Tag {
  final Map<String, _Tag> entries;

  const _CompoundTag(this.entries);

  @override
  int get id => _compound;

  @override
  void write(PacketWriter w) {
    for (final entry in entries.entries) {
      w.writeByte(entry.value.id);
      _writeModifiedUtf8(w, entry.key);
      entry.value.write(w);
    }
    w.writeByte(_end);
  }
}

_Tag _convert(Object? json, List<String> path, NumberHints? hints) {
  if (json is Map<String, Object?>) {
    final entries = <String, _Tag>{};
    for (final entry in json.entries) {
      final value = entry.value;
      if (value == null) continue;
      entries[entry.key] = _convert(value, [...path, entry.key], hints);
    }
    return _CompoundTag(entries);
  }
  if (json is List<Object?>) {
    return _ListTag([
      for (final element in json)
        if (element == null) throw JsonNbtException('null in a list at ${path.join('.')}') else _convert(element, path, hints),
    ]);
  }
  if (json is String) return _Text(json);
  if (json is bool) return _Number(_byte, json ? 1 : 0);
  if (json is num) return _number(json, path, hints);
  throw JsonNbtException('Cannot convert ${json.runtimeType} at ${path.join('.')} to NBT');
}

_Tag _number(num value, List<String> path, NumberHints? hints) {
  final hint = hints?.call(path);
  switch (hint) {
    case NbtNumber.byte:
      return _Number(_byte, value.toInt());
    case NbtNumber.short:
      return _Number(_short, value.toInt());
    case NbtNumber.int:
      return _Number(_int, value.toInt());
    case NbtNumber.long:
      return _Number(_long, value.toInt());
    case NbtNumber.float:
      return _Number(_float, value.toDouble());
    case NbtNumber.double:
      return _Number(_double, value.toDouble());
    case null:
      break;
  }
  if (value is int) {
    return value >= -0x80000000 && value <= 0x7FFFFFFF ? _Number(_int, value) : _Number(_long, value);
  }
  return _Number(_double, value.toDouble());
}

/// Java's modified UTF-8 with the unsigned short length NBT strings have:
/// code units are written one by one (a supplementary character is its two
/// surrogates, three bytes each) and NUL is `C0 80`.
void _writeModifiedUtf8(PacketWriter w, String value) {
  final bytes = <int>[];
  for (final unit in value.codeUnits) {
    if (unit != 0 && unit < 0x80) {
      bytes.add(unit);
    } else if (unit < 0x800) {
      bytes.add(0xC0 | (unit >> 6));
      bytes.add(0x80 | (unit & 0x3F));
    } else {
      bytes.add(0xE0 | (unit >> 12));
      bytes.add(0x80 | ((unit >> 6) & 0x3F));
      bytes.add(0x80 | (unit & 0x3F));
    }
  }
  if (bytes.length > 0xFFFF) {
    throw const JsonNbtException('An NBT string is longer than 65535 bytes');
  }
  w.writeShort(bytes.length);
  w.writeBytes(bytes);
}

/// The numeric hints of CC: Tweaked's upgrade codecs: `damageMultiplier` of
/// `TurtleToolSpec` is a `Codec.FLOAT`; every other number in the entries of
/// the two registries is absent or an int.
NbtNumber? upgradeNumberHints(List<String> path) =>
    path.isNotEmpty && path.last == 'damageMultiplier' ? NbtNumber.float : null;
