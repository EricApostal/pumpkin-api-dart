// Registration hooks for the actuator content of the contraptions module: bearings, pistons,
// pulleys, gantries, elevators, minecart contraptions, chassis, super glue, mounted contraptions,
// the wrench and the contraption data. The contraptions module (`contraptions_module.dart`) calls
// these in its phases; the actuator area fills them in.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart' show HostBlockGetter;
import '../api/infra.dart' show AssemblyExceptionHooks, AssemblyExceptionInfo;
import '../api/payloads.dart' show PayloadBus;
import '../api/wrenchable.dart';
import '../common/common.dart';
import '../common/host_bridge.dart' show PosToHost;
import '../common/vec_helper.dart' show VecHelper;
import '../conveyance/belt/belt_geometry.dart' show nextSegmentPosition;
import '../conveyance/chain/chain_conveyor_block_entity.dart'
    show ChainConveyorBlockEntity;
import '../core/block_entity.dart';
import '../core/module.dart';
import '../core/registry.dart';
import '../infrastructure/config/create_configs.dart';
import '../kinetics/api.dart'
    show
        KineticNetworkService,
        FacingBlockDef,
        DirectionalAxisBlockDef,
        AxisBlockDef,
        KineticBlockDef,
        KState,
        KAxis,
        Dir;
import 'bearing/bearing_block_entities.dart';
import 'bearing/bearing_blocks.dart';
import 'bearing/bearing_contraptions.dart';
import 'bearing/sail.dart';
import 'blocks/actuator_contract.dart';
import 'blocks/actuator_runtime.dart';
import 'chassis/chassis_block_entity.dart';
import 'chassis/chassis_blocks.dart';
import 'chassis/sticker_block_entity.dart';
import 'core/movement_checks.dart';
import 'core/contraption.dart' show ContraptionMovementHooks;
import 'core/structure_info.dart';
import 'core/contraption_type.dart';
import 'elevator/elevator_blocks.dart';
import 'elevator/elevator_column.dart';
import 'elevator/elevator_contact_block_entity.dart';
import 'elevator/elevator_contraption.dart';
import 'elevator/elevator_packets.dart';
import 'elevator/elevator_pulley_block_entity.dart';
import 'entity/contraption_entity.dart';
import 'entity/host_contraption_entities.dart' show ContraptionHostHooks;
import 'entity/oriented_contraption_entity.dart'
    show MinecartStallSink, OrientedContraptionHooks;
import 'gantry/gantry_carriage.dart';
import 'gantry/gantry_contraption.dart';
import 'glue/super_glue_handler.dart';
import 'glue/super_glue_item.dart';
import 'glue/super_glue_packets.dart';
import 'minecart/capability/capability_minecart_controller.dart';
import 'minecart/capability/minecart_controller.dart';
import 'minecart/coupling_handler.dart';
import 'minecart/minecart_access.dart';
import 'minecart/minecart_coupling_item.dart';
import 'minecart/minecart_packets.dart';
import 'mounted/cart_assembler_block_entity.dart';
import 'mounted/minecart_contraption_item.dart';
import 'mounted/mounted_blocks.dart';
import 'mounted/mounted_contraption.dart';
import 'piston/linear_actuator_block_entity.dart';
import 'piston/piston_blocks.dart';
import 'piston/piston_contraption.dart';
import 'pulley/pulley_block_entity.dart';
import 'pulley/pulley_blocks.dart';
import 'pulley/pulley_contraption.dart';
import 'wrench/radial_wrench_handler.dart';

/// Phase 1: blocks, block entity types, items, entity types.
void registerActuatorContent(CreateRegistry registry) {
  for (final block in [
    ...buildBearingBlocks(),
    ...buildSails(),
    ...buildPistonBlocks(),
    ...buildPulleyBlocks(),
    ...buildGantryBlocks(),
    ...buildElevatorBlocks(),
    ...buildMountedBlocks(),
    ...buildChassisBlocks(),
  ]) {
    registry.block(block);
  }

  // Block entity types (keys equal the Java registry names).
  void type<T extends CreateBlockEntity>(
    String key,
    List<String> blocks,
    T Function(String worldId, BlockPos pos) create,
  ) {
    if (registry.blockEntityTypes.contains('create:$key')) return;
    registry.blockEntityType(
      BlockEntityTypeSpec(
        key: 'create:$key',
        validBlocks: [for (final b in blocks) 'create:$b'],
        create: create,
        tickInterval: 1,
      ),
    );
  }

  type('mechanical_bearing', [
    'mechanical_bearing',
  ], MechanicalBearingBlockEntity.new);
  type('windmill_bearing', [
    'windmill_bearing',
  ], WindmillBearingBlockEntity.new);
  type('clockwork_bearing', [
    'clockwork_bearing',
  ], ClockworkBearingBlockEntity.new);
  type('mechanical_piston', [
    'mechanical_piston',
    'sticky_mechanical_piston',
  ], MechanicalPistonBlockEntity.new);
  type('rope_pulley', ['rope_pulley'], PulleyBlockEntity.new);
  type('elevator_pulley', ['elevator_pulley'], ElevatorPulleyBlockEntity.new);
  type('elevator_contact', [
    'elevator_contact',
  ], ElevatorContactBlockEntity.new);
  type('gantry_pinion', ['gantry_carriage'], GantryCarriageBlockEntity.new);
  type('cart_assembler', ['cart_assembler'], CartAssemblerBlockEntity.new);
  type('chassis', [
    'radial_chassis',
    'linear_chassis',
    'secondary_linear_chassis',
  ], ChassisBlockEntity.new);
  type('sticker', ['sticker'], StickerBlockEntity.new);

  // Items whose block is not the item's block (the white sail item places every dyed sail) are
  // linked in `loadActuatorContent`.
  registry.item(superGlueRegistration());
  registry.item(minecartCouplingItem());
  for (final item in minecartContraptionItemRegistrations()) {
    registry.item(item);
  }

  // Entities.
  void entity(String key, double width, double height, {bool saveable = true}) {
    if (registry.entityTypes.contains('create:$key')) return;
    registry.entityType(
      EntityTypeSpec(
        key: 'create:$key',
        width: width,
        height: height,
        category: EntityCategory.misc,
        trackingRange: 10,
        updateInterval: 3,
        fireImmune: true,
        saveable: saveable,
      ),
    );
  }

  entity('super_glue', 0.6, 1.8, saveable: false);

  // Contraption kinds, so a saved contraption is read back as the right subclass.
  ContraptionTypes.registerAll({
    'create:bearing': () => BearingContraption(),
    'create:clockwork': () => ClockworkContraption(),
    'create:stabilized': () => StabilizedContraption(),
    'create:piston': () => PistonContraption(),
    'create:pulley': () => PulleyContraption(),
    'create:gantry': () => GantryContraption(),
    'create:elevator': () => ElevatorContraption(),
    'create:mounted': () => MountedContraption(),
  });
}

/// Phase 2: services, event subscriptions, payload handlers.
void loadActuatorContent(CreateContext ctx) {
  final configs = ctx.services.find<CreateConfigs>();
  ActuatorRuntime(
    settings: configs == null
        ? DefaultContraptionSettings()
        : ConfigsContraptionSettings(configs),
    store: ctx.blockEntities,
    worlds: ctx.worlds,
    log: ctx.log,
    configs: configs,
  );
  // The constructor installs the runtime the block entities read.

  // The mounted and stabilized contraptions answer the oriented entity's questions about their
  // rotation mode and coupling.
  OrientedContraptionHooks.rotationLock = (c) =>
      c is MountedContraption && c.rotationLocked;
  OrientedContraptionHooks.pauseWhileRotating = (c) =>
      c is MountedContraption && c.rotationPaused;
  OrientedContraptionHooks.stabilizedFacing = (c) =>
      c is StabilizedContraption ? c.facing : null;
  OrientedContraptionHooks.coupledPositions = _coupledCartPositions;
  OrientedContraptionHooks.addExtraInventories = (c, riding) {
    if (c is MountedContraption) c.addExtraInventories(riding);
  };
  // `OrientedContraptionHooks.powerFurnace` stays uninstalled: the host exposes neither the
  // fuel of a furnace minecart nor a way to set it, so a cart is not refuelled from the cargo.
  // `MountedContraptionHooks.externalInventory` stays uninstalled for the same reason: the host
  // has no container view of an entity, so the contents of a chest or hopper minecart do not
  // join the contraption inventory.

  // `riding.getData(MINECART_CONTROLLER)`: a cart that has a controller takes its stall from the
  // contraption; without this the contraption and the controller each stop the cart.
  OrientedContraptionHooks.minecartControllerOf = (vehicle) {
    final controller = CapabilityMinecartController.byUuid(
      vehicle.worldId,
      vehicle.uuid,
    );
    return controller == null ? null : _ControllerStallSink(controller);
  };

  // `MinecartSim2020.getRailVec`: the cart turns along its rail, not along its motion.
  OrientedContraptionHooks.projectOnRail = (vehicle, motion) {
    final world = ctx.worlds.byId(vehicle.worldId);
    if (world == null) return null;
    final cart = HostMinecartWorld(world, ctx.blockEntities).byId(
      vehicle.entityId,
    );
    final shape = cart?.railShape;
    if (shape == null) return null;
    return VecHelper.project(motion, railVec(shape));
  };

  // `Contraption.moveBlock`: a windmill bearing inside a moved structure lets go first.
  ContraptionHostHooks.disassembleWindmillBearing = (worldId, pos) {
    final be = ctx.blockEntities.at(worldId, pos.toBlockPos());
    if (be is WindmillBearingBlockEntity) be.disassembleForMovement();
  };

  // `Contraption.moveBlock` -> `ChainConveyorBlockEntity.notifyConnectedToValidate()`: a
  // conveyor moved by a contraption must revalidate its chained neighbours, or a stale
  // connection keeps routing packages to a conveyor that is no longer there.
  ContraptionHostHooks.notifyChainConveyor = (worldId, pos) {
    final be = ctx.blockEntities.at(worldId, pos.toBlockPos());
    if (be is ChainConveyorBlockEntity) be.notifyConnectedToValidate();
  };

  // `Contraption.moveChassis`: the chassis block entity's connected group and its range.
  ContraptionMovementHooks.addAttachedChasses = (level, pos, frontier, visited) {
    final be = ctx.blockEntities.at(level.worldId, pos.toBlockPos());
    if (be is ChassisBlockEntity) be.addAttachedChasses(frontier, visited);
  };
  ContraptionMovementHooks.chassisIncludedPositions = (level, pos, direction) {
    final be = ctx.blockEntities.at(level.worldId, pos.toBlockPos());
    return be is ChassisBlockEntity
        ? be.getIncludedBlockPositions(direction)
        : null;
  };
  // `Contraption.moveBelt`: slopes and vertical belts; the core fallback is straight only.
  ContraptionMovementHooks.beltNextSegment = nextSegmentPosition;

  // Kinetic connection rules of the actuators.
  final kinetics = ctx.services.find<KineticNetworkService>();
  if (kinetics != null) {
    for (final key in bearingBlocks) {
      kinetics.registerKineticBlock(
        key,
        const FacingBlockDef(shaftAtFront: false),
      );
    }
    // `MechanicalPistonBlock extends DirectionalAxisKineticBlock`: the shaft socket is on the
    // sides (`getRotationAxis`), not behind the piston.
    kinetics.registerKineticBlock(
      'create:mechanical_piston',
      const DirectionalAxisBlockDef(),
    );
    kinetics.registerKineticBlock(
      'create:sticky_mechanical_piston',
      const DirectionalAxisBlockDef(),
    );
    // `PulleyBlock extends HorizontalAxisKineticBlock`: the shaft runs along the `axis`
    // property, through both sides.
    kinetics.registerKineticBlock(
      'create:rope_pulley',
      const AxisBlockDef(),
    );
    // `GantryCarriageBlock extends DirectionalAxisKineticBlock`: the pinion's shaft runs on the
    // axis perpendicular to the facing.
    kinetics.registerKineticBlock(
      'create:gantry_carriage',
      const DirectionalAxisBlockDef(),
    );
    // `ElevatorPulleyBlock.getRotationAxis`: the facing turned a quarter, shaft on both sides.
    kinetics.registerKineticBlock(
      'create:elevator_pulley',
      const _ElevatorPulleyDef(),
    );
  }

  // The white sail item places every dyed sail block (`BlankSailBlockItem.registerBlocks`).
  for (final key in dyedSailKeys) {
    try {
      BlockRegistries.host.setBlockItem(whiteSail, key);
    } on BlockRegistryException catch (e) {
      ctx.log.warn('Could not link the sail item to $key: ${e.message}');
    }
  }

  // Payload handlers.
  final bus = ctx.services.find<PayloadBus>();
  if (bus != null) {
    bindGluePackets(bus);
    bindElevatorPackets(bus);
    bindMinecartPackets(bus);
    bus.onServerbound('create:radial_wrench_menu_submit', (player, fields) {
      final blockPos = fields['blockPos'] as (int, int, int);
      final stateId = fields['newState'] as int;
      final state = HostBlockGetter.stateOfId(stateId);
      unawaited(
        handleRadialWrenchSubmit(
          player,
          kinetics,
          ctx.services.find<WrenchRegistry>(),
          blockPos,
          state,
        ),
      );
    });
  }

  // The coupling chain and the contraption disassembly the minecart code asks for.
  CouplingChain.next = nextInCouplingChain;
  ContraptionDisassembly.disassemble = (entity) {
    if (entity is AbstractContraptionEntity) {
      unawaited(entity.disassemble());
    }
  };

  // Off-hand glue on block placement.
  ctx.listen(Events.blockPlace, (server, e) async {
    if (e.cancelled) return;
    await onBlockPlaced(server, e);
  });

  // A cart assembler only moves with a cart on it (`MountedContraption.movementAllowed`).
  if (!_registeredCartAssemblerCheck) {
    _registeredCartAssemblerCheck = true;
    BlockMovementChecks.registerMovementAllowedCheck((state, level, pos) {
      if (state.key != cartAssemblerKey) return CheckResult.pass;
      final carts = level.minecartsAt(pos);
      return carts.any((c) => c.canAssemble)
          ? CheckResult.success
          : CheckResult.fail;
    });
  }

  // Minecart contraption items: placing one on a rail, picking one up with the wrench, and the
  // coupling item on a cart.
  ctx.host.intercept(Events.playerUseBlock, (server, e) async {
    if (e.cancelled) return e;
    if (await useMinecartContraptionItem(server, e)) return e.cancel();
    if (await useCartAssemblerItem(server, e)) return e.cancel();
    return e;
  });
  ctx.host.intercept(Events.playerInteractEntity, (server, e) async {
    if (e.cancelled) return e;
    if (e.action != EntityInteractionAction.interact) return e;

    if (await onMinecartInteract(server, e)) return e.cancel();

    final world = e.player.getWorld();
    final worldId = world.getId();
    final target = world.getEntityById(id: e.entityId);
    if (target == null) return e;

    // `entity instanceof AbstractContraptionEntity -> entity.getVehicle()`.
    var cart = target;
    if (ActuatorHosts.entities?.entityById(worldId, e.entityId) != null) {
      cart = target.getVehicle() ?? target;
    }

    if ((await heldItemKey(e.player)) != 'create:wrench') return e;
    return await tryPickUpMinecartContraption(e.player, world, cart)
        ? e.cancel()
        : e;
  });

  // The coupling physics and the minecart controller update.
  ctx.listen(Events.worldTick, (server, e) async {
    CapabilityMinecartController.tick(
      HostMinecartWorld(e.targetWorld, ctx.blockEntities),
    );
    await tickPendingRides();
  });
  ctx.listen(Events.worldUnload, (server, e) {
    if (e.cancelled) return;
    final worldId = e.targetWorld.getId();
    ElevatorColumn.forgetWorld(worldId);
    CapabilityMinecartController.forgetWorld(worldId);
    clearPendingRides();
  });

  ctx.services.provide<AssemblyExceptionHooks>(_AssemblyExceptions());
}

/// Phase 3: the server finished loading.
void serverActuatorContentLoaded(CreateRuntime runtime) {
  final bus = runtime.services.find<PayloadBus>();
  if (bus != null) ActuatorHosts.payloadBus = bus;

  // Wrench: the bearings disassemble on a wrench click, the sails rotate, the elevator contact
  // turns back into a redstone contact, the cart assembler rotates and turns back into a rail.
  // The registry is provided by the equipment module, which loads after this one in phase 2, so
  // it only exists here (`onServerLoaded`), like the kinetic wrench registrations.
  final wrench = runtime.services.find<WrenchRegistry>();
  if (wrench == null) {
    runtime.log.warn(
      'No wrench registry: the bearings, sails, pistons, pulley and gantry carriage cannot be wrenched.',
    );
    return;
  }
  registerActuatorWrenchables(wrench, () => runtime.blockEntities);
}

/// Registers the actuator blocks in [wrench] (`IWrenchable`). Called from `onServerLoaded`, where
/// the equipment module's registry exists; kept separate so it can be tested without a server.
void registerActuatorWrenchables(WrenchRegistry wrench, BlockEntityStore Function() blockEntities) {
  for (final key in bearingBlocks) {
    wrench.register(
      key,
      bearingWrenchable(
        disassemble: (c) async {
          final be = blockEntities().at(c.world.getId(), c.pos);
          if (be is MechanicalBearingBlockEntity) be.disassemble();
          if (be is ClockworkBearingBlockEntity) be.disassemble();
        },
      ),
    );
  }
  wrench.registerDefault(['create:sail_frame', ...dyedSailKeys]);
  wrench.register('create:elevator_contact', elevatorContactWrenchable());
  wrench.register('create:cart_assembler', cartAssemblerWrenchable());
  // `MechanicalPistonBlock.onWrenched`: rotate only while retracted.
  wrench.register('create:mechanical_piston', pistonWrenchable());
  wrench.register('create:sticky_mechanical_piston', pistonWrenchable());
  // `KineticBlock`/`WrenchableDirectionalBlock` keep the `IWrenchable` default (rotate,
  // sneak-dismantle): the pulley, the carriage, the piston head and the extension pole.
  wrench.registerDefault([
    'create:rope_pulley',
    'create:gantry_carriage',
    'create:mechanical_piston_head',
    'create:piston_extension_pole',
  ]);
}

/// Plugin unload.
void unloadActuatorContent() {
  OrientedContraptionHooks.rotationLock = null;
  OrientedContraptionHooks.pauseWhileRotating = null;
  OrientedContraptionHooks.stabilizedFacing = null;
  OrientedContraptionHooks.coupledPositions = null;
  OrientedContraptionHooks.addExtraInventories = null;
  OrientedContraptionHooks.minecartControllerOf = null;
  OrientedContraptionHooks.projectOnRail = null;
  ContraptionHostHooks.disassembleWindmillBearing = null;
  ContraptionMovementHooks.addAttachedChasses = null;
  ContraptionMovementHooks.chassisIncludedPositions = null;
  ContraptionMovementHooks.beltNextSegment = null;
  CouplingChain.next = null;
  ContraptionDisassembly.disassemble = null;
  ElevatorColumn.clear();
  CapabilityMinecartController.clear();
  clearPendingRides();
  ActuatorRuntime.maybe?.dispose();
}

/// `OrientedContraptionEntity.getCoupledCartsIfPresent`: the positions of the two coupled carts.
(Vec3, Vec3)? _coupledCartPositions(
  ContraptionPassengerRef vehicle,
  String couplingId,
) {
  if (couplingId.isEmpty) return null;
  // The passenger keeps its world id: a host `Entity` handle is only valid inside the callback
  // that received it.
  final worldId = vehicle.worldId;

  final controller = CapabilityMinecartController.byUuid(worldId, couplingId);
  if (controller == null || !controller.isPresent) return null;
  final otherId = controller.getCoupledCart(true);
  if (otherId == null) return null;
  final other = CapabilityMinecartController.byUuid(worldId, otherId);
  if (other == null || !other.isPresent) return null;

  final first = controller.cart?.position;
  final second = other.cart?.position;
  if (first == null || second == null) return null;
  return (first, second);
}

/// The stall part of a `MinecartController`, as the oriented contraption entity sees it.
final class _ControllerStallSink implements MinecartStallSink {
  final MinecartController controller;

  const _ControllerStallSink(this.controller);

  @override
  bool get isPresent => controller.isPresent;

  @override
  void setStalledExternally(bool stall) =>
      controller.setStalledExternally(stall);
}

/// `create:<color>_sail` keys.
final List<String> dyedSailKeys = [for (final c in sailColors) dyedSail(c)];

/// The cart assembler check is registered once; `BlockMovementChecks` has no removal.
bool _registeredCartAssemblerCheck = false;

/// `ElevatorPulleyBlock.getRotationAxis` / `hasShaftTowards`: the shaft runs along the facing's
/// clockwise axis and sticks out of both sides.
final class _ElevatorPulleyDef extends KineticBlockDef {
  const _ElevatorPulleyDef();

  @override
  KAxis rotationAxis(KState state) =>
      (state.dirOf('facing') ?? Dir.north).clockWise(KAxis.y).axis;

  @override
  bool hasShaftTowards(KState state, Dir face) =>
      face.axis == rotationAxis(state);
}

/// `AssemblyExceptionHooks` for `/create highlight`: the last exception of the actuator block
/// entity at a position.
final class _AssemblyExceptions implements AssemblyExceptionHooks {
  @override
  AssemblyExceptionInfo? lastAssemblyException(World world, Pos pos) {
    final runtime = ActuatorRuntime.maybe;
    if (runtime == null) return null;
    final be = runtime.store.at(
      world.getId(),
      BlockPos(x: pos.$1, y: pos.$2, z: pos.$3),
    );
    if (be is! AssemblyExceptionHolding) return null;
    final exception = (be as AssemblyExceptionHolding).lastAssemblyException;
    if (exception == null) return null;
    return AssemblyExceptionInfo(
      exception.toComponentJson(),
      exception.position,
    );
  }
}
