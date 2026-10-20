// `MinecartController`: the per-cart state of the coupling system — stalled (internal/external) and
// coupled to another cart — saved with the cart and synced to the clients.
//
// Java: `content/contraptions/minecart/capability/MinecartController`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../common/common.dart';
import '../../../core/nbt.dart';
import '../../blocks/actuator_contract.dart';
import '../../core/contraption.dart';
import 'capability_minecart_controller.dart';
import '../../core/nbt_map.dart';
import '../minecart_access.dart';

/// `MinecartController`.
final class MinecartController {
  /// The world the cart lives in, `null` for the EMPTY controller.
  final MinecartWorld? level;
  final String cartUuid;

  /// `<internal (waiting couplings), external (stalled contraptions)>`.
  Couple<StallData?> stallData = Couple<StallData?>(null, null);

  /// `<main (this cart leads), connected (the other cart leads)>`.
  Couple<CouplingData?> couplings = Couple<CouplingData?>(null, null);

  bool needsEntryRefresh = true;

  MinecartController(this.level, this.cartUuid);

  /// `MinecartController.EMPTY`.
  MinecartController.empty() : level = null, cartUuid = '';

  bool get isEmpty => level == null;

  MinecartAccess? get cart => level?.byUuid(cartUuid);

  bool get isPresent {
    final c = cart;
    return c != null && c.isAlive;
  }

  void tick() {
    final c = cart;
    if (c == null || level == null) return;

    if (needsEntryRefresh) {
      CapabilityMinecartController.queueAddition(level!, c.uuid);
      needsEntryRefresh = false;
    }

    stallData.forEach((s) => s?.tick(c));

    var internalStall = false;
    couplings.forEachWithContext((coupling, main) {
      if (coupling == null) return;
      final otherId = coupling.idOfCart(!main);
      final other = CapabilityMinecartController.getIfPresent(level!, otherId);
      internalStall =
          internalStall ||
          other == null ||
          !other.isPresent ||
          other.isStalledInternal(false);
    });
    setStalled(internalStall, internal: true);
    _disassemble(c);
  }

  /// `disassemble`: a contraption riding an activator rail is placed back, and the rail damages
  /// the cart it carried.
  void _disassemble(MinecartAccess c) {
    // `cart instanceof Minecart`: a plain rideable cart never carries a contraption.
    if (c.isPlainCart) return;
    final passenger = c.firstPassengerContraption;
    if (passenger == null) return;

    final pos = c.position;
    var y = pos.$2.floor();
    final below = (pos.$1.floor(), y - 1, pos.$3.floor());
    if (isRailState(level!.stateAt(below))) y--;
    final railPos = (pos.$1.floor(), y, pos.$3.floor());
    final railState = level!.stateAt(railPos);
    // `PoweredRailBlock.isActivatorRail()`: an activator rail fires whether or not it is powered.
    if (!isRailState(railState) || railState.key != 'minecraft:activator_rail') return;
    if (c.isVehicle) c.ejectPassengers();
    // `setHurtDir(-getHurtDir()); setHurtTime(10); setDamage(50)`: the cart is destroyed.
    c.markActivatorRailHit();
    final contraption = passenger;
    if (contraption is ContraptionEntityHandle) {
      ContraptionDisassembly.disassemble?.call(contraption);
    }
  }

  bool get isFullyCoupled => isLeadingCoupling && isConnectedToCoupling;

  bool get isLeadingCoupling => couplings.first != null;

  bool get isConnectedToCoupling => couplings.second != null;

  bool get isCoupledThroughContraption =>
      hasContraptionCoupling(true) || hasContraptionCoupling(false);

  bool hasContraptionCoupling(bool main) =>
      couplings.get(main)?.contraption ?? false;

  double getCouplingLength(bool leading) => couplings.get(leading)?.length ?? 0;

  void decouple() {
    couplings.forEachWithContext((coupling, main) {
      if (coupling == null) return;
      final otherId = coupling.idOfCart(!main);
      final other = CapabilityMinecartController.getIfPresent(level!, otherId);
      if (other == null) return;
      removeConnection(main);
      other.removeConnection(!main);
    });
  }

  void removeConnection(bool main) {
    if (hasContraptionCoupling(main) && level != null) {
      final passenger = cart?.firstPassengerContraption;
      if (passenger is ContraptionEntityHandle)
        ContraptionDisassembly.disassemble?.call(passenger);
    }
    couplings.set(main, null);
    needsEntryRefresh |= main;
    sendData();
  }

  /// `prepareForCoupling`: flips the chain so [isLeading] is on the requested side.
  void prepareForCoupling(bool isLeading) {
    if (isLeading && isLeadingCoupling || !isLeading && isConnectedToCoupling) {
      final cartsToFlip = <MinecartController>[];
      var current = this;
      final forward = current.isLeadingCoupling;
      var safetyCount = 1000;
      while (true) {
        if (safetyCount-- <= 0) return;
        cartsToFlip.add(current);
        final next = CouplingChain.next?.call(level!, current, forward);
        if (next == null || next.isEmpty) break;
        current = next;
      }

      for (final controller in cartsToFlip) {
        controller.couplings.forEachWithContext((coupling, leading) {
          if (coupling == null) return;
          coupling.flip();
          // A contraption riding this cart remembers which end of the coupling it is on.
          if (!coupling.contraption) return;
          final contraption = controller.cart?.firstPassengerContraption;
          if (contraption is! OrientedCouplingId) return;
          final id = contraption.couplingId;
          if (id == coupling.mainCartId) {
            contraption.setCouplingId(coupling.connectedCartId);
          } else if (id == coupling.connectedCartId) {
            contraption.setCouplingId(coupling.mainCartId);
          }
        });
        controller.couplings = controller.couplings.swap();
        controller.needsEntryRefresh = true;
        // `continue` in Java: the rest of the chain is flipped too, only this cart skips the sync.
        if (identical(controller, this)) continue;
        controller.sendData();
      }
    }
  }

  void coupleWith(
    bool isLeading,
    String coupled,
    double length,
    bool contraption,
  ) {
    final mainId = isLeading ? cartUuid : coupled;
    final connectedId = isLeading ? coupled : cartUuid;
    couplings.set(
      isLeading,
      CouplingData(mainId, connectedId, length, contraption),
    );
    needsEntryRefresh |= isLeading;
    sendData();
  }

  String? getCoupledCart(bool asMain) {
    final coupling = couplings.get(asMain);
    if (coupling == null) return null;
    return asMain ? coupling.connectedCartId : coupling.mainCartId;
  }

  bool get isStalled => isStalledInternal(true) || isStalledInternal(false);

  bool isStalledInternal(bool internal) => stallData.get(internal) != null;

  void setStalledExternally(bool stall) => setStalled(stall, internal: false);

  void setStalled(bool stall, {required bool internal}) {
    if (isStalledInternal(internal) == stall) return;
    final c = cart;
    if (c == null) return;

    if (stall) {
      stallData.set(internal, StallData.of(c));
      sendData();
      return;
    }

    if (!isStalledInternal(!internal)) stallData.get(internal)?.release(c);
    stallData.set(internal, null);
    sendData();
  }

  /// `sendData`: the state goes to the clients tracking the cart.
  void sendData() {
    final c = cart;
    if (c == null || level == null) return;
    final bus = ActuatorHosts.payloadBus;
    if (bus == null) return;
    final nbt = serializeNbt();
    bus.sendToTrackingAt(
      'create:minecart_controller',
      _worldId(level!),
      (c.position.$1.floor(), c.position.$2.floor(), c.position.$3.floor()),
      {'entityId': c.id, 'nbt': nbt.isEmpty ? null : nbt.toValue()},
    );
  }

  String _worldId(MinecartWorld level) =>
      level is HostMinecartWorld ? level.worldId : '';

  /// `serializeNBT`.
  NbtMap serializeNbt() {
    final nbt = NbtMap();
    stallData.forEachWithContext((stall, internal) {
      if (stall != null)
        nbt.putCompound(
          internal ? 'InternalStallData' : 'StallData',
          stall.serialize(),
        );
    });
    couplings.forEachWithContext((coupling, main) {
      if (coupling != null)
        nbt.putCompound(
          main ? 'MainCoupling' : 'ConnectedCoupling',
          coupling.serialize(),
        );
    });
    return nbt;
  }

  /// `deserializeNBT`.
  void deserializeNbt(NbtMap nbt) {
    final internalStall = nbt.getCompoundOrNull('InternalStallData');
    final externalStall = nbt.getCompoundOrNull('StallData');
    final mainCoupling = nbt.getCompoundOrNull('MainCoupling');
    final connectedCoupling = nbt.getCompoundOrNull('ConnectedCoupling');

    stallData = Couple<StallData?>(
      internalStall == null ? null : StallData.read(internalStall),
      externalStall == null ? null : StallData.read(externalStall),
    );
    couplings = Couple<CouplingData?>(
      mainCoupling == null ? null : CouplingData.read(mainCoupling),
      connectedCoupling == null ? null : CouplingData.read(connectedCoupling),
    );
    needsEntryRefresh = true;
  }
}

/// `MinecartController.CouplingData`.
final class CouplingData {
  String mainCartId;
  String connectedCartId;
  final double length;
  final bool contraption;

  CouplingData(
    this.mainCartId,
    this.connectedCartId,
    this.length,
    this.contraption,
  );

  void flip() {
    final swap = mainCartId;
    mainCartId = connectedCartId;
    connectedCartId = swap;
  }

  String idOfCart(bool main) => main ? mainCartId : connectedCartId;

  NbtMap serialize() => NbtMap()
    ..putString('Main', mainCartId)
    ..putString('Connected', connectedCartId)
    ..putFloat('Length', length)
    ..putBool('Contraption', contraption);

  static CouplingData read(NbtMap nbt) => CouplingData(
    nbt.getString('Main'),
    nbt.getString('Connected'),
    nbt.getDouble('Length'),
    nbt.getBool('Contraption'),
  );
}

/// `MinecartController.StallData`.
final class StallData {
  Vec3 position = vec3Zero;
  Vec3 motion = vec3Zero;
  double yaw = 0;
  double pitch = 0;

  StallData();

  StallData.of(MinecartAccess cart) {
    position = cart.position;
    motion = cart.velocity;
    yaw = cart.yaw;
    pitch = cart.pitch;
    tick(cart);
  }

  void tick(MinecartAccess cart) {
    cart.setVelocity(vec3Zero);
    cart.setRotation(yaw, pitch);
  }

  void release(MinecartAccess cart) => cart.setVelocity(motion);

  NbtMap serialize() => NbtMap()
    ..putVec('Pos', position)
    ..putVec('Motion', motion)
    ..putFloat('Yaw', yaw)
    ..putFloat('Pitch', pitch);

  static StallData read(NbtMap nbt) => StallData()
    ..position = nbt.getVec('Pos')
    ..motion = nbt.getVec('Motion')
    ..yaw = nbt.getDouble('Yaw')
    ..pitch = nbt.getDouble('Pitch');
}

/// Hooks the coupling code uses so it does not import the entity layer.
abstract final class ContraptionDisassembly {
  static void Function(ContraptionEntityHandle entity)? disassemble;
}

/// The part of an oriented contraption the coupling code needs: the coupling it is attached to.
/// Implemented by `OrientedContraptionEntity`; the coupling flip of a coupled chain keeps it on
/// the correct end.
abstract interface class OrientedCouplingId {
  String? get couplingId;
  void setCouplingId(String? id);
}

/// `CouplingHandler.getNextInCouplingChain`.
abstract final class CouplingChain {
  static MinecartController? Function(
    MinecartWorld level,
    MinecartController controller,
    bool forward,
  )?
  next;

  static String? coupledCart(MinecartController controller, bool forward) =>
      controller.getCoupledCart(forward);
}

/// The NBT type re-export used by the packet fields.
typedef MinecartNbtValue = NbtValue;
