// `TranslatingContraption` (pure): a contraption that moves without rotating (pistons, elevators,
// gantries, minecarts). It caches the blocks that can hit the world in the movement direction.
import '../../common/common.dart';
import '../core/contraption.dart';
import '../core/level.dart';
import 'contraption_entity.dart';

/// `TranslatingContraption`.
class TranslatingContraption extends Contraption
    implements TranslatingContraptionLike {
  Set<Pos>? _cachedColliders;
  Direction? _cachedColliderDirection;

  /// `getOrCreateColliders(world, movementDirection)`.
  Set<Pos> getOrCreateColliders(
    ContraptionLevel level,
    Direction movementDirection,
  ) {
    if (_cachedColliders == null ||
        _cachedColliderDirection != movementDirection) {
      _cachedColliderDirection = movementDirection;
      _cachedColliders = createColliders(level, movementDirection);
    }
    return _cachedColliders!;
  }

  /// `createColliders(world, movementDirection)`: the blocks with a collision shape whose
  /// neighbour in the movement direction has none.
  Set<Pos> createColliders(
    ContraptionLevel level,
    Direction movementDirection,
  ) {
    final colliders = <Pos>{};
    for (final info in getBlocks().values) {
      final offsetPos = info.pos.relative(movementDirection);
      if (level.stateCollisionEmpty(info.state)) continue;
      final next = getBlocks()[offsetPos];
      if (next != null && !level.stateCollisionEmpty(next.state)) continue;
      colliders.add(info.pos);
    }
    return colliders;
  }

  /// Drops the cached colliders when the structure changed.
  void invalidateCachedColliders() {
    _cachedColliders = null;
    _cachedColliderDirection = null;
  }

  @override
  Future<void> removeBlocksFromWorld(ContraptionLevel level, Pos offset) async {
    final count = blocks.length;
    await super.removeBlocksFromWorld(level, offset);
    if (count != blocks.length) invalidateCachedColliders();
  }

  @override
  bool canBeStabilized(Direction facing, Pos localPos) =>
      settings?.stabiliseStableContraptions ?? false;
}
