// `WheelMountLogic`: the state machine of the wheel mount: which wheel is
// mounted, how far the suspension reaches, how fast the wheel turns and how the
// wheel's normal force is computed.
//
// The host side of the block entity (`WheelMountBlockEntity`) keeps the
// inventory and the Sable handles; everything that decides *numbers* is here, so
// it runs on the VM.
//
// Pure: no host imports.
//
// Java: `content/blocks/wheel_mount/WheelMountBlockEntity.java`
//       (582 lines), `content/blocks/wheel_mount/WheelMountInventory.java`
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/common/common.dart' show Pos, Vec3;
import 'package:create/src/common/direction.dart' show Axis, Direction;

import '../../../config/offroad_config.dart';
import '../../components/tire_like.dart';

/// `WheelMountBlockEntity.SuspensionStrengthValueBehaviour`
/// (`WheelMountBlockEntity.java:537-549`).
abstract final class SuspensionStrength {
  /// `MAX_SUSPENSION_STRENGTH` (`WheelMountBlockEntity.java:539`).
  static const int max = 180;

  /// `between(5, MAX_SUSPENSION_STRENGTH)` (`WheelMountBlockEntity.java:542`).
  static const int min = 5;

  /// `this.strength.value = 10` (`WheelMountBlockEntity.java:127`).
  static const int defaultValue = 10;
}

/// What `WheelMountBlock.switchStacks` did (`WheelMountBlock.java:102-143`).
final class WheelSwap {
  /// The player put a wheel in (or swapped one).
  final bool switched;

  /// The stack that was in the mount before, which the player gets back.
  final ({String itemKey, int count})? returned;

  /// The wheel that is now in the mount.
  final String? inserted;

  /// Whether the incoming stack was consumed by the swap.
  final bool consumed;

  const WheelSwap({required this.switched, this.returned, this.inserted, this.consumed = false});
}

/// The result of the ray cast the suspension does
/// (`WheelMountBlockEntity.TerrainCastResult`, `WheelMountBlockEntity.java:361`).
final class WheelMountTerrainCast {
  /// `maxExtension`: the distance from the mount down to the terrain, 5 when
  /// nothing was hit (`WheelMountBlockEntity.java:366`).
  final double maxExtension;

  /// `normal`: the face of the block that was hit.
  final Direction normal;

  /// `minInteractingBlock`: the block that was hit, `null` when the cast missed.
  final Pos? minInteractingBlock;

  const WheelMountTerrainCast({
    required this.maxExtension,
    this.normal = Direction.up,
    this.minInteractingBlock,
  });

  /// The cast that hit nothing: the Java starts `minExtension` at 5 and never
  /// lowers it (`WheelMountBlockEntity.java:366`), and `minInteractingBlock` stays
  /// null.
  static const WheelMountTerrainCast miss = WheelMountTerrainCast(maxExtension: 5);

  bool get hit => minInteractingBlock != null;
}

/// The impulse the suspension applies to the sub-level this wheel is on.
final class WheelMountImpulse {
  /// The local force (`queuedForce`).
  final Vec3 force;

  /// `springForce`: the vertical part before the terrain normal is applied.
  final double springForce;

  /// `dampingForce`: the velocity-dependent part of [springForce].
  final double dampingForce;

  /// `brakingFrictionStrength`: how much the wheel brakes, from the redstone
  /// signal and the friction of the surface.
  final double brakingFrictionStrength;

  /// `springLength`: the compressed length of the suspension.
  final double springLength;

  /// `normalMassScaling`: how the sub-level's mass scaled the strength.
  final double normalMassScaling;

  /// `strengthMul`: the strength multiplier of the lateral forces.
  final double strengthMul;

  const WheelMountImpulse({
    required this.force,
    required this.springForce,
    required this.dampingForce,
    required this.brakingFrictionStrength,
    required this.springLength,
    required this.normalMassScaling,
    required this.strengthMul,
  });
}

/// The state machine of one wheel mount.
final class WheelMountLogic {
  /// `MAX_ALLOWED_EXTENSION` (`WheelMountBlockEntity.java:71`).
  static const double maxAllowedExtension = 0.65;

  /// `NO_WHEEL_EXTENSION` (`WheelMountBlockEntity.java:72`).
  static const double noWheelExtension = 0.5;

  /// `Mth.clamp(unclampedExtension, -0.45, MAX_ALLOWED_EXTENSION)`
  /// (`WheelMountBlockEntity.java:343`).
  static const double minExtension = -0.45;

  /// `suspensionRestDistance` (`WheelMountBlockEntity.java:161`).
  static const double suspensionRestDistance = maxAllowedExtension;

  /// `r`, the half-size of the wheel's search box
  /// (`WheelMountBlockEntity.java:195`).
  static const double wheelRadiusSdf = 1;

  /// The strength the scroll value starts at (`WheelMountBlockEntity.java:127`).
  int suspensionStrength = SuspensionStrength.defaultValue;

  /// The mounted wheel's item key, `null` when the mount is empty.
  String? heldItemKey;

  /// The mounted wheel's data (`CurrentStack`'s `offroad:tire` component).
  TireLike? heldTire;

  /// `extension` (`WheelMountBlockEntity.java:81`).
  double extension = noWheelExtension;

  /// `lastExtension`, for the interpolated render.
  double lastExtension = noWheelExtension;

  /// `chasingYaw` / `lastChasingYaw`.
  double chasingYaw = 0;
  double lastChasingYaw = 0;

  /// `angle` / `lastAngle`.
  double angle = 0;
  double lastAngle = 0;

  /// `angularVelocity`.
  double angularVelocity = 0;

  /// `touchingFriction`: the friction of the block the wheel rests on.
  double touchingFriction = 1;

  /// `liftedUp`: the wheel hangs in the air.
  bool liftedUp = false;

  /// The last steering signal the server saw (the client gets it in the update
  /// tag, `WheelMountBlockEntity.java:464-474`).
  int lastServerSteeringSignal = 0;
  int lastServerSteeringSignalLeft = 0;
  int lastServerSteeringSignalRight = 0;

  /// The steering signals the client received.
  int clientSteeringSignal = 0;
  int clientSteeringSignalLeft = 0;
  int clientSteeringSignalRight = 0;

  WheelMountLogic();

  /// `getHeldItem().isEmpty()`.
  bool get hasWheel => heldTire != null;

  /// The impact this block costs its network (`OffroadStress.setImpact(16)`,
  /// `OffroadBlocks.java:97`).
  double get stressImpact => OffroadConfig.wheelMountImpact;

  // -- Inventory (`WheelMountInventory.java:193-203`) ---------------------------

  /// `canInsertItem(item)`: only an item with an `offroad:tire` component fits.
  ///
  /// Java reads the component off the stack (`OffroadDataComponents.TIRE`); the
  /// caller resolves it, because the host API only exposes *built-in* data
  /// components on a stack (`ItemStack.getComponents`).
  ///
  /// TODO(parity): `WheelMountInventory.java:193-196` reads
  /// `ItemInfoWrapper.generateFromInfo(item).get(OffroadDataComponents.TIRE)`;
  /// the host has no accessor for a custom component's value on an item stack,
  /// so the port resolves the preset by item key instead
  /// (`TireLike.forItem`, `OffroadItems.java:20,30,40,56`).
  static bool canInsert({required TireLike? incomingTire}) => incomingTire != null;

  /// `WheelMountBlock.switchStacks` (`WheelMountBlock.java:102-143`): the mount
  /// takes one item of the incoming stack and hands back what it held.
  WheelSwap swapStacks({
    required String? incomingItemKey,
    required TireLike? incomingTire,
    required bool hasInfiniteMaterials,
  }) {
    if (incomingItemKey != null && incomingTire == null) {
      return const WheelSwap(switched: false);
    }

    final previousKey = heldItemKey;

    heldItemKey = incomingTire == null ? null : incomingItemKey;
    heldTire = incomingTire;

    return WheelSwap(
      switched: true,
      returned: previousKey == null ? null : (itemKey: previousKey, count: 1),
      inserted: heldItemKey,
      // `player.hasInfiniteMaterials()` keeps the held stack.
      consumed: incomingTire != null && !hasInfiniteMaterials,
    );
  }

  /// `WheelMountInventory.setChanged()` + `mount.sendData()` of a swap.
  void onStackChanged() {}

  // -- Friction (`WheelMountBlockEntity.java:142-147`) --------------------------

  /// `fudgeFriction`: give a slight amount of friction even at 0.
  static double fudgeFriction(double realValue) =>
      realValue < 1 ? 0.1 + 0.9 * realValue : realValue;

  /// `Math.min(this.touchingFriction, 1.0)`.
  double get surfaceBraking => math.min(touchingFriction, 1);

  // -- Steering (`WheelMountBlockEntity.java:442-475`) --------------------------

  /// `computeYaw` (`WheelMountBlockEntity.java:442`): the wheel turns by a
  /// quarter of 30/45 of a radian at full lock.
  static double computeYaw(int steeringSignal) {
    if (steeringSignal == 0) return 0;
    return -steeringSignal / 15.0 * math.pi / 4.0 * (30.0 / 45.0);
  }

  /// `signalLeft - signalRight` (`WheelMountBlockEntity.java:462`).
  static int steeringSignal({required int left, required int right}) => left - right;

  /// Whether the server must send the new steering signals
  /// (`WheelMountBlockEntity.java:464`).
  bool steeringChanged({required int signal, required int left, required int right}) =>
      signal != lastServerSteeringSignal ||
      left != lastServerSteeringSignalLeft ||
      right != lastServerSteeringSignalRight;

  /// `tick`'s yaw chase (`WheelMountBlockEntity.java:261-262`).
  void tickChasingYaw(int steeringSignal) {
    lastChasingYaw = chasingYaw;
    chasingYaw = _lerp(0.4, chasingYaw, computeYaw(steeringSignal));
  }

  /// `getSteeringSignal` for the client, which reads what the server sent.
  int get steeringSignalForSide => lastServerSteeringSignal;

  // -- Extension (`WheelMountBlockEntity.java:318-344`) -------------------------

  /// `computeMaxExtension(radius)` (`WheelMountBlockEntity.java:318`): how far
  /// the wheel may drop, and the friction of what it touches.
  double computeMaxExtension({
    required TireLike tire,
    required WheelMountTerrainCast cast,
    required double terrainFriction,
  }) {
    final unclampedExtension = cast.maxExtension - tire.radius;

    liftedUp = unclampedExtension > maxAllowedExtension;
    if (!cast.hit) {
      touchingFriction = 1;
    } else {
      touchingFriction = fudgeFriction(terrainFriction);
    }

    return unclampedExtension.clamp(minExtension, maxAllowedExtension);
  }

  /// The client half of `tick` (`WheelMountBlockEntity.java:266-315`): the
  /// extension chase and the angle.
  ///
  /// [translation] is the wheel's velocity along its axis in the sub-level's
  /// frame, divided by 20 (`WheelMountBlockEntity.java:295`).
  void tickClient({
    required double kineticSpeed,
    required int brakeSignal,
    required double translation,
    required bool hasSubLevel,
    required double maxExtension,
  }) {
    final tire = heldTire;
    if (tire == null) {
      angle = 0;
      lastAngle = 0;
      lastExtension = extension;
      extension = _lerp(0.6, extension, noWheelExtension);
      return;
    }

    lastExtension = extension;
    extension = _lerp(0.7, extension, maxExtension);

    // `speed` is flipped for the X axis (`WheelMountBlockEntity.java:283`).
    final rpt =
        kineticSpeed *
        math.pi *
        2.0 /
        60.0 /
        20.0 *
        (15 - brakeSignal) /
        15.0;
    final attemptedAngularVelocity = _lerp(0.2, angularVelocity, rpt);

    if (!hasSubLevel || liftedUp) {
      angularVelocity = attemptedAngularVelocity;
      lastAngle = angle;
      angle += angularVelocity;
      return;
    }

    // Compute the angle we must have changed for the current tick.
    final circumference = math.pi * tire.radius * 2.0;
    var angularDelta = -translation / circumference * math.pi * 2.0;

    // Visually slip on a slippery surface.
    if (touchingFriction < 1) {
      angularDelta = _lerp(touchingFriction, attemptedAngularVelocity, angularDelta);
    }

    lastAngle = angle;
    angle += angularDelta;
    angularVelocity = angularDelta;
  }

  /// The server half of the physics tick's suspension
  /// (`WheelMountBlockEntity.java:159-196`).
  ///
  /// Returns `false` when the wheel has no contact and the Java `return`s at
  /// `WheelMountBlockEntity.java:190-193`, `true` when the spring is applied.
  bool applyPhysicsExtension(double maxExtension) {
    extension = maxExtension;
    if (maxExtension > suspensionRestDistance + (heldTire?.radius ?? 0) + 0.25) {
      extension = suspensionRestDistance;
      return false;
    }
    return true;
  }

  /// The spring and friction impulse of `sable$physicsTick`
  /// (`WheelMountBlockEntity.java:163-238`).
  ///
  /// [normalMass] is `1 / massData.getInverseNormalMass(pos, UP)`.
  /// [localVelocityY] is the sub-level-frame velocity along Y, [localVelocity]
  /// the whole of it, [normalD] the wheel's forward axis and [sideD] its
  /// lateral axis, both rotated by the chasing yaw.
  /// [rayHitNormal] is the terrain normal in the sub-level's frame.
  WheelMountImpulse computeImpulse({
    required double normalMass,
    required double timeStep,
    required double localVelocityY,
    required Vec3 localVelocity,
    required Vec3 normalD,
    required Vec3 sideD,
    required Vec3 rayHitNormal,
    required double kineticSpeed,
    required int brakeSignal,
  }) {
    final tire = heldTire;
    final effectiveStrength = suspensionStrength.toDouble();
    final normalMassScaling = math.min(normalMass / effectiveStrength, 1.0) * 10.0;

    final strengthMul = effectiveStrength * normalMassScaling * 2;
    final springStrength = effectiveStrength * normalMassScaling * 40;
    final dampingStrength = effectiveStrength * normalMassScaling;

    final distance = (suspensionRestDistance / 6.0) + extension;
    final springLength = (distance - (tire?.radius ?? 0)).clamp(0.0, suspensionRestDistance);

    final dampingForce = -localVelocityY * dampingStrength;
    final springForce =
        ((suspensionRestDistance - springLength) * springStrength + dampingForce) * timeStep;

    var force = _scale(rayHitNormal, springForce);

    // Damping and the friction of the driven wheel.
    final brakeStrength = brakeSignal / 15.0;
    final brakingFrictionStrength = (0.075 + brakeStrength * 0.3) * surfaceBraking;

    final alongNormal =
        _dot(localVelocity, normalD) * -brakingFrictionStrength * strengthMul * timeStep +
        kineticSpeed * (1.0 - brakeStrength) * surfaceBraking * 1.75 * timeStep;
    force = _add(force, _scale(normalD, alongNormal));

    final alongSide = _dot(localVelocity, sideD) * -0.6 * touchingFriction * strengthMul * timeStep;
    force = _add(force, _scale(sideD, alongSide));

    return WheelMountImpulse(
      force: force,
      springForce: springForce,
      dampingForce: dampingForce,
      brakingFrictionStrength: brakingFrictionStrength,
      springLength: springLength,
      normalMassScaling: normalMassScaling,
      strengthMul: strengthMul,
    );
  }

  // -- The wheel's axes (`WheelMountBlockEntity.java:179-184,298-301`) ----------

  /// `getRotatedWheelAxis(normal)`: the normal turned by the chasing yaw
  /// (`WheelMountBlockEntity.java:420-424`).
  Vec3 rotatedWheelAxis((int, int, int) normal) =>
      _rotateYDegrees((normal.$1.toDouble(), normal.$2.toDouble(), normal.$3.toDouble()), chasingYaw);

  /// `Direction.get(POSITIVE, axis).getUnitVec3i()` with the X/Z swap the Java
  /// applies (`WheelMountBlockEntity.java:180-183`).
  static (int, int, int) sidewaysNormal(Axis axis) {
    final positive = switch (axis) {
      Axis.x => (1, 0, 0),
      Axis.y => (0, 1, 0),
      Axis.z => (0, 0, 1),
    };
    return (positive.$3, 0, positive.$1);
  }

  /// `kineticSpeed = facing.getAxis() == X ? getSpeed() : -getSpeed()` for the
  /// physics tick (`WheelMountBlockEntity.java:229`).
  static double physicsKineticSpeed({required double speed, required Axis axis}) =>
      axis == Axis.x ? speed : -speed;

  /// `kineticSpeed = facing.getAxis() == X ? -getSpeed() : getSpeed()` for the
  /// client tick (`WheelMountBlockEntity.java:283`).
  static double clientKineticSpeed({required double speed, required Axis axis}) =>
      axis == Axis.x ? -speed : speed;

  // -- Saved data (`WheelMountBlockEntity.java:481-512`) ------------------------

  /// `write(tag, registries, clientPacket)`; the inventory's stack is written by
  /// the host (`CurrentStack`), which the port keeps in [heldItemKey].
  Map<String, Object?> write({required bool clientPacket}) => {
    if (clientPacket) 'SteeringSignalStrength': lastServerSteeringSignal,
    if (clientPacket) 'SteeringSignalStrengthLeft': lastServerSteeringSignalLeft,
    if (clientPacket) 'SteeringSignalStrengthRight': lastServerSteeringSignalRight,
  };

  /// `read(tag, registries, clientPacket)`
  /// (`WheelMountBlockEntity.java:494-512`).
  void read(Map<String, Object?> tag, {required bool clientPacket}) {
    if (!clientPacket) return;
    if (!tag.containsKey('SteeringSignalStrength')) return;
    clientSteeringSignal = (tag['SteeringSignalStrength'] as num?)?.toInt() ?? 0;
    clientSteeringSignalLeft = (tag['SteeringSignalStrengthLeft'] as num?)?.toInt() ?? 0;
    clientSteeringSignalRight = (tag['SteeringSignalStrengthRight'] as num?)?.toInt() ?? 0;
    onStackChanged();
  }

  /// `createRenderBoundingBox()` (`WheelMountBlockEntity.java:527-535`): the
  /// block, inflated by the wheel's radius.
  static double renderBoundingBoxSize(TireLike? tire) => tire == null ? 0 : tire.radius + 1;

  static double _lerp(double delta, double start, double end) => start + delta * (end - start);

  static Vec3 _add(Vec3 a, Vec3 b) => (a.$1 + b.$1, a.$2 + b.$2, a.$3 + b.$3);
  static Vec3 _scale(Vec3 v, double s) => (v.$1 * s, v.$2 * s, v.$3 * s);
  static double _dot(Vec3 a, Vec3 b) => a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;

  /// `Vector3d.rotateY(deg)`.
  static Vec3 _rotateYDegrees(Vec3 v, double deg) {
    if (deg == 0) return v;
    final r = deg / 180.0 * math.pi;
    final sin = math.sin(r);
    final cos = math.cos(r);
    return (v.$1 * cos + v.$3 * sin, v.$2, v.$3 * cos - v.$1 * sin);
  }
}