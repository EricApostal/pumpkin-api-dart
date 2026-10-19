// `ContraptionHandler` (pure): the contraptions of each world that take part in collision. The
// host calls [tick] from its world tick; spawned entities are queued and join the collision list
// on the next tick.
import 'contraption_collider.dart';
import 'contraption_entity.dart';

/// `ContraptionHandler`.
abstract final class ContraptionHandler {
  static final Map<String, Map<int, AbstractContraptionEntity>> _loaded = {};
  static final Map<String, List<AbstractContraptionEntity>> _queued = {};

  /// `tick(world)`: registers queued entities, drops dead ones and collides the rest.
  static void tick(String worldId) {
    final map = _loaded.putIfAbsent(worldId, () => {});
    final queued = _queued[worldId];
    if (queued != null) {
      for (final entity in queued) {
        map[entity.entityId] = entity;
      }
      queued.clear();
    }

    for (final entry in map.entries.toList()) {
      final entity = entry.value;
      if (!entity.isAliveOrStale) {
        map.remove(entry.key);
        continue;
      }
      if (!entity.isAlive) {
        entity.staleTicks--;
        continue;
      }
      ContraptionCollider.collideEntities(entity);
    }
  }

  /// `addSpawnedContraptionsToCollisionList`.
  static void addSpawnedContraptionsToCollisionList(
    String worldId,
    AbstractContraptionEntity entity,
  ) {
    _queued.putIfAbsent(worldId, () => []).add(entity);
  }

  /// The contraption entity with [id] in [worldId], `null` when it is not loaded.
  static AbstractContraptionEntity? entityById(String worldId, int id) =>
      _loaded[worldId]?[id];

  /// Forgets the contraptions of a world that unloaded.
  static void forgetWorld(String worldId) {
    _loaded.remove(worldId);
    _queued.remove(worldId);
  }

  static void clear() {
    _loaded.clear();
    _queued.clear();
  }
}
