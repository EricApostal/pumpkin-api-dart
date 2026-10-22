// The seam between the balloon model and the host that spawns the gust entity.
//
// Java's `Balloon.spawnGust` calls `GustEntity.addGust(level, pos, dir)` directly. The model is
// pure (no host imports), so the spawn goes through this hook instead: the plugin installs it and
// spawns an `aeronautics:gust` entity, and a server without the plugin (the VM tests) leaves it
// unset.
//
// Pure: no host imports.
import 'dart:typed_data';

import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;

import '../propeller/geometry.dart' show directionRotation;

/// `GustEntity.addGust(level, pos, direction)`.
abstract final class GustSpawnHooks {
  /// Spawns one gust at the block [pos] of the world [worldId], pointing in [direction].
  static void Function(String worldId, Pos pos, Direction direction)? spawn;
}
/// The four `float`s of [direction]'s rotation quaternion (`SableBufferUtils.write`, x, y, z, w),
/// which is `GustEntity.writeSpawnData`: what the client renders the gust's particles from.
Uint8List gustSpawnData(Direction direction) {
  final q = directionRotation(direction);
  final data = ByteData(16);
  data.setFloat32(0, q.x, Endian.big);
  data.setFloat32(4, q.y, Endian.big);
  data.setFloat32(8, q.z, Endian.big);
  data.setFloat32(12, q.w, Endian.big);
  return data.buffer.asUint8List();
}

