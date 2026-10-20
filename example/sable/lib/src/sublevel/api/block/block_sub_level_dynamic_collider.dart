// `dev.ryanhcode.sable.api.block.BlockSubLevelDynamicCollider`: a block whose
// collision boxes are built at runtime instead of being baked from its shape.
//
// Pure: no host imports.
import '../physics/collider/voxel_collider_data.dart';

/// A block with a dynamic collider.
abstract interface class BlockSubLevelDynamicCollider {
  /// Fills [data] with the current collision boxes.
  void buildBoxes(VoxelColliderData data);
}
