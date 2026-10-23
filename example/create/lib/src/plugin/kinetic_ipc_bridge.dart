// The caller half of Create's kinetic operations (`create.kinetics`).
//
// An addon plugin (Aeronautics, Simulated, Offroad) links `package:create` but runs
// in its own wasm instance, so its `KineticsRuntime` is a *different* one from
// Create's plugin's: its block entities tick in its own component and its own
// propagator would build a second, partial network. When Create's plugin is
// loaded, this bridge turns that runtime into a caller instead: the block rules
// of the addon are rebuilt in Create's component from their wire form, the nodes
// of this component are announced position by position, and the verdicts that
// land on `create.kinetics` run in the component's own block entities.
//
// When no owner is loaded (`ping` fails) the bridge stays disarmed and the local
// runtime propagates by itself, which is the single-plugin case; `KineticsRuntime
// .hosted` is then `false` and nothing reaches over the channel.
//
// Host: this file uses `pumpkin_api` (channels, events, the world tick).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/block_entity.dart' show CreateBlockEntity;
import '../kinetics/foreign.dart' show ForeignNodeValues, KineticOwnerLink;
import '../kinetics/geometry.dart';
import '../kinetics/node.dart' show ForeignVerdictValues, KineticNode;
import '../kinetics/runtime.dart';
import '../kinetics/wire_def.dart';

/// The channel name shared with the owner (`kinetics_api.dart`).
const String kineticsChannelName = 'create.kinetics';

/// The plugin that runs the network.
const String kineticsOwnerPlugin = 'create';

/// The channel version the owner answers. A consumer that speaks a different
/// one stays local rather than guessing.
const int kineticsProtocolVersion = 1;

Object? _identity(Map<String, Object?> message) => message;

Map<String, Object?> _asMap(Object? json) =>
    json is Map ? {for (final entry in json.entries) '${entry.key}': entry.value} : const {};

/// Arms the caller half of the kinetic network for a component that is not
/// Create: the block rules of this component are registered in the owner's
/// component, its nodes are announced, and the verdicts that come back run in
/// its own block entities (`kinetic_ipc_bridge.dart`).
///
/// Call it from the plugin's `onLoad`, after the module registered its kinetic
/// defs locally (so [KineticsBridge.rules] is filled) and before the first world
/// tick; keep the returned bridge and [KineticsBridge.close] it in `onUnload`.
///
/// The bridge *asks* whether an owner is loaded (the `ping` on the first world
/// tick) instead of assuming: without Create, `hosted` stays `false` and this
/// component propagates locally, which is the single-plugin case.
KineticsBridge installConsumerKinetics({
  required Context context,
  required Logger log,
  KineticsRuntime? runtime,
}) {
  final bridge = KineticsBridge(runtime ?? KineticsRuntime.instance, log: log);
  bridge.install();
  // The probe runs on the first world tick of this component, when every plugin
  // has loaded: plugin load order is not fixed, so a claim at load time could
  // arrive before the owner is listening.
  context.listen(Events.worldTick, (server, event) {
    bridge.tickWorld(event.targetWorld.getId());
  });
  return bridge;
}

/// The caller half of Create's kinetic operations.
///
/// One instance per plugin: [install] registers the `apply` handler and asks the
/// owner to subscribe the plugin, [close] drops it.
final class KineticsBridge implements KineticOwnerLink {
  KineticsBridge(
    this._runtime, {
    required Logger log,
    this.owner = kineticsOwnerPlugin,
  }) : _log = log;

  final KineticsRuntime _runtime;
  final Logger _log;

  /// The plugin that is asked to run the network.
  final String owner;

  /// The rules of this component's kinetic blocks and their stress values. Set
  /// by the plugin after it registered its own defs (in this component too, so
  /// the local fallback has them); sent with [register].
  final Map<String, ({WireKineticDef def, double? impact, double? capacity, int? generatedRpm})>
  rules = {};

  /// Registers the rule (and the stress values) of a kinetic block of this
  /// component.
  ///
  /// Call it for every block whose `IRotate` rule this component registered in
  /// its own runtime: the owner rebuilds the same rule from [WireKineticDef]'s
  /// wire form, which is why the defs of an addon's kinetic blocks are
  /// [WireKineticDef]s — one description for both components, no drift.
  void addRule(
    String blockKey,
    WireKineticDef def, {
    double? impact,
    double? capacity,
    int? generatedRpm,
  }) {
    rules[blockKey] = (
      def: def,
      impact: impact,
      capacity: capacity,
      generatedRpm: generatedRpm,
    );
  }

  bool _installed = false;

  /// The verdict the owner last sent for each announced node, by packed position:
  /// a node that only re-announced itself must not be re-sent unchanged.
  final Map<String, Map<int, ForeignNodeValues>> _announced = {};

  static const IpcChannel<Map<String, Object?>> _owner =
      IpcChannel<Map<String, Object?>>(kineticsChannelName, _identity, _asMap);

  /// Whether the bridge is armed: the owner answered `ping`, so this component
  /// announces its nodes instead of propagating by itself.
  @override
  bool get hosted => _armed;
  bool _armed = false;

  /// Whether [install] ran (the `apply` handler is registered).
  bool get installed => _installed;

  /// Registers the `apply` handler and asks the owner to take over.
  ///
  /// Safe to call before Create loads: a failed `ping` leaves the bridge
  /// disarmed and the local runtime propagates by itself. The next [tickWorld]
  /// retries the probe, because the load order of two plugins is not fixed and
  /// Create may come up later.
  void install() {
    if (_installed) return;
    _owner.handle((sender, message) {
      if (message['op'] == 'apply') {
        _apply(message);
      }
      return null;
    });
    _installed = true;
  }

  /// Prods the bridge: ping the owner (when not armed) and re-announce the live
  /// nodes (after a reconnect). Queued, never blocking the tick.
  void tickWorld(String worldId) {
    if (!_armed) {
      unawaited(_probeAndRegister());
      return;
    }
    // Nothing to push regularly: nodes announce themselves when they attach or
    // change. The probe already covers the gap (the owner restarted).
  }

  Future<void> _probeAndRegister() async {
    try {
      final reply = await _owner.request(owner, const {'op': 'ping'});
      if (reply is! Map || reply['protocol'] != kineticsProtocolVersion) {
        return;
      }
    } on Object {
      // No owner loaded: this component propagates by itself.
      return;
    }
    _armed = true;
    _runtime.ownerLink = this;
    await register();
    _log.info(
      'Kinetics: $owner runs the kinetic network (${rules.length} block rules sent).',
    );
    // Nodes that attached before the owner answered announced into the void;
    // refresh every live one now.
    _announced.clear();
    reannounceAll();
  }

  /// Sends the rules and stress values of this component's kinetic blocks.
  Future<void> register() async {
    if (rules.isEmpty) return;
    try {
      final reply = await _owner.request(owner, {
        'op': 'register',
        'blocks': {
          for (final entry in rules.entries)
            entry.key: {
              'def': entry.value.def.toJson(),
              if (entry.value.impact != null) 'impact': entry.value.impact,
              if (entry.value.capacity != null) 'capacity': entry.value.capacity,
              if (entry.value.generatedRpm != null) 'generatedRpm': entry.value.generatedRpm,
            },
        },
      });
      if (reply is Map && (reply['unsupported'] as List?)?.isNotEmpty == true) {
        _log.warn(
          'Kinetics: the owner cannot take ${(reply['unsupported'] as List).join(', ')}: '
          'their rule is not a wire def. They propagate locally.',
        );
      }
    } on Object catch (error) {
      _log.warn('Kinetics: could not register with $owner: $error');
    }
  }

  /// Re-announces every live kinetic block entity of every known world.
  ///
  /// Called after the owner answered, so nodes that attached while the bridge
  /// was disarmed join the network; the update itself is idempotent and the
  /// verdict round trip settles them.
  void reannounceAll() {
    if (!_armed) return;
    for (final worldId in _runtime.levelIds) {
      for (final be in _runtime.store.inWorld(worldId)) {
        _announceIfKinetic(be);
      }
    }
  }

  void _announceIfKinetic(Object be) {
    if (be is! KineticNode) return;
    final node = be;
    unawaited(updateOf(node));
  }

  // -- The link the block entities call into ------------------------------------

  @override
  void nodeAttached(KineticNode node) {
    if (!_armed) return;
    unawaited(updateOf(node));
  }

  @override
  void nodeDetached(KineticNode node) {
    if (!_armed) {
      return;
    }
    _dropAnnounced(node);
    unawaited(
      _owner.request(owner, {
        'op': 'detach',
        'world': _levelWorld(node),
        'pos': [node.kpos.x, node.kpos.y, node.kpos.z],
      }).catchError((Object _) => null),
    );
  }

  @override
  void nodeChanged(KineticNode node) {
    if (!_armed) return;
    unawaited(updateOf(node));
  }

  /// The world id of [node]: the level view it propagates through carries the id.
  ///
  /// An addon block entity may hand out a `KineticLevel` of its own (a mixin can
  /// override `level`), so the block entity's own `worldId` is the fallback — the
  /// announce must not be dropped because the level view is not this module's.
  String? _levelWorld(KineticNode node) {
    final level = node.level;
    if (level is HostKineticLevel) return level.worldId;
    final Object be = node;
    if (be is CreateBlockEntity) return be.worldId;
    return null;
  }

  /// Announces [node] to the owner: position, block key and the values the
  /// propagation reads. No-op when the values did not change since the last send.
  Future<void> updateOf(KineticNode node) async {
    if (!_armed) return;
    final values = ForeignNodeValues(
      generatedSpeed: node.generatedSpeed,
      addedStress: node.calculateStressApplied(),
      addedCapacity: node.calculateAddedStressCapacity(),
    );
    final world = _levelWorld(node);
    if (world == null) return;
    final byWorld = _announced.putIfAbsent(world, () => {});
    if (byWorld[node.kpos.packed] == values) return;
    byWorld[node.kpos.packed] = values;
    _log.debug('Kinetics: announcing ${node.blockState.block} at ${node.kpos} to $owner.');
    try {
      await _owner.request(owner, {
        'op': 'update',
        'world': world,
        'pos': [node.kpos.x, node.kpos.y, node.kpos.z],
        'block': node.blockState.block,
        'generatedSpeed': values.generatedSpeed,
        'addedStress': values.addedStress,
        'addedCapacity': values.addedCapacity,
      });
    } on Object {
      byWorld.remove(node.kpos.packed);
    }
  }

  void _dropAnnounced(KineticNode node) {
    for (final byWorld in _announced.values) {
      byWorld.remove(node.kpos.packed);
    }
  }

  // -- Applying the owner's verdict ----------------------------------------------

  void _apply(Map<String, Object?> message) {
    final world = message['world'];
    final nodes = message['nodes'];
    _log.debug('Kinetics: got ${nodes is List ? nodes.length : '?'} verdict(s) for $world.');
    if (world is! String || nodes is! List) {
      _log.warn('Kinetics: malformed verdict from $owner: $message');
      return;
    }
    for (final entry in nodes) {
      if (entry is! Map) continue;
      final pos = _posOf(entry['pos']);
      if (pos == null) continue;
      final be = _runtime.store.at(world, BlockPos(x: pos.x, y: pos.y, z: pos.z));
      final KineticNode? node = be is KineticNode ? be as KineticNode : null;
      if (node == null) {
        _log.warn('Kinetics: no block entity of this component at $pos in $world for a verdict.');
        continue;
      }
      _log.debug('Kinetics: applying a verdict to ${node.blockState.block} at $pos.');
      node.applyNetworkVerdict(
        ForeignVerdictValues(
          speedValue: _double(entry['speed']) ?? 0,
          source: _kposOrNull(entry['source']),
          network: _int(entry['network']),
          capacity: _double(entry['capacity']) ?? 0,
          stress: _double(entry['stress']) ?? 0,
          networkSize: _int(entry['networkSize']) ?? 0,
          overStressed: entry['overStressed'] == true,
        ),
      );
      _log.debug(
        'Kinetics: ${node.blockState.block} at $pos is now speed ${node.theoreticalSpeed}, '
        'network ${node.network}',
      );
    }
  }

  static KPos? _kposOrNull(Object? value) {
    final pos = _posOf(value);
    return pos;
  }

  static KPos? _posOf(Object? value) {
    if (value is! List || value.length != 3) return null;
    final x = _int(value[0]);
    final y = _int(value[1]);
    final z = _int(value[2]);
    if (x == null || y == null || z == null) return null;
    return KPos(x, y, z);
  }

  static double? _double(Object? value) => value is num ? value.toDouble() : null;

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  /// Forgets the armed state (plugin unload).
  void close() {
    _armed = false;
    if (identical(_runtime.ownerLink, this)) _runtime.ownerLink = null;
    _announced.clear();
    rules.clear();
    _installed = false;
  }

  @override
  String toString() => 'KineticsBridge(${_armed ? 'hosted by $owner' : 'local'})';
}