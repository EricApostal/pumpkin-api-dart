// The embedded data pack format (pure Dart, no host or dart:io): a list of files
// serialised as one blob, gzip compressed, base64 encoded and split in chunks.
// `tool/package_datapack.dart` writes it (using dart:io's gzip), the plugin reads
// it with [gunzip], a small inflate that works under dart2wasm (no dart:io there).
//
// Blob layout (before gzip), all integers are unsigned LEB128 varints:
//   entry*  where entry = pathLength path(utf8) dataLength data
import 'dart:convert';
import 'dart:typed_data';

/// One file of the pack: [path] relative to the pack root, with `/` separators.
final class PackFile {
  final String path;
  final Uint8List bytes;

  const PackFile(this.path, this.bytes);

  @override
  String toString() => 'PackFile($path, ${bytes.length} bytes)';
}

/// One embedded category (recipes, tags, ...) as generated into `datapack.g.dart`.
final class PackBlob {
  /// The category name, the key of the config switch (`datapack.<category>`).
  final String category;

  /// Number of files and their total uncompressed size, for logging.
  final int fileCount;
  final int rawBytes;

  /// base64 of the gzip of the serialised files, in order.
  final List<String> chunks;

  const PackBlob(this.category, this.fileCount, this.rawBytes, this.chunks);

  /// Decodes the files of this blob.
  List<PackFile> unpack() => decodePackBlob(chunks);
}

// -- serialisation ---------------------------------------------------------------

void _writeVarint(BytesBuilder out, int value) {
  while (value >= 0x80) {
    out.addByte((value & 0x7f) | 0x80);
    value >>= 7;
  }
  out.addByte(value);
}

/// Serialises [files] (not yet compressed).
Uint8List encodePackEntries(Iterable<PackFile> files) {
  final out = BytesBuilder(copy: false);
  for (final f in files) {
    final path = utf8.encode(f.path);
    _writeVarint(out, path.length);
    out.add(path);
    _writeVarint(out, f.bytes.length);
    out.add(f.bytes);
  }
  return out.toBytes();
}

/// The inverse of [encodePackEntries].
List<PackFile> decodePackEntries(Uint8List data) {
  final files = <PackFile>[];
  var i = 0;
  int varint() {
    var shift = 0;
    var value = 0;
    while (true) {
      if (i >= data.length) throw const FormatException('truncated pack data');
      final b = data[i++];
      value |= (b & 0x7f) << shift;
      if (b < 0x80) return value;
      shift += 7;
    }
  }

  while (i < data.length) {
    final pathLength = varint();
    if (i + pathLength > data.length) throw const FormatException('truncated pack path');
    final path = utf8.decode(Uint8List.sublistView(data, i, i + pathLength));
    i += pathLength;
    final length = varint();
    if (i + length > data.length) throw const FormatException('truncated pack file');
    files.add(PackFile(path, Uint8List.sublistView(data, i, i + length)));
    i += length;
  }
  return files;
}

/// Splits [text] into pieces of at most [size] characters.
List<String> chunkString(String text, {int size = 4096}) => [
  for (var i = 0; i < text.length; i += size) text.substring(i, i + size < text.length ? i + size : text.length),
];

/// Decodes the chunks of a blob: concatenate, base64, gunzip, entries.
List<PackFile> decodePackBlob(List<String> chunks) {
  final b64 = StringBuffer();
  for (final c in chunks) {
    b64.write(c);
  }
  return decodePackEntries(gunzip(base64Decode(b64.toString())));
}

/// A stable 64 bit FNV-1a hash (as 16 hex digits) over [parts] (each prefixed by
/// its length, so the split points matter).
String fnv1a64Hex(Iterable<List<int>> parts) {
  const prime = 0x100000001b3;
  var h = -3750763034362895579; // 0xcbf29ce484222325 as a signed 64 bit int
  void mix(int b) {
    h ^= b & 0xff;
    h *= prime;
  }

  for (final p in parts) {
    for (var n = p.length, k = 0; k < 4; k++, n >>= 8) {
      mix(n);
    }
    for (final b in p) {
      mix(b);
    }
  }
  final hi = ((h >> 32) & 0xffffffff).toRadixString(16).padLeft(8, '0');
  final lo = (h & 0xffffffff).toRadixString(16).padLeft(8, '0');
  return hi + lo;
}

// -- gunzip ----------------------------------------------------------------------

/// Decompresses a gzip stream (RFC 1952 around RFC 1951 deflate). Throws a
/// [FormatException] on corrupt input.
Uint8List gunzip(Uint8List input) {
  if (input.length < 18 || input[0] != 0x1f || input[1] != 0x8b || input[2] != 8) {
    throw const FormatException('not a gzip stream');
  }
  final flags = input[3];
  var pos = 10;
  if (flags & 4 != 0) pos += 2 + (input[pos] | (input[pos + 1] << 8));
  if (flags & 8 != 0) {
    while (input[pos++] != 0) {}
  }
  if (flags & 16 != 0) {
    while (input[pos++] != 0) {}
  }
  if (flags & 2 != 0) pos += 2;
  final expected = input[input.length - 4] |
      (input[input.length - 3] << 8) |
      (input[input.length - 2] << 16) |
      (input[input.length - 1] << 24);
  final out = _Inflater(input, pos, expected).run();
  if (out.length != expected) throw const FormatException('gzip size mismatch');
  final o = input.length - 8;
  final crc = input[o] | (input[o + 1] << 8) | (input[o + 2] << 16) | (input[o + 3] << 24);
  if (_crc32(out) != crc) throw const FormatException('gzip checksum mismatch');
  return out;
}

Uint32List? _crcTable;

int _crc32(Uint8List data) {
  var table = _crcTable;
  if (table == null) {
    table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    _crcTable = table;
  }
  var c = 0xffffffff;
  for (final b in data) {
    c = table[(c ^ b) & 0xff] ^ (c >> 8);
  }
  return (c ^ 0xffffffff) & 0xffffffff;
}

const _lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
const _lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
const _distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
const _distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
const _clOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

/// A canonical Huffman table (counts per length, symbols sorted by code).
final class _Huffman {
  final Uint16List count = Uint16List(16);
  late final Uint16List symbol;

  _Huffman(List<int> lengths, [int n = -1]) {
    final total = n < 0 ? lengths.length : n;
    symbol = Uint16List(total);
    for (var i = 0; i < total; i++) {
      count[lengths[i]]++;
    }
    final offs = Uint16List(16);
    for (var l = 1; l < 15; l++) {
      offs[l + 1] = offs[l] + count[l];
    }
    for (var i = 0; i < total; i++) {
      if (lengths[i] != 0) symbol[offs[lengths[i]]++] = i;
    }
  }
}

final class _Inflater {
  final Uint8List _in;
  int _pos;
  int _bitBuf = 0;
  int _bitCnt = 0;
  Uint8List _out;
  int _outLen = 0;

  _Inflater(this._in, this._pos, int sizeHint) : _out = Uint8List(sizeHint > 0 && sizeHint < (1 << 30) ? sizeHint : 1 << 16);

  int _bits(int need) {
    var val = _bitBuf;
    while (_bitCnt < need) {
      if (_pos >= _in.length) throw const FormatException('deflate: unexpected end');
      val |= _in[_pos++] << _bitCnt;
      _bitCnt += 8;
    }
    _bitBuf = val >> need;
    _bitCnt -= need;
    return val & ((1 << need) - 1);
  }

  void _put(int b) {
    if (_outLen == _out.length) {
      final bigger = Uint8List(_out.length * 2);
      bigger.setRange(0, _outLen, _out);
      _out = bigger;
    }
    _out[_outLen++] = b;
  }

  int _decode(_Huffman h) {
    var code = 0, first = 0, index = 0;
    for (var len = 1; len <= 15; len++) {
      code |= _bits(1);
      final count = h.count[len];
      if (code - count < first) return h.symbol[index + (code - first)];
      index += count;
      first += count;
      first <<= 1;
      code <<= 1;
    }
    throw const FormatException('deflate: bad code');
  }

  Uint8List run() {
    int last;
    do {
      last = _bits(1);
      switch (_bits(2)) {
        case 0:
          _stored();
        case 1:
          _fixed();
        case 2:
          _dynamic();
        default:
          throw const FormatException('deflate: bad block type');
      }
    } while (last == 0);
    return Uint8List.sublistView(_out, 0, _outLen);
  }

  void _stored() {
    _bitBuf = 0;
    _bitCnt = 0;
    if (_pos + 4 > _in.length) throw const FormatException('deflate: truncated');
    final len = _in[_pos] | (_in[_pos + 1] << 8);
    final nlen = _in[_pos + 2] | (_in[_pos + 3] << 8);
    if (len != (~nlen & 0xffff)) throw const FormatException('deflate: bad stored length');
    _pos += 4;
    if (_pos + len > _in.length) throw const FormatException('deflate: truncated');
    for (var i = 0; i < len; i++) {
      _put(_in[_pos++]);
    }
  }

  static _Huffman? _fixedLit;
  static _Huffman? _fixedDist;

  void _fixed() {
    if (_fixedLit == null) {
      final l = List<int>.filled(288, 8);
      for (var i = 144; i < 256; i++) {
        l[i] = 9;
      }
      for (var i = 256; i < 280; i++) {
        l[i] = 7;
      }
      _fixedLit = _Huffman(l);
      _fixedDist = _Huffman(List<int>.filled(30, 5));
    }
    _codes(_fixedLit!, _fixedDist!);
  }

  void _dynamic() {
    final nlen = _bits(5) + 257;
    final ndist = _bits(5) + 1;
    final ncode = _bits(4) + 4;
    final lengths = List<int>.filled(320, 0);
    for (var i = 0; i < ncode; i++) {
      lengths[_clOrder[i]] = _bits(3);
    }
    final cl = _Huffman(lengths, 19);
    var idx = 0;
    final all = List<int>.filled(nlen + ndist, 0);
    while (idx < nlen + ndist) {
      final sym = _decode(cl);
      if (sym < 16) {
        all[idx++] = sym;
      } else {
        var prev = 0;
        int rep;
        if (sym == 16) {
          if (idx == 0) throw const FormatException('deflate: bad repeat');
          prev = all[idx - 1];
          rep = 3 + _bits(2);
        } else if (sym == 17) {
          rep = 3 + _bits(3);
        } else {
          rep = 11 + _bits(7);
        }
        if (idx + rep > nlen + ndist) throw const FormatException('deflate: bad repeat');
        while (rep-- > 0) {
          all[idx++] = prev;
        }
      }
    }
    _codes(_Huffman(all.sublist(0, nlen)), _Huffman(all.sublist(nlen)));
  }

  void _codes(_Huffman lit, _Huffman dist) {
    while (true) {
      var sym = _decode(lit);
      if (sym < 256) {
        _put(sym);
      } else if (sym == 256) {
        return;
      } else {
        sym -= 257;
        if (sym >= 29) throw const FormatException('deflate: bad length');
        final len = _lengthBase[sym] + _bits(_lengthExtra[sym]);
        final ds = _decode(dist);
        if (ds >= 30) throw const FormatException('deflate: bad distance');
        final d = _distBase[ds] + _bits(_distExtra[ds]);
        if (d > _outLen) throw const FormatException('deflate: distance too far');
        for (var i = 0; i < len; i++) {
          _put(_out[_outLen - d]);
        }
      }
    }
  }
}
