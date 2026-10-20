// `CartAssemblerBlockEntity`: assembles the structure above a cart into a mounted contraption when
// a cart passes over it, and takes it apart on an activator or unpowered controller rail.
//
// Java: `content/contraptions/mounted/CartAssemblerBlockEntity`.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/value_settings.dart';
import '../../common/common.dart';
import '../../core/block_entity.dart';
import '../../kinetics/api.dart' show ScrollValueBehaviour;
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_nbt.dart';
import '../blocks/actuator_runtime.dart';
import '../core/level.dart';
import '../core/structure_info.dart';
import '../minecart/capability/capability_minecart_controller.dart';
import '../minecart/coupling_handler.dart';
import '../entity/oriented_contraption_entity.dart';
import 'minecart_contraption_item.dart' show attachContraptionToCart;
import '../minecart/minecart_access.dart';
import 'cart_assemble_rail_type.dart';
import 'mounted_contraption.dart';

/// The assembly cooldown in ticks.
const int cartAssemblerCooldown = 8;

final class CartAssemblerBlockEntity extends CreateBlockEntity
    implements ValueSettingsHost, AssemblyExceptionHolding {
  CartAssemblerBlockEntity(super.worldId, super.pos) {
    // `addBehaviours`: added at construction so `read` restores the saved `ScrollValue`.
    _movementMode = addBehaviour(ScrollValueBehaviour().between(0, 2));
  }

  int ticksSinceMinecartUpdate = cartAssemblerCooldown;
  AssemblyException? lastException;
  MinecartRef? cartToAssemble;
  ScrollValueBehaviour? _movementMode;

  Pos get localPos => (this.pos.x, this.pos.y, this.pos.z);

  CartMovementMode get movementMode =>
      CartMovementMode.values[(_movementMode?.value ?? 0).clamp(0, 2)];

  BState get stateNow =>
      HostBlockGetter.stateOfId(world!.getBlockStateId(pos: this.pos));

  @override
  void tick() {
    super.tick();
    if (ticksSinceMinecartUpdate < cartAssemblerCooldown) {
      ticksSinceMinecartUpdate++;
    }
    final cart = cartToAssemble;
    cartToAssemble = null;
    if (cart != null) tryAssemble(cart);
  }

  /// `queueAssembly(cart)`: the next tick handles the cart.
  void queueAssembly(MinecartRef cart) => cartToAssemble = cart;

  /// `tryAssemble`.
  Future<void> tryAssemble(MinecartRef cart) async {
    if (!isMinecartUpdateValid()) return;
    ticksSinceMinecartUpdate = 0;

    final state = stateNow;
    if (state.key != cartAssemblerKey) return;
    final access = HostMinecartWorld(
      world!,
      ActuatorRuntime.instance.store,
    ).byId(cart.id);
    final action = CartAssemblerAction.forCart(
      state,
      hasPassengers: access?.isVehicle ?? false,
    );
    if (action.shouldAssemble) await assemble(cart);
    if (action.shouldDisassemble) await disassemble(cart);

    if (action == CartAssemblerAction.assembleAccelerate ||
        action == CartAssemblerAction.assembleAccelerateDirectional) {
      final level = HostMinecartWorld(world!, ActuatorRuntime.instance.store);
      final cartAccess = level.byId(cart.id);
      if (cartAccess == null) return;
      final speed = cartAccess.maxSpeed;
      final axis = state['shape'] == 'east_west' ? Axis.x : Axis.z;
      var facing = Direction.fromAxisAndDirection(axis, AxisDirection.positive);
      if (action == CartAssemblerAction.assembleAccelerate &&
          cartAccess.velocity.length > 1 / 128) {
        for (final d in Direction.fromAxisAndDirection(
          axis,
          AxisDirection.positive,
        ).axis.directions) {
          final neighbour = localPos.relative(d);
          if (HostBlockGetter(world!).isCollisionShapeFullBlock(neighbour)) {
            facing = d.opposite;
          }
        }
      } else if (action == CartAssemblerAction.assembleAccelerateDirectional) {
        facing = state.flag('backwards') ? facing.opposite : facing;
      }
      cartAccess.setVelocity(facing.unitVec3 * speed);
    }

    if (action == CartAssemblerAction.disassembleBrake) {
      final cartAccess = HostMinecartWorld(
        world!,
        ActuatorRuntime.instance.store,
      ).byId(cart.id);
      if (cartAccess == null) return;
      final diff = localPos.center - cartAccess.position;
      cartAccess.setVelocity((diff.$1 / 16, 0.0, diff.$3 / 16));
    }
  }

  bool isMinecartUpdateValid() =>
      ticksSinceMinecartUpdate >= cartAssemblerCooldown;

  /// `assemble`.
  Future<void> assemble(MinecartRef cartRef) async {
    final level = ActuatorHosts.levelOf(worldId);
    final factory = ActuatorHosts.entities;
    if (level == null || factory == null) return;

    final controller = CapabilityMinecartController.get(
      HostMinecartWorld(world!, ActuatorRuntime.instance.store),
      cartRef.uuid,
    );
    if (controller.isCoupledThroughContraption) {
      return;
    }

    final minecartLevel = HostMinecartWorld(
      world!,
      ActuatorRuntime.instance.store,
    );
    final cartAccess = minecartLevel.byId(cartRef.id);
    // `if (!cart.getPassengers().isEmpty()) return;`
    if (cartAccess == null || cartAccess.isVehicle) {
      return;
    }

    final contraption = MountedContraption(movementMode);
    try {
      final ok = await contraption.assemble(level, localPos);
      if (!ok) {
        return;
      }
      lastException = null;
      sendData();
    } on AssemblyException catch (e) {
      lastException = e;
      sendData();
      return;
    }

    final connected = contraption.connectedCart;
    final couplingFound = connected != null;
    // `CartAssemblerBlock.getHorizontalDirection`: the rail shape turned by `backwards`.
    final pointing = stateNow['shape'] == 'east_west'
        ? Direction.west
        : Direction.north;
    var initialOrientation = stateNow.flag('backwards')
        ? pointing.opposite
        : pointing;

    if (couplingFound) {
      // The cart moves onto the assembler before the coupling is made.
      level.moveMinecart(cartRef, (
        localPos.$1 + .5,
        localPos.$2.toDouble(),
        localPos.$3 + .5,
      ));
      if (!await tryToCoupleCarts(
        null,
        minecartLevel,
        cartRef.id,
        connected.id,
      )) {
        return;
      }
      final cartPos =
          minecartLevel.byId(cartRef.id)?.position ?? cartRef.position;
      final diff = connected.position - cartPos;
      initialOrientation = Direction.fromYRot(atan2Degrees(diff.$3, diff.$1));
    }

    await contraption.removeBlocksFromWorld(level, posZero);
    contraption.startMoving(level);
    contraption.expandBoundsAroundAxis(Axis.y);

    final entity = factory.createOriented(
      worldId,
      contraption,
      initialOrientation,
    );
    if (couplingFound && entity is OrientedContraptionEntity) {
      entity.couplingId = cartRef.uuid;
    }
    entity.setPos((localPos.$1 + .5, localPos.$2.toDouble(), localPos.$3 + .5));
    factory.spawn(worldId, entity);

    // `entity.startRiding(cart)`: the factory spawns asynchronously, so the passenger is attached
    // on the next world tick.
    final cartEntity = world!.getEntityById(id: cartRef.id);
    if (cartEntity != null) {
      attachContraptionToCart(entity, worldId, cartEntity.getId());
    }
  }

  /// `disassemble`: the cart assembler stops an assembled cart. The contraption entity disassembles
  /// itself when it stops riding (`OrientedContraptionEntity.stopRiding`).
  Future<void> disassemble(MinecartRef cartRef) async {
    final level = HostMinecartWorld(world!, ActuatorRuntime.instance.store);
    final cart = level.byId(cartRef.id);
    if (cart == null || !cart.isVehicle) return;
    final passenger = cart.firstPassengerContraption;
    if (passenger is! OrientedContraptionEntity) return;

    final pointing = stateNow['shape'] == 'east_west'
        ? Direction.west
        : Direction.north;
    final yaw =
        (stateNow.flag('backwards') ? pointing.opposite : pointing).toYRot;

    final couplingId = passenger.couplingId;
    if (couplingId == null) {
      passenger
        ..yaw = yaw
        ..startAtYaw(yaw);
      await _disassembleCart(cart, passenger);
      return;
    }

    // The connected cart must sit on an assembler that disassembles as well.
    final ownController = CapabilityMinecartController.getIfPresent(
      level,
      cart.uuid,
    );
    final otherUuid = ownController?.getCoupledCart(true);
    final other = CapabilityMinecartController.getIfPresent(level, otherUuid);
    final otherCart = other?.cart;
    if (otherCart == null) return;

    final railPos = otherCart.railPos;
    final otherPos =
        railPos ??
        (
          otherCart.position.$1.floor(),
          otherCart.position.$2.floor(),
          otherCart.position.$3.floor(),
        );
    final otherState = level.stateAt(otherPos);
    if (otherState.key != cartAssemblerKey) return;
    if (!CartAssemblerAction.forCart(
      otherState,
      hasPassengers: otherCart.isVehicle,
    ).shouldDisassemble) {
      return;
    }

    passenger
      ..yaw = yaw
      ..startAtYaw(yaw);
    ownController?.decouple();
    await _disassembleCart(cart, passenger);
  }

  /// `disassembleCart`: eject the passengers (the contraption disassembles as it stops riding).
  Future<void> _disassembleCart(
    MinecartAccess cart,
    OrientedContraptionEntity contraption,
  ) async {
    cart.ejectPassengers();
    await contraption.stopRiding();
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    writeAssemblyException(tag, lastException);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    lastException = readAssemblyException(tag);
    super.read(tag, clientPacket: clientPacket);
  }

  @override
  AssemblyException? get lastAssemblyException => lastException;

  @override
  List<ValueSettingsTarget> get valueSettingsTargets => [
    ?_movementMode,
  ];
}

/// `Math.atan2` in degrees, for the coupling orientation.
double atan2Degrees(double y, double x) => math.atan2(y, x) * 180 / math.pi;
