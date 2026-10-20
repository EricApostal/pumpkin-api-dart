// `dev.ryanhcode.sable.api.block.BlockSubLevelCollisionShape`: a block that
// supplies a separate collision shape for sub-level physics.
//
// Pure: no host imports.
//
// create's block-state and shape types are not exported from its public barrel
// yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState, BlockGetter;
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;

/// A collision shape: the union of its boxes, in block units.
typedef SubLevelShape = List<BlockBox>;

/// A block with a physics-only collision shape.
abstract interface class BlockSubLevelCollisionShape {
  /// The collision shape that is baked for [state].
  SubLevelShape getSubLevelCollisionShape(BlockGetter blockGetter, BState state);
}
