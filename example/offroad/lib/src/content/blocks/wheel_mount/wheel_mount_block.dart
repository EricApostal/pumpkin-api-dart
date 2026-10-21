// The wheel mount: a kinetic block that carries one tire and applies the
// suspension's spring, damping and friction forces to the sub-level it sits on.
//
// Java: `content/blocks/wheel_mount/{WheelMountBlock,WheelMountBlockEntity,WheelMountInventory}`.
//
// The numbers live in the pure [WheelMountLogic]; this file is the host half:
// the scroll value, the redstone steering, the held item, the sub-level physics
// callback and the saved data.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/create.dart';
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/direction.dart' show Axis, Direction;
import 'package:create/src/common/host_bridge.dart' show DirectionToHost, PosToHost;
import 'package:create/src/common/pos.dart';
import 'package:create/src/kinetics/block_defs.dart' show FacingBlockDef;
import 'package:create/src/kinetics/behaviours.dart' show ScrollValueBehaviour;
import 'package:create/src/kinetics/kinetic_block_entity.dart';
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart';

import '../../../config/offroad_config.dart';
import '../../../host/offroad_hooks.dart';
import '../../../index/offroad_ids.dart';
import '../../components/tire_like.dart';
import 'wheel_mount_logic.dart';

/// The block and block entity key (`offroad:wheel_mount`).
const String wheelMountKey = OffroadIds.wheelMount;

/// `WheelMountBlockEntity`.
final class WheelMountBlockEntity extends KineticBlockEntity implements BlockEntitySubLevelActor {
  WheelMountBlockEntity(super.worldId, super.pos) {
    // `addBehaviours` runs in the constructor so `read` restores the saved
    // `ScrollValue` (the framework reads before `onLoad`).
    _strength = addBehaviour(
      ScrollValueBehaviour().between(SuspensionStrength.min, SuspensionStrength.max),
    )..value = SuspensionStrength.defaultValue;
  }

  /// The pure state machine.
  final WheelMountLogic logic = WheelMountLogic();

  ScrollValueBehaviour? _strength;

  /// `getInventory().slot` as the item key and its tire data.
  String? _heldItemKey;

  /// The force the suspension accumulated this physics tick
  /// (`forceTotal` + `queuedForce`).
  final ForceTotal _forceTotal = ForceTotal();

  /// The position the force is applied at, in the sub-level's frame.
  final Vector3d _queuedForcePos = Vector3d();

  /// The accumulated force of this physics tick.
  final Vector3d _queuedForce = Vector3d();

  /// `getHeldItem()`: the mounted wheel's key, `null` when empty.
  String? get heldItemKey => _heldItemKey;

  /// `getHeldItem().get(OffroadDataComponents.TIRE)`.
  ///
  /// TODO(parity): the host has no accessor for a custom component's value on an
  /// item stack, so the preset is resolved from the item key
  /// (`TireLike.forItem`); the values are the ones `OffroadItems` gives the item.
  TireLike? get heldTire => _heldItemKey == null ? null : TireLike.forItem(_heldItemKey!);

  /// The state of the block as plain data.
  BState get bState => BState(blockState.block, blockState.props);

  /// The position as the pure [Pos] (`getBlockPos()`); `pos` is the host
  /// `BlockPos`.
  Pos get blockPos => (this.pos.x, this.pos.y, this.pos.z);

  /// `HORIZONTAL_FACING`.
  Direction get facing => bState.dir('facing') ?? Direction.north;

  /// The suspension strength the player set (`strength.getValue()`).
  int get suspensionStrength => _strength?.value ?? SuspensionStrength.defaultValue;

  /// `calculateStressApplied`: the impact of `OffroadStress.setImpact(16.0)`
  /// (`OffroadBlocks.java:97`), scaled by the speed the network drives it at.
  @override
  double calculateStressApplied() => OffroadConfig.wheelMountImpact * speed.abs() / 16.0;

  // -- The held item ------------------------------------------------------------

  /// `switchStacks` (`WheelMountBlock.java:102-143`), against the port's
  /// item-key inventory.
  WheelSwap swapStacks({required String? incomingItemKey, required bool hasInfiniteMaterials}) {
    final swap = logic.swapStacks(
      incomingItemKey: incomingItemKey,
      incomingTire: incomingItemKey == null ? null : TireLike.forItem(incomingItemKey),
      hasInfiniteMaterials: hasInfiniteMaterials,
    );
    if (!swap.switched) return swap;

    _heldItemKey = swap.inserted;
    markDirty();
    sendData();
    return swap;
  }

  /// `preRemoveSideEffects`: the wheel drops in front of the mount, not inside
  /// it (`WheelMountBlockEntity.java:105-115`).
  @override
  void onRemoved() {
    final held = _heldItemKey;
    final w = world;
    if (held != null && w != null) {
      final dropPos = blockPos.relative(facing);
      unawaited(w.dropItem(dropPos.center, ItemStacks.plain(held)));
      _heldItemKey = null;
    }
    OffroadHooks.forgetActor(worldId, this.pos);
    super.onRemoved();
  }

  // -- Tick ---------------------------------------------------------------------

  /// `getSteeringSignal` (`WheelMountBlockEntity.java:451-478`): the difference
  /// between the signals of the two sides.
  ///
  /// TODO(parity): Java reads `level.getSignal(pos.relative(d), d)` — the signal
  /// the neighbour emits toward the mount. The host only exposes
  /// `getBestNeighborSignal(pos)`, so each side's best signal is used; a
  /// neighbour that emits only toward another face reads stronger here.
  int _steeringSignal() {
    final w = world;
    if (w == null) return 0;
    final left = facing.clockWise;
    final right = facing.counterClockWise;
    final leftSignal = _cachedSignal(w, blockPos.relative(left));
    final rightSignal = _cachedSignal(w, blockPos.relative(right));

    final signal = WheelMountLogic.steeringSignal(left: leftSignal, right: rightSignal);
    if (logic.steeringChanged(signal: signal, left: leftSignal, right: rightSignal)) {
      logic.lastServerSteeringSignal = signal;
      logic.lastServerSteeringSignalLeft = leftSignal;
      logic.lastServerSteeringSignalRight = rightSignal;
      sendData();
    }
    return signal;
  }

  /// The redstone signal of one side, re-read at most once per tick.
  final Map<Pos, int> _signals = {};

  int _cachedSignal(World w, Pos pos) => _signals[pos] ??= 0;

  /// `tick`: the server chases the yaw and sends the steering signal; the angle
  /// itself is client-only.
  @override
  void tick() {
    logic.suspensionStrength = suspensionStrength;
    logic.heldItemKey = _heldItemKey;
    logic.heldTire = heldTire;

    logic.tickChasingYaw(_steeringSignal());
    _signals.clear();
    _readSignals();

    super.tick();
  }

  /// Reads the two steering signals asynchronously and caches them for the next
  /// tick (`getBestNeighborSignal` is a host call).
  void _readSignals() {
    final w = world;
    if (w == null) return;
    for (final side in [facing.clockWise, facing.counterClockWise]) {
      final target = blockPos.relative(side);
      unawaited(
        w
            .getBestNeighborSignal(pos: target.toBlockPos())
            .then((value) => _signals[target] = value),
      );
    }
  }

  // -- Physics ------------------------------------------------------------------

  /// `BlockEntitySubLevelActor.sable$tick`: the mount has no per-game-tick
  /// sub-level work in Java either.
  @override
  void sable$tick(ServerSubLevel subLevel) {}

  @override
  Iterable<SubLevel>? sable$getConnectionDependencies() => null;

  @override
  Iterable<SubLevel>? sable$getLoadingDependencies() => null;

  /// `sable$physicsTick` (`WheelMountBlockEntity.java:149-238`).
  @override
  void sable$physicsTick(ServerSubLevel subLevel, RigidBodyHandle handle, double timeStep) {
    final tire = heldTire;
    if (tire == null) return;

    final massData = subLevel.massTracker;
    if (massData == null || massData.isInvalid()) return;

    final center = blockPos.relative(facing).center;
    final pose = subLevel.logicalPose;
    final axis = facing.axis;
    final sideNormal = WheelMountLogic.sidewaysNormal(axis);
    final normalD = logic.rotatedWheelAxis(sideNormal);
    final sideD = logic.rotatedWheelAxis(WheelMountLogic.sidewaysNormal(switch (axis) {
      Axis.x => Axis.z,
      Axis.z => Axis.x,
      Axis.y => Axis.y,
    }));

    final cast = _castToTerrain(center, normalD);
    final maxExtension = logic.computeMaxExtension(
      tire: tire,
      cast: cast,
      terrainFriction: _frictionAt(cast.minInteractingBlock),
    );
    if (!logic.applyPhysicsExtension(maxExtension)) return;

    final velocity = SubLevelHelper.getVelocityOfSubLevel(
      OffroadHooks.of(world!).sableLevel,
      subLevel,
      Vector3d(center.$1, center.$2, center.$3),
      Vector3d(),
    );
    final localVelocity = pose.transformNormalInverse(velocity);
    final local = (localVelocity.x, localVelocity.y, localVelocity.z);

    final normalMass = _normalMass(massData, center);
    final impulse = logic.computeImpulse(
      normalMass: normalMass,
      timeStep: timeStep,
      localVelocityY: local.$2,
      localVelocity: local,
      normalD: normalD,
      sideD: sideD,
      rayHitNormal: (0.0, 1.0, 0.0),
      kineticSpeed: WheelMountLogic.physicsKineticSpeed(speed: speed, axis: axis),
      brakeSignal: _brakeSignal(),
    );

    _queuedForcePos.set(center.$1, center.$2, center.$3);
    _queuedForce.set(impulse.force.$1, impulse.force.$2, impulse.force.$3);
    _forceTotal.applyImpulseAtPoint(massData, _queuedForcePos, _queuedForce);
    handle.applyForcesAndReset(_forceTotal);
  }

  /// `1 / massData.getInverseNormalMass(pos, UP)`.
  ///
  /// TODO(parity): Sable's `MassData` in the port exposes no
  /// `getInverseNormalMass(position, normal)`, so the wheel uses the body's
  /// uniform normal mass (`1 / getInverseMass()`). A long sub-level has a larger
  /// normal mass at its ends, so the suspension is softer there than in Java.
  double _normalMass(MassData massData, (double, double, double) center) {
    final inverse = massData.getInverseMass();
    return inverse <= 0 ? 0 : 1 / inverse;
  }

  /// `this.level.getSignal(blockPos.above(), Direction.UP)`.
  int _brakeSignal() => _signals[(this.pos.x, this.pos.y + 1, this.pos.z)] ?? 0;

  /// The friction of the block the wheel rests on
  /// (`PhysicsBlockPropertyHelper.getFriction`).
  ///
  /// TODO(parity): `sable:friction` is a block property the Sable port does not
  /// read yet; the default of the block properties table (1.0) is used.
  double _frictionAt(Pos? pos) => 1;

  /// `computeMaxExtensionToTerrain` (`WheelMountBlockEntity.java:361-418`): three
  /// vertical casts down from the wheel, the nearest hit wins.
  ///
  /// TODO(parity): Java clips with `ClipContext.Block.COLLIDER` along the
  /// sub-level-aware level clip, ignoring the containing sub-level and keeping
  /// the hit normal. The port walks the host's blocks straight down from each of
  /// the three sample points and treats a solid block as a hit with an up normal,
  /// which is the same answer for the flat ground a wheel drives on.
  WheelMountTerrainCast _castToTerrain((double, double, double) center, (double, double, double) normalD) {
    final w = world;
    if (w == null) return WheelMountTerrainCast.miss;

    var best = WheelMountTerrainCast.miss;
    for (var i = -1; i <= 1; i++) {
      final x = center.$1 + normalD.$1 * i;
      final z = center.$3 + normalD.$3 * i;
      for (var step = 1; step <= 5; step++) {
        final y = center.$2 - step;
        final state = BlockRegistry.stateFromId(
          w.getBlockStateId(pos: (x.floor(), y.floor(), z.floor()).toBlockPos()),
        );
        if (state == null || state.isAir || state.isLiquid) continue;
        final distance = center.$2 - (y.floor() + 1.0);
        if (distance <= 1e-5) break;
        if (distance < best.maxExtension) {
          best = WheelMountTerrainCast(
            maxExtension: distance,
            normal: Direction.up,
            minInteractingBlock: (x.floor(), y.floor(), z.floor()),
          );
        }
        break;
      }
    }
    return best;
  }

  // -- Saved data ---------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    final held = _heldItemKey;
    if (held != null) tag.putString('CurrentStack', held);
    for (final entry in logic.write(clientPacket: clientPacket).entries) {
      final value = entry.value;
      if (value is int) tag.putInt(entry.key, value);
    }
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    _heldItemKey = tag.getString('CurrentStack');
    logic.read({
      if (tag.containsKey('SteeringSignalStrength')) 'SteeringSignalStrength': tag.getInt('SteeringSignalStrength'),
      if (tag.containsKey('SteeringSignalStrengthLeft')) 'SteeringSignalStrengthLeft': tag.getInt('SteeringSignalStrengthLeft'),
      if (tag.containsKey('SteeringSignalStrengthRight')) 'SteeringSignalStrengthRight': tag.getInt('SteeringSignalStrengthRight'),
    }, clientPacket: clientPacket);
  }
}

/// `WheelMountBlock`.
CreateBlock buildWheelMountBlock() => CreateBlock(
  key: wheelMountKey,
  properties: [CreateProps.horizontalFacing],
  defaultState: {'facing': 'north'},
  // `SharedProperties.stone()`: `Blocks.STONE`'s 1.5 / 6.
  hardness: 1.5,
  blastResistance: 6,
  requiresCorrectTool: true,
  soundType: 'stone',
  canOcclude: false,
  // `AllTags.AllBlockTags.SAFE_NBT`.
  tags: const ['create:safe_nbt'],
  placement: const [
    // `getPreferredHorizontalFacing` is not in the port's placement rules; Java
    // falls back to the look direction (opposite unless sneaking) in that case,
    // which is exactly these two rules.
    PlacementRule.lookingDirection('facing', opposite: true, whenSneaking: false),
    PlacementRule.lookingDirection('facing', whenSneaking: true),
  ],
  blockEntityType: wheelMountKey,
  behavior: BlockBehavior(
    onUseWithItem: (server, e) async {
      // `WheelMountBlock.useItemOn`: only a click on the front face (or the top)
      // swaps the wheel; anything else is the ordinary item behaviour.
      final state = HostBlockGetter.stateOfId(e.stateIndex);
      final facing = state.dir('facing') ?? Direction.north;
      if (e.face != facing.toHost() && e.face != BlockDirection.down) return BlockUseResult.pass;

      final be = OffroadHooks.store?.at(e.targetWorld.getId(), e.pos);
      if (be is! WheelMountBlockEntity) return BlockUseResult.pass;

      final held = e.item;
      final heldKey = await held.getRegistryKey();
      // An empty stack reports `minecraft:air` as its registry key.
      final key = heldKey == 'minecraft:air' ? null : heldKey;
      if (key != null && TireLike.forItem(key) == null) return BlockUseResult.pass;

      final swap = be.swapStacks(incomingItemKey: key, hasInfiniteMaterials: e.player.isCreative);
      if (!swap.switched) return BlockUseResult.pass;

      if (swap.returned case final returned?) {
        await e.player.give(ItemStacks.plain(returned.itemKey, count: returned.count));
      }
      if (swap.consumed) await held.setCount(count: await held.getCount() - 1);
      return BlockUseResult.success;
    },
  ),
);

/// The kinetic rules of the wheel mount: `HorizontalKineticBlock`, whose shaft
/// leaves through the side opposite its facing.
const FacingBlockDef wheelMountKineticDef = FacingBlockDef(shaftAtFront: false);
