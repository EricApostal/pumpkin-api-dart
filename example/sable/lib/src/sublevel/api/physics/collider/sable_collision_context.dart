// `dev.ryanhcode.sable.api.physics.collider.SableCollisionContext`: the context
// used when baking collision shapes for the physics pipeline.
//
// Java's version extends vanilla `CollisionContext`; the Dart port only needs
// the block-state getter the shape callbacks read, so that is what it carries.
//
// Pure: no host imports.
//
// create's block-state types are not exported from its public barrel yet, so
// they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState, BlockGetter;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;

/// The collision context used for sub-level physics shapes.
abstract interface class SableCollisionContext {
  /// The blocks the shape is baked against.
  BlockGetter get blockGetter;

  /// The context to use for getting shapes.
  static SableCollisionContext get() => _instance;

  static final SableCollisionContext _instance = _SableCollisionContextImpl();
}

final class _SableCollisionContextImpl implements SableCollisionContext {
  @override
  BlockGetter get blockGetter => _EmptyBlockGetter.instance;
}

final class _EmptyBlockGetter implements BlockGetter {
  static final _EmptyBlockGetter instance = _EmptyBlockGetter();

  // `BlockGetter` batches repeated reads; the empty getter has nothing to cache.
  @override
  void beginBatch() {}

  @override
  void endBatch() {}

  @override
  BState stateAt((int, int, int) p) => BState.air;

  @override
  bool isLoaded((int, int, int) p) => false;

  @override
  bool isFaceSturdy((int, int, int) p, Direction face) => false;

  @override
  List<BlockBox> collisionBoxes((int, int, int) p) => const [];

  @override
  bool supportShapeEmpty((int, int, int) p) => true;

  @override
  bool canBeReplaced((int, int, int) p) => true;

  /// `BlockGetter.isSolid`: the empty getter has no blocks, so nothing is solid.
  @override
  bool isSolid((int, int, int) p) => false;

  @override
  bool hasTag((int, int, int) p, String tag) => false;

  @override
  bool isWater((int, int, int) p) => false;

  @override
  bool collisionShapeEmpty((int, int, int) p) => true;

  @override
  bool isCollisionShapeFullBlock((int, int, int) p) => false;
}
