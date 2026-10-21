// `EjectorBlockEntity` (server behaviour): the weighted ejector. It charges with items (a depot
// behaviour), winds up with the kinetic speed and launches its contents along the `EntityLauncher`
// trajectory to the target (a direct belt input, or an item entity). Non-player entities standing
// on it are launched as well; players are launched by their own client, which reports the result
// back through `deployElytra` and the `EJECTOR_MAXED` award.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import '../../../api/blocks.dart';
import '../../../api/kinetics.dart'
    show
        Dir,
        KAxis,
        KState,
        KineticBlockDef,
        KineticBlockEntity,
        ScrollValueBehaviour;
import '../../../common/direction.dart';
import '../../../common/host_bridge.dart';
import '../../../common/pos.dart';
import '../../../processing/transport/transport_behaviours.dart' as pt;
import '../../behaviours/belt_interfaces.dart';
import '../../behaviours/processing_bridge.dart';
import '../../belt/transported_item.dart';
import '../../items/item_codec.dart';
import '../../items/item_data.dart';
import '../../nbt_names.dart';
import '../../runtime.dart';
import '../funnel/funnel_block_entity.dart';
import '../transport_support.dart';
import 'depot_behaviour.dart';
import 'ejector_lid.dart';
import 'entity_launcher.dart';

/// `EjectorBlockEntity.State`.
enum _EjectorState { charged, launching, retracting }

/// The kinetic rules of `create:weighted_ejector`: the shaft runs along the axis perpendicular to
/// the facing (`getRotationAxis = facing.getClockWise().getAxis()`).
final class EjectorKineticDef extends KineticBlockDef {
  const EjectorKineticDef();

  @override
  KAxis rotationAxis(KState state) {
    final facing = state.dirOf('facing') ?? Dir.north;
    return facing.axis == KAxis.z ? KAxis.x : KAxis.z;
  }

  @override
  bool hasShaftTowards(KState state, Dir face) =>
      face.axis == rotationAxis(state);
}

/// `EjectorBlockEntity`.
class EjectorBlockEntity extends KineticBlockEntity {
  late final DepotBehaviour depotBehaviour;
  late final ScrollValueBehaviour maxStackSize;

  final EntityLauncher launcher = EntityLauncher(1, 0);
  double lidProgress = 1;
  bool powered = false;
  bool _launch = false;
  _EjectorState _state = _EjectorState.retracting;

  int scanCooldown = 0;
  ItemValue? trackedItem;
  final List<_Launched> _launchedItems = [];

  EjectorBlockEntity(super.worldId, super.pos) {
    depotBehaviour = addBehaviour(DepotBehaviour());
    maxStackSize = addBehaviour(ScrollValueBehaviour()..between(0, 64));
    depotBehaviour.maxStackSize = () => maxStackSize.value;
    depotBehaviour.canAcceptItems = () => _state == _EjectorState.charged;
    depotBehaviour.canFunnelsPullFrom = (Direction side) => side != getFacing();
    depotBehaviour.enableMerging();
    depotBehaviour.addSubBehaviours();
  }

  ConveyanceRuntime get rt => ConveyanceRuntime.i;

  @override
  void initialize() {
    super.initialize();
    rt.fire('Ejector signal', updateSignal);
  }

  BState get state => rt.stateAt(worldId, this.pos.toPos());

  BState stateAt(Pos p) => rt.stateAt(worldId, p);

  /// `getFacing`.
  Direction getFacing() {
    final blockState = state;
    if (blockState.key != 'create:weighted_ejector') return Direction.up;
    return blockState.dir('facing') ?? Direction.north;
  }

  bool get isRetracting => _state == _EjectorState.retracting;

  bool get isLaunching => _state == _EjectorState.launching;

  bool get isPowered => powered;

  // -- Tick ------------------------------------------------------------------------------------

  @override
  Future<void> tick() async {
    super.tick();
    if (scanCooldown > 0) scanCooldown--;

    if (_launch) {
      _launch = false;
      await activateDeferred();
    }

    final totalTime = math.max(3.0, launcher.getTotalFlyingTicks());
    for (final entry in List.of(_launchedItems)) {
      entry.time++;
      if (entry.time > totalTime) {
        await placeItemAtTarget(totalTime, entry);
        _launchedItems.remove(entry);
      }
    }

    final windUp = getWindUpSpeed();
    if (_state == _EjectorState.launching) {
      // `lidProgress.chase(1, .8f, Chaser.EXP)`: the lid keeps opening until it is nearly there.
      _chaseLid(1, ejectorLidChaseSpeed);
      _tickLidChaser();
      if (lidProgress > ejectorLidOpenThreshold) {
        _state = _EjectorState.retracting;
        lidProgress = 1;
      }
    } else if (_state == _EjectorState.retracting) {
      // Finish the opening chase first, then close at the wind-up speed.
      if (_lidTarget == 1 && !_lidSettled) {
        _tickLidChaser();
      } else {
        _chaseLid(0, 0);
        if (lidProgress == 0) {
          _state = _EjectorState.charged;
          lidProgress = 0;
          sendData();
        }
        lidProgress = ejectorLidRetract(lidProgress, windUp);
      }
    } else {
      // `CHARGED`: the lid sits closed with no chase running.
      _chaseLid(0, 0);
      lidProgress = 0;
      await ejectIfTriggered();
    }
  }

  double _lidTarget = 1;
  double _lidSpeed = 0;

  bool get _lidSettled => (lidProgress - _lidTarget).abs() < 1e-5;

  void _chaseLid(double target, double speed) {
    _lidTarget = target;
    _lidSpeed = speed;
  }

  /// `LerpedFloat.tickChaser`.
  void _tickLidChaser() {
    if (_lidSpeed == 0) return;
    if (_lidSettled) {
      lidProgress = _lidTarget;
      return;
    }
    lidProgress = ejectorLidChase(lidProgress, _lidTarget, _lidSpeed);
  }

  /// `activate`.
  void activate() {
    _launch = true;
    nudgeEntities();
  }

  /// `activateDeferred`.
  Future<void> activateDeferred() async {
    if (_state != _EjectorState.charged) return;
    await launchItems();
    await launchEntities();
    _state = _EjectorState.launching;
    // `lidProgress.chase(1, .8f, Chaser.EXP)`: the lid opens over the following ticks.
    _chaseLid(1, ejectorLidChaseSpeed);
    final world = this.world;
    if (world != null) {
      playSoundAt(
        world,
        this.pos.toPos(),
        Sound.blockWoodenTrapdoorClose,
        volume: .35,
        pitch: 1,
      );
    }
  }

  /// The box `new AABB(worldPosition).inflate(-1/16, 0, -1/16)`.
  List<EntitySnapshot> _entitiesOnEjector(World world) =>
      world.getEntitiesInBox(
        min: (this.pos.x + 1 / 16, this.pos.y.toDouble(), this.pos.z + 1 / 16),
        max: (
          this.pos.x + 1 - 1 / 16,
          this.pos.y + 1.0,
          this.pos.z + 1 - 1 / 16,
        ),
        filter: const EntityFilterAll(),
      );

  /// `nudgeEntities`: living entities on the ejector are lifted out of its lid.
  void nudgeEntities() {
    final world = this.world;
    if (world == null) return;
    for (final snapshot in _entitiesOnEjector(world)) {
      if (snapshot.entityTypeKey == 'minecraft:player') continue;
      final entity = world.getEntityById(id: snapshot.id);
      entity?.moveBy((0, .125, 0));
    }
  }

  /// The server half of Java's `activateDeferred`: every non-player, non-item entity standing on
  /// the ejector is moved to its lid and given the launch velocity. Packages are left alone, like
  /// Java's `PackageEntity` exception.
  Future<void> launchEntities() async {
    final world = this.world;
    if (world == null) return;
    final facing = getFacing();
    for (final snapshot in _entitiesOnEjector(world)) {
      if (snapshot.entityTypeKey == 'minecraft:item' ||
          snapshot.entityTypeKey == 'minecraft:player')
        continue;
      final entity = world.getEntityById(id: snapshot.id);
      if (entity == null || entity.pluginTypeKey == 'create:package') continue;
      await entity.teleport(
        pos: (this.pos.x + .5, this.pos.y + 1.0, this.pos.z + .5),
        worldRef: world,
      );
      entity.setVelocity(velocity: launcher.motionFor(facing));
    }
  }

  /// `launchItems`.
  Future<void> launchItems() async {
    final facing = getFacing().opposite;
    final above = this.pos.toPos().above;
    if (funnelFacing(stateAt(above)) == facing) {
      final funnel = rt.typedAt<FunnelBlockEntity>(worldId, above);
      // `directOutput.tryExportingToBeltFunnel(stack, funnelFacing, false)`: `null` means the
      // funnel above refuses outright (not a pulling belt funnel, or no block entity), and the
      // stack stays put. Either way a funnel above ends the launch attempt.
      Future<ItemValue?> exportToFunnel(ItemValue stack) async => funnel == null
          ? null
          : await funnel.tryExportingToBeltFunnel(
              stack,
              facing,
              simulate: false,
            );
      final held = depotBehaviour.heldItem;
      if (held != null) {
        final remainder = await exportToFunnel(held.stack);
        if (remainder != null) {
          if (remainder.isEmpty) {
            depotBehaviour.removeHeldItem();
          } else if (remainder.count != held.stack.count) {
            held.stack = remainder;
          }
        }
      }
      for (final ts in List.of(depotBehaviour.incoming)) {
        final stack = ts.stack;
        final remainder = await exportToFunnel(stack);
        if (remainder == null) continue;
        if (remainder.isEmpty) {
          depotBehaviour.incoming.remove(ts);
        } else if (remainder.count != stack.count) {
          ts.stack = remainder;
        }
      }
      for (
        var slot = 0;
        slot < depotBehaviour.processingOutputBuffer.slots;
        slot++
      ) {
        final stack = depotBehaviour.processingOutputBuffer.getStack(slot);
        if (stack.isEmpty) continue;
        final remainder = await exportToFunnel(stack);
        if (remainder != null) {
          depotBehaviour.processingOutputBuffer.setStack(slot, remainder);
        }
      }
      return;
    }

    // Non-funnel launch: vanilla observers aimed at the ejector see a change
    // (`ObserverBlock.updateShape` from the side that faces the ejector). The host's
    // `updateShapeAround` is exactly that shape update sent to the six neighbours.
    final world = this.world;
    if (world != null) {
      var notifiesObserver = false;
      for (final d in Direction.values) {
        final neighbour = this.pos.toPos().relative(d);
        final neighbourState = stateAt(neighbour);
        if (neighbourState.key != 'minecraft:observer') continue;
        if (neighbourState.dir('facing') != d.opposite) continue;
        notifiesObserver = true;
      }
      if (notifiesObserver) {
        await world.updateShapeAround(pos: this.pos);
      }
    }

    final held = depotBehaviour.heldItem;
    if (held != null) {
      _addToLaunched(held.stack);
      depotBehaviour.removeHeldItem();
    }
    for (final ts in depotBehaviour.incoming) {
      _addToLaunched(ts.stack);
    }
    depotBehaviour.incoming.clear();
    for (
      var slot = 0;
      slot < depotBehaviour.processingOutputBuffer.slots;
      slot++
    ) {
      final extracted = depotBehaviour.processingOutputBuffer.extract(slot, 64);
      if (extracted.isNotEmpty) _addToLaunched(extracted);
    }
    depotBehaviour.owner.markDirty();
    depotBehaviour.owner.sendData();
  }

  bool _addToLaunched(ItemValue stack) {
    if (trackedItem == null && scanCooldown == 0) {
      scanCooldown = rt.ejectorScanInterval;
      trackedItem = stack;
    }
    _launchedItems.add(_Launched(stack));
    return true;
  }

  /// `ejectIfTriggered`.
  Future<void> ejectIfTriggered() async {
    if (powered) return;
    final present = depotBehaviour.getPresentStackSize();
    if (present == 0) return;
    if (present < maxStackSize.value) return;
    final held = depotBehaviour.heldItem;
    if (held != null && held.beltPosition < .49) return;

    final facing = getFacing().opposite;
    if (funnelFacing(stateAt(this.pos.toPos().above)) == facing &&
        held != null) {
      final funnel = rt.typedAt<FunnelBlockEntity>(
        worldId,
        this.pos.toPos().above,
      );
      final remainder = funnel == null
          ? null
          : await funnel.tryExportingToBeltFunnel(
              held.stack,
              facing,
              simulate: true,
            );
      // `tryFunnel == null || !tryFunnel.isEmpty()`: the funnel would not take everything.
      if (remainder == null || remainder.isNotEmpty) return;
    }

    final target = getTargetDirectInput();
    if (target != null && held != null) {
      final remainder = await target.handleInsertion(
        TransportedItemStack(held.stack),
        Direction.up,
        simulate: true,
      );
      if (remainder.count == held.stack.count) return;
    }

    activate();
    markDirty();
    sendData();
  }

  // -- Target ----------------------------------------------------------------------------------

  Pos getTargetPos() => this.pos
      .toPos()
      .aboveBy(launcher.verticalDistance)
      .relative(getFacing(), math.max(1, launcher.horizontalDistance));

  /// `getTargetOpenInv`: the direct belt input of the block the ejector aims at. Machines that
  /// expose the behaviour rather than implementing [DirectBeltInput] are adapted like funnels do.
  DirectBeltInput? getTargetDirectInput() {
    final be = rt.beAt(worldId, getTargetPos());
    if (be is DirectBeltInput) return be as DirectBeltInput;
    final behaviour = be?.getBehaviour<pt.DirectBeltInputBehaviour>();
    return behaviour == null ? null : DirectInputAdapter(behaviour);
  }

  Future<void> placeItemAtTarget(double maxTime, _Launched entry) async {
    if (entry.stack.isEmpty) return;
    final target = getTargetDirectInput();
    if (target != null) {
      final remainder = await target.handleInsertion(
        TransportedItemStack(entry.stack),
        Direction.up,
        simulate: false,
      );
      entry.stack = remainder;
    }
    if (entry.stack.isEmpty) return;

    final world = this.world;
    if (world == null) return;
    final at = launcher.getGlobalPos(
      maxTime,
      getFacing().opposite,
      this.pos.toPos(),
    );
    final motion = launcher.getGlobalVelocity(
      maxTime,
      getFacing().opposite,
      this.pos.toPos(),
    );
    await spawnItemEntity(
      world,
      at,
      entry.stack,
      velocity: (motion.$1 * .5, motion.$2 * .5, motion.$3 * .5),
    );
  }

  /// `getWindUpSpeed`.
  double getWindUpSpeed() {
    final hd = launcher.getHorizontalDistance();
    final vd = launcher.getVerticalDistance();
    final speedFactor = speed.abs() / 256;
    final distanceFactor = (hd == 0 && vd == 0)
        ? 1.0
        : math.sqrt(hd * hd + vd * vd).toDouble();
    return speedFactor / distanceFactor;
  }

  /// `updateSignal`.
  Future<void> updateSignal() async {
    final world = this.world;
    if (world == null) return;
    final shouldPower = await world.hasRedstoneNeighborSignal(this.pos);
    if (shouldPower == powered) return;
    powered = shouldPower;
    sendData();
  }

  /// `setTarget`.
  void setTarget(int horizontalDistance, int verticalDistance) {
    launcher.set(math.max(1, horizontalDistance), verticalDistance);
    sendData();
  }

  /// `deployElytra`: `EntityHack.setElytraFlying` sets the shared fall-flying flag. The client
  /// sends this after it launched the player off the ejector (`EjectorElytraPacket`).
  void deployElytra(Player player) {
    final entity = player.asEntity();
    try {
      entity.setFallFlying(fallFlying: true);
    } finally {
      entity.dispose();
    }
  }

  /// `EjectorAwardPacket.applySettings`: `AllAdvancements.EJECTOR_MAXED.awardTo(player)`. The
  /// player handle of a payload handler is only valid until the handler yields, so keep it for
  /// the asynchronous award.
  void awardMaxed(Player player) {
    final kept = player.keep();
    unawaited(
      rt.award(kept, 'ejector_maxed').whenComplete(() {
        try {
          kept.dispose();
        } on Object {
          // already invalid
        }
      }),
    );
  }

  /// `getTargetPosition`.
  Pos getTargetPosition() => getTargetPos();

  @override
  void onRemoved() {
    final world = this.world;
    if (world != null) {
      final facing = getFacing().opposite;
      for (final entry in _launchedItems) {
        final at = launcher.getGlobalPos(
          entry.time.toDouble(),
          facing,
          this.pos.toPos(),
        );
        final motion = launcher.getGlobalVelocity(
          entry.time.toDouble(),
          facing,
          this.pos.toPos(),
        );
        rt.fire(
          'Dropping a launched item',
          () => spawnItemEntity(
            world,
            at,
            entry.stack,
            velocity: (motion.$1 * .5, motion.$2 * .5, motion.$3 * .5),
          ),
        );
      }
    }
    _launchedItems.clear();
    super.onRemoved();
  }

  // -- Persistence -----------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag
      ..putInt('HorizontalDistance', launcher.getHorizontalDistance())
      ..putInt('VerticalDistance', launcher.getVerticalDistance())
      ..putBool('Powered', powered)
      // `State.name()` is the upper-case constant.
      ..putString('State', enumNbtName(_state.name))
      // `Lid` is the `LerpedFloat` compound (`{Speed, Target, Value}`).
      ..putCompound(
        'Lid',
        NbtCompound()
          ..putFloat('Speed', _lidSpeed)
          ..putFloat('Target', _lidTarget)
          ..putFloat('Value', lidProgress),
      )
      // `IntAttached.serializeNBT`: `{Item, Location}`.
      ..putList('LaunchedItems', [
        for (final entry in _launchedItems)
          NbtCompound()
            ..putCompound(
              'Item',
              ItemCodec.toTag(entry.stack, clientPacket: clientPacket),
            )
            ..putInt('Location', entry.time),
      ]);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    final hd = tag.getInt('HorizontalDistance') ?? 0;
    final vd = tag.getInt('VerticalDistance') ?? 0;
    if (launcher.getHorizontalDistance() != hd ||
        launcher.getVerticalDistance() != vd) {
      launcher.set(hd, vd);
      launcher.clamp(rt.maxEjectorDistance);
    }
    powered = tag.getBool('Powered') ?? false;
    final stateName = tag.getString('State');
    // Java's `readState` falls back to the first constant (`CHARGED`).
    _state = enumFromNbtName(stateName, _EjectorState.values);
    final lid = tag.getCompound('Lid');
    if (lid != null) {
      lidProgress = lid.getDouble('Value') ?? 0;
      _lidTarget = lid.getDouble('Target') ?? lidProgress;
      _lidSpeed = lid.getDouble('Speed') ?? 0;
    } else {
      lidProgress = tag.getDouble('Lid') ?? 0; // legacy float form
      _lidTarget = lidProgress;
      _lidSpeed = 0;
    }
    _launchedItems
      ..clear()
      ..addAll([
        for (final e in tag.getList('LaunchedItems') ?? const <Object>[])
          if (e is NbtCompound)
            _Launched(
              ItemCodec.fromAnyNbt(e.getCompound('Item')),
              e.getInt('Location') ?? 0,
            ),
      ]);
  }
}

final class _Launched {
  ItemValue stack;
  int time;

  _Launched(this.stack, [this.time = 0]);
}
