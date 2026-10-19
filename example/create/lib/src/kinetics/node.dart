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

  /// Registers (or replaces) the definition of [block] (`create:shaft`).
  void register(String block, KineticBlockDef def) => _defs[block] = def;

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
    RotationPropagator.handleAdded(level, kpos, this);
  }

  void detachKinetics() {
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
