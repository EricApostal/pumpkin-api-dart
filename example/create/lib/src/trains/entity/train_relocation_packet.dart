// `TrainRelocationPacket` (serverbound `create:relocate_train`): moves the train the player is
// looking at onto the clicked track (`TrainRelocator.relocate`). On success the clients that track
// a carriage get `create:contraption_relocation`, which resets the relocation timer of the entity.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../../core/module.dart';
import '../manager/create.dart';
import '../manager/global_railway_manager.dart' show RailwayHooks;
import '../station/host_ops.dart' show plainTrainsText, sendOverlay, trainsLang;
import '../support/runtime.dart';
import '../track/bezier_track_point_location.dart';
import '../track/track_host.dart';
import 'carriage_contraption_entity.dart';
import 'train.dart';
import 'train_level.dart';
import 'train_relocator.dart';

/// Installs the handler on the payload bus.
void installTrainRelocationPacket(CreateContext ctx) {
  final bus = ctx.services.find<PayloadBus>();
  bus?.onServerbound('create:relocate_train', (player, fields) {
    final trainId = fields['trainId'] as String?;
    final pos = fields['pos'];
    final lookAngle = fields['lookAngle'];
    final entityId = fields['entityId'];
    if (trainId == null ||
        pos is! Pos ||
        lookAngle is! Vec3 ||
        entityId is! int)
      return;

    final train = Create.RAILWAYS.trains[trainId];
    final world = player.getWorld();
    final worldId = world.getId();
    final entity = _carriageEntity(train, entityId);
    if (train == null || entity == null) {
      Tr.i.log.warn('Could not relocate train $trainId: not present on server');
      return;
    }
    if (entity.trainId != train.id) return;

    final bezier = _bezier(fields['hoveredBezier']);
    final direction = fields['direction'] == true;
    final verifyDistance = TrainSettings.current.maxTrackPlacementLength * 2;

    final playerEntity = player.asEntity();
    final (px, py, pz) = player.getPosition();
    final eye = playerEntity.eyePosition;
    // `Player.isWithinBlockInteractionRange(pos, 64)`: from the eye to the block's AABB, with
    // the block interaction range (4.5 by default) added to the 64.
    final blockRange =
        (playerEntity.asLiving()?.getAttributeValue(attr: Attribute.blockInteractionRange) ?? 4.5) +
        verifyDistance;
    if (_distanceToBlockSqr(eye, pos) >= blockRange * blockRange) {
      Tr.i.log.warn(
        'Could not relocate train ${plainTrainsText(train.name)}: player too far from clicked pos',
      );
      return;
    }
    final entityPos = entity.position;
    final ex = px - entityPos.$1,
        ey = py - entityPos.$2,
        ez = pz - entityPos.$3;
    if (ex * ex + ey * ey + ez * ez > verifyDistance * verifyDistance) {
      Tr.i.log.warn(
        'Could not relocate train ${plainTrainsText(train.name)}: player too far from carriage entity',
      );
      return;
    }

    final level = HostTrackLevel(world, Tr.i.store);
    final trainLevel = RailwayHooks.trainLevelById?.call(worldId);
    if (!TrainRelocator.relocate(
      train,
      level,
      trainLevel,
      pos,
      bezier,
      direction,
      lookAngle,
      false,
    )) {
      Tr.i.log.warn(
        'Could not relocate train ${plainTrainsText(train.name)}: relocation failed server-side',
      );
      return;
    }

    sendOverlay(player, trainsLang('create.train.relocate.success'), color: 'a');
    for (final carriage in train.carriages) {
      carriage.forEachPresentEntity((e) {
        e.nonDamageTicks = 10;
        bus.sendToTrackingAt(
          'create:contraption_relocation',
          e.dimension,
          posContaining(e.position),
          {'entityId': e.id},
        );
      });
    }
  });
}

/// `AABB.distanceToSqr(Vec3)` of the box of block [pos].
double _distanceToBlockSqr(Vec3 point, Pos pos) {
  final dx = math.max(0.0, math.max(pos.x - point.$1, point.$1 - (pos.x + 1)));
  final dy = math.max(0.0, math.max(pos.y - point.$2, point.$2 - (pos.y + 1)));
  final dz = math.max(0.0, math.max(pos.z - point.$3, point.$3 - (pos.z + 1)));
  return dx * dx + dy * dy + dz * dz;
}

/// The carriage entity of [train] with [entityId], if it is present.
CarriageContraptionEntity? _carriageEntity(Train? train, int entityId) {
  if (train == null) return null;
  for (final carriage in train.carriages) {
    final entity = carriage.anyAvailableEntity();
    if (entity != null && entity.id == entityId) return entity;
  }
  return null;
}

BezierTrackPointLocation? _bezier(Object? value) {
  if (value is! Map) return null;
  final pos = value['curveTarget'];
  final segment = value['segment'];
  if (pos is! Pos || segment is! int) return null;
  return BezierTrackPointLocation(pos, segment);
}
