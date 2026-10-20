// `dev.ryanhcode.sable.api.block.BlockSubLevelAssemblyListener`: a block that is
// notified whenever assembly moves it.
//
// Pure: no host imports.
//
// create's block-state type is not exported from its public barrel yet, so it is
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/pos.dart' show Pos;

import '../../host/sub_level_host.dart';

/// A block that wants to know when [SubLevelAssemblyHelper] moves it.
abstract interface class BlockSubLevelAssemblyListener {
  /// Called before the block is moved from [oldPos] to [newPos].
  void beforeMove(
    SableLevel originLevel,
    SableLevel resultingLevel,
    BState newState,
    Pos oldPos,
    Pos newPos,
  ) {}

  /// Called after the block was moved; the old block has not been removed yet.
  void afterMove(
    SableLevel originLevel,
    SableLevel resultingLevel,
    BState newState,
    Pos oldPos,
    Pos newPos,
  );
}
