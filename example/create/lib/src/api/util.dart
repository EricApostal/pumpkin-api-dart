/// Create's utility classes for all modules (published by the `content` module).
///
/// Java name -> Dart:
/// * `Direction`, `Direction.Axis`, `Rotation`, `Mirror` -> [Direction], [Axis], [BlockRotation], [BlockMirror]
/// * `BlockPos` -> `Pos` = `(int, int, int)` (`PosMath`: `relative`, `above`, `distSqr`, ...); `toBlockPos()` / `toPos()`
/// * `Vec3` -> `Vec3` = `(double, double, double)` (`Vec3Math` of pumpkin_api)
/// * `VecHelper`, `AngleHelper`, `BlockFace`, `Couple`, `Pair`, `Iterate`, `IntAttached`, `Pointing`, `BBHelper`
///   (on [BlockBounds]), `DyeHelper`, `StringHelper`
/// * `BlockHelper` (host parts: `destroyBlock`, `findAndRemoveInInventory`, `setZeroAge`, ...), `BlockStates`
///   (property access by state id), `NbtHelper`
library;

export '../common/common.dart';
export '../common/host_bridge.dart';
