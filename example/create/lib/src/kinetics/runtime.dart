// The host side of the kinetic network: block state decoding, the world view
// the propagator uses, and the runtime object block entities find their settings
// in. Everything that touches `package:pumpkin_api` lives here and in the files
// that import this one; the algorithms are in the pure files.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/block_entity.dart';
import '../core/blocks.dart' show CreateBlock;
import '../core/perf.dart';
import '../core/worlds.dart';
import '../api/config.dart' as cfg;
import 'foreign.dart';
import 'geometry.dart';
import 'node.dart';
import 'settings.dart';
import 'use_records.dart';

/// Block states by global state id and back, with caches (a state id never changes).
final class StateCodec {
  final Map<int, KState> _byId = {};
  final Map<KState, int> _ids = {};

  /// The state with global id [stateId] (air for an unknown id).
  KState decode(int stateId) => _byId[stateId] ??= _decodeUncached(stateId);

  KState _decodeUncached(int stateId) {
    final info = BlockRegistry.stateInfo(stateId);
    if (info == null) return KState.air;
    final key = info.name.contains(':') ? info.name : 'minecraft:${info.name}';
    final props = <String, String>{for (final (k, v) in info.properties) k: v};
    final state = KState(key, props);
    _ids[state] = stateId;
    return state;
  }

  /// The global id of [state] (properties it lacks take the defaults), or `null`.
  int? idOf(KState state) {
    final known = _ids[state];
    if (known != null) return known;
    final id = BlockRegistry.resolveState(state.block, state.props);
    if (id != null) {
      _ids[state] = id;
      _byId.putIfAbsent(id, () => state);
    }
    return id;
  }
}

BlockPos toBlockPos(KPos p) => BlockPos(x: p.x, y: p.y, z: p.z);
KPos toKPos(BlockPos p) => KPos(p.x, p.y, p.z);

/// The per-world view of the kinetic network used by the propagator.
final class HostKineticLevel extends KineticLevel {
  final String worldId;
  final KineticsRuntime runtime;

  HostKineticLevel(this.worldId, this.runtime);

  /// The foreign nodes of this world, created on first use.
  late final foreign = ForeignKineticNodes(this);

  @override
  KineticConfig get settings => runtime.settings;
  @override
  KineticBlockRegistry get blocks => runtime.blocks;
  @override
  StressSource get stress => runtime.stress;

  World? get world => runtime.worlds.byId(worldId);

  @override
  bool get hosted => runtime.hosted;

  @override
  KineticNode? nodeAt(KPos pos) {
    // A component that does not own the network has no node of its own to offer
    // (its block entities are announced to the owner instead).
    if (hosted) return null;
    final be = runtime.store.at(worldId, toBlockPos(pos));
    if (be is KineticNode) return be as KineticNode;
    return foreign.at(pos);
  }

  // A propagation pass reads each position of a network several times: every node asks for its
  // six neighbours, which are the other nodes' own positions, and `_propagateNewSource` walks the
  // whole connected tree from each side. Each read is a wasm call, so a pass (`beginBatch`) serves
  // them from these caches instead. Nothing changes a block state inside a pass: `destroyBlock` is
  // async and the pass returns right after it.
  int _batchDepth = 0;
  final Map<int, int> _batchStateIds = {};
  final Map<int, bool> _batchLoaded = {};

  @override
  void beginBatch() => _batchDepth++;

  @override
  void endBatch() {
    if (_batchDepth == 0) return;
    if (--_batchDepth == 0) {
      _batchStateIds.clear();
      _batchLoaded.clear();
    }
  }

  @override
  KState stateAt(KPos pos) {
    final w = world;
    if (w == null) return KState.air;
    if (_batchDepth == 0) {
      return runtime.states.decode(_readStateId(w, pos));
    }
    final key = pos.packed;
    final cached = _batchStateIds[key];
    if (cached != null) return runtime.states.decode(cached);
    final id = _readStateId(w, pos);
    _batchStateIds[key] = id;
    return runtime.states.decode(id);
  }

  int _readStateId(World w, KPos pos) {
    if (!Perf.enabled) return w.getBlockStateId(pos: toBlockPos(pos));
    final watch = Stopwatch()..start();
    try {
      return w.getBlockStateId(pos: toBlockPos(pos));
    } finally {
      Perf.record('host.getBlockStateId', watch.elapsedMicroseconds);
    }
  }

  @override
  bool isLoaded(KPos pos) {
    final w = world;
    if (w == null) return false;
    if (_batchDepth == 0) return _readLoaded(w, pos);
    final key = pos.packed;
    final cached = _batchLoaded[key];
    if (cached != null) return cached;
    final loaded = _readLoaded(w, pos);
    _batchLoaded[key] = loaded;
    return loaded;
  }

  bool _readLoaded(World w, KPos pos) {
    if (!Perf.enabled) return w.isLoaded(pos: toBlockPos(pos));
    final watch = Stopwatch()..start();
    try {
      return w.isLoaded(pos: toBlockPos(pos));
    } finally {
      Perf.record('host.isLoaded', watch.elapsedMicroseconds);
    }
  }

  final Set<KPos> _destroying = {};

  @override
  void destroyBlock(KPos pos) {
    final w = world;
    if (w == null || !_destroying.add(pos)) return;
    unawaited(
      w
          .breakBlock(toBlockPos(pos), drop: true)
          .catchError((Object e, StackTrace s) {
            runtime.log.error('Breaking the block at $pos failed', error: e, stackTrace: s);
            return false;
          })
          .whenComplete(() => _destroying.remove(pos)),
    );
  }

  // -- The link to the component that runs the network -------------------------

  @override
  void nodeAttached(KineticNode node) => runtime.ownerLink?.nodeAttached(node);

  @override
  void nodeDetached(KineticNode node) => runtime.ownerLink?.nodeDetached(node);

  @override
  void nodeChanged(KineticNode node) => runtime.ownerLink?.nodeChanged(node);
}

/// Who knows how efficient a boiler is: the fluids module provides it so the
/// steam engine can read the tank behind it.
abstract interface class SteamEngineBoilerSource {
  /// The efficiency (0..1+) of the engine attached to the tank block at
  /// ([x], [y], [z]) in world [worldId]; `null` if there is no fluid tank there.
  double? engineEfficiency(String worldId, int x, int y, int z);
}

/// [KineticConfig] over the live config of the infrastructure module
/// (`/create config` changes apply at once).
final class ConfigsKineticConfig implements KineticConfig {
  final cfg.CreateConfigs configs;

  const ConfigsKineticConfig(this.configs);

  cfg.CKinetics get _k => configs.server.kinetics;

  @override
  bool get disableStress => _k.disableStress.value;
  @override
  int get maxRotationSpeed => _k.maxRotationSpeed.value;
  @override
  int get kineticValidationFrequency => _k.kineticValidationFrequency.value;
  @override
  double get mediumSpeed => _k.mediumSpeed.value;
  @override
  double get fastSpeed => _k.fastSpeed.value;
  @override
  double get crankHungerMultiplier => _k.crankHungerMultiplier.value;
}

/// The stress values: the live config first, then what modules registered.
final class LayeredStress implements StressSource {
  final cfg.BlockStressValues? live;
  final KineticStressTable table;

  LayeredStress(this.live, this.table);

  @override
  double impact(String block) {
    final l = live;
    if (l != null && l.hasImpact(block)) return l.impact(block);
    return table.impact(block);
  }

  @override
  double capacity(String block) {
    final l = live;
    if (l != null && l.hasCapacity(block)) return l.capacity(block);
    return table.capacity(block);
  }
}

/// Shared state of the module: settings, registry of kinetic block rules, stress
/// table, state codec, the per-world levels.
final class KineticsRuntime {
  static KineticsRuntime? _instance;

  /// The runtime; available after the module's `onLoad`.
  static KineticsRuntime get instance => _instance ?? (throw StateError('The kinetics module is not loaded'));

  static bool get isLoaded => _instance != null;

  /// The stored fallback settings (the `kinetics` section of config.json).
  final KineticsSettings fallbackSettings;
  cfg.CreateConfigs? _configs;

  /// The live config values of the infrastructure module when it is loaded,
  /// otherwise [fallbackSettings].
  KineticConfig get settings {
    final c = _configs;
    return c == null ? fallbackSettings : ConfigsKineticConfig(c);
  }

  /// The table of the manifest defaults and what other modules registered.
  late final KineticStressTable stressTable = KineticStressTable(fallbackSettings);

  /// Impact and capacity per RPM, from the live config when available.
  StressSource get stress => LayeredStress(_configs?.stress, stressTable);

  /// `equipment.placementAssistRange`.
  int get placementAssistRange => _configs?.server.equipment.placementAssistRange.value ?? 12;

  /// Switches to the live config of the infrastructure module.
  void useConfigs(cfg.CreateConfigs configs) => _configs = configs;

  final KineticBlockRegistry blocks = KineticBlockRegistry();
  final StateCodec states = StateCodec();
  final BlockEntityStore store;
  final Worlds worlds;
  final Logger log;
  final UseRecords useRecords = UseRecords();

  /// The blocks of this module by key (filled by the module).
  final Map<String, CreateBlock> kineticBlocks = {};

  /// Positions (`worldId:packed`) whose next block change was written with
  /// `UPDATE_KNOWN_SHAPE`: Java skips `updateIndirectNeighbourShapes` for it, so the
  /// kinetic information must be kept.
  final Set<String> keepKineticInfo = {};

  /// Provided by the fluids module: the efficiency of boilers (steam engine).
  SteamEngineBoilerSource? boilerSource;

  /// The link to the component that runs the network, when this component does
  /// not (`foreign.dart`). Create's own plugin never sets it — it *is* the owner.
  KineticOwnerLink? ownerLink;

  /// Whether another component runs the kinetic network (see [ownerLink]).
  bool get hosted => ownerLink?.hosted ?? false;

  final Map<String, HostKineticLevel> _levels = {};

  KineticsRuntime(this.fallbackSettings, this.store, this.worlds, this.log) {
    _instance = this;
  }

  HostKineticLevel level(String worldId) => _levels.putIfAbsent(worldId, () => HostKineticLevel(worldId, this));

  /// The worlds this runtime has a level view of.
  Iterable<String> get levelIds => _levels.keys;

  /// Forgets the networks of a world (world unload).
  void forgetWorld(String worldId) => _levels.remove(worldId)?.clearNetworks();

  void dispose() {
    for (final l in _levels.values) {
      l.clearNetworks();
    }
    _levels.clear();
    if (identical(_instance, this)) _instance = null;
  }
}
