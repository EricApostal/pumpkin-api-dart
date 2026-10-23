// The kinetic node: the part of Create's `KineticBlockEntity` that the network
// and the propagator talk to, written without host imports. The block entity
// (`kinetic_block_entity.dart`) mixes [KineticNodeMixin] into the framework's
// block entity; the unit tests mix it into a fake.
import 'block_defs.dart';
import 'geometry.dart';
import 'network.dart';
import 'propagator.dart';
import 'sequence.dart';
import 'settings.dart';

/// The registry of [KineticBlockDef]s by block key (`IRotate` implementors).
final class KineticBlockRegistry {
  final Map<String, KineticBlockDef> _defs = {};

  /// Block keys that are encased chain drives (`ChainDriveBlock` and subclasses).
  final Set<String> chainDriveBlocks = {};

  /// The blocks whose definition belongs to *another* component, by block key,
  /// with the plugin that owns them (`create.kinetics`, see `foreign.dart`).
  ///
  /// The owner runs one network for every component, so it also holds the rules
  /// of the addons' blocks; a block in here is one whose block entity lives in
  /// another wasm instance.
  final Map<String, String> _foreign = {};

  /// Registers (or replaces) the definition of [block] (`create:shaft`).
  void register(String block, KineticBlockDef def) => _defs[block] = def;

  /// Registers the definition of a block of another component and the plugin
  /// that owns it, so the propagation materialises its block entity as a
  /// `ForeignKineticNode` instead of looking it up in this component's store.
  void registerForeign(String block, KineticBlockDef def, String plugin) {
    _defs[block] = def;
    _foreign[block] = plugin;
  }

  /// The plugin that owns [block], `null` when this component does.
  String? ownerOf(String block) => _foreign[block];

  bool isForeign(String block) => _foreign.containsKey(block);

  KineticBlockDef? defOf(String block) => _defs[block];

  /// The definition of the block of [state], `null` if it is not an `IRotate`.
  KineticBlockDef? defFor(KState state) => _defs[state.block];

  /// `ICogWheel.isSmallCog(state)`.
  bool isSmallCog(KState state) => defFor(state)?.isSmallCog ?? false;

  /// `ICogWheel.isLargeCog(state)`.
  bool isLargeCog(KState state) => defFor(state)?.isLargeCog ?? false;

  bool isChainDrive(KState state) => chainDriveBlocks.contains(state.block);

  Iterable<String> get blocks => _defs.keys;
}

/// What the kinetic logic needs from a world; the host implementation reads the
/// block entity store and the world, tests use a map.
abstract class KineticLevel {
  /// The networks of this world by id (`TorquePropagator.networks`).
  final Map<int, KineticNetwork> networks = {};

  KineticConfig get settings;
  KineticBlockRegistry get blocks;
  StressSource get stress;

  /// The kinetic block entity at [pos], `null` if there is none or it is not loaded.
  KineticNode? nodeAt(KPos pos);

  /// The block state at [pos] (air when unloaded).
  KState stateAt(KPos pos);

  bool isLoaded(KPos pos);

  /// `level.destroyBlock(pos, true)`.
  void destroyBlock(KPos pos);

  /// Whether another component runs the kinetic network of this world.
  ///
  /// A plugin that links `package:create` but is not Create runs its own
  /// `KineticsRuntime` with no Create blocks in it, so a network built here
  /// would be a second, partial truth. When an owner is loaded, this is `true`
  /// and the block entities of this component announce themselves to it instead
  /// (`foreign.dart`).
  bool get hosted => false;

  /// This component's node at [pos] appeared: the owner has to include it in
  /// the network (no-op when [hosted] is `false`, i.e. this component owns it).
  void nodeAttached(KineticNode node) {}

  /// This component's node at [pos] is gone.
  void nodeDetached(KineticNode node) {}

  /// The node's own values changed and the owner has to be told (a generator's
  /// `generatedSpeed`, a source that changed its stress).
  void nodeChanged(KineticNode node) {}

  /// `level.tickRateManager().isFrozen()`.
  bool get isTickFrozen => false;

  /// `TorquePropagator.getOrCreateNetworkFor`.
  KineticNetwork? getOrCreateNetworkFor(KineticNode node) {
    final id = node.network;
    if (id == null) return null;
    return networks.putIfAbsent(id, () => KineticNetwork(this, id));
  }

  /// Forgets all networks (world unload).
  void clearNetworks() => networks.clear();

  /// Starts a batch of reads: until [endBatch] the level may serve repeated reads of the same
  /// position from a cache. The rotation propagator reads every neighbour of every node it visits,
  /// so one pass asks for the same position many times and each read is a host call. The default
  /// keeps no cache.
  void beginBatch() {}

  /// Ends the batch started by [beginBatch]; drops whatever it cached.
  void endBatch() {}
}

/// The speed controller side of the propagation (`SpeedControllerBlockEntity`).
abstract interface class SpeedControllerNode {
  /// The configured target speed (`targetSpeed.getValue()`).
  int get targetSpeedValue;
}

/// `ChainGearshiftBlockEntity.getModifier()`.
abstract interface class ChainModifierNode {
  double get chainModifier;
}

/// A kinetic block entity as the network sees it.
abstract interface class KineticNode {
  KPos get kpos;
  KineticLevel get level;

  /// The block state of the block entity (cached while it is being removed).
  KState get blockState;

  int? get network;
  KPos? get source;
  bool get networkDirty;
  set networkDirty(bool value);

  /// Applies the verdict the component that runs the network sent for this node
  /// (`create.kinetics`, the `apply` push): the network's speed, source, stress
  /// and capacity. Only the cross-component path calls it; a local propagation
  /// sets those values itself.
  ///
  /// Default: what a local propagation would have done with the numbers, minus
  /// the table maintenance the owner already did (no `networkDirty` flip, no
  /// re-sync). The block behaviours hang off `onSpeedChanged`, so this runs it
  /// exactly as a local propagation would — a bearing that starts turning
  /// assembles, a propeller's discs spin up.
  void applyNetworkVerdict(ForeignVerdictValues verdict);

  /// `getSpeed()`: 0 while overstressed.
  double get speed;

  /// `getTheoreticalSpeed()`.
  double get theoreticalSpeed;

  void setSpeed(double speed);

  /// `getGeneratedSpeed()`.
  double get generatedSpeed;

  bool get isSource;
  bool get hasSource;
  bool get hasNetwork;
  int get flickerScore;

  double calculateStressApplied();
  double calculateAddedStressCapacity();

  void updateFromNetwork(
    double maxStress,
    double currentStress,
    int networkSize,
  );
  void onSpeedChanged(double previousSpeed);
  void setSource(KPos source);
  void removeSource();
  void sendData();

  /// `getOrCreateNetwork()`.
  KineticNetwork? getOrCreateNetwork();

  /// `KineticBlockEntity.propagateRotationTo`.
  double propagateRotationTo(
    KineticNode target,
    KState stateFrom,
    KState stateTo,
    KPos diff,
    bool connectedViaAxes,
    bool connectedViaCogs,
  );

  /// `addPropagationLocations`.
  List<KPos> addPropagationLocations(
    KineticBlockDef block,
    KState state,
    List<KPos> neighbours,
  );

  /// `isCustomConnection`.
  bool isCustomConnection(KineticNode other, KState state, KState otherState);

  /// `RotationPropagator.getAxisModifier` for gearboxes and split shafts: the
  /// factor between [direction] and the source side. 1 for other blocks.
  double shaftHalvesModifier(Dir direction) => 1;

  /// The context of a sequenced gearshift this node is driven by.
  SequenceContext? get sequenceContext;
}

/// The verdict the component that runs the network sends for one node of another
/// component (`create.kinetics`' `apply` push): the `ForeignNodeVerdict` fields
/// as data (`foreign.dart`).
final class ForeignVerdictValues {
  final double speedValue;
  final KPos? source;
  final int? network;
  final double capacity;
  final double stress;
  final int networkSize;
  final bool overStressed;

  const ForeignVerdictValues({
    required this.speedValue,
    required this.source,
    required this.network,
    required this.capacity,
    required this.stress,
    required this.networkSize,
    required this.overStressed,
  });
}

/// The shared logic of every kinetic block entity. Requires [pos], [level],
/// [blockState], [sendData], [markChanged].
mixin KineticNodeMixin implements KineticNode {
  // -- Fields (names as in Java) --------------------------------------------------
  @override
  int? network;
  @override
  KPos? source;
  @override
  bool networkDirty = false;

  /// `updateSpeed`: the block entity still has to attach to its neighbours.
  bool updateSpeed = true;
  int preventSpeedUpdate = 0;

  double speedValue = 0;
  double capacity = 0;
  double stress = 0;
  bool overStressed = false;
  bool wasMoved = false;
  int flickerTally = 0;
  int networkSize = 0;
  int validationCountdown = 0;
  double lastStressApplied = 0;
  double lastCapacityProvided = 0;
  @override
  SequenceContext? sequenceContext;

  /// Called whenever the persistent state changed (`setChanged`).
  void markChanged();

  // -- Speed ----------------------------------------------------------------------
  @override
  double get generatedSpeed => 0;

  @override
  bool get isSource => generatedSpeed != 0;

  @override
  double get speed {
    if (overStressed || level.isTickFrozen) return 0;
    return theoreticalSpeed;
  }

  @override
  double get theoreticalSpeed => speedValue;

  @override
  void setSpeed(double speed) => speedValue = speed;

  @override
  bool get hasSource => source != null;

  @override
  bool get hasNetwork => network != null;

  @override
  int get flickerScore => flickerTally;

  bool get isOverStressed => overStressed;

  /// `needsSpeedUpdate()`.
  bool get needsSpeedUpdate => updateSpeed;

  /// The block key whose stress values apply (`getStressConfigKey`).
  String get stressConfigKey => blockState.block;

  @override
  double calculateStressApplied() {
    final impact = level.stress.impact(stressConfigKey);
    lastStressApplied = impact;
    return impact;
  }

  @override
  double calculateAddedStressCapacity() {
    final cap = level.stress.capacity(stressConfigKey);
    lastCapacityProvided = cap;
    return cap;
  }

  @override
  KineticNetwork? getOrCreateNetwork() => level.getOrCreateNetworkFor(this);

  // -- Lifecycle (the block entity calls these) ------------------------------------

  /// `initialize()`: joins the saved network.
  void kineticInitialize() {
    // The saved `Network`/`Speed` of this component's block entity came from the
    // component that runs the network, and there is no local table to join.
    if (level.hosted) return;
    if (hasNetwork) {
      final net = getOrCreateNetwork()!;
      if (!net.initialized) net.initFromTE(capacity, stress, networkSize);
      net.addSilently(this, lastCapacityProvided, lastStressApplied);
    }
  }

  /// The start of `tick()`, before the base class ticks.
  void kineticTickStart() {
    if (needsSpeedUpdate) attachKinetics();
  }

  /// The rest of `tick()`, after the base class ticked.
  void kineticTickEnd() {
    preventSpeedUpdate = 0;

    // The verdicts the owner sends already carry the network the node belongs
    // to, so there is no local network to sync or validate here.
    if (level.hosted) return;

    if (validationCountdown-- <= 0) {
      validationCountdown = level.settings.kineticValidationFrequency;
      validateKinetics();
    }

    if (flickerScore > 0) flickerTally = flickerScore - 1;

    if (networkDirty) {
      if (hasNetwork) getOrCreateNetwork()?.updateNetwork();
      networkDirty = false;
    }
  }

  void validateKinetics() {
    if (hasSource) {
      if (!hasNetwork) {
        removeSource();
        return;
      }
      final src = source!;
      if (!level.isLoaded(src)) return;
      final sourceBE = level.nodeAt(src);
      // Java compares the protected `speed` field (the theoretical speed), not
      // `getSpeed()`: an overstressed source still drives its network.
      if (sourceBE == null || sourceBE.theoreticalSpeed == 0) {
        removeSource();
        detachKinetics();
        return;
      }
      return;
    }

    if (speedValue != 0) {
      if (generatedSpeed == 0) speedValue = 0;
    }
  }

  /// The verdict the component that runs the network sent (see [KineticNode]).
  @override
  void applyNetworkVerdict(ForeignVerdictValues verdict) {
    final previousSpeed = speed;
    speedValue = verdict.speedValue;
    source = verdict.source;
    network = verdict.network;
    capacity = verdict.capacity;
    stress = verdict.stress;
    networkSize = verdict.networkSize;
    networkDirty = false;
    final over = verdict.overStressed && !level.settings.disableStress;
    final speedChanged = previousSpeed != speed;
    overStressed = over;
    // The block behaviours hang off `onSpeedChanged` (a swivel bearing assembles,
    // a propeller's discs spin up), so the peer runs it exactly as a local
    // propagation would.
    if (speedChanged) onSpeedChanged(previousSpeed);
    markChanged();
    if (speedChanged) sendData();
  }

  @override
  void updateFromNetwork(
    double maxStress,
    double currentStress,
    int networkSize,
  ) {
    networkDirty = false;
    capacity = maxStress;
    stress = currentStress;
    this.networkSize = networkSize;
    final over = maxStress < currentStress && !level.settings.disableStress;
    markChanged();

    if (over != overStressed) {
      final prevSpeed = speed;
      overStressed = over;
      onSpeedChanged(prevSpeed);
      sendData();
    }
  }

  @override
  void onSpeedChanged(double previousSpeed) {
    final fromOrToZero = (previousSpeed == 0) != (speed == 0);
    final directionSwap = !fromOrToZero && previousSpeed.sign != speed.sign;
    if (fromOrToZero || directionSwap) flickerTally = flickerScore + 5;
    markChanged();
  }

  /// `remove()`: the block is gone, leave the network.
  void kineticRemove() {
    // A component that does not own the network: the owner is told and drops the
    // node, and there is no local table to leave (`foreign.dart`).
    if (level.hosted) {
      level.nodeDetached(this);
      return;
    }
    if (hasNetwork) getOrCreateNetwork()?.remove(this);
    detachKinetics();
  }

  @override
  void setSource(KPos source) {
    this.source = source;
    final sourceBE = level.nodeAt(source);
    if (sourceBE == null) {
      removeSource();
      return;
    }
    setNetwork(sourceBE.network);
    copySequenceContextFrom(sourceBE);
  }

  void copySequenceContextFrom(KineticNode sourceBE) {
    sequenceContext = sourceBE.sequenceContext;
  }

  @override
  void removeSource() {
    final prevSpeed = speed;
    speedValue = 0;
    source = null;
    setNetwork(null);
    sequenceContext = null;
    onSpeedChanged(prevSpeed);
  }

  void setNetwork(int? networkIn) {
    if (network == networkIn) return;
    if (network != null) getOrCreateNetwork()?.remove(this);

    network = networkIn;
    markChanged();

    if (networkIn == null) return;

    final net = getOrCreateNetwork()!;
    net.initialized = true;
    net.add(this);
  }

  void attachKinetics() {
    updateSpeed = false;
    // A component that does not own the network does not propagate: it announces
    // the node to the component that does (`foreign.dart`).
    if (level.hosted) {
      level.nodeAttached(this);
      return;
    }
    RotationPropagator.handleAdded(level, kpos, this);
  }

  void detachKinetics() {
    if (level.hosted) {
      level.nodeDetached(this);
      return;
    }
    RotationPropagator.handleRemoved(level, kpos, this);
  }

  /// `RotationPropagator.handleAdded(level, pos, this)` without the `updateSpeed` flag.
  void handleAdded() {
    RotationPropagator.handleAdded(level, kpos, this);
  }

  /// `isSpeedRequirementFulfilled()`.
  bool get isSpeedRequirementFulfilled {
    final def = level.blocks.defFor(blockState);
    if (def == null) return true;
    return speed.abs() >=
        def.minimumRequiredSpeedLevel.speedValue(level.settings);
  }

  /// `clearKineticInformation()`.
  void clearKineticInformation() {
    speedValue = 0;
    source = null;
    network = null;
    overStressed = false;
    stress = 0;
    capacity = 0;
    lastStressApplied = 0;
    lastCapacityProvided = 0;
  }

  void warnOfMovement() => wasMoved = true;

  /// `effects.queueRotationIndicators()`: the host block entity spawns the particles.
  void queueRotationIndicators() {}

  // -- Customisation points ------------------------------------------------------------
  @override
  double propagateRotationTo(
    KineticNode target,
    KState stateFrom,
    KState stateTo,
    KPos diff,
    bool connectedViaAxes,
    bool connectedViaCogs,
  ) => 0;

  @override
  List<KPos> addPropagationLocations(
    KineticBlockDef block,
    KState state,
    List<KPos> neighbours,
  ) {
    if (!canPropagateDiagonally(block, state)) return neighbours;
    final axis = block.rotationAxis(state);
    for (var z = -1; z <= 1; z++) {
      for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
          if (axis.choose(x, y, z) != 0) continue;
          if (x * x + y * y + z * z != 2) continue;
          neighbours.add(kpos.offset(x, y, z));
        }
      }
    }
    return neighbours;
  }

  @override
  bool isCustomConnection(KineticNode other, KState state, KState otherState) =>
      false;

  bool canPropagateDiagonally(KineticBlockDef block, KState state) =>
      block.isSmallCog;

  @override
  double shaftHalvesModifier(Dir direction) => 1;
}
