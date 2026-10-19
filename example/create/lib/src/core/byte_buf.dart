// FriendlyByteBuf helpers (pure) on top of `PacketReader` / `PacketWriter` of
// pumpkin_api, which already have VarInt, VarLong, strings, UUIDs (as text),
// floats/doubles, optionals, lists and packed block positions. This adds the
// rest of what Create's packets use.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import 'nbt.dart';

extension CreatePacketReader on PacketReader {
  /// Three doubles.
  (double, double, double) readVec3() => (readDouble(), readDouble(), readDouble());

  /// A VarInt ordinal of [values] (`FriendlyByteBuf.readEnum`).
  T readEnum<T extends Enum>(List<T> values) {
    final ordinal = readVarInt();
    if (ordinal < 0 || ordinal >= values.length) {
      throw PacketException('Enum ordinal $ordinal out of range 0..${values.length - 1}');
    }
    return values[ordinal];
  }

  /// A list of VarInts.
  List<int> readVarIntList({int maxLength = 65535}) => readList((r) => r.readVarInt(), maxLength: maxLength);

  /// A resource location as `namespace:path`.
  String readId() => readString(maxLength: 32767);

  /// A network NBT root tag, `null` for `TAG_End`.
  NbtValue? readNbt() => NetworkNbt.read(this);

  /// A compound written with [CreatePacketWriter.writeNbt]; an empty compound if absent.
  Map<String, NbtValue> readNbtCompound() => readNbt()?.asCompound ?? <String, NbtValue>{};
}

extension CreatePacketWriter on PacketWriter {
  /// Three doubles.
  void writeVec3((double, double, double) v) {
    writeDouble(v.$1);
    writeDouble(v.$2);
    writeDouble(v.$3);
  }

  /// A VarInt ordinal (`FriendlyByteBuf.writeEnum`).
  void writeEnum(Enum value) => writeVarInt(value.index);

  /// A list of VarInts.
  void writeVarIntList(Iterable<int> values) => writeList<int>(values, (w, v) => w.writeVarInt(v));

  /// A resource location.
  void writeId(String id) => writeString(id, maxLength: 32767);

  /// A network NBT root tag; `null` writes `TAG_End`.
  void writeNbt(NbtValue? root) => NetworkNbt.write(this, root);
}
