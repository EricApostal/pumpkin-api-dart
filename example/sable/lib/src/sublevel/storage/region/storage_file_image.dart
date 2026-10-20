// The on-disk format of Sable's sub-level storage files, as a pure in-memory
// implementation.
//
// A storage file (`.slvls`) starts with a 4096-byte header of 1024 span ints.
// Each span is `(sectorStart << 8) | sectorLength` (length ≤ 255 sectors); a
// span of 0 means "no data at this index". Data sectors follow the header.
// Payloads larger than 255 sectors move to an external file (`.slvl`) and the
// span holds a one-sector stub whose payload type byte has the external mask
// set.
//
// Each payload is framed as a 4-byte length, one type byte, then the bytes the
// codec produced (Java writes gzip-compressed NBT there).
//
// Pure: no host imports.
import 'dart:typed_data';

import '../util/bit_grid.dart';

/// A growable sector bitset (Java `BitSet`, which grows on demand).
final class _SectorBits {
  final List<int> _words = [];

  bool get(int index) {
    final word = index >> 5;
    if (word >= _words.length) return false;
    return (_words[word] & (1 << (index & 31))) != 0;
  }

  void set(int index, [bool value = true]) {
    final word = index >> 5;
    while (_words.length <= word) {
      _words.add(0);
    }
    if (value) {
      _words[word] |= 1 << (index & 31);
    } else {
      _words[word] &= ~(1 << (index & 31)) & 0xFFFFFFFF;
    }
  }

  void setRange(int start, int end, [bool value = true]) {
    for (var i = start; i < end; i++) {
      set(i, value);
    }
  }

  void clearRange(int start, int end) => setRange(start, end, false);

  /// The index of the first set bit at or after [from], or `-1`.
  int nextSetBit(int from) {
    for (var i = from; i < _words.length * 32; i++) {
      if (get(i)) return i;
    }
    return -1;
  }

  /// The index of the first clear bit at or after [from].
  int nextClearBit(int from) {
    var i = from;
    while (get(i)) {
      i++;
    }
    return i;
  }

  /// One past the highest set bit (Java `BitSet.length()`).
  int get length {
    for (var word = _words.length - 1; word >= 0; word--) {
      final value = _words[word];
      if (value != 0) {
        for (var bit = 31; bit >= 0; bit--) {
          if ((value & (1 << bit)) != 0) return word * 32 + bit + 1;
        }
      }
    }
    return 0;
  }
}

/// A sub-level storage file in memory.
final class StorageFileImage {
  /// The size of the header (and of every sector of a region file).
  static const int headerSize = 4096;

  /// The number of sub-level indices in one storage file.
  static const int indexCapacity = headerSize ~/ 4;

  /// The maximum span length, in sectors (the length field is one byte).
  static const int maxSpanLength = 255;

  /// The payload type flag that means "the payload lives in an external file".
  static const int externalMask = 16;

  /// The sector size of the file.
  final int sectorSize;

  /// The header spans, one per index.
  final Int32List spans;

  final _SectorBits _usedSectors = _SectorBits();
  final BitGrid usedIndices = BitGrid(indexCapacity);

  /// The data sectors, growing as needed. `image[0..headerSize)` is the header.
  Uint8List image;

  /// The external payloads by index (one `.slvl` file each).
  final Map<int, Uint8List> externalPayloads = {};

  StorageFileImage(this.sectorSize, {Uint8List? existing})
    : spans = Int32List(indexCapacity),
      image = existing ?? Uint8List(headerSize) {
    // Sector 0 (the header) is always in use.
    _usedSectors.setRange(0, headerSize ~/ sectorSize);
    if (existing != null) {
      _readHeader();
    }
  }

  void _readHeader() {
    final headerBytes = existingHeaderBytes(image);
    for (var index = 0; index < indexCapacity; index++) {
      final span = _readInt(headerBytes, index * 4);
      spans[index] = span;
      usedIndices.set(index, span != 0);
      if (span == 0) continue;

      final start = spanStart(span);
      final length = spanLength(span);
      if (length <= 0 || start < 0) continue;
      _usedSectors.setRange(start, start + length);
    }
  }

  static Uint8List existingHeaderBytes(Uint8List image) {
    final header = Uint8List(headerSize);
    final copy = image.length < headerSize ? image.length : headerSize;
    header.setRange(0, copy, image);
    return header;
  }

  static int _readInt(Uint8List bytes, int offset) {
    final data = ByteData.sublistView(bytes, offset, offset + 4);
    return data.getInt32(0);
  }

  static void _writeInt(Uint8List bytes, int offset, int value) {
    final data = ByteData.sublistView(bytes, offset, offset + 4);
    data.setInt32(0, value);
  }

  /// `SubLevelStorageFile.findFreeIndex`.
  int findFreeIndex() => usedIndices.nextClearBit(0);

  /// The total number of indices.
  int get totalIndexCapacity => indexCapacity;

  /// `getSpanStart`.
  int spanStart(int span) => (span >> 8) & 0xFFFFFF;

  /// `getSpanLength`.
  int spanLength(int span) => span & 0xFF;

  /// `packSpan`.
  int packSpan(int start, int length) {
    if (start < 0 || length <= 0 || length > maxSpanLength) {
      throw ArgumentError('Invalid span: start=$start, length=$length');
    }
    return (start << 8) | length;
  }

  /// Whether the file has no payloads.
  bool get isEmpty => _usedSectors.length <= (headerSize ~/ sectorSize);

  /// Allocates [spaceNeeded] consecutive free sectors and returns the start.
  int allocateSpace(int spaceNeeded) {
    var j = 0;
    while (true) {
      final start = _usedSectors.nextClearBit(j);
      final nextSet = _usedSectors.nextSetBit(start);
      if (nextSet == -1 || nextSet - start >= spaceNeeded) {
        _usedSectors.setRange(start, start + spaceNeeded);
        return start;
      }
      j = nextSet;
    }
  }

  int _sizeToSectors(int sizeBytes) => (sizeBytes + sectorSize - 1) ~/ sectorSize;

  void _ensureCapacity(int sectors) {
    final needed = sectors * sectorSize;
    if (image.length >= needed) return;
    final grown = Uint8List(needed);
    grown.setRange(0, image.length, image);
    image = grown;
  }

  /// Writes the payload [bytes] at [index] (Java `write(int, ByteBuffer)`).
  void write(int index, Uint8List bytes) {
    final oldSpan = spans[index];
    final oldStart = spanStart(oldSpan);
    final oldLength = spanLength(oldSpan);

    var sectorsNeeded = _sizeToSectors(bytes.length + 5);
    var external = false;
    if (sectorsNeeded > maxSpanLength) {
      external = true;
      sectorsNeeded = 1;
    }

    final sectorStart = allocateSpace(sectorsNeeded);
    _ensureCapacity(sectorStart + sectorsNeeded);

    final framed = _frame(bytes, external: external);
    if (external) {
      externalPayloads[index] = Uint8List.fromList(bytes);
      image.setRange(sectorStart * sectorSize, sectorStart * sectorSize + framed.length, framed);
    } else {
      image.setRange(sectorStart * sectorSize, sectorStart * sectorSize + framed.length, framed);
      externalPayloads.remove(index);
    }

    spans[index] = packSpan(sectorStart, sectorsNeeded);
    usedIndices.set(index, true);
    _writeHeader();

    if (oldStart != 0) {
      _usedSectors.clearRange(oldStart, oldStart + oldLength);
    }
  }

  static Uint8List _frame(Uint8List payload, {required bool external}) {
    final header = ByteData(5);
    if (external) {
      // A stub: "one byte of data follows", with the external flag.
      header.setInt32(0, 1);
      header.setUint8(4, externalMask);
      return header.buffer.asUint8List();
    }
    header.setInt32(0, payload.length + 1);
    header.setUint8(4, 0);
    final framed = Uint8List(5 + payload.length);
    framed.setRange(0, 5, header.buffer.asUint8List());
    framed.setRange(5, 5 + payload.length, payload);
    return framed;
  }

  /// Reads the payload at [index], or `null` when there is none.
  Uint8List? read(int index) {
    if (index < 0 || index >= indexCapacity) return null;
    final span = spans[index];
    final start = spanStart(span);
    final length = spanLength(span);
    if (start == 0) return null;
    if (length <= 0 || (start + length) * sectorSize > image.length) return null;

    final sectorBytes = Uint8List.sublistView(
      image,
      start * sectorSize,
      (start + length) * sectorSize,
    );
    if (sectorBytes.length < 5) return null;

    final remaining = ByteData.sublistView(sectorBytes).getInt32(0);
    final type = sectorBytes[4];
    if (remaining == 0) return null;

    if ((type & externalMask) != 0) {
      return externalPayloads[index];
    }

    final payloadLength = remaining - 1;
    if (payloadLength < 0 || payloadLength > sectorBytes.length - 5) return null;
    return Uint8List.sublistView(sectorBytes, 5, 5 + payloadLength);
  }

  /// Clears the payload at [index].
  void clear(int index) {
    final span = spans[index];
    if (span == 0) return;

    spans[index] = 0;
    usedIndices.clear(index);

    final start = spanStart(span);
    _usedSectors.clearRange(start, start + spanLength(span));
    _writeHeader();
    externalPayloads.remove(index);
  }

  void _writeHeader() {
    for (var index = 0; index < indexCapacity; index++) {
      _writeInt(image, index * 4, spans[index]);
    }
  }

  /// Truncates or pads the image to whole sectors (Java
  /// `padOrTruncateToFullSector`).
  void padOrTruncateToFullSector() {
    final desired = _usedSectors.length * sectorSize;
    if (image.length == desired) return;
    final resized = Uint8List(desired);
    final copy = image.length < desired ? image.length : desired;
    resized.setRange(0, copy, image);
    image = resized;
  }

  /// The bytes to write to disk.
  Uint8List flushBytes() {
    _writeHeader();
    padOrTruncateToFullSector();
    return image;
  }
}
