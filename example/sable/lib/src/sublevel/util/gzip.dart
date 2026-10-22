// A pure-Dart gzip codec (RFC 1952) with an inflater for RFC 1951: the wasm
// component has no `dart:io` and the plugin API exposes no compression, and
// Sable's storage payloads are gzip-compressed NBT
// (`SubLevelStorageFile.COMPRESS_DATA` → `NbtIo.writeCompressed`).
//
// The decompressor implements the whole format the Java `GZIPInputStream` can
// produce: stored, fixed-Huffman and dynamic-Huffman deflate blocks, gzip
// header flag skipping (extra/name/comment/hcrc) and the CRC32/ISIZE trailer
// check. The compressor emits a valid gzip stream of stored (uncompressed)
// deflate blocks: any inflater, including Java's, reads it back byte for byte,
// which is what the interop needs. It does not shrink the payload.
//
// Pure: no host imports. The VM tests cross-check both directions against
// `dart:io`'s `GZipCodec`.
import 'dart:typed_data';

/// The largest raw block a stored deflate block can hold (`2^16 - 1`).
const int _maxStoredBlock = 0xFFFF;

/// Compresses [bytes] into a gzip stream (stored blocks, no compression).
Uint8List gzipEncode(Uint8List bytes) {
  final out = BytesBuilder(copy: false);
  // Header: magic, CM=deflate, FLG=0 (no extra/name/comment/hcrc), mtime=0,
  // XFL=0, OS=255 (unknown), like the RFC's suggested values.
  out.add(const [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 255]);

  var offset = 0;
  while (true) {
    final end = offset + _maxStoredBlock < bytes.length ? offset + _maxStoredBlock : bytes.length;
    final length = end - offset;
    final final_ = end >= bytes.length;
    // BFINAL (1 bit) then BTYPE=00 (2 bits), LSB first; the reader aligns to the
    // next byte after these three bits, so they land in one byte.
    out.addByte(final_ ? 1 : 0);
    out.addByte(length & 0xFF);
    out.addByte((length >> 8) & 0xFF);
    final complement = (~length) & 0xFFFF;
    out.addByte(complement & 0xFF);
    out.addByte((complement >> 8) & 0xFF);
    out.add(Uint8List.sublistView(bytes, offset, end));
    offset = end;
    if (final_) break;
  }

  final crc = _crc32(bytes);
  out.addByte(crc & 0xFF);
  out.addByte((crc >> 8) & 0xFF);
  out.addByte((crc >> 16) & 0xFF);
  out.addByte((crc >> 24) & 0xFF);
  out.addByte(bytes.length & 0xFF);
  out.addByte((bytes.length >> 8) & 0xFF);
  out.addByte((bytes.length >> 16) & 0xFF);
  out.addByte((bytes.length >> 24) & 0xFF);
  return out.takeBytes();
}

/// Decompresses a gzip stream.
///
/// Throws a [FormatException] on a malformed stream, a bad CRC or a wrong size,
/// so a corrupt payload is never mistaken for a valid one.
Uint8List gzipDecode(Uint8List input) {
  if (input.length < 18) {
    throw const FormatException('gzip: stream is too short to hold a header and trailer');
  }
  if (input[0] != 0x1f || input[1] != 0x8b) {
    throw const FormatException('gzip: bad magic number (not a gzip stream)');
  }
  if (input[2] != 8) {
    throw FormatException('gzip: unsupported compression method ${input[2]}');
  }
  final flags = input[3];
  var at = 10;

  if (flags & 0x04 != 0) {
    // FEXTRA: a 2-byte little-endian length followed by that many bytes.
    if (at + 2 > input.length) throw const FormatException('gzip: truncated extra field');
    final extra = input[at] | (input[at + 1] << 8);
    at += 2 + extra;
  }
  if (flags & 0x08 != 0) at = _skipZeroTerminated(input, at, 'name');
  if (flags & 0x10 != 0) at = _skipZeroTerminated(input, at, 'comment');
  if (flags & 0x02 != 0) at += 2; // FHCRC.
  if (at > input.length) throw const FormatException('gzip: truncated header');

  final inflater = _Inflater(input, at);
  final data = inflater.inflate();

  final trailer = inflater.at;
  if (trailer + 8 > input.length) {
    throw const FormatException('gzip: truncated trailer');
  }
  final crc = _readUint32(input, trailer);
  final size = _readUint32(input, trailer + 4);
  if (size != (data.length & 0xFFFFFFFF)) {
    throw FormatException('gzip: size mismatch (header says $size, got ${data.length})');
  }
  if (crc != _crc32(data)) {
    throw const FormatException('gzip: CRC32 mismatch (the payload is corrupt)');
  }
  return data;
}

int _skipZeroTerminated(Uint8List input, int at, String what) {
  while (at < input.length && input[at] != 0) {
    at++;
  }
  if (at >= input.length) throw FormatException('gzip: unterminated $what field');
  return at + 1;
}

int _readUint32(Uint8List input, int at) =>
    input[at] | (input[at + 1] << 8) | (input[at + 2] << 16) | (input[at + 3] << 24);

/// The RFC 1951 inflater.
///
/// The Huffman decoding is the canonical "puff" algorithm: a table of
/// per-length code counts and a symbol list sorted by code, read one bit at a
/// time.
final class _Inflater {
  _Inflater(this.input, this.at);

  final Uint8List input;
  int at;

  /// The bit buffer, filled LSB first.
  int _bitBuffer = 0;
  int _bitCount = 0;

  int _bits(int need) {
    while (_bitCount < need) {
      if (at >= input.length) {
        throw const FormatException('deflate: unexpected end of stream');
      }
      _bitBuffer |= input[at++] << _bitCount;
      _bitCount += 8;
    }
    final value = _bitBuffer & ((1 << need) - 1);
    _bitBuffer >>= need;
    _bitCount -= need;
    return value;
  }

  int _bit() => _bits(1);

  /// Discards the bits of the current partial byte.
  void _alignToByte() {
    _bitBuffer = 0;
    _bitCount = 0;
  }

  Uint8List inflate() {
    final out = <int>[];
    while (true) {
      final finalBlock = _bit();
      final type = _bits(2);
      switch (type) {
        case 0:
          _storedBlock(out);
        case 1:
          _huffmanBlock(out, _fixedLiteral, _fixedDistance, false);
        case 2:
          final (literals, distances) = _dynamicTables();
          _huffmanBlock(out, literals, distances, true);
        default:
          throw const FormatException('deflate: invalid block type 3');
      }
      if (finalBlock == 1) break;
      if (out.length > 1 << 30) {
        throw const FormatException('deflate: output exceeds 1 GiB (the stream is corrupt)');
      }
    }
    return Uint8List.fromList(out);
  }

  void _storedBlock(List<int> out) {
    _alignToByte();
    if (at + 4 > input.length) throw const FormatException('deflate: truncated stored block');
    final length = input[at] | (input[at + 1] << 8);
    final complement = input[at + 2] | (input[at + 3] << 8);
    at += 4;
    if (length != ((~complement) & 0xFFFF)) {
      throw const FormatException('deflate: stored block length check failed');
    }
    if (at + length > input.length) throw const FormatException('deflate: truncated stored block');
    out.addAll(Uint8List.sublistView(input, at, at + length));
    at += length;
  }

  void _huffmanBlock(List<int> out, _Huffman literals, _Huffman distances, bool dynamic) {
    while (true) {
      final symbol = literals.decode(this);
      if (symbol < 256) {
        out.add(symbol);
      } else if (symbol == 256) {
        return;
      } else {
        final index = symbol - 257;
        if (index >= _lengthBase.length) {
          throw const FormatException('deflate: invalid length symbol');
        }
        final length = _lengthBase[index] + _bits(_lengthExtra[index]);
        final distanceSymbol = distances.decode(this);
        if (distanceSymbol >= _distanceBase.length) {
          throw const FormatException('deflate: invalid distance symbol');
        }
        final distance = _distanceBase[distanceSymbol] + _bits(_distanceExtra[distanceSymbol]);
        if (distance > out.length) {
          throw const FormatException('deflate: distance goes before the start of the output');
        }
        final start = out.length - distance;
        for (var i = 0; i < length; i++) {
          out.add(out[start + i]);
        }
      }
      if (out.length > 1 << 30) {
        throw const FormatException('deflate: output exceeds 1 GiB (the stream is corrupt)');
      }
    }
  }

  /// Reads the code lengths of a dynamic block and builds both tables.
  (_Huffman, _Huffman) _dynamicTables() {
    const order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
    final literalCount = _bits(5) + 257;
    final distanceCount = _bits(5) + 1;
    final codeLengthCount = _bits(4) + 4;
    if (literalCount > 286 || distanceCount > 30) {
      throw const FormatException('deflate: too many literal/distance codes');
    }

    final codeLengthLengths = List<int>.filled(19, 0);
    for (var i = 0; i < codeLengthCount; i++) {
      codeLengthLengths[order[i]] = _bits(3);
    }
    final codeLengths = _Huffman(codeLengthLengths, 19, 'code lengths');

    final lengths = List<int>.filled(literalCount + distanceCount, 0);
    var index = 0;
    while (index < lengths.length) {
      final symbol = codeLengths.decode(this);
      switch (symbol) {
        case 16:
          if (index == 0) {
            throw const FormatException('deflate: repeat with no previous code length');
          }
          final previous = lengths[index - 1];
          var repeat = 3 + _bits(2);
          while (repeat-- > 0 && index < lengths.length) {
            lengths[index++] = previous;
          }
        case 17:
          var repeat = 3 + _bits(3);
          while (repeat-- > 0 && index < lengths.length) {
            lengths[index++] = 0;
          }
        case 18:
          var repeat = 11 + _bits(7);
          while (repeat-- > 0 && index < lengths.length) {
            lengths[index++] = 0;
          }
        default:
          lengths[index++] = symbol;
      }
    }

    final literals = _Huffman(lengths.sublist(0, literalCount), literalCount, 'literal');
    final distances = _Huffman(lengths.sublist(literalCount), distanceCount, 'distance');
    return (literals, distances);
  }
}

/// A canonical Huffman decoding table.
final class _Huffman {
  _Huffman(List<int> lengths, int count, String what) : _count = List<int>.filled(16, 0) {
    for (var symbol = 0; symbol < count; symbol++) {
      _count[lengths[symbol]]++;
    }
    if (_count[0] == count) {
      throw FormatException('deflate: no $what codes in the block');
    }

    // Over-subscribed codes are invalid; incomplete ones are only valid for a
    // single-symbol code (the RFC's exception, which a fixed distance table
    // needs for the two unused codes).
    var left = 1;
    for (var length = 1; length <= 15; length++) {
      left <<= 1;
      left -= _count[length];
      if (left < 0) throw FormatException('deflate: over-subscribed $what code lengths');
    }
    if (left > 0) {
      // An incomplete code is only valid as the RFC's single one-bit symbol
      // (the fixed distance table relies on it).
      var maxLength = 0;
      for (var length = 1; length <= 15; length++) {
        if (_count[length] > 0) maxLength = length;
      }
      if (maxLength != 1) {
        throw FormatException('deflate: incomplete $what code lengths');
      }
    }

    _offset = List<int>.filled(16, 0);
    var sum = 0;
    for (var length = 1; length <= 15; length++) {
      _offset[length] = sum;
      sum += _count[length];
    }
    _symbol = List<int>.filled(sum > 0 ? sum : 1, 0);
    final next = List<int>.from(_offset);
    for (var symbol = 0; symbol < count; symbol++) {
      final length = lengths[symbol];
      if (length != 0) _symbol[next[length]++] = symbol;
    }
  }

  final List<int> _count;
  late final List<int> _offset;
  late final List<int> _symbol;

  /// Decodes one symbol.
  int decode(_Inflater inflater) {
    var code = 0;
    var first = 0;
    var index = 0;
    for (var length = 1; length <= 15; length++) {
      code |= inflater._bit();
      final count = _count[length];
      if (code - first < count) {
        return _symbol[index + (code - first)];
      }
      index += count;
      first += count;
      first <<= 1;
      code <<= 1;
    }
    throw const FormatException('deflate: invalid Huffman code');
  }
}

final _fixedLiteral = () {
  final lengths = List<int>.filled(288, 0);
  for (var symbol = 0; symbol < 144; symbol++) {
    lengths[symbol] = 8;
  }
  for (var symbol = 144; symbol < 256; symbol++) {
    lengths[symbol] = 9;
  }
  for (var symbol = 256; symbol < 280; symbol++) {
    lengths[symbol] = 7;
  }
  for (var symbol = 280; symbol < 288; symbol++) {
    lengths[symbol] = 8;
  }
  return _Huffman(lengths, 288, 'fixed literal');
}();

final _fixedDistance = () {
  final lengths = List<int>.filled(32, 5);
  return _Huffman(lengths, 32, 'fixed distance');
}();

const List<int> _lengthBase = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
];

const List<int> _lengthExtra = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
];

const List<int> _distanceBase = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
];

const List<int> _distanceExtra = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
];

int _crc32(Uint8List bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (~crc) & 0xFFFFFFFF;
}