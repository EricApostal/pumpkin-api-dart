// `DimensionPalette` (pure): the dimensions a graph packet or a saved graph refers to by index.
// A dimension is the world id (`minecraft:overworld`), see `World.getId()`.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../core/byte_buf.dart';
import '../util/ctag.dart';

/// The id of the overworld (`Level.OVERWORLD`).
const String overworldId = 'minecraft:overworld';

class DimensionPalette {
  final List<String> gatheredDims;

  DimensionPalette([List<String>? gatheredDims]) : gatheredDims = gatheredDims ?? <String>[];

  int encode(String dimension) {
    var indexOf = gatheredDims.indexOf(dimension);
    if (indexOf == -1) {
      indexOf = gatheredDims.length;
      gatheredDims.add(dimension);
    }
    return indexOf;
  }

  String decode(int index) {
    if (gatheredDims.length <= index || index < 0) return overworldId;
    return gatheredDims[index];
  }

  /// `send(FriendlyByteBuf)`: an int count, then the identifiers.
  void send(PacketWriter buffer) {
    buffer.writeInt(gatheredDims.length);
    for (final rk in gatheredDims) {
      buffer.writeId(rk);
    }
  }

  static DimensionPalette receive(PacketReader buffer) {
    final palette = DimensionPalette();
    final length = buffer.readInt();
    for (var i = 0; i < length; i++) {
      palette.gatheredDims.add(buffer.readId());
    }
    return palette;
  }

  void write(CTag tag) {
    tag.putCompoundList('DimensionPalette', [
      for (final rk in gatheredDims) CTag()..putString('Id', rk),
    ]);
  }

  static DimensionPalette read(CTag tag) {
    final palette = DimensionPalette();
    for (final c in tag.getCompoundList('DimensionPalette')) {
      palette.gatheredDims.add(c.getString('Id'));
    }
    return palette;
  }
}
