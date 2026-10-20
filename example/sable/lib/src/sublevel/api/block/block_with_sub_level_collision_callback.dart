// `dev.ryanhcode.sable.api.block.BlockWithSubLevelCollisionCallback`: blocks
// with a physics collision callback.
//
// Java finds the callback by asking the block object and by reading the
// `sable:fragile` block property. Dart block states are plain data, so the
// callback is looked up in a registry the block modules fill in, and the fragile
// property falls back to the callback the physics module installs.
//
// Pure: no host imports.
//
// create's block-state type is not exported from its public barrel yet, so it is
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;

import '../physics/callback/block_sub_level_collision_callback.dart';

/// A block with a collision callback.
abstract interface class BlockWithSubLevelCollisionCallback {
  /// The callback of this block.
  BlockSubLevelCollisionCallback sable$getCallback();

  static final Map<String, BlockSubLevelCollisionCallback> _callbacks = {};

  /// The callback used for states with the `fragile` property, installed by the
  /// physics module (Java `FragileBlockCallback.INSTANCE`).
  static BlockSubLevelCollisionCallback? fragileCallback;

  /// Registers the callback of [blockKey] (`minecraft:stone`).
  static void register(String blockKey, BlockSubLevelCollisionCallback callback) =>
      _callbacks[blockKey] = callback;

  /// Removes the callback of [blockKey].
  static void unregister(String blockKey) => _callbacks.remove(blockKey);

  /// `sable$getCallback(state)`: the callback of [state], or `null`.
  static BlockSubLevelCollisionCallback? sable$getCallbackFor(BState state) {
    final registered = _callbacks[state.key];
    if (registered != null) return registered;
    if (state.flag('fragile')) return fragileCallback;
    return null;
  }

  /// Whether [state] has a collision callback.
  static bool hasCallback(BState state) => sable$getCallbackFor(state) != null;
}
