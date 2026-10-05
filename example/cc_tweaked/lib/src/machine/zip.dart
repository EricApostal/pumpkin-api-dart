// Reads zip archives (the CC: Tweaked mod jar) in pure Dart: the central
// directory and the `stored` and `deflate` methods, which is all a jar uses.
// The inflate routine follows zlib's `puff.c`.
import 'dart:typed_data';

/// The archive is not a zip file we can read.
final class ZipException implements Exception {
  final String message;

  const ZipException(this.message);

  @override
  String toString() => 'ZipException: $message';
}

/// One file of an archive.
final class ZipEntry {
  final String name;
  final int size;
  final int _method;
  final int _compressedSize;
  final int _headerOffset;
  final Uint8List _archive;

  ZipEntry._(
    this.name,
    this.size,
    this._method,
    this._compressedSize,
    this._headerOffset,
    this._archive,
  );

  bool get isDirectory => name.endsWith('/');

  /// The decompressed content.
  Uint8List read() {
    final view = ByteData.sublistView(_archive);
    if (view.getUint32(_headerOffset, Endian.little) != 0x04034b50) {
      throw ZipException('Bad local header for $name');
    }
    final nameLength = view.getUint16(_headerOffset + 26, Endian.little);
    final extraLength = view.getUint16(_headerOffset + 28, Endian.little);
    final start = _headerOffset + 30 + nameLength + extraLength;
    final data = Uint8List.sublistView(_archive, start, start + _compressedSize);
    switch (_method) {
      case 0:
        return Uint8List.fromList(data);
      case 8:
        return _Inflater(data, size).run();
      default:
        throw ZipException('Unsupported compression method $_method for $name');
    }
  }
}

/// The files of a zip archive.
final class ZipArchive {
  final List<ZipEntry> entries;

  ZipArchive._(this.entries);

  /// Reads the central directory of [bytes].
  factory ZipArchive.parse(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    var eocd = bytes.length - 22;
    while (eocd >= 0 && view.getUint32(eocd, Endian.little) != 0x06054b50) {
      eocd--;
    }
    if (eocd < 0) throw const ZipException('Not a zip archive');
    final count = view.getUint16(eocd + 10, Endian.little);
    var offset = view.getUint32(eocd + 16, Endian.little);
    final entries = <ZipEntry>[];
    for (var i = 0; i < count; i++) {
      if (offset + 46 > bytes.length ||
          view.getUint32(offset, Endian.little) != 0x02014b50) {
        throw const ZipException('Corrupt central directory');
      }
      final method = view.getUint16(offset + 10, Endian.little);
      final compressed = view.getUint32(offset + 20, Endian.little);
      final size = view.getUint32(offset + 24, Endian.little);
      final nameLength = view.getUint16(offset + 28, Endian.little);
      final extraLength = view.getUint16(offset + 30, Endian.little);
      final commentLength = view.getUint16(offset + 32, Endian.little);
      final headerOffset = view.getUint32(offset + 42, Endian.little);
      final name = String.fromCharCodes(
        Uint8List.sublistView(bytes, offset + 46, offset + 46 + nameLength),
      );
      entries.add(ZipEntry._(name, size, method, compressed, headerOffset, bytes));
      offset += 46 + nameLength + extraLength + commentLength;
    }
    return ZipArchive._(entries);
  }

  /// The entry called [name], or null.
  ZipEntry? find(String name) {
    for (final entry in entries) {
      if (entry.name == name) return entry;
    }
    return null;
  }
}

const List<int> _lengthBase = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, //
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
];
const List<int> _lengthExtra = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, //
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
];
const List<int> _distBase = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, //
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
];
const List<int> _distExtra = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, //
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
];
const List<int> _codeLengthOrder = [
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15, //
];

/// A canonical Huffman code: how many symbols have each length, and the
/// symbols in code order.
final class _Huffman {
  final List<int> count = List<int>.filled(16, 0);
  final List<int> symbol;

  _Huffman(List<int> lengths, int n) : symbol = List<int>.filled(n, 0) {
    for (var i = 0; i < n; i++) {
      count[lengths[i]]++;
    }
    final offsets = List<int>.filled(16, 0);
    for (var len = 1; len < 15; len++) {
      offsets[len + 1] = offsets[len] + count[len];
    }
    for (var i = 0; i < n; i++) {
      if (lengths[i] != 0) symbol[offsets[lengths[i]]++] = i;
    }
  }
}

final class _Inflater {
  final Uint8List _input;
  final Uint8List _output;
  int _in = 0;
  int _out = 0;
  int _bitBuffer = 0;
  int _bitCount = 0;

  _Inflater(this._input, int expectedSize) : _output = Uint8List(expectedSize);

  int _bits(int need) {
    var value = _bitBuffer;
    while (_bitCount < need) {
      if (_in >= _input.length) throw const ZipException('Truncated deflate data');
      value |= _input[_in++] << _bitCount;
      _bitCount += 8;
    }
    _bitBuffer = value >> need;
    _bitCount -= need;
    return value & ((1 << need) - 1);
  }

  int _decode(_Huffman h) {
    var code = 0;
    var first = 0;
    var index = 0;
    for (var len = 1; len <= 15; len++) {
      code |= _bits(1);
      final count = h.count[len];
      if (code - count < first) return h.symbol[index + (code - first)];
      index += count;
      first += count;
      first <<= 1;
      code <<= 1;
    }
    throw const ZipException('Invalid Huffman code');
  }

  void _stored() {
    _bitBuffer = 0;
    _bitCount = 0;
    if (_in + 4 > _input.length) throw const ZipException('Truncated stored block');
    final len = _input[_in] | (_input[_in + 1] << 8);
    _in += 4;
    if (_in + len > _input.length || _out + len > _output.length) {
      throw const ZipException('Stored block overflows');
    }
    _output.setRange(_out, _out + len, _input, _in);
    _in += len;
    _out += len;
  }

  void _codes(_Huffman lengthCode, _Huffman distanceCode) {
    while (true) {
      var symbol = _decode(lengthCode);
      if (symbol < 256) {
        if (_out >= _output.length) throw const ZipException('Output overflow');
        _output[_out++] = symbol;
      } else if (symbol == 256) {
        return;
      } else {
        symbol -= 257;
        if (symbol >= 29) throw const ZipException('Invalid length symbol');
        final len = _lengthBase[symbol] + _bits(_lengthExtra[symbol]);
        final distSymbol = _decode(distanceCode);
        if (distSymbol >= 30) throw const ZipException('Invalid distance symbol');
        final dist = _distBase[distSymbol] + _bits(_distExtra[distSymbol]);
        if (dist > _out) throw const ZipException('Distance too far back');
        if (_out + len > _output.length) throw const ZipException('Output overflow');
        for (var i = 0; i < len; i++) {
          _output[_out] = _output[_out - dist];
          _out++;
        }
      }
    }
  }

  void _fixed() {
    final lengths = List<int>.filled(288, 0);
    for (var i = 0; i < 144; i++) {
      lengths[i] = 8;
    }
    for (var i = 144; i < 256; i++) {
      lengths[i] = 9;
    }
    for (var i = 256; i < 280; i++) {
      lengths[i] = 7;
    }
    for (var i = 280; i < 288; i++) {
      lengths[i] = 8;
    }
    final lengthCode = _Huffman(lengths, 288);
    final distanceCode = _Huffman(List<int>.filled(30, 5), 30);
    _codes(lengthCode, distanceCode);
  }

  void _dynamic() {
    final nlen = _bits(5) + 257;
    final ndist = _bits(5) + 1;
    final ncode = _bits(4) + 4;
    if (nlen > 286 || ndist > 30) throw const ZipException('Bad dynamic block');
    final lengths = List<int>.filled(320, 0);
    for (var i = 0; i < ncode; i++) {
      lengths[_codeLengthOrder[i]] = _bits(3);
    }
    final lengthLengths = _Huffman(lengths.sublist(0, 19), 19);
    var index = 0;
    final all = List<int>.filled(nlen + ndist, 0);
    while (index < nlen + ndist) {
      var symbol = _decode(lengthLengths);
      if (symbol < 16) {
        all[index++] = symbol;
      } else {
        var previous = 0;
        int repeat;
        if (symbol == 16) {
          if (index == 0) throw const ZipException('No previous length');
          previous = all[index - 1];
          repeat = 3 + _bits(2);
        } else if (symbol == 17) {
          repeat = 3 + _bits(3);
        } else {
          repeat = 11 + _bits(7);
        }
        if (index + repeat > nlen + ndist) {
          throw const ZipException('Too many lengths');
        }
        while (repeat-- > 0) {
          all[index++] = previous;
        }
      }
    }
    final lengthCode = _Huffman(all.sublist(0, nlen), nlen);
    final distanceCode = _Huffman(all.sublist(nlen), ndist);
    _codes(lengthCode, distanceCode);
  }

  Uint8List run() {
    bool last;
    do {
      last = _bits(1) == 1;
      switch (_bits(2)) {
        case 0:
          _stored();
        case 1:
          _fixed();
        case 2:
          _dynamic();
        default:
          throw const ZipException('Invalid block type');
      }
    } while (!last);
    if (_out != _output.length) throw const ZipException('Size mismatch');
    return _output;
  }
}
