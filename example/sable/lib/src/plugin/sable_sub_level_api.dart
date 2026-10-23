// The sub-level operations other plugin **components** call.
//
// A Pumpkin server runs every plugin in its own wasm instance, and each plugin
// compiles its own copy of `package:sable`, so `SubLevelContainer`'s static map
// is per component: the container this plugin creates is invisible to the
// Simulated / Aeronautics / Offroad components, even though they link the same
// source. See `docs/sable-core-port.md`, "Cross-plugin ownership".
//
// So the model is not shared, it is *asked*: this channel is the operation
// surface. Sable keeps ownership (it creates, ticks and closes the containers)
// and the other components send operations here, over the host's plugin IPC
// (`IpcChannel`, addressed by the plugin name `sable`). Only data crosses the
// boundary — ids, positions, bounds — never objects.
//
// The handler is synchronous by construction (`IpcChannel.handle`), so an
// operation runs to completion inside Sable's component before the reply is
// sent. The *caller* awaits the reply, which is why `assemble` is only safe from
// an entry point that can await (`simulated:assemble` is dispatched from an
// async payload handler); a block-entity tick has to queue its request.
//
// Host: this file uses `pumpkin_api` (IPC + commands only).
// create's positions are not exported from its public barrel yet.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/common/pos.dart' show Pos;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../sublevel/api/command/sable_command_helper.dart' show SableCommandError;
import '../sublevel/api/command/sub_level_selector.dart';
import '../sublevel/api/physics_constraint.dart';
import '../sublevel/api/sub_level_assembly_helper.dart';
import '../sublevel/api/sub_level_raycast.dart';
import '../sublevel/math/bounding_box.dart';
import '../sublevel/math/vector.dart' show Vector3d;
import '../sublevel/model/server_sub_level.dart';
import '../sublevel/model/server_sub_level_container.dart';
import '../sublevel/model/sub_level_container.dart';
import '../sublevel/physics/floating_block_material.dart';
import '../sublevel/physics/physics_block_properties.dart';
import '../sublevel/system/physics_system.dart' show SubLevelPhysicsSystem;

/// The IPC channel every sub-level operation travels on.
///
/// The envelope is `{"type": "sable.sublevels", "data": {"op": ...}}` (see
/// `IpcChannel`); `op` is one of [SableSubLevelOps].
const IpcChannel<Map<String, Object?>> sableSubLevelChannel = IpcChannel<
  Map<String, Object?>
>(
  sableSubLevelChannelName,
  _encodeMessage,
  _decodeMessage,
);

/// The channel name (`IpcChannel` requires one per message type).
const String sableSubLevelChannelName = 'sable.sublevels';

/// The plugin name other components address the operations to.
const String sablePluginName = 'sable';

Object? _encodeMessage(Map<String, Object?> message) => message;

Map<String, Object?> _decodeMessage(Object? json) =>
    json is Map ? {for (final entry in json.entries) '${entry.key}': entry.value} : const {};

/// The operations of [sableSubLevelChannel].
abstract final class SableSubLevelOps {
  /// `{"op": "list", "world": ...}`: every sub-level of the level.
  static const String list = 'list';

  /// `{"op": "get", "world": ..., "id": ...}`: one sub-level, or `null`.
  static const String get = 'get';

  /// `{"op": "containing", "world": ..., "pos": [x, y, z]}`: the sub-level whose
  /// plot contains a block position, or `null`.
  static const String containing = 'containing';

  /// `{"op": "areaLoaded", "world": ..., "center": [x, y, z], "range": n}`.
  static const String areaLoaded = 'areaLoaded';

  /// `{"op": "assemble", "world": ..., "anchor": [x,y,z], "blocks": [...],
  /// "bounds": [minX,minY,minZ,maxX,maxY,maxZ]}`.
  static const String assemble = 'assemble';

  /// `{"op": "resolve", "world": ..., "selector": "@n", "source": [x, y, z],
  /// "rotation": [yaw, pitch] | absent}`: the sub-levels a `SubLevelArgumentType`
  /// selector names, resolved against this component's container.
  ///
  /// The selector grammar is Sable's own (`@e`, `@n`, `@r`, `@v`, `@l`, `@t`,
  /// `@i`, modifiers, a UUID, `static_world`), so the parse and the resolution
  /// both stay in the component that holds the sub-levels; a caller only sends
  /// the text and the source it would have resolved from.
  static const String resolve = 'resolve';

  /// `{"op": "lock", "world": ..., "ids": [...], "locked": true | false |
  /// absent}`: lock or unlock sub-levels.
  ///
  /// `locked` absent toggles every named sub-level; with it, only the ones whose
  /// state differs are flipped. The reply is `{"updated": n, "locked": [ids]}`,
  /// `n` counting the flips (`SimCommand.lockSubLevels`'s own count) and
  /// `locked` listing every sub-level this component currently holds a lock on.
  static const String lock = 'lock';

  /// `{"op": "subscribe"}`: push `changed` messages to the sender from now on.
  static const String subscribe = 'subscribe';

  /// `{"op": "physicsData", "materials": {ID: {...}}, "properties": [...]}`:
  /// the `floating_materials/**` and `physics_block_properties/**` JSON of the
  /// sending component.
  ///
  /// Java reads one global property registry and one global material table, both
  /// filled from *every* enabled datapack by one reload listener, so a block of
  /// another mod floats in Sable's own sub-levels. The port's tables are per
  /// component and the model that ticks the sub-levels lives here, so the other
  /// component hands its entries over: a levitite structure assembled by the
  /// physics assembler is ticked in *this* component, and without the push this
  /// component has no `aeronautics:levitite` material and no
  /// `#aeronautics:levitite` → `sable:floating_material` definition, so its
  /// blocks lift nothing.
  ///
  /// The reply is `{"materials": n, "definitions": m}`.
  static const String physicsData = 'physicsData';

  /// The push: `{"op": "changed", "world": ..., "subLevels": [...]}`.
  static const String changed = 'changed';
}

/// The reply shape: `{"ok": true, ...}` or `{"ok": false, "error": "..."}`.
Map<String, Object?> _ok([Map<String, Object?> fields = const {}]) => {'ok': true, ...fields};

Map<String, Object?> _error(Object error) => {'ok': false, 'error': '$error'};

/// What the API needs from the plugin: the level containers, by dimension.
typedef SableLevelLookup = SubLevelContainer? Function(String world);

/// The sub-level operations of the Sable plugin.
final class SableSubLevelApi {
  SableSubLevelApi(this._containerOf, {required this.log});

  /// Resolves the world named by a request (dimension key or world id).
  final SableLevelLookup _containerOf;

  final Logger log;

  /// The components that asked for `changed` pushes.
  final Set<String> _subscribers = {};

  /// The locks this component holds, by dimension and sub-level id (each entry
  /// is one `addConstraint` on that dimension's pipeline).
  final Map<String, Map<String, PhysicsConstraintHandle>> _locks = {};

  /// Registers the handler. Call once, from `onLoad`.
  void install() {
    sableSubLevelChannel.handle(_handle);
  }

  /// Announces the current sub-levels of [level] to the subscribers.
  ///
  /// Called when a sub-level is added or removed, so a component that keeps a
  /// mirror (it needs synchronous answers, see the class comment) can refresh
  /// it without polling.
  void announce(SubLevelContainer container) {
    if (_subscribers.isEmpty) return;
    final message = _ok({
      'op': SableSubLevelOps.changed,
      'world': container.level.dimensionId,
      'subLevels': _describeAll(container),
    });
    for (final subscriber in _subscribers.toList()) {
      sableSubLevelChannel.send(subscriber, message).then(
        (_) {},
        // A component that unloaded cannot answer; stop pushing to it.
        onError: (Object _) {
          _subscribers.remove(subscriber);
        },
      );
    }
  }

  Object? _handle(String sender, Map<String, Object?> message) {
    final op = message['op'];
    if (op == SableSubLevelOps.subscribe) {
      _subscribers.add(sender);
      return _ok({'subscribed': true});
    }
    if (op == SableSubLevelOps.physicsData) return _physicsData(sender, message);

    final world = message['world'];
    if (world is! String) return _error('"world" must be a string');
    final resolved = _containerOf(world);
    if (resolved is! ServerSubLevelContainer) {
      return _error('No server sub-level container for $world (level not loaded)');
    }
    final container = resolved;

    try {
      return switch (op) {
        SableSubLevelOps.list => _ok({'subLevels': _describeAll(container)}),
        SableSubLevelOps.get => _ok({'subLevel': _describeOne(container, message['id'])}),
        SableSubLevelOps.containing =>
          _ok({'subLevel': _containing(container, message['pos'])}),
        SableSubLevelOps.areaLoaded => _ok({'loaded': _areaLoaded(container, message)}),
        SableSubLevelOps.assemble => _assemble(container, message),
        SableSubLevelOps.resolve => _resolve(container, message),
        SableSubLevelOps.lock => _lock(container, message),
        _ => _error('Unknown sub-level operation "$op"'),
      };
    } on Object catch (error) {
      log.warn('sable.sublevels "$op" from $sender failed: $error');
      return _error(error);
    }
  }

  // --------------------------------------------------------------- operations

  /// Applies the physics data another component sent
  /// ([SableSubLevelOps.physicsData]).
  ///
  /// The payload is the raw JSON of the sender's `floating_materials/**` and
  /// `physics_block_properties/**` entries, decoded here with the same
  /// converters this component uses for its own pack, so a pushed entry and a
  /// packed one cannot drift.
  ///
  /// A malformed entry is skipped with a warning rather than failing the whole
  /// operation: the sender's other entries are still worth having, and Java
  /// skips a file its codec rejects the same way.
  Map<String, Object?> _physicsData(String sender, Map<String, Object?> message) {
    var materials = 0;
    final rawMaterials = message['materials'];
    if (rawMaterials is Map) {
      for (final entry in rawMaterials.entries) {
        final json = entry.value;
        if (json is! Map) continue;
        try {
          FloatingBlockMaterialDataHandler.addMaterial(
            '${entry.key}',
            FloatingBlockMaterial.fromJson(json.cast<Object?, Object?>()),
          );
          materials++;
        } on Object catch (error) {
          log.warn('sable.sublevels physicsData from $sender: skipping material ${entry.key}: $error');
        }
      }
    }

    final definitions = <PhysicsBlockPropertiesDefinition>[];
    final rawProperties = message['properties'];
    if (rawProperties is List) {
      for (final json in rawProperties) {
        if (json is! Map) continue;
        try {
          final definition = PhysicsBlockPropertiesDefinition.tryFromJson(
            json.cast<Object?, Object?>(),
          );
          if (definition != null) definitions.add(definition);
        } on Object catch (error) {
          log.warn('sable.sublevels physicsData from $sender: skipping a definition: $error');
        }
      }
    }
    PhysicsBlockPropertyHelper.addDefinitions(definitions);

    log.info(
      'Sable: $materials floating material${materials == 1 ? '' : 's'} and '
      '${definitions.length} physics block propert${definitions.length == 1 ? 'y' : 'ies'} '
      'from $sender.',
    );
    return _ok({'materials': materials, 'definitions': definitions.length});
  }

  Map<String, Object?> _assemble(ServerSubLevelContainer container, Map<String, Object?> message) {
    final anchor = _posOf(message['anchor']);
    final bounds = _boundsOf(message['bounds']);
    final blocks = message['blocks'];
    if (anchor == null || bounds == null || blocks is! List) {
      return _error('"anchor", "bounds" and "blocks" are required');
    }

    final positions = <Pos>[];
    for (final entry in blocks) {
      final pos = _posOf(entry);
      if (pos == null) return _error('bad block position "$entry"');
      positions.add(pos);
    }

    final subLevel = SubLevelAssemblyHelper.assembleBlocks(
      container.level,
      anchor,
      positions,
      bounds,
    );
    return _ok({
      'subLevel': _describeOne(container, subLevel.uniqueIdOrNull),
      'assembledBlocks': positions.length,
    });
  }

  Map<String, Object?>? _containing(ServerSubLevelContainer container, Object? rawPos) {
    final pos = _posOf(rawPos);
    if (pos == null) return null;
    final plot = container.getPlot(pos.$1 >> 4, pos.$3 >> 4);
    final subLevel = plot?.getSubLevel();
    if (subLevel is! ServerSubLevel) return null;
    return _describeOne(container, subLevel.uniqueIdOrNull);
  }

  bool _areaLoaded(ServerSubLevelContainer container, Map<String, Object?> message) {
    final center = _posOf(message['center']);
    final range = message['range'];
    if (center == null || range is! num) return false;

    final level = container.level;
    final r = range.toInt();
    if (center.$2 + r < level.minY || center.$2 - r >= level.maxY) return false;

    final host = container.chunkHost;
    for (var chunkX = (center.$1 - r) >> 4; chunkX <= (center.$1 + r) >> 4; chunkX++) {
      for (var chunkZ = (center.$3 - r) >> 4; chunkZ <= (center.$3 + r) >> 4; chunkZ++) {
        if (host.getLoadedChunk(chunkX, chunkZ) == null) return false;
      }
    }
    return true;
  }

  // ---------------------------------------------------------------- describing

  List<Map<String, Object?>> _describeAll(SubLevelContainer container) => [
    for (final subLevel in container.getAllSubLevels())
      if (subLevel is ServerSubLevel) _describe(subLevel),
  ];

  Map<String, Object?>? _describeOne(SubLevelContainer container, Object? id) {
    if (id is! String) return null;
    final subLevel = container.getSubLevelById(id);
    if (subLevel is! ServerSubLevel) return null;
    return _describe(subLevel);
  }

  /// The data a caller can act on: identity, pose, bounds and mass.
  ///
  /// Deliberately no object graph: the receiving component can only use these
  /// values, never the sub-level itself.
  Map<String, Object?> _describe(ServerSubLevel subLevel) {
    final pose = subLevel.logicalPose;
    final position = pose.position();
    final orientation = pose.orientation();
    final bounds = subLevel.boundingBox;
    final tracker = subLevel.massTracker;
    final mass = tracker == null || tracker.isInvalid() ? null : tracker.getMass();
    final plot = subLevel.getPlot();
    final center = plot.getCenterBlock();

    return {
      'id': subLevel.uniqueIdOrNull,
      'removed': subLevel.isRemoved(),
      'position': [position.x, position.y, position.z],
      'orientation': [orientation.x, orientation.y, orientation.z, orientation.w],
      'bounds': [bounds.minX, bounds.minY, bounds.minZ, bounds.maxX, bounds.maxY, bounds.maxZ],
      'mass': mass,
      'plot': [plot.plotPos.$1, plot.plotPos.$2],
      // The plot's centre block, which is what `assembleBlocks` measures its
      // offset from (`SimAssemblyResult.offset`).
      'centerBlock': [center.$1, center.$2, center.$3],
    };
  }

  // ---------------------------------------------------------------- new operations

  /// Resolves a selector text against [container] (`SableSubLevelOps.resolve`).
  ///
  /// `SubLevelArgumentType.subLevels` parses anything Java's argument would
  /// take (a UUID, `static_world`, an `@`-selector with modifiers). The result
  /// carries the matched ids in the container's current order.
  Map<String, Object?> _resolve(ServerSubLevelContainer container, Map<String, Object?> message) {
    final selector = message['selector'];
    if (selector is! String) return _error('"selector" must be a string');
    final source = _double3Of(message['source']) ?? (0.0, 0.0, 0.0);
    final look = _double2Of(message['rotation']);

    final parser = SubLevelArgumentType.subLevels;
    late final SubLevelTarget target;
    try {
      target = parser.parse(selector);
    } on SubLevelSelectorException catch (error) {
      return _error(error.error.message);
    }
    if (target is SubLevelTargetNone) return _ok({'ids': const <String>[]});

    final sourcePosition = Vector3d(source.$1, source.$2, source.$3);
    final containing = _containingOf(container, sourcePosition.x, sourcePosition.y, sourcePosition.z);
    ServerSubLevel? viewed;
    if (look != null && containing != null) {
      final hit = SubLevelRaycast.pick(
        container,
        Vector3d(
          sourcePosition.x,
          // `Player.getEyeHeight` for a standing player (`command_support.dart`).
          sourcePosition.y + 1.62,
          sourcePosition.z,
        ),
        SubLevelRaycast.lookVector(look.$1, look.$2),
        // `Entity.pick`'s reach (`command_support.dart`: 100 blocks).
        100.0,
      );
      final hitSubLevel = hit?.subLevel;
      viewed = hitSubLevel is ServerSubLevel ? hitSubLevel : null;
    }
    final context = SubLevelTargetContext(
      container: container,
      sourcePosition: sourcePosition,
      random: math.Random(),
      trackingSubLevel: containing,
      viewedSubLevel: viewed,
      containingSubLevel: containing,
    );
    late final List<ServerSubLevel> selected;
    try {
      selected = target.getSubLevels(context).whereType<ServerSubLevel>().toList();
    } on SubLevelSelectorException catch (error) {
      return _error(error.error.message);
    }
    return _ok({
      'ids': [for (final subLevel in selected) if (subLevel.uniqueIdOrNull != null) subLevel.uniqueIdOrNull!],
    });
  }

  /// `{"op": "lock"}`: toggles the physics-staff locks of [container]'s
  /// sub-levels (`PhysicsStaffServerHandler.toggleLock` + `isLocked`, by id).
  ///
  /// The lock itself is Java's: a `FixedConstraintConfiguration` welding the
  /// sub-level to the static world at its own pose, added to the pipeline
  /// (`PhysicsStaffServerHandler.addConstraint`). Only the *authority* differs:
  /// Java keeps the lock map in Simulated's per-level saved data and the
  /// constraint handles beside it, but a handle is a Dart object that cannot
  /// cross into this component, so the handles live here — in the component
  /// that owns the pipeline — and the set of locked ids is persisted by the
  /// caller that asked for the lock.
  ///
  /// Java's two quirks are kept: the count is the number of *flips*, not of
  /// locks, and a sub-level that cannot be resolved at all still counts (Java's
  /// `toggleLock` returns early on a `null` sub-level while the command's loop
  /// has already incremented).
  Map<String, Object?> _lock(ServerSubLevelContainer container, Map<String, Object?> message) {
    final ids = message['ids'];
    if (ids is! List) return _error('"ids" must be a list of sub-level ids');
    final wanted = message['locked'];
    if (wanted != null && wanted is! bool) return _error('"locked" must be a boolean');

    final locks = _locksOf(container.level.dimensionId);
    _pruneDeadLocks(locks);

    final subLevels = <ServerSubLevel>[];
    var updated = 0;
    for (final entry in ids) {
      if (entry is! String) return _error('"ids" must be a list of sub-level ids');
      final subLevel = container.getSubLevelById(entry);
      if (subLevel is! ServerSubLevel) {
        // Java counts the flip even though its `toggleLock` does nothing.
        updated++;
        continue;
      }
      subLevels.add(subLevel);
    }

    final pipeline = _constraintPipeline(container);
    if (subLevels.isNotEmpty && pipeline == null) {
      return _error(SableCommandError.constraintsUnsupported.message);
    }
    for (final subLevel in subLevels) {
      final id = subLevel.uniqueIdOrNull;
      if (id == null) continue;
      final locked = locks.containsKey(id);
      final bool shouldLock = switch (wanted) {
        final bool explicit => explicit,
        _ => !locked,
      };
      if (shouldLock == locked) continue;
      if (shouldLock) {
        locks[id] = _addLock(pipeline!, subLevel);
      } else {
        locks.remove(id)?.remove();
      }
      updated++;
    }

    return _ok({
      'updated': updated,
      // Java's `sendLocksToClients` payload is the live set; a dead handle is
      // not a lock (`isLocked` requires a valid one), so it is not reported.
      'locked': [for (final lock in locks.entries) if (lock.value.isValid) lock.key],
    });
  }

  /// The locks of [dimension], by sub-level id. Java keys the same map by UUID
  /// in `PhysicsStaffServerHandler`.
  Map<String, PhysicsConstraintHandle> _locksOf(String dimension) =>
      _locks.putIfAbsent(dimension, () => <String, PhysicsConstraintHandle>{});

  /// Drops the locks whose handle the engine no longer holds (`isValid` false:
  /// a sub-level that was removed, or a pipeline that was disposed with its
  /// level). Java reaches the same set through `applyLockIfNeeded`, which
  /// re-creates a handle as soon as the sub-level is back; here the caller that
  /// asked for the lock re-applies it with `"locked": true`.
  static void _pruneDeadLocks(Map<String, PhysicsConstraintHandle> locks) =>
      locks.removeWhere((_, handle) => !handle.isValid);

  /// `PhysicsStaffServerHandler.addConstraint`: a fixed joint between the world
  /// and [subLevel], at the sub-level's own pose.
  static PhysicsConstraintHandle _addLock(ConstraintPipeline pipeline, ServerSubLevel subLevel) {
    final pose = subLevel.logicalPose;
    return pipeline.addConstraint(
      null,
      subLevel,
      FixedConstraintConfiguration(pose.position(), pose.rotationPoint(), pose.orientation()),
    );
  }

  /// The constraint-capable pipeline of [container], or `null`.
  static ConstraintPipeline? _constraintPipeline(ServerSubLevelContainer container) {
    final system = container.physics;
    if (system is! SubLevelPhysicsSystem) return null;
    final pipeline = system.getPipeline();
    return pipeline is ConstraintPipeline ? pipeline as ConstraintPipeline : null;
  }

  // ------------------------------------------------------------------- parsing

  /// The sub-level whose plot holds the block ([x], [y], [z]), or `null`.
  static ServerSubLevel? _containingOf(ServerSubLevelContainer container, double x, double y, double z) {
    final plot = container.getPlot(x.floor(), z.floor());
    final subLevel = plot?.getSubLevel();
    return subLevel is ServerSubLevel ? subLevel : null;
  }

  /// A three-double tuple (`source`), or `null`.
  static (double, double, double)? _double3Of(Object? value) {
    if (value is! List || value.length != 3) return null;
    final values = [for (final entry in value) _doubleOf(entry)];
    if (values.any((v) => v == null)) return null;
    return (values[0]!, values[1]!, values[2]!);
  }

  /// A two-double tuple (`rotation`), or `null`.
  static (double, double)? _double2Of(Object? value) {
    if (value is! List || value.length != 2) return null;
    final a = _doubleOf(value[0]);
    final b = _doubleOf(value[1]);
    if (a == null || b == null) return null;
    return (a, b);
  }

  static double? _doubleOf(Object? value) => switch (value) {
    final num v => v.toDouble(),
    _ => null,
  };

  static Pos? _posOf(Object? value) {
    if (value is! List || value.length != 3) return null;
    final x = _intOf(value[0]);
    final y = _intOf(value[1]);
    final z = _intOf(value[2]);
    if (x == null || y == null || z == null) return null;
    return (x, y, z);
  }

  static BoundingBox3i? _boundsOf(Object? value) {
    if (value is! List || value.length != 6) return null;
    final values = [for (final entry in value) _intOf(entry)];
    if (values.any((v) => v == null)) return null;
    return BoundingBox3i.values(
      values[0]!,
      values[1]!,
      values[2]!,
      values[3]!,
      values[4]!,
      values[5]!,
    );
  }

  static int? _intOf(Object? value) => switch (value) {
    final int v => v,
    final double v when v == v.roundToDouble() => v.toInt(),
    _ => null,
  };
}
