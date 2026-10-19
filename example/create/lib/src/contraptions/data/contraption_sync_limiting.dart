// `ContraptionSyncLimiting` (pure): a contraption's spawn payload must fit in a clientbound custom
// payload, so its NBT is written as `TAG_End` (null) when it would not, and the client falls back
// to a fresh contraption (`AbstractContraptionEntity`).
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../core/nbt.dart';
import '../core/nbt_map.dart';

abstract final class ContraptionSyncLimiting {
  /// The clientbound custom payload limit the spawn packet has to fit in.
  static const int sizeLimit = 1048576;

  /// Space left for the rest of the packet.
  static const int buffer = 20000;

  /// The limit the sync check uses.
  static const int limit = sizeLimit - buffer;

  /// `writeSafe`: writes [data] to [w], or a lone `TAG_End` when it is too large.
  static void writeSafe(NbtMap data, PacketWriter w) {
    final root = data.toValue();
    if (NetworkNbt.encode(root).length > limit) {
      w.writeByte(0);
      return;
    }
    NetworkNbt.write(w, root);
  }
}
