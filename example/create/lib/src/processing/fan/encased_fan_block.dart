// `EncasedFanBlock` / `EncasedFanBlockEntity`: the kinetic fan. It turns its rotation into an
// [AirCurrent] that pushes or pulls entities and processes items. Ported from
// `content/kinetics/fan/EncasedFanBlock.java` and `EncasedFanBlockEntity.java`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/advancements.dart';
import '../../common/common.dart' hide pos;
import '../../common/host_bridge.dart';
import '../../core/blocks.dart';
import '../support/kinetics_bridge.dart';
import '../processing_runtime.dart';
import 'air_current.dart';

/// `EncasedFanBlockEntity`.
final class EncasedFanBlockEntity extends KineticBlockEntity
    implements IAirCurrentSource {
  /// `registerAwardables(behaviours, ENCASED_FAN, FAN_PROCESSING)`
  /// (`EncasedFanBlockEntity.java:39`): the fan awards its owner.
  late final AdvancementBehaviour advancements;

  EncasedFanBlockEntity(super.worldId, super.pos) {
    advancements = addBehaviour(
      AdvancementBehaviour(
        [AllAdvancements.encasedFan, AllAdvancements.fanProcessing],
        () => ProcessingRuntime.instance.advancements,
      ),
    );
    airCurrent = AirCurrent(this);
  }

  /// Awards `FAN_PROCESSING` for a current that processed something, on behalf of the current
  /// (`fan.award(AllAdvancements.FAN_PROCESSING)` in `AirCurrent.java:126,157`).
  @override
  void onFanProcessed() {
    unawaited(advancements.awardPlayer(AllAdvancements.fanProcessing));
  }

  /// `airCurrent`.
  @override
  late final AirCurrent airCurrent;

  /// `airCurrentUpdateCooldown`.
  int airCurrentUpdateCooldown = 0;

  /// `entitySearchCooldown`.
  int entitySearchCooldown = 0;

  /// `updateAirFlow`.
  bool updateAirFlow = true;

  @override
  World? get airCurrentWorld => world;

  @override
  String get airCurrentWorldId => worldId;

  @override
  Pos get airCurrentPos => pos.toPos();

  @override
  Dir get airflowOriginSide => blockState.dirOf('facing') ?? Dir.north;

  @override
  Dir? get airFlowDirection {
    final s = speed;
    if (s == 0) return null;
    final facing = airflowOriginSide;
    return convertToDirection(s, facing) > 0 ? facing : facing.opposite;
  }

  @override
  double get maxDistance {
    final speedAbs = speed.abs();
    final cfg = ProcessingRuntime.isLoaded
        ? ProcessingRuntime.instance.configs?.server.kinetics
        : null;
    final argmax = (cfg?.fanRotationArgmax.value ?? 256).toDouble();
    final push = (cfg?.fanPushDistance.value ?? 20).toDouble();
    final pull = (cfg?.fanPullDistance.value ?? 20).toDouble();
    final factor = math.min(speedAbs / argmax, 1.0);
    final pushDistance = 3 + (push - 3) * factor;
    final pullDistance = 3 + (pull - 3) * factor;
    return speed > 0 ? pushDistance : pullDistance;
  }

  @override
  bool get isSourceRemoved => removed;

  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    updateAirFlow = true;
  }

  /// `blockInFrontChanged`.
  void blockInFrontChanged() => updateAirFlow = true;

  @override
  void tick() {
    super.tick();

    final cfg = ProcessingRuntime.isLoaded
        ? ProcessingRuntime.instance.configs?.server.kinetics
        : null;
    final checkRate = cfg?.fanBlockCheckRate.value ?? 30;
    if (airCurrentUpdateCooldown-- <= 0) {
      airCurrentUpdateCooldown = checkRate;
      updateAirFlow = true;
    }

    if (updateAirFlow) {
      updateAirFlow = false;
      airCurrent.rebuild();
      // `if (airCurrent.maxDistance > 0) award(ENCASED_FAN)`
      // (`EncasedFanBlockEntity.java:137`): the fan blows.
      if (airCurrent.maxDistance > 0) {
        unawaited(advancements.awardPlayer(AllAdvancements.encasedFan));
      }
      sendData();
    }

    if (speed == 0) return;

    if (entitySearchCooldown-- <= 0) {
      entitySearchCooldown = 5;
      airCurrent.findEntities();
    }

    airCurrent.tick();
  }
}

/// `EncasedFanBlock.getStateForPlacement`: chutes take priority, then neighbouring shafts.
KState encasedFanPlacement(PlacementContext ctx) {
  final face = ctx.clickedFace;
  final placedOn = ctx.stateAt(ctx.placedOnPos);
  final placedOnOpposite = ctx.stateAt(ctx.pos.relative(face));

  if (_isChute(placedOn)) {
    return KState('create:encased_fan', {'facing': face.opposite.name});
  }
  if (_isChute(placedOnOpposite)) {
    return KState('create:encased_fan', {'facing': face.name});
  }

  Dir? preferred;
  for (final side in Dir.values) {
    final state = ctx.stateAt(ctx.pos.relative(side));
    final def = ctx.blocks.defFor(state);
    if (def == null || !def.hasShaftTowards(state, side.opposite)) continue;
    if (preferred != null && preferred.axis != side.axis) {
      preferred = null;
      break;
    }
    preferred = side;
  }

  final facing = preferred ?? ctx.nearestLooking;
  final result = (ctx.hasPlayer && ctx.sneaking) ? facing : facing.opposite;
  return KState('create:encased_fan', {'facing': result.name});
}

bool _isChute(KState state) =>
    state.isCreate('chute') || state.isCreate('smart_chute');

/// The block and block entity type of the encased fan.
KineticBlockSpec encasedFanSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'encased_fan',
    blockEntityType: 'create:encased_fan',
    placement: const [PlacementRule.lookingDirection('facing')],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      neighbor: (c, e) {
        c.beOf<EncasedFanBlockEntity>()?.blockInFrontChanged();
      },
      afterPlaced: (c, e) {
        c.beOf<EncasedFanBlockEntity>()?.blockInFrontChanged();
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const FacingBlockDef(shaftAtFront: false),
    placement: (ctx, placed, use, world) => encasedFanPlacement(ctx),
  );
  return spec;
}
