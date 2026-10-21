// The `offroad` module: the blocks, the block entity types, the kinetic rules,
// the contraption actor and the per-world mining tick.
//
// Java: `Offroad` (the mod entry point), `index/OffroadBlocks`,
// `index/OffroadBlockEntityTypes`, `index/OffroadEntityTypes`,
// `index/OffroadDataComponents`, `index/OffroadContraptionTypes`,
// `handlers/server/MultiMiningServerManager`, `content/blocks/*/…Actor`,
// `events/OffroadCommonEvents`.
// ignore_for_file: implementation_imports
import 'package:create/create.dart';
import 'package:create/src/contraptions/core/movement.dart' show MovementBehaviours;
import 'package:create/src/contraptions/core/contraption_type.dart' show ContraptionTypes;
import 'package:create/src/kinetics/service.dart' show KineticNetworkService;

import 'config/offroad_config.dart';
import 'content/blocks/borehead_bearing/borehead_bearing_block.dart';
import 'content/blocks/rock_cutting_wheel/rock_cutting_wheel_block.dart';
import 'content/blocks/wheel_mount/wheel_mount_block.dart';
import 'content/contraptions/borehead_contraption.dart';
import 'host/offroad_hooks.dart';
import 'index/offroad_ids.dart';
import 'index/offroad_registry.dart';

/// `BlockBreakingKineticBlockEntity.NEXT_BREAKER_ID`.
int _nextBreakerId = 0;

/// The module.
final class OffroadModule extends CreateModule {
  @override
  String get name => offroadModId;

  @override
  void register(CreateRegistry registry) => registerOffroad(registry);

  @override
  void onLoad(CreateContext ctx) {
    OffroadHooks.store = ctx.blockEntities;
    // `MultiMiningServerManager` takes the next breaker id and negates it
    // (`MultiMiningServerManager.java:33-38`).
    OffroadHooks.breakerIds = () => ++_nextBreakerId;

    final kinetics = ctx.services.find<KineticNetworkService>();
    kinetics?.registerKineticBlock(boreheadBearingKey, boreheadBearingKineticDef);
    kinetics?.registerKineticBlock(rockCuttingWheelKey, rockCuttingWheelKineticDef);
    kinetics?.registerKineticBlock(wheelMountKey, wheelMountKineticDef);
    kinetics?.registerStress(OffroadIds.boreheadBearing, impact: OffroadConfig.boreheadBearingImpact);
    kinetics?.registerStress(OffroadIds.wheelMount, impact: OffroadConfig.wheelMountImpact);

    // `RockCuttingWheelBlock.onRegister(movementBehaviour(new RockCuttingWheelActor()))`.
    MovementBehaviours.register(rockCuttingWheelKey, const RockCuttingWheelActor());

    // `OffroadContraptionTypes.BOREHEAD_CONTRAPON_TYPE` appended to Create's
    // `create:contraption_type` (`BoreheadBearingContraption::new`).
    ContraptionTypes.register(OffroadIds.boreheadContraption, BoreheadBearingContraption.new);

    // `OffroadCommonEvents.physicsTick` + `MultiMiningServerManager.tick`: one
    // server tick of every world.
    ctx.onWorldTick(
      (t) => OffroadHooks.tickWorld(t.world, players: t.playersInWorld),
      label: '$name#mining',
    );
  }

  @override
  void onUnload() {
    OffroadHooks.clear();
    // `ContraptionTypes` has no `unregister`: the key stays registered after an
    // unload, which is harmless (it is only read to build a saved contraption).
  }
}