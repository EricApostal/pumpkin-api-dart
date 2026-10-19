// `KineticBlockEntity`, `GeneratingKineticBlockEntity` and the small base classes
// every kinetic block entity of every module builds on. The logic is in the pure
// mixins (`node.dart`, `generating.dart`); this adds the framework glue: the
// NBT Create's client reads, ticking, the world view.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/block_entity.dart';
import '../api/particles.dart';
import 'block_defs.dart';
import 'generating.dart';
import 'geometry.dart';
import 'node.dart';
import 'runtime.dart';
import 'sequence.dart';
import 'settings.dart';

/// Base of every kinetic block entity (shafts, machines, belts, ...).
///
/// Override the hooks, not the lifecycle: [getGeneratedSpeed]-style getters
/// ([generatedSpeed]), [calculateStressApplied], [onSpeedChanged],
/// [propagateRotationTo], [isCustomConnection], [addPropagationLocations] and
/// [onKineticInitialize]. [speed] is 0 while overstressed, [theoreticalSpeed]
/// is the speed of the network.
class KineticBlockEntity extends CreateBlockEntity with KineticNodeMixin {
  KineticBlockEntity(super.worldId, super.pos);

  bool _kineticInitialized = false;
  KState? _cachedState;
  int _cachedStateId = -1;
  KPos? _kpos;

  /// The settings, block rules and stress table.
  KineticsRuntime get runtime => KineticsRuntime.instance;

  @override
  KPos get kpos => _kpos ??= KPos(pos.x, pos.y, pos.z);

  @override
  HostKineticLevel get level => runtime.level(worldId);

  /// The block state of this block entity. While the entity is being removed
  /// (the block is already gone) it is the last state seen, as in Java where
  /// `getBlockState()` is cached by the block entity.
  @override
  KState get blockState {
    final w = world;
    if (w != null && !removed) {
      final id = w.getBlockStateId(pos: pos);
      if (id != _cachedStateId) {
        final s = runtime.states.decode(id);
        if (_acceptsState(s) || _cachedState == null) {
          _cachedStateId = id;
          _cachedState = s;
        }
      }
    }
    return _cachedState ?? KState.air;
  }

  bool _acceptsState(KState s) {
    if (runtime.blocks.defOf(s.block) != null) return true;
    final spec = store.typeSpec(typeKey);
    return spec != null && spec.validBlocks.contains(s.block);
  }

  /// The state as last seen (also after the block entity was removed).
  KState? get lastKnownState => _cachedState;

  /// The block key of the current state's block.
  String get blockKey => blockState.block;

  @override
  void markChanged() => markDirty();

  // -- Lifecycle ----------------------------------------------------------------

  /// Runs once, in the first tick after the entity attached to its neighbours and
  /// joined its saved network (the place of Java's `initialize()` override).
  void onKineticInitialize() {}

  @override
  void tick() {
    kineticTickStart();
    if (!_kineticInitialized) {
      _kineticInitialized = true;
      kineticInitialize();
      lazyTick(); // SmartBlockEntity.initialize ends with a lazy tick
      onKineticInitialize();
      if (speedValue != 0 || hasNetwork) sendData();
    }
    super.tick();
    if (_particleCountdown > 0 && --_particleCountdown == 0) spawnRotationIndicators();
    kineticTickEnd();
  }

  @override
  void onRemoved() {
    super.onRemoved();
    kineticRemove();
  }

  int _particleCountdown = 0;

  /// `KineticEffectHandler.queueRotationIndicators`: the particles show the rotation
  /// direction and speed level in two ticks.
  @override
  void queueRotationIndicators() => _particleCountdown = 2;

  /// `KineticEffectHandler.spawnRotationIndicators`.
  void spawnRotationIndicators() {
    final s = speed;
    if (s == 0) return;
    final state = blockState;
    final def = runtime.blocks.defFor(state);
    final w = world;
    if (def == null || w == null) return;
    final axis = def.rotationAxis(state);
    final (radius1, radius2) = rotationIndicatorRadii(state.block);
    final level = SpeedLevel.of(s, runtime.settings);
    final particleSpeed = level.particleSpeed * s.sign;
    try {
      w.spawnPluginParticleAt(
        'create:rotation_indicator',
        (pos.x + .5, pos.y + .5, pos.z + .5),
        speed: 1,
        count: 20,
        options: CreateParticleOptions.rotationIndicator(
          color: level.color,
          speed: particleSpeed,
          radius1: radius1,
          radius2: radius2,
          lifeSpan: 10,
          axisOrdinal: axis.index,
        ),
      );
    } on HostException catch (e) {
      runtime.log.debug('Rotation indicators could not be spawned: ${e.message}');
    }
  }

  /// `remove()` for a block entity that stays in the store but whose block
  /// changed (a different block of the same type took its place).
  void resetForNewBlock() {
    kineticRemove();
    clearKineticInformation();
    updateSpeed = true;
    _kineticInitialized = false;
    _cachedStateId = -1;
    _cachedState = null;
  }

  // -- NBT (the format Create's client reads) --------------------------------------

  /// Whether the sequence context is sent to the client (`syncSequenceContext`).
  bool get syncSequenceContext => false;

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putFloat('Speed', speedValue);
    final seq = sequenceContext;
    if (seq != null && (!clientPacket || syncSequenceContext)) {
      tag.putCompound(
        'Sequence',
        NbtCompound()
          ..putString('Mode', seq.instruction.javaName)
          ..putDouble('Value', seq.relativeValue),
      );
    }
    if (needsSpeedUpdate) tag.putBool('NeedsSpeedUpdate', true);

    final src = source;
    if (src != null) tag.putIntArray('Source', [src.x, src.y, src.z]);

    final id = network;
    if (id != null) {
      final net = NbtCompound()
        ..putLong('Id', id)
        ..putFloat('Stress', stress)
        ..putFloat('Capacity', capacity)
        ..putInt('Size', networkSize);
      if (lastStressApplied != 0) net.putFloat('AddedStress', lastStressApplied);
      if (lastCapacityProvided != 0) net.putFloat('AddedCapacity', lastCapacityProvided);
      tag.putCompound('Network', net);
    }
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    clearKineticInformation();

    // Do not read kinetic information when placed after movement.
    if (wasMoved) {
      super.read(tag, clientPacket: clientPacket);
      return;
    }

    speedValue = tag.getDouble('Speed') ?? 0;
    final seq = tag.getCompound('Sequence');
    sequenceContext = seq == null
        ? null
        : SequenceContext(
            SequencerInstructions.fromJavaName(seq.getString('Mode')),
            seq.getDouble('Value') ?? 0,
          );

    source = null;
    final srcArr = tag.getIntArray('Source');
    if (srcArr != null && srcArr.length >= 3) source = KPos(srcArr[0], srcArr[1], srcArr[2]);

    final net = tag.getCompound('Network');
    if (net != null) {
      network = net.getInt('Id') ?? 0;
      stress = net.getDouble('Stress') ?? 0;
      capacity = net.getDouble('Capacity') ?? 0;
      networkSize = net.getInt('Size') ?? 0;
      lastStressApplied = net.getDouble('AddedStress') ?? 0;
      lastCapacityProvided = net.getDouble('AddedCapacity') ?? 0;
      overStressed = capacity < stress && !runtime.settings.disableStress;
    }

    super.read(tag, clientPacket: clientPacket);
  }

  // -- Utilities -------------------------------------------------------------------

  /// Sets the block state of this block (fire and forget, errors are logged).
  /// Flags default to a normal block change.
  void setStateAsync(KState state, {Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal}) {
    final w = world;
    final id = runtime.states.idOf(state);
    if (w == null || id == null) return;
    unawaited(
      w.setBlockState(pos: pos, state: id, updateFlags: flags).catchError((Object e, StackTrace st) {
        runtime.log.error('Setting the state of $this failed', error: e, stackTrace: st);
      }),
    );
  }

  /// `KineticBlockEntity.switchToBlockState` for a block at [bePos]: changes the
  /// block state, detaching this entity from the network first when the new
  /// state is not kinetically equivalent. Returns when the world was changed.
  Future<void> switchToState(KState state) =>
      KineticOps.switchToBlockState(runtime, worldId, pos, state);

  @override
  String toString() => '$typeKey@${pos.x},${pos.y},${pos.z}';
}

/// The block entity of generators: speed sources.
abstract class GeneratingKineticBlockEntity extends KineticBlockEntity with GeneratingNodeMixin {
  GeneratingKineticBlockEntity(super.worldId, super.pos);

  @override
  void tick() {
    super.tick();
    generatingTick();
  }
}

/// `SimpleKineticBlockEntity`: large cogwheels also connect over the twelve edge diagonals.
class SimpleKineticBlockEntity extends KineticBlockEntity {
  SimpleKineticBlockEntity(super.worldId, super.pos);

  @override
  List<KPos> addPropagationLocations(KineticBlockDef block, KState state, List<KPos> neighbours) {
    if (!block.isLargeCog) return super.addPropagationLocations(block, state, neighbours);
    for (var z = -1; z <= 1; z++) {
      for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
          if (x * x + y * y + z * z == 2) neighbours.add(kpos.offset(x, y, z));
        }
      }
    }
    return neighbours;
  }
}

/// `DirectionalShaftHalvesBlockEntity`: gearboxes and split shafts.
class DirectionalShaftHalvesBlockEntity extends KineticBlockEntity {
  DirectionalShaftHalvesBlockEntity(super.worldId, super.pos);

  /// The direction of the source relative to this block (`getSourceFacing`).
  Dir get sourceFacing {
    final s = source ?? kpos;
    final local = s - kpos;
    return Dir.approximateNearest(local.x, local.y, local.z);
  }
}

/// Operations on kinetic blocks that need the world.
abstract final class KineticOps {
  /// `KineticBlockEntity.switchToBlockState`.
  static Future<void> switchToBlockState(KineticsRuntime rt, String worldId, BlockPos pos, KState state) async {
    final world = rt.worlds.byId(worldId);
    if (world == null) return;
    final level = rt.level(worldId);
    final kpos = toKPos(pos);
    final current = level.stateAt(kpos);
    if (current == state) return;
    final id = rt.states.idOf(state);
    if (id == null) return;

    final node = level.nodeAt(kpos);
    if (node is! KineticBlockEntity) {
      await world.setBlockState(pos: pos, state: id, updateFlags: BlockUpdateFlags.normal);
      return;
    }

    final newDef = rt.blocks.defFor(state);
    if (newDef != null && !newDef.areStatesKineticallyEquivalent(current, state)) {
      if (node.hasNetwork) node.getOrCreateNetwork()?.remove(node);
      node.detachKinetics();
      node.removeSource();
    }

    if (node case final GeneratingNodeMixin g) g.reActivateSource = true;

    await world.setBlockState(pos: pos, state: id, updateFlags: BlockUpdateFlags.normal);
  }
}
