// A binding-free description of the network encoding of a custom data
// component, in the prefix notation `custom-components.wit` takes: the
// builder a plugin uses to say "this component is a VarInt followed by a
// UUID", and a checker that tells whether bytes are exactly one such value.

import 'packet_buffer.dart';

/// The kind of one node of a [ComponentCodec], mirroring `codec-op` of the
/// WIT.
enum CodecOpKind {
  varInt('var-int'),
  varLong('var-long'),
  flag('flag'),
  byte('byte'),
  short('short'),
  int32('int'),
  long('long'),
  float32('float32'),
  float64('float64'),
  text('text'),
  byteArray('byte-array'),
  uuid('uuid'),
  fixedBytes('fixed-bytes'),
  nbt('nbt'),
  stack('stack'),
  componentPatch('component-patch'),
  optional('optional'),
  repeated('repeated'),
  sequence('sequence');

  const CodecOpKind(this.wireName);

  /// The name of the case in the WIT.
  final String wireName;
}

/// One entry of the op list: a [kind], and the count for `fixed-bytes(n)` and
/// `sequence(n)`.
final class ComponentCodecOp {
  final CodecOpKind kind;

  /// The `n` of `fixed-bytes(n)` and `sequence(n)`, 0 for the other kinds.
  final int argument;

  const ComponentCodecOp(this.kind, [this.argument = 0]);

  @override
  bool operator ==(Object other) =>
      other is ComponentCodecOp && other.kind == kind && other.argument == argument;

  @override
  int get hashCode => Object.hash(kind, argument);

  @override
  String toString() => switch (kind) {
    CodecOpKind.fixedBytes || CodecOpKind.sequence => '${kind.wireName}($argument)',
    _ => kind.wireName,
  };
}

/// Describes how the value of a custom data component is encoded on the wire
/// (what a client writes after the component id in an item stack), in the
/// shape the host needs to find where a value ends.
///
/// Built from combinators; the op list is in **prefix notation** with one root
/// node, which is what [ComponentTypeBackend.register] sends to the host:
///
/// ```dart
/// ComponentCodec.varInt                       // computer_id
/// ComponentCodec.sequence([ComponentCodec.varInt, ComponentCodec.varInt])
/// ComponentCodec.sequence([
///   ComponentCodec.text,
///   ComponentCodec.repeated(ComponentCodec.sequence([ComponentCodec.text, ComponentCodec.text])),
/// ])
/// ```
final class ComponentCodec {
  /// The nodes in prefix notation.
  final List<ComponentCodecOp> ops;

  const ComponentCodec._(this.ops);

  static const ComponentCodec varInt = ComponentCodec._([ComponentCodecOp(CodecOpKind.varInt)]);
  static const ComponentCodec varLong = ComponentCodec._([ComponentCodecOp(CodecOpKind.varLong)]);

  /// One byte that is 0 or 1 (`bool`).
  static const ComponentCodec flag = ComponentCodec._([ComponentCodecOp(CodecOpKind.flag)]);
  static const ComponentCodec byte = ComponentCodec._([ComponentCodecOp(CodecOpKind.byte)]);

  /// Two bytes, big endian.
  static const ComponentCodec short = ComponentCodec._([ComponentCodecOp(CodecOpKind.short)]);

  /// Four bytes, big endian.
  static const ComponentCodec int32 = ComponentCodec._([ComponentCodecOp(CodecOpKind.int32)]);

  /// Eight bytes, big endian.
  static const ComponentCodec long = ComponentCodec._([ComponentCodecOp(CodecOpKind.long)]);
  static const ComponentCodec float32 = ComponentCodec._([ComponentCodecOp(CodecOpKind.float32)]);
  static const ComponentCodec float64 = ComponentCodec._([ComponentCodecOp(CodecOpKind.float64)]);

  /// A VarInt length and that many bytes of UTF-8 (identifiers too).
  static const ComponentCodec text = ComponentCodec._([ComponentCodecOp(CodecOpKind.text)]);

  /// A VarInt length and that many bytes.
  static const ComponentCodec byteArray = ComponentCodec._([ComponentCodecOp(CodecOpKind.byteArray)]);

  /// 16 bytes.
  static const ComponentCodec uuid = ComponentCodec._([ComponentCodecOp(CodecOpKind.uuid)]);

  /// A network NBT tag (an unnamed root).
  static const ComponentCodec nbt = ComponentCodec._([ComponentCodecOp(CodecOpKind.nbt)]);

  /// An item stack in the play encoding.
  static const ComponentCodec stack = ComponentCodec._([ComponentCodecOp(CodecOpKind.stack)]);

  /// A data component patch (`VarInt added, VarInt removed, (id, value)*,
  /// removed id*`); values of custom components inside it are read with their
  /// own codec by the host.
  static const ComponentCodec componentPatch = ComponentCodec._([ComponentCodecOp(CodecOpKind.componentPatch)]);

  /// [count] bytes with no length prefix.
  factory ComponentCodec.fixedBytes(int count) {
    RangeError.checkNotNegative(count, 'count');
    return ComponentCodec._([ComponentCodecOp(CodecOpKind.fixedBytes, count)]);
  }

  /// A flag, then [inner] if the flag is true.
  factory ComponentCodec.optional(ComponentCodec inner) =>
      ComponentCodec._([const ComponentCodecOp(CodecOpKind.optional), ...inner.ops]);

  /// A VarInt count, then that many [inner] values.
  factory ComponentCodec.repeated(ComponentCodec inner) =>
      ComponentCodec._([const ComponentCodecOp(CodecOpKind.repeated), ...inner.ops]);

  /// The [parts] one after another (a record).
  factory ComponentCodec.sequence(List<ComponentCodec> parts) => ComponentCodec._([
    ComponentCodecOp(CodecOpKind.sequence, parts.length),
    for (final part in parts) ...part.ops,
  ]);

  /// How many nodes the description has.
  int get nodeCount => ops.length;

  /// The number of bytes of the one value of this codec that starts at
  /// [offset] of [bytes]. Throws a [PacketException] if the bytes end early or
  /// are malformed, and an [UnsupportedError] for `nbt`, `stack` and
  /// `component-patch`, which need the registries of the host to measure.
  int measure(List<int> bytes, [int offset = 0]) {
    final reader = PacketReader(bytes)..skip(offset);
    final next = _skip(reader, 0);
    if (next != ops.length) {
      throw StateError('Malformed codec: $nodeCount nodes, the root ends at $next');
    }
    return reader.position - offset;
  }

  /// Whether [bytes] are exactly one value of this codec (what the host
  /// checks before it accepts a value). `false` for the kinds [measure]
  /// cannot handle.
  bool accepts(List<int> bytes) {
    try {
      return measure(bytes) == bytes.length;
    } on PacketException {
      return false;
    } on UnsupportedError {
      return false;
    }
  }

  /// Skips the value of the node at [index]; returns the index after the node
  /// (and its children).
  int _skip(PacketReader reader, int index) {
    final op = ops[index];
    switch (op.kind) {
      case CodecOpKind.varInt:
        reader.readVarInt();
      case CodecOpKind.varLong:
        reader.readVarLong();
      case CodecOpKind.flag || CodecOpKind.byte:
        reader.skip(1);
      case CodecOpKind.short:
        reader.skip(2);
      case CodecOpKind.int32 || CodecOpKind.float32:
        reader.skip(4);
      case CodecOpKind.long || CodecOpKind.float64:
        reader.skip(8);
      case CodecOpKind.text:
        reader.skip(_length(reader));
      case CodecOpKind.byteArray:
        reader.skip(_length(reader));
      case CodecOpKind.uuid:
        reader.skip(16);
      case CodecOpKind.fixedBytes:
        reader.skip(op.argument);
      case CodecOpKind.nbt || CodecOpKind.stack || CodecOpKind.componentPatch:
        throw UnsupportedError('${op.kind.wireName} values cannot be measured without the host');
      case CodecOpKind.optional:
        final present = reader.readUnsignedByte();
        if (present > 1) throw PacketException('Optional flag is $present');
        final after = _end(index + 1);
        if (present == 1) _skip(reader, index + 1);
        return after;
      case CodecOpKind.repeated:
        final count = reader.readVarInt();
        if (count < 0) throw PacketException('Negative count $count');
        final after = _end(index + 1);
        for (var i = 0; i < count; i++) {
          _skip(reader, index + 1);
        }
        return after;
      case CodecOpKind.sequence:
        var next = index + 1;
        for (var i = 0; i < op.argument; i++) {
          next = _skip(reader, next);
        }
        return next;
    }
    return index + 1;
  }

  static int _length(PacketReader reader) {
    final length = reader.readVarInt();
    if (length < 0) throw PacketException('Negative length $length');
    return length;
  }

  /// The index after the node at [index], without reading anything.
  int _end(int index) {
    final op = ops[index];
    var next = index + 1;
    switch (op.kind) {
      case CodecOpKind.optional || CodecOpKind.repeated:
        next = _end(next);
      case CodecOpKind.sequence:
        for (var i = 0; i < op.argument; i++) {
          next = _end(next);
        }
      default:
        break;
    }
    return next;
  }

  @override
  bool operator ==(Object other) {
    if (other is! ComponentCodec || other.ops.length != ops.length) return false;
    for (var i = 0; i < ops.length; i++) {
      if (ops[i] != other.ops[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(ops);

  /// The prefix notation, for logs: `sequence(2) var-int uuid`.
  @override
  String toString() => ops.join(' ');
}
