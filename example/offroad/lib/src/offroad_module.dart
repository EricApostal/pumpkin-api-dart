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
import 'package:create/src/contraptions/core/movement_checks.dart' show BlockMovementChecks;
import 'package:create/src/contraptions/entity/contraption_entity_ticking.dart'
    show ContraptionEntityTicking;
import 'package:create/src/contraptions/entity/host_contraption_entities.dart'
    show ContraptionHostHooks;
import 'package:create/src/kinetics/geometry.dart' show Dir;
import 'package:create/src/kinetics/runtime.dart' show KineticsRuntime;
import 'package:create/src/kinetics/use_records.dart' show UseRecord;
import 'package:pumpkin_api/pumpkin_api.dart' show Events, UuidExt;

import 'config/offroad_config.dart';
import 'content/blocks/borehead_bearing/borehead_bearing_block.dart';
import 'content/blocks/rock_cutting_wheel/rock_cutting_wheel_block.dart';
import 'content/blocks/wheel_mount/wheel_mount_block.dart';
import 'content/contraptions/borehead_contraption.dart';
import 'content/entities/borehead_contraption_entity.dart';
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

    // `BoreheadBearingBlock`/`RockCuttingWheelBlock`/`WheelMountBlock` are `IRotate`s: their
    // connection rules and their stress values go into Create's kinetics state, which this
    // component holds through `installHostedModuleState`. The kinetics *module* is not loaded
    // here, so there is no `KineticNetworkService` to register them through
    // (`installHostedModuleState`'s doc: an addon registers a definition per block in
    // `KineticsRuntime.instance`); registering through the service silently skipped every one
    // of these calls, which left the blocks unconnected and their stress impact at zero.
    if (KineticsRuntime.isLoaded) {
      final kinetics = KineticsRuntime.instance;
      kinetics.blocks.register(boreheadBearingKey, boreheadBearingKineticDef);
      kinetics.blocks.register(rockCuttingWheelKey, rockCuttingWheelKineticDef);
      kinetics.blocks.register(wheelMountKey, wheelMountKineticDef);
      kinetics.stressTable.register(
        OffroadIds.boreheadBearing,
        impact: OffroadConfig.boreheadBearingImpact,
      );
      kinetics.stressTable.register(
        OffroadIds.wheelMount,
        impact: OffroadConfig.wheelMountImpact,
      );
    } else {
      ctx.log.warn(
        "Create's kinetics state is not installed: Offroad's blocks will not turn.",
      );
    }

    // The host's `placed` event carries neither the clicked face nor the sneak state
    // (`block_callbacks.dart`), so a placement correction reads the click from the last
    // block use of the player — the records Create's kinetics module keeps for its own
    // blocks, which this component fills here (`KineticsModule.onLoad`).
    if (KineticsRuntime.isLoaded) {
      final records = KineticsRuntime.instance.useRecords;
      ctx.listen(Events.playerUseBlock, (server, e) async {
        final String itemKey;
        try {
          itemKey = await e.item.getRegistryKey();
        } catch (_) {
          return;
        }
        final face = Dir.fromName(e.face.name);
        if (face == null) return;
        records.put(
          e.player.getId().asString,
          UseRecord(e.blockPos, face, e.sneaking, itemKey, e.cursor),
        );
      });
    }

    // `RockCuttingWheelBlock.onRegister(movementBehaviour(new RockCuttingWheelActor()))`.
    MovementBehaviours.register(rockCuttingWheelKey, const RockCuttingWheelActor());

    // `RockCuttingWheelBlock`'s static block (`RockCuttingWheelBlock.java:12-33`): the wheel
    // is attached towards every direction but its own, and does not support what its face
    // points at. Without these a contraption drags the blocks in front of a wheel into the
    // structure.
    BlockMovementChecks.registerAttachedCheck(rockCuttingWheelAttachedCheck);
    BlockMovementChecks.registerNotSupportiveCheck(rockCuttingWheelNotSupportiveCheck);

    // `OffroadContraptionTypes.BOREHEAD_CONTRAPON_TYPE` appended to Create's
    // `create:contraption_type` (`BoreheadBearingContraption::new`).
    ContraptionTypes.register(OffroadIds.boreheadContraption, BoreheadBearingContraption.new);

    // `OffroadEntityTypes.BOREHEAD_CONTRAPTION_ENTITY`: the contraption entity kind of a
    // borehead (`BoreheadContraptionEntity.create`). Registering it here is what makes the
    // spawn send the entity to the client under this key (instead of
    // `create:stationary_contraption`) and what ticks it.
    ContraptionHostHooks.registerControlledEntity(
      key: OffroadIds.boreheadContraptionEntity,
      type: BoreheadContraptionEntity,
      create: BoreheadContraptionEntity.new,
    );
    ctx.tickContraptionEntityTypes(const [OffroadIds.boreheadContraptionEntity]);

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