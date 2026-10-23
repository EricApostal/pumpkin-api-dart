// The kinetic blocks of *another* component, as the component that owns the
// network sees them.
//
// A Pumpkin server runs every plugin in its own wasm instance and each plugin
// compiles its own copy of `package:create`, so `KineticsRuntime` — and with it
// the block entity store, the block registry and the per-level network map — is
// per component. A Create shaft is a block entity of Create's component and an
// Aeronautics propeller bearing one of Aeronautics', so the two never meet in one
// propagator, which is why a shaft could not drive a propeller bearing at all
// (Java has one `TorquePropagator` per level for every mod,
// `TorquePropagator.java:11`).
//
// The network still has to be *one* graph, so the owner (Create's plugin) keeps
// it and the other components' nodes are materialised here as data: a
// [ForeignKineticNode] carries everything the propagation reads, and every write
// it receives is queued as one `apply` message for the component that really owns
// the block entity (`KineticOwnerLink`). Only data crosses the boundary.
//
// The rule half of a foreign block ([KineticBlockDef]) is registered by the
// component that owns the block; see `wire_def.dart` for why it crosses as data.
//
// Pure: no host imports, so a network that spans two components is unit tested
// against a recording link.
import 'geometry.dart';
import 'node.dart';
import 'propagator.dart';

/// The channel a component uses to reach the owner of the network.
///
/// The consumer half of the wire-up (`KineticsBridge` in `package:create`'s
/// plugin layer) implements this; the propagation only ever calls into it, so the
/// algorithms stay testable.
abstract interface class KineticOwnerLink {
  /// Whether the owner runs the network: then the component that holds this link
  /// does not propagate locally, it announces and applies.
  bool get hosted;

  /// The node at [pos] appeared (`KineticBlockEntity.kineticTickStart`'s attach).
  void nodeAttached(KineticNode node);

  /// The node at [pos] is gone (`kineticRemove`).
  void nodeDetached(KineticNode node);

  /// The node's own values changed (a generator's `generatedSpeed`).
  void nodeChanged(KineticNode node);
}

/// The values a component sends for one of its nodes: everything the propagator
/// reads, and nothing it could not use on the other side (no objects cross).
final class ForeignNodeValues {
  final double generatedSpeed;
  final double addedStress;
  final double addedCapacity;

  const ForeignNodeValues({
    this.generatedSpeed = 0,
    this.addedStress = 0,
    this.addedCapacity = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is ForeignNodeValues &&
      other.generatedSpeed == generatedSpeed &&
      other.addedStress == addedStress &&
      other.addedCapacity == addedCapacity;

  @override
  int get hashCode => Object.hash(generatedSpeed, addedStress, addedCapacity);
}

/// The verdict the owner sends back for one foreign node
/// (`KineticNetwork._updateFromNetwork` plus the speed the propagator set).
final class ForeignNodeVerdict {
  final double speed;
  final KPos? source;
  final int? network;
  final double capacity;
  final double stress;
  final int networkSize;
  final bool overStressed;

  const ForeignNodeVerdict({
    required this.speed,
    required this.source,
    required this.network,
    required this.capacity,
    required this.stress,
    required this.networkSize,
    required this.overStressed,
  });

  Map<String, Object?> toJson(KPos pos) => {
    'pos': [pos.x, pos.y, pos.z],
    'speed': speed,
    'source': source == null ? null : [source!.x, source!.y, source!.z],
    'network': network,
    'capacity': capacity,
    'stress': stress,
    'networkSize': networkSize,
    'overStressed': overStressed,
  };

  @override
  bool operator ==(Object other) =>
      other is ForeignNodeVerdict &&
      other.speed == speed &&
      other.source == source &&
      other.network == network &&
      other.capacity == capacity &&
      other.stress == stress &&
      other.networkSize == networkSize &&
      other.overStressed == overStressed;

  @override
  int get hashCode =>
      Object.hash(speed, source, network, capacity, stress, networkSize, overStressed);
}

/// A kinetic block entity of another component, as a [KineticNode] of this one.
///
/// Everything the propagation mutates (speed, source, network, capacity, stress)
/// is held here and pushed to the owning component; everything the propagation
/// queries but does not own ([generatedSpeed], the two stress contributions) comes
/// from the values that component sent. The connection *rule* comes from the
/// registered [KineticBlockDef], exactly as for a local node.
final class ForeignKineticNode with KineticNodeMixin implements KineticNode {
  ForeignKineticNode(ForeignKineticNodes registry, KPos pos)
    : _registry = registry,
      _pos = pos;

  final ForeignKineticNodes _registry;
  final KPos _pos;

  /// The plugin that owns the block entity (the address `apply` is sent to).
  String plugin = '';

  ForeignNodeValues values = const ForeignNodeValues();

  /// The verdict last pushed for this node, so an unchanged node is not sent
  /// again on every sync.
  ForeignNodeVerdict? pushed;

  bool pending = false;

  @override
  KPos get kpos => _pos;

  @override
  KineticLevel get level => _registry.level;

  /// The block state, read from the world (the state is shared: the host holds it
  /// and every component reads the same blocks).
  @override
  KState get blockState => level.stateAt(_pos);

  @override
  double get generatedSpeed => values.generatedSpeed;

  @override
  double calculateStressApplied() {
    lastStressApplied = values.addedStress;
    return values.addedStress;
  }

  @override
  double calculateAddedStressCapacity() {
    lastCapacityProvided = values.addedCapacity;
    return values.addedCapacity;
  }

  /// The current verdict of this node (what `apply` sends).
  ForeignNodeVerdict get verdict => ForeignNodeVerdict(
    speed: speedValue,
    source: source,
    network: network,
    capacity: capacity,
    stress: stress,
    networkSize: networkSize,
    overStressed: overStressed,
  );

  // -- The two write hooks the propagation uses to report back -----------------

  /// `markChanged`: the owning component writes its own block entity, so this
  /// only records that the component has to be told.
  @override
  void markChanged() => _registry.markPending(this);

  @override
  void sendData() => _registry.markPending(this);

  @override
  String toString() => 'ForeignKineticNode(${blockState.block} at $_pos from $plugin)';
}

/// The foreign nodes of one owner, by world and position.
///
/// The owner creates a node when the component that owns the block entity
/// announces it (`create.kinetics`' `update`) and drops it when that component
/// says it is gone (`detach`) or the block state there is no longer a kinetic
/// block of that component.
final class ForeignKineticNodes {
  ForeignKineticNodes(this.level);

  final KineticLevel level;

  final Map<int, ForeignKineticNode> _nodes = {};

  /// The nodes whose verdict changed, by the plugin that has to be told.
  final Map<String, Set<ForeignKineticNode>> _pending = {};
  bool _collecting = false;

  /// The node at [pos], or `null` when no component announced one.
  ForeignKineticNode? existing(KPos pos) => _nodes[pos.packed];

  /// The node at [pos] for the propagation: `null` when the block there is not a
  /// kinetic block any more (the component did not say `detach`, e.g. the block
  /// was replaced or the position is not loaded).
  ForeignKineticNode? at(KPos pos) {
    final node = _nodes[pos.packed];
    if (node == null) return null;
    if (!level.isLoaded(pos)) return null;
    final def = level.blocks.defFor(level.stateAt(pos));
    if (def == null || level.blocks.ownerOf(level.stateAt(pos).block) == null) {
      // The block is gone (or replaced by something that is not a kinetic block):
      // the component's block entity is gone with it.
      forget(node);
      return null;
    }
    return node;
  }

  /// Creates or refreshes the node a component announced.
  ForeignKineticNode announce(
    String plugin,
    KPos pos,
    ForeignNodeValues values,
  ) {
    final existing = _nodes[pos.packed];
    final node = existing ?? ForeignKineticNode(this, pos);
    final fresh = existing == null;
    final changed = fresh || existing.values != values;
    node
      ..plugin = plugin
      ..values = values;
    _nodes[pos.packed] = node;

    // A generator of another component reports its speed the way
    // `GeneratingNodeMixin.applyNewSpeed` does locally: it starts turning *and*
    // owns its network before it attaches, so the first propagation conveys
    // rotation to its neighbours instead of meeting a sourceless node.
    if (node.generatedSpeed != 0 && !node.hasSource) {
      if (!node.hasNetwork) node.setNetwork(node.kpos.packed);
      if (node.speedValue == 0) node.setSpeed(node.generatedSpeed);
    }

    if (changed) {
      // Joins the network (a fresh node), or conveys a new generated speed
      // through it.
      RotationPropagator.handleAdded(level, pos, node);
    }
    markPending(node);
    return node;
  }

  /// Drops the node at [pos] (the component removed its block entity).
  void detach(KPos pos) {
    final node = _nodes.remove(pos.packed);
    if (node == null) return;
    _pendingFor(node.plugin).remove(node);
    if (node.hasNetwork) node.getOrCreateNetwork()?.remove(node);
    node.detachKinetics();
  }

  /// Forgets [node] and detaches it from its network.
  void forget(ForeignKineticNode node) {
    _nodes.remove(node.kpos.packed);
    _pendingFor(node.plugin).remove(node);
    if (node.hasNetwork) node.getOrCreateNetwork()?.remove(node);
    node.detachKinetics();
  }

  void markPending(ForeignKineticNode node) {
    if (node.plugin.isEmpty) return;
    node.pending = true;
    _pendingFor(node.plugin).add(node);
  }

  Set<ForeignKineticNode> _pendingFor(String plugin) =>
      _pending.putIfAbsent(plugin, () => <ForeignKineticNode>{});

  /// Whether any node has a change waiting to be sent.
  bool get hasPending => _pending.values.any((set) => set.isNotEmpty);

  /// The `apply` messages for one plugin: one entry per node whose verdict
  /// changed since the last send. The sets are cleared.
  List<Map<String, Object?>> takePending(String plugin) {
    final set = _pending[plugin];
    if (set == null || set.isEmpty) return const [];
    set.removeWhere((node) => node.plugin != plugin || !_nodes.containsKey(node.kpos.packed));
    final out = <Map<String, Object?>>[];
    for (final node in set) {
      final verdict = node.verdict;
      if (verdict == node.pushed) continue;
      node.pushed = verdict;
      node.pending = false;
      out.add(verdict.toJson(node.kpos));
    }
    set.clear();
    return out;
  }

  /// Drops every node of one plugin (it unloaded or never answered `apply`).
  void dropPlugin(String plugin) {
    for (final pos in [
      for (final entry in _nodes.entries)
        if (entry.value.plugin == plugin) entry.key,
    ]) {
      detach(KPos.unpack(pos));
    }
    _pending.remove(plugin);
  }

  /// The plugins with changes waiting.
  Iterable<String> get pendingPlugins => [
    for (final entry in _pending.entries)
      if (entry.value.isNotEmpty) entry.key,
  ];

  /// Runs [body] while the network is being propagated, so a change made in one
  /// pass is not sent before the pass finished (the pass is what decides the
  /// speed of the whole set).
  T batch<T>(T Function() body) {
    if (_collecting) return body();
    _collecting = true;
    try {
      return body();
    } finally {
      _collecting = false;
    }
  }

  /// All foreign nodes of one world (tests, diagnostics).
  Iterable<ForeignKineticNode> get nodes => _nodes.values;

  int get count => _nodes.length;
}