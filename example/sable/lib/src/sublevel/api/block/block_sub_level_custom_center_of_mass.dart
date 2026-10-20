// `dev.ryanhcode.sable.api.block.BlockSubLevelCustomCenterOfMass`: a block that
// supplies its own centre of mass for sub-level physics.
//
// Pure: no host imports.
//
// create's block-state type is not exported from its public barrel yet, so it is
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState, BlockGetter;

import '../../math/vector.dart';

/// A block with a custom centre of mass.
abstract interface class BlockSubLevelCustomCenterOfMass {
  /// The centre of mass baked for [state], relative to the lower corner of the
  /// block.
  Vector3d getCenterOfMass(BlockGetter blockGetter, BState state);
}
