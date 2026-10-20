// `dev.ryanhcode.sable.api.block.BlockEntitySubLevelReactionWheel`: a block
// entity that gives a sub-level angular momentum.
//
// Pure: no host imports.
//
// create's block-state type is not exported from its public barrel yet, so it is
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;

import '../../math/vector.dart';

/// A reaction wheel mounted on a sub-level.
abstract interface class BlockEntitySubLevelReactionWheel {
  /// Writes the wheel's angular velocity, in radians per second, into
  /// [angularVelocity].
  ///
  /// The angular momentum given to the sub-level is this velocity scaled by the
  /// block's inertia and mass properties.
  void sable$getAngularVelocity(Vector3d angularVelocity);

  /// The block state of this block entity.
  BState getBlockState();
}
