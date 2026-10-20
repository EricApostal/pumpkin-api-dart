// `dev.ryanhcode.sable.api.physics.collider.VoxelColliderData`: the collision
// boxes a dynamic collider builds for one block state.
//
// Pure: no host imports.
import '../../../math/vector.dart';

/// Collision boxes for a single block.
abstract interface class VoxelColliderData {
  /// Adds a collision box. Coordinates are inside a single block, `0..1`.
  void addBox(Vector3d min, Vector3d max);

  /// Removes every box.
  void clearBoxes();
}

/// The default implementation: a plain list of boxes.
final class VoxelColliderDataImpl implements VoxelColliderData {
  /// The boxes as `[minX, minY, minZ, maxX, maxY, maxZ]`.
  final List<List<double>> boxes = [];

  @override
  void addBox(Vector3d min, Vector3d max) =>
      boxes.add([min.x, min.y, min.z, max.x, max.y, max.z]);

  @override
  void clearBoxes() => boxes.clear();
}
