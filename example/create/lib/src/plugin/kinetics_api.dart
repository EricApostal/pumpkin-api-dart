// The kinetic operations other plugin **components** call.
//
// A Pumpkin server runs every plugin in its own wasm instance and each plugin
// compiles its own copy of `package:create`, so `KineticsRuntime` — the block
// entity store, the block registry and the per-level network map — is per
// component. A Create shaft is a block entity of Create's component and an
// Aeronautics propeller bearing one of Aeronautics', so without this the two never
// meet in one propagator: measured, `create:mechanical_bearing` joins a network
// (`Size 3`, `Speed 16f`) while `aeronautics:propeller_bearing` sits at speed 0 in
// a network of its own. Java has one `TorquePropagator` per level for every mod
// (`TorquePropagator.java:11`).
//
// **The owner is Create's plugin**: it links Create's kinetics module, which owns
// the network table, the block rules, the stress table and the config, and every
// *source of rotation* of the fleet is a Create block (water wheel, windmill
// bearing, steam engine, creative motor, hand crank) that the addons' blocks are
// driven by. The addons are consumers: their block entities extend Create's
// `KineticBlockEntity` and their blocks are `IRotate`s of Create's network. Same
// shape as the sub-level decision (`docs/sable-core-port.md`, "Cross-plugin
// ownership"): one component owns, the others ask through one door.
//
// Only data crosses: a consumer registers the *rules* of its blocks (see
// `wire_def.dart`), announces a node (position + the values the propagation
// reads) and applies the verdict it gets back. The owner materialises the node as
// a `ForeignKineticNode` in its own propagation.
//
// Host: this file uses `pumpkin_api` (IPC + the world tick).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../kinetics/foreign.dart';
import '../kinetics/geometry.dart';
import '../kinetics/runtime.dart';
import '../kinetics/wire_def.dart';

/// The IPC channel every kinetic operation travels on.
const IpcChannel<Map<String, Object?>> kineticsChannel = IpcChannel<
  Map<String, Object?>
>(
  kineticsChannelName,
  _identity,
  _asMap,
);

/// The channel name (one per message type, see `IpcChannel`).
const String kineticsChannelName = 'create.kinetics';

/// The plugin name other components address the operations to.
const String kineticsOwnerPlugin = 'create';

Object? _identity(Map<String, Object?> message) => message;

Map<String, Object?> _asMap(Object? json) =>
    json is Map ? {for (final entry in json.entries) '${entry.key}': entry.value} : const {};

/// The wire version: the owner answers `ping` with it and a consumer that speaks
/// a different one stays local rather than guessing.
const int kineticsProtocolVersion = 1;

/// The operations of [kineticsChannel].
abstract final class KineticWireOps {
  /// Who runs the network: `{"op": "ping"}` -> `{"ok": true, "protocol": 1}`.
  static const String ping = 'ping';

  /// The rules and stress values of the caller's kinetic blocks.
  static const String register = 'register';

  /// One node of the caller appeared or changed its own values.
  static const String update = 'update';

  /// One node of the caller is gone.
  static const String detach = 'detach';

  /// The owner's reply for the nodes of the caller (`apply`).
  static const String apply = 'apply';
}

Map<String, Object?> _ok([Map<String, Object?> fields = const {}]) => {'ok': true, ...fields};

Map<String, Object?> _error(Object error) => {'ok': false, 'error': '$error'};

/// The kinetic operations of Create's plugin: it owns the network of every
/// component and answers on [kineticsChannel].
final class KineticsApi {
  KineticsApi(this._runtime, this.log);

  final KineticsRuntime _runtime;
  final Logger log;

  /// Registers the handler. Call once, from the plugin's `onLoad`.
  void install() => kineticsChannel.handle(_handle);

  Object? _handle(String sender, Map<String, Object?> message) {
    final op = message['op'];
    try {
      return switch (op) {
        KineticWireOps.ping => _ok({
          'protocol': kineticsProtocolVersion,
          'plugin': kineticsOwnerPlugin,
        }),
        KineticWireOps.register => _register(sender, message),
        KineticWireOps.update => _update(sender, message),
        KineticWireOps.detach => _detach(message),
        _ => _error('Unknown kinetic operation "$op"'),
      };
    } on Object catch (error, stack) {
      log.warn('create.kinetics "$op" from $sender failed: $error', error: error, stackTrace: stack);
      return _error(error);
    }
  }

  // ------------------------------------------------------------------ register

  Object? _register(String sender, Map<String, Object?> message) {
    final blocks = message['blocks'];
    if (blocks is! Map) return _error('"blocks" must be an object');

    var registered = 0;
    final unsupported = <String>[];
    for (final entry in blocks.entries) {
      final key = '${entry.key}';
      final spec = entry.value;
      if (spec is! Map) {
        unsupported.add(key);
        continue;
      }
      final def = WireKineticDef.fromJson(spec['def']);
      if (def == null) {
        // A rule outside the wire vocabulary: the owner cannot rebuild it, and a
        // rule that is *approximated* would connect blocks Java does not connect.
        unsupported.add(key);
        continue;
      }
      _runtime.blocks.registerForeign(key, def, sender);
      _runtime.stressTable.register(
        key,
        impact: _double(spec['impact']),
        capacity: _double(spec['capacity']),
        generatedRpm: _int(spec['generatedRpm']),
      );
      if (spec['chainDrive'] == true) _runtime.blocks.chainDriveBlocks.add(key);
      registered++;
    }
    if (unsupported.isNotEmpty) {
      log.warn(
        '$sender registered ${unsupported.length} kinetic blocks whose rule is not '
        'a wire def (${unsupported.join(', ')}): their blocks will not connect to '
        "Create's network.",
      );
    }
    log.info(
      'create.kinetics: $sender registered $registered kinetic block rules'
      '${unsupported.isEmpty ? '' : ' (${unsupported.length} unsupported)'}.',
    );
    return _ok({'registered': registered, 'unsupported': unsupported});
  }

  // -------------------------------------------------------------------- update

  Object? _update(String sender, Map<String, Object?> message) {
    final world = _worldId(message['world']);
    final pos = _posOf(message['pos']);
    if (world == null || pos == null) {
      log.warn('create.kinetics: $sender sent an update without "world"/"pos": $message');
      return _error('"world" and "pos" are required');
    }
    final state = _runtime.level(world).stateAt(pos);
    final owner = _runtime.blocks.ownerOf(state.block);
    if (owner != sender) {
      log.warn(
        'create.kinetics: $sender announced ${state.block} at $pos, which belongs to '
        '${owner ?? 'no component it registered'}: not taken.',
      );
      return _error(
        '${state.block} at $pos belongs to ${owner ?? 'no component'} (sender $sender)',
      );
    }

    final level = _runtime.level(world);
    final node = level.foreign.announce(
      sender,
      pos,
      ForeignNodeValues(
        generatedSpeed: _double(message['generatedSpeed']) ?? 0,
        addedStress: _double(message['addedStress']) ?? 0,
        addedCapacity: _double(message['addedCapacity']) ?? 0,
      ),
    );
    // One line per announcement at debug level: it is the trace of the wire-up (who
    // announced what, and what the node looks like once it joined), and an operator
    // chasing a bearing that does not turn needs exactly this.
    log.debug(
      'create.kinetics: $sender announced ${state.block} at $pos '
      '(state ${state.props}, generated ${_fmt(node.generatedSpeed)}, '
      'speed ${_fmt(node.theoreticalSpeed)}, network ${node.network}, '
      'source ${node.source}, members ${node.getOrCreateNetwork()?.members.length ?? 0})',
    );
    return _ok();
  }

  Object? _detach(Map<String, Object?> message) {
    final world = _worldId(message['world']);
    final pos = _posOf(message['pos']);
    if (world == null || pos == null) return _error('"world" and "pos" are required');
    _runtime.level(world).foreign.detach(pos);
    return _ok();
  }

  // -------------------------------------------------------------------- pushing

  /// Sends every node whose verdict changed to the component that owns it.
  ///
  /// Called once per world tick by the plugin, after the block entities of that
  /// world ticked: the propagation runs inside the tick, so one flush per tick
  /// carries every change it made.
  void flush() {
    for (final world in _runtime.levelIds.toList()) {
      final foreign = _runtime.level(world).foreign;
      if (!foreign.hasPending) continue;
      for (final plugin in foreign.pendingPlugins.toList()) {
        final nodes = foreign.takePending(plugin);
        if (nodes.isEmpty) continue;
        log.debug('create.kinetics: ${nodes.length} verdict(s) to $plugin in $world: $nodes');
        unawaited(
          kineticsChannel.send(plugin, {
            'op': KineticWireOps.apply,
            'world': world,
            'nodes': nodes,
          }).catchError((Object error) {
            // The component unloaded (or never answered): its nodes are stale, so
            // drop them rather than pushing into the void forever.
            log.warn('create.kinetics: $plugin did not take its verdict: $error');
            _runtime.level(world).foreign.dropPlugin(plugin);
          }),
        );
      }
    }
  }

  String? _worldId(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return _runtime.worlds.worldIdOf(value) ?? value;
  }

  static KPos? _posOf(Object? value) {
    if (value is! List || value.length != 3) return null;
    final x = _int(value[0]);
    final y = _int(value[1]);
    final z = _int(value[2]);
    if (x == null || y == null || z == null) return null;
    return KPos(x, y, z);
  }

  static String _fmt(double value) => value == value.roundToDouble() ? '${value.round()}' : '$value';

  static double? _double(Object? value) => value is num ? value.toDouble() : null;

  static int? _int(Object? value) => value is num ? value.toInt() : null;
}