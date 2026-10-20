// Registration hooks for the actors (movement behaviours) of the contraptions module: harvesters,
// ploughs, rollers, seats, portable storage interfaces, contraption controls, train controls and the
// block behaviours that run on a moving contraption. The contraptions module
// (`contraptions_module.dart`) calls these in its phases.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import '../api/payloads.dart' show HostItemStacks, PayloadBus;
import '../api/wrenchable.dart';
import '../common/common.dart';
import '../common/host_bridge.dart';
import '../core/block_entity.dart';
import '../core/module.dart';
import '../core/registry.dart';
import '../infrastructure/config/create_configs.dart';
import 'actors/actor_runtime.dart';
import 'actors/contraption_controls/contraption_controls_behaviour.dart';
import 'actors/contraption_controls/contraption_controls_block.dart';
import 'actors/harvester/harvester_block.dart';
import 'actors/harvester/harvester_movement_behaviour.dart';
import 'actors/host_interacting_player.dart';
import 'actors/plough/plough_block.dart';
import 'actors/plough/plough_movement_behaviour.dart';
import 'actors/psi/portable_storage_interface_block.dart';
import 'actors/psi/portable_storage_interface_movement.dart';
import 'actors/roller/roller_block.dart';
import 'actors/roller/roller_movement_behaviour.dart';
import 'actors/seat/seat_block.dart';
import 'actors/seat/seat_entity.dart';
import 'actors/seat/seat_interaction_behaviour.dart';
import 'actors/seat/seat_movement_behaviour.dart';
import 'actors/train_controls/controls_behaviour.dart';
import 'actors/train_controls/controls_block.dart';
import 'bearing/stabilized_bearing_movement_behaviour.dart';
import 'behaviours/all_movement_behaviours.dart';
import 'core/movement.dart';
import 'entity/host_contraption_entities.dart';

/// The 16 seats, in `DyeColor` order.
final List<String> seatBlockKeys = [
  for (final c in dyeColors) 'create:${c}_seat',
];

/// Phase 1: blocks, block entity types, items.
void registerActorContent(CreateRegistry registry) {
  // Blocks in the order of the manifest (AllBlocks).
  registry.block(buildPortableStorageInterfaceBlock(fluids: true));
  registry.block(buildContraptionControlsBlock());
  registry.block(buildPortableStorageInterfaceBlock(fluids: false));
  registry.block(buildHarvesterBlock());
  registry.block(buildPloughBlock());
  registry.block(buildRollerBlock());
  registry.block(buildTrainControlsBlock());
  for (final color in dyeColors) {
    registry.block(buildSeatBlock(color));
  }

  registry.blockEntityType(
    const BlockEntityTypeSpec(
      key: HarvesterBlockEntity.type,
      validBlocks: ['create:mechanical_harvester'],
      create: HarvesterBlockEntity.new,
      tickInterval: 0,
    ),
  );
  registry.blockEntityType(
    const BlockEntityTypeSpec(
      key: RollerBlockEntity.type,
      validBlocks: ['create:mechanical_roller'],
      create: RollerBlockEntity.new,
      tickInterval: 1,
    ),
  );
  registry.blockEntityType(
    const BlockEntityTypeSpec(
      key: PortableItemInterfaceBlockEntity.type,
      validBlocks: ['create:portable_storage_interface'],
      create: PortableItemInterfaceBlockEntity.new,
      tickInterval: 1,
    ),
  );
  registry.blockEntityType(
    const BlockEntityTypeSpec(
      key: PortableFluidInterfaceBlockEntity.type,
      validBlocks: ['create:portable_fluid_interface'],
      create: PortableFluidInterfaceBlockEntity.new,
      tickInterval: 1,
    ),
  );
  registry.blockEntityType(
    const BlockEntityTypeSpec(
      key: ContraptionControlsBlockEntity.type,
      validBlocks: ['create:contraption_controls'],
      create: ContraptionControlsBlockEntity.new,
      tickInterval: 1,
    ),
  );

  registry.entityType(seatEntityType);
}

/// Phase 2: the movement behaviour registry and the services.
void loadActorContent(CreateContext ctx) {
  final runtime = ActorRuntime(
    ctx.worlds,
    ctx.blockEntities,
    ctx.services.find<CreateConfigs>(),
    ctx.log,
    itemIds: HostItemStacks.resolverFor(() => ctx.ids),
  );
  ActorRuntime.install(runtime);
  ctx.services.provide<ActorRuntime>(runtime);

  _registerBehaviours();

  final controls = ControlsServerHandler();
  ctx.services.provide<ControlsServerHandler>(controls);

  // `ControlsInputPacket`: the held keys of a driver.
  ctx.services.find<PayloadBus>()?.onServerbound('create:controls_input', (
    player,
    fields,
  ) {
    final rawPos = fields['controlsPos'];
    if (rawPos is! (int, int, int)) return;
    final entityId = fields['contraptionEntityId'];
    if (entityId is! int) return;
    final rawButtons = fields['activatedButtons'];
    final buttons = <int>[
      if (rawButtons is List)
        for (final button in rawButtons)
          if (button is int) button,
    ];
    final world = player.getWorld();
    final worldId = world.getId();
    final entity = controlsEntityAt(worldId, entityId);
    if (entity == null) return;
    if (fields['stopControlling'] == true) {
      entity.stopControlling(rawPos);
      return;
    }
    final interacting = HostInteractingPlayer(player);
    if (!entity.canInteractWithBlock(interacting, rawPos.center, 16)) return;
    controls.receivePressed(
      worldId,
      entity,
      rawPos,
      interacting.uuid,
      buttons,
      fields['press'] == true,
    );
  });

  // `RollerBlockItem.place`: the roller moves on top of the clicked block when the block below it
  // is full on top.
  ctx.host.intercept(Events.playerUseBlock, (server, e) async {
    if (e.cancelled) return e;
    if (await useRollerItem(server, e)) return e.cancel();
    return e;
  });

  // `Contraption.addPassengersToWorld` -> `SeatBlock.sitDown`: when a contraption is placed back
  // into the world, a rider that sat on one of its seats sits on the seat block again.
  ContraptionHostHooks.sitPassenger = (worldId, pos, passenger) {
    final world = ctx.worlds.byId(worldId);
    if (world == null) return false;
    if (!isSeatBlock(world.getBlock(pos: pos.toBlockPos()).name)) return false;
    if (isSeatOccupied(world, pos)) return false;
    // The host handle of the passenger is released when this callback returns; the seating
    // finishes on a later tick, so keep it until then.
    final kept = passenger.keep();
    unawaited(sitDown(world, pos, kept).whenComplete(kept.dispose));
    return true;
  };

  // `ContraptionEntityHooks.leashedMob` (`SeatBlock.getLeashed`) stays uninstalled: the host
  // exposes the `leashed` entity flag but not the leash holder, so a mob cannot be matched to the
  // player leading it.

  // The contraption controls actor tells the core how to apply its filters.
  ActorControlHooks.isDisabledInitially =
      ContraptionControlsMovement.isDisabledInitially;
  ActorControlHooks.filterOf = ContraptionControlsMovement.getFilter;
  ActorControlHooks.isSameFilter = ContraptionControlsMovement.isSameFilter;

  // Per-world state: seat entities that lost their block, and the keys held on train controls.
  ctx.listen(Events.worldTick, (server, e) {
    final world = e.targetWorld;
    final worldId = world.getId();

    for (final entry in SeatEntities.of(worldId).entries.toList()) {
      tickSeat(world, worldId, entry.key, entry.value);
    }

    final players = server.getPlayersInWorld(worldRef: world);
    controls.tick(worldId, (uuid) {
      for (final player in players) {
        if (player.getId().asString == uuid)
          return HostInteractingPlayer(player);
      }
      return null;
    });
  });
  ctx.listen(Events.worldUnload, (server, e) {
    if (e.cancelled) return;
    final worldId = e.targetWorld.getId();
    SeatEntities.forgetWorld(worldId);
    controls.forgetWorld(worldId);
  });
}

/// Phase 3: the server finished loading.
void serverActorContentLoaded(CreateRuntime runtime) {
  final wrench = runtime.services.find<WrenchRegistry>();
  if (wrench == null) return;

  // `AttachedActorBlock.onWrenched` returns FAIL: the wrench does nothing on these blocks.
  const refuse = CallbackWrenchable(onWrenchedOverride: _refuseWrench);
  wrench.registerAll(const [
    'create:mechanical_harvester',
    'create:mechanical_plough',
    'create:mechanical_roller',
  ], refuse);

  // `ControlsBlock` keeps the `IWrenchable` default (rotate / dismantle).
  wrench.registerDefault(const [
    'create:controls',
    'create:contraption_controls',
  ]);
}

/// Plugin unload.
void unloadActorContent() {
  ActorRuntime.uninstall();
  SeatEntities.clear();
  ActorControlHooks.isDisabledInitially = null;
  ActorControlHooks.filterOf = null;
  ActorControlHooks.isSameFilter = null;
  ContraptionHostHooks.sitPassenger = null;
}

Future<WrenchResult> _refuseWrench(WrenchContext c) async => WrenchResult.fail;

void _registerBehaviours() {
  registerAllMovementBehaviours();
  registerAllInteractionBehaviours();

  MovementBehaviours.register(
    'create:mechanical_harvester',
    const HarvesterMovementBehaviour(),
  );
  MovementBehaviours.register(
    'create:mechanical_plough',
    const PloughMovementBehaviour(),
  );
  MovementBehaviours.register(
    'create:mechanical_roller',
    const RollerMovementBehaviour(),
  );

  for (final key in seatBlockKeys) {
    MovementBehaviours.register(key, const SeatMovementBehaviour());
    MovingInteractions.register(key, const SeatInteractionBehaviour());
  }

  MovementBehaviours.register(
    'create:portable_storage_interface',
    const PortableStorageInterfaceMovement(),
  );
  MovementBehaviours.register(
    'create:portable_fluid_interface',
    const PortableStorageInterfaceMovement(),
  );

  MovementBehaviours.register(
    'create:contraption_controls',
    const ContraptionControlsMovement(),
  );
  MovingInteractions.register(
    'create:contraption_controls',
    const ContraptionControlsMovingInteraction(),
  );

  MovementBehaviours.register(
    'create:controls',
    const ControlsMovementBehaviour(),
  );
  MovingInteractions.register(
    'create:controls',
    const ControlsInteractionBehaviour(),
  );

  // `AllBlocks.MECHANICAL_BEARING.onRegister(movementBehaviour(new
  // StabilizedBearingMovementBehaviour()))`.
  MovementBehaviours.register(
    'create:mechanical_bearing',
    const StabilizedBearingMovementBehaviour(),
  );
}
