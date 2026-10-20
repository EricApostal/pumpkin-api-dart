// `dev.simulated_team.simulated.util.SimLevelUtil`: whether the area around a
// position is actually loaded, which the spring and the assembler need before
// they touch a partner position.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.util.SimLevelUtil
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'package:create/src/common/pos.dart' show Pos;
import 'package:sable/sable.dart';

/// Level queries that do not belong to a single content class.
abstract final class SimLevelUtil {
  /// Whether a sub-level contains [center], or every chunk within [range]
  /// blocks of it is loaded and its y range is inside the world.
  static bool isAreaActuallyLoaded(SableLevel level, Pos center, int range) {
    if (SubLevelHelper.getContaining(level, center) != null) return true;

    if (center.$2 + range < level.minY || center.$2 - range >= level.maxY) {
      return false;
    }

    final host = SubLevelContainer.of(level)?.chunkHost;
    if (host == null) return false;

    final minChunkX = (center.$1 - range) >> 4;
    final maxChunkX = (center.$1 + range) >> 4;
    final minChunkZ = (center.$3 - range) >> 4;
    final maxChunkZ = (center.$3 + range) >> 4;

    for (var chunkX = minChunkX; chunkX <= maxChunkX; chunkX++) {
      for (var chunkZ = minChunkZ; chunkZ <= maxChunkZ; chunkZ++) {
        if (host.getLoadedChunk(chunkX, chunkZ) == null) return false;
      }
    }

    return true;
  }
}
