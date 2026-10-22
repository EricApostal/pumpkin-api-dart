// The `aeronautics:gust` entity: the puff of gas that escapes when a balloon is ruptured.
//
// Java: `content/blocks/hot_air/gust/GustEntity`. `Balloon.spawnGust` spawns one per escaping gas
// direction (`GustEntity.addGust`); while it lives (5 ticks) it pushes the sub-level it is inside,
// and it despawns after that. The client half (particles, the local sound) is the mod's.
//
// The entity's orientation travels as its spawn data — four big-endian `float`s, the quaternion of
// `Direction.getRotation` (`SableBufferUtils.write(Quaterniondc)`), the same bytes Java writes in
// `writeSpawnData`. The host sends them with the add-entity packet, so a NeoForge client gets an
// entity it can render instead of one it discards on its first tick.
//
// Host: this file uses `pumpkin_api`.
// create's internals are not exported from its barrel yet.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/contraptions/core/entity_type_keys.dart' show reportedEntityTypeKey;
import 'package:create/src/core/module.dart' show CreateContext;
import 'package:create/src/equipment/armor/armor_host.dart' show findEntity;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart' show ServerSubLevel, SubLevelHelper, Vector3d;

import '../../../../aeronautics_hooks.dart';
import '../../../../hot_air/gust_hook.dart' show GustSpawnHooks, gustSpawnData;
import '../../../../host/world_balloon_world.dart' show balloonWorldOf;

/// The entity type key.
const String gustEntityKey = 'aeronautics:gust';

/// `GustEntity.tickCount > 5`: the tick count after which a gust despawns.
const int gustLifetimeTicks = 5;

/// `forceDir = orientation.transform((0, 1, 0)).mul(-3)`: a gust pushes along the direction it
/// points, times `-3`.
const double gustForce = -3;

/// The gust entities of the server, and the tick that moves them.
final class GustHost {
  /// The direction every live gust was spawned with, by entity id.
  ///
  /// Java keeps the orientation on the entity (`readSpawnData`), which is also what a client
  /// renders from; the port keeps the payload as the entity's spawn data and the direction here.
  final Map<int, Direction> _directions = {};

  /// Installs the spawn hook and the tick.
  void install(CreateContext ctx) {
    GustSpawnHooks.spawn = _spawn;
    ctx.listen(Events.entityTick, _onEntityTick);
    ctx.listen(Events.entityRemove, (server, e) => _directions.remove(e.entityId));
    try {
      ctx.host.tickPluginEntities(gustEntityKey, interval: 1);
    } on Object catch (e) {
      ctx.log.warn('gusts are not ticked: $e');
    }
  }

  /// `GustEntity.addGust(level, pos, direction)`: one entity at the center of [pos], pointing in
  /// [direction].
  void _spawn(String worldId, Pos pos, Direction direction) {
    final world = AeronauticsHooks.worlds?.byId(worldId);
    if (world == null) return;
    unawaited(
      world
          .spawnPlugin(
            gustEntityKey,
            (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5),
            spawnData: gustSpawnData(direction),
          )
          .then((Entity entity) => _directions[entity.getId()] = direction),
    );
  }

  /// `GustEntity.tick`: push the sub-level the gust is inside, then despawn after 5 ticks.
  ///
  /// The push is Java's: `applyImpulseAtPoint(position, orientation * (0, 1, 0) * -3)` on the
  /// containing sub-level's body. It resolves that sub-level through [SubLevelHelper], which is the
  /// only reach this component has into the port's sub-levels (see
  /// `example/sable/docs/sable-core-port.md`, "Cross-plugin ownership"): while this component's
  /// container is empty the gust still spawns and despawns on time, and the push lands as soon as
  /// the owning component's sub-levels are mirrored here.
  Future<void> _onEntityTick(Server server, EntityTickEventData e) async {
    if (reportedEntityTypeKey(e.entityType) != gustEntityKey) return;
    final entity = findEntity(server, e.entityId);
    if (entity == null) {
      _directions.remove(e.entityId);
      return;
    }

    final direction = _directions[e.entityId];
    if (direction != null) {
      final (x, y, z) = entity.getPosition();
      final level = balloonWorldOf(entity.getWorld()).level;
      final subLevel = SubLevelHelper.getContainingPos(level, Vector3d(x, y, z));
      if (subLevel is ServerSubLevel) {
        subLevel.physicsBody?.applyImpulseAtPoint(
          Vector3d(x, y, z),
          Vector3d(
            direction.stepX * gustForce,
            direction.stepY * gustForce,
            direction.stepZ * gustForce,
          ),
        );
      }
    }

    if (entity.getTicksLived() > gustLifetimeTicks) {
      _directions.remove(e.entityId);
      entity.remove();
    }
  }
}