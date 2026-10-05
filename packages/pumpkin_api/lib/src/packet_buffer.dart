// Minecraft's `FriendlyByteBuf` primitives and payload codecs. Free of host
// imports, so it can be unit-tested on the Dart VM; the public API re-exports
// it from package:pumpkin_api.
import 'dart:convert';
import 'dart:typed_data';

/// Thrown when packet data cannot be encoded or decoded: it is malformed, too
/// long, or ends too early.
class PacketException implements Exception {
  final String message;

  const PacketException(this.message);

  @override
  String toString() => 'PacketException: $message';
}

/// Thrown when a [PacketReader] needs more bytes than are left.
final class PacketUnderflowException extends PacketException {
  /// How many bytes were needed.
  final int needed;

  /// How many bytes were left.
  final int available;

  /// Where in the data the read started.
  final int offset;

  PacketUnderflowException(this.needed, this.available, this.offset)
    : super(
        'Truncated data: needed $needed byte(s) at offset $offset, '
        'but only $available left',
      );
}

/// The default maximum length of a string, in UTF-16 code units, as in
/// Minecraft's `FriendlyByteBuf.readUtf()`.
const int defaultMaxStringLength = 32767;

/// Reads the primitives of Minecraft's network format from a byte array.
///
/// All multi-byte numbers are big endian. Reads that run past the end of the
/// data throw a [PacketUnderflowException]; malformed data throws a
/// [PacketException].
///
/// ```dart
/// final reader = PacketReader(data);
/// final version = reader.readVarInt();
/// final name = reader.readString(maxLength: 64);
/// reader.expectEnd();
/// ```
final class PacketReader {
  final Uint8List _bytes;
  final ByteData _view;
  int _offset;

  /// Reads [bytes] (not copied) from the start.
  PacketReader(List<int> bytes)
    : this._(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));

  PacketReader._(Uint8List bytes)
    : _bytes = bytes,
      _view = ByteData.sublistView(bytes),
      _offset = 0;

  /// How many bytes were read so far.
  int get position => _offset;

  /// How many bytes are left.
  int get remaining => _bytes.length - _offset;

  /// Whether all bytes were read.
  bool get isExhausted => _offset >= _bytes.length;

  /// Throws a [PacketException] if bytes are left. Use it after reading a
  /// whole message, to reject trailing garbage.
  void expectEnd() {
    if (!isExhausted) {
      throw PacketException('$remaining unexpected trailing byte(s)');
    }
  }

  int _take(int count) {
    if (count < 0) throw PacketException('Negative length $count');
    if (remaining < count) {
      throw PacketUnderflowException(count, remaining, _offset);
    }
    final start = _offset;
    _offset += count;
    return start;
  }

  /// Skips [count] bytes.
  void skip(int count) => _take(count);

  /// A signed byte.
  int readByte() => _view.getInt8(_take(1));

  /// An unsigned byte.
  int readUnsignedByte() => _view.getUint8(_take(1));

  /// A boolean: one byte, false for zero.
  bool readBool() => readUnsignedByte() != 0;

  /// A signed 16-bit number.
  int readShort() => _view.getInt16(_take(2));

  /// An unsigned 16-bit number.
  int readUnsignedShort() => _view.getUint16(_take(2));

  /// A signed 32-bit number.
  int readInt() => _view.getInt32(_take(4));

  /// A signed 64-bit number.
  int readLong() => _view.getInt64(_take(8));

  /// A 32-bit float.
  double readFloat() => _view.getFloat32(_take(4));

  /// A 64-bit float.
  double readDouble() => _view.getFloat64(_take(8));

  /// A variable-length 32-bit number (1 to 5 bytes, 7 bits each, little end
  /// first). Throws if it is longer than 5 bytes or does not fit 32 bits.
  int readVarInt() {
    var result = 0;
    for (var i = 0; i < 5; i++) {
      final byte = readUnsignedByte();
      if (i == 4 && byte > 0x0F) {
        throw PacketException(
          byte & 0x80 != 0
              ? 'VarInt is longer than 5 bytes'
              : 'VarInt does not fit 32 bits',
        );
      }
      result |= (byte & 0x7F) << (7 * i);
      if (byte & 0x80 == 0) return result.toSigned(32);
    }
    throw const PacketException('VarInt is longer than 5 bytes');
  }

  /// A variable-length 64-bit number (1 to 10 bytes). Throws if it is longer
  /// than 10 bytes or does not fit 64 bits.
  int readVarLong() {
    var result = 0;
    for (var i = 0; i < 10; i++) {
      final byte = readUnsignedByte();
      if (i == 9 && byte > 0x01) {
        throw PacketException(
          byte & 0x80 != 0
              ? 'VarLong is longer than 10 bytes'
              : 'VarLong does not fit 64 bits',
        );
      }
      result |= (byte & 0x7F) << (7 * i);
      if (byte & 0x80 == 0) return result;
    }
    throw const PacketException('VarLong is longer than 10 bytes');
  }

  /// [count] raw bytes (a copy).
  Uint8List readBytes(int count) {
    final start = _take(count);
    return Uint8List.sublistView(_bytes, start, start + count).sublist(0);
  }

  /// All remaining bytes (a copy).
  Uint8List readRemainingBytes() => readBytes(remaining);

  /// A byte array: a VarInt length, then that many bytes. Throws if it is
  /// longer than [maxLength] or than the data left.
  Uint8List readByteArray({int? maxLength}) {
    final length = readVarInt();
    if (length < 0) throw PacketException('Negative array length $length');
    if (maxLength != null && length > maxLength) {
      throw PacketException(
        'Byte array of $length byte(s) is longer than the maximum $maxLength',
      );
    }
    return readBytes(length);
  }

  /// A UTF-8 string: a VarInt byte length, then the bytes. Like Minecraft it
  /// accepts at most [maxLength] UTF-16 code units (so at most
  /// `maxLength * 3` bytes) and throws on invalid UTF-8.
  String readString({int maxLength = defaultMaxStringLength}) {
    final length = readVarInt();
    if (length < 0) throw PacketException('Negative string length $length');
    if (length > maxLength * 3) {
      throw PacketException(
        'String of $length byte(s) is longer than the maximum '
        '${maxLength * 3} (for $maxLength characters)',
      );
    }
    final start = _take(length);
    final String text;
    try {
      text = utf8.decode(Uint8List.sublistView(_bytes, start, start + length));
    } on FormatException catch (e) {
      throw PacketException('String is not valid UTF-8: ${e.message}');
    }
    if (text.length > maxLength) {
      throw PacketException(
        'String of ${text.length} characters is longer than the maximum '
        '$maxLength',
      );
    }
    return text;
  }

  /// A UUID: two 64-bit numbers. Returned in canonical form, like
  /// `00112233-4455-6677-8899-aabbccddeeff`.
  String readUuid() {
    final high = readLong();
    final low = readLong();
    return '${_hex((high >>> 32) & 0xffffffff, 8)}-'
        '${_hex((high >>> 16) & 0xffff, 4)}-'
        '${_hex(high & 0xffff, 4)}-'
        '${_hex((low >>> 48) & 0xffff, 4)}-'
        '${_hex(low & 0xffffffffffff, 12)}';
  }

  /// A block position, packed into one 64-bit number (x: 26 bits, z: 26 bits,
  /// y: 12 bits).
  (int, int, int) readBlockPos() {
    final packed = readLong();
    return (packed >> 38, (packed << 52) >> 52, (packed << 26) >> 38);
  }

  /// An optional value: a boolean, then the value if it is true.
  T? readOptional<T>(T Function(PacketReader reader) readValue) =>
      readBool() ? readValue(this) : null;

  /// A list: a VarInt count, then the elements. Throws if there are more than
  /// [maxLength] of them.
  List<T> readList<T>(
    T Function(PacketReader reader) readElement, {
    int maxLength = 65535,
  }) {
    final count = readVarInt();
    if (count < 0) throw PacketException('Negative list size $count');
    if (count > maxLength) {
      throw PacketException(
        'List of $count element(s) is longer than the maximum $maxLength',
      );
    }
    return [for (var i = 0; i < count; i++) readElement(this)];
  }
}

/// Writes the primitives of Minecraft's network format into a growing byte
/// array. The counterpart of [PacketReader].
///
/// ```dart
/// final writer = PacketWriter()
///   ..writeVarInt(1)
///   ..writeString('hello')
///   ..writeBool(true);
/// channel.send(player, writer.toBytes());
/// ```
final class PacketWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);
  final ByteData _scratch = ByteData(8);

  /// How many bytes were written so far.
  int get length => _out.length;

  /// The bytes written so far (a copy).
  Uint8List toBytes() => Uint8List.fromList(_out.toBytes());

  void _flushScratch(int count) =>
      _out.add(Uint8List.fromList(_scratch.buffer.asUint8List(0, count)));

  void _checkRange(String type, int value, int min, int max) {
    if (value < min || value > max) {
      throw RangeError.range(value, min, max, type);
    }
  }

  /// A byte; accepts -128 to 255.
  void writeByte(int value) {
    _checkRange('byte', value, -128, 255);
    _out.addByte(value & 0xFF);
  }

  /// A boolean as one byte.
  void writeBool(bool value) => _out.addByte(value ? 1 : 0);

  /// A 16-bit number; accepts -32768 to 65535.
  void writeShort(int value) {
    _checkRange('short', value, -32768, 65535);
    _scratch.setUint16(0, value & 0xFFFF);
    _flushScratch(2);
  }

  /// A 32-bit number; accepts -2^31 to 2^32 - 1.
  void writeInt(int value) {
    _checkRange('int', value, -0x80000000, 0xFFFFFFFF);
    _scratch.setUint32(0, value & 0xFFFFFFFF);
    _flushScratch(4);
  }

  /// A 64-bit number.
  void writeLong(int value) {
    _scratch.setInt64(0, value);
    _flushScratch(8);
  }

  /// A 32-bit float.
  void writeFloat(double value) {
    _scratch.setFloat32(0, value);
    _flushScratch(4);
  }

  /// A 64-bit float.
  void writeDouble(double value) {
    _scratch.setFloat64(0, value);
    _flushScratch(8);
  }

  /// A variable-length number holding a signed 32-bit [value]. Negative
  /// numbers take 5 bytes.
  void writeVarInt(int value) {
    _checkRange('VarInt', value, -0x80000000, 0x7FFFFFFF);
    var rest = value & 0xFFFFFFFF;
    while (rest > 0x7F) {
      _out.addByte((rest & 0x7F) | 0x80);
      rest >>= 7;
    }
    _out.addByte(rest);
  }

  /// A variable-length number holding a signed 64-bit [value]. Negative
  /// numbers take 10 bytes.
  void writeVarLong(int value) {
    var rest = value;
    while (rest & ~0x7F != 0) {
      _out.addByte((rest & 0x7F) | 0x80);
      rest >>>= 7;
    }
    _out.addByte(rest);
  }

  /// Raw bytes, without a length.
  void writeBytes(List<int> bytes) {
    _out.add(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  }

  /// A byte array: a VarInt length, then the bytes.
  void writeByteArray(List<int> bytes, {int? maxLength}) {
    if (maxLength != null && bytes.length > maxLength) {
      throw PacketException(
        'Byte array of ${bytes.length} byte(s) is longer than the maximum '
        '$maxLength',
      );
    }
    writeVarInt(bytes.length);
    writeBytes(bytes);
  }

  /// A UTF-8 string: a VarInt byte length, then the bytes. Throws if [value]
  /// has more than [maxLength] UTF-16 code units. Unpaired surrogates are
  /// written as U+FFFD.
  void writeString(String value, {int maxLength = defaultMaxStringLength}) {
    if (value.length > maxLength) {
      throw PacketException(
        'String of ${value.length} characters is longer than the maximum '
        '$maxLength',
      );
    }
    final bytes = utf8.encode(value);
    if (bytes.length > maxLength * 3) {
      throw PacketException(
        'String of ${bytes.length} byte(s) is longer than the maximum '
        '${maxLength * 3}',
      );
    }
    writeVarInt(bytes.length);
    writeBytes(bytes);
  }

  /// A UUID given as text (with or without dashes) as two 64-bit numbers.
  void writeUuid(String uuid) {
    final hex = uuid.replaceAll('-', '');
    final high = _parseHex(hex, 0);
    final low = _parseHex(hex, 16);
    if (hex.length != 32 || high == null || low == null) {
      throw PacketException('Invalid UUID: $uuid');
    }
    writeLong(high);
    writeLong(low);
  }

  /// A block position packed into one 64-bit number. x and z must fit 26
  /// bits, y 12 bits (signed).
  void writeBlockPos((int, int, int) pos) {
    final (x, y, z) = pos;
    _checkRange('block x', x, -0x2000000, 0x1FFFFFF);
    _checkRange('block y', y, -0x800, 0x7FF);
    _checkRange('block z', z, -0x2000000, 0x1FFFFFF);
    writeLong(((x & 0x3FFFFFF) << 38) | ((z & 0x3FFFFFF) << 12) | (y & 0xFFF));
  }

  /// An optional value: a boolean, then the value if there is one.
  void writeOptional<T>(
    T? value,
    void Function(PacketWriter writer, T value) writeValue,
  ) {
    if (value == null) {
      writeBool(false);
    } else {
      writeBool(true);
      writeValue(this, value);
    }
  }

  /// A list: a VarInt count, then the elements.
  void writeList<T>(
    Iterable<T> values,
    void Function(PacketWriter writer, T value) writeElement,
  ) {
    final list = values is List<T> ? values : values.toList();
    writeVarInt(list.length);
    for (final value in list) {
      writeElement(this, value);
    }
  }
}

/// Shortcuts to encode and decode a whole message.
abstract final class PacketBuffer {
  /// Runs [write] on a new [PacketWriter] and returns the bytes.
  static Uint8List encode(void Function(PacketWriter writer) write) {
    final writer = PacketWriter();
    write(writer);
    return writer.toBytes();
  }

  /// Runs [read] on [data], and throws a [PacketException] if bytes are left
  /// over (unless [allowTrailing]).
  static T decode<T>(
    List<int> data,
    T Function(PacketReader reader) read, {
    bool allowTrailing = false,
  }) {
    final reader = PacketReader(data);
    final value = read(reader);
    if (!allowTrailing) reader.expectEnd();
    return value;
  }
}

/// Turns values into the bytes of a custom payload and back.
///
/// ```dart
/// final codec = PayloadCodec<Hello>.buffer(
///   write: (w, hello) => w
///     ..writeVarInt(hello.version)
///     ..writeString(hello.name),
///   read: (r) => Hello(r.readVarInt(), r.readString()),
/// );
/// ```
abstract class PayloadCodec<T> {
  const PayloadCodec();

  /// A codec from two functions.
  factory PayloadCodec.of({
    required Uint8List Function(T value) encode,
    required T Function(Uint8List data) decode,
  }) => _FunctionCodec<T>(encode, decode);

  /// A codec that uses [PacketWriter] and [PacketReader]. When [requireEnd] is
  /// true (the default) decoding fails if bytes are left over.
  factory PayloadCodec.buffer({
    required void Function(PacketWriter writer, T value) write,
    required T Function(PacketReader reader) read,
    bool requireEnd = true,
  }) => _FunctionCodec<T>(
    (value) => PacketBuffer.encode((writer) => write(writer, value)),
    (data) => PacketBuffer.decode(data, read, allowTrailing: !requireEnd),
  );

  /// The payload bytes for [value].
  Uint8List encode(T value);

  /// The value in [data]. Throws a [PacketException] or [FormatException] if
  /// the data is malformed.
  T decode(List<int> data);
}

final class _FunctionCodec<T> extends PayloadCodec<T> {
  final Uint8List Function(T value) _encode;
  final T Function(Uint8List data) _decode;

  _FunctionCodec(this._encode, this._decode);

  @override
  Uint8List encode(T value) => _encode(value);

  @override
  T decode(List<int> data) =>
      _decode(data is Uint8List ? data : Uint8List.fromList(data));
}

/// Ready-made [PayloadCodec]s.
abstract final class PayloadCodecs {
  /// The raw bytes.
  static final PayloadCodec<Uint8List> bytes = PayloadCodec<Uint8List>.of(
    encode: (value) => value,
    decode: (data) => data,
  );

  /// Text as plain UTF-8, without a length prefix.
  static final PayloadCodec<String> utf8Text = PayloadCodec<String>.of(
    encode: (value) => Uint8List.fromList(utf8.encode(value)),
    decode: (data) => utf8.decode(data),
  );

  /// A single Minecraft string (VarInt length prefix).
  static final PayloadCodec<String> string = PayloadCodec<String>.buffer(
    write: (writer, value) => writer.writeString(value),
    read: (reader) => reader.readString(),
  );

  /// A JSON value as UTF-8 text.
  static final PayloadCodec<Object?> json = PayloadCodec<Object?>.of(
    encode: (value) => Uint8List.fromList(utf8.encode(jsonEncode(value))),
    decode: (data) => jsonDecode(utf8.decode(data)),
  );
}

String _hex(int value, int width) =>
    value.toRadixString(16).padLeft(width, '0');

/// Parses the 16 hex digits at [start] as a 64-bit number, or null.
int? _parseHex(String hex, int start) {
  if (hex.length < start + 16) return null;
  final digits = hex.substring(start, start + 16);
  if (!RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(digits)) return null;
  return (int.parse(digits.substring(0, 8), radix: 16) << 32) |
      int.parse(digits.substring(8), radix: 16);
}

/// The channel clients and servers use to tell each other which custom
/// payload channels they understand.
const registerChannel = 'minecraft:register';

/// The payload of `minecraft:register`: the channel names, each followed by a
/// NUL byte (no length prefix).
///
/// Mod loaders refuse to *send* a channel the server did not announce this
/// way (NeoForge: `UnsupportedOperationException`, Fabric: `canSend` is
/// false), so a plugin that receives payloads from a mod announces them first.
Uint8List encodeChannelList(Iterable<String> channels) {
  final bytes = <int>[];
  for (final channel in channels) {
    bytes
      ..addAll(utf8.encode(channel))
      ..add(0);
  }
  return Uint8List.fromList(bytes);
}

/// The channel names in a `minecraft:register` / `minecraft:unregister`
/// payload.
List<String> decodeChannelList(List<int> data) => [
  for (final name in utf8.decode(data).split('\u0000'))
    if (name.isNotEmpty) name,
];
